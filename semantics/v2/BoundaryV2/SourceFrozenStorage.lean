import BoundaryV2.SourceFrozenClone

namespace BoundaryV2.Profile.Source.Machine
namespace FrozenContracts
namespace Preservation

/-- All stored capture snapshots agree with the current physical cells. -/
def Preserves (before after : List (Option Object)) : Prop :=
  HeapValid { objects := before } → HeapValid { objects := after }

theorem Preserves.refl (objects : List (Option Object)) : Preserves objects objects := fun valid => valid

theorem Preserves.trans (first : Preserves before middle) (second : Preserves middle after) : Preserves before after :=
  fun valid => second (first valid)

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

theorem move_preserves (before after : Heap) (values : List Located) (receiver : Nat → Custody.Owner)
    (accepted : moveValues before values receiver = some after) : Preserves before.objects after.objects := by
  simp [moveValues, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  exact .refl _

theorem allocate_preserves (before after : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject before schema stored owner exclusive = some (after, value))
    (storedValid : ObjectValid before stored) : Preserves before.objects after.objects := by
  have preserved := CellStability.allocate_preserves _ _ _ _ _ _ _ accepted
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  all_goals
    first | obtain ⟨rfl, _⟩ := accepted | obtain ⟨_, _, rfl, _⟩ := accepted
    intro valid entry member object present
    rcases List.mem_append.mp member with old | new
    · exact object_stability_preserves _ _ _ preserved (valid entry old object present)
    · simp only [List.mem_singleton] at new
      cases new
      cases present
      exact object_stability_preserves _ _ _ preserved storedValid

theorem replace_preserves (before after : Heap) (node : NodeId) (old stored : Object)
    (looked : before.lookup node = some old) (same : CellStability.signature stored = CellStability.signature old)
    (accepted : replaceObject before node stored = some after)
    (storedValid : ObjectValid before stored) : Preserves before.objects after.objects := by
  have preserved := CellStability.replace_preserves _ _ _ _ _ looked same accepted
  unfold replaceObject at accepted
  split at accepted <;> try contradiction
  cases accepted
  intro valid entry member object present
  rcases List.mem_or_eq_of_mem_set member with old | rfl
  · exact object_stability_preserves _ _ _ preserved (valid entry old object present)
  · cases present
    exact object_stability_preserves _ _ _ preserved storedValid

theorem retire_noncell_preserves (machine : State) (value : Located) (node : NodeId) (stored : Object) (after : Heap)
    (looked : lookupObject machine value = .ok (node, stored)) (noncell : CellStability.signature stored = none)
    (accepted : retireObject machine.heap value = some after) : Preserves machine.heap.objects after.objects := by
  have preserved := CellStability.retire_noncell_preserves _ _ _ _ _ looked noncell accepted
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, Option.bind_eq_some_iff, consumeValue, pure, Option.some.injEq] at accepted
  obtain ⟨_, _, _, ⟨_, _, rfl⟩, rfl⟩ := accepted
  intro valid entry member object present
  rcases List.mem_or_eq_of_mem_set member with old | rfl
  · exact object_stability_preserves _ _ _ preserved (valid entry old object present)
  · cases present
end Preservation

theorem initial_heap_valid (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) : HeapValid machine.heap := by
  simp only [initial, bind, Preservation.except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ := accepted
  simp [HeapValid]

end FrozenContracts
end BoundaryV2.Profile.Source.Machine
