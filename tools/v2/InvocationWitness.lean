import GraphWitness
import BoundaryV2.TargetExecution
import Lean

open Lean BoundaryV2 BoundaryV2.Profile
open BoundaryV2.Profile.Target

namespace BoundaryV2.Tooling.InvocationWitness

def orError (result : Except String α) : IO α :=
  match result with | .ok value => pure value | .error reason => throw (IO.userError reason)
def field (json : Json) (name : String) : IO Json := orError (json.getObjVal? name)
def string (json : Json) (name : String) : IO String := do orError ((← field json name).getStr?)
def required (result : Option α) (reason : String) : IO α :=
  match result with | some value => pure value | none => throw (IO.userError reason)
def semantic (result : Except Machine.Invalid α) (reason : String) : IO α :=
  match result with | .ok value => pure value | .error error => throw (IO.userError s!"{reason}: {repr error}")

structure ProgramCache where
  path : String
  bytes : Bytes
  witness : Admission.Witness
  image : Machine.ImageContext bytes witness

def meaning (schemas : List (Schema .target)) (schema : SchemaId .target) (bytes : Bytes) : IO (Value .target) :=
  required (Value.decodeAt schemas 1000 schema bytes) "inconclusive: external value witness search"

def loadProgram (path : String) : IO ProgramCache := do
  let bytes := (← IO.FS.readBinFile path).toList
  let program ← required (Images.decodeImage bytes) s!"{path}: malformed BPI2"
  let constants ← program.constants.mapM fun literal => meaning program.schemas literal.schema literal.bytes
  let (subject, borrows) ← Tooling.BorrowWitness.read (← orError (Json.parse (← IO.FS.readFile (path ++ ".graph.borrow.json"))))
  if subject != program then throw (IO.userError "borrow witness differs from complete image program")
  let witness : Admission.Witness := ⟨constants, borrows⟩
  let image ← required (Machine.ImageContext.decode bytes witness) s!"{path}: complete program admission rejected"
  pure ⟨path, bytes, witness, image⟩

def graphWitness (entry : ProgramCache) (state : Graph.State) : IO Graph.Admission.Witness := do
  let blobs ← state.blobs.mapM fun blob => meaning entry.image.context.program.schemas blob.schema blob.bytes
  let projections ← match ← Tooling.GraphWitness.rows entry.image.context.program state entry.witness.borrows with
    | .ok rows => pure rows
    | .error query => throw (IO.userError s!"inconclusive: invocation needs additional program borrow query {repr query}")
  pure ⟨blobs, projections⟩

def responseWitness (entry : ProgramCache) (state : Graph.State) (snapshot bytes : Bytes) : IO Boundary.ResponseWitness := do
  let program := entry.image.context.program
  let request ← semantic (Boundary.request program state snapshot) "derive response request"
  let result ← required (Images.rawResult.decode bytes) "malformed ERS2"
  let (payload, resume) ← required (Protocol.requestDescriptors request) "malformed request descriptors"
  let pending ← required state.roots.pending "response without pending root"
  let some (.pending effect _ _ _) := state.nodes[pending.value]? | throw (IO.userError "response without pending node")
  let effect ← required program.effects[effect.value]? "missing response effect"
  pure ⟨← meaning program.schemas effect.result result.value,
    ← meaning payload.types payload.root request.payload, ← meaning resume.types resume.root result.value⟩

def inputWitness (entry : ProgramCache) (input : Protocol.Input) (clock : Boundary.Clock) : IO Boundary.InputWitness := do
  let program := entry.image.context.program
  match input.instanceData with
  | .initialArgs bytes =>
    let function ← required program.functions[program.roots.entry.value]? "missing entry function"
    let (arguments, rest) ← required (Value.readFields (Value.readTree program.schemas 1000) function.parameters bytes)
      "inconclusive: initial argument witness search"
    if !rest.isEmpty then throw (IO.userError "trailing initial argument bytes")
    let initial ← semantic (entry.image.initial arguments) "model initialization"
    pure ⟨arguments, ← graphWitness entry initial.raw, clock, none⟩
  | .state bytes =>
    let state ← required (Graph.Snapshot.decode bytes) "malformed incoming PST2"
    let response ← match input.control with
      | .continueValue (some result) => do pure (some (← responseWitness entry state bytes result))
      | _ => pure none
    pure ⟨[], ← graphWitness entry state, clock, response⟩

def outputState : Protocol.Outcome → Option Bytes
  | .progressed bytes | .yielded bytes | .requested bytes _ => some bytes
  | _ => none

/-- Search only for candidate finite evidence. The boundary checker then
compares the complete captured output; this native search is not proof. -/
def deriveInvocation (entry : ProgramCache) (record : Boundary.PublicInvocation)
    (clock : Boundary.Clock) : IO (Boundary.InvocationWitness × Boundary.InvocationResult) := do
  let input ← required (Protocol.inputCodec.decode record.input) "malformed captured PKI2"
  let output ← required (Protocol.outcomeCodec.decode record.output) "malformed captured PKO2"
  let incoming ← inputWitness entry input clock
  let prepared ← semantic (Boundary.prepare entry.image input incoming) "prepare captured invocation"
  let count ← match input.mode with
    | .advance => pure 1
    | .run => do
      let mut state := prepared.state
      let mut count := 0
      while !Boundary.stopped state do
        if count == 100000 then throw (IO.userError "inconclusive: invocation witness search")
        state := (← semantic (Machine.tick entry.image.context state) "captured invocation transition").state
        count := count + 1
      pure count
  let outgoing ← match outputState output with
    | none => pure ⟨[], []⟩
    | some bytes => graphWitness entry (← required (Graph.Snapshot.decode bytes) "malformed captured PST2")
  let witness : Boundary.InvocationWitness := ⟨incoming, outgoing, count⟩
  let checked ← required (Boundary.checkInvocation entry.image record clock witness) "captured invocation disagreement"
  return (witness, checked)

end BoundaryV2.Tooling.InvocationWitness
