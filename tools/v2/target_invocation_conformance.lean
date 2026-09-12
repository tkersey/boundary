import InvocationWitness

open Lean BoundaryV2 BoundaryV2.Profile
open BoundaryV2.Profile.Target
open BoundaryV2.Tooling.InvocationWitness

def main (arguments : List String) : IO UInt32 := do
  let path :: filters := arguments | throw (IO.userError "expected native invocation cohort JSON and optional case names")
  let groups ← orError (Json.parse (← IO.FS.readFile path))
  let mut programs : List ProgramCache := []
  let mut total := 0
  let mut cases := 0
  let mut eventCount := 0
  for group in (← orError groups.getArr?).toList do
    let name ← string group "name"
    if !filters.isEmpty && !filters.contains name then continue
    let imagePath ← string group "image"
    let entry ← match programs.find? (fun entry => entry.path == imagePath) with
      | some entry => pure entry | none => loadProgram imagePath
    programs := entry :: programs.filter (fun previous => previous.path != imagePath)
    let mut clock : Boundary.Clock := ⟨0, none⟩
    let mut count := 0
    let items := (← orError (← field group "transitions").getArr?).toList
    let checkSegment ← items.anyM fun item => do
      let bytes := (← IO.FS.readBinFile (← string item "input")).toList
      let input ← required (Protocol.inputCodec.decode bytes) "malformed segment PKI2"
      pure (input.mode == .run)
    let mut records : List Boundary.PublicInvocation := []
    let mut witnesses : List Boundary.InvocationWitness := []
    let mut firstInstance : Option Protocol.Instance := none
    let mut wrongResponseChecked := false
    for item in items do
      let inputPath ← string item "input"
      let outputPath ← string item "output"
      let inputBytes := (← IO.FS.readBinFile inputPath).toList
      let actualBytes := (← IO.FS.readBinFile outputPath).toList
      let input ← required (Protocol.inputCodec.decode inputBytes) s!"{inputPath}: malformed PKI2"
      let actual ← required (Protocol.outcomeCodec.decode actualBytes) s!"{outputPath}: malformed PKO2"
      let incoming ← inputWitness entry input clock
      let outgoing ← match outputState actual with
        | some bytes => do
          let state ← required (Graph.Snapshot.decode bytes) "malformed outgoing PST2"
          graphWitness entry state
        | none => pure ⟨[], []⟩
      let steps ← match input.mode with
        | .advance => pure 1
        | .run => do
          let steps ← orError (← field item "steps").getNat?
          let prepared ← semantic (Boundary.prepare entry.image input incoming) "prepare run"
          pure (if prepared.parked then 0 else steps)
      let witness : Boundary.InvocationWitness := ⟨incoming, outgoing, steps⟩
      let record : Boundary.PublicInvocation := ⟨inputBytes, actualBytes⟩
      let result ← match Boundary.checkInvocation entry.image record clock witness with
        | some result => pure result
        | none => do
          let observed ← semantic (Boundary.observe entry.image input witness) s!"{name} invocation {count}: target boundary"
          let modelBytes := Protocol.outcomeCodec.encode observed.outcome
          IO.FS.writeBinFile (outputPath ++ ".model") modelBytes.toByteArray
          IO.FS.writeFile (outputPath ++ ".difference") s!"actual: {repr actual}\nmodel: {repr observed.outcome}\nraw model: {repr observed.state.raw}\n"
          throw (IO.userError s!"{name} invocation {count}: complete PKO2 binding rejected; saved .model and .difference")
      if count == 0 then
        firstInstance := some input.instanceData
        let changed := { record with output := record.output ++ [0] }
        if (Boundary.checkInvocation entry.image changed clock witness).isSome then
          throw (IO.userError "changed complete output admitted")
        let otherImage := { input with image := input.image ++ [0] }
        if (Boundary.checkInvocation entry.image { record with input := Protocol.inputCodec.encode otherImage } clock witness).isSome then
          throw (IO.userError "changed complete image admitted")
        if input.mode == .run && steps > 0 then
          if (Boundary.checkInvocation entry.image record clock { witness with internalSteps := steps - 1 }).isSome then
            throw (IO.userError "incomplete internal run witness admitted")
      if !wrongResponseChecked then
        if let .continueValue (some bytes) := input.control then
          let response ← required (Images.rawResult.decode bytes) "malformed mutation response"
          let response := { response with requestIdentity := response.requestIdentity.map (fun byte => byte ^^^ 1) }
          let changed := { input with control := .continueValue (some (Images.rawResult.encode response)) }
          if (Boundary.checkInvocation entry.image { record with input := Protocol.inputCodec.encode changed } clock witness).isSome then
            throw (IO.userError "wrong response binding admitted")
          wrongResponseChecked := true
      if checkSegment then
        records := records ++ [record]
        witnesses := witnesses ++ [witness]
      clock := result.clock
      eventCount := eventCount + result.events.length
      count := count + 1
      total := total + 1
      if total % 1000 == 0 then IO.eprintln s!"target invocation: {total} complete outputs matched"
    if checkSegment then
      let before : Boundary.Continuation := ⟨firstInstance, ⟨0, none⟩, false⟩
      let result ← required (Boundary.checkExecution entry.image records witnesses before .completed)
        s!"{name}: complete invocation segment rejected"
      if !result.continuation.terminal || result.continuation.instanceData.isSome then
        throw (IO.userError "completed segment retained a resumable state")
      if (Boundary.checkExecution entry.image records.dropLast witnesses.dropLast before .completed).isSome then
        throw (IO.userError "omitted final invocation certified as completed")
      if records.length > 1 then
        if (Boundary.checkExecution entry.image records.dropLast witnesses.dropLast before .prefix).isNone then
          throw (IO.userError "explicit nonempty execution prefix rejected")
        if (Boundary.checkExecution entry.image (records.take 1 ++ records) (witnesses.take 1 ++ witnesses) before .completed).isSome then
          throw (IO.userError "repeated initial invocation admitted within one execution")
    cases := cases + 1
    IO.println s!"target invocation: {name} passed {count} exact PKO2 comparisons"
    (← IO.getStdout).flush
  if cases == 0 then throw (IO.userError "empty invocation cohort")
  IO.println s!"target invocation: {cases} cases, {total} complete PKO2 comparisons, {eventCount} semantic events"
  pure 0
