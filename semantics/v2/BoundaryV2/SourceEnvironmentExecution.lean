import BoundaryV2.SourceEnvironmentEffects

namespace BoundaryV2.Profile.Source.Machine
namespace EnvironmentInventory

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem executeControlTerm_preserves_types (machine : State) (context : Context) (after : Transition)
    (accepted : executeControlTerm machine context = .ok after) (typed : All context.source machine) :
    All context.source after.state := by
  unfold executeControlTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  have outer : Environment.Types context.source bindings := by
    simpa only [executing, control] using control_types _ _ typed
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  cases term <;> simp only at accepted <;> try contradiction
  case conditional =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    exact with_control_types _ _ _ typed outer
  case call =>
    cases accepted
    exact with_control_types _ _ _ typed outer
  case apply =>
    split at accepted <;> try contradiction
    exact applyClosure_preserves_types _ _ _ _ _ accepted typed
  case fail =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, rfl⟩ := accepted
    exact with_control_types _ _ _ typed (by simp [control, Environment.Types])
  case matchSum =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact enterPattern_preserves_types _ _ _ _ _ _ _ _ accepted typed outer
  case unpackProduct =>
    split at accepted <;> try contradiction
    exact enterPattern_preserves_types _ _ _ _ _ _ _ _ accepted typed outer

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
  have heapTyped : All context.source { machine with heap := heap } := movedTyped
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
        _ _ _ _ _ _ allocated heapTyped (by simp [object, Environment.Types])
      apply applyClosure_preserves_types _ _ _ _ _ applied
      simpa only [All, state, List.cons_append, List.nil_append, List.flatMap_cons, frame] using allocatedTyped

theorem beginCleanup_preserves_types (machine : State) (context : Context) (identity : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (accepted : beginCleanup machine context identity exit normal tail = .ok after)
    (typed : All context.source machine) (tailTyped : Environment.Types context.source (tail.flatMap frame)) :
    All context.source after.state := by
  simp only [beginCleanup, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, ⟨_, _⟩, _, _, _, _, _, _, _, transition, applied, rfl⟩ := accepted
  apply applyClosure_preserves_types _ _ _ _ _ applied
  have stacked := with_stack_types _ _ tail typed tailTyped
  exact stacked

theorem finishCleanup_preserves_types (machine : State) (context : Context) (after : Transition)
    (accepted : finishCleanup machine context = .ok after) (typed : All context.source machine) :
    All context.source after.state := by
  unfold finishCleanup at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i identity invocation exit normal tail stacked
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, ⟨_, _⟩, _, _, _, rfl⟩ := accepted
  apply resumeRelease_preserves_types
  exact with_stack_types _ _ _ typed (tail_types _ _ _ _ stacked typed)

theorem cleanupFailed_preserves_types (source : Module) (machine : State) (identity : ObligationId)
    (invocation : InvocationId) (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : cleanupFailed machine identity invocation outer normal tail inner = .ok after)
    (typed : All source machine) (tailTyped : Environment.Types source (tail.flatMap frame)) : All source after.state := by
  unfold cleanupFailed at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, ⟨_, _⟩, _, rfl⟩ := accepted
  have stacked := with_stack_types _ _ tail typed tailTyped
  exact with_control_types _ _ _ stacked (by simp [control, Environment.Types])

theorem releaseScope_preserves_types (source : Module) (machine : State) (after : Transition)
    (accepted : releaseScope machine = .ok after) (typed : All source machine) : All source after.state := by
  unfold releaseScope at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact with_control_types _ _ _ typed (by simp [control, Environment.Types])

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
    exact with_control_types _ _ _ middleTyped (by simp [control, Environment.Types])

theorem discardValues_preserves_types (machine : State) (context : Context) (after : Transition)
    (accepted : discardValues machine context = .ok after) (typed : All context.source machine) :
    All context.source after.state := by
  unfold discardValues at accepted
  split at accepted <;> try contradiction
  split at accepted
  · cases accepted; exact resumeRelease_preserves_types _ _ _ typed
  · split at accepted
    · cases accepted; exact with_control_types _ _ _ typed (by simp [control, Environment.Types])
    · simp only [bind, except_bind_ok] at accepted
      obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
      have storedTyped := lookupObject_types _ _ _ _ _ looked typed
      cases stored <;> try contradiction
      all_goals
        simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨store, retired, rfl⟩ := accepted
        have heapTyped := retireObject_preserves_types _ _ _ _ retired typed
      all_goals first
        | exact with_control_types _ _ _ heapTyped (by simp [control, Environment.Types])
        | (simp only [All, Environment.Types, state, control, List.flatMap_append, List.flatMap_cons,
             List.flatMap_nil, List.append_nil, frame, object, capture, List.mem_append] at heapTyped storedTyped ⊢
           grind only [])

theorem unwindStep_preserves_types (machine : State) (context : Context) (after : Transition)
    (accepted : unwindStep machine context = .ok after) (typed : All context.source machine) :
    All context.source after.state := by
  unfold unwindStep at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  cases stacked : machine.stack with
  | nil =>
    simp only [stacked] at accepted
    split at accepted
    · cases accepted
      simp only [All, Environment.Types, state, control, stacked, List.mem_append] at typed ⊢
      grind only []
    · split at accepted <;> try contradiction
      all_goals cases accepted; simpa only [All, state, stacked] using typed
  | cons saved tail =>
    have tailTyped := tail_types _ _ _ _ stacked typed
    have stackedTyped := with_stack_types _ _ _ typed tailTyped
    cases saved <;> simp only [stacked] at accepted
    case invocation =>
      split at accepted
      · cases accepted
        simp only [All, Environment.Types, state, control, stacked, List.mem_append] at typed ⊢
        grind only []
      · cases accepted; exact stackedTyped
    case lexical =>
      split at accepted
      · cases accepted
        simp only [All, Environment.Types, state, control, stacked, List.mem_append] at typed ⊢
        grind only []
      · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨_, _, _, _, rfl⟩ := accepted
        exact stackedTyped
    case protection => exact beginCleanup_preserves_types _ _ _ _ _ _ _ accepted typed tailTyped
    case cleanupReturn => exact cleanupFailed_preserves_types _ _ _ _ _ _ _ _ _ accepted typed tailTyped
    case releaseReturn =>
      cases accepted
      exact with_control_types _ _ _ stackedTyped (by simp [control, Environment.Types])
    case disposalReturn =>
      repeat' split at accepted
      all_goals simp only [pure, Except.pure, Except.bind, Except.ok.injEq] at accepted
      all_goals cases accepted
      all_goals exact with_control_types _ _ _ stackedTyped (by simp [control, Environment.Types])
    all_goals cases accepted; exact stackedTyped


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
      simpa only [All, state, executing, stacked] using typed
    | cons saved tail =>
      have tailTyped := tail_types _ _ _ _ stacked typed
      have stackedTyped := with_stack_types _ _ _ typed tailTyped
      cases saved <;> simp only [stacked] at accepted
      all_goals first
        | exact enterBinding_preserves_types _ _ _ accepted typed
        | exact deliverOperand_preserves_types _ _ accepted typed
        | exact leaveInvocation_preserves_types _ _ _ accepted typed
        | exact leaveLexical_preserves_types _ _ _ accepted typed
        | exact restoreResumeCaller_preserves_types _ _ _ accepted typed
        | exact completeHandler_preserves_types _ _ _ accepted typed
        | exact beginCleanup_preserves_types _ _ _ _ _ _ _ accepted typed tailTyped
        | exact finishCleanup_preserves_types _ _ _ accepted typed
        | (cases accepted; exact stackedTyped)
        | (cases accepted; exact with_control_types _ _ _ stackedTyped (by simp [control, Environment.Types]))
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

/-- Every lexical binding in running, stacked, or captured source code keeps
its declared schema through the actual transition relation. This component
neither assumes nor establishes complete frame or heap compatibility. -/
theorem initialized_execution_preserves_environment_types (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : All context.source after :=
  steps_preserve_types _ _ _ _ steps (initial_types _ _ _ initialized)

end EnvironmentInventory
end BoundaryV2.Profile.Source.Machine
