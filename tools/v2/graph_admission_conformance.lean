import BoundaryV2.GraphEffects
import BoundaryV2.GraphUses
import BoundaryV2.Snapshot
import Lean

open Lean BoundaryV2 BoundaryV2.Profile
open BoundaryV2.Profile.Graph.Admission

private def orError (result : Except String α) : IO α :=
  match result with | .ok value => pure value | .error reason => throw (IO.userError reason)

private def field (json : Json) (name : String) : IO Json := orError (json.getObjVal? name)
private def string (json : Json) (name : String) : IO String := do orError ((← field json name).getStr?)

def main (arguments : List String) : IO UInt32 := do
  let [path] := arguments | throw (IO.userError "expected graph cohort JSON")
  let json ← orError (Json.parse (← IO.FS.readFile path))
  let mut total := 0
  let mut values := 0
  let mut kinds : List String := []
  for group in (← orError json.getArr?).toList do
    let image ← string group "image"
    let some program := Images.decodeImage (← IO.FS.readBinFile image).toList
      | throw (IO.userError s!"{image}: malformed BPI2 subject")
    let identity := Protocol.programIdentity program
    let effects := Target.Admission.effectFacts program
    let name ← string group "name"
    for item in (← orError (← field group "states").getArr?).toList do
      let path ← orError item.getStr?
      let some state := Graph.Snapshot.decode (← IO.FS.readBinFile path).toList
        | throw (IO.userError s!"{path}: malformed or noncanonical PST2 subject")
      if !positionValidWithIdentity program identity state then
        throw (IO.userError s!"{path}: position admission rejected; roots={rootsValid state}, custody={Graph.custody program state}, forest={forestValid state}, captures={capturesUnique state}, returning={(returning state).all (normalReturning state)}, exits={exitsValid state}, pending={pendingCount state}")
      for (record, index) in state.nodes.zipIdx do
        let kind := ((repr record).pretty.splitOn " " |>.head!).trimAscii.toString
        if !kinds.contains kind then kinds := kinds ++ [kind]
        if !recordValid program state index record then
          throw (IO.userError s!"{path}: record {index} rejected: {repr record}")
        match record with
        | .oneShot capture | .multiTemplate capture =>
          if !captureValid program state capture then
            throw (IO.userError s!"{path}: record {index} capture rejected: {repr capture}")
        | _ => pure ()
      if !effectsValidWith program state effects then
        throw (IO.userError s!"{path}: effect scope rejected")
      let some uses := directUses state | throw (IO.userError s!"{path}: direct use locations rejected")
      if !usesValid state uses then
        throw (IO.userError s!"{path}: direct lexical scope rejected; holder DAG={holderAcyclic state}")
      let meanings ← state.blobs.mapM fun blob =>
        match Profile.Value.decodeAt program.schemas 1000 blob.schema blob.bytes with
        | some value => pure value
        | none => throw (IO.userError s!"{path}: inconclusive blob witness search")
      if !blobsValid program state meanings then throw (IO.userError s!"{path}: blob meanings rejected")
      values := values + meanings.length
      let changed := { state with programIdentity := state.programIdentity.set 0 (state.programIdentity[0] ^^^ 1) }
      if positionValidWithIdentity program identity changed then throw (IO.userError "changed program identity admitted")
      total := total + 1
      if total % 1000 == 0 then IO.eprintln s!"graph records: {total} snapshots checked"
    IO.println s!"graph records: {name} passed"
    (← IO.getStdout).flush
  IO.println s!"graph records: {total} complete native snapshots, {values} exact blob meanings, {kinds.length} node kinds"
  IO.println (toJson kinds).compress
  return 0
