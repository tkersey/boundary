import BoundaryV2.SourceReferenceSafety

namespace BoundaryV2.Profile.Source.Machine
namespace ReferenceSafety
open ReferenceContracts

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem fields_value (before after : Heap) (value : SemanticValue)
    (objects : after.objects = before.objects) (custody : after.custody = before.custody)
    (supply : after.nextCustody = before.nextCustody) (good : ValueGood schemas before value) : ValueGood schemas after value := by
  refine ⟨?_, custody ▸ good.2.1, supply ▸ good.2.2⟩
  apply references_mono value _ _ good.1
  intro schema node token valid
  simpa only [ReferenceValid, Heap.lookup, objects, custody] using valid

theorem temporary_fields (machine after : State) (owner : Custody.Owner)
    (accepted : temporary machine = .ok (after, owner)) :
    after.heap.objects = machine.heap.objects ∧ after.heap.custody = machine.heap.custody ∧
      after.heap.nextCustody = machine.heap.nextCustody := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  exact ⟨rfl, rfl, rfl⟩

theorem temporary_value (machine after : State) (owner : Custody.Owner) (value : SemanticValue)
    (accepted : temporary machine = .ok (after, owner)) (good : ValueGood schemas machine.heap value) :
    ValueGood schemas after.heap value :=
  let fields := temporary_fields _ _ _ accepted
  fields_value _ _ _ fields.1 fields.2.1 fields.2.2 good

theorem temporary_valid (machine after : State) (owner : Custody.Owner)
    (accepted : temporary machine = .ok (after, owner)) (good : Valid schemas machine) : Valid schemas after := by
  have values := ValueInventory.temporary_preserves_all _ _ _ accepted _ good.values
  refine ⟨fun value member => temporary_value _ _ _ value accepted (values value member), ?_⟩
  have fields := temporary_fields _ _ _ accepted
  intro entry member
  simpa only [Heap.lookup, fields.1] using good.live entry (fields.2.1 ▸ member)

theorem finishTemporary_fields (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) :
    after.state.heap.objects = machine.heap.objects ∧ after.state.heap.custody = machine.heap.custody ∧
      after.state.heap.nextCustody = machine.heap.nextCustody := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  cases accepted
  exact ⟨rfl, rfl, rfl⟩

theorem finishTemporary_value (machine : State) (result : Located) (after : Transition) (value : SemanticValue)
    (accepted : finishTemporary machine result = .ok after) (good : ValueGood schemas machine.heap value) :
    ValueGood schemas after.state.heap value :=
  let fields := finishTemporary_fields _ _ _ accepted
  fields_value _ _ _ fields.1 fields.2.1 fields.2.2 good

theorem finishTemporary_valid (machine : State) (result : Located) (after : Transition)
    (accepted : finishTemporary machine result = .ok after) (good : Valid schemas machine)
    (resultGood : ValueGood schemas machine.heap result.value) : Valid schemas after.state := by
  have values := ValueInventory.finishTemporary_preserves_all _ _ _ accepted _ good.values resultGood
  refine ⟨fun value member => finishTemporary_value _ _ _ value accepted (values value member), ?_⟩
  have fields := finishTemporary_fields _ _ _ accepted
  intro entry member
  simpa only [Heap.lookup, fields.1] using good.live entry (fields.2.1 ▸ member)

theorem scopedValue_valid (machine : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue machine value = .ok after) (good : Valid schemas machine)
    (valueGood : ValueGood schemas machine.heap value) : Valid schemas after.state := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, finished⟩ := accepted
  exact finishTemporary_valid _ _ _ finished (temporary_valid _ _ _ temporaryOk good)
    (temporary_value _ _ _ _ temporaryOk valueGood)

theorem consumeBook_value (heap : Heap) (book : Custody.Book) (tokens : List CustodyToken) (owner : Custody.Owner)
    (value : SemanticValue) (accepted : Custody.consume heap.custody tokens owner = some book)
    (good : ValueGood schemas heap value) : ValueGood schemas {heap with custody := book} value := by
  refine ⟨?_, consumeBook_preserves_alignment _ _ _ _ _ accepted good.2.1, good.2.2⟩
  unfold Custody.consume at accepted
  split at accepted <;> try contradiction
  cases accepted
  apply references_mono value _ _ good.1
  intro schema node token valid usable
  apply valid
  cases token with
  | none => trivial
  | some token =>
    obtain ⟨entry, member, same⟩ := usable
    exact ⟨entry, (List.mem_filter.mp member).1, same⟩

theorem commitPure_value (machine : State) (opcode : Opcode) (operands : List Located) (result : SemanticValue)
    (after : Transition) (value : SemanticValue) (accepted : commitPure machine opcode operands result = .ok after)
    (good : ValueGood schemas machine.heap value) : ValueGood schemas after.state.heap value := by
  simp only [commitPure, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, accepted⟩ := accepted
  have middleGood := temporary_value _ _ _ value temporaryOk good
  split at accepted <;> simp only [except_bind_ok, fromOption_ok] at accepted
  · obtain ⟨_, _, _, _, finished⟩ := accepted
    exact finishTemporary_value _ _ _ _ finished middleGood
  · obtain ⟨moved, movedOk, _, _, book, consumed, finished⟩ := accepted
    have movedGood := move_value _ _ _ _ _ movedOk middleGood
    have consumedGood := consumeBook_value _ _ _ _ _ consumed movedGood
    exact finishTemporary_value _ _ _ _ finished consumedGood

theorem commitPure_valid (machine : State) (opcode : Opcode) (operands : List Located) (result : SemanticValue)
    (after : Transition) (accepted : commitPure machine opcode operands result = .ok after)
    (good : Valid schemas machine) (resultGood : ValueGood schemas machine.heap result) : Valid schemas after.state := by
  have values := ValueInventory.all_mono _ _ machine good.values (fun value holds => commitPure_value _ _ _ _ _ value accepted holds)
  exact ⟨ValueInventory.commitPure_preserves_all _ _ _ _ _ accepted _ values (commitPure_value _ _ _ _ _ _ accepted resultGood),
    commitPure_preserves_live_objects _ _ _ _ _ accepted good.live⟩

theorem primitive_value (schemas : List (Schema .source)) (heap : Heap) (constants : List SemanticValue)
    (opcode : Opcode) (schema : SchemaId .source) (immediate : Nat) (operands : List SemanticValue) (result : SemanticValue)
    (constantsGood : ∀ value ∈ constants, ValueGood schemas heap value)
    (operandsGood : ∀ value ∈ operands, ValueGood schemas heap value)
    (accepted : Primitives.evaluate schemas constants opcode schema immediate operands = .ok (.value result)) :
    ValueGood schemas heap result :=
  ⟨Primitives.evaluate_preserves_references _ _ _ _ _ _ _ _
      (fun value member => (constantsGood value member).1) (fun value member => (operandsGood value member).1) accepted,
    primitive_preserves_alignment _ _ _ _ _ _ _ _
      (fun value member => (constantsGood value member).2.1) (fun value member => (operandsGood value member).2.1) accepted,
    primitive_preserves_token_bounds _ _ _ _ _ _ _ _
      (fun value member => (constantsGood value member).2.2) (fun value member => (operandsGood value member).2.2) accepted⟩

theorem admitted_value_good (schemas : List (Schema .source)) (heap : Heap) (value : SemanticValue)
    (accepted : Profile.Value.externalValid schemas value = true) : ValueGood schemas heap value := by
  have free := external_value_has_no_runtime_handles _ _ accepted
  exact ⟨reference_free_valid _ _ _ free.1, token_free_aligned _ _ free.2, by simp [ValueTokensBounded, free.2]⟩

end ReferenceSafety
end BoundaryV2.Profile.Source.Machine
