import BoundaryV2.SourceValueTypes

namespace BoundaryV2.Profile.Source.Machine

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem lookupVariable_preserves_all (bindings : Environment) (binder : VariableId) (value : Located)
    (found : lookupVariable bindings binder = some value) (property : SemanticValue → Prop)
    (holds : ∀ binding ∈ bindings, property binding.located.value) : property value.value := by
  simp only [lookupVariable, Option.map_eq_some_iff] at found
  obtain ⟨binding, found, rfl⟩ := found
  exact holds binding (List.mem_of_find?_eq_some found)

theorem captured_values_preserve_all (bindings : Environment) (vars : List VariableId) (values : List Located)
    (accepted : vars.mapM (fun binder => fromOption (lookupVariable bindings binder) .reference) = .ok values)
    (property : SemanticValue → Prop) (holds : ∀ binding ∈ bindings, property binding.located.value) :
    ∀ value ∈ values, property value.value := by
  induction vars generalizing values with
  | nil => simp only [List.mapM_nil, pure, Except.pure, Except.ok.injEq] at accepted; cases accepted; simp
  | cons binder rest induction =>
    simp only [List.mapM_cons, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨value, found, tail, tailFound, rfl⟩ := accepted
    intro child member
    rcases List.mem_cons.mp member with rfl | member
    · exact lookupVariable_preserves_all bindings binder child found property holds
    · exact induction tail tailFound child member

theorem checked_context_checks_value (context : Context) (reference : SourceValueId) (value : Source.Value)
    (typed : context.typingValid = true) (found : context.source.values[reference.value]? = some value) :
    Admission.primitiveValid context.source context.captures value = true := by
  simp only [Context.typingValid, Option.any_eq_true] at typed
  obtain ⟨results, _, admitted⟩ := typed
  exact Admission.primitives_checks_unreachable_value _ _
    (Admission.typed_checks_all_declarations _ _ _ _ admitted).2.1 value (List.mem_of_getElem? found)

theorem admitted_lambda_has_computation_schema (source : Module) (facts : Analysis.Facts)
    (function : FunctionId .source) (schema : SchemaId .source)
    (accepted : Admission.lambdaValid source facts function schema = true) :
    ∃ signature, source.schemas[schema.value]? = some (.internal (.computation signature)) := by
  cases found : source.schemas[schema.value]? with
  | none => simp [Admission.lambdaValid, found] at accepted
  | some shape =>
    cases shape <;> simp [Admission.lambdaValid, found] at accepted
    rename_i inner
    cases inner <;> simp at accepted
    exact ⟨_, rfl⟩

theorem makeClosure_preserves_value_shapes (state : State) (context : Context)
    (schema : SchemaId .source) (signature : ComputationType .source) (function : FunctionId .source)
    (bindings : Environment) (after : Transition)
    (shape : context.source.schemas[schema.value]? = some (.internal (.computation signature)))
    (accepted : makeClosure state context schema function bindings = .ok after)
    (typed : ValueInventory.All (ValueShape context.source.schemas) state)
    (inputs : ∀ binding ∈ bindings, ValueShape context.source.schemas binding.located.value) :
    ValueInventory.All (ValueShape context.source.schemas) after.state := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  obtain ⟨values, captured, accepted⟩ := accepted
  exact closure_creation_preserves_value_shapes state context schema signature function values after shape accepted typed
    (captured_values_preserve_all bindings _ values captured _ inputs)

private theorem finishValue_preserves_all (state : State) (value : Located) (property : SemanticValue → Prop)
    (holds : ValueInventory.All property state) (valueHolds : property value.value) :
    ValueInventory.All property (finishValue state value).state := by
  simp only [finishValue, ValueInventory.All, ValueInventory.state, ValueInventory.control,
    List.mem_append, List.mem_singleton] at holds ⊢
  grind only []

/-- The full expression-entry dispatcher preserves finite value typing.
Lambda schema facts and literal values come from checked source admission. -/
theorem enterExpression_preserves_value_shapes (state : State) (context : Context) (after : Transition)
    (accepted : enterExpression state context = .ok after) (contextTyped : context.typingValid = true)
    (typed : ValueInventory.All (ValueShape context.source.schemas) state) :
    ValueInventory.All (ValueShape context.source.schemas) after.state := by
  unfold enterExpression at accepted
  split at accepted <;> try contradiction
  rename_i reference bindings control
  have bindingsTyped : ∀ binding ∈ bindings, ValueShape context.source.schemas binding.located.value := by
    intro binding member
    apply typed binding.located.value
    simp only [ValueInventory.state, control, ValueInventory.control, ValueInventory.environment]
    exact List.mem_append_left _ (List.mem_append_left _ (List.mem_append_left _ (List.mem_map.mpr ⟨binding, member, rfl⟩)))
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨schema, expression⟩, found, accepted⟩ := accepted
  have admitted := checked_context_checks_value context reference _ contextTyped found
  cases expression with
  | «variable» binder =>
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨value, foundValue, _, _, _, _, rfl⟩ := accepted
    exact finishValue_preserves_all state value _ typed
      (lookupVariable_preserves_all bindings binder value foundValue _ bindingsTyped)
  | literal constant =>
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨value, foundValue, _, _, accepted⟩ := accepted
    exact ValueInventory.scopedValue_preserves_all _ _ _ accepted _ typed
      (external_value_has_shape _ _ ((checked_context_constants_are_external context contextTyped)
        value (List.mem_of_getElem? foundValue)))
  | lambda function =>
    obtain ⟨signature, shape⟩ := admitted_lambda_has_computation_schema context.source context.captures function schema admitted
    exact makeClosure_preserves_value_shapes state context schema signature function bindings after shape accepted typed bindingsTyped
  | primitive opcode operands immediate failures =>
    cases operands with
    | nil =>
      cases accepted
      simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control,
        List.map_nil, List.append_nil, List.mem_append] at typed ⊢
      grind only []
    | cons first rest =>
      cases accepted
      simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.frame,
        List.flatMap_cons, List.map_nil, List.append_nil, List.mem_append] at typed ⊢
      grind only []

end BoundaryV2.Profile.Source.Machine
