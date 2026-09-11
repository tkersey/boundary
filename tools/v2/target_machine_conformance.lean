import BoundaryV2.Images
import BoundaryV2.TargetMachine
import BoundaryV2.UseAdmission
import Lean

open Lean BoundaryV2 BoundaryV2.Profile
open BoundaryV2.Profile.Target.Machine

deriving instance Repr for BoundaryV2.Profile.Value

private def get (json : Lean.Json) (name : String) : Except String Lean.Json := json.getObjVal? name
private def nat (json : Lean.Json) (name : String) : Except String Nat := do (← get json name).getNat?
private def str (json : Lean.Json) (name : String) : Except String String := do (← get json name).getStr?
private def array (json : Lean.Json) (name : String) : Except String (List Lean.Json) := do return (← (← get json name).getArr?).toList

private def rawBytes (json : Lean.Json) : Except String Bytes := do
  (← json.getArr?).toList.mapM fun item => do
    let number ← item.getNat?
    if number < 256 then pure (UInt8.ofNat number) else throw "invalid byte"

private partial def value (json : Lean.Json) : Except String SemanticValue := do
  let schema : SchemaId .target := ⟨← nat json "schema"⟩
  match ← str json "kind" with
  | "scalar" =>
    let some integer := (← str json "value").toInt? | throw "bad integer"
    return .scalar schema integer
  | "blob" => return .blob schema (← rawBytes (← get json "value"))
  | "product" => return .product schema (← (← array json "value").mapM value)
  | "sequence" => return .sequence schema (← (← array json "value").mapM value)
  | "variant" => return .variant schema (← nat json "tag") (← value (← get json "value"))
  | _ => throw "bad value kind"

private def orError (result : Except String α) : IO α :=
  match result with | .ok value => pure value | .error reason => throw (IO.userError reason)

private def bytesJson (bytes : Bytes) : Lean.Json := toJson (bytes.map UInt8.toNat)

private def encoded (program : Target.Program) (value : SemanticValue) : IO Lean.Json := do
  if !Profile.Value.externalValid program.schemas value then throw (IO.userError "non-external result")
  return bytesJson (Profile.Value.encode program.schemas value)

private def reasonJson : Protocol.Reason → Lean.Json
  | .text bytes => toJson (String.fromUTF8! bytes.toByteArray)
  | .bytes bytes => bytesJson bytes

private def terminal (program : Target.Program) (state : State program) (trace : List Lean.Json) : IO (Option Lean.Json) := do
  let fields := [("trace", toJson trace)]
  match state.result with
  | some (.completed value) => return some (Lean.Json.mkObj (fields ++ [("kind", toJson "Completed"), ("value", ← encoded program value)]))
  | some (.failed value failures reason) =>
    return some (Lean.Json.mkObj (fields ++ [("kind", toJson "Failed"), ("value", ← encoded program value),
      ("cleanupFailures", toJson (← failures.mapM (encoded program)))] ++ reason.toList.map (fun reason => ("cancellation", reasonJson reason))))
  | some (.cancelled reason failures) =>
    return some (Lean.Json.mkObj (fields ++ [("kind", toJson "Cancelled"), ("reason", reasonJson reason),
      ("cleanupFailures", toJson (← failures.mapM (encoded program)))]))
  | none => return none

private def traceEvent (program : Target.Program) (event : Event) : IO (Option Lean.Json) := do
  match event with
  | .yielded => return some (Lean.Json.mkObj [("kind", toJson "Yielded")])
  | .requestOpened _ effect payload =>
    let some effect := program.effects[effect.value]? | throw (IO.userError "missing effect")
    return some (Lean.Json.mkObj [("kind", toJson "Requested"),
      ("identity", toJson (String.fromUTF8! effect.identity.toByteArray)), ("payload", ← encoded program payload)])
  | _ => return none

private def accept (context : Context) (name : String) (state : State context.program) (steps : Nat)
    (result : Except Invalid (Transition context.program)) : IO (Transition context.program) :=
  match result with
  | .ok transition => pure transition
  | .error reason =>
    let position := state.roots.current.bind state.store.lookup
    let detail := match position with
      | some (.control control) =>
        match context.program.blocks[control.block.value]? with
        | some block =>
          let phase := match evaluateBlock context state control with
            | .error reason => s!"instruction evaluation {repr reason}"
            | .ok (.complete _ _) => "terminator"
            | .ok (.failed ..) => "authored fault unwind"
          s!"\nphase: {phase}\nblock: {repr block}"
        | none => ""
      | _ => ""
    throw (IO.userError s!"{name}: {repr reason} at transition {steps}, {repr position}{detail}")

private def runCase (context : Context) (test : Lean.Json) : IO Lean.Json := do
  let name ← orError (str test "name")
  let arguments ← orError ((← orError (array test "args")).mapM value)
  let responses ← orError ((← orError (array test "responses")).mapM value)
  let controls ← orError (array test "cancellations")
  let initialBytes ← orError (rawBytes (← orError (get test "initial")))
  let some entry := context.program.functions[context.program.roots.entry.value]? | throw (IO.userError "missing entry")
  let depth := (arguments.map Profile.Value.height).foldl max 0
  let some (decoded, rest) := Profile.Value.readFields (Profile.Value.readTree context.program.schemas depth) entry.parameters initialBytes
    | throw (IO.userError "initial value decoding rejected")
  if !rest.isEmpty || decoded != arguments then throw (IO.userError "initial witness mismatch")
  let responseBytes ← orError ((← orError (array test "responseBytes")).mapM rawBytes)
  if responseBytes.length != responses.length then throw (IO.userError "response inventory mismatch")
  for (bytes, response) in responseBytes.zip responses do
    if !Profile.Value.checkExternal context.program.schemas response.schema bytes response then
      throw (IO.userError "response witness mismatch")
  let mut state ← match initial context (Vector.replicate 32 0) arguments with
    | .ok state => pure state | .error reason => throw (IO.userError s!"{name}: initial {repr reason}")
  let mut trace := []
  let mut responseIndex := 0
  let mut applied : List Nat := []
  for steps in [:2000000] do
    if let some result ← terminal context.program state trace then
      if responseIndex != responses.length || applied.length != controls.length then throw (IO.userError s!"{name}: unused external inputs")
      return Lean.Json.mkObj [("name", toJson name), ("steps", toJson steps), ("actual", result)]
    let transition ← accept context name state steps (tick context state)
    state := transition.state
    for event in transition.events do
      if let some row ← traceEvent context.program event then trace := trace ++ [row]
    if state.status == .yielded || state.status == .parked then
      for (control, id) in controls.zipIdx do
        let position ← orError (nat control "at")
        if position + 1 == trace.length && !applied.contains id then
          let raw ← orError (get control "reason")
          let reason ← match raw.getStr? with
            | .ok text => pure (Protocol.Reason.text text.toUTF8.toList)
            | .error _ => pure (Protocol.Reason.bytes (← orError (rawBytes raw)))
          state := (← accept context name state steps (external context state (.cancel reason))).state
          applied := applied ++ [id]
      match state.status with
      | .yielded => state := (← accept context name state steps (external context state .continueYield)).state
      | .parked =>
        let some response := responses[responseIndex]? | throw (IO.userError s!"{name}: missing response")
        let some occurrence := state.pendingOccurrence | throw (IO.userError "missing request occurrence")
        state := (← accept context name state steps (external context state (.response occurrence response))).state
        responseIndex := responseIndex + 1
      | _ => pure ()
  throw (IO.userError s!"{name}: inconclusive operational test limit")

def main (arguments : List String) : IO UInt32 := do
  let [path] := arguments | throw (IO.userError "expected witness JSON")
  let json ← orError (Lean.Json.parse (← IO.FS.readFile path))
  for group in (← orError json.getArr?).toList do
    let path ← orError (str group "path")
    let some program := Images.decodeImage (← IO.FS.readBinFile path).toList | throw (IO.userError s!"{path}: image decoder rejected")
    let constants ← orError ((← orError (array group "constants")).mapM value)
    let some context := Context.ofWitness program constants | throw (IO.userError s!"{path}: constant witnesses rejected")
    if !Target.Admission.declarationsValid program constants then
      throw (IO.userError s!"{path}: program declaration admission rejected")
    if !Target.Admission.regionsValid program then
      throw (IO.userError s!"{path}: program region admission rejected")
    let effectFacts := Target.Admission.effectFacts program
    for (block, index) in program.blocks.zipIdx do
      if !Target.Admission.blockInstructionsValid program block then
        throw (IO.userError s!"{path}: block {index} instruction admission rejected")
      if !Target.Admission.terminatorValid program effectFacts block then
        throw (IO.userError s!"{path}: block {index} terminator admission rejected")
      if !Target.Admission.blockUsesValid program effectFacts block then
        throw (IO.userError s!"{path}: block {index} use admission rejected")
    for test in (← orError (array group "tests")) do
      let name ← orError (str test "name")
      let row ← try runCase context test catch error => pure (Lean.Json.mkObj [("name", toJson name), ("error", toJson error.toString)])
      IO.println row.compress
  return 0
