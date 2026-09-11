import ExecutionProof
import ProgramProof
import BoundaryV2.SHA256Certificate

open Lean BoundaryV2 BoundaryV2.Profile BoundaryV2.Profile.Target
open BoundaryV2.Tooling.InvocationWitness BoundaryV2.Tooling.ExecutionProof

private def digestName (bytes : Bytes) : String :=
  let alphabet := "0123456789abcdef".toList.toArray
  String.ofList ((SHA256.hash bytes).toList.flatMap fun byte =>
    [alphabet[byte.toNat / 16]!, alphabet[byte.toNat % 16]!])

private def hashInput (domain : String) (fields : List Bytes) : Bytes :=
  domain.toUTF8.data.toList ++ fields.flatMap Protocol.hashField

private def hashWitness (input : Bytes) : List SHA256.Working := Id.run do
  let mut remaining := SHA256.padding input
  let mut prior := SHA256.initial
  let mut witness := []
  for _ in List.range (remaining.length / 64) do
    let next := SHA256.compress prior (Vector.ofFn fun index => remaining[index.val]?.getD 0)
    witness := witness ++ [next]
    prior := next
    remaining := remaining.drop 64
  return witness

private def largeHashProof (name : String) (bytes : Bytes) : String := Id.run do
  let states := (hashWitness bytes).toArray
  let mut remaining := SHA256.padding bytes
  let mut unique : Array Bytes := #[]
  let mut blocks : Array Nat := #[]
  for _ in [:states.size] do
    let block := remaining.take 64
    let index := (unique.toList.idxOf? block).getD unique.size
    if index == unique.size then unique := unique.push block
    blocks := blocks.push index
    remaining := remaining.drop 64
  let mut declarations := [s!"def {name}Input : Bytes := {literal bytes}"]
  for index in [:unique.size] do
    declarations := declarations ++ [s!"def {name}Block{index} : Bytes := {literal unique[index]!}"]
  declarations := declarations ++ [s!"def {name}Suffix{states.size} : Bytes := []"]
  for index in (List.range states.size).reverse do
    declarations := declarations ++ [s!"def {name}Suffix{index} : Bytes := {name}Block{blocks[index]!} ++ {name}Suffix{index + 1}"]
  declarations := declarations ++ [s!"theorem {name}Padding : SHA256.padding {name}Input = {name}Suffix0 := by decide +kernel"]
  for h : index in [:states.size] do
    let prior := if index == 0 then "SHA256.initial" else s!"{name}State{index - 1}"
    declarations := declarations ++ [s!"def {name}State{index} : SHA256.Working := {literal states[index]}",
      s!"theorem {name}Step{index} : SHA256.compressionStep {name}Block{blocks[index]!} {prior} = {name}State{index} := by decide +kernel"]
  let final := s!"{name}State{states.size - 1}"
  declarations := declarations ++ [s!"theorem {name}Chain{states.size} : SHA256.BlockDerivation {name}Suffix{states.size} {final} {final} := .done _"]
  for index in (List.range states.size).reverse do
    let prior := if index == 0 then "SHA256.initial" else s!"{name}State{index - 1}"
    declarations := declarations ++ [s!"theorem {name}Chain{index} : SHA256.BlockDerivation {name}Suffix{index} {prior} {final} := .step {name}Block{blocks[index]!} {name}Suffix{index + 1} {prior} {name}State{index} {final} (by decide +kernel) {name}Step{index} {name}Chain{index + 1}"]
  let digest := s!"({literal (SHA256.hash bytes).toList.toArray}).toVector"
  declarations := declarations ++ [
    s!"theorem {name}Bytes : SHA256.hash {name}Input = {digest} :=\n  (SHA256.hash_of_block_derivation {name}Input {name}Suffix0 {final} {name}Padding {name}Chain0).trans (by decide +kernel)",
    s!"set_option linter.unusedSimpArgs false in\n@[cbv_eval] theorem {name} : SHA256.hashNumerals {literal (bytes.map UInt8.toNat)} = {digest} := by\n  unfold SHA256.hashNumerals\n  have exactInput : ({literal (bytes.map UInt8.toNat)} : List Nat).map UInt8.ofNat = {name}Input := by\n    simp only [{name}Input, List.map_append, List.map_replicate, List.map_cons, List.map_nil]\n    rfl\n  rw [exactInput]\n  exact {name}Bytes"]
  return String.intercalate "\n" declarations

private def hashProof (name : String) (bytes : Bytes) : String :=
  -- Whole-check reduction already exceeds the kernel budget on a 2 KiB
  -- two-run payload. Compose block proofs before that expansion grows.
  if bytes.length > 512 then largeHashProof name bytes else
    s!"@[cbv_eval] theorem {name} : SHA256.hashNumerals {literal (bytes.map UInt8.toNat)} = ({literal (SHA256.hash bytes).toList.toArray}).toVector :=\n  SHA256.checkHash_sound _ {literal (hashWitness bytes)} _ (by decide +kernel)"

private def widthProofs (schemas : List (Schema .target)) : IO String := do
  let types := s!"({literal schemas} : List (Schema .target))"
  let first := List.replicate schemas.length SchemaAdmission.infinity
  let mut current := first
  let mut declarations : List String := []
  let mut steps : List String := [s!"    SchemaAdmission.widthLoop {types} (List.replicate {types}.length SchemaAdmission.infinity) = SchemaAdmission.widthLoop {types} {literal first} := congrArg (SchemaAdmission.widthLoop {types}) (by decide +kernel)"]
  for index in List.range (schemas.length + 1) do
    let next := SchemaAdmission.widthRound schemas current
    if next == current then
      steps := steps ++ [s!"    _ = {literal current} := SchemaAdmission.widthLoop_of_fixed {types} {literal current} (by decide +kernel)"]
      return String.intercalate "\n" declarations ++
        s!"\n@[cbv_eval] theorem schemaWidthsKnown : SchemaAdmission.widths {types} = {literal current} := by\n  unfold SchemaAdmission.widths\n  calc\n{String.intercalate "\n" steps}"
    declarations := declarations ++ [s!"theorem widthRound{index} : SchemaAdmission.widthRound {types} {literal current} = {literal next} := by decide +kernel"]
    steps := steps ++ [s!"    _ = SchemaAdmission.widthLoop {types} {literal next} := (SchemaAdmission.widthLoop_round {types} {literal current}).symm.trans (congrArg (SchemaAdmission.widthLoop {types}) widthRound{index})"]
    current := next
  throw (IO.userError "inconclusive: schema width witness search")

private def requestHashInputs (outcome : Protocol.Outcome) : IO (List Bytes) := do
  let .requested snapshot bytes := outcome | pure []
  let request ← required (Images.rawRequest.decode bytes) "malformed captured ERQ2"
  let state ← required (Graph.Snapshot.decode snapshot) "malformed request PST2"
  let pending ← required state.roots.pending "request without pending root"
  let some (.pending _ _ _ source) := state.nodes[pending.value]? | throw (IO.userError "request without pending node")
  pure [snapshot, request.resumeSchema,
    hashInput "boundary.residual-contract/v2" [request.semanticIdentity, request.payloadSchema, request.resumeSchema],
    hashInput "boundary.continuation-binding/v2" [request.programIdentity.toList, request.pendingStateDigest.toList,
      Wire.natural source.value, (SHA256.hash request.resumeSchema).toList],
    hashInput "boundary.effect-request/v2" (Protocol.requestFields request)]

def main (arguments : List String) : IO UInt32 := do
  let manifest :: output :: filters := arguments
    | throw (IO.userError "expected invocation manifest, generated-module directory, and optional case names")
  IO.FS.createDirAll output
  let groups ← orError (Json.parse (← IO.FS.readFile manifest))
  let mut programs : List ProgramCache := []
  let mut packages : List (String × BoundaryV2.Tooling.ProgramProof.Package) := []
  let mut produced := 0
  for group in (← orError groups.getArr?).toList do
    let name ← string group "name"
    if !filters.isEmpty && !filters.contains name then continue
    let imagePath ← string group "image"
    let entry ← match programs.find? (fun entry => entry.path == imagePath) with
      | some entry => pure entry | none => loadProgram imagePath
    programs := entry :: programs.filter (fun previous => previous.path != imagePath)
    let mut clock : Boundary.Clock := ⟨0, none⟩
    let mut records : List Boundary.PublicInvocation := []
    let mut witnesses : List Boundary.InvocationWitness := []
    let mut initial : Option Bytes := none
    let mut continuation : Option Boundary.Continuation := none
    let mut hashInputs : List Bytes := []
    for item in (← orError (← field group "transitions").getArr?).toList do
      let inputBytes := (← IO.FS.readBinFile (← string item "input")).toList
      let outputBytes := (← IO.FS.readBinFile (← string item "output")).toList
      let input ← required (Protocol.inputCodec.decode inputBytes) "malformed PKI2 subject"
      let outcome ← required (Protocol.outcomeCodec.decode outputBytes) "malformed PKO2 subject"
      for bytes in ← requestHashInputs outcome do
        if !hashInputs.contains bytes then hashInputs := hashInputs ++ [bytes]
      if records.isEmpty then
        let .initialArgs bytes := input.instanceData | throw (IO.userError "initial execution must start with initial arguments")
        initial := some bytes
      let incoming ← inputWitness entry input clock
      let outgoing ← match outputState outcome with
        | some bytes => do graphWitness entry (← required (Graph.Snapshot.decode bytes) "malformed PST2 subject")
        | none => pure ⟨[], []⟩
      let steps ← match input.mode with
        | .advance => pure 1
        | .run => do
          let count ← orError (← field item "steps").getNat?
          let prepared ← semantic (Boundary.prepare entry.image input incoming) "prepare candidate run"
          pure (if prepared.parked then 0 else count)
      let witness : Boundary.InvocationWitness := ⟨incoming, outgoing, steps⟩
      let record : Boundary.PublicInvocation := ⟨inputBytes, outputBytes⟩
      let result ← required (Boundary.checkInvocation entry.image record clock witness) "candidate invocation rejected"
      if let some before := continuation then
        if before.instanceData != some result.instanceData then throw (IO.userError "candidate invocation omitted a boundary state")
      clock := result.clock
      continuation := some result.continuation
      records := records ++ [record]
      witnesses := witnesses ++ [witness]
    let initialBytes ← required initial "empty execution subject"
    if !(continuation.any (·.terminal)) then throw (IO.userError "inconclusive: initial execution has not terminated")
    let subjects := Wire.Codec.blob.encode entry.bytes ++ records.flatMap
      (fun record => Wire.Codec.blob.encode record.input ++ Wire.Codec.blob.encode record.output)
    let module := "BoundaryCertificateExecution" ++ digestName subjects
    let recordData := records.map fun record => s!"{leftBrace} input := {literal record.input}, output := {literal record.output} {rightBrace}"
    let witnessData := witnesses.map witnessLiteral
    let package ← match packages.find? (fun previous => previous.1 == imagePath) with
      | some (_, package) => pure package
      | none => do
        let imageModule := "BoundaryCertificateImage" ++ digestName (hashInput "boundary.program-certificate/v1"
          [entry.bytes, (literal entry.witness.constants).toUTF8.data.toList,
            (literal entry.witness.borrows).toUTF8.data.toList])
        let storedData := entry.image.context.constants.map storedLiteral
        let programHashInput := Protocol.programPreimage entry.image.context.program
        let schemaWidthProofs ← widthProofs entry.image.context.program.schemas
        let dataCode := s!"def imageBytes : Bytes := {literal entry.bytes}\ndef programWitness : Admission.Witness := {leftBrace} constants := {literal entry.witness.constants}, borrows := {literal entry.witness.borrows} {rightBrace}\ndef program : Program := {literal entry.image.context.program}\n{schemaWidthProofs}\ndef expectedIdentity : Digest := ({literal entry.image.identity.toList.toArray}).toVector\ntheorem programPreimageKnown : Protocol.programPreimage ({literal entry.image.context.program} : Program) = {literal programHashInput} := by decide_cbv\n{hashProof "programHashKnown" programHashInput}\n@[cbv_eval] theorem programIdentityKnown : Protocol.programIdentity ({literal entry.image.context.program} : Program) = expectedIdentity := by\n  unfold Protocol.programIdentity\n  rw [programPreimageKnown, SHA256.hash_as_numerals]\n  exact programHashKnown\ndef storedConstants : List (Machine.StoredBlob program.schemas) := [{String.intercalate "," storedData}]\n"
        BoundaryV2.Tooling.ProgramProof.emit (System.FilePath.mk output) imageModule entry dataCode
    packages := (imagePath, package) :: packages.filter (fun previous => previous.1 != imagePath)
    let hashProofs := String.intercalate "\n" (hashInputs.zipIdx.map fun (bytes, index) => hashProof s!"hash{index}" bytes)
    let executionProof ← composedProof entry records witnesses hashInputs initialBytes
    let prelude := s!"abbrev imageBytes : Bytes := {package.module}.imageBytes\nabbrev programWitness : Admission.Witness := {package.module}.programWitness\nabbrev program : Program := {package.module}.program\nabbrev image : Machine.ImageContext imageBytes programWitness := {package.module}.image\n{hashProofs}\ndef records : List Boundary.PublicInvocation := [{String.intercalate "," recordData}]\ndef witnesses : List Boundary.InvocationWitness := [{String.intercalate "," witnessData}]\n"
    let sections := (prelude ++ executionProof).splitOn moduleBreak
    let mut artifacts := package.artifacts
    let mut previous := package.module
    for (partBody, index) in sections.zipIdx do
      let last := index + 1 == sections.length
      let part := if last then module else s!"{module}Part{index}"
      let code := s!"import {previous}\nimport BoundaryV2.ExecutionEvaluation\nimport Lean.Elab.Tactic.Cbv\n\nset_option Elab.async false\nset_option cbv.warning false\nattribute [cbv_opaque] BoundaryV2.Profile.SHA256.hashNumerals BoundaryV2.Profile.SHA256.hash\nattribute [cbv_eval] BoundaryV2.Profile.SHA256.hash_as_numerals\nset_option cbv.maxSteps 5000000\nset_option maxRecDepth 65536\nset_option maxHeartbeats 0\n\nnamespace {module}\nopen BoundaryV2 BoundaryV2.Profile BoundaryV2.Profile.Target\n\n{partBody}\nend {module}\n"
      let partPath := System.FilePath.mk output / (part ++ ".lean")
      IO.FS.writeFile partPath code
      if !last then artifacts := artifacts ++ [⟨part, partPath⟩]
      previous := part
    let path := System.FilePath.mk output / (module ++ ".lean")
    let recordsJson := records.map fun record => Json.mkObj [("input", toJson (record.input.map UInt8.toNat)), ("output", toJson (record.output.map UInt8.toNat))]
    let claim := Json.mkObj [("name", toJson (module ++ ".certificate")), ("kind", toJson "initial-execution"),
      ("image", toJson (entry.bytes.map UInt8.toNat)), ("records", toJson recordsJson)]
    let metadata := Json.mkObj [("module", toJson module), ("path", toJson path.toString), ("claims", toJson [claim]),
      ("case", toJson name), ("status", toJson "candidate"),
      ("dependencies", toJson (artifacts.map fun item => Json.mkObj
        [("module", toJson item.module), ("path", toJson item.path.toString), ("claims", toJson ([] : List Json))]))]
    IO.FS.writeFile (System.FilePath.mk output / (module ++ ".json")) metadata.compress
    produced := produced + 1
    IO.println s!"execution candidate: {name}, {records.length} complete records, {path}"
    (← IO.getStdout).flush
  if produced == 0 then throw (IO.userError "empty execution candidate selection")
  pure 0
