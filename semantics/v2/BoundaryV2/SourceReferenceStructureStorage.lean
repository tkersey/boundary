import BoundaryV2.SourceReferenceStructure
import BoundaryV2.SourcePrimitiveTypes

namespace BoundaryV2.Profile.Source.Machine
namespace ReferenceStructureContracts

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

theorem closure_creation_preserves_reference_structure (state : State) (context : Context)
    (schema : SchemaId .source) (signature : ComputationType .source) (function : FunctionId .source)
    (values : List Located) (after : Transition)
    (shape : context.source.schemas[schema.value]? = some (.internal (.computation signature)))
    (accepted : makeClosureWithValues state context schema function values = .ok after)
    (typed : ValueInventory.All (ValueStructure context.source.schemas) state)
    (inputs : ∀ value ∈ values, ValueStructure context.source.schemas value.value) :
    ValueInventory.All (ValueStructure context.source.schemas) after.state := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, ⟨middle, owner⟩, temporaryAccepted, moved, moveAccepted, ⟨heap, result⟩, allocated, finished⟩ := accepted
  have middleTyped := ValueInventory.temporary_preserves_all _ _ _ temporaryAccepted _ typed
  have movedTyped := ValueInventory.moveValues_preserves_all _ _ _ _ moveAccepted _ middleTyped
  have storedTyped : ∀ child ∈ ValueInventory.object (.closure schema function
      (((Analysis.captures context.captures function).zip values).mapIdx (fun index (binder, value) =>
        Binding.mk binder (retainAt value (.closure ⟨middle.heap.objects.length⟩ index))))),
      ValueStructure context.source.schemas child := by
    intro child member
    simp only [ValueInventory.object, ValueInventory.environment, List.mapIdx_eq_zipIdx_map,
      List.map_map, Function.comp_def, List.mem_map, retainAt] at member
    obtain ⟨⟨⟨binder, value⟩, index⟩, pairMember, rfl⟩ := member
    exact inputs value (List.of_mem_zip (List.fst_mem_of_mem_zipIdx pairMember)).2
  have allocatedTyped := ValueInventory.allocateObject_preserves_all _ _ _ _ _ _ _ allocated _ movedTyped storedTyped
  have resultTyped := typed_has_reference_structure _ _ (computation_allocation_value_shape _ _ _ _ signature _ _ _ _ shape allocated)
  exact ValueInventory.finishTemporary_preserves_all _ _ _ finished _ allocatedTyped resultTyped

theorem makeClosure_preserves_reference_structure (state : State) (context : Context)
    (schema : SchemaId .source) (signature : ComputationType .source) (function : FunctionId .source)
    (bindings : Environment) (after : Transition)
    (shape : context.source.schemas[schema.value]? = some (.internal (.computation signature)))
    (accepted : makeClosure state context schema function bindings = .ok after)
    (typed : ValueInventory.All (ValueStructure context.source.schemas) state)
    (inputs : ∀ binding ∈ bindings, ValueStructure context.source.schemas binding.located.value) :
    ValueInventory.All (ValueStructure context.source.schemas) after.state := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  obtain ⟨values, captured, accepted⟩ := accepted
  exact closure_creation_preserves_reference_structure state context schema signature function values after shape accepted typed
    (captured_values_preserve_all bindings _ values captured _ inputs)

private theorem finishValue_preserves_all (state : State) (value : Located) (property : SemanticValue → Prop)
    (holds : ValueInventory.All property state) (valueHolds : property value.value) :
    ValueInventory.All property (finishValue state value).state := by
  simp only [finishValue, ValueInventory.All, ValueInventory.state, ValueInventory.control,
    List.mem_append, List.mem_singleton] at holds ⊢
  grind only []

/-- Expression entry preserves catalog paths to reference leaves, using
admitted lambda schemas and literal values. -/
theorem enterExpression_preserves_reference_structure (state : State) (context : Context) (after : Transition)
    (accepted : enterExpression state context = .ok after) (contextTyped : context.typingValid = true)
    (typed : ValueInventory.All (ValueStructure context.source.schemas) state) :
    ValueInventory.All (ValueStructure context.source.schemas) after.state := by
  unfold enterExpression at accepted
  split at accepted <;> try contradiction
  rename_i reference bindings control
  have bindingsTyped : ∀ binding ∈ bindings, ValueStructure context.source.schemas binding.located.value := by
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
      (typed_has_reference_structure _ _ (external_value_has_shape _ _ ((checked_context_constants_are_external context contextTyped)
        value (List.mem_of_getElem? foundValue))))
  | lambda function =>
    obtain ⟨signature, shape⟩ := admitted_lambda_has_computation_schema context.source context.captures function schema admitted
    exact makeClosure_preserves_reference_structure state context schema signature function bindings after shape accepted typed bindingsTyped
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

set_option maxRecDepth 4096 in
set_option maxHeartbeats 1600000 in
theorem heapPrimitive_preserves_reference_structure (machine : State) (context : Context)
    (operation : Primitives.GraphOperation) (schema : SchemaId .source) (immediate : Nat)
    (operands : List Located) (after : Transition)
    (accepted : heapPrimitive machine context operation schema immediate operands = .ok after)
    (contextTyped : context.typingValid = true)
    (typed : ValueInventory.All (ValueStructure context.source.schemas) machine)
    (inputs : ∀ value ∈ operands, ValueStructure context.source.schemas value.value) :
    ValueInventory.All (ValueStructure context.source.schemas) after.state := by
  cases operation <;> simp only [heapPrimitive, bind, except_bind_ok, fromOption_ok] at accepted
  case computation =>
    obtain ⟨⟨function, expected⟩, constructorAt, _, checked, accepted⟩ := accepted
    have same : schema = expected := by simpa using require_ok _ _ _ checked
    subst expected
    obtain ⟨signature, found⟩ := checked_constructor_has_computation_schema context immediate function schema contextTyped constructorAt
    exact closure_creation_preserves_reference_structure _ _ _ signature _ _ _ found accepted typed inputs
  case cellNew =>
    split at accepted <;> try contradiction
    rename_i regionValue initial
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, object⟩, looked, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨shape, found, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, ⟨middle, owner⟩, temporaryOk, moved, moveOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have middleTyped := ValueInventory.temporary_preserves_all _ _ _ temporaryOk _ typed
    have movedTyped := ValueInventory.moveValues_preserves_all _ _ _ _ moveOk _ middleTyped
    have initialTyped := inputs initial (by simp)
    have allocatedTyped := ValueInventory.allocateObject_preserves_all
      { middle with heap := { moved with nextCell := moved.nextCell + 1 } } _ _ _ _ _ _ allocated _ movedTyped
      (by simpa only [ValueInventory.object, retainAt, List.mem_singleton, forall_eq] using initialTyped)
    have resultTyped : ValueStructure context.source.schemas result.value := by
      rw [ValueInventory.allocateObject_result _ _ _ _ _ _ _ allocated]
      apply typed_has_reference_structure
      exact .reference found rfl
    exact ValueInventory.finishTemporary_preserves_all _ _ _ finished _ allocatedTyped resultTyped
  case cellGet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, object⟩, looked, accepted⟩ := accepted
    split at accepted <;> try contradiction
    rename_i storedNode identity cellSchema region content matched
    cases matched
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    have contentsTyped := ValueInventory.lookupObject_preserves_all _ _ _ _ looked _ typed
    exact ValueInventory.scopedValue_preserves_all _ _ _ accepted _ typed
      (contentsTyped content.value (by simp [ValueInventory.object]))
  case cellSet =>
    split at accepted <;> try contradiction
    rename_i value replacement
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, object⟩, looked, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, shape, found, _, checked, store, replaced, accepted⟩ := accepted
    have unitIs : shape = .unit := by simpa using require_ok _ _ _ checked
    have unitAt : context.source.schemas[schema.value]? = some .unit := by simpa only [unitIs] using found
    have storeTyped := ValueInventory.replaceObject_preserves_all _ _ _ _ replaced _ typed
      (by simpa only [ValueInventory.object, retainAt, List.mem_singleton, forall_eq] using inputs replacement (by simp))
    exact ValueInventory.scopedValue_preserves_all _ _ _ accepted _ storeTyped (typed_has_reference_structure _ _ (.scalar unitAt rfl))
  case package =>
    split at accepted <;> try contradiction
    rename_i value
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, object⟩, looked, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨shape, found, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, ⟨middle, owner⟩, temporaryOk, moved, moveOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have middleTyped := ValueInventory.temporary_preserves_all _ _ _ temporaryOk _ typed
    have movedTyped := ValueInventory.moveValues_preserves_all _ _ _ _ moveOk _ middleTyped
    have allocatedTyped := ValueInventory.allocateObject_preserves_all _ _ _ _ _ _ _ allocated _ movedTyped
      (by simpa only [ValueInventory.object, retainAt, List.mem_singleton, forall_eq] using inputs value (by simp))
    have resultTyped : ValueStructure context.source.schemas result.value := by
      rw [ValueInventory.allocateObject_result _ _ _ _ _ _ _ allocated]
      apply typed_has_reference_structure
      exact .reference found rfl
    exact ValueInventory.finishTemporary_preserves_all _ _ _ finished _ allocatedTyped resultTyped
  case unpack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, object⟩, looked, accepted⟩ := accepted
    split at accepted <;> try contradiction
    rename_i storedNode storedSchema content matched
    cases matched
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, store, retired, accepted⟩ := accepted
    have storeTyped := ValueInventory.retireObject_preserves_all _ _ _ retired _ typed
    have contentsTyped := ValueInventory.lookupObject_preserves_all _ _ _ _ looked _ typed
    exact ValueInventory.commitPure_preserves_all _ _ _ _ _ accepted _ storeTyped
      (contentsTyped content.value (by simp [ValueInventory.object]))
  case cloneResumption =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, object⟩, looked, accepted⟩ := accepted
    split at accepted <;> try contradiction
    rename_i storedNode capture matched
    cases matched
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨sourceShape, sourceAt, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨resultShape, resultAt, accepted⟩ := accepted
    split at accepted <;> try contradiction
    rename_i resultSignature
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, checked, _, _, retired, retireOk, ⟨middle, owner⟩, temporaryOk,
      ⟨store, result⟩, allocated, finished⟩ := accepted
    have resultIs := (Bool.and_eq_true_iff.mp (require_ok _ _ _ checked)).2
    have resultMulti : resultSignature.use = .multi := by
      have exactSignature := of_decide_eq_true resultIs
      rw [exactSignature]
    have captureTyped := ValueInventory.lookupObject_preserves_all _ _ _ _ looked _ typed
    have retiredTyped := ValueInventory.retireObject_preserves_all _ _ _ retireOk _ typed
    have middleTyped := ValueInventory.temporary_preserves_all _ _ _ temporaryOk _ retiredTyped
    have allocatedTyped := ValueInventory.allocateObject_preserves_all _ _ _ _ _ _ _ allocated _ middleTyped captureTyped
    have resultTyped : ValueStructure context.source.schemas result.value := by
      rw [ValueInventory.allocateObject_result _ _ _ _ _ _ _ allocated]
      apply typed_has_reference_structure
      exact .reference resultAt (by simp [ReferenceOwnership, resultMulti])
    exact ValueInventory.finishTemporary_preserves_all _ _ _ finished _ allocatedTyped resultTyped
  case resourcePack =>
    split at accepted <;> try contradiction
    rename_i value
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨shape, found, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, ⟨middle, owner⟩, temporaryOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have middleTyped := ValueInventory.temporary_preserves_all _ _ _ temporaryOk _ typed
    have allocatedTyped := ValueInventory.allocateObject_preserves_all _ _ _ _ _ _ _ allocated _ middleTyped
      (by simpa only [ValueInventory.object, retainAt, List.mem_singleton, forall_eq] using inputs value (by simp))
    have resultTyped : ValueStructure context.source.schemas result.value := by
      rw [ValueInventory.allocateObject_result _ _ _ _ _ _ _ allocated]
      apply typed_has_reference_structure
      exact .reference found rfl
    exact ValueInventory.finishTemporary_preserves_all _ _ _ finished _ allocatedTyped resultTyped
  case resourceUnpack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨shape, _, resourceShape, resourceAt, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨resource, resourceAt, invocation, invocationAt, _, checked, ⟨node, object⟩, looked, accepted⟩ := accepted
    split at accepted
    · rename_i storedSchema content matched
      cases matched
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, store, retired, accepted⟩ := accepted
      have storeTyped := ValueInventory.retireObject_preserves_all _ _ _ retired _ typed
      have contentsTyped := ValueInventory.lookupObject_preserves_all _ _ _ _ looked _ typed
      exact ValueInventory.scopedValue_preserves_all _ _ _ accepted _ storeTyped
        (contentsTyped content.value (by simp [ValueInventory.object]))
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨identity, _, obligation, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, stored, storedAt, accepted⟩ := accepted
      split at accepted <;> try contradiction
      rename_i storedSchema content
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      have contentsTyped := ValueInventory.lookup_preserves_all _ _ _ storedAt _ typed
      exact ValueInventory.scopedValue_preserves_all _ _ _ accepted _ typed
        (contentsTyped content.value (by simp [ValueInventory.object]))
    · contradiction

theorem executePrimitive_preserves_reference_structure (machine : State) (context : Context) (after : Transition)
    (accepted : executePrimitive machine context = .ok after) (contextTyped : context.typingValid = true)
    (typed : ValueInventory.All (ValueStructure context.source.schemas) machine) :
    ValueInventory.All (ValueStructure context.source.schemas) after.state := by
  unfold executePrimitive at accepted
  split at accepted <;> try contradiction
  rename_i schema opcode immediate failures bindings operands executing
  have inputs : ∀ value ∈ operands, ValueStructure context.source.schemas value.value := by
    intro value member
    apply typed
    simp only [ValueInventory.state, executing, ValueInventory.control, List.mem_append, List.mem_map]
    exact Or.inl (Or.inl (Or.inl (Or.inr ⟨value, member, rfl⟩)))
  have constantsTyped : ∀ value ∈ context.executionConstants, ValueStructure context.source.schemas value :=
    fun value member => typed_has_reference_structure _ _ (checked_execution_constants_have_value_shapes context contextTyped value member)
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · contradiction
  · exact ValueInventory.authoredFailure_preserves_all _ _ _ _ _ accepted _ typed constantsTyped
  · rename_i value evaluated
    have valueTyped := primitive_preserves_reference_structure context.source.schemas context.executionConstants
      opcode schema immediate (operands.map Located.value) value constantsTyped (by
        intro child member
        obtain ⟨original, belongs, rfl⟩ := List.mem_map.mp member
        exact inputs original belongs) evaluated
    exact ValueInventory.commitPure_preserves_all _ _ _ _ _ accepted _ typed valueTyped
  · exact heapPrimitive_preserves_reference_structure _ _ _ _ _ _ _ accepted contextTyped typed inputs

end ReferenceStructureContracts
end BoundaryV2.Profile.Source.Machine
