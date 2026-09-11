import BoundaryV2.SnapshotExamples

open BoundaryV2.Profile
open BoundaryV2.Profile.Graph

/-- Data-only conformance fixture emission. It is separate from certification. -/
def main (args : List String) : IO UInt32 := do
  let [directory] := args | throw <| IO.userError "usage: snapshot_conformance.lean <output-directory>"
  let directory : System.FilePath := directory
  for (_, node) in Snapshot.Examples.nodeCases do
    IO.println s!"tag\t{Codecs.nodeTagName (Codecs.nodeView node).1}"
  for (name, state) in Snapshot.Examples.allCases do
    if !Images.rawState.valid state then throw <| IO.userError s!"snapshot.invalid_raw_fixture: {name}"
    let raw := Images.rawState.encode state
    if Images.rawState.decode raw != some state then throw <| IO.userError s!"snapshot.raw_roundtrip: {name}"
    IO.FS.writeBinFile (directory / s!"{name}.raw.pst2") ⟨raw.toArray⟩
    match Snapshot.canonicalize state with
    | none =>
      if (Snapshot.decode raw).isSome then throw <| IO.userError s!"snapshot.invalid_admitted: {name}"
      IO.println s!"case\t{name}\tinvalid\tfalse"
    | some normalized =>
      let some canonical := Snapshot.encode state
        | throw <| IO.userError s!"snapshot.normalized_not_encodable: {name}"
      if Snapshot.canonicalize normalized != some normalized then
        throw <| IO.userError s!"snapshot.not_idempotent: {name}"
      if Snapshot.decode canonical != some normalized then
        throw <| IO.userError s!"snapshot.canonical_roundtrip: {name}"
      if (Snapshot.decode raw).isSome != (raw == canonical) then
        throw <| IO.userError s!"snapshot.raw_admission: {name}"
      IO.FS.writeBinFile (directory / s!"{name}.canonical.pst2") ⟨canonical.toArray⟩
      IO.println s!"case\t{name}\tok\t{raw == canonical}"
      let renameNode (reference : NodeId) : NodeId :=
        if reference.value < state.nodes.length then ⟨state.nodes.length - 1 - reference.value⟩ else reference
      let renameBlob (reference : BlobId) : BlobId :=
        if reference.value < state.blobs.length then ⟨state.blobs.length - 1 - reference.value⟩ else reference
      let reversed : State := { state with
        roots := remapRoots renameNode state.roots
        nodes := state.nodes.reverse.map (remapNode renameNode renameBlob)
        blobs := state.blobs.reverse }
      let garbage : State := { reversed with
        nodes := reversed.nodes ++ [.injection ⟨reversed.nodes.length + 100⟩]
        blobs := reversed.blobs ++ [⟨17, [200, 201, 202]⟩] }
      for (suffix, variation) in [("reversed", reversed), ("garbage", garbage)] do
        let variationName := s!"{name}-{suffix}"
        if !Images.rawState.valid variation then throw <| IO.userError s!"snapshot.invalid_variation: {variationName}"
        if Snapshot.encode variation != some canonical then throw <| IO.userError s!"snapshot.relocation_changed_bytes: {variationName}"
        let variationRaw := Images.rawState.encode variation
        if (Snapshot.decode variationRaw).isSome != (variationRaw == canonical) then
          throw <| IO.userError s!"snapshot.variation_admission: {variationName}"
        IO.FS.writeBinFile (directory / s!"{variationName}.raw.pst2") ⟨variationRaw.toArray⟩
        IO.FS.writeBinFile (directory / s!"{variationName}.canonical.pst2") ⟨canonical.toArray⟩
        IO.println s!"case\t{variationName}\tok\t{variationRaw == canonical}"
  return 0
