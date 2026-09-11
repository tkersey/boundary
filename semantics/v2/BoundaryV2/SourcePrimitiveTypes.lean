import BoundaryV2.SourceUnwindTypes
import BoundaryV2.PrimitiveEvaluatorTypes
import BoundaryV2.PrimitiveResultSchema

namespace BoundaryV2.Profile.Source

namespace Analysis

private theorem row_member (rows : List (List α)) (index : Nat) (value : α)
    (member : value ∈ rows[index]?.getD []) : ∃ row ∈ rows, value ∈ row := by
  cases found : rows[index]? with
  | none => simp [found] at member
  | some row => exact ⟨row, List.mem_of_getElem? found, by simpa only [found, Option.getD_some] using member⟩

theorem constructor_has_lambda (source : Module) (key : ConstructorKey)
    (member : key ∈ constructors source) :
    ∃ value ∈ source.values, value.expression = .lambda key.1 ∧ value.schema = key.2 := by
  let property (key : ConstructorKey) := ∃ value ∈ source.values,
    value.expression = .lambda key.1 ∧ value.schema = key.2
  let rowsValid (rows : List (List ConstructorKey)) := ∀ row ∈ rows, ∀ key ∈ row, property key
  have valuesValid : rowsValid (valueConstructorRows source) := by
    unfold valueConstructorRows
    apply List.foldlRecOn (motive := rowsValid)
    · simp [rowsValid]
    · intro rows valid value valueMember row rowMember key keyMember
      simp only [List.map_cons, List.map_nil, List.mem_append, List.mem_singleton] at rowMember
      rcases rowMember with rowMember | rfl
      · exact valid row rowMember key keyMember
      · have member := List.mem_eraseDups.mp keyMember
        cases expression : value.expression with
        | lambda function =>
          have same : key = (function, value.schema) := by simpa only [expression, List.mem_singleton] using member
          subst key
          exact ⟨value, valueMember, expression, rfl⟩
        | primitive opcode operands immediate failures =>
          simp only [expression, List.mem_flatMap] at member
          obtain ⟨operand, _, member⟩ := member
          obtain ⟨row, rowMember, member⟩ := row_member rows operand.value key member
          exact valid row rowMember key member
        | «variable» _ | literal _ => simp [expression] at member
  have termsValid : rowsValid (constructorRows source) := by
    unfold constructorRows
    apply List.foldlRecOn (motive := rowsValid)
    · simp [rowsValid]
    · intro rows valid term _ row rowMember key keyMember
      simp only [List.map_cons, List.map_nil, List.mem_append, List.mem_singleton] at rowMember
      rcases rowMember with rowMember | rfl
      · exact valid row rowMember key keyMember
      · have member := List.mem_eraseDups.mp keyMember
        rcases List.mem_append.mp member with member | member
        · obtain ⟨child, _, member⟩ := List.mem_flatMap.mp member
          obtain ⟨row, rowMember, member⟩ := row_member rows child.value key member
          exact valid row rowMember key member
        · obtain ⟨child, _, member⟩ := List.mem_flatMap.mp member
          obtain ⟨row, rowMember, member⟩ := row_member (valueConstructorRows source) child.value key member
          exact valuesValid row rowMember key member
  simp only [constructors, List.mem_eraseDups, List.mem_flatMap] at member
  obtain ⟨function, _, body, _, member⟩ := member
  obtain ⟨row, rowMember, member⟩ := row_member (constructorRows source) body.value key member
  exact termsValid row rowMember key member

end Analysis

namespace Machine

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

theorem checked_constructor_has_computation_schema (context : Context) (index : Nat)
    (function : FunctionId .source) (schema : SchemaId .source) (typed : context.typingValid = true)
    (found : (Analysis.constructors context.source)[index]? = some (function, schema)) :
    ∃ signature, context.source.schemas[schema.value]? = some (.internal (.computation signature)) := by
  obtain ⟨value, member, expression, same⟩ := Analysis.constructor_has_lambda context.source (function, schema)
    (List.mem_of_getElem? found)
  obtain ⟨reference, foundValue⟩ := List.mem_iff_getElem?.mp member
  have admitted := checked_context_checks_value context ⟨reference⟩ value typed foundValue
  have lambda : Admission.lambdaValid context.source context.captures function schema = true := by
    simpa only [Admission.primitiveValid, expression, same] using admitted
  exact admitted_lambda_has_computation_schema _ _ function schema lambda

theorem checked_execution_constants_have_value_shapes (context : Context) (typed : context.typingValid = true) :
    ∀ value ∈ context.executionConstants, ValueShape context.source.schemas value := by
  have ordinary := checked_context_constants_are_external context typed
  intro value member
  unfold Context.executionConstants at member
  split at member
  · exact external_value_has_shape _ _ (ordinary value member)
  · rename_i index unitAt
    split at member
    · rcases List.mem_append.mp member with member | member
      · exact external_value_has_shape _ _ (ordinary value member)
      · have same := List.mem_singleton.mp member
        subst value
        obtain ⟨bounded, unit, _⟩ := List.findIdx?_eq_some_iff_getElem.mp unitAt
        have found : context.source.schemas[index]? = some .unit := by
          rw [List.getElem?_eq_getElem bounded]
          congr 1
          simpa using unit
        exact .scalar found rfl
    · exact external_value_has_shape _ _ (ordinary value member)

theorem checked_context_schemas_valid (context : Context) (typed : context.typingValid = true) :
    SchemaAdmission.valid context.source.schemas = true := by
  simp only [Context.typingValid, Option.any_eq_true] at typed
  obtain ⟨results, _, admitted⟩ := typed
  have declarations := (Admission.typed_checks_all_declarations _ _ _ _ admitted).1
  simp only [Admission.declarationsValid, Bool.and_eq_true] at declarations
  exact declarations.1.1.1.1.1.1.1

namespace ValueInventory

theorem replaceObject_preserves_all (machine : State) (node : NodeId) (stored : Object) (store : Heap)
    (accepted : replaceObject machine.heap node stored = some store) (property : SemanticValue → Prop)
    (holds : All property machine) (objectHolds : ∀ value ∈ object stored, property value) :
    All property { machine with heap := store } := by
  unfold replaceObject at accepted
  split at accepted <;> try contradiction
  cases accepted
  simp only [All, state, heap, List.mem_append, List.mem_flatMap, List.mem_map] at holds ⊢
  grind only [→ List.mem_or_eq_of_mem_set, Option.toList_some, List.mem_singleton]

theorem authoredFailure_preserves_all (machine : State) (context : Context)
    (failures : List (InstructionFailure .source)) (fault : Fault) (after : Transition)
    (accepted : authoredFailure machine context failures fault = .ok after)
    (property : SemanticValue → Prop) (holds : All property machine)
    (constants : ∀ value ∈ context.executionConstants, property value) : All property after.state := by
  simp only [authoredFailure, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨failure, _, value, valueAt, _, _, rfl⟩ := accepted
  have valueHolds := constants value (List.mem_of_getElem? valueAt)
  simp only [All, state, control, exitValues, List.mem_append, List.mem_singleton, List.append_nil] at holds ⊢
  grind only []

end ValueInventory

set_option maxRecDepth 4096 in
set_option maxHeartbeats 1600000 in
theorem heapPrimitive_preserves_value_shapes (machine : State) (context : Context)
    (operation : Primitives.GraphOperation) (schema : SchemaId .source) (immediate : Nat)
    (operands : List Located) (after : Transition)
    (accepted : heapPrimitive machine context operation schema immediate operands = .ok after)
    (contextTyped : context.typingValid = true)
    (typed : ValueInventory.All (ValueShape context.source.schemas) machine)
    (inputs : ∀ value ∈ operands, ValueShape context.source.schemas value.value) :
    ValueInventory.All (ValueShape context.source.schemas) after.state := by
  cases operation <;> simp only [heapPrimitive, bind, except_bind_ok, fromOption_ok] at accepted
  case computation =>
    obtain ⟨⟨function, expected⟩, constructorAt, _, checked, accepted⟩ := accepted
    have same : schema = expected := by simpa using require_ok _ _ _ checked
    subst expected
    obtain ⟨signature, found⟩ := checked_constructor_has_computation_schema context immediate function schema contextTyped constructorAt
    exact closure_creation_preserves_value_shapes _ _ _ signature _ _ _ found accepted typed inputs
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
    have resultTyped : ValueShape context.source.schemas result.value := by
      rw [ValueInventory.allocateObject_result _ _ _ _ _ _ _ allocated]
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
    exact ValueInventory.scopedValue_preserves_all _ _ _ accepted _ storeTyped (.scalar unitAt rfl)
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
    have resultTyped : ValueShape context.source.schemas result.value := by
      rw [ValueInventory.allocateObject_result _ _ _ _ _ _ _ allocated]
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
    have resultTyped : ValueShape context.source.schemas result.value := by
      rw [ValueInventory.allocateObject_result _ _ _ _ _ _ _ allocated]
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
    have resultTyped : ValueShape context.source.schemas result.value := by
      rw [ValueInventory.allocateObject_result _ _ _ _ _ _ _ allocated]
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

/-- Actual execution preserves value shapes when its operand schemas satisfy
the admitted primitive interface. Deriving that interface from frame typing
remains a separate source-state obligation. -/
theorem executePrimitive_preserves_value_shapes (machine : State) (context : Context)
    (schema : SchemaId .source) (opcode : Opcode) (immediate : Nat)
    (failures : List (InstructionFailure .source)) (bindings : Environment) (operands : List Located)
    (owner : FunctionId .source) (after : Transition)
    (executing : machine.control = .execute (.primitive schema opcode immediate failures) bindings operands)
    (accepted : executePrimitive machine context = .ok after)
    (contextTyped : context.typingValid = true)
    (typed : ValueInventory.All (ValueShape context.source.schemas) machine)
    (admitted : PrimitiveAdmission.operationType (Admission.primitiveContext context.source context.captures)
      owner ⟨opcode, schema, immediate, failures⟩ (operands.map (fun value => value.value.schema)) = true) :
    ValueInventory.All (ValueShape context.source.schemas) after.state := by
  have inputs : ∀ value ∈ operands, ValueShape context.source.schemas value.value := by
    intro value member
    apply typed
    simp only [ValueInventory.state, executing, ValueInventory.control, List.mem_append, List.mem_map]
    exact Or.inl (Or.inl (Or.inl (Or.inr ⟨value, member, rfl⟩)))
  have constantsTyped := checked_execution_constants_have_value_shapes context contextTyped
  simp only [executePrimitive, executing, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · contradiction
  · exact ValueInventory.authoredFailure_preserves_all _ _ _ _ _ accepted _ typed constantsTyped
  · rename_i value evaluated
    have valueTyped := Primitives.evaluate_preserves_types
      (Admission.primitiveContext context.source context.captures) owner (ReferenceOwnership context.source.schemas)
      context.executionConstants ⟨opcode, schema, immediate, failures⟩ (operands.map Located.value) value
      (checked_context_schemas_valid context contextTyped) constantsTyped
      (by
        intro value member
        obtain ⟨located, belongs, rfl⟩ := List.mem_map.mp member
        exact inputs located belongs)
      (by simpa only [List.map_map, Function.comp_def] using admitted) evaluated
    exact ValueInventory.commitPure_preserves_all _ _ _ _ _ accepted _ typed valueTyped
  · exact heapPrimitive_preserves_value_shapes _ _ _ _ _ _ _ accepted contextTyped typed inputs

end Machine
end BoundaryV2.Profile.Source
