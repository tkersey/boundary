import BoundaryV2.SourceCellExecution
import BoundaryV2.SourceValueTypes

namespace BoundaryV2.Profile.Source.Machine
namespace FrozenContracts

/-- A frozen cell names the same physical cell as its current heap entry.
The contents can differ, but their schemas cannot. -/
def CellValid (heap : Heap) (saved : FrozenCell) : Prop :=
  ∃ schema content, heap.lookup saved.node = some (.cell saved.identity schema saved.region content) ∧
    content.value.schema = saved.content.value.schema

def Valid (heap : Heap) (capture : Capture) : Prop :=
  ∀ saved ∈ capture.frozenCells, CellValid heap saved ∧ saved.region ∈ capture.localRegions

theorem snapshot_valid (heap : Heap) (regions : List RegionInstanceId) (saved : FrozenCell)
    (member : saved ∈ frozenCells heap regions) : CellValid heap saved ∧ saved.region ∈ regions := by
  obtain ⟨schema, found, localRegion⟩ := (frozen_cells_are_exactly_local heap regions saved).mp member
  exact ⟨⟨schema, saved.content, found, rfl⟩, localRegion⟩

theorem cell_stability_preserves (before after : Heap) (saved : FrozenCell)
    (preserved : CellStability.Preserves before.objects after.objects)
    (valid : CellValid before saved) : CellValid after saved := by
  obtain ⟨schema, content, found, same⟩ := valid
  obtain ⟨replacement, later, replacementSchema⟩ := CellStability.cell_of_view after saved.node _
    (preserved _ _ (CellStability.view_of_cell _ _ _ _ _ _ found))
  exact ⟨schema, replacement, later, replacementSchema.trans same⟩

theorem steps_preserve (context : Context) (before after : State) (events : List Event)
    (steps : Steps context before events after) (capture : Capture) (valid : Valid before.heap capture) :
    Valid after.heap capture := by
  intro saved member
  exact ⟨cell_stability_preserves _ _ _ (CellStability.steps_preserve _ _ _ _ steps) (valid saved member).1,
    (valid saved member).2⟩

theorem frozenObject_preserves_signature (heap : Heap) (capture : Capture) (dormant : List Capture)
    (valid : Valid heap capture) (dormantValid : ∀ inner ∈ dormant, Valid heap inner)
    (node : NodeId) (stored : Object) (found : heap.lookup node = some stored) :
    CellStability.signature (frozenObject capture dormant node stored) = CellStability.signature stored := by
  cases stored <;> try rfl
  rename_i identity schema region content
  cases selected : (capture.frozenCells ++ dormant.flatMap Capture.frozenCells).find? (fun saved => saved.node == node) with
  | none => simp [frozenObject, selected]
  | some saved =>
    have savedValid : CellValid heap saved := by
      have member := List.mem_of_find?_eq_some selected
      rcases List.mem_append.mp member with member | member
      · exact (valid saved member).1
      · obtain ⟨inner, innerMember, member⟩ := List.mem_flatMap.mp member
        exact (dormantValid inner innerMember saved member).1
    obtain ⟨savedSchema, savedContent, savedFound, same⟩ := savedValid
    have sameNode : saved.node = node := by simpa using List.find?_some selected
    rw [sameNode, found] at savedFound
    cases savedFound
    simp [frozenObject, selected, CellStability.signature, same]

theorem capture_references_in_support (heap : Heap) (capture : Capture) (node : NodeId)
    (member : node ∈ captureReferences capture) : node ∈ cloneSupport heap capture := by
  unfold cloneSupport
  apply List.foldlRecOn
  · exact List.mem_eraseDups.mpr member
  · intro support present _ _
    apply List.mem_eraseDups.mpr
    exact List.mem_append_left _ present

theorem frozen_node_in_support (heap : Heap) (capture : Capture) (saved : FrozenCell)
    (member : saved ∈ capture.frozenCells) : saved.node ∈ cloneSupport heap capture := by
  apply capture_references_in_support
  simp only [captureReferences, List.mem_append]
  right
  exact List.mem_flatMap.mpr ⟨saved, member, by simp⟩

theorem copied_capture_valid (before after : Heap) (root inner : Capture) (dormant : List Capture)
    (mapping : Renaming) (rootValid : Valid before root)
    (dormantValid : ∀ saved ∈ dormant, Valid before saved) (innerValid : Valid before inner)
    (copies : ∀ saved ∈ inner.frozenCells, ∀ schema current,
      before.lookup saved.node = some (.cell saved.identity schema saved.region current) →
      after.lookup (renamed mapping.nodes saved.node) =
        some (renameObject mapping (frozenObject root dormant saved.node (.cell saved.identity schema saved.region current)))) :
    Valid after (renameCapture mapping inner) := by
  intro renamedCell member
  obtain ⟨saved, savedMember, rfl⟩ := List.mem_map.mp member
  obtain ⟨⟨schema, current, found, sameSchema⟩, localRegion⟩ := innerValid saved savedMember
  have newFound := copies saved savedMember schema current found
  have signatureSame := frozenObject_preserves_signature before root dormant rootValid dormantValid
    saved.node (.cell saved.identity schema saved.region current) found
  let frozenContent := (((root.frozenCells ++ dormant.flatMap Capture.frozenCells).find?
    (fun cell => cell.node == saved.node)).map FrozenCell.content).getD current
  have frozenSchema : frozenContent.value.schema = current.value.schema := by
    have projected := congrArg (fun value => value.map CellStability.Signature.contentSchema) signatureSame
    simpa only [frozenObject, CellStability.signature, Option.map_some, Option.some.injEq] using projected
  constructor
  · refine ⟨schema, renameLocated mapping frozenContent, ?_, ?_⟩
    · exact newFound
    · simpa only [renameLocated, renaming_preserves_value_schema] using frozenSchema.trans sameSchema
  · exact List.mem_map.mpr ⟨saved.region, localRegion, rfl⟩

def ObjectValid (heap : Heap) : Object → Prop
  | .oneShot capture | .multiTemplate capture => Valid heap capture
  | _ => True

def HeapValid (heap : Heap) : Prop :=
  ∀ entry ∈ heap.objects, ∀ object ∈ entry, ObjectValid heap object

theorem heap_lookup (heap : Heap) (node : NodeId) (object : Object)
    (found : heap.lookup node = some object) (valid : HeapValid heap) : ObjectValid heap object := by
  simp only [Heap.lookup, Option.bind_eq_some_iff] at found
  obtain ⟨entry, atNode, present⟩ := found
  cases entry <;> simp [id] at present
  cases present
  exact valid _ (List.mem_of_getElem? atNode) _ rfl

theorem object_stability_preserves (before after : Heap) (stored : Object)
    (preserved : CellStability.Preserves before.objects after.objects)
    (valid : ObjectValid before stored) : ObjectValid after stored := by
  cases stored <;> try trivial
  all_goals
    intro saved member
    exact ⟨cell_stability_preserves before after saved preserved (valid saved member).1, (valid saved member).2⟩

end FrozenContracts

end BoundaryV2.Profile.Source.Machine
