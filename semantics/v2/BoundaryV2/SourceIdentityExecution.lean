import BoundaryV2.SourceIdentityTransitions
import BoundaryV2.SourceIndexLaws

namespace BoundaryV2.Profile.Source.Machine
namespace IdentitySupport

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

theorem tickRunning_valid (machine : State) (context : Context) (after : Transition)
    (bounded : ValidAt limit machine) (upper : Upper limit after.state.heap)
    (accepted : tickRunning machine context = .ok after) : ValidAt limit after.state := by
  cases executing : machine.control <;> simp only [tickRunning, executing] at accepted
  case term => exact enterTerm_valid _ _ _ bounded accepted
  case expression => exact enterExpression_valid _ _ _ bounded accepted
  case invoke => exact enterInvocation_valid _ _ _ bounded upper accepted
  case release => exact releaseScope_valid _ _ bounded accepted
  case discard => exact discardValues_valid _ _ _ bounded accepted
  case unwind => exact unwindStep_valid _ _ _ bounded upper accepted
  case execute intent bindings operands =>
    cases intent with
    | primitive => exact executePrimitive_valid _ _ _ bounded upper accepted
    | term term =>
      cases term <;> first
        | exact executeEffectTerm_valid _ _ _ bounded upper accepted
        | exact executeCleanupTerm_valid _ _ _ bounded upper accepted
        | exact executeControlTerm_valid _ _ _ bounded upper accepted
  case delivered value =>
    cases stacked : machine.stack with
    | nil =>
      simp only [stacked, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
      exact ⟨bounded.heap, (by simpa only [stacked] using bounded.frames), trivial, bounded.scope, bounded.invocation⟩
    | cons saved tail =>
      have frameBound := bounded.frames saved (by simp [stacked])
      have tailBound : ∀ frame ∈ tail, FrameValid limit frame :=
        fun frame member => bounded.frames frame (by simp [stacked, member])
      cases saved <;> simp only [stacked] at accepted
      all_goals first
        | exact enterBinding_valid _ _ _ bounded upper accepted
        | exact deliverOperand_valid _ _ bounded accepted
        | exact leaveInvocation_valid _ _ bounded accepted
        | exact leaveLexical_valid _ _ bounded accepted
        | exact restoreResumeCaller_valid _ _ bounded accepted
        | exact completeHandler_valid _ _ _ bounded accepted
        | exact finishCleanup_valid _ _ _ bounded accepted
        | (cases accepted; exact ⟨bounded.heap, tailBound, trivial, bounded.scope, bounded.invocation⟩)
        | skip
      case protection => exact beginCleanup_valid _ _ _ _ _ _ _ bounded tailBound upper accepted
      case disposalReturn => contradiction
      case releaseReturn =>
        cases accepted
        exact ⟨bounded.heap, tailBound, frameBound, bounded.scope, bounded.invocation⟩

theorem tick_valid (machine : State) (context : Context) (after : Transition)
    (bounded : ValidAt limit machine) (upper : Upper limit after.state.heap)
    (accepted : tick machine context = .ok after) : ValidAt limit after.state := by
  cases phase : machine.status <;> simp only [tick, phase] at accepted
  · exact tickRunning_valid _ _ _ bounded upper accepted
  all_goals cases accepted; exact bounded

theorem cancelControl_valid {control : Control} (bounded : ControlValid limit control) :
    ControlValid limit (cancelControl control reason) := by
  cases control with
  | release scope after => cases after <;> exact bounded
  | discard values after => cases after <;> trivial
  | term | expression | execute | delivered | invoke | unwind => trivial

theorem external_valid (machine : State) (context : Context) (action : External) (after : Transition)
    (bounded : ValidAt limit machine)
    (accepted : external machine context action = .ok after) : ValidAt limit after.state := by
  have active : ValidAt limit {machine with status := .running} :=
    ⟨bounded.heap, bounded.frames, bounded.control, bounded.scope, bounded.invocation⟩
  have scopedBound (value : SemanticValue) (result : Transition)
      (resumed : scopedValue {machine with status := .running} value = .ok result) : ValidAt limit result.state :=
    scopedValue_valid active resumed
  have cancelled (reason : Protocol.Reason) : ControlValid limit (cancelControl machine.control reason) :=
    cancelControl_valid bounded.control
  cases action <;> cases phase : machine.status <;>
    simp only [external, phase, bind, pure, Except.pure, Except.bind] at accepted <;> try contradiction
  all_goals constructor <;> grind (gen := 32) only [except_bind_ok, ← ValidAt.mk, cases ValidAt]

theorem step_valid_at (step : Step context before events after) (bounded : ValidAt limit before)
    (upper : Upper limit after.heap) : ValidAt limit after := by
  cases step with
  | internal accepted => exact tick_valid _ _ _ bounded upper accepted
  | external accepted => exact external_valid _ _ _ _ bounded accepted

/-- Each actual source step preserves all retained metadata identity bounds.
The numeric upper bound used inside allocation proofs is the successor's own
allocation supply; no well-formedness of that successor is assumed. -/
theorem step_valid (step : Step context before events after) (bounded : Valid before) : Valid after := by
  exact step_valid_at step (valid_mono (limits_monotone (step_allocation step).heap) bounded)
    (fun _ => Nat.le_refl _)

theorem steps_valid (steps : Steps context before events after) (bounded : Valid before) : Valid after := by
  induction steps with
  | refl => exact bounded
  | cons step _ induction => exact induction (step_valid step bounded)

/-- All initialized source executions keep attachment, region, cell, lexical
scope, invocation, and cleanup-obligation identities within their allocated
supplies, including metadata inside dormant captured continuations. -/
theorem initialized_execution_preserves_identity_bounds (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : Valid after :=
  steps_valid steps (initial_valid _ _ _ initialized)

private theorem identity_eq {left right : Ref space domain} (same : left.value = right.value) : left = right := by
  cases left
  cases right
  simpa only [Ref.mk.injEq] using same

theorem scope_record_exists (indexed : heap.Indexed) (identity : LexicalScopeId)
    (bounded : Bound (limits heap) identity) :
    ∃ record, heap.scopes[identity.value]? = some record ∧ record.id = identity := by
  have inside : identity.value < heap.scopes.length := by
    simpa only [Bound, limits, indexed.supplies.1] using bounded
  have found : heap.scopes[identity.value]? = some heap.scopes[identity.value] := by simp [inside]
  refine ⟨_, found, ?_⟩
  exact identity_eq (indexed.scope_identity found)

theorem invocation_record_exists (indexed : heap.Indexed) (identity : InvocationId)
    (bounded : Bound (limits heap) identity) :
    ∃ record, heap.invocations[identity.value]? = some record ∧ record.id = identity := by
  have inside : identity.value < heap.invocations.length := by
    simpa only [Bound, limits, indexed.supplies.2.1] using bounded
  have found : heap.invocations[identity.value]? = some heap.invocations[identity.value] := by simp [inside]
  refine ⟨_, found, ?_⟩
  exact identity_eq (indexed.invocation_identity found)

theorem obligation_record_exists (indexed : heap.Indexed) (identity : ObligationId)
    (bounded : Bound (limits heap) identity) :
    ∃ record, heap.obligations[identity.value]? = some record ∧ record.id = identity := by
  have inside : identity.value < heap.obligations.length := by
    simpa only [Bound, limits, indexed.supplies.2.2] using bounded
  have found : heap.obligations[identity.value]? = some heap.obligations[identity.value] := by simp [inside]
  refine ⟨_, found, ?_⟩
  exact identity_eq (indexed.obligation_identity found)

/-- Every reachable current scope and invocation has its actual indexed record.
The same lookup lemmas apply to the bounded metadata in frames, captures, stored
objects, and cleanup obligations. -/
theorem initialized_execution_has_current_records (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) :
    (∃ record, after.heap.scopes[after.scope.value]? = some record ∧ record.id = after.scope) ∧
    (∃ record, after.heap.invocations[after.invocation.value]? = some record ∧ record.id = after.invocation) := by
  have bounded := initialized_execution_preserves_identity_bounds _ _ _ _ _ initialized steps
  have indexed := source_trajectory_indices _ _ _ _ initialized steps
  exact ⟨scope_record_exists indexed _ bounded.scope, invocation_record_exists indexed _ bounded.invocation⟩

end IdentitySupport
end BoundaryV2.Profile.Source.Machine
