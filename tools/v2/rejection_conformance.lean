/- Executable conformance for captured refusal records and mutation controls. -/
import InvocationWitness
import BoundaryV2.TargetRejection
open Lean BoundaryV2 BoundaryV2.Profile BoundaryV2.Profile.Target BoundaryV2.Tooling.InvocationWitness
private def readBytes (row : Json) (key : String) : IO Bytes := do
  return (← IO.FS.readBinFile (← string row key)).toList

def main (args : List String) : IO UInt32 := do
  let [manifestPath, recordsPath] := args | throw (IO.userError "expected manifest and records")
  let manifest ← orError (Json.parse (← IO.FS.readFile manifestPath))
  let groups ← (← orError manifest.getArr?).toList.mapM fun row => do
    pure (← string row "name", ← string row "image")
  let json ← orError (Json.parse (← IO.FS.readFile recordsPath))
  let records ← orError (← field json "records").getArr?
  for row in records do
    let caseName ← string row "case"
    let path ← required ((groups.find? (fun pair => pair.1 == caseName)).map Prod.snd) "missing case"
    let entry ← loadProgram path
    let producer ← string row "producer"
    let backend ← match producer with
      | "native" => pure Boundary.Backend.native
      | "wasm" => pure Boundary.Backend.wasm
      | _ => throw (IO.userError "unknown backend")
    let record : Boundary.RefusalRecord := {
      backend := backend
      input := ← readBytes row "input", output := ← readBytes row "output"
      diagnostic := ← readBytes row "error", inputAfter := ← readBytes row "inputAfter"
      status := ← orError (← field row "status").getNat? }
    unless Boundary.checkRefusal entry.image record do throw (IO.userError s!"refusal failed: {caseName}/{producer}")
    for bad in [{ record with status := 0 }, { record with output := [0] },
        { record with inputAfter := 0 :: record.inputAfter }] do
      if Boundary.checkRefusal entry.image bad then throw (IO.userError "surface mutation accepted")
    let retry ← readBytes row "retryInput"
    if Boundary.checkRefusal entry.image { record with input := retry, inputAfter := retry } then
      throw (IO.userError "valid original action was called refused")
  IO.println s!"refusal conformance: {records.size} actual records, {records.size * 3} surface mutations and {records.size} valid-action controls passed"
  pure 0
