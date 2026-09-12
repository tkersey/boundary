import BoundaryV2.SourceFailureEffects

namespace BoundaryV2.Profile.Source.Machine
namespace FailureSchemas

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

theorem primary_failure_type (source : Module) (value : Cleanup.Exit .source) (failure : SemanticValue)
    (typed : Types source (exit value)) (failed : value.primary = .failure failure) :
    failure.schema = source.failure := typed _ (by simp [exit, failed])

theorem set_obligation_preserves_types (source : Module) (machine : State) (index : Nat)
    (record : Cleanup.Obligation .source) (typed : All source machine) (recordTyped : Types source (obligation record)) :
    All source { machine with heap := { machine.heap with obligations := machine.heap.obligations.set index record } } := by
  simp only [All, Types, state, heap, List.mem_append, List.mem_flatMap] at typed ⊢
  simp only [Types] at recordTyped
  grind only [→ List.mem_or_eq_of_mem_set]

theorem begin_obligation_types (source : Module) (before after : Cleanup.Obligation .source)
    (invocation : InvocationId) (events : List Cleanup.Event)
    (accepted : Cleanup.begin before invocation = some (after, events)) : Types source (obligation after) := by
  unfold Cleanup.begin at accepted
  split at accepted <;> try contradiction
  cases accepted
  simp [obligation, Types]

theorem complete_obligation_types (source : Module) (before after : Cleanup.Obligation .source)
    (invocation : InvocationId) (result : Except SemanticValue Unit) (events : List Cleanup.Event)
    (accepted : Cleanup.complete before invocation result = some (after, events))
    (failureTyped : ∀ value, result = .error value → value.schema = source.failure) : Types source (obligation after) := by
  unfold Cleanup.complete at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases result with
  | ok resultValue => cases resultValue; cases accepted; simp [obligation, Types]
  | error failure => cases accepted; simpa [obligation, Types] using failureTyped failure rfl

theorem exit_after_types (source : Module) (value : Cleanup.Exit .source) (normal : Option Located)
    (after : AfterRelease) (accepted : exitAfter value normal = .ok after)
    (typed : Types source (exit value)) : Types source (afterRelease after) := by
  unfold exitAfter at accepted
  split at accepted
  · simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    simp [afterRelease, Types]
  · cases accepted; exact typed

theorem resumeRelease_preserves_types (source : Module) (machine : State) (after : AfterRelease)
    (typed : All source machine) (afterTyped : Types source (afterRelease after)) :
    All source (resumeRelease machine after).state := by
  cases after with
  | deliver value => exact with_control_types _ _ _ typed (by simp [control, Types])
  | unwind value => exact with_control_types _ _ _ typed afterTyped

theorem beginCleanup_preserves_types (machine : State) (context : Context) (identity : ObligationId)
    (value : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (accepted : beginCleanup machine context identity value normal tail = .ok after)
    (typed : All context.source machine) (exitTyped : Types context.source (exit value))
    (tailTyped : Types context.source (tail.flatMap frame)) : All context.source after.state := by
  simp only [beginCleanup, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨before, _, _, _, ⟨record, events⟩, began, _, _, _, _, _, _, transition, applied, rfl⟩ := accepted
  have recordTyped := begin_obligation_types context.source _ _ _ _ began
  have heapTyped := set_obligation_preserves_types _ _ identity.value _ typed recordTyped
  have framedTyped := with_stack_types _ _ (.cleanupReturn identity ⟨machine.heap.nextInvocation⟩ (observedExit machine value) normal :: tail) heapTyped (by
    simp only [Types, List.flatMap_cons, frame, List.mem_append, observed_exit] at exitTyped tailTyped ⊢
    grind only [])
  have result := applyClosure_preserves_types _ _ _ _ _ applied framedTyped
  exact result

theorem finishCleanup_preserves_types (machine : State) (context : Context) (after : Transition)
    (accepted : finishCleanup machine context = .ok after) (typed : All context.source machine) :
    All context.source after.state := by
  unfold finishCleanup at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i identity invocation value normal tail stacked
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, before, _, ⟨record, events⟩, completed, release, released, rfl⟩ := accepted
  have recordTyped := complete_obligation_types context.source _ _ _ _ _ completed (by simp)
  have heapTyped := set_obligation_preserves_types _ _ identity.value _ typed recordTyped
  have frameTyped := frame_types _ _ (.cleanupReturn identity invocation value normal) (by simp [stacked]) typed
  have exitTyped : Types context.source (exit (observedExit machine value)) := by
    simpa only [frame, observed_exit] using frameTyped
  have releaseTyped := exit_after_types _ _ _ _ released exitTyped
  have stackedTyped := with_stack_types _ _ _ heapTyped (tail_types _ _ _ _ stacked typed)
  exact resumeRelease_preserves_types _ _ _ stackedTyped releaseTyped

theorem cleanupFailed_preserves_types (source : Module) (machine : State) (identity : ObligationId)
    (invocation : InvocationId) (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : cleanupFailed machine identity invocation outer normal tail inner = .ok after)
    (typed : All source machine) (outerTyped : Types source (exit outer)) (innerTyped : Types source (exit inner))
    (tailTyped : Types source (tail.flatMap frame)) : All source after.state := by
  unfold cleanupFailed at accepted
  split at accepted <;> try contradiction
  rename_i failure failed
  have failureTyped := primary_failure_type source inner failure innerTyped failed
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨before, _, ⟨record, events⟩, completed, rfl⟩ := accepted
  have recordTyped := complete_obligation_types source _ _ _ _ _ completed (by intro value same; cases same; exact failureTyped)
  have heapTyped := set_obligation_preserves_types _ _ identity.value _ typed recordTyped
  have stackedTyped := with_stack_types _ _ _ heapTyped tailTyped
  exact with_control_types _ _ _ stackedTyped (merge_abrupt_types _ _ _ outerTyped innerTyped)

theorem cleanupAbandoned_preserves_types (source : Module) (machine : State) (identity : ObligationId)
    (invocation : InvocationId) (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : cleanupAbandoned machine identity invocation outer normal tail inner = .ok after)
    (typed : All source machine) (outerTyped : Types source (exit outer)) (innerTyped : Types source (exit inner))
    (tailTyped : Types source (tail.flatMap frame)) : All source after.state := by
  simp only [cleanupAbandoned, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, before, _, ⟨record, events⟩, completed, rfl⟩ := accepted
  have recordTyped := complete_obligation_types source _ _ _ _ _ completed (by intro value same; contradiction)
  have heapTyped := set_obligation_preserves_types _ _ identity.value _ typed recordTyped
  have stackedTyped := with_stack_types _ _ _ heapTyped tailTyped
  exact with_control_types _ _ _ stackedTyped (propagate_exit_types _ _ _ outerTyped innerTyped)

theorem finishCleanupUnwind_preserves_types (source : Module) (machine : State) (identity : ObligationId)
    (invocation : InvocationId) (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : finishCleanupUnwind machine identity invocation outer normal tail inner = .ok after)
    (typed : All source machine) (outerTyped : Types source (exit outer)) (innerTyped : Types source (exit inner))
    (tailTyped : Types source (tail.flatMap frame)) : All source after.state := by
  unfold finishCleanupUnwind at accepted
  split at accepted <;> first
    | exact cleanupFailed_preserves_types _ _ _ _ _ _ _ _ _ accepted typed outerTyped innerTyped tailTyped
    | exact cleanupAbandoned_preserves_types _ _ _ _ _ _ _ _ _ accepted typed outerTyped innerTyped tailTyped
    | contradiction

theorem finishDisposal_preserves_types (source : Module) (machine : State) (after : Transition)
    (accepted : finishDisposal machine = .ok after) (typed : All source machine) : All source after.state := by
  unfold finishDisposal at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i remaining release invocation scope tail stacked
  have tailTyped := tail_types _ _ _ _ stacked typed
  have frameTyped := frame_types _ _ (.disposalReturn remaining release invocation scope) (by simp [stacked]) typed
  cases accepted
  exact with_control_types _ _ _ (with_stack_types _ _ _ typed tailTyped) frameTyped

theorem releaseScope_preserves_types (source : Module) (machine : State) (after : Transition)
    (accepted : releaseScope machine = .ok after) (typed : All source machine) : All source after.state := by
  unfold releaseScope at accepted
  split at accepted <;> try contradiction
  rename_i scope release executing
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact with_control_types _ _ _ typed (by simpa only [executing, control] using control_types _ _ typed)


theorem executeControlTerm_preserves_types (machine : State) (context : Context) (after : Transition)
    (accepted : executeControlTerm machine context = .ok after) (typed : All context.source machine) :
    All context.source after.state := by
  unfold executeControlTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  cases term <;> simp only at accepted <;> try contradiction
  case conditional =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    exact with_control_types _ _ _ typed (by simp [control, Types])
  case call =>
    cases accepted
    exact with_control_types _ _ _ typed (by simp [control, Types])
  case apply =>
    split at accepted <;> try contradiction
    exact applyClosure_preserves_types _ _ _ _ _ accepted typed
  case fail =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, checked, rfl⟩ := accepted
    have schema := require_ok _ _ _ checked
    apply with_control_types _ _ _ typed
    simpa only [control, exit, Types, List.map_nil, List.append_nil, List.mem_singleton, forall_eq, beq_iff_eq] using schema
  case matchSum =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact enterPattern_preserves_types _ _ _ _ _ _ _ _ accepted typed
  case unpackProduct =>
    split at accepted <;> try contradiction
    exact enterPattern_preserves_types _ _ _ _ _ _ _ _ accepted typed

theorem installProtection_preserves_types (machine : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (accepted : installProtection machine context body cleanup arguments resource loan = .ok after)
    (typed : All context.source machine) : All context.source after.state := by
  simp only [installProtection, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨bodyType, _, _, _, _, _, _, _, _, _, store, moved, accepted⟩ := accepted
  have movedTyped := moveValues_preserves_types _ _ _ _ _ moved typed
  let record : Cleanup.Obligation .source := ⟨⟨machine.heap.nextObligation⟩, machine.scope, machine.heap.nextObligation,
    cleanup.value, resource.map Located.value, .pending⟩
  let heap := { store with obligations := store.obligations ++ [record], nextObligation := store.nextObligation + 1 }
  have heapTyped : All context.source { machine with heap := heap }  := by
    simpa only [All, state, heap, FailureSchemas.heap, List.flatMap_append, List.flatMap_cons, List.flatMap_nil,
      record, obligation, List.append_nil] using movedTyped
  cases resource with
  | none =>
    cases loan <;> try contradiction
    simp only [pure, Except.pure, Except.bind] at accepted
    apply applyClosure_preserves_types _ _ _ _ _ accepted
    simpa only [All, state, List.singleton_append, List.flatMap_cons, frame, List.nil_append] using heapTyped
  | some resourceValue =>
    cases loan with
    | none => contradiction
    | some descriptor =>
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨borrowSchema, _, _, _, ⟨afterStore, borrowed⟩, allocated, _, rfl, applied⟩ := accepted
      have allocatedTyped := allocateObject_preserves_types _
        { machine with heap := { heap with nextRegion := heap.nextRegion + 1, loans := heap.loans ++ [(⟨heap.nextRegion⟩, ⟨machine.heap.nextObligation⟩)] } }
        _ _ _ _ _ _ allocated heapTyped (by simp [object, Types])
      apply applyClosure_preserves_types _ _ _ _ _ applied
      simpa only [All, state, List.cons_append, List.nil_append, List.flatMap_cons, frame] using allocatedTyped

theorem executeCleanupTerm_preserves_types (machine : State) (context : Context) (after : Transition)
    (accepted : executeCleanupTerm machine context = .ok after) (typed : All context.source machine) :
    All context.source after.state := by
  unfold executeCleanupTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact installProtection_preserves_types _ _ _ _ _ _ _ _ accepted typed
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, ⟨middle, owner⟩, temporaryOk, rfl⟩ := accepted
    have middleTyped := temporary_preserves_types _ _ _ _ temporaryOk typed
    exact with_control_types _ _ _ middleTyped (by simp [control, afterRelease, Types])

theorem discardValues_preserves_types (machine : State) (context : Context) (after : Transition)
    (accepted : discardValues machine context = .ok after) (typed : All context.source machine) :
    All context.source after.state := by
  unfold discardValues at accepted
  split at accepted <;> try contradiction
  rename_i values release executing
  have releaseTyped : Types context.source (afterRelease release) := by
    simpa only [executing, control] using control_types _ _ typed
  split at accepted
  · cases accepted; exact resumeRelease_preserves_types _ _ _ typed releaseTyped
  · split at accepted
    · cases accepted; exact with_control_types _ _ _ typed releaseTyped
    · simp only [bind, except_bind_ok] at accepted
      obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
      have storedTyped := lookupObject_types _ _ _ _ _ looked typed
      cases stored <;> try contradiction
      all_goals
        simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨store, retired, rfl⟩ := accepted
        have heapTyped := retireObject_preserves_types _ _ _ _ retired typed
      all_goals first
        | exact with_control_types _ _ _ heapTyped releaseTyped
        | (simp only [All, Types, state, control, List.flatMap_append, List.flatMap_cons,
             List.flatMap_nil, List.append_nil, frame, object, capture, afterRelease, List.mem_append, List.not_mem_nil] at heapTyped storedTyped releaseTyped ⊢
           cases release <;> simp only [exit, List.map_nil, List.append_nil] at * <;> grind only [])


theorem unwindStep_preserves_types (machine : State) (context : Context) (after : Transition)
    (accepted : unwindStep machine context = .ok after) (typed : All context.source machine) :
    All context.source after.state := by
  unfold unwindStep at accepted
  split at accepted <;> try contradiction
  rename_i original unwinding
  have exitTyped : Types context.source (exit (observedExit machine original)) := by
    simpa only [observed_exit, unwinding, control] using control_types _ _ typed
  have pendingTyped := with_control_types _ _ (.discard [] (.unwind (observedExit machine original))) typed exitTyped
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  cases stacked : machine.stack with
  | nil =>
    simp only [stacked] at accepted
    split at accepted
    · cases accepted; simpa only [All, state, control, stacked] using pendingTyped
    · split at accepted <;> try contradiction
      all_goals cases accepted
      all_goals simp only [All, Types, state, status, List.mem_append] at typed ⊢
      all_goals simp only [Types] at exitTyped
      all_goals grind only []
  | cons saved tail =>
    have tailTyped := tail_types _ _ _ _ stacked typed
    have stackedTyped := with_stack_types _ _ _ typed tailTyped
    have frameTyped := frame_types _ _ saved (by simp [stacked]) typed
    cases saved <;> simp only [stacked] at accepted
    case invocation =>
      split at accepted
      · cases accepted; simpa only [All, state, control, stacked] using pendingTyped
      · cases accepted; exact stackedTyped
    case lexical =>
      split at accepted
      · cases accepted; simpa only [All, state, control, stacked] using pendingTyped
      · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨_, _, _, _, rfl⟩ := accepted
        exact stackedTyped
    case protection => exact beginCleanup_preserves_types _ _ _ _ _ _ _ accepted typed exitTyped tailTyped
    case cleanupReturn => exact finishCleanupUnwind_preserves_types _ _ _ _ _ _ _ _ _ accepted typed frameTyped exitTyped tailTyped
    case releaseReturn scope release =>
      cases accepted
      apply with_control_types _ _ _ stackedTyped
      cases release with
      | unwind value => exact propagate_exit_types _ _ _ frameTyped exitTyped
      | deliver value => exact propagate_exit_types _ _ _ (by simp [Types, exit]) exitTyped
    case disposalReturn remaining release invocation scope =>
      cases primary : (observedExit machine original).primary <;> simp only [primary] at accepted
      all_goals cases release <;> simp only [pure, Except.pure, Except.bind] at accepted
      all_goals cases accepted
      all_goals apply with_control_types _ _ _ stackedTyped
      all_goals first
        | exact frameTyped
        | exact exitTyped
        | exact propagate_exit_types _ _ _ (by simp [Types, exit]) exitTyped
    all_goals cases accepted; exact stackedTyped

theorem with_status_types (source : Module) (machine : State) (next : Status) (typed : All source machine)
    (nextTyped : Types source (status next)) : All source { machine with status := next } := by
  simp only [All, Types, state, List.mem_append] at typed ⊢
  simp only [Types] at nextTyped
  grind only []

theorem external_preserves_types (machine : State) (context : Context) (action : External) (after : Transition)
    (accepted : external machine context action = .ok after) (typed : All context.source machine) :
    All context.source after.state := by
  have running : All context.source { machine with status := .running } :=
    with_status_types _ _ _ typed (by simp [status, Types])
  have cancelled (reason : Protocol.Reason) : All context.source
      { machine with status := .running, control := cancelControl machine.control reason, cancellation := some reason } := by
    have result := with_control_types _ _ (cancelControl machine.control reason) running
      (by simpa only [cancel_control] using control_types _ _ typed)
    exact result
  have cancellationOnly (reason : Protocol.Reason) : All context.source { machine with cancellation := some reason } := typed
  have scopedResult (value : SemanticValue) (transition : Transition)
      (checked : scopedValue { machine with status := .running } value = .ok transition) :
      All context.source transition.state := scopedValue_preserves_types _ _ _ _ checked running
  cases phase : machine.status <;> cases action <;>
    simp only [external, phase, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw,
      Except.bind] at accepted <;> try contradiction
  all_goals grind (gen := 32) only []


theorem tickRunning_preserves_types (machine : State) (context : Context) (after : Transition)
    (accepted : tickRunning machine context = .ok after) (typed : All context.source machine) :
    All context.source after.state := by
  cases executing : machine.control <;> simp only [tickRunning, executing] at accepted
  case term => exact enterTerm_preserves_types _ _ _ accepted typed
  case expression => exact enterExpression_preserves_types _ _ _ accepted typed
  case invoke => exact enterInvocation_preserves_types _ _ _ accepted typed
  case release => exact releaseScope_preserves_types _ _ _ accepted typed
  case discard => exact discardValues_preserves_types _ _ _ accepted typed
  case unwind => exact unwindStep_preserves_types _ _ _ accepted typed
  case execute intent bindings operands =>
    cases intent with
    | primitive => exact executePrimitive_preserves_types _ _ _ accepted typed
    | term term =>
      cases term <;> first
        | exact executeEffectTerm_preserves_types _ _ _ accepted typed
        | exact executeCleanupTerm_preserves_types _ _ _ accepted typed
        | exact executeControlTerm_preserves_types _ _ _ accepted typed
  case delivered value =>
    cases stacked : machine.stack with
    | nil =>
      simp only [stacked, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
      have result := with_status_types _ _ (.completed value.value) typed (by simp [status, Types])
      simpa only [All, state, executing, stacked] using result
    | cons saved tail =>
      have tailTyped := tail_types _ _ _ _ stacked typed
      have stackedTyped := with_stack_types _ _ _ typed tailTyped
      have frameTyped := frame_types _ _ saved (by simp [stacked]) typed
      cases saved <;> simp only [stacked] at accepted
      all_goals first
        | exact enterBinding_preserves_types _ _ _ accepted typed
        | exact deliverOperand_preserves_types _ _ accepted typed
        | exact leaveInvocation_preserves_types _ _ _ accepted typed
        | exact leaveLexical_preserves_types _ _ _ accepted typed
        | exact restoreResumeCaller_preserves_types _ _ _ accepted typed
        | exact completeHandler_preserves_types _ _ _ accepted typed
        | exact beginCleanup_preserves_types _ _ _ _ _ _ _ accepted typed (by simp [Types, exit]) tailTyped
        | exact finishCleanup_preserves_types _ _ _ accepted typed
        | exact finishDisposal_preserves_types _ _ _ accepted typed
        | (cases accepted; exact stackedTyped)
        | (cases accepted; exact with_control_types _ _ _ stackedTyped frameTyped)
        | contradiction

theorem tick_preserves_types (machine : State) (context : Context) (after : Transition)
    (accepted : tick machine context = .ok after) (typed : All context.source machine) :
    All context.source after.state := by
  cases phase : machine.status <;> simp only [tick, phase] at accepted
  · exact tickRunning_preserves_types _ _ _ accepted typed
  all_goals cases accepted; exact typed

theorem step_preserves_types (context : Context) (before after : State) (events : List Event)
    (step : Step context before events after) (typed : All context.source before) : All context.source after := by
  cases step with
  | internal accepted => exact tick_preserves_types _ _ _ accepted typed
  | external accepted => exact external_preserves_types _ _ _ _ accepted typed

theorem steps_preserve_types (context : Context) (before after : State) (events : List Event)
    (steps : Steps context before events after) (typed : All context.source before) : All context.source after := by
  induction steps with
  | refl => exact typed
  | cons step _ induction => exact induction (step_preserves_types _ _ _ _ step typed)

/-- Primary failures, accumulated failures, and failed obligation records keep
the module's declared failure schema throughout actual initialized source
execution, including captured continuations and cleanup. -/
theorem initialized_execution_preserves_failure_schemas (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : All context.source after :=
  steps_preserve_types _ _ _ _ steps (initial_types _ _ _ initialized)


theorem reachable_unwind_preserves_value_shapes (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (original : Cleanup.Exit .source)
    (unwinding : machine.control = .unwind original) (after : Transition)
    (accepted : unwindStep machine context = .ok after)
    (typed : ValueInventory.All (ValueShape context.source.schemas) machine)
    : ValueInventory.All (ValueShape context.source.schemas) after.state := by
  have failureTyped := initialized_execution_preserves_failure_schemas _ _ _ _ _ initialized steps
  have originalTyped : Types context.source (exit original) := by
    simpa only [unwinding, control] using control_types _ _ failureTyped
  have observedTyped : Types context.source (exit (observedExit machine original)) := by
    simpa only [observed_exit] using originalTyped
  have originalValues : ∀ value ∈ exitValues original, ValueShape context.source.schemas value := by
    intro value member
    apply typed
    simp [ValueInventory.state, unwinding, ValueInventory.control, member]
  apply unwindStep_preserves_value_shapes _ _ _ _ unwinding accepted typed _
  intro value failed
  rcases failed with failed | member
  · exact ⟨originalValues value (ValueInventory.observed_exit_subset machine original (by simp [exitValues, failed])),
      primary_failure_type _ _ _ observedTyped failed⟩
  · exact ⟨originalValues value (by simp [exitValues, member]), originalTyped _ (List.mem_append_right _ (List.mem_map.mpr ⟨value, member, rfl⟩))⟩

end FailureSchemas
end BoundaryV2.Profile.Source.Machine
