import BoundaryV2.SourceFrozenCells

namespace BoundaryV2.Profile.Source.Machine
namespace FrozenContracts

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem require_ok (condition : Bool) (reason : Invalid) (result : Unit)
    (accepted : require condition reason = .ok result) : condition = true := by
  unfold require at accepted
  split at accepted <;> first | assumption | contradiction

theorem instantiation_checks_support_closure (machine after : State) (context : Context)
    (capture instantiated : Capture)
    (accepted : instantiateCapture machine context capture = .ok (after, instantiated)) :
    ∀ node ∈ cloneSupport machine.heap capture,
      ∀ child ∈ cloneChildren machine.heap capture.localRegions node,
        child ∈ cloneSupport machine.heap capture := by
  simp only [instantiateCapture, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, closed, _⟩ := accepted
  have checked := require_ok _ _ _ closed
  intro node member child childMember
  have inFlat := List.mem_flatMap.mpr ⟨node, member, childMember⟩
  simpa only [List.contains_iff_mem] using List.all_eq_true.mp checked child inFlat

theorem instantiate_preserves_heap_and_frozen_contracts (machine after : State) (context : Context)
    (capture instantiated : Capture)
    (accepted : instantiateCapture machine context capture = .ok (after, instantiated))
    (heapValid : HeapValid machine.heap) (valid : Valid machine.heap capture) :
    HeapValid after.heap ∧ Valid after.heap instantiated := by
  let support := cloneSupport machine.heap capture
  let dormant := support.filterMap (fun node => match machine.heap.lookup node with
    | some (.multiTemplate inner) => some inner | _ => none)
  let regions := (capture.localRegions ++ dormant.flatMap Capture.localRegions).eraseDups
  let attachments := (capture.delimiter.identity :: activeAttachments capture.frames ++
    dormant.flatMap (fun inner => inner.delimiter.identity :: activeAttachments inner.frames)).eraseDups
  let copyNodes := support.filter fun node => match machine.heap.lookup node with
    | some (.cell _ _ region _) | some (.region region _ _ _) => regions.contains region
    | some (.capability identity _) => attachments.contains identity
    | some (.closure ..) | some (.multiTemplate _) => true
    | _ => false
  have allDormant : ∀ inner ∈ dormant, Valid machine.heap inner := by
    intro inner member
    obtain ⟨node, _, selected⟩ := List.mem_filterMap.mp member
    split at selected <;> try contradiction
    rename_i saved found
    cases selected
    exact heap_lookup _ _ _ found heapValid
  have closed := instantiation_checks_support_closure _ _ _ _ _ accepted
  have preserved := CellStability.instantiateCapture_preserves _ _ _ _ accepted
  obtain ⟨mapping, _, captureKnown, copiedAt, inventory⟩ := instantiation_inventory machine after context capture instantiated accepted
  change ∀ reference ∈ copyNodes, ∃ object,
    machine.heap.lookup reference = some object ∧
    after.heap.lookup (renamed mapping.nodes reference) =
      some (renameObject mapping (frozenObject capture dormant reference object)) at copiedAt
  change ∀ entry ∈ after.heap.objects, entry ∈ machine.heap.objects ∨
    ∃ reference ∈ copyNodes, ∃ object, machine.heap.lookup reference = some object ∧
      entry = some (renameObject mapping (frozenObject capture dormant reference object)) at inventory
  have copiedValid (inner : Capture) (innerValid : Valid machine.heap inner)
      (supported : ∀ saved ∈ inner.frozenCells, saved.node ∈ support)
      (localRegions : ∀ region ∈ inner.localRegions, region ∈ regions) :
      Valid after.heap (renameCapture mapping inner) := by
    apply copied_capture_valid machine.heap after.heap capture inner dormant mapping valid allDormant innerValid
    intro saved member schema current found
    have copyMember : saved.node ∈ copyNodes := by
      apply List.mem_filter.mpr
      refine ⟨supported saved member, ?_⟩
      simp only [found]
      exact List.contains_iff_mem.mpr (localRegions saved.region (innerValid saved member).2)
    obtain ⟨stored, oldFound, newFound⟩ := copiedAt saved.node copyMember
    rw [found] at oldFound
    cases oldFound
    exact newFound
  constructor
  · intro entry member stored present
    rcases inventory entry member with old | copied
    · exact object_stability_preserves _ _ _ preserved (heapValid entry old stored present)
    · obtain ⟨node, nodeMember, object, found, rfl⟩ := copied
      cases present
      cases object <;> try trivial
      · rename_i inner
        have impossible := (List.mem_filter.mp nodeMember).2
        simp [found] at impossible
      · rename_i inner
        have innerMember : inner ∈ dormant := List.mem_filterMap.mpr
          ⟨node, (List.mem_filter.mp nodeMember).1, by rw [found]⟩
        apply copiedValid inner (allDormant inner innerMember)
        · intro saved member
          apply closed node (List.mem_filter.mp nodeMember).1 saved.node
          simp only [cloneChildren, found, objectReferences]
          simp only [captureReferences, List.mem_append]
          right
          exact List.mem_flatMap.mpr ⟨saved, member, by simp⟩
        · intro region member
          apply List.mem_eraseDups.mpr
          exact List.mem_append_right _ (List.mem_flatMap.mpr ⟨inner, innerMember, member⟩)
  · rw [captureKnown]
    apply copiedValid capture valid
    · exact frozen_node_in_support _ _
    · intro region member
      exact List.mem_eraseDups.mpr (List.mem_append_left _ member)

end FrozenContracts
end BoundaryV2.Profile.Source.Machine
