import BoundaryV2.ProtocolAdmission

open BoundaryV2.Profile
open BoundaryV2.Profile.Protocol

private def bytes (text : String) : Bytes := text.toUTF8.data.toList
private def digest (value : UInt8) : Digest := Vector.replicate 32 value
private def descriptor (types : List (Schema .target)) : Bytes :=
  [0] ++ (Codecs.schema .target).list.encode types

private def request : Request := bindRequest {
  programIdentity := digest 1, pendingStateDigest := digest 2,
  residualContractDigest := digest 0, continuationBindingDigest := digest 3,
  semanticIdentity := bytes "example", payloadSchema := descriptor [.u64],
  resumeSchema := descriptor [.boolean], payload := List.replicate 8 0,
  requestIdentity := digest 0 }

private def requests : List (String × Request) := [
  ("base", request),
  ("program", { request with programIdentity := digest 4 }),
  ("state", { request with pendingStateDigest := digest 4 }),
  ("contract", { request with residualContractDigest := digest 4 }),
  ("continuation", { request with continuationBindingDigest := digest 4 }),
  ("semantic", { request with semanticIdentity := bytes "example2" }),
  ("payload-schema", { request with payloadSchema := descriptor [.i64] }),
  ("resume-schema", { request with resumeSchema := descriptor [.u8] }),
  ("payload", { request with payload := 1 :: List.replicate 7 0 }),
  ("self", { request with requestIdentity := digest 4 })]

private def program : Target.Program := {
  roots := ⟨1, 0, 0, 0⟩, schemas := [.unit], constants := [⟨0, []⟩], effects := [],
  functions := [⟨0, [], 0, [], []⟩], blocks := [⟨0, [], [⟨.constant, 0, [], 0, []⟩], .returnValue 0⟩] }

/-- Some section variants are raw records rather than admitted programs. This
tests the actual identity routine, whose admission precondition is separate. -/
private def programs : List (String × Target.Program) := [
  ("base", program),
  ("roots", { program with roots := ⟨2, 0, 0, 0⟩ }),
  ("schemas", { program with schemas := [.boolean] }),
  ("constants", { program with constants := [⟨0, [1]⟩] }),
  ("effects", { program with effects := [⟨bytes "effect", 0, 0, [], [], .linear, true⟩] }),
  ("functions", { program with functions := [⟨0, [0], 0, [], []⟩] }),
  ("blocks", { program with blocks := [⟨0, [], [], .returnValue 0⟩] }),
  ("handlers", { program with handlers := [⟨.shallow, 0, 0, 0, [], none, [], []⟩] }),
  ("scopes", { program with scopes := ⟨[⟨[0], [], [], .linear⟩], 1, [⟨0, [0], [0]⟩]⟩ }),
  ("constructors", { program with constructors := [⟨0, 0, 0⟩] })]

private def reasons : List (String × Reason) := [
  ("text", .text (bytes "stop")), ("empty-text", .text []), ("binary", .bytes [255, 0]),
  ("bad-text", .text [192, 128]), ("truncated-text", .text [226, 130]),
  ("surrogate", .text [237, 160, 128])]

private def outcomes : List (String × Outcome) := [
  ("progressed", .progressed [0, 255]), ("requested", .requested [0] [255]),
  ("yielded", .yielded []), ("completed", .completed [255]),
  ("failed", .failed [255] [0] none),
  ("capacity", .needsCapacity ⟨.output, ⟨wordLimit - 1, .exact⟩, ⟨128, .lowerBound⟩,
    ⟨0, .notObserved⟩, ⟨65536, .exact⟩⟩)]

private def emit (directory : System.FilePath) (mode name : String) (input : Bytes)
    (expected : Option Bytes) : IO Unit := do
  IO.FS.writeBinFile (directory / s!"{name}.input") ⟨input.toArray⟩
  if let some output := expected then
    IO.FS.writeBinFile (directory / s!"{name}.expected") ⟨output.toArray⟩
  IO.println s!"{mode}\t{name}\t{if expected.isSome then "ok" else "reject"}"

private def recordCase (directory : System.FilePath) (mode name : String)
    (codec : Wire.Codec α) (value : α) : IO Unit := do
  let encoded := codec.encode value
  let accepted := codec.valid value
  if (codec.decode encoded).isSome != accepted then
    throw <| IO.userError s!"protocol.admission_mismatch: {name}"
  emit directory mode name encoded (if accepted then some encoded else none)

def main (args : List String) : IO UInt32 := do
  let [directory] := args | throw <| IO.userError "usage: protocol_conformance.lean <output-directory>"
  let directory : System.FilePath := directory
  for size in [0, 1, 3, 55, 56, 63, 64, 65, 119, 120, 127, 128, 129, 255, 1024, 4096] do
    let input := (List.range size).map (fun n => UInt8.ofNat (n * 73 + 19))
    emit directory "sha256" s!"sha-{size}" input (some (SHA256.hash input).toList)
  for (name, candidate) in requests do
    let input := Images.rawRequest.encode candidate
    emit directory "request-identity" s!"request-{name}" input (some (requestIdentity candidate).toList)
    emit directory "contract-identity" s!"contract-{name}" input
      (some (contractIdentity candidate.semanticIdentity candidate.payloadSchema candidate.resumeSchema).toList)
    let value : Value .target := .scalar 0 (if name == "payload" then 1 else 0)
    emit directory "request" s!"admit-request-{name}" input
      (if checkRequest candidate value then some input else none)
    let bound := bindRequest candidate
    let rebound := Images.rawRequest.encode bound
    emit directory "request" s!"admit-rebound-{name}" rebound
      (if checkRequest bound value then some rebound else none)
  for (name, changed) in [("empty-name", { request with semanticIdentity := [] }),
      ("invalid-name", { request with semanticIdentity := [255] }),
      ("invalid-schema", { request with payloadSchema := [0, 0] }),
      ("noncanonical-schema", { request with payloadSchema := descriptor [.u64, .u64] }),
      ("internal-schema", { request with resumeSchema := descriptor [.internal (.capability 0)] }),
      ("short-payload", { request with payload := [0] }),
      ("trailing-payload", { request with payload := List.replicate 9 0 })] do
    let bound := bindRequest changed
    let input := Images.rawRequest.encode bound
    emit directory "request" s!"admit-request-{name}" input
      (if checkRequest bound (.scalar 0 0) then some input else none)
  let result : Result := ⟨request.requestIdentity, SHA256.hash request.resumeSchema, [1]⟩
  for (name, candidate, witness) in [("valid", result, (1 : Int)),
      ("false", { result with value := [0] }, 0),
      ("wrong-request", { result with requestIdentity := digest 0 }, 1),
      ("wrong-schema", { result with resumeSchemaDigest := digest 0 }, 1),
      ("invalid-boolean", { result with value := [2] }, 2),
      ("absent-value", { result with value := [] }, 1),
      ("trailing-value", { result with value := [1, 0] }, 1)] do
    let input := Wire.Codec.blob.encode (Images.rawRequest.encode request) ++
      Wire.Codec.blob.encode (Images.rawResult.encode candidate)
    emit directory "result" s!"result-{name}" input
      (if checkResult request candidate (.scalar 0 0) (.scalar 0 witness) then some input else none)
  for block in [0, 1, 127, 128, 16383, 16384, wordLimit - 1] do
    let input := (digest 1).toList ++ (digest 2).toList ++ Wire.natural block ++ (digest 3).toList
    emit directory "continuation-identity" s!"continuation-{block}" input
      (some (continuationIdentity (digest 1) (digest 2) ⟨block⟩ (digest 3)).toList)
  for (name, candidate) in programs do
    emit directory "program-identity" s!"program-{name}" (Codecs.rawProgram.encode candidate)
      (some (programIdentity candidate).toList)
  for (modeName, mode) in [("advance", Protocol.Mode.advance), ("run", .run)] do
    for (instanceName, instanceData) in [("initial", Instance.initialArgs [0, 255]), ("state", .state [255])] do
      let controls := [("continue", Control.continueValue none), ("result", .continueValue (some [255]))] ++
        reasons.map (fun (name, reason) => (s!"cancel-{name}", Control.cancel reason))
      for (controlName, control) in controls do
        recordCase directory "input" s!"input-{modeName}-{instanceName}-{controlName}" inputCodec
          ⟨mode, [255, 0], instanceData, control⟩
  for (name, outcome) in outcomes do
    recordCase directory "outcome" s!"outcome-{name}" outcomeCodec outcome
  for (reasonName, reason) in reasons do
    for (failureName, failures) in [("empty", [0]), ("values", [2, 0, 1, 255]),
        ("absent", []), ("trailing", [0, 0]), ("truncated", [1, 2, 0]), ("overlong", [128, 0])] do
      recordCase directory "outcome" s!"failed-{reasonName}-{failureName}" outcomeCodec
        (.failed [255] failures (some reason))
      recordCase directory "outcome" s!"cancelled-{reasonName}-{failureName}" outcomeCodec
        (.cancelled reason failures)
  return 0
