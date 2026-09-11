import BoundaryV2.SnapshotCanonical

namespace BoundaryV2.Profile.Graph.Snapshot

/-- Finite support may omit garbage. Every referenced mutable node remains a
separate identity; immutable blobs are compared by their complete contents. -/
def referenceCovered (original : State) (found : Discovery) : Reference → Bool
  | .node reference => found.order.contains reference
  | .blob reference => original.blobs[reference.value]?.any found.blobs.contains

/-- A support row covers all outgoing references and preserves the complete
record under the existing snapshot renaming. -/
def nodeMatches (original normalized : State) (found : Discovery) (reference : NodeId) : Bool :=
  original.nodes[reference.value]?.any (fun record =>
    normalized.nodes[(renameNode found reference).value]? ==
      some (remapNode (renameNode found) (renameBlob original found) record) &&
    (nodeReferences record).all (referenceCovered original found))

theorem reference_covered_iff (original : State) (found : Discovery) (reference : Reference) :
    referenceCovered original found reference = true ↔ Represented original found reference := by
  cases reference <;> simp [referenceCovered, Represented, Option.any_eq_true]

theorem matching_support_covers_live_references (original normalized : State) (found : Discovery)
    (roots : (rootReferences original.roots).all (referenceCovered original found) = true)
    (records : found.order.all (nodeMatches original normalized found) = true) :
    ∀ reference, Reachable original reference → Represented original found reference := by
  intro reference live
  induction live with
  | root member => exact (reference_covered_iff _ _ _).mp (List.all_eq_true.mp roots _ member)
  | child prior atNode edge induction =>
    have checked := List.all_eq_true.mp records _ induction
    simp only [nodeMatches, atNode, Option.any_some, Bool.and_eq_true] at checked
    exact (reference_covered_iff _ _ _).mp (List.all_eq_true.mp checked.2 _ edge)

theorem matching_support_has_valid_live_references (original normalized : State) (found : Discovery)
    (roots : (rootReferences original.roots).all (referenceCovered original found) = true)
    (records : found.order.all (nodeMatches original normalized found) = true) : LiveReferencesValid original := by
  have represented := matching_support_covers_live_references original normalized found roots records
  intro reference live
  have covered := represented reference live
  cases reference with
  | node reference =>
    have checked := List.all_eq_true.mp records reference covered
    obtain ⟨record, atNode, _⟩ := (Option.any_eq_true _ _).mp checked
    exact (List.getElem?_eq_some_iff.mp atNode).1
  | blob reference =>
    obtain ⟨blob, atBlob, _⟩ := covered
    exact (List.getElem?_eq_some_iff.mp atBlob).1

theorem relocation_of_matching_support (original normalized : State) (found : Discovery)
    (roots : (rootReferences original.roots).all (referenceCovered original found) = true)
    (records : found.order.all (nodeMatches original normalized found) = true)
    (blobs : normalized.blobs = found.blobs) :
    Relocation original normalized (renameNode found) (renameBlob original found) := by
  have represented := matching_support_covers_live_references original normalized found roots records
  constructor
  · intro reference record live atNode
    have checked := List.all_eq_true.mp records reference (represented _ live)
    simp only [nodeMatches, atNode, Option.any_some, Bool.and_eq_true, beq_iff_eq] at checked
    exact checked.1
  · intro reference content live present
    obtain ⟨actual, atActual, member⟩ := represented _ live
    have same := Option.some.inj (atActual.symm.trans present)
    subst actual
    simp only [renameBlob, present, blobs]
    rw [List.getElem?_eq_getElem (List.idxOf_lt_length_of_mem member), List.getElem_idxOf]
  · intro left right leftLive rightLive same
    exact (renaming_injective_on_live_nodes found left right (represented _ leftLive)
      (represented _ rightLive)).mp same

/-- Checking the compact graph and its complete live-record correspondence
proves the original normalizer's exact result, without evaluating its traversal
through all physical garbage during proof construction. -/
theorem canonicalize_of_matching_support (original normalized : State) (found : Discovery)
    (roots : (rootReferences original.roots).all (referenceCovered original found) = true)
    (records : found.order.all (nodeMatches original normalized found) = true)
    (blobs : normalized.blobs = found.blobs)
    (rootMap : normalized.roots = remapRoots (renameNode found) original.roots)
    (identity : normalized.programIdentity = original.programIdentity)
    (status : normalized.status = original.status)
    (canonical : canonicalize normalized = some normalized) : canonicalize original = some normalized := by
  obtain ⟨result, accepted⟩ := canonicalize_complete original
    (matching_support_has_valid_live_references original normalized found roots records)
  have relocated := canonicalize_under_relocation original normalized result (renameNode found) (renameBlob original found)
    (relocation_of_matching_support original normalized found roots records blobs) rootMap identity status accepted
  have same := Option.some.inj (relocated.symm.trans canonical)
  exact same ▸ accepted

/-- Every successful canonicalization supplies this finite correspondence,
including shared/cyclic nodes and coalesced immutable blobs. -/
theorem canonicalization_has_matching_support (original normalized : State)
    (accepted : canonicalize original = some normalized) :
    ∃ found : Discovery,
      (rootReferences original.roots).all (referenceCovered original found) = true ∧
      found.order.all (nodeMatches original normalized found) = true ∧
      normalized.blobs = found.blobs ∧
      normalized.roots = remapRoots (renameNode found) original.roots ∧
      normalized.programIdentity = original.programIdentity ∧
      normalized.status = original.status ∧
      canonicalize normalized = some normalized := by
  obtain ⟨found, discovered, indexed, _, _, _⟩ := canonicalize_reindexes_reachable_graph original normalized accepted
  have covered := discovery_covers_roots_and_edges original found discovered
  refine ⟨found, ?_, ?_, indexed.blobs, indexed.roots, indexed.identity, indexed.status,
    canonicalize_idempotent original normalized accepted⟩
  · apply List.all_eq_true.mpr
    intro reference member
    exact (reference_covered_iff _ _ _).mpr (covered.1 reference member)
  · apply List.all_eq_true.mpr
    intro reference member
    obtain ⟨record, atNode, children⟩ := covered.2 reference member
    have matched := indexed.node_at_reference reference member record atNode
    simp only [nodeMatches, atNode, Option.any_some, Bool.and_eq_true, beq_iff_eq]
    refine ⟨matched, List.all_eq_true.mpr ?_⟩
    intro child edge
    exact (reference_covered_iff _ _ _).mpr (children child edge)

end BoundaryV2.Profile.Graph.Snapshot
