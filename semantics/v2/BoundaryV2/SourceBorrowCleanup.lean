import BoundaryV2.SourceBorrowEffects

namespace BoundaryV2.Profile.Source.Machine
namespace BorrowRegistry

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

private theorem require_ok (condition : Bool) (reason : Invalid) (result : Unit)
    (accepted : require condition reason = .ok result) : condition = true := by
  unfold require at accepted
  split at accepted <;> first | assumption | contradiction

theorem begin_resource (before after : Cleanup.Obligation .source) (invocation : InvocationId)
    (events : List Cleanup.Event) (accepted : Cleanup.begin before invocation = some (after, events)) :
    after.resource = before.resource := by
  unfold Cleanup.begin at accepted
  split at accepted <;> try contradiction
  cases accepted
  rfl

theorem complete_resource (before after : Cleanup.Obligation .source) (invocation : InvocationId)
    (result : Except SemanticValue Unit) (events : List Cleanup.Event)
    (accepted : Cleanup.complete before invocation result = some (after, events)) : after.resource = before.resource := by
  unfold Cleanup.complete at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases result with
  | ok value => cases value; cases accepted; rfl
  | error value => cases accepted; rfl

theorem replace_obligation_valid (heap : Heap) (index : Nat) (before after : Cleanup.Obligation .source)
    (found : heap.obligations[index]? = some before) (same : after.resource = before.resource) (valid : Valid heap) :
    Valid {heap with obligations := heap.obligations.set index after} :=
  same_objects_valid _ _ valid (replace_obligation_tables _ _ _ _ found same) rfl

theorem beginCleanup_valid (machine : State) (context : Context) (id : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (accepted : beginCleanup machine context id exit normal tail = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  simp only [beginCleanup, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨original, originalAt, _, _, ⟨record, events⟩, begun, _, _, _, _, _, _, result, applied, rfl⟩ := accepted
  have next := replace_obligation_valid _ _ _ _ originalAt (begin_resource _ _ _ _ begun) valid
  exact applyClosure_valid _ _ _ _ result applied next

theorem finishCleanup_valid (machine : State) (context : Context) (after : Transition)
    (accepted : finishCleanup machine context = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  unfold finishCleanup at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, original, originalAt, ⟨record, events⟩, completed, released, _, rfl⟩ := accepted
  exact replace_obligation_valid _ _ _ _ originalAt (complete_resource _ _ _ _ _ completed) valid

theorem cleanupFailed_valid (machine : State) (id : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : cleanupFailed machine id invocation outer normal tail inner = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  unfold cleanupFailed at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨original, originalAt, ⟨record, events⟩, completed, rfl⟩ := accepted
  exact replace_obligation_valid _ _ _ _ originalAt (complete_resource _ _ _ _ _ completed) valid

theorem cleanupAbandoned_valid (machine : State) (id : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : cleanupAbandoned machine id invocation outer normal tail inner = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  simp only [cleanupAbandoned, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, original, originalAt, ⟨record, events⟩, completed, rfl⟩ := accepted
  exact replace_obligation_valid _ _ _ _ originalAt (complete_resource _ _ _ _ _ completed) valid

theorem finishCleanupUnwind_valid (machine : State) (id : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : finishCleanupUnwind machine id invocation outer normal tail inner = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  unfold finishCleanupUnwind at accepted
  split at accepted <;> first
    | exact cleanupFailed_valid _ _ _ _ _ _ _ _ accepted valid
    | exact cleanupAbandoned_valid _ _ _ _ _ _ _ _ accepted valid
    | contradiction

theorem unwindStep_valid (machine : State) (context : Context) (after : Transition)
    (original : Cleanup.Exit .source) (unwinding : machine.control = .unwind original)
    (accepted : unwindStep machine context = .ok after) (valid : Valid machine.heap)
    : Valid after.state.heap := by
  simp only [unwindStep, unwinding, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨scope, _, accepted⟩ := accepted
  cases stacked : machine.stack with
  | nil =>
    simp only [stacked] at accepted
    split at accepted
    · cases accepted
      exact valid
    · split at accepted <;> try contradiction
      all_goals cases accepted
      all_goals exact valid
  | cons saved tail =>
    cases saved <;> simp only [stacked] at accepted
    case invocation invocation parent =>
      split at accepted
      · cases accepted
        exact valid
      · cases accepted
        exact valid
    case lexical identity =>
      split at accepted
      · cases accepted
        exact valid
      · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨_, _, parent, _, rfl⟩ := accepted
        exact valid
    case restore invocation parent =>
      cases accepted
      exact valid
    case binding binder body bindings parent =>
      cases accepted
      exact valid
    case operands intent bindings remaining evaluated =>
      cases accepted
      exact valid
    case handler active =>
      cases accepted
      exact valid
    case region region =>
      cases accepted
      exact valid
    case injection values =>
      cases accepted
      exact valid
    case protection identity =>
      exact beginCleanup_valid _ _ _ _ _ _ _ accepted valid
    case cleanupReturn identity invocation outer normal =>
      exact finishCleanupUnwind_valid _ _ _ _ _ _ _ _ accepted valid
    case releaseReturn scope afterRelease =>
      cases accepted
      exact valid
    case disposalReturn remaining afterRelease invocation parent =>
      cases primaryIs : (observedExit machine original).primary <;> simp only [primaryIs] at accepted
      all_goals cases afterRelease <;> simp only [pure, Except.pure, Except.bind] at accepted
      all_goals cases accepted
      all_goals exact valid



theorem executeCleanupTerm_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executeCleanupTerm machine context = .ok after) (valid : Valid machine.heap) (bounded : IdentitySupport.Valid machine) : Valid after.state.heap := by
  unfold executeCleanupTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact installProtection_valid _ _ _ _ _ _ _ _ accepted valid bounded
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, unitIndex, _, ⟨middle, owner⟩, reserved, rfl⟩ := accepted
    have next := temporary_valid _ _ _ reserved valid
    exact next

end BorrowRegistry
end BoundaryV2.Profile.Source.Machine
