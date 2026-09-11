import BoundaryV2.SourceTokenInventory
import BoundaryV2.SourcePrimitiveTypes

namespace BoundaryV2.Profile.Source.Machine
namespace TokenInventory

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

theorem closure_creation_preserves_token_bounds (state : State) (context : Context)
    (schema : SchemaId .source) (function : FunctionId .source)
    (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues state context schema function values = .ok after)
    (upper : after.state.heap.nextCustody ≤ limit)
    (typed : ValueInventory.All (ValueTokensBounded limit) state)
    (inputs : ∀ value ∈ values, ValueTokensBounded limit value.value) :
    ValueInventory.All (ValueTokensBounded limit) after.state := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, ⟨middle, owner⟩, temporaryAccepted, moved, moveAccepted, ⟨heap, result⟩, allocated, finished⟩ := accepted
  have middleTyped := ValueInventory.temporary_preserves_all _ _ _ temporaryAccepted _ typed
  have movedTyped := ValueInventory.moveValues_preserves_all _ _ _ _ moveAccepted _ middleTyped
  have storedTyped : ∀ child ∈ ValueInventory.object (.closure schema function
      (((Analysis.captures context.captures function).zip values).mapIdx (fun index (binder, value) =>
        Binding.mk binder (retainAt value (.closure ⟨middle.heap.objects.length⟩ index))))),
      ValueTokensBounded limit child := by
    intro child member
    simp only [ValueInventory.object, ValueInventory.environment, List.mapIdx_eq_zipIdx_map,
      List.map_map, Function.comp_def, List.mem_map, retainAt] at member
    obtain ⟨⟨⟨binder, value⟩, index⟩, pairMember, rfl⟩ := member
    exact inputs value (List.of_mem_zip (List.fst_mem_of_mem_zipIdx pairMember)).2
  have allocatedTyped := ValueInventory.allocateObject_preserves_all _ _ _ _ _ _ _ allocated _ movedTyped storedTyped
  have resultTyped := allocation_result _ _ _ _ _ _ _ allocated
    (Nat.le_trans (finishTemporary_allocation _ _ _ finished).heap.custody upper)
  exact ValueInventory.finishTemporary_preserves_all _ _ _ finished _ allocatedTyped resultTyped

theorem makeClosure_preserves_token_bounds (state : State) (context : Context)
    (schema : SchemaId .source) (function : FunctionId .source)
    (bindings : Environment) (after : Transition)
    (accepted : makeClosure state context schema function bindings = .ok after)
    (upper : after.state.heap.nextCustody ≤ limit)
    (typed : ValueInventory.All (ValueTokensBounded limit) state)
    (inputs : ∀ binding ∈ bindings, ValueTokensBounded limit binding.located.value) :
    ValueInventory.All (ValueTokensBounded limit) after.state := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  obtain ⟨values, captured, accepted⟩ := accepted
  exact closure_creation_preserves_token_bounds state context schema function values after accepted upper typed
    (captured_values_preserve_all bindings _ values captured _ inputs)

private theorem finishValue_preserves_all (state : State) (value : Located) (property : SemanticValue → Prop)
    (holds : ValueInventory.All property state) (valueHolds : property value.value) :
    ValueInventory.All property (finishValue state value).state := by
  simp only [finishValue, ValueInventory.All, ValueInventory.state, ValueInventory.control,
    List.mem_append, List.mem_singleton] at holds ⊢
  grind only []

/-- Expression entry retains prior tokens or allocates below the returned
custody supply. Literal values come from checked source admission. -/
theorem enterExpression_preserves_token_bounds (state : State) (context : Context) (after : Transition)
    (accepted : enterExpression state context = .ok after) (contextTyped : context.typingValid = true)
    (upper : after.state.heap.nextCustody ≤ limit)
    (typed : ValueInventory.All (ValueTokensBounded limit) state) :
    ValueInventory.All (ValueTokensBounded limit) after.state := by
  unfold enterExpression at accepted
  split at accepted <;> try contradiction
  rename_i reference bindings control
  have bindingsTyped : ∀ binding ∈ bindings, ValueTokensBounded limit binding.located.value := by
    intro binding member
    apply typed binding.located.value
    simp only [ValueInventory.state, control, ValueInventory.control, ValueInventory.environment]
    exact List.mem_append_left _ (List.mem_append_left _ (List.mem_append_left _ (List.mem_map.mpr ⟨binding, member, rfl⟩)))
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨schema, expression⟩, found, accepted⟩ := accepted
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
      (by simp [ValueTokensBounded, (external_value_has_no_runtime_handles _ _
        ((checked_context_constants_are_external context contextTyped) value (List.mem_of_getElem? foundValue))).2])
  | lambda function =>
    exact makeClosure_preserves_token_bounds state context schema function bindings after accepted upper typed bindingsTyped
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
theorem heapPrimitive_preserves_token_bounds (machine : State) (context : Context)
    (operation : Primitives.GraphOperation) (schema : SchemaId .source) (immediate : Nat)
    (operands : List Located) (after : Transition)
    (accepted : heapPrimitive machine context operation schema immediate operands = .ok after)
    (upper : after.state.heap.nextCustody ≤ limit)
    (typed : ValueInventory.All (ValueTokensBounded limit) machine)
    (inputs : ∀ value ∈ operands, ValueTokensBounded limit value.value) :
    ValueInventory.All (ValueTokensBounded limit) after.state := by
  cases operation <;> simp only [heapPrimitive, bind, except_bind_ok, fromOption_ok] at accepted
  case computation =>
    obtain ⟨⟨function, expected⟩, constructorAt, _, checked, accepted⟩ := accepted
    have same : schema = expected := by simpa using require_ok _ _ _ checked
    subst expected
    exact closure_creation_preserves_token_bounds _ _ _ _ _ _ accepted upper typed inputs
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
    have resultTyped := allocation_result _ _ _ _ _ _ _ allocated
      (Nat.le_trans (finishTemporary_allocation _ _ _ finished).heap.custody upper)
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
    exact ValueInventory.scopedValue_preserves_all _ _ _ accepted _ storeTyped (by simp [ValueTokensBounded, ownedTokens])
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
    have resultTyped := allocation_result _ _ _ _ _ _ _ allocated
      (Nat.le_trans (finishTemporary_allocation _ _ _ finished).heap.custody upper)
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
    have resultTyped := allocation_result _ _ _ _ _ _ _ allocated
      (Nat.le_trans (finishTemporary_allocation _ _ _ finished).heap.custody upper)
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
    have resultTyped := allocation_result _ _ _ _ _ _ _ allocated
      (Nat.le_trans (finishTemporary_allocation _ _ _ finished).heap.custody upper)
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

theorem executePrimitive_preserves_token_bounds (machine : State) (context : Context) (after : Transition)
    (accepted : executePrimitive machine context = .ok after) (contextTyped : context.typingValid = true)
    (upper : after.state.heap.nextCustody ≤ limit)
    (typed : ValueInventory.All (ValueTokensBounded limit) machine) :
    ValueInventory.All (ValueTokensBounded limit) after.state := by
  unfold executePrimitive at accepted
  split at accepted <;> try contradiction
  rename_i schema opcode immediate failures bindings operands executing
  have inputs : ∀ value ∈ operands, ValueTokensBounded limit value.value := by
    intro value member
    apply typed
    simp only [ValueInventory.state, executing, ValueInventory.control, List.mem_append, List.mem_map]
    exact Or.inl (Or.inl (Or.inl (Or.inr ⟨value, member, rfl⟩)))
  have constantsTyped : ∀ value ∈ context.executionConstants, ValueTokensBounded limit value :=
    fun value member => by simp [ValueTokensBounded, (checked_execution_constants_have_no_handles context contextTyped value member).2]
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · contradiction
  · exact ValueInventory.authoredFailure_preserves_all _ _ _ _ _ accepted _ typed constantsTyped
  · rename_i value evaluated
    have valueTyped := primitive_preserves_token_bounds limit context.source.schemas context.executionConstants
      opcode schema immediate (operands.map Located.value) value constantsTyped (by
        intro child member
        obtain ⟨original, belongs, rfl⟩ := List.mem_map.mp member
        exact inputs original belongs) evaluated
    exact ValueInventory.commitPure_preserves_all _ _ _ _ _ accepted _ typed valueTyped
  · exact heapPrimitive_preserves_token_bounds _ _ _ _ _ _ _ accepted upper typed inputs

end TokenInventory
end BoundaryV2.Profile.Source.Machine
