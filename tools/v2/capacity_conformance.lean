import InvocationWitness
import BoundaryV2.TargetCapacity

open Lean BoundaryV2 BoundaryV2.Profile BoundaryV2.Profile.Target
open BoundaryV2.Tooling.InvocationWitness

private def readBytes (row : Json) (key : String) : IO Bytes :=
  return (← IO.FS.readBinFile (← string row key)).toList

private def natural (row : Json) (key : String) : IO Nat := do
  orError (← field row key).getNat?

private def optionalBytes (row : Json) (key : String) : IO (Option Bytes) := do
  let value ← field row key
  if value == Json.null then return none
  return some (← IO.FS.readBinFile (← orError value.getStr?)).toList

private def optionalNatural (row : Json) (key : String) : IO (Option Nat) := do
  let value ← field row key
  if value == Json.null then return none
  return some (← orError value.getNat?)

def main (args : List String) : IO UInt32 := do
  let [manifest, imagePath, probe] := args | throw (IO.userError "expected capacity manifest, image, and borrow probe")
  let bytes := (← IO.FS.readBinFile imagePath).toList
  let program ← required (Images.decodeImage bytes) "malformed capacity image"
  let _ ← Tooling.GraphWitness.refresh probe imagePath program []
  let entry ← loadProgram imagePath
  let json ← orError (Json.parse (← IO.FS.readFile manifest))
  let rows ← orError (← field json "rows").getArr?
  let mut arenas : List String := []
  for row in rows do
    let arena ← string row "arena"
    if arenas.contains arena then throw (IO.userError "duplicate capacity arena")
    arenas := arenas ++ [arena]
    let followups ← (← orError (← field row "followups").getArr?).toList.mapM fun next => do
      let invocation : Boundary.PublicInvocation := ⟨← readBytes next "input", ← readBytes next "output"⟩
      pure (⟨invocation, ← readBytes next "inputAfter", ← natural next "prepareStatus",
        ← natural next "executeStatus"⟩ : Boundary.CapacityFollowup)
    let record : Boundary.CapacityRecord := {
      input := ← readBytes row "input", output := ← readBytes row "output"
      callerInputAfter := ← readBytes row "callerInputAfter", guestInputAfter := ← optionalBytes row "inputAfter"
      prepareStatus := ← natural row "prepareStatus", executeStatus := ← optionalNatural row "executeStatus"
      retry := ⟨← readBytes row "retryInput", ← readBytes row "retryOutput"⟩
      retryInputAfter := ← readBytes row "retryInputAfter", retryPrepareStatus := ← natural row "retryPrepareStatus"
      retryExecuteStatus := ← natural row "retryExecuteStatus", followups := followups }
    let input ← required (Protocol.inputCodec.decode record.retry.input) "malformed retry PKI2"
    let .initialArgs arguments := input.instanceData | throw (IO.userError "expected initial capacity invocation")
    let mut clock : Boundary.Clock := ⟨0, none⟩
    let mut witnesses := []
    for invocation in record.retry :: followups.map Boundary.CapacityFollowup.invocation do
      let (witness, result) ← deriveInvocation entry invocation clock
      witnesses := witnesses ++ [witness]
      clock := result.clock
    let _ ← required (Boundary.checkCapacityExecution entry.image record witnesses arguments)
      s!"capacity retry rejected: {arena}"
    let mutations := [
      { record with callerInputAfter := 0 :: record.callerInputAfter },
      { record with retry := { record.retry with input := record.retry.input ++ [0] } },
      { record with retryInputAfter := 0 :: record.retryInputAfter },
      { record with prepareStatus := 2 },
      { record with executeStatus := some 2 },
      { record with retryPrepareStatus := 1 },
      { record with retryExecuteStatus := 2 },
      { record with output := record.retry.output },
      { record with output := record.output ++ [0] },
      { record with retry := { record.retry with output := record.retry.output ++ [0] } }]
    let next ← required followups.head? "capacity fixture missing retry continuation"
    let replace (next : Boundary.CapacityFollowup) := { record with followups := next :: followups.tail }
    let mutations := mutations ++ [
      replace { next with inputAfter := 0 :: next.inputAfter },
      replace { next with prepareStatus := 1 },
      replace { next with executeStatus := 1 },
      replace { next with invocation := { next.invocation with input := next.invocation.input ++ [0] } },
      replace { next with invocation := { next.invocation with output := next.invocation.output ++ [0] } }]
    for changed in mutations do
      if (Boundary.checkCapacityExecution entry.image changed witnesses arguments).isSome then
        throw (IO.userError s!"capacity mutation admitted: {arena}")
    if (Boundary.checkCapacityExecution entry.image { record with followups := [] } (witnesses.take 1) arguments).isSome then
      throw (IO.userError s!"incomplete capacity retry admitted: {arena}")
    IO.eprintln s!"capacity {arena}: complete retry, 15 field mutations, and omitted completion passed"
  unless arenas.length == 3 && ["input", "working", "output"].all arenas.contains do
    throw (IO.userError "missing capacity arena")
  IO.println "capacity conformance: 3 actual completed retry executions and 48 mutations passed"
  return 0
