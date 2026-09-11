import BoundaryV2.SnapshotCollection
import BoundaryV2.GraphRemapping

namespace BoundaryV2.Profile.Graph.Snapshot

/-- A relocation preserves every reachable physical record and immutable blob.
Node identity is injective on live nodes; blob identity may coalesce equal data.
Unreachable storage imposes no correspondence obligation. -/
structure Relocation (original relocated : State)
    (nodes : NodeId → NodeId) (blobs : BlobId → BlobId) : Prop where
  node : ∀ reference record, Reachable original (.node reference) →
    original.nodes[reference.value]? = some record →
    relocated.nodes[(nodes reference).value]? = some (remapNode nodes blobs record)
  blob : ∀ reference content, Reachable original (.blob reference) →
    original.blobs[reference.value]? = some content →
    relocated.blobs[(blobs reference).value]? = some content
  injective : ∀ left right, Reachable original (.node left) → Reachable original (.node right) →
    nodes left = nodes right → left = right

def Discovery.relocate (nodes : NodeId → NodeId) (found : Discovery) : Discovery :=
  { order := found.order.map nodes, blobs := found.blobs }

theorem walk_relocates (original relocated : State) (nodes : NodeId → NodeId)
    (blobs : BlobId → BlobId) (relocation : Relocation original relocated nodes blobs)
    (remaining : List NodeId) (pending : List Reference) (found result : Discovery)
    (accepted : walk original remaining pending found = some result)
    (live : ∀ reference ∈ pending, Reachable original reference)
    (remainingUnique : remaining.Nodup) (otherRemaining : List NodeId)
    (otherUnique : otherRemaining.Nodup)
    (unvisited : ∀ reference, Reachable original (.node reference) →
      (nodes reference ∈ otherRemaining ↔ reference ∈ remaining)) :
    walk relocated otherRemaining (pending.map (Reference.map nodes blobs)) (found.relocate nodes) =
      some (result.relocate nodes) := by
  induction remaining, pending, found using walk.induct original generalizing result otherRemaining with
  | case1 remaining found =>
    simp only [walk, Option.some.injEq] at accepted
    cases accepted
    simp only [List.map_nil, walk]
  | case2 remaining found reference tail absent => simp [walk, absent] at accepted
  | case3 remaining found reference tail record atNode fresh ih =>
    simp only [walk, atNode, fresh, ↓reduceDIte] at accepted
    have headLive := live _ (List.mem_cons_self ..)
    have relocatedNode := relocation.node reference record headLive atNode
    have relocatedFresh := (unvisited reference headLive).mpr fresh
    have next := ih result accepted (by
      intro child member
      rcases List.mem_append.mp member with edge | later
      · exact .child headLive atNode edge
      · exact live _ (List.mem_cons_of_mem _ later))
      (remainingUnique.erase reference) (otherRemaining.erase (nodes reference))
      (otherUnique.erase _) (by
        intro other otherLive
        rw [otherUnique.mem_erase_iff, remainingUnique.mem_erase_iff,
          unvisited other otherLive]
        have same : nodes other = nodes reference ↔ other = reference :=
          ⟨relocation.injective other reference otherLive headLive, congrArg nodes⟩
        simp only [ne_eq, same])
    simpa only [List.map_cons, Reference.map, walk, relocatedNode, relocatedFresh, ↓reduceDIte,
      remapNode_references, List.map_append, List.map_singleton, List.map_nil, Discovery.relocate] using next
  | case4 remaining found reference tail record atNode old ih =>
    simp only [walk, atNode, old, ↓reduceDIte] at accepted
    have headLive := live _ (List.mem_cons_self ..)
    have relocatedNode := relocation.node reference record headLive atNode
    have relocatedOld : nodes reference ∉ otherRemaining := by
      intro member
      exact old ((unvisited reference headLive).mp member)
    have next := ih result accepted (fun child member => live _ (List.mem_cons_of_mem _ member))
      remainingUnique otherRemaining otherUnique unvisited
    simpa only [List.map_cons, Reference.map, walk, relocatedNode, relocatedOld, ↓reduceDIte] using next
  | case5 remaining found reference tail absent => simp [walk, absent] at accepted
  | case6 remaining found reference tail content atBlob ih =>
    simp only [walk, atBlob] at accepted
    have relocatedBlob := relocation.blob reference content (live _ (List.mem_cons_self ..)) atBlob
    have next := ih result accepted (fun child member => live _ (List.mem_cons_of_mem _ member))
      remainingUnique otherRemaining otherUnique unvisited
    simpa only [List.map_cons, Reference.map, walk, relocatedBlob, Discovery.relocate, dite_eq_ite] using next

theorem Reindexed.relocation (indexed : Reindexed original found normalized)
    (discovered : discover original = some found) :
    Relocation original normalized (renameNode found) (renameBlob original found) := by
  have represented := discovery_represents_reachable original found discovered
  refine ⟨?_, ?_, ?_⟩
  · intro reference record live present
    exact indexed.node_at_reference reference (represented _ live) record present
  · intro reference content live present
    rcases represented _ live with ⟨actual, atActual, member⟩
    have same := Option.some.inj (atActual.symm.trans present)
    subst actual
    simp only [renameBlob, present, indexed.blobs]
    rw [List.getElem?_eq_getElem (List.idxOf_lt_length_of_mem member), List.getElem_idxOf]
  · intro left right leftLive rightLive equal
    exact (renaming_injective_on_live_nodes found left right (represented _ leftLive)
      (represented _ rightLive)).mp equal

private theorem inventory_unique (size : Nat) :
    ((List.range size).map (fun index => (⟨index⟩ : NodeId))).Nodup := by
  apply List.nodup_range.map
  intro left right different same
  exact different (congrArg Ref.value same)

private theorem mem_inventory (size : Nat) (reference : NodeId) :
    reference ∈ (List.range size).map (fun index => (⟨index⟩ : NodeId)) ↔ reference.value < size := by
  constructor
  · intro member
    rcases List.mem_map.mp member with ⟨index, bounded, same⟩
    simpa [← same] using List.mem_range.mp bounded
  · intro bounded
    exact List.mem_map.mpr ⟨reference.value, List.mem_range.mpr bounded, by cases reference; rfl⟩

theorem discover_relocates (original relocated : State) (nodes : NodeId → NodeId)
    (blobs : BlobId → BlobId) (relocation : Relocation original relocated nodes blobs)
    (roots : rootReferences relocated.roots = (rootReferences original.roots).map (Reference.map nodes blobs))
    (found : Discovery) (accepted : discover original = some found) :
    discover relocated = some (found.relocate nodes) := by
  have represented := discovery_represents_reachable original found accepted
  have covered := discovery_covers_roots_and_edges original found accepted
  unfold discover
  rw [roots]
  apply walk_relocates original relocated nodes blobs relocation _ _ {} found accepted
    (fun _ member => .root member) (inventory_unique _) _ (inventory_unique _)
  intro reference live
  rcases covered.2 reference (represented _ live) with ⟨record, atNode, _⟩
  rw [mem_inventory, mem_inventory]
  exact iff_of_true (List.getElem?_eq_some_iff.mp (relocation.node reference record live atNode)).1
    (List.getElem?_eq_some_iff.mp atNode).1

theorem renamed_discovery_order (found : Discovery) (unique : found.order.Nodup) :
    found.order.map (renameNode found) = (List.range found.order.length).map (fun index => ⟨index⟩) := by
  apply List.ext_getElem
  · simp
  · intro index leftBound rightBound
    simp only [List.getElem_map, List.getElem_range, renameNode, unique.idxOf_getElem]

theorem discover_after_collection (original normalized : State)
    (accepted : canonicalize original = some normalized) :
    discover normalized = some {
      order := (List.range normalized.nodes.length).map (fun index => ⟨index⟩)
      blobs := normalized.blobs } := by
  rcases canonicalize_reindexes_reachable_graph original normalized accepted with
    ⟨found, discovered, indexed, unique, _⟩
  have again := discover_relocates original normalized (renameNode found) (renameBlob original found)
    (indexed.relocation discovered) (by rw [indexed.roots, remapRoots_references]) found discovered
  simpa only [Discovery.relocate, renamed_discovery_order found unique, indexed.length, indexed.blobs] using again

def inventory (state : State) : Discovery :=
  { order := (List.range state.nodes.length).map (fun index => ⟨index⟩), blobs := state.blobs }

private theorem inventory_node_at (state : State) (index : Nat) (bounded : index < state.nodes.length) :
    (inventory state).order[index]? = some ⟨index⟩ := by simp [inventory, bounded]

theorem inventory_renames_node_to_self (state : State) (reference : NodeId)
    (bounded : reference.value < state.nodes.length) : renameNode (inventory state) reference = reference := by
  have member : reference.value < (inventory state).order.length := by simpa [inventory] using bounded
  have atIndex : (inventory state).order[reference.value]'member = reference := by
    simp only [inventory, List.getElem_map, List.getElem_range]
  have unique : (inventory state).order.Nodup := inventory_unique state.nodes.length
  have same := unique.idxOf_getElem reference.value member
  rw [atIndex] at same
  cases reference with | mk index => simp only [renameNode, same]

theorem inventory_renames_blob_to_self (state : State) (unique : state.blobs.Nodup)
    (reference : BlobId) (bounded : reference.value < state.blobs.length) :
    renameBlob state (inventory state) reference = reference := by
  have present := List.getElem?_eq_getElem bounded
  cases reference with | mk index =>
    simp only [renameBlob, present, inventory, unique.idxOf_getElem]

theorem inventory_fixes_valid_reference (state : State) (unique : state.blobs.Nodup)
    (reference : Reference) (valid : ReferenceValid state reference) :
    reference.map (renameNode (inventory state)) (renameBlob state (inventory state)) = reference := by
  cases reference with
  | node reference => exact congrArg Reference.node (inventory_renames_node_to_self state reference valid)
  | blob reference => exact congrArg Reference.blob (inventory_renames_blob_to_self state unique reference valid)

/-- Saving an already collected graph is a fixed point, for arbitrary finite
graphs including cycles and aliases. This concerns snapshot data, not execution. -/
theorem canonicalize_idempotent (original normalized : State)
    (accepted : canonicalize original = some normalized) : canonicalize normalized = some normalized := by
  have again : discover normalized = some (inventory normalized) := discover_after_collection original normalized accepted
  have unique := (discovery_has_distinct_nodes_and_blobs normalized (inventory normalized) again).2
  have valid := canonicalize_has_no_dangling_references original normalized accepted
  rcases discovered_graph_materializes normalized (inventory normalized) again with ⟨result, materialized⟩
  have indexed := materialize_exact normalized (inventory normalized) result materialized
  have rootSame : result.roots = normalized.roots := indexed.roots.trans
    (remapRoots_identity_on_references normalized.roots (fun reference member =>
      inventory_fixes_valid_reference normalized unique reference (valid.1 reference member)))
  have nodeSame : result.nodes = normalized.nodes := by
    apply List.ext_getElem?
    intro index
    by_cases bounded : index < normalized.nodes.length
    · have atOrder := inventory_node_at normalized index bounded
      rcases indexed.node index ⟨index⟩ atOrder with ⟨record, present, atResult⟩
      have fixed := remapNode_identity_on_references record (fun reference member =>
        inventory_fixes_valid_reference normalized unique reference (valid.2 index record present reference member))
      exact (atResult.trans (congrArg some fixed)).trans present.symm
    · have resultBound : result.nodes.length ≤ index := by simpa [indexed.length, inventory] using Nat.le_of_not_gt bounded
      rw [List.getElem?_eq_none resultBound, List.getElem?_eq_none (Nat.le_of_not_gt bounded)]
  have same : result = normalized := by
    cases result
    cases normalized
    simp only [State.mk.injEq]
    exact ⟨indexed.identity, indexed.status, rootSame, nodeSame, indexed.blobs⟩
  simp only [canonicalize, again, bind, Option.bind, materialized, same]

theorem encode_after_collection (original normalized : State)
    (accepted : canonicalize original = some normalized) : encode original = encode normalized := by
  simp only [encode, accepted, canonicalize_idempotent original normalized accepted]

end BoundaryV2.Profile.Graph.Snapshot
