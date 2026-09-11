import GraphWitness
import Lean

open Lean BoundaryV2 BoundaryV2.Profile
open BoundaryV2.Profile.Graph.Admission

private def orError (result : Except String α) : IO α :=
  match result with | .ok value => pure value | .error reason => throw (IO.userError reason)
private def field (json : Json) (name : String) : IO Json := orError (json.getObjVal? name)
private def string (json : Json) (name : String) : IO String := do orError ((← field json name).getStr?)

private def replacements (program : Target.Program) (state : Graph.State) (value : Graph.Value) : List Graph.Value :=
  match program.schemas[value.schema.value]?, value.body with
  | some (.internal (.capability _)), .reference current =>
    (inventory state).filterMap (fun target =>
      let replaced : Graph.Value := ⟨value.schema, .reference target⟩
      if target != current && valueValid program state replaced value.schema then some replaced else none)
  | _, _ => []

private def replaceValues (program : Target.Program) (state : Graph.State) (values : List Graph.Value) : List (List Graph.Value) :=
  values.zipIdx.flatMap (fun (value, index) => (replacements program state value).map (values.set index))

private def changedRecords (program : Target.Program) (state : Graph.State) : Graph.Node → List Graph.Node
  | .control control => (replaceValues program state control.arguments).map (fun values => .control { control with arguments := values })
  | .continuation saved => saved.arguments.zipIdx.flatMap (fun (argument, index) =>
      argument.toList.flatMap (fun value => (replacements program state value).map
        (fun value => .continuation { saved with arguments := saved.arguments.set index (some value) })))
  | .aggregate schema tag values => (replaceValues program state values).map (.aggregate schema tag)
  | .environment values tail => (replaceValues program state values).map (fun values => .environment values tail)
  | .handler definition values evidence region =>
    (replaceValues program state values).map (fun values => .handler definition values evidence region)
  | _ => []

private def basicValid (program : Target.Program) (identity : Digest) (effects : Target.Admission.EffectFacts)
    (state : Graph.State) : Bool := positionValidWithIdentity program identity state && recordsValid program state &&
  captureRecordsValid program state && effectsValidWith program state effects && (directUses state).any (usesValid state)

def main (arguments : List String) : IO UInt32 := do
  let [path, probe] := arguments | throw (IO.userError "expected borrowed-return cohort and native probe")
  let json ← orError (Json.parse (← IO.FS.readFile path))
  let mut mutations := 0
  for group in (← orError json.getArr?).toList do
    let image ← string group "image"
    let name ← string group "name"
    let some program := Images.decodeImage (← IO.FS.readBinFile image).toList | throw (IO.userError "invalid image")
    let identity := Protocol.programIdentity program
    let effects := Target.Admission.effectFacts program
    let borrowed ← orError (Json.parse (← IO.FS.readFile (image ++ ".graph.borrow.json")))
    let (subject, borrows) ← Tooling.BorrowWitness.read borrowed
    if subject != program || !Target.Borrow.check program borrows then throw (IO.userError "invalid borrowed program subject")
    let mut found := false
    for item in (← orError (← field group "states").getArr?).toList do
      if found then continue
      let original ← orError item.getStr?
      let some state := Graph.Snapshot.decode (← IO.FS.readBinFile original).toList | throw (IO.userError "invalid original state")
      for (record, index) in state.nodes.zipIdx do
        if found then continue
        for replacement in changedRecords program state record do
          if found then continue
          let changed := { state with nodes := state.nodes.set index replacement }
          let some changed := Graph.Snapshot.canonicalize changed | continue
          if !basicValid program identity effects changed then continue
          let .ok rows ← Tooling.GraphWitness.rows program changed borrows | continue
          if !projectionRowsValid program changed borrows rows then throw (IO.userError "invalid rebuilt mutation witness")
          if futureScopesValid program changed borrows rows then continue
          let meanings ← changed.blobs.mapM fun blob =>
            match Profile.Value.decodeAt program.schemas 1000 blob.schema blob.bytes with
            | some meaning => pure meaning | none => throw (IO.userError "inconclusive mutation blob witness")
          if checkWithFacts program identity effects borrows changed ⟨meanings, rows⟩ then
            throw (IO.userError "invalid future lifetime admitted by full graph checker")
          let changedPath := image ++ ".younger-borrow.pst2"
          IO.FS.writeBinFile changedPath (Images.rawState.encode changed).toByteArray
          let result ← IO.Process.output { cmd := probe, args := #["state", image ++ ".graph.program", changedPath] }
          if result.exitCode == 0 || !result.stdout.isEmpty || !result.stderr.startsWith "error: InvalidScope\n" then
            throw (IO.userError s!"native lifetime mutation result disagrees: {result.exitCode}, {result.stderr}")
          mutations := mutations + 1
          found := true
          IO.println s!"future lifetime mutation: {name}, original={original}, changed={changedPath}"
          (← IO.getStdout).flush
    if !found then throw (IO.userError s!"{name}: no isolated future-lifetime mutation found")
  IO.println s!"future lifetime mutations: {mutations} fully typed current states rejected by Lean and native future-scope admission"
  pure 0
