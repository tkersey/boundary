import BoundaryV2.SourceClosureEffects
import BoundaryV2.SourceEnvironmentExecution

namespace BoundaryV2.Profile.Source.Machine
namespace ClosureContracts

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem enterTerm_valid (context : Context) (machine : State) (after : Transition)
    (accepted : enterTerm machine context.source = .ok after) (typed : Valid context machine.heap.objects) :
    Valid context after.state.heap.objects := by
  unfold enterTerm at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  repeat' split at accepted
  all_goals cases accepted; exact typed

theorem deliverOperand_valid (context : Context) (machine : State) (after : Transition)
    (accepted : deliverOperand machine = .ok after) (typed : Valid context machine.heap.objects) :
    Valid context after.state.heap.objects := by
  unfold deliverOperand at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  split at accepted <;> cases accepted <;> exact typed

theorem completeHandler_valid (machine : State) (context : Context) (after : Transition)
    (accepted : completeHandler machine context = .ok after) (typed : Valid context machine.heap.objects) :
    Valid context after.state.heap.objects := by
  unfold completeHandler at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact typed

theorem cleanupFailed_valid (context : Context) (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : cleanupFailed machine identity invocation outer normal tail inner = .ok after)
    (typed : Valid context machine.heap.objects) : Valid context after.state.heap.objects := by
  unfold cleanupFailed at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact typed

theorem releaseScope_valid (context : Context) (machine : State) (after : Transition)
    (accepted : releaseScope machine = .ok after) (typed : Valid context machine.heap.objects) :
    Valid context after.state.heap.objects := by
  unfold releaseScope at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact typed

theorem leaveInvocation_valid (context : Context) (machine : State) (after : Transition)
    (accepted : leaveInvocation machine = .ok after) (typed : Valid context machine.heap.objects) :
    Valid context after.state.heap.objects := by
  unfold leaveInvocation at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  exact leaveScope_valid _ _ _ _ _ _ _ accepted typed

theorem leaveLexical_valid (context : Context) (machine : State) (after : Transition)
    (accepted : leaveLexical machine = .ok after) (typed : Valid context machine.heap.objects) :
    Valid context after.state.heap.objects := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, leaving, accepted⟩ := accepted
  have result := leaveScope_valid _ _ _ _ _ _ _ leaving typed
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, store, moved, rfl⟩ := accepted
  have movedTyped := move_valid _ _ _ _ _ moved result
  exact movedTyped

theorem executeControlTerm_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executeControlTerm machine context = .ok after) (typed : Valid context machine.heap.objects) :
    Valid context after.state.heap.objects := by
  unfold executeControlTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  case h_1 =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    exact typed
  all_goals first
    | (cases accepted; exact typed)
    | (split at accepted <;> try contradiction)
  all_goals first
    | exact applyClosure_valid _ _ _ _ _ accepted typed
    | exact enterPattern_valid _ _ _ _ _ _ _ _ accepted typed
    | (simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
       obtain ⟨_, _, rfl⟩ := accepted
       exact typed)
    | (simp only [except_bind_ok] at accepted
       obtain ⟨_, _, accepted⟩ := accepted
       exact enterPattern_valid _ _ _ _ _ _ _ _ accepted typed)

theorem executeCleanupTerm_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executeCleanupTerm machine context = .ok after) (typed : Valid context machine.heap.objects) :
    Valid context after.state.heap.objects := by
  unfold executeCleanupTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact installProtection_valid _ _ _ _ _ _ _ _ accepted typed
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, ⟨middle, owner⟩, temporaryOk, rfl⟩ := accepted
    have result := temporary_valid _ _ _ _ temporaryOk typed
    exact result

theorem executeEffectTerm_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executeEffectTerm machine context = .ok after) (typed : Valid context machine.heap.objects) :
    Valid context after.state.heap.objects := by
  unfold executeEffectTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  cases term <;> simp only at accepted <;> try contradiction
  case perform operation => exact openRequest_valid _ _ _ _ _ accepted typed
  all_goals split at accepted <;> try contradiction
  all_goals first
    | exact installHandler_valid _ _ _ _ _ _ _ _ accepted typed
    | exact resumeValue_valid _ _ _ _ _ _ accepted typed
    | exact resumeComputation_valid _ _ _ _ _ accepted typed
    | exact enterRegion_valid _ _ _ _ _ _ accepted typed

theorem unwindStep_valid (machine : State) (context : Context) (after : Transition)
    (accepted : unwindStep machine context = .ok after) (typed : Valid context machine.heap.objects) :
    Valid context after.state.heap.objects := by
  unfold unwindStep at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  cases stacked : machine.stack with
  | nil =>
    simp only [stacked] at accepted
    split at accepted
    · cases accepted; exact typed
    · split at accepted <;> try contradiction
      all_goals cases accepted; exact typed
  | cons saved tail =>
    cases saved <;> simp only [stacked] at accepted
    case invocation => split at accepted <;> cases accepted <;> exact typed
    case lexical =>
      split at accepted
      · cases accepted; exact typed
      · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨_, _, _, _, rfl⟩ := accepted
        exact typed
    case protection => exact beginCleanup_valid _ _ _ _ _ _ _ accepted typed
    case cleanupReturn => exact cleanupFailed_valid _ _ _ _ _ _ _ _ _ accepted typed
    case disposalReturn =>
      repeat' split at accepted
      all_goals simp only [pure, Except.pure, Except.bind, Except.ok.injEq] at accepted
      all_goals cases accepted; exact typed
    all_goals cases accepted; exact typed

theorem tickRunning_valid (machine : State) (context : Context) (after : Transition)
    (accepted : tickRunning machine context = .ok after) (typed : Valid context machine.heap.objects)
    (contextTyped : context.typingValid = true) : Valid context after.state.heap.objects := by
  cases executing : machine.control <;> simp only [tickRunning, executing] at accepted
  case term => exact enterTerm_valid _ _ _ accepted typed
  case expression => exact enterExpression_valid _ _ _ accepted typed contextTyped
  case invoke => exact enterInvocation_valid _ _ _ accepted typed
  case release => exact releaseScope_valid _ _ _ accepted typed
  case discard => exact discardValues_valid _ _ _ accepted typed
  case unwind => exact unwindStep_valid _ _ _ accepted typed
  case execute intent bindings operands =>
    cases intent with
    | primitive => exact executePrimitive_valid _ _ _ accepted typed contextTyped
    | term term =>
      cases term <;> first
        | exact executeEffectTerm_valid _ _ _ accepted typed
        | exact executeCleanupTerm_valid _ _ _ accepted typed
        | exact executeControlTerm_valid _ _ _ accepted typed
  case delivered value =>
    cases stacked : machine.stack with
    | nil =>
      simp only [stacked, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
      exact typed
    | cons saved tail =>
      cases saved <;> simp only [stacked] at accepted
      all_goals first
        | exact enterBinding_valid _ _ _ accepted typed
        | exact deliverOperand_valid _ _ _ accepted typed
        | exact leaveInvocation_valid _ _ _ accepted typed
        | exact leaveLexical_valid _ _ _ accepted typed
        | exact restoreResumeCaller_valid _ _ _ accepted typed
        | exact completeHandler_valid _ _ _ accepted typed
        | exact beginCleanup_valid _ _ _ _ _ _ _ accepted typed
        | exact finishCleanup_valid _ _ _ accepted typed
        | (cases accepted; exact typed)
        | contradiction

theorem tick_valid (machine : State) (context : Context) (after : Transition)
    (accepted : tick machine context = .ok after) (typed : Valid context machine.heap.objects)
    (contextTyped : context.typingValid = true) : Valid context after.state.heap.objects := by
  cases phase : machine.status <;> simp only [tick, phase] at accepted
  · exact tickRunning_valid _ _ _ accepted typed contextTyped
  all_goals cases accepted; exact typed

theorem external_valid (machine : State) (context : Context) (action : External) (after : Transition)
    (accepted : external machine context action = .ok after) (typed : Valid context machine.heap.objects) :
    Valid context after.state.heap.objects := by
  have scopedValid (value : SemanticValue) (transition : Transition)
      (checked : scopedValue { machine with status := .running } value = .ok transition) :
      Valid context transition.state.heap.objects := scopedValue_valid _ _ _ _ checked typed
  cases action <;> cases phase : machine.status <;>
    simp only [external, phase, bind, pure, Except.pure, Except.bind] at accepted <;> try contradiction
  all_goals grind (gen := 32) only [except_bind_ok]

theorem initial_valid (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) : Valid context machine.heap.objects := by
  simp only [initial, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ := accepted
  simp [Valid]

theorem step_valid (context : Context) (before after : State) (events : List Event)
    (step : Step context before events after) (typed : Valid context before.heap.objects)
    (contextTyped : context.typingValid = true) : Valid context after.heap.objects := by
  cases step with
  | internal accepted => exact tick_valid _ _ _ accepted typed contextTyped
  | external accepted => exact external_valid _ _ _ _ accepted typed

theorem steps_valid (context : Context) (before after : State) (events : List Event)
    (steps : Steps context before events after) (typed : Valid context before.heap.objects)
    (contextTyped : context.typingValid = true) : Valid context after.heap.objects := by
  induction steps with
  | refl => exact typed
  | cons step _ induction => exact induction (step_valid _ _ _ _ step typed contextTyped)

theorem initialized_execution_preserves_closure_contracts (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : Valid context after.heap.objects := by
  have contextTyped : context.typingValid = true := by
    simpa only [Context.typingValid, Option.any_eq_true] using initial_checks_typing _ _ _ initialized
  exact steps_valid _ _ _ _ steps (initial_valid _ _ _ initialized) contextTyped

theorem environment_variable_types (source : Module) (bindings : Environment) (typed : Environment.Types source bindings) :
    Admission.variableTypes source (bindings.map Binding.var) = some (bindings.map (fun binding => binding.located.value.schema)) := by
  induction bindings with
  | nil => rfl
  | cons binding tail induction =>
    have first := typed binding (by simp)
    have rest := induction (fun member belongs => typed member (List.mem_cons_of_mem _ belongs))
    simp only [Admission.variableTypes] at rest
    simp only [Admission.variableTypes, List.map_cons, List.mapM_cons, first, bind, Option.bind_some, rest, pure]

theorem reachable_closure_contract (context : Context) (arguments : List SemanticValue) (before machine : State)
    (events : List Event) (initialized : initial context arguments = .ok before) (steps : Steps context before events machine)
    (node : NodeId) (schema : SchemaId .source) (function : FunctionId .source) (bindings : Environment)
    (found : machine.heap.lookup node = some (.closure schema function bindings)) :
    Admission.lambdaValid context.source context.captures function schema = true ∧
    bindings.map Binding.var = Analysis.captures context.captures function ∧ Environment.Types context.source bindings := by
  have valid := initialized_execution_preserves_closure_contracts _ _ _ _ _ initialized steps
  have stored := heap_lookup _ _ _ _ found valid
  have environments := EnvironmentInventory.initialized_execution_preserves_environment_types _ _ _ _ _ initialized steps
  have values := EnvironmentInventory.lookup_types _ _ _ _ found environments
  exact ⟨stored.1, stored.2, values⟩

theorem reachable_closure_signature (context : Context) (arguments : List SemanticValue) (before machine : State)
    (events : List Event) (initialized : initial context arguments = .ok before) (steps : Steps context before events machine)
    (node : NodeId) (schema : SchemaId .source) (function : FunctionId .source) (bindings : Environment)
    (found : machine.heap.lookup node = some (.closure schema function bindings)) :
    ∃ signature definition,
      context.source.schemas[schema.value]? = some (.internal (.computation signature)) ∧
      context.source.functions[function.value]? = some definition ∧
      Admission.variableTypes context.source definition.parameters = some signature.parameters ∧
      definition.result = signature.result ∧
      definition.effects.all signature.effects.contains = true ∧
      definition.regions = signature.regions ∧
      bindings.map Binding.var = Analysis.captures context.captures function ∧
      ∀ binding ∈ bindings,
        context.source.variables[binding.var.value]? = some binding.located.value.schema ∧
        signature.captureBound.contains binding.located.value.schema = true := by
  obtain ⟨admitted, binders, environments⟩ := reachable_closure_contract _ _ _ _ _ initialized steps _ _ _ _ found
  obtain ⟨signature, shape⟩ := admitted_lambda_has_computation_schema _ _ _ _ admitted
  have fields := environment_variable_types context.source bindings environments
  rw [binders] at fields
  simp only [Admission.lambdaValid, shape, bind, Option.bind_some] at admitted
  cases functionAt : context.source.functions[function.value]? with
  | none => simp [functionAt] at admitted
  | some definition =>
    simp only [functionAt, Option.bind_some, fields, pure, Option.getD_some, Bool.and_eq_true, beq_iff_eq] at admitted
    refine ⟨signature, definition, shape, rfl, admitted.1.1.1.1, admitted.1.1.1.2,
      admitted.1.1.2, admitted.1.2, binders, ?_⟩
    intro binding member
    exact ⟨environments binding member, List.all_eq_true.mp admitted.2 _ (List.mem_map.mpr ⟨binding, member, rfl⟩)⟩
end ClosureContracts
end BoundaryV2.Profile.Source.Machine
