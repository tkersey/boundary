import BoundaryV2.SourceCustodyCapture

namespace BoundaryV2.Profile.Source.Machine
namespace CustodyCoverage

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

private theorem flatMap_remove_subset (values : List α) (index : Nat) (removed replacement : α)
    (f : α → List β) (found : values[index]? = some removed) :
    values.flatMap f ⊆ (values.set index replacement).flatMap f ++ f removed := by
  induction values generalizing index with
  | nil => simp at found
  | cons value values induction =>
    cases index with
    | zero =>
      cases found
      intro child member
      rcases List.mem_append.mp member with first | rest
      · exact List.mem_append_right _ first
      · exact List.mem_append_left _ (List.mem_append_right _ rest)
    | succ index =>
      intro child member
      rcases List.mem_append.mp member with first | rest
      · exact List.mem_append_left _ (List.mem_append_left _ first)
      · rcases List.mem_append.mp (induction index found rest) with kept | lost
        · exact List.mem_append_left _ (List.mem_append_right _ kept)
        · exact List.mem_append_right _ lost

theorem commitPure_transit_valid (machine : State) (opcode : Opcode) (operands : List Located)
    (result : SemanticValue) (after : Transition) (observed : observes opcode = false)
    (accepted : commitPure machine opcode operands result = .ok after)
    (valid : Covered machine.heap.custody (fields machine ++ operands))
    (empty : QueueCustody.controlFields machine.control = []) : Valid after.state := by
  simp only [commitPure, observed, Bool.false_eq_true, if_false, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨middle, owner⟩, reserved, heap, moved, _, _, custody, consumed, finished⟩ := accepted
  have next := temporary_covered machine middle owner operands reserved valid
  have movedCover := moveValues_transit_covered _ _ _ _ _ moved next
  have resultCover := consume_result_covered _ _ _ _ _ _ consumed movedCover
  rw [← move_fields _ _ _ _ moved] at resultCover
  have done := finishTemporary_covered _ _ [] _ finished
    (by rw [temporary_control _ _ _ reserved]; exact empty) resultCover
  simpa only [Valid, List.append_nil] using done

theorem retire_free_valid (machine : State) (heap : Heap) (value : Located) (node : NodeId) (stored : Object)
    (looked : lookupObject machine value = .ok (node, stored))
    (accepted : retireObject machine.heap value = some heap) (valid : Valid machine)
    (free : ∀ field ∈ OwningFields.object stored ++ QueueCustody.objectFields stored, ownedTokens field.value = []) :
    Valid {machine with heap := heap} := by
  have next := retireObject_covered _ _ _ _ _ [] looked accepted (by simpa [Valid] using valid)
  exact Covered.drop_free _ _ _ (by simpa only [List.append_nil] using next) free

theorem replace_free_valid (machine : State) (heap : Heap) (node : NodeId) (stored replacement : Object)
    (found : machine.heap.lookup node = some stored)
    (accepted : replaceObject machine.heap node replacement = some heap) (valid : Valid machine)
    (free : ∀ field ∈ OwningFields.object stored ++ QueueCustody.objectFields stored, ownedTokens field.value = []) :
    Valid {machine with heap := heap} := by
  have position : machine.heap.objects[node.value]? = some (some stored) := by
    simp only [Heap.lookup, Option.bind_eq_some_iff] at found
    obtain ⟨entry, atEntry, isStored⟩ := found
    cases entry <;> try contradiction
    cases isStored
    exact atEntry
  unfold replaceObject at accepted
  split at accepted <;> try contradiction
  cases accepted
  apply Covered.drop_free _ _ _ ?_ free
  apply Covered.mono _ _ _ valid
  have objects := flatMap_remove_subset machine.heap.objects node.value (some stored) (some replacement)
    (fun entry => entry.toList.flatMap OwningFields.object) position
  have queues := flatMap_remove_subset machine.heap.objects node.value (some stored) (some replacement)
    (fun entry => entry.toList.flatMap QueueCustody.objectFields) position
  intro field member
  simp only [fields, OwningFields.heap, QueueCustody.fields_components, QueueCustody.heapFields,
    List.mem_append] at member ⊢
  simp only [Option.toList_some, List.flatMap_singleton] at objects queues
  rcases member with ((object | protection) | holding) | ((control | stack) | queue)
  · have includes := List.mem_append.mp (objects object)
    grind only []
  · grind only []
  · grind only []
  · grind only []
  · grind only []
  · have includes := List.mem_append.mp (queues queue)
    grind only []

theorem allocation_from_valid (machine : State) (heap : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject machine.heap schema stored owner exclusive = some (heap, value)) (valid : Valid machine) :
    Covered heap.custody (fields {machine with heap := heap} ++ [value]) := by
  apply allocate_covered _ _ _ _ _ _ _ [] accepted
  apply Covered.mono _ _ _ valid
  intro field member
  exact List.mem_append_left _ (List.mem_append_left _ member)

theorem heapPrimitive_valid (machine : State) (context : Context) (operation : Primitives.GraphOperation)
    (schema : SchemaId .source) (immediate : Nat) (operands : List Located) (after : Transition)
    (valid : Valid machine) (empty : QueueCustody.controlFields machine.control = [])
    (cellsFree : ∀ node identity schema region content,
      machine.heap.lookup node = some (.cell identity schema region content) → ownedTokens content.value = [])
    (resourcesFree : ∀ node schema content,
      machine.heap.lookup node = some (.resource schema content) → ownedTokens content.value = [])
    (accepted : heapPrimitive machine context operation schema immediate operands = .ok after) : Valid after.state := by
  cases operation <;> simp only [heapPrimitive, bind, except_bind_ok, fromOption_ok] at accepted
  case computation =>
    obtain ⟨_, _, _, _, accepted⟩ := accepted
    exact makeClosureWithValues_valid _ _ _ _ _ _ accepted valid empty
  case cellNew =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, ⟨middle, owner⟩, reserved, moved, movedAt, ⟨heap, result⟩, allocated, finished⟩ := accepted
    have next := temporary_covered machine middle owner [] reserved (by simpa [Valid] using valid)
    have movedCover := moveValues_covered _ _ _ _ _ movedAt (by simpa using next)
    rw [← move_fields _ _ _ _ movedAt] at movedCover
    have allocatedCover := allocate_covered {middle with heap := {moved with nextCell := moved.nextCell + 1}}
      heap _ _ _ _ _ [] allocated (by
        simpa only [List.mapIdx_cons, List.mapIdx_nil, List.append_nil, OwningFields.object,
          QueueCustody.objectFields, DisposalShape.object, List.filter_nil,
          fields, OwningFields.heap, QueueCustody.fields_components, QueueCustody.heapFields] using movedCover)
    have done := finishTemporary_covered _ _ [] _ finished
      (by rw [temporary_control _ _ _ reserved]; exact empty) allocatedCover
    simpa only [Valid, List.append_nil] using done
  case cellGet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact scopedValue_valid _ _ _ accepted valid empty
  case cellSet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, heap, replaced, accepted⟩ := accepted
    have found := (CellStability.lookupObject_reference _ _ _ _ looked).2
    have next := replace_free_valid _ _ _ _ _ found replaced valid (by
      intro field member
      simp only [OwningFields.object, QueueCustody.objectFields, DisposalShape.object,
        List.filter_nil, List.append_nil, List.mem_singleton] at member
      subst field
      exact cellsFree _ _ _ _ _ found)
    exact scopedValue_valid _ _ _ accepted next empty
  case package =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, ⟨middle, owner⟩, reserved, moved, movedAt, ⟨heap, result⟩, allocated, finished⟩ := accepted
    have next := temporary_covered machine middle owner [] reserved (by simpa [Valid] using valid)
    have movedCover := moveValues_covered _ _ _ _ _ movedAt (by simpa using next)
    rw [← move_fields _ _ _ _ movedAt] at movedCover
    have allocatedCover := allocate_covered {middle with heap := moved} heap _ _ _ _ _ [] allocated (by
      simpa only [List.mapIdx_cons, List.mapIdx_nil, List.append_nil, OwningFields.object,
        QueueCustody.objectFields, DisposalShape.object, List.filter_nil] using movedCover)
    have done := finishTemporary_covered _ _ [] _ finished
      (by rw [temporary_control _ _ _ reserved]; exact empty) allocatedCover
    simpa only [Valid, List.append_nil] using done
  case unpack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, heap, retired, accepted⟩ := accepted
    have next := retireObject_covered _ _ _ _ _ [] looked retired (by simpa [Valid] using valid)
    apply commitPure_transit_valid _ _ _ _ _ rfl accepted ?_ empty
    simpa only [OwningFields.object, QueueCustody.objectFields, DisposalShape.object,
      List.filter_nil, List.append_nil] using next
  case cloneResumption =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    rename_i saved
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, cloneChecked, retired, retireOk, ⟨middle, owner⟩, reserved, ⟨heap, result⟩, allocated, finished⟩ := accepted
    have safe := (clone_safe_has_no_captured_custody _ _ _ (require_ok _ _ _ cloneChecked)).1
    have retiredValid := retire_free_valid _ _ _ _ _ looked retireOk valid (by
      simp only [OwningFields.object, QueueCustody.objectFields, DisposalShape.object,
        OwnerLocations.clone_capture_has_no_queue context.source saved safe, List.filter_nil, List.nil_append]
      simp)
    have next := temporary_covered _ _ _ [] reserved (by simpa [Valid] using retiredValid)
    have allocatedCover := allocation_from_valid _ _ _ _ _ _ _ allocated (by simpa [Valid] using next)
    have done := finishTemporary_covered _ _ [] _ finished
      (by rw [temporary_control _ _ _ reserved]; exact empty) allocatedCover
    simpa only [Valid, List.append_nil] using done
  case resourcePack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, ⟨middle, owner⟩, reserved, ⟨heap, result⟩, allocated, finished⟩ := accepted
    have next := temporary_covered _ _ _ [] reserved (by simpa [Valid] using valid)
    have allocatedCover := allocation_from_valid _ _ _ _ _ _ _ allocated (by simpa [Valid] using next)
    have done := finishTemporary_covered _ _ [] _ finished
      (by rw [temporary_control _ _ _ reserved]; exact empty) allocatedCover
    simpa only [Valid, List.append_nil] using done
  case resourceUnpack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, ⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    case resource =>
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, heap, retired, accepted⟩ := accepted
      have found := (CellStability.lookupObject_reference _ _ _ _ looked).2
      have next := retire_free_valid _ _ _ _ _ looked retired valid (by
        intro field member
        simp only [OwningFields.object, QueueCustody.objectFields, DisposalShape.object,
          List.filter_nil, List.append_nil, List.mem_singleton] at member
        subst field
        exact resourcesFree _ _ _ found)
      exact scopedValue_valid _ _ _ accepted next empty
    case borrow =>
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      exact scopedValue_valid _ _ _ accepted valid empty

end CustodyCoverage
end BoundaryV2.Profile.Source.Machine
