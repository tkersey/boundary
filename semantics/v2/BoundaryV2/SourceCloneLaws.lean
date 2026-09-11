import BoundaryV2.SourceActivationLaws
import BoundaryV2.SourceEffects

namespace BoundaryV2.Profile.Source.Machine

private theorem bind_success (value : Except Invalid α) (next : α → Except Invalid β)
    (result : β) (accepted : value.bind next = .ok result) :
    ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value with
  | error error => cases accepted
  | ok input => exact ⟨input, rfl, accepted⟩

private theorem mapM_at (function : α → Except Invalid β) (inputs : List α) (outputs : List β)
    (accepted : inputs.mapM function = .ok outputs) (index : Nat) (input : α)
    (present : inputs[index]? = some input) :
    ∃ output, function input = .ok output ∧ outputs[index]? = some output := by
  induction inputs generalizing outputs index with
  | nil => simp at present
  | cons head tail induction =>
    rw [List.mapM_cons] at accepted
    obtain ⟨first, atHead, accepted⟩ := bind_success _ _ _ accepted
    obtain ⟨rest, atTail, accepted⟩ := bind_success _ _ _ accepted
    cases accepted
    cases index with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at present
      exact ⟨first, present ▸ atHead, rfl⟩
    | succ index =>
      exact induction rest atTail index present

private theorem dedup_nodup [BEq α] [LawfulBEq α] (values : List α) : values.eraseDups.Nodup := by
  cases values with
  | nil => simp
  | cons head tail =>
    rw [List.eraseDups_cons, List.nodup_cons]
    constructor
    · simp [List.mem_eraseDups]
    · exact dedup_nodup _
termination_by values.length
decreasing_by have := List.length_filter_le (fun value => !value == head) tail; simp only [List.length_cons]; omega

private theorem dedup_of_nodup [BEq α] [LawfulBEq α] (values : List α) (unique : values.Nodup) :
    values.eraseDups = values := by
  induction values with
  | nil => rfl
  | cons head tail induction =>
    rw [List.nodup_cons] at unique
    have unchanged : tail.filter (fun value => !value == head) = tail := by
      apply List.filter_eq_self.mpr
      intro value member
      have different : value ≠ head := by intro same; exact unique.1 (same ▸ member)
      simpa using different
    rw [List.eraseDups_cons, unchanged, induction unique.2]

private theorem copied_lookup_at_map (objects : List (Option Object)) (nodes : List NodeId)
    (copied : List (Option Object)) (function : NodeId → Except Invalid (Option Object))
    (accepted : nodes.mapM function = .ok copied) (unique : nodes.Nodup)
    (reference : NodeId) (member : reference ∈ nodes) :
    ∃ entry, function reference = .ok entry ∧
      (objects ++ copied)[(renamed (freshMap .runtime .node objects.length nodes) reference).value]? = some entry := by
  have atInput : nodes[nodes.idxOf reference]? = some reference := by
    rw [List.getElem?_eq_getElem (List.idxOf_lt_length_of_mem member), List.getElem_idxOf]
  obtain ⟨entry, checked, atOutput⟩ := mapM_at _ _ _ accepted _ reference atInput
  refine ⟨entry, checked, ?_⟩
  have atMap := renamed_inside_fresh_map .runtime .node objects.length nodes reference member
  obtain ⟨index, inBounds, atIndex⟩ := List.mem_mapIdx.mp atMap
  have source := congrArg Prod.fst atIndex
  have target := congrArg (fun pair => pair.2.value) atIndex
  simp only at source target
  simp only [dedup_of_nodup nodes unique] at source inBounds
  have sameIndex : index = nodes.idxOf reference := by
    rw [← source, unique.idxOf_getElem]
  rw [← target, List.getElem?_append_right (by omega)]
  simpa only [Nat.add_sub_cancel_left, sameIndex] using atOutput

theorem clone_support_has_one_entry_per_object (heap : Heap) (capture : Capture) :
    (cloneSupport heap capture).Nodup := by
  unfold cloneSupport
  apply List.foldlRecOn
  · exact dedup_nodup _
  · intro support _ _ _
    exact dedup_nodup _

/-- Select local snapshots by physical cell identity. Outside cells are
excluded from the copy inventory and retain current storage. -/
def frozenObject (capture : Capture) (dormant : List Capture) (node : NodeId) : Object → Object
  | .cell identity schema region content =>
    let frozen := (capture.frozenCells ++ dormant.flatMap Capture.frozenCells).find? (fun saved => saved.node == node)
    .cell identity schema region ((frozen.map FrozenCell.content).getD content)
  | object => object

theorem frozen_cells_are_exactly_local (heap : Heap) (regions : List RegionInstanceId) (saved : FrozenCell) :
    saved ∈ frozenCells heap regions ↔
      ∃ schema, heap.lookup saved.node = some (.cell saved.identity schema saved.region saved.content) ∧
        saved.region ∈ regions := by
  constructor
  · intro member
    obtain ⟨⟨entry, index⟩, present, selected⟩ := List.mem_filterMap.mp member
    have atIndex := List.mk_mem_zipIdx_iff_getElem?.mp present
    cases entry with
    | none => cases selected
    | some object =>
      cases object <;> simp only at selected
      all_goals try cases selected
      rename_i identity schema region content
      split at selected
      · cases selected
        refine ⟨schema, ?_, by simpa using ‹regions.contains region = true›⟩
        simp only [Heap.lookup, atIndex, Option.bind_some]
        rfl
      · cases selected
  · rintro ⟨schema, present, localRegion⟩
    have physical : heap.objects[saved.node.value]? =
        some (some (.cell saved.identity schema saved.region saved.content)) := by
      cases entry : heap.objects[saved.node.value]? with
      | none => simp [Heap.lookup, entry] at present
      | some object => simpa [Heap.lookup, entry] using present
    apply List.mem_filterMap.mpr
    refine ⟨(some (.cell saved.identity schema saved.region saved.content), saved.node.value),
      List.mk_mem_zipIdx_iff_getElem?.mpr physical, ?_⟩
    cases saved
    simp only at localRegion ⊢
    simp [localRegion]

theorem frozen_lookup_exact (heap : Heap) (regions : List RegionInstanceId) (reference : NodeId)
    (identity : CellId) (schema : SchemaId .source) (region : RegionInstanceId) (content : Located)
    (present : heap.lookup reference = some (.cell identity schema region content))
    (localRegion : region ∈ regions) :
    (frozenCells heap regions).find? (fun saved => saved.node == reference) =
      some ⟨reference, identity, region, content⟩ := by
  have member : (⟨reference, identity, region, content⟩ : FrozenCell) ∈ frozenCells heap regions :=
    (frozen_cells_are_exactly_local _ _ _).mpr ⟨schema, present, localRegion⟩
  cases found : (frozenCells heap regions).find? (fun saved => saved.node == reference) with
  | none =>
    have missing := List.find?_eq_none.mp found _ member
    simp at missing
  | some saved =>
    have sameNode : saved.node = reference := by simpa using List.find?_some found
    obtain ⟨storedSchema, stored, _⟩ := (frozen_cells_are_exactly_local _ _ _).mp
      (List.mem_of_find?_eq_some found)
    rw [sameNode, present] at stored
    have same := Object.cell.inj (Option.some.inj stored)
    cases saved
    simp only at sameNode same
    rcases same with ⟨rfl, rfl, rfl, rfl⟩
    cases sameNode
    rfl

theorem frozen_copy_reads_captured_local_storage (capturedHeap : Heap) (capture : Capture)
    (dormant : List Capture) (reference : NodeId) (identity : CellId)
    (schema : SchemaId .source) (region : RegionInstanceId) (captured current : Located)
    (snapshot : capture.frozenCells = frozenCells capturedHeap capture.localRegions)
    (present : capturedHeap.lookup reference = some (.cell identity schema region captured))
    (localRegion : region ∈ capture.localRegions) :
    frozenObject capture dormant reference (.cell identity schema region current) =
      .cell identity schema region captured := by
  have selected := frozen_lookup_exact capturedHeap capture.localRegions reference identity schema region captured present localRegion
  simp [frozenObject, snapshot, List.find?_append, selected]

/-- Every copied physical object, including dormant templates and aliased
local cells, is obtained from exactly its old object and one common renaming.
The statement exposes the map actually used by `instantiateCapture`. -/
theorem instantiation_copies_exact_objects (state after : State) (context : Context)
    (capture instantiated : Capture)
    (accepted : instantiateCapture state context capture = .ok (after, instantiated)) :
    let support := cloneSupport state.heap capture
    let dormant := support.filterMap (fun node => match state.heap.lookup node with
      | some (.multiTemplate inner) => some inner | _ => none)
    let regions := (capture.localRegions ++ dormant.flatMap Capture.localRegions).eraseDups
    let attachments := (capture.delimiter.identity :: activeAttachments capture.frames ++
      dormant.flatMap (fun inner => inner.delimiter.identity :: activeAttachments inner.frames)).eraseDups
    let copiedNodes := support.filter fun node => match state.heap.lookup node with
      | some (.cell _ _ region _) | some (.region region _ _ _) => regions.contains region
      | some (.capability identity _) => attachments.contains identity
      | some (.closure ..) | some (.multiTemplate _) => true
      | _ => false
    ∃ mapping : Renaming,
      mapping.nodes = freshMap .runtime .node state.heap.objects.length copiedNodes ∧
      instantiated = renameCapture mapping capture ∧
      ∀ reference ∈ copiedNodes, ∃ object,
        state.heap.lookup reference = some object ∧
        after.heap.lookup (renamed mapping.nodes reference) =
          some (renameObject mapping (frozenObject capture dormant reference object)) := by
  dsimp only
  unfold instantiateCapture at accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨copied, copiedKnown, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  cases accepted
  refine ⟨_, rfl, rfl, ?_⟩
  intro reference member
  obtain ⟨output, checked, atOutput⟩ := copied_lookup_at_map state.heap.objects _ _ _ copiedKnown
    ((clone_support_has_one_entry_per_object state.heap capture).filter _) reference member
  obtain ⟨object, original, checked⟩ := bind_success _ _ _ checked
  have originalLookup : state.heap.lookup reference = some object := by
    cases found : state.heap.lookup reference <;> simp [fromOption, found] at original
    subst object
    rfl
  cases checked
  refine ⟨object, originalLookup, ?_⟩
  exact congrArg (fun value => value.bind id) atOutput

end BoundaryV2.Profile.Source.Machine
