import BoundaryV2.SourceCustodyEffects

namespace BoundaryV2.Profile.Source.Machine
namespace CustodyCoverage

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

private theorem flatMap_set_same (values : List α) (index : Nat) (replacement original : α)
    (f : α → List β) (found : values[index]? = some original) (same : f replacement = f original) :
    (values.set index replacement).flatMap f = values.flatMap f := by
  induction values generalizing index with
  | nil => simp at found
  | cons value values induction =>
    cases index with
    | zero => cases found; simp [same]
    | succ index => simpa only [List.set_cons_succ, List.flatMap_cons] using congrArg (f value ++ ·) (induction index found)

theorem append_obligation_covered (machine : State) (record : Cleanup.Obligation .source)
    (covered : Covered machine.heap.custody (fields machine ++ OwningFields.obligation record)) :
    Valid {machine with heap := {machine.heap with obligations := machine.heap.obligations ++ [record]}} := by
  apply Covered.mono _ _ _ covered
  intro field member
  simp only [fields, OwningFields.heap, QueueCustody.fields_components, QueueCustody.heapFields,
    List.flatMap_append, List.flatMap_singleton, List.mem_append] at member ⊢
  grind only []

theorem installProtection_valid (machine : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (accepted : installProtection machine context body cleanup arguments resource loan = .ok after) (valid : Valid machine)
    (empty : QueueCustody.controlFields machine.control = [])
    (contracts : ClosureContracts.Valid context machine.heap.objects) : Valid after.state := by
  simp only [installProtection, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, store, moved, accepted⟩ := accepted
  let identity : ObligationId := ⟨machine.heap.nextObligation⟩
  let record : Cleanup.Obligation .source := ⟨identity, machine.scope, identity.value,
    cleanup.value, resource.map Located.value, .pending⟩
  let kept := {store with obligations := store.obligations ++ [record], nextObligation := store.nextObligation + 1}
  have movedCover := moveValues_covered _ _ _ _ _ moved valid
  rw [← move_fields _ _ _ _ moved] at movedCover
  have storedCover := append_obligation_covered {machine with heap := store} record (by
    cases resource <;> simpa only [record, identity, OwningFields.obligation, Option.map_none, Option.map_some,
      Option.toList_none, Option.toList_some, List.map_nil, List.map_cons, List.mapIdx_cons, List.mapIdx_nil,
      retainAt] using movedCover)
  have next : Valid {machine with heap := kept} := storedCover
  have movedTyped := ClosureContracts.move_valid context machine.heap store _ _ moved contracts
  have typed : ClosureContracts.Valid context kept.objects := movedTyped
  cases resource with
  | none =>
    cases loan <;> try contradiction
    simp only [pure, Except.pure, Except.bind] at accepted
    exact applyClosure_valid _ _ _ _ _ accepted next empty typed
  | some value =>
    cases loan with
    | none => contradiction
    | some descriptor =>
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, ⟨afterStore, borrowed⟩, allocated, _, rfl, applied⟩ := accepted
      let seedHeap : Heap := {kept with nextRegion := kept.nextRegion + 1, loans := kept.loans ++ [(⟨kept.nextRegion⟩, identity)]}
      have seed : Valid {machine with heap := seedHeap} := next
      have created := allocate_nonowning_valid _ _ _ _ _ _ allocated seed
      have createdTyped := ClosureContracts.allocate_valid context _ _ _ _ _ _ _ allocated typed trivial
      exact applyClosure_valid _ _ _ _ _ applied created empty createdTyped

theorem begin_obligation_fields (before after : Cleanup.Obligation .source) (invocation : InvocationId)
    (events : List Cleanup.Event) (accepted : Cleanup.begin before invocation = some (after, events)) :
    OwningFields.obligation after = OwningFields.obligation before := by
  unfold Cleanup.begin at accepted
  split at accepted <;> try contradiction
  cases accepted
  rfl

theorem complete_obligation_fields (before after : Cleanup.Obligation .source) (invocation : InvocationId)
    (result : Except SemanticValue Unit) (events : List Cleanup.Event)
    (accepted : Cleanup.complete before invocation result = some (after, events)) :
    OwningFields.obligation after = OwningFields.obligation before := by
  unfold Cleanup.complete at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases result with
  | ok value => cases value; cases accepted; rfl
  | error value => cases accepted; rfl

theorem replace_obligation_valid (machine : State) (index : Nat) (before after : Cleanup.Obligation .source)
    (found : machine.heap.obligations[index]? = some before)
    (same : OwningFields.obligation after = OwningFields.obligation before) (valid : Valid machine) :
    Valid {machine with heap := {machine.heap with obligations := machine.heap.obligations.set index after}} := by
  have retained := flatMap_set_same machine.heap.obligations index after before OwningFields.obligation found same
  simpa only [Valid, fields, OwningFields.heap, retained, QueueCustody.fields_components, QueueCustody.heapFields] using valid

theorem beginCleanup_valid (machine : State) (context : Context) (id : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (accepted : beginCleanup machine context id exit normal tail = .ok after) (valid : Valid machine)
    (same : tail.flatMap QueueCustody.frameFields = machine.stack.flatMap QueueCustody.frameFields)
    (empty : QueueCustody.controlFields machine.control = [])
    (contracts : ClosureContracts.Valid context machine.heap.objects) : Valid after.state := by
  simp only [beginCleanup, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨original, originalAt, _, _, ⟨record, events⟩, begun, _, _, _, _, _, _, result, applied, rfl⟩ := accepted
  have tailValid := stack_fields_valid machine tail valid same
  have stored := replace_obligation_valid {machine with stack := tail} id.value original record originalAt
    (begin_obligation_fields _ _ _ _ begun) tailValid
  exact applyClosure_valid _ _ _ _ result applied stored empty contracts

theorem resumeRelease_valid (machine : State) (after : AfterRelease) (valid : Valid machine)
    (empty : QueueCustody.controlFields machine.control = []) : Valid (resumeRelease machine after).state := by
  cases after <;> exact control_valid _ _ valid empty

theorem finishCleanup_valid (machine : State) (context : Context) (after : Transition)
    (accepted : finishCleanup machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold finishCleanup at accepted
  split at accepted <;> try contradiction
  rename_i value executing
  split at accepted <;> try contradiction
  rename_i id invocation exit normal tail stacked
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, original, originalAt, ⟨record, events⟩, completed, released, _, rfl⟩ := accepted
  have next := stack_fields_valid machine tail valid (by simp [stacked, QueueCustody.frameFields, DisposalShape.frame])
  have stored := replace_obligation_valid {machine with stack := tail} id.value original record originalAt
    (complete_obligation_fields _ _ _ _ _ completed) next
  exact resumeRelease_valid _ _ stored (by rw [executing]; rfl)

theorem cleanupFailed_valid (machine : State) (id : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : cleanupFailed machine id invocation outer normal tail inner = .ok after) (valid : Valid machine)
    (same : tail.flatMap QueueCustody.frameFields = machine.stack.flatMap QueueCustody.frameFields)
    (empty : QueueCustody.controlFields machine.control = []) : Valid after.state := by
  unfold cleanupFailed at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨original, originalAt, ⟨record, events⟩, completed, rfl⟩ := accepted
  have next := stack_fields_valid machine tail valid same
  have stored := replace_obligation_valid {machine with stack := tail} id.value original record originalAt
    (complete_obligation_fields _ _ _ _ _ completed) next
  exact control_valid _ _ stored empty

theorem cleanupAbandoned_valid (machine : State) (id : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : cleanupAbandoned machine id invocation outer normal tail inner = .ok after) (valid : Valid machine)
    (same : tail.flatMap QueueCustody.frameFields = machine.stack.flatMap QueueCustody.frameFields)
    (empty : QueueCustody.controlFields machine.control = []) : Valid after.state := by
  simp only [cleanupAbandoned, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, original, originalAt, ⟨record, events⟩, completed, rfl⟩ := accepted
  have next := stack_fields_valid machine tail valid same
  have stored := replace_obligation_valid {machine with stack := tail} id.value original record originalAt
    (complete_obligation_fields _ _ _ _ _ completed) next
  exact control_valid _ _ stored empty

theorem finishCleanupUnwind_valid (machine : State) (id : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : finishCleanupUnwind machine id invocation outer normal tail inner = .ok after) (valid : Valid machine)
    (same : tail.flatMap QueueCustody.frameFields = machine.stack.flatMap QueueCustody.frameFields)
    (empty : QueueCustody.controlFields machine.control = []) : Valid after.state := by
  unfold finishCleanupUnwind at accepted
  split at accepted <;> first
    | exact cleanupFailed_valid _ _ _ _ _ _ _ _ accepted valid same empty
    | exact cleanupAbandoned_valid _ _ _ _ _ _ _ _ accepted valid same empty
    | contradiction

theorem unwindStep_valid (machine : State) (context : Context) (after : Transition)
    (original : Cleanup.Exit .source) (unwinding : machine.control = .unwind original)
    (accepted : unwindStep machine context = .ok after) (valid : Valid machine)
    (contracts : ClosureContracts.Valid context machine.heap.objects) : Valid after.state := by
  simp only [unwindStep, unwinding, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨scope, _, accepted⟩ := accepted
  have empty : QueueCustody.controlFields machine.control = [] := by rw [unwinding]; rfl
  have pendingValid : Valid {machine with control := .discard (scope.holdings.flatMap (liveOwned machine.heap)) (.unwind (observedExit machine original))} :=
    control_valid machine _ valid empty
  cases stacked : machine.stack with
  | nil =>
    simp only [stacked] at accepted
    split at accepted
    · cases accepted
      simpa only [Valid, fields, QueueCustody.fields_components, stacked] using pendingValid
    · split at accepted <;> try contradiction
      all_goals cases accepted
      all_goals simpa only [Valid, fields, QueueCustody.fields_components, unwinding, stacked] using valid
  | cons saved tail =>
    have same (free : QueueCustody.frameFields saved = []) :
        tail.flatMap QueueCustody.frameFields = machine.stack.flatMap QueueCustody.frameFields := by
      simp only [stacked, List.flatMap_cons, free, List.nil_append]
    have tailValid (free : QueueCustody.frameFields saved = []) : Valid {machine with stack := tail} :=
      stack_fields_valid machine tail valid (same free)
    cases saved <;> simp only [stacked] at accepted
    case invocation invocation parent =>
      split at accepted
      · cases accepted
        simpa only [Valid, fields, QueueCustody.fields_components, stacked] using pendingValid
      · cases accepted
        simpa only [Valid, fields, QueueCustody.fields_components, QueueCustody.controlFields, DisposalShape.control, unwinding] using tailValid rfl
    case lexical identity =>
      split at accepted
      · cases accepted
        simpa only [Valid, fields, QueueCustody.fields_components, stacked] using pendingValid
      · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨_, _, parent, _, rfl⟩ := accepted
        simpa only [Valid, fields, QueueCustody.fields_components, QueueCustody.controlFields, DisposalShape.control, unwinding] using tailValid rfl
    case restore invocation parent =>
      cases accepted
      simpa only [Valid, fields, QueueCustody.fields_components, QueueCustody.controlFields, DisposalShape.control, unwinding] using tailValid rfl
    case binding binder body bindings parent =>
      cases accepted
      simpa only [Valid, fields, QueueCustody.fields_components, QueueCustody.controlFields, DisposalShape.control, unwinding] using tailValid rfl
    case operands intent bindings remaining evaluated =>
      cases accepted
      simpa only [Valid, fields, QueueCustody.fields_components, QueueCustody.controlFields, DisposalShape.control, unwinding] using tailValid rfl
    case handler active =>
      cases accepted
      simpa only [Valid, fields, QueueCustody.fields_components, QueueCustody.controlFields, DisposalShape.control, unwinding] using tailValid rfl
    case region region =>
      cases accepted
      simpa only [Valid, fields, QueueCustody.fields_components, QueueCustody.controlFields, DisposalShape.control, unwinding] using tailValid rfl
    case injection values =>
      cases accepted
      simpa only [Valid, fields, QueueCustody.fields_components, QueueCustody.controlFields, DisposalShape.control, unwinding] using tailValid rfl
    case protection identity =>
      exact beginCleanup_valid _ _ _ _ _ _ _ accepted valid (same rfl) empty contracts
    case cleanupReturn identity invocation outer normal =>
      exact finishCleanupUnwind_valid _ _ _ _ _ _ _ _ accepted valid (same rfl) empty
    case releaseReturn scope afterRelease =>
      cases accepted
      exact control_valid _ (.unwind _) (tailValid rfl) empty
    case disposalReturn remaining afterRelease invocation parent =>
      cases primaryIs : (observedExit machine original).primary <;> simp only [primaryIs] at accepted
      all_goals cases afterRelease <;> simp only [pure, Except.pure, Except.bind] at accepted
      all_goals cases accepted
      all_goals simpa only [Valid, fields, QueueCustody.fields_components, QueueCustody.controlFields,
        QueueCustody.frameFields, DisposalShape.control, DisposalShape.frame, unwinding, stacked,
        List.flatMap_cons, List.filter_nil, List.nil_append] using valid

theorem executeCleanupTerm_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executeCleanupTerm machine context = .ok after) (valid : Valid machine)
    (contracts : ClosureContracts.Valid context machine.heap.objects) : Valid after.state := by
  unfold executeCleanupTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  have empty : QueueCustody.controlFields machine.control = [] := by rw [executing]; rfl
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact installProtection_valid _ _ _ _ _ _ _ _ accepted valid empty contracts
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, unitIndex, _, ⟨middle, owner⟩, reserved, rfl⟩ := accepted
    have next := temporary_covered machine middle owner [] reserved (by simpa [Valid] using valid)
    exact control_valid _ _ (by simpa [Valid] using next) (by rw [temporary_control _ _ _ reserved]; exact empty)

end CustodyCoverage
end BoundaryV2.Profile.Source.Machine
