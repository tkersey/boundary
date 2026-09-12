import BoundaryV2.SourceLexicalExecution
import BoundaryV2.SourceIdentityExecution
import BoundaryV2.SourceValueExecution
import BoundaryV2.SourceEnvironmentExecution

namespace BoundaryV2.Profile.Source.Machine
namespace EntryProgress

private theorem initialized_typing (context : Context) (arguments : List SemanticValue)
    (before : State) (initialized : initial context arguments = .ok before) : context.typingValid = true := by
  simpa only [Context.typingValid, Option.any_eq_true] using initial_checks_typing _ _ _ initialized

theorem term (machine : State) (source : Module) (reference : TermId) (bindings : Environment)
    (authored : Source.Term) (executing : machine.control = .term reference bindings)
    (found : source.terms[reference.value]? = some authored) :
    ∃ after, enterTerm machine source = .ok after := by
  cases authored <;> simp only [enterTerm, executing, found]
  all_goals repeat' split
  all_goals exact ⟨_, rfl⟩

theorem scopedValue (machine : State) (value : SemanticValue) (scope : Scope)
    (found : machine.heap.scopes[machine.scope.value]? = some scope) (identity : scope.id = machine.scope) :
    ∃ after, Machine.scopedValue machine value = .ok after := by
  have bounded := (List.getElem?_eq_some_iff.mp found).1
  simp [Machine.scopedValue, temporary, found, identity, finishTemporary,
    bind, Except.bind, pure, Except.pure, List.getElem?_set_self bounded]

theorem literal_value (context : Context) (reference : SourceValueId) (schema : SchemaId .source)
    (constant : ConstantId .source) (typed : context.typingValid = true)
    (found : context.source.values[reference.value]? = some ⟨schema, .literal constant⟩) :
    ∃ value, context.constants[constant.value]? = some value ∧ value.schema = schema := by
  have literalTyped : (context.source.constants[constant.value]?).map Literal.schema = some schema := by
    simpa only [Admission.primitiveValid, beq_iff_eq] using checked_context_checks_value context reference _ typed found
  obtain ⟨literal, literalAt, literalSchema⟩ := Option.map_eq_some_iff.mp literalTyped
  simp only [Context.typingValid, Option.any_eq_true] at typed
  obtain ⟨results, _, admitted⟩ := typed
  have declarations := (Admission.typed_checks_all_declarations _ _ _ _ admitted).1
  simp only [Admission.declarationsValid, Bool.and_eq_true] at declarations
  have constants := Admission.constants_exact _ _ declarations.1.1.1.1.1.2
  have bounded : constant.value < context.constants.length := by
    rw [← constants.1]
    exact (List.getElem?_eq_some_iff.mp literalAt).1
  let value := context.constants[constant.value]
  have valueAt : context.constants[constant.value]? = some value := List.getElem?_eq_getElem bounded
  exact ⟨value, valueAt, (constants.2 _ _ _ literalAt valueAt).1.trans literalSchema⟩

theorem literal (machine : State) (context : Context) (reference : SourceValueId) (bindings : Environment)
    (schema : SchemaId .source) (constant : ConstantId .source) (scope : Scope)
    (executing : machine.control = .expression reference bindings)
    (found : context.source.values[reference.value]? = some ⟨schema, .literal constant⟩)
    (typed : context.typingValid = true)
    (scopeAt : machine.heap.scopes[machine.scope.value]? = some scope) (identity : scope.id = machine.scope) :
    ∃ after, enterExpression machine context = .ok after := by
  obtain ⟨value, valueAt, valueSchema⟩ := literal_value _ _ _ _ typed found
  simpa [enterExpression, executing, found, fromOption, require, valueAt, valueSchema,
    bind, Except.bind, pure, Except.pure] using scopedValue machine value scope scopeAt identity

theorem primitive_operands (machine : State) (context : Context) (reference : SourceValueId)
    (bindings : Environment) (schema : SchemaId .source) (opcode : Opcode) (operands : List SourceValueId)
    (immediate : Nat) (failures : List (InstructionFailure .source))
    (executing : machine.control = .expression reference bindings)
    (found : context.source.values[reference.value]? = some ⟨schema, .primitive opcode operands immediate failures⟩) :
    ∃ after, enterExpression machine context = .ok after := by
  cases operands <;> simp [enterExpression, executing, found, fromOption, bind, Except.bind, pure, Except.pure]

theorem delivered_operand (machine : State) (value : Located) (intent : Intent) (bindings : Environment)
    (remaining : List SourceValueId) (evaluated : List Located) (tail : List Frame)
    (executing : machine.control = .delivered value)
    (stacked : machine.stack = .operands intent bindings remaining evaluated :: tail) :
    ∃ after, deliverOperand machine = .ok after := by
  cases remaining <;> simp [deliverOperand, executing, stacked, pure, Except.pure]

theorem reachable_term (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (reference : TermId) (bindings : Environment)
    (executing : machine.control = .term reference bindings) (running : machine.status = .running) :
    ∃ after, tick machine context = .ok after := by
  obtain ⟨authored, found⟩ := LexicalCoverage.reachable_term_has_source _ _ _ _ _ initialized steps _ _ executing
  simpa only [tick, running, tickRunning, executing] using term machine context.source reference bindings authored executing found

theorem reachable_literal (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (reference : SourceValueId) (bindings : Environment)
    (schema : SchemaId .source) (constant : ConstantId .source)
    (executing : machine.control = .expression reference bindings)
    (found : context.source.values[reference.value]? = some ⟨schema, .literal constant⟩)
    (running : machine.status = .running) : ∃ after, tick machine context = .ok after := by
  obtain ⟨scope, scopeAt, identity⟩ := (IdentitySupport.initialized_execution_has_current_records _ _ _ _ _ initialized steps).1
  simpa only [tick, running, tickRunning, executing] using
    literal machine context reference bindings schema constant scope executing found
      (initialized_typing _ _ _ initialized) scopeAt identity

/-- Reachability supplies both the lexical binding and its exact source schema.
Live ownership is a separate condition for a noncopyable variable. -/
theorem reachable_variable_value (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (reference : SourceValueId) (bindings : Environment)
    (schema : SchemaId .source) (var : VariableId)
    (executing : machine.control = .expression reference bindings)
    (found : context.source.values[reference.value]? = some ⟨schema, .variable var⟩) :
    ∃ value, lookupVariable bindings var = some value ∧ value.value.schema = schema ∧
      ValueShape context.source.schemas value.value := by
  obtain ⟨value, valueAt⟩ := LexicalCoverage.reachable_variable_has_binding _ _ _ _ _ initialized steps _ _ _ _ executing found
  have declared : context.source.variables[var.value]? = some schema := by
    simpa only [Admission.primitiveValid, beq_iff_eq] using
      checked_context_checks_value context reference _ (initialized_typing _ _ _ initialized) found
  have envTyped : Environment.Types context.source bindings := by
    simpa only [EnvironmentInventory.control, executing] using
      EnvironmentInventory.control_types _ _ (EnvironmentInventory.initialized_execution_preserves_environment_types _ _ _ _ _ initialized steps)
  have same := Option.some.inj ((envTyped.lookup var value valueAt).symm.trans declared)
  have values := initialized_execution_preserves_value_shapes _ _ _ _ _ initialized steps
  refine ⟨value, valueAt, same, ?_⟩
  apply lookupVariable_preserves_all bindings var value valueAt
  intro binding member
  apply values
  simp only [ValueInventory.state, executing, ValueInventory.control, ValueInventory.environment,
    List.mem_append, List.mem_map]
  exact Or.inl (Or.inl (Or.inl ⟨binding, member, rfl⟩))

theorem reachable_variable_result (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (reference : SourceValueId) (bindings : Environment)
    (schema : SchemaId .source) (var : VariableId)
    (executing : machine.control = .expression reference bindings)
    (found : context.source.values[reference.value]? = some ⟨schema, .variable var⟩) :
    ∃ value, lookupVariable bindings var = some value ∧ value.value.schema = schema ∧
      enterExpression machine context = if current machine.heap value then .ok (finishValue machine value) else .error .custody := by
  obtain ⟨value, valueAt, same, _⟩ := reachable_variable_value _ _ _ _ _ initialized steps _ _ _ _ executing found
  refine ⟨value, valueAt, same, ?_⟩
  cases active : current machine.heap value <;>
    simp [enterExpression, executing, found, fromOption, require, valueAt, same, active, bind, Except.bind, pure, Except.pure]

/-- A copyable variable needs no live exclusive token. Initialization and the
proved trajectory invariants suffice for the actual transition to succeed. -/
theorem reachable_copy_variable (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (reference : SourceValueId) (bindings : Environment)
    (schema : SchemaId .source) (var : VariableId)
    (executing : machine.control = .expression reference bindings)
    (found : context.source.values[reference.value]? = some ⟨schema, .variable var⟩)
    (copy : Traits.check context.source.schemas .copy schema = true)
    (running : machine.status = .running) : ∃ after, tick machine context = .ok after := by
  obtain ⟨value, valueAt, same, valueTyped⟩ := reachable_variable_value _ _ _ _ _ initialized steps _ _ _ _ executing found
  have noTokens := copy_value_has_no_tokens _ _ valueTyped
    (Traits.check_sound _ _ _ (by simpa only [same] using copy))
  simp [tick, running, tickRunning, executing, enterExpression, found, fromOption, require,
    valueAt, same, current, noTokens, bind, Except.bind, pure, Except.pure]

theorem reachable_release (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (scope : LexicalScopeId) (released : AfterRelease)
    (executing : machine.control = .release scope released) (running : machine.status = .running) :
    ∃ after, tick machine context = .ok after := by
  have bounded := IdentitySupport.initialized_execution_preserves_identity_bounds _ _ _ _ _ initialized steps
  have indexed := source_trajectory_indices _ _ _ _ initialized steps
  have scopeBound : IdentitySupport.Bound (IdentitySupport.limits machine.heap) scope := by
    simpa only [IdentitySupport.ControlValid, executing] using bounded.control
  obtain ⟨record, recordAt, identity⟩ := IdentitySupport.scope_record_exists indexed scope scopeBound
  simp [tick, running, tickRunning, executing, releaseScope, recordAt, identity,
    fromOption, require, bind, Except.bind, pure, Except.pure]

theorem empty_discard (machine : State) (context : Context) (released : AfterRelease)
    (executing : machine.control = .discard [] released) (running : machine.status = .running) :
    ∃ after, tick machine context = .ok after := by
  simp [tick, running, tickRunning, executing, discardValues, pure, Except.pure]

theorem disposal_return (machine : State) (context : Context) (value : Located)
    (remaining : List Located) (released : AfterRelease) (invocation : InvocationId)
    (scope : LexicalScopeId) (tail : List Frame) (executing : machine.control = .delivered value)
    (stacked : machine.stack = .disposalReturn remaining released invocation scope :: tail)
    (running : machine.status = .running) : ∃ after, tick machine context = .ok after := by
  simp [tick, running, tickRunning, executing, stacked, finishDisposal, pure, Except.pure]

theorem primitive_operands_tick (machine : State) (context : Context) (reference : SourceValueId)
    (bindings : Environment) (schema : SchemaId .source) (opcode : Opcode) (operands : List SourceValueId)
    (immediate : Nat) (failures : List (InstructionFailure .source))
    (executing : machine.control = .expression reference bindings)
    (found : context.source.values[reference.value]? = some ⟨schema, .primitive opcode operands immediate failures⟩)
    (running : machine.status = .running) : ∃ after, tick machine context = .ok after := by
  simpa only [tick, running, tickRunning, executing] using
    primitive_operands machine context reference bindings schema opcode operands immediate failures executing found

theorem delivered_operand_tick (machine : State) (context : Context) (value : Located)
    (intent : Intent) (bindings : Environment) (remaining : List SourceValueId) (evaluated : List Located)
    (tail : List Frame) (executing : machine.control = .delivered value)
    (stacked : machine.stack = .operands intent bindings remaining evaluated :: tail)
    (running : machine.status = .running) : ∃ after, tick machine context = .ok after := by
  simpa only [tick, running, tickRunning, executing, stacked] using
    delivered_operand machine value intent bindings remaining evaluated tail executing stacked

end EntryProgress
end BoundaryV2.Profile.Source.Machine
