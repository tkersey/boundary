import GraphWitness
import Lean

open Lean BoundaryV2 BoundaryV2.Profile
open BoundaryV2.Profile.Graph.Admission

private def orError (result : Except String α) : IO α :=
  match result with | .ok value => pure value | .error reason => throw (IO.userError reason)
private def field (json : Json) (name : String) : IO Json := orError (json.getObjVal? name)
private def string (json : Json) (name : String) : IO String := do orError ((← field json name).getStr?)

private structure ProgramCache where
  path : String
  bytes : Bytes
  program : Target.Program
  constants : List (Profile.Value .target)
  borrows : Target.Borrow.Witness
  requested : List Target.Borrow.Query := []

private def programValid (entry : ProgramCache) : IO Unit := do
  let witness : Target.Admission.Witness := ⟨entry.constants, entry.borrows⟩
  if Target.CertifiedImage.decode entry.bytes witness != some entry.program then
    throw (IO.userError s!"{entry.path}: extended program admission rejected")

private def loadProgram (probe path : String) : IO ProgramCache := do
  let bytes := (← IO.FS.readBinFile path).toList
  let some program := Images.decodeImage bytes | throw (IO.userError s!"{path}: malformed BPI2 subject")
  let constants ← program.constants.mapM fun literal =>
    match Profile.Value.decodeAt program.schemas ((literal.bytes.length + 1) * (program.schemas.length + 1)) literal.schema literal.bytes with
    | some meaning => pure meaning
    | none => throw (IO.userError "inconclusive: program constant witness search")
  let borrows ← Tooling.GraphWitness.refresh probe path program []
  let entry : ProgramCache := ⟨path, bytes, program, constants, borrows, []⟩
  programValid entry
  pure entry

def main (arguments : List String) : IO UInt32 := do
  let [path, probe] := arguments | throw (IO.userError "expected graph cohort JSON and native admission probe")
  let json ← orError (Json.parse (← IO.FS.readFile path))
  let mut programs : List ProgramCache := []
  let mut total := 0
  let mut projectionCount := 0
  let mut omissionMutations := 0
  let mut outputMutations := 0
  for group in (← orError json.getArr?).toList do
    let path ← string group "image"
    let name ← string group "name"
    let mut entry ← match programs.find? (fun entry => entry.path == path) with
      | some entry => pure entry | none => loadProgram probe path
    let identity := Protocol.programIdentity entry.program
    let effects := Target.Admission.effectFacts entry.program
    let mut mutatedMissing := false
    let mut mutatedOutput := false
    for item in (← orError (← field group "states").getArr?).toList do
      let path ← orError item.getStr?
      let bytes := (← IO.FS.readBinFile path).toList
      let some state := Graph.Snapshot.decode bytes | throw (IO.userError s!"{path}: malformed PST2 subject")
      let mut complete : Option (List ProjectionRow) := none
      while complete.isNone do
        match ← Tooling.GraphWitness.rows entry.program state entry.borrows with
        | .ok rows => complete := some rows
        | .error query =>
          if entry.requested.contains query then throw (IO.userError "native borrow producer omitted a requested summary")
          if entry.requested.length ≥ 10000 then throw (IO.userError "inconclusive: graph query witness search limit")
          let requested := entry.requested ++ [query]
          let borrows ← Tooling.GraphWitness.refresh probe entry.path entry.program requested
          entry := { entry with requested := requested, borrows := borrows }
          programValid entry
      let some projections := complete | throw (IO.userError "projection completion invariant")
      let meanings ← state.blobs.mapM fun blob =>
        match Profile.Value.decodeAt entry.program.schemas 1000 blob.schema blob.bytes with
        | some value => pure value
        | none => throw (IO.userError s!"{path}: inconclusive blob witness search")
      let witness : Graph.Admission.Witness := ⟨meanings, projections⟩
      if !checkWithFacts entry.program identity effects entry.borrows state witness then
        throw (IO.userError s!"{path}: full saved-state admission rejected; future scopes={futureScopesValid entry.program state entry.borrows projections}")
      if !mutatedMissing && !projections.isEmpty then
        if checkWithFacts entry.program identity effects entry.borrows state { witness with projections := projections.drop 1 } then
          throw (IO.userError "missing required graph projection admitted")
        mutatedMissing := true
        omissionMutations := omissionMutations + 1
      if !mutatedOutput then
        for (row, index) in projections.zipIdx do
          if !mutatedOutput && !row.outputs.isEmpty then
            let changed := projections.set index { row with outputs := row.outputs.drop 1 }
            if checkWithFacts entry.program identity effects entry.borrows state { witness with projections := changed } then
              throw (IO.userError "missing projected value or scope admitted")
            mutatedOutput := true
            outputMutations := outputMutations + 1
      total := total + 1
      projectionCount := projectionCount + projections.length
      if total % 1000 == 0 then IO.eprintln s!"full graph admission: {total} snapshots checked"
    programs := entry :: programs.filter (fun previous => previous.path != entry.path)
    IO.println s!"full graph admission: {name} passed, {entry.requested.length} additional program queries"
    (← IO.getStdout).flush
  IO.println s!"full graph admission: {total} snapshots, {projectionCount} closed projections, {omissionMutations} missing-row and {outputMutations} missing-output mutations rejected"
  pure 0
