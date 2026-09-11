import BoundaryV2.SnapshotReachability

namespace BoundaryV2.Profile.Graph.Snapshot

def ReferenceValid (state : State) : Reference → Prop
  | .node reference => reference.value < state.nodes.length
  | .blob reference => reference.value < state.blobs.length

def LiveReferencesValid (state : State) : Prop :=
  ∀ reference, Reachable state reference → ReferenceValid state reference

theorem walk_complete_for_valid_references (state : State) (remaining : List NodeId)
    (pending : List Reference) (found : Discovery) (valid : LiveReferencesValid state)
    (live : ∀ reference ∈ pending, Reachable state reference) :
    ∃ result, walk state remaining pending found = some result := by
  induction remaining, pending, found using walk.induct state with
  | case1 remaining found => exact ⟨found, by rw [walk]⟩
  | case2 remaining found reference tail absent =>
    have bounded := valid _ (live _ (List.mem_cons_self ..))
    have missing := List.getElem?_eq_none_iff.mp absent
    change reference.value < state.nodes.length at bounded
    omega
  | case3 remaining found reference tail node atNode fresh ih =>
    have next := ih (by
      intro child member
      rcases List.mem_append.mp member with edge | later
      · exact .child (live _ (List.mem_cons_self ..)) atNode edge
      · exact live _ (List.mem_cons_of_mem _ later))
    rcases next with ⟨result, accepted⟩
    exact ⟨result, by simpa only [walk, atNode, fresh, ↓reduceDIte] using accepted⟩
  | case4 remaining found reference tail node atNode old ih =>
    rcases ih (fun child member => live _ (List.mem_cons_of_mem _ member)) with ⟨result, accepted⟩
    exact ⟨result, by simpa only [walk, atNode, old, ↓reduceDIte] using accepted⟩
  | case5 remaining found reference tail absent =>
    have bounded := valid _ (live _ (List.mem_cons_self ..))
    have missing := List.getElem?_eq_none_iff.mp absent
    change reference.value < state.blobs.length at bounded
    omega
  | case6 remaining found reference tail blob atBlob ih =>
    rcases ih (fun child member => live _ (List.mem_cons_of_mem _ member)) with ⟨result, accepted⟩
    exact ⟨result, by simpa [walk, atBlob] using accepted⟩

private theorem mapM_complete (f : α → Option β) (values : List α)
    (present : ∀ value ∈ values, ∃ result, f value = some result) :
    ∃ result, values.mapM f = some result := by
  induction values with
  | nil => exact ⟨[], rfl⟩
  | cons head tail ih =>
    rcases present head (List.mem_cons_self ..) with ⟨first, atHead⟩
    rcases ih (fun value member => present value (List.mem_cons_of_mem _ member)) with ⟨rest, atTail⟩
    exact ⟨first :: rest, by simp [List.mapM_cons, atHead, atTail]⟩

private theorem mapM_exact (f : α → Option β) (values : List α) (result : List β)
    (accepted : values.mapM f = some result) :
    result.length = values.length ∧ ∀ index : Nat, result[index]? = (values[index]?).bind f := by
  induction values generalizing result with
  | nil => simp at accepted; cases accepted; simp
  | cons head tail ih =>
    cases first : f head with
    | none => simp [List.mapM_cons, first] at accepted
    | some firstValue =>
      cases rest : tail.mapM f with
      | none => simp [List.mapM_cons, first, rest] at accepted
      | some restValues =>
        simp [List.mapM_cons, first, rest] at accepted
        cases accepted
        have next := ih restValues rest
        refine ⟨by simp [next.1], ?_⟩
        intro index
        cases index with
        | zero => simpa using first.symm
        | succ index => simpa using next.2 index

/-- Exact reindexing of every retained physical record. All non-reference fields,
the program identity, status and blob contents come from the original graph. -/
structure Reindexed (original : State) (found : Discovery) (normalized : State) : Prop where
  identity : normalized.programIdentity = original.programIdentity
  status : normalized.status = original.status
  roots : normalized.roots = remapRoots (renameNode found) original.roots
  blobs : normalized.blobs = found.blobs
  length : normalized.nodes.length = found.order.length
  node : ∀ (index : Nat) (reference : NodeId), found.order[index]? = some reference →
    ∃ record, original.nodes[reference.value]? = some record ∧
      normalized.nodes[index]? = some (remapNode (renameNode found) (renameBlob original found) record)

theorem materialize_exact (original : State) (found : Discovery) (normalized : State)
    (accepted : materialize original found = some normalized) : Reindexed original found normalized := by
  unfold materialize at accepted
  cases mapped : found.order.mapM (fun reference =>
    (original.nodes[reference.value]?).bind (fun node => some (remapNode (renameNode found) (renameBlob original found) node))) with
  | none => simp [mapped] at accepted
  | some nodes =>
    have fields : normalized = { original with
        roots := remapRoots (renameNode found) original.roots
        nodes := nodes
        blobs := found.blobs } := by
      simpa [mapped] using accepted.symm
    subst normalized
    have exactMap := mapM_exact _ _ _ mapped
    refine ⟨rfl, rfl, rfl, rfl, exactMap.1, ?_⟩
    intro index reference present
    have atIndex := exactMap.2 index
    rw [present] at atIndex
    have bound : index < nodes.length := by
      rw [exactMap.1]
      exact (List.getElem?_eq_some_iff.mp present).1
    cases atOriginal : original.nodes[reference.value]? with
    | none =>
      have missing : nodes[index]? = none := by simpa [atOriginal] using atIndex
      have outside := List.getElem?_eq_none_iff.mp missing
      omega
    | some record => exact ⟨record, rfl, by simpa [atOriginal] using atIndex⟩

theorem discovered_graph_materializes (original : State) (found : Discovery)
    (accepted : discover original = some found) : ∃ normalized, materialize original found = some normalized := by
  have covered := discovery_covers_roots_and_edges original found accepted
  have mapped := mapM_complete (fun reference =>
    (original.nodes[reference.value]?).bind (fun node => some (remapNode (renameNode found) (renameBlob original found) node))) found.order (by
      intro reference member
      rcases covered.2 reference member with ⟨record, present, _⟩
      exact ⟨remapNode (renameNode found) (renameBlob original found) record, by simp [present]⟩)
  rcases mapped with ⟨nodes, mapped⟩
  refine ⟨{ original with roots := remapRoots (renameNode found) original.roots, nodes := nodes, blobs := found.blobs }, ?_⟩
  simp [materialize, mapped]

theorem canonicalize_complete (original : State) (valid : LiveReferencesValid original) :
    ∃ normalized, canonicalize original = some normalized := by
  rcases walk_complete_for_valid_references original _ _ {} valid (fun _ member => .root member) with ⟨found, discovered⟩
  rcases discovered_graph_materializes original found discovered with ⟨normalized, materialized⟩
  exact ⟨normalized, by simp [canonicalize, discover, discovered, materialized]⟩

theorem canonicalize_reindexes_reachable_graph (original normalized : State)
    (accepted : canonicalize original = some normalized) :
    ∃ found, discover original = some found ∧ Reindexed original found normalized ∧
      found.order.Nodup ∧ found.blobs.Nodup ∧
      ∀ reference, reference ∈ found.order ↔ Reachable original (.node reference) := by
  unfold canonicalize at accepted
  cases discovered : discover original with
  | none => simp [discovered] at accepted
  | some found =>
    have materialized : materialize original found = some normalized := by simpa [discovered] using accepted
    have distinct := discovery_has_distinct_nodes_and_blobs original found discovered
    exact ⟨found, rfl, materialize_exact original found normalized materialized,
      distinct.1, distinct.2, discovery_exactly_reachable_nodes original found discovered⟩

theorem canonicalize_succeeds_exactly_for_valid_live_references (original : State) :
    (∃ normalized, canonicalize original = some normalized) ↔ LiveReferencesValid original := by
  constructor
  · rintro ⟨normalized, accepted⟩
    rcases canonicalize_reindexes_reachable_graph original normalized accepted with
      ⟨found, discovered, _⟩
    have covered := discovery_covers_roots_and_edges original found discovered
    intro reference reachable
    have represented := discovery_represents_reachable original found discovered reference reachable
    cases reference with
    | node reference =>
      rcases covered.2 reference represented with ⟨record, atNode, _⟩
      exact (List.getElem?_eq_some_iff.mp atNode).1
    | blob reference =>
      rcases represented with ⟨blob, atBlob, _⟩
      exact (List.getElem?_eq_some_iff.mp atBlob).1
  · exact canonicalize_complete original

theorem Reindexed.node_at_reference (indexed : Reindexed original found normalized)
    (reference : NodeId) (live : reference ∈ found.order) (record : Node)
    (present : original.nodes[reference.value]? = some record) :
    normalized.nodes[(renameNode found reference).value]? =
      some (remapNode (renameNode found) (renameBlob original found) record) := by
  have atOrder : found.order[(renameNode found reference).value]? = some reference := by
    change found.order[found.order.idxOf reference]? = some reference
    rw [List.getElem?_eq_getElem (List.idxOf_lt_length_of_mem live), List.getElem_idxOf]
  rcases indexed.node _ reference atOrder with ⟨actual, atOriginal, atNormalized⟩
  have same := Option.some.inj (atOriginal.symm.trans present)
  simpa [same] using atNormalized

theorem Reindexed.maps_references_within_bounds (indexed : Reindexed original found normalized)
    (reference : Reference) (represented : Represented original found reference) :
    ReferenceValid normalized (reference.map (renameNode found) (renameBlob original found)) := by
  cases reference with
  | node reference =>
    change (renameNode found reference).value < normalized.nodes.length
    rw [indexed.length]
    exact renaming_within_output_inventory found reference represented
  | blob reference =>
    rcases represented with ⟨blob, atBlob, live⟩
    change (renameBlob original found reference).value < normalized.blobs.length
    simp only [renameBlob, atBlob, indexed.blobs]
    exact List.idxOf_lt_length_of_mem live

theorem Reindexed.preserves_reachable_paths (indexed : Reindexed original found normalized)
    (discovered : discover original = some found) (reference : Reference)
    (reachable : Reachable original reference) :
    Reachable normalized (reference.map (renameNode found) (renameBlob original found)) := by
  induction reachable with
  | root member =>
    apply Reachable.root
    rw [indexed.roots, remapRoots_references (renameNode found) (renameBlob original found)]
    exact List.mem_map.mpr ⟨_, member, rfl⟩
  | @child parent record child parentLive atParent edge ih =>
    have live := (discovery_exactly_reachable_nodes original found discovered parent).mpr parentLive
    have atNormalized := indexed.node_at_reference parent live record atParent
    apply Reachable.child ih atNormalized
    rw [remapNode_references]
    exact List.mem_map.mpr ⟨child, edge, rfl⟩

/-- Collection does not leave any unreachable record or interned blob behind. -/
theorem canonicalize_has_no_garbage (original normalized : State)
    (accepted : canonicalize original = some normalized) :
    (∀ reference : NodeId, reference.value < normalized.nodes.length → Reachable normalized (.node reference)) ∧
    (∀ reference : BlobId, reference.value < normalized.blobs.length → Reachable normalized (.blob reference)) := by
  rcases canonicalize_reindexes_reachable_graph original normalized accepted with
    ⟨found, discovered, indexed, nodesUnique, blobsUnique, liveNodes⟩
  have allLive := walk_collects_only_reachable original _ _ {} found discovered
    (fun _ member => .root member) (by constructor <;> simp)
  constructor
  · intro reference bounded
    have indexBound : reference.value < found.order.length := by simpa [indexed.length] using bounded
    let old := found.order[reference.value]'indexBound
    have oldMember : old ∈ found.order := List.getElem_mem _
    have path := indexed.preserves_reachable_paths discovered (.node old) ((liveNodes old).mp oldMember)
    have renamed : renameNode found old = reference := by
      cases reference with
      | mk index =>
        simp only [renameNode, old, nodesUnique.idxOf_getElem]
    simpa only [Reference.map, renamed] using path
  · intro reference bounded
    have indexBound : reference.value < found.blobs.length := by simpa [indexed.blobs] using bounded
    let blob := found.blobs[reference.value]'indexBound
    have blobMember : blob ∈ found.blobs := List.getElem_mem _
    rcases allLive.2 blob blobMember with ⟨old, oldLive, atOld⟩
    have path := indexed.preserves_reachable_paths discovered (.blob old) oldLive
    have renamed : renameBlob original found old = reference := by
      cases reference with
      | mk index => simp only [renameBlob, atOld, blob, blobsUnique.idxOf_getElem]
    simpa only [Reference.map, renamed] using path

theorem canonicalize_has_no_dangling_references (original normalized : State)
    (accepted : canonicalize original = some normalized) :
    (∀ reference ∈ rootReferences normalized.roots, ReferenceValid normalized reference) ∧
    (∀ (index : Nat) (record : Node), normalized.nodes[index]? = some record →
      ∀ reference ∈ nodeReferences record, ReferenceValid normalized reference) := by
  rcases canonicalize_reindexes_reachable_graph original normalized accepted with
    ⟨found, discovered, indexed, _⟩
  have covered := discovery_covers_roots_and_edges original found discovered
  constructor
  · intro reference member
    rw [indexed.roots, remapRoots_references (renameNode found) (renameBlob original found)] at member
    rcases List.mem_map.mp member with ⟨old, oldMember, same⟩
    exact same ▸ indexed.maps_references_within_bounds old (covered.1 old oldMember)
  · intro index record atRecord reference member
    have indexBound : index < found.order.length := by
      rw [← indexed.length]
      exact (List.getElem?_eq_some_iff.mp atRecord).1
    let old := found.order[index]'indexBound
    have oldMember : old ∈ found.order := List.getElem_mem _
    have atOrder : found.order[index]? = some old := List.getElem?_eq_getElem indexBound
    rcases indexed.node index old atOrder with ⟨prior, atPrior, atNormalized⟩
    have sameRecord := Option.some.inj (atRecord.symm.trans atNormalized)
    rw [sameRecord, remapNode_references] at member
    rcases List.mem_map.mp member with ⟨child, edge, same⟩
    rcases covered.2 old oldMember with ⟨actual, atActual, children⟩
    have samePrior := Option.some.inj (atActual.symm.trans atPrior)
    exact same ▸ indexed.maps_references_within_bounds child (children child (by simpa [samePrior] using edge))

end BoundaryV2.Profile.Graph.Snapshot
