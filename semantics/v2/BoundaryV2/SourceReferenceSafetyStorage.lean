import BoundaryV2.SourceReferenceSafetyValues

namespace BoundaryV2.Profile.Source.Machine
namespace ReferenceSafety
open ReferenceContracts

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

theorem retirement_shape (before after : Heap) (retired : Located)
    (accepted : retireObject before retired = some after) (modes : ValueModes schemas retired.value) :
    ValueShape schemas retired.value := by
  obtain ⟨schema, node, token, shape, _⟩ := retire_lookup _ _ _ accepted
  simpa only [shape, ValueModes, Primitives.ReferencesSatisfy] using modes

theorem scalar_good (schemas : List (Schema .source)) (heap : Heap) (schema : SchemaId .source) (bits : Nat) :
    ValueGood schemas heap (.scalar schema bits) := by
  simp [ValueGood, ValueValid, Primitives.ReferencesSatisfy, ValueAligned, ownedReferences,
    ValueTokensBounded, ownedTokens]

theorem lookup_good (machine : State) (value : Located) (node : NodeId) (stored : Object)
    (accepted : lookupObject machine value = .ok (node, stored)) (good : Valid schemas machine) :
    ∀ child ∈ ValueInventory.object stored, ValueGood schemas machine.heap child :=
  ValueInventory.lookupObject_preserves_all _ _ _ _ accepted _ good.values

theorem nextCell_valid (machine : State) (count : Nat) (good : Valid schemas machine) :
    Valid schemas {machine with heap := {machine.heap with nextCell := count}} := ⟨good.values, good.live⟩

theorem closure_creation_valid (state : State) (context : Context)
    (schema : SchemaId .source) (function : FunctionId .source) (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues state context schema function values = .ok after)
    (good : Valid context.source.schemas state)
    (inputs : ∀ value ∈ values, ValueGood context.source.schemas state.heap value.value) :
    Valid context.source.schemas after.state := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, ⟨middle, owner⟩, temporaryOk, moved, moveOk, ⟨heap, result⟩, allocated, finished⟩ := accepted
  have middleGood := temporary_valid _ _ _ temporaryOk good
  have movedGood := move_valid _ _ _ _ moveOk middleGood
  have movedInputs : ∀ value ∈ values, ValueGood context.source.schemas moved value.value :=
    fun value member => move_value _ _ _ _ _ moveOk (temporary_value _ _ _ _ temporaryOk (inputs value member))
  have storedGood : ∀ child ∈ ValueInventory.object (.closure schema function
      (((Analysis.captures context.captures function).zip values).mapIdx (fun index (binder, value) =>
        Binding.mk binder (retainAt value (.closure ⟨middle.heap.objects.length⟩ index))))),
      ValueGood context.source.schemas moved child := by
    intro child member
    simp only [ValueInventory.object, ValueInventory.environment, List.mapIdx_eq_zipIdx_map,
      List.map_map, Function.comp_def, List.mem_map, retainAt] at member
    obtain ⟨⟨⟨binder, value⟩, index⟩, pairMember, rfl⟩ := member
    exact movedInputs value (List.of_mem_zip (List.fst_mem_of_mem_zipIdx pairMember)).2
  have allocatedGood := allocation_valid _ _ _ _ _ _ _ allocated movedGood storedGood
  have resultGood := allocation_result (schemas := context.source.schemas) _ _ _ _ _ _ _ allocated (by rfl)
  exact finishTemporary_valid _ _ _ finished allocatedGood resultGood

theorem makeClosure_valid (state : State) (context : Context)
    (schema : SchemaId .source) (function : FunctionId .source) (bindings : Environment) (after : Transition)
    (accepted : makeClosure state context schema function bindings = .ok after)
    (good : Valid context.source.schemas state)
    (inputs : ∀ binding ∈ bindings, ValueGood context.source.schemas state.heap binding.located.value) :
    Valid context.source.schemas after.state := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  obtain ⟨values, captured, accepted⟩ := accepted
  exact closure_creation_valid _ _ _ _ _ _ accepted good
    (captured_values_preserve_all bindings _ values captured _ inputs)

theorem finishValue_valid (state : State) (value : Located) (good : Valid schemas state)
    (valueGood : ValueGood schemas state.heap value.value) : Valid schemas (finishValue state value).state := by
  refine ⟨?_, good.live⟩
  have holds := good.values
  simp only [finishValue, ValueInventory.All, ValueInventory.state, ValueInventory.control,
    List.mem_append, List.mem_singleton] at holds ⊢
  grind only []

theorem enterExpression_valid (state : State) (context : Context) (after : Transition)
    (accepted : enterExpression state context = .ok after) (contextTyped : context.typingValid = true)
    (good : Valid context.source.schemas state) : Valid context.source.schemas after.state := by
  unfold enterExpression at accepted
  split at accepted <;> try contradiction
  rename_i reference bindings control
  have bindingsGood : ∀ binding ∈ bindings, ValueGood context.source.schemas state.heap binding.located.value := by
    intro binding member
    apply good.values
    simp only [ValueInventory.state, control, ValueInventory.control, ValueInventory.environment]
    exact List.mem_append_left _ (List.mem_append_left _ (List.mem_append_left _ (List.mem_map.mpr ⟨binding, member, rfl⟩)))
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨schema, expression⟩, found, accepted⟩ := accepted
  cases expression with
  | «variable» binder =>
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨value, foundValue, _, _, _, _, rfl⟩ := accepted
    exact finishValue_valid _ _ good (lookupVariable_preserves_all bindings binder value foundValue _ bindingsGood)
  | literal constant =>
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨value, foundValue, _, _, accepted⟩ := accepted
    exact scopedValue_valid _ _ _ accepted good
      (admitted_value_good _ _ _ ((checked_context_constants_are_external context contextTyped) value (List.mem_of_getElem? foundValue)))
  | lambda function => exact makeClosure_valid _ _ _ _ _ _ accepted good bindingsGood
  | primitive opcode operands immediate failures =>
    cases operands with
    | nil =>
      cases accepted
      refine ⟨?_, good.live⟩
      have holds := good.values
      simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control,
        List.map_nil, List.append_nil, List.mem_append] at holds ⊢
      grind only []
    | cons first rest =>
      cases accepted
      refine ⟨?_, good.live⟩
      have holds := good.values
      simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.frame,
        List.flatMap_cons, List.map_nil, List.append_nil, List.mem_append] at holds ⊢
      grind only []

end ReferenceSafety
end BoundaryV2.Profile.Source.Machine
