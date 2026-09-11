import BoundaryV2.SnapshotCanonical

namespace BoundaryV2.Profile.Graph.Snapshot.Examples

private theorem reference_literal (n : Nat) : (OfNat.ofNat n : Ref space domain) = ⟨n⟩ := rfl

def zeroDigest : Digest := (Vector.replicate 32 0)
def blobValue (id : Nat) : Value := ⟨17, .blob ⟨id⟩⟩
def nodeValue (id : Nat) : Value := ⟨23, .reference ⟨id⟩⟩
def ownedValue (id : Nat) : Value := ⟨29, .owned ⟨⟨id⟩⟩⟩
def scalarValue : Value := ⟨31, .scalar #[0, 1, 2, 3, 254, 255, 0, 4].toVector⟩
def values : List Value := [blobValue 2, nodeValue 2, scalarValue, ownedValue 1, blobValue 1, blobValue 0]
def capture : Capture := ⟨37, some 2, 1, some 3, values⟩
def exitRecord (reason : ExitReason) : Exit := ⟨reason, values, some (.bytes [1, 2, 3]), some 2, some 3, values.reverse⟩

/-- Covers each physical record tag, optional reference, capture and exit field.
These are raw graph codec cases, not program-admitted execution states. -/
def nodeCases : List (String × Node) := [
  ("control", .control ⟨41, values, some 1, some 2, some 3⟩),
  ("continuation", .continuation ⟨43, [none, some (blobValue 2), some (nodeValue 1), none,
    some (ownedValue 2), some scalarValue], some 3, some 2, some 1⟩),
  ("handler", .handler 47 values (some 2) (some 3)),
  ("attachment-active", .attachment 1 (some 2) (some 3) .active (some 2)),
  ("attachment-suspended", .attachment 2 (some 1) (some 3) .suspended (some 1)),
  ("environment", .environment values (some 3)),
  ("aggregate", .aggregate 53 59 values),
  ("region", .region 61 (some 3) [⟨2⟩, ⟨1⟩, ⟨2⟩]),
  ("region-scope", .regionScope 67 2 (some 1)),
  ("injection", .injection 2),
  ("protection", .protection 71 ⟨2⟩ (some 3) (some 1) (some 2) (some 3)),
  ("cleanup-return", .cleanupReturn ⟨2⟩ (some 3) 1),
  ("disposal-return", .disposalReturn 73 (some 2) values),
  ("unwind", .unwind (some 2) values),
  ("cell", .cell 79 3 (some (blobValue 2))),
  ("cell-empty", .cell 79 1 none),
  ("one-shot", .oneShot capture),
  ("one-shot-spent", .oneShot { capture with capture := none }),
  ("multi-template", .multiTemplate capture),
  ("branch", .branch 3 2 [(1, 2), (2, 3), (1, 2)]),
  ("package", .package 83 (ownedValue 2)),
  ("computation", .computation 89 2),
  ("resource", .resource 97 (blobValue 2)),
  ("borrow", .borrow 101 2 3),
  ("obligation-pending", .obligation 103 (some (blobValue 2)) (some (ownedValue 1)) .pending),
  ("obligation-running", .obligation 107 (some (blobValue 1)) (some (nodeValue 2)) (.running 3)),
  ("obligation-completed", .obligation 109 none none .completed),
  ("obligation-failed", .obligation 113 (some (nodeValue 1)) (some (blobValue 2)) (.failed (blobValue 0))),
  ("pending", .pending 127 (blobValue 2) 3 131),
  ("exit-normal", .exit (exitRecord (.normal (blobValue 2)))),
  ("exit-failure", .exit (exitRecord (.failure (ownedValue 2)))),
  ("exit-cancellation", .exit (exitRecord .cancellation)),
  ("exit-abandoned", .exit (exitRecord .abandoned))]

def caseState (node : Node) : State := ⟨zeroDigest, .active, { current := some 0 }, [
  node,
  .environment [blobValue 0, blobValue 2] (some 3),
  .aggregate 137 139 [nodeValue 1, blobValue 1, blobValue 2, ownedValue 1],
  .environment [nodeValue 1, blobValue 3] (some 1),
  .injection 999],
  [⟨17, [9, 8, 7]⟩, ⟨17, [9, 8, 7]⟩, ⟨17, [0, 255, 128]⟩, ⟨19, [0, 255, 128]⟩,
    ⟨17, [200]⟩]⟩

def cycle : State := ⟨zeroDigest, .active, { current := some 1 }, [
  .region 0 none [],
  .control { block := 0, arguments := [nodeValue 2, nodeValue 2] },
  .cell 23 0 (some (nodeValue 2)),
  .injection 999], []⟩

def normalizedCycle : State := ⟨zeroDigest, .active, { current := some 0 }, [
  .control { block := 0, arguments := [nodeValue 1, nodeValue 1] },
  .cell 23 2 (some (nodeValue 1)),
  .region 0 none []], []⟩

theorem cycle_aliases_preserved_and_garbage_removed : canonicalize cycle = some normalizedCycle := by
  have discovery : discover cycle = some ⟨[1, 2, 0], []⟩ := by
    change walk cycle [0, 1, 2, 3] [.node 1] {} = _
    simp [reference_literal, walk, cycle, nodeReferences, valuesReferences, valueReferences, optionalReferences, nodeValue]
  rw [canonicalize, discovery]
  decide +kernel

theorem cycle_normalization_idempotent : canonicalize normalizedCycle = some normalizedCycle := by
  exact canonicalize_idempotent cycle normalizedCycle cycle_aliases_preserved_and_garbage_removed

theorem cycle_normalized_bytes_admitted : decode (Images.rawState.encode normalizedCycle) = some normalizedCycle := by
  exact decode_encode_canonical cycle normalizedCycle cycle_aliases_preserved_and_garbage_removed (by decide +kernel)

theorem noncanonical_cycle_bytes_rejected : decode (Images.rawState.encode cycle) = none := by
  have parsed := Images.rawState.readComplete cycle [] (by decide +kernel)
  simp only [List.append_nil] at parsed
  simp only [decode, parsed, bind, Option.bind, List.isEmpty_nil, Bool.not_true, Bool.false_eq_true,
    ↓reduceIte, cycle_aliases_preserved_and_garbage_removed]
  decide +kernel

def equalNodes : State := ⟨zeroDigest, .active, { current := some 0 }, [
  .control { block := 0, arguments := [nodeValue 1, nodeValue 2, nodeValue 1] },
  .environment [] none, .environment [] none], []⟩

theorem equal_node_records_keep_distinct_identity : canonicalize equalNodes = some equalNodes := by
  have discovery : discover equalNodes = some ⟨[0, 1, 2], []⟩ := by
    change walk equalNodes [0, 1, 2] [.node 0] {} = _
    simp [reference_literal, walk, equalNodes, nodeReferences, valuesReferences, valueReferences, optionalReferences, nodeValue]
  rw [canonicalize, discovery]
  decide +kernel

def blobGraph : State := ⟨zeroDigest, .active, { current := some 0 }, [
  .control { block := 0, arguments := [blobValue 2, blobValue 1, blobValue 0] }],
  [⟨17, [1, 2]⟩, ⟨17, [1, 2]⟩, ⟨19, [1, 2]⟩]⟩

def normalizedBlobs : State := ⟨zeroDigest, .active, { current := some 0 }, [
  .control { block := 0, arguments := [blobValue 0, blobValue 1, blobValue 1] }],
  [⟨19, [1, 2]⟩, ⟨17, [1, 2]⟩]⟩

theorem blobs_merge_only_with_equal_schema_and_bytes : canonicalize blobGraph = some normalizedBlobs := by
  have discovery : discover blobGraph = some ⟨[0], normalizedBlobs.blobs⟩ := by
    change walk blobGraph [0] [.node 0] {} = _
    simp [reference_literal, walk, blobGraph, normalizedBlobs, nodeReferences, valuesReferences, valueReferences, optionalReferences, blobValue]
  rw [canonicalize, discovery]
  decide +kernel

def invalidNode : State := { equalNodes with roots := { current := some 999 } }
def invalidBlob : State := { blobGraph with blobs := [] }
theorem dangling_node_rejected : canonicalize invalidNode = none := by
  simp [reference_literal, canonicalize, discover, walk, invalidNode, equalNodes, rootReferences, optionalReferences]
theorem dangling_blob_rejected : canonicalize invalidBlob = none := by
  simp [reference_literal, canonicalize, discover, walk, invalidBlob, blobGraph, rootReferences, optionalReferences,
    nodeReferences, valuesReferences, valueReferences, blobValue]

def allCases : List (String × State) := (nodeCases.map (fun (name, node) => (name, caseState node))) ++ [
  ("cycle", cycle), ("equal-nodes", equalNodes), ("blob-interning", blobGraph),
  ("root-order", { caseState (.environment [] none) with
    roots := ⟨some 3, some 2, [⟨1⟩, ⟨0⟩, ⟨2⟩], some 1, some 2⟩ }),
  ("empty-roots", { cycle with roots := {} }),
  ("invalid-node", invalidNode), ("invalid-blob", invalidBlob)]

end BoundaryV2.Profile.Graph.Snapshot.Examples
