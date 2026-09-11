import BoundaryV2.SourceReferenceSafetyStorage

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

set_option maxRecDepth 4096 in
set_option maxHeartbeats 1600000 in
theorem heapPrimitive_valid (machine : State) (context : Context)
    (operation : Primitives.GraphOperation) (schema : SchemaId .source) (immediate : Nat)
    (operands : List Located) (after : Transition)
    (accepted : heapPrimitive machine context operation schema immediate operands = .ok after)
    (good : Valid context.source.schemas machine)
    (modes : ValueInventory.All (ValueModes context.source.schemas) machine)
    (inputs : ∀ value ∈ operands, ValueGood context.source.schemas machine.heap value.value)
    (inputModes : ∀ value ∈ operands, ValueModes context.source.schemas value.value) :
    Valid context.source.schemas after.state := by
  cases operation <;> simp only [heapPrimitive, bind, except_bind_ok, fromOption_ok] at accepted
  case computation =>
    obtain ⟨⟨function, expected⟩, constructorAt, _, checked, accepted⟩ := accepted
    have same : schema = expected := by simpa using require_ok _ _ _ checked
    subst expected
    exact closure_creation_valid _ _ _ _ _ _ accepted good inputs
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
    have middleGood := temporary_valid _ _ _ temporaryOk good
    have movedGood := move_valid _ _ _ _ moveOk middleGood
    have initialGood := move_value _ _ _ _ _ moveOk (temporary_value _ _ _ _ temporaryOk (inputs initial (by simp)))
    have allocatedGood := allocation_valid _ _ _ _ _ _ _ allocated (nextCell_valid _ _ movedGood)
      (by simpa only [ValueInventory.object, retainAt, List.mem_singleton, forall_eq] using (fields_value moved {moved with nextCell := moved.nextCell + 1} initial.value rfl rfl rfl initialGood))
    exact finishTemporary_valid _ _ _ finished allocatedGood
      (allocation_result _ _ _ _ _ _ _ allocated (by rfl))
  case cellGet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, object⟩, looked, accepted⟩ := accepted
    split at accepted <;> try contradiction
    rename_i storedNode identity cellSchema region content matched
    cases matched
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact scopedValue_valid _ _ _ accepted good
      (lookup_good _ _ _ _ looked good content.value (by simp [ValueInventory.object]))
  case cellSet =>
    split at accepted <;> try contradiction
    rename_i value replacement
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, object⟩, looked, accepted⟩ := accepted
    split at accepted <;> try contradiction
    rename_i storedNode identity cellSchema region content matched
    cases matched
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, shape, found, _, checked, store, replaced, accepted⟩ := accepted
    have storeGood := replacement_valid _ _ _ _ _
      (CellStability.lookupObject_reference _ _ _ _ looked).2 replaced (fun _ matched => matched) good
      (by simpa only [ValueInventory.object, retainAt, List.mem_singleton, forall_eq] using inputs replacement (by simp))
    exact scopedValue_valid _ _ _ accepted storeGood (scalar_good _ _ _ _)
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
    have middleGood := temporary_valid _ _ _ temporaryOk good
    have movedGood := move_valid _ _ _ _ moveOk middleGood
    have inputGood := move_value _ _ _ _ _ moveOk (temporary_value _ _ _ _ temporaryOk (inputs value (by simp)))
    have allocatedGood := allocation_valid _ _ _ _ _ _ _ allocated movedGood
      (by simpa only [ValueInventory.object, retainAt, List.mem_singleton, forall_eq] using inputGood)
    exact finishTemporary_valid _ _ _ finished allocatedGood (allocation_result _ _ _ _ _ _ _ allocated (by rfl))
  case unpack =>
    split at accepted <;> try contradiction
    rename_i value
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, object⟩, looked, accepted⟩ := accepted
    split at accepted <;> try contradiction
    rename_i storedNode storedSchema content matched
    cases matched
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, store, retired, accepted⟩ := accepted
    have valueShape := retirement_shape _ _ _ retired (inputModes value (by simp))
    have valueGood := inputs value (by simp)
    have storeGood := retirement_valid _ _ _ retired good valueShape valueGood modes
    have contentGood := retirement_value _ _ _ _ retired good.live valueShape valueGood
      (ValueInventory.lookupObject_preserves_all _ _ _ _ looked _ modes content.value (by simp [ValueInventory.object]))
      (lookup_good _ _ _ _ looked good content.value (by simp [ValueInventory.object]))
    exact commitPure_valid _ _ _ _ _ accepted storeGood contentGood
  case cloneResumption =>
    split at accepted <;> try contradiction
    rename_i value
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
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, checked, _, _, retired, retireOk, ⟨middle, owner⟩, temporaryOk,
      ⟨store, result⟩, allocated, finished⟩ := accepted
    have valueShape := retirement_shape _ _ _ retireOk (inputModes value (by simp))
    have valueGood := inputs value (by simp)
    have retiredGood := retirement_valid _ _ _ retireOk good valueShape valueGood modes
    have middleGood := temporary_valid _ _ _ temporaryOk retiredGood
    have captureGood : ∀ child ∈ ValueInventory.object (.multiTemplate {capture with schema := schema}),
        ValueGood context.source.schemas middle.heap child := by
      intro child member
      exact temporary_value _ _ _ _ temporaryOk (retirement_value _ _ _ _ retireOk good.live valueShape valueGood
        (ValueInventory.lookupObject_preserves_all _ _ _ _ looked _ modes child member)
        (lookup_good _ _ _ _ looked good child member))
    have allocatedGood := allocation_valid _ _ _ _ _ _ _ allocated middleGood captureGood
    exact finishTemporary_valid _ _ _ finished allocatedGood (allocation_result _ _ _ _ _ _ _ allocated (by rfl))
  case resourcePack =>
    split at accepted <;> try contradiction
    rename_i value
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨shape, found, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, ⟨middle, owner⟩, temporaryOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have middleGood := temporary_valid _ _ _ temporaryOk good
    have inputGood := temporary_value _ _ _ _ temporaryOk (inputs value (by simp))
    have allocatedGood := allocation_valid _ _ _ _ _ _ _ allocated middleGood
      (by simpa only [ValueInventory.object, retainAt, List.mem_singleton, forall_eq] using inputGood)
    exact finishTemporary_valid _ _ _ finished allocatedGood (allocation_result _ _ _ _ _ _ _ allocated (by rfl))
  case resourceUnpack =>
    split at accepted <;> try contradiction
    rename_i value
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
      have valueShape := retirement_shape _ _ _ retired (inputModes value (by simp))
      have valueGood := inputs value (by simp)
      have storeGood := retirement_valid _ _ _ retired good valueShape valueGood modes
      have contentGood := retirement_value _ _ _ _ retired good.live valueShape valueGood
        (ValueInventory.lookupObject_preserves_all _ _ _ _ looked _ modes content.value (by simp [ValueInventory.object]))
        (lookup_good _ _ _ _ looked good content.value (by simp [ValueInventory.object]))
      exact scopedValue_valid _ _ _ accepted storeGood contentGood
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨identity, _, obligation, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, stored, storedAt, accepted⟩ := accepted
      split at accepted <;> try contradiction
      rename_i storedSchema content
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      exact scopedValue_valid _ _ _ accepted good
        (ValueInventory.lookup_preserves_all _ _ _ storedAt _ good.values content.value (by simp [ValueInventory.object]))
    · contradiction

end ReferenceSafety
end BoundaryV2.Profile.Source.Machine
