import BoundaryV2.SnapshotRelocation

namespace BoundaryV2.Profile.Graph.Snapshot

private theorem rename_relocated_node (found : Discovery) (nodes : NodeId → NodeId)
    (unique : (found.order.map nodes).Nodup) (reference : NodeId) (member : reference ∈ found.order) :
    renameNode (found.relocate nodes) (nodes reference) = renameNode found reference := by
  have bounded := List.idxOf_lt_length_of_mem member
  have mappedBound : found.order.idxOf reference < (found.order.map nodes).length := by simpa using bounded
  have atIndex : (found.order.map nodes)[found.order.idxOf reference]'mappedBound = nodes reference := by
    simp only [List.getElem_map, List.getElem_idxOf]
  have same := unique.idxOf_getElem (found.order.idxOf reference) mappedBound
  rw [atIndex] at same
  exact congrArg Ref.mk same

theorem Relocation.canonical_reference (relocation : Relocation original relocated nodes blobs)
    (discovered : discover original = some found)
    (otherUnique : (found.order.map nodes).Nodup)
    (reference : Reference) (live : Reachable original reference) :
    reference.map (renameNode (found.relocate nodes) ∘ nodes)
      (renameBlob relocated (found.relocate nodes) ∘ blobs) =
        reference.map (renameNode found) (renameBlob original found) := by
  have represented := discovery_represents_reachable original found discovered reference live
  cases reference with
  | node reference => exact congrArg Reference.node (rename_relocated_node found nodes otherUnique reference represented)
  | blob reference =>
    rcases represented with ⟨content, atBlob, _⟩
    have atRelocated := relocation.blob reference content live atBlob
    simp only [Reference.map, Function.comp_def, renameBlob, atBlob, atRelocated, Discovery.relocate]

/-- Canonical snapshots are independent of live-node allocation numbers and
blob positions. The relocation may also add or remove arbitrary unreachable
storage and coalesce blobs with equal complete content. Root roles, status,
program identity, and every reachable record must be preserved. -/
theorem canonicalize_under_relocation (original relocated normalized : State)
    (nodes : NodeId → NodeId) (blobs : BlobId → BlobId)
    (relocation : Relocation original relocated nodes blobs)
    (roots : relocated.roots = remapRoots nodes original.roots)
    (identity : relocated.programIdentity = original.programIdentity)
    (status : relocated.status = original.status)
    (accepted : canonicalize original = some normalized) :
    canonicalize relocated = some normalized := by
  rcases canonicalize_reindexes_reachable_graph original normalized accepted with
    ⟨found, discovered, indexed, _, _, liveNodes⟩
  have relocatedDiscovery := discover_relocates original relocated nodes blobs relocation
    (by rw [roots, remapRoots_references]) found discovered
  have otherUnique := (discovery_has_distinct_nodes_and_blobs relocated (found.relocate nodes) relocatedDiscovery).1
  have sameReference := relocation.canonical_reference discovered otherUnique
  rcases discovered_graph_materializes relocated (found.relocate nodes) relocatedDiscovery with ⟨result, materialized⟩
  have other := materialize_exact relocated (found.relocate nodes) result materialized
  have sameRoots : result.roots = normalized.roots := by
    rw [other.roots, roots, remapRoots_compose, indexed.roots]
    apply remapRoots_congr
      (b₁ := renameBlob relocated (found.relocate nodes) ∘ blobs) (b₂ := renameBlob original found)
    intro reference member
    exact sameReference reference (.root member)
  have sameNodes : result.nodes = normalized.nodes := by
    apply List.ext_getElem?
    intro index
    by_cases bounded : index < found.order.length
    · let reference := found.order[index]'bounded
      have atOrder : found.order[index]? = some reference := List.getElem?_eq_getElem bounded
      have referenceLive := (liveNodes reference).mp (List.getElem_mem _)
      have atRelocatedOrder : (found.relocate nodes).order[index]? = some (nodes reference) := by
        simp only [Discovery.relocate, List.getElem?_map, atOrder, Option.map_some]
      rcases indexed.node index reference atOrder with ⟨record, atOriginal, atNormalized⟩
      rcases other.node index (nodes reference) atRelocatedOrder with ⟨relocatedRecord, atRelocated, atResult⟩
      have expected := relocation.node reference record referenceLive atOriginal
      have sameRecord := Option.some.inj (atRelocated.symm.trans expected)
      rw [sameRecord, remapNode_compose] at atResult
      have sameMapped : remapNode (renameNode (found.relocate nodes) ∘ nodes)
          (renameBlob relocated (found.relocate nodes) ∘ blobs) record =
            remapNode (renameNode found) (renameBlob original found) record := by
        apply remapNode_congr
        intro child edge
        exact sameReference child (.child referenceLive atOriginal edge)
      rw [sameMapped] at atResult
      exact atResult.trans atNormalized.symm
    · have leftBound : result.nodes.length ≤ index := by
        simpa only [other.length, Discovery.relocate, List.length_map] using Nat.le_of_not_gt bounded
      have rightBound : normalized.nodes.length ≤ index := by
        simpa only [indexed.length] using Nat.le_of_not_gt bounded
      rw [List.getElem?_eq_none leftBound, List.getElem?_eq_none rightBound]
  have same : result = normalized := by
    have sameIdentity := (other.identity.trans identity).trans indexed.identity.symm
    have sameStatus := (other.status.trans status).trans indexed.status.symm
    have sameBlobs := other.blobs.trans indexed.blobs.symm
    cases result
    cases normalized
    simp only [State.mk.injEq]
    exact ⟨sameIdentity, sameStatus, sameRoots, sameNodes, sameBlobs⟩
  simp only [canonicalize, relocatedDiscovery, bind, Option.bind, materialized, same]

theorem canonical_bytes_under_relocation (original relocated normalized : State)
    (nodes : NodeId → NodeId) (blobs : BlobId → BlobId)
    (relocation : Relocation original relocated nodes blobs)
    (roots : relocated.roots = remapRoots nodes original.roots)
    (identity : relocated.programIdentity = original.programIdentity)
    (status : relocated.status = original.status)
    (accepted : canonicalize original = some normalized) : encode original = encode relocated := by
  have same := canonicalize_under_relocation original relocated normalized nodes blobs relocation roots identity status accepted
  simp only [encode, accepted, same]

theorem decode_encode_canonical (original normalized : State)
    (accepted : canonicalize original = some normalized)
    (widths : Images.rawState.valid normalized = true) :
    decode (Images.rawState.encode normalized) = some normalized := by
  have read : Images.rawState.read (Images.rawState.encode normalized) = some (normalized, []) :=
    by simpa using Images.rawState.readComplete normalized [] widths
  simp [decode, read, canonicalize_idempotent original normalized accepted]

end BoundaryV2.Profile.Graph.Snapshot
