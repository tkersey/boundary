import BoundaryV2.SourceReader
import BoundaryV2.SourceMachine
import BoundaryV2.SourceContracts
import BoundaryV2.ValueCodec
import Lean

open Lean BoundaryV2 BoundaryV2.Profile
open BoundaryV2.Profile.Source.Machine

deriving instance Repr for BoundaryV2.Profile.Value

private def get (json : Lean.Json) (name : String) : Except String Lean.Json := json.getObjVal? name
private def nat (json : Lean.Json) (name : String) : Except String Nat := do (← get json name).getNat?
private def str (json : Lean.Json) (name : String) : Except String String := do (← get json name).getStr?
private def array (json : Lean.Json) (name : String) : Except String (List Lean.Json) := do return (← (← get json name).getArr?).toList

private def rows (json : Lean.Json) : Except String (List Source.Analysis.Row) := do
  (← json.getArr?).toList.mapM fun row => do
    (← row.getArr?).toList.mapM fun entry => do
      let pair ← entry.getArr?
      if pair.size != 2 then throw "bad fact row"
      return (⟨← pair[0]!.getNat?⟩, ← pair[1]!.getNat?)

private partial def value (json : Lean.Json) : Except String SemanticValue := do
  let schema : SchemaId .source := ⟨← nat json "schema"⟩
  match ← str json "kind" with
  | "scalar" =>
    let some integer := (← str json "value").toInt? | throw "bad integer"
    return .scalar schema integer
  | "blob" =>
    let bytes ← (← array json "value").mapM fun byte => do
      let n ← byte.getNat?
      if n < 256 then return UInt8.ofNat n else throw "bad byte"
    return .blob schema bytes
  | "product" => return .product schema (← (← array json "value").mapM value)
  | "sequence" => return .sequence schema (← (← array json "value").mapM value)
  | "variant" => return .variant schema (← nat json "tag") (← value (← get json "value"))
  | _ => throw "bad value kind"

private def bytesJson (bytes : Bytes) : Lean.Json := toJson (bytes.map UInt8.toNat)

private def encoded (source : Source.Module) (value : SemanticValue) : IO Lean.Json := do
  if !Profile.Value.externalValid source.schemas value then throw (IO.userError "non-external result")
  let bytes := Profile.Value.encode source.schemas value
  return bytesJson bytes

private def reasonJson : Protocol.Reason → Lean.Json
  | .text bytes => toJson (String.fromUTF8! bytes.toByteArray)
  | .bytes bytes => bytesJson bytes

private def controlDescription : Control → String
  | .term term _ => s!"term {term.value}"
  | .expression expression _ => s!"expression {expression.value}"
  | .invoke function _ _ => s!"invoke {function.value}"
  | .execute (.term term) _ values => s!"execute {repr term} operands {values.map (fun value => repr value.value)}"
  | .execute (.primitive schema opcode _ _) _ _ => s!"primitive {repr opcode}, result schema {schema.value}"
  | .delivered value => s!"delivered {repr value.value}"
  | .unwind _ => "unwind"
  | .release scope _ => s!"release {scope.value}"
  | .discard values _ => s!"discard {values.map (fun value => repr value.value)}"

private def frameDescription : Frame → String
  | .binding var next _ scope => s!"binding {var.value}/{next.value}/{scope.value}"
  | .operands .. => "operands"
  | .invocation invocation scope => s!"invocation {invocation.value}/{scope.value}"
  | .restore invocation scope => s!"restore {invocation.value}/{scope.value}"
  | .lexical scope => s!"lexical {scope.value}"
  | .handler activation => s!"handler {activation.identity.value}/{activation.definition.value}"
  | .region identity => s!"region {identity.value}"
  | .protection identity => s!"protection {identity.value}"
  | .cleanupReturn identity invocation .. => s!"cleanup {identity.value}/{invocation.value}"
  | .disposalReturn .. => "disposal"
  | .injection _ => "injection"
  | .releaseReturn .. => "releaseReturn"

private def accept (name : String) (state : State) (step : Nat) (result : Except Invalid Transition) : IO Transition :=
  match result with
  | .ok transition => pure transition
  | .error reason => throw (IO.userError s!"{name}: {repr reason} at transition {step}, {controlDescription state.control}, scope={state.scope.value}, invocation={state.invocation.value}, stack={state.stack.map frameDescription}")

private def traceEvent (source : Source.Module) (event : Event) : IO (Option Lean.Json) := do
  match event with
  | .yielded => return some (Lean.Json.mkObj [("kind", toJson "Yielded")])
  | .requestOpened request =>
    let some effect := source.effects[request.effect.value]? | throw (IO.userError "effect missing")
    return some (Lean.Json.mkObj [("kind", toJson "Requested"),
      ("identity", toJson (String.fromUTF8! effect.identity.toByteArray)), ("payload", ← encoded source request.payload)])
  | _ => return none

private def terminal (source : Source.Module) (state : State) (trace : List Lean.Json) : IO (Option Lean.Json) := do
  let fieldsBase := [("trace", toJson trace)]
  match state.status with
  | .completed value => return some (Lean.Json.mkObj (fieldsBase ++ [("kind", toJson "Completed"), ("value", ← encoded source value)]))
  | .failed exit =>
    let .failure value := exit.primary | throw (IO.userError "failed status/exit mismatch")
    let fields := fieldsBase ++ [("kind", toJson "Failed"), ("value", ← encoded source value),
      ("cleanupFailures", toJson (← exit.failures.mapM (encoded source)))]
    return some (Lean.Json.mkObj (fields ++ exit.cancellation.toList.map (fun reason => ("cancellation", reasonJson reason))))
  | .cancelled exit =>
    let some reason := exit.cancellation | throw (IO.userError "cancelled without reason")
    return some (Lean.Json.mkObj (fieldsBase ++ [("kind", toJson "Cancelled"), ("reason", reasonJson reason),
      ("cleanupFailures", toJson (← exit.failures.mapM (encoded source)))]))
  | _ => return none

private def orError (result : Except String α) : IO α :=
  match result with | .ok value => pure value | .error reason => throw (IO.userError reason)

private def rawBytes (json : Lean.Json) : Except String Bytes := do
  (← json.getArr?).toList.mapM fun item => do
    let number ← item.getNat?
    if number < 256 then pure (UInt8.ofNat number) else throw "invalid byte"

private def checkDecoded (source : Source.Module) (bytes : Bytes) (expected : SemanticValue) : IO Unit := do
  let some decoded := Profile.Value.decodeAt source.schemas (Profile.Value.height expected) expected.schema bytes
    | throw (IO.userError "value codec rejected canonical bytes")
  if decoded != expected then throw (IO.userError "value codec disagrees with independent witness")

private def runCase (context : Context) (test : Lean.Json) : IO Lean.Json := do
  let name ← orError (str test "name")
  let arguments ← orError ((← orError (array test "args")).mapM value)
  let responses ← orError ((← orError (array test "responses")).mapM value)
  let controls ← orError (array test "cancellations")
  if let .ok raw := get test "initial" then
    let bytes ← orError (rawBytes raw)
    let some entry := context.source.functions[context.source.entry.value]? | throw (IO.userError "missing entry")
    let types ← orError (entry.parameters.mapM (fun var => match context.source.variables[var.value]? with | some type => .ok type | none => .error "missing variable"))
    let depth := (arguments.map Profile.Value.height).foldl max 0
    let some (decoded, rest) := Profile.Value.readFields (Profile.Value.readTree context.source.schemas depth) types bytes
      | throw (IO.userError "initial argument codec rejection")
    if !rest.isEmpty || decoded != arguments then throw (IO.userError "initial argument codec mismatch")
  if let .ok raw := get test "responseBytes" then
    let bytes ← orError ((← orError raw.getArr?).toList.mapM rawBytes)
    if bytes.length != responses.length then throw (IO.userError "response byte inventory mismatch")
    for (bytes, expected) in bytes.zip responses do checkDecoded context.source bytes expected
  let mut state ← match initial context arguments with
    | .ok state => pure state | .error reason => throw (IO.userError s!"{name}: initial {repr reason}")
  let mut trace := []
  let mut responseIndex := 0
  let mut applied : List Nat := []
  for steps in [:2000000] do
    if let some result ← terminal context.source state trace then
      if responseIndex != responses.length || applied.length != controls.length then
        throw (IO.userError s!"{name}: unused external inputs")
      return Lean.Json.mkObj [("name", toJson name), ("steps", toJson steps), ("actual", result)]
    let transition ← accept name state steps (tick state context)
    state := transition.state
    for event in transition.events do
      if let some row ← traceEvent context.source event then trace := trace ++ [row]
    let boundary := match state.status with | .yielded | .parked _ => true | _ => false
    if boundary then
      for (control, id) in controls.zipIdx do
        let position ← orError (nat control "at")
        if position + 1 == trace.length && !applied.contains id then
          let raw ← orError (get control "reason")
          let reason ← match raw.getStr? with
            | .ok text => pure (Protocol.Reason.text text.toUTF8.toList)
            | .error _ => do
              let bytes ← orError ((← orError raw.getArr?).toList.mapM (fun byte => do pure (UInt8.ofNat (← byte.getNat?))))
              pure (Protocol.Reason.bytes bytes)
          state := (← accept name state steps (external state context (.cancel reason))).state
          applied := applied ++ [id]
      match state.status with
      | .yielded => state := (← accept name state steps (external state context .continueYield)).state
      | .parked request =>
        let some response := responses[responseIndex]? | throw (IO.userError s!"{name}: missing response")
        state := (← accept name state steps (external state context (.response request.occurrence response))).state
        responseIndex := responseIndex + 1
      | _ => pure ()
  throw (IO.userError s!"{name}: inconclusive operational test limit")

def main (arguments : List String) : IO UInt32 := do
  let [path] := arguments | throw (IO.userError "expected witness JSON")
  let json ← orError (Lean.Json.parse (← IO.FS.readFile path))
  for group in (← orError json.getArr?).toList do
    let sourcePath ← orError (str group "path")
    let some source := SourceReader.decode (← IO.FS.readBinFile sourcePath).toList | throw (IO.userError "source decode rejected")
    if let .ok expected := group.getObjVal? "constructors" then
      let expected ← orError ((← orError expected.getArr?).toList.mapM (fun entry => do
        pure ((⟨← nat entry "function"⟩ : FunctionId .source), (⟨← nat entry "schema"⟩ : SchemaId .source))))
      if Source.Analysis.constructors source != expected then throw (IO.userError s!"{sourcePath}: source constructor catalog mismatch")
    let facts ← orError (get group "facts")
    let context : Context := {
      source := source
      constants := ← orError ((← orError (array group "constants")).mapM value)
      captures := {
        values := ← orError (rows (← orError (get facts "values")))
        terms := ← orError (rows (← orError (get facts "terms")))
        functions := ← orError (rows (← orError (get facts "functions"))) } }
    if context.constants.length != source.constants.length then throw (IO.userError "constant inventory mismatch")
    if let .ok budget := group.getObjVal? "authorityBudgetMs" then
      let budget ← orError budget.getNat?
      let started ← IO.monoNanosNow
      let authority := Source.Admission.authorityTermRows source context.captures source.entry
      let some entry := source.functions[source.entry.value]? | throw (IO.userError "missing benchmark entry")
      if authority.length != source.terms.length || !(entry.body >>= fun body => authority[body.value]?).getD false then
        throw (IO.userError "source authority benchmark changed its result")
      if (← IO.monoNanosNow) - started > budget * 1000000 then
        throw (IO.userError "source authority scan exceeded its test time budget")
    if !context.typingValid then throw (IO.userError s!"{sourcePath}: source typing admission rejected")
    let some results := Source.Analysis.inferResults source
      | throw (IO.userError s!"{sourcePath}: source result inference rejected")
    if !Source.Analysis.foundationValid source context.captures results then
      throw (IO.userError s!"{sourcePath}: source declaration, result or capture admission rejected")
    if !Source.Admission.declarationsValid source context.constants then
      for (type, index) in source.schemas.zipIdx do
        if let .internal inner := type then
          if !Source.Admission.internalValid source inner then
            throw (IO.userError s!"{sourcePath}: source internal schema {index} rejected: {repr inner}")
      for (handler, index) in source.handlers.zipIdx do
        if !Source.Admission.handlerValid source handler then
          throw (IO.userError s!"{sourcePath}: source handler {index} rejected")
      throw (IO.userError s!"{sourcePath}: source declarations rejected")
    if !Source.Admission.contractsValid source then
      let effects := Source.Admission.effectFacts source
      for (function, index) in source.functions.zipIdx do
        let contracts := Source.Admission.contractRows source effects function.effects function.regions
        if !(function.body >>= fun body => contracts[body.value]?).getD false then
          throw (IO.userError s!"{sourcePath}: source function {index} contract rejected")
      throw (IO.userError s!"{sourcePath}: source unreachable term contract rejected")
    let allEffects := (List.range source.effects.length).map (fun index => (⟨index⟩ : EffectId .source))
    let allRegions := (List.range source.regionCount).map (fun index => (⟨index⟩ : RegionId .source))
    let badValue : SourceValueId := ⟨source.values.length⟩
    for term in source.terms do
      let malformed : Option Source.Term := match term with
        | .call function arguments => some (.call function (arguments ++ [badValue]))
        | .apply closure arguments => some (.apply closure (arguments ++ [badValue]))
        | .perform operation => some (.perform { operation with payload := badValue })
        | .handle handler body arguments state => some (.handle handler body (arguments ++ [badValue]) state)
        | .resumeValue token _ => some (.resumeValue token badValue)
        | .resumeWith token argument handler state => some (.resumeWith token argument handler (state ++ [badValue]))
        | .resumeComputation token _ => some (.resumeComputation token badValue)
        | .protect body _ arguments resource region => some (.protect body badValue arguments resource region)
        | .withRegion region _ arguments => some (.withRegion region badValue arguments)
        | .dispose _ => some (.dispose badValue)
        | .fail _ => some (.fail badValue)
        | .value _ | .bind .. | .conditional .. | .yieldThen _ | .matchSum .. | .unpackProduct .. => none
      if malformed.any (Source.Admission.termValid source (Source.Admission.effectFacts source) allEffects allRegions) then
        throw (IO.userError s!"{sourcePath}: source control contract mutation admitted")
    for effect in source.effects do
      if Source.Admission.effectValid source { effect with identity := [] } ||
          Source.Admission.effectValid source { effect with result := ⟨source.schemas.length⟩ } then
        throw (IO.userError s!"{sourcePath}: source effect declaration mutation admitted")
    for handler in source.handlers do
      if Source.Admission.handlerValid source { handler with returnFunction := ⟨source.functions.length⟩ } then
        throw (IO.userError s!"{sourcePath}: source handler declaration mutation admitted")
    if !Source.Admission.primitivesValid source context.captures then
      for (value, index) in source.values.zipIdx do
        if !Source.Admission.primitiveValid source context.captures value then
          throw (IO.userError s!"{sourcePath}: source primitive or lambda {index} rejected: {repr value}")
      throw (IO.userError s!"{sourcePath}: source resource authority rejected")
    for value in source.values do
      match value.expression with
      | .primitive opcode operands immediate failures =>
        let badType := { value with schema := ⟨source.schemas.length⟩ }
        let badOperand := { value with expression := .primitive opcode (operands ++ [⟨source.values.length⟩]) immediate failures }
        let badFault := { value with expression := .primitive opcode operands immediate (failures ++ [⟨.arithmeticOverflow, ⟨source.constants.length + 1⟩⟩]) }
        if [badType, badOperand, badFault].any (Source.Admission.primitiveValid source context.captures) then
          throw (IO.userError s!"{sourcePath}: source primitive mutation admitted")
      | .lambda _ =>
        if Source.Admission.primitiveValid source context.captures { value with schema := ⟨source.schemas.length⟩ } then
          throw (IO.userError s!"{sourcePath}: source lambda schema mutation admitted")
      | _ => pure ()
    let some first := results.head? | throw (IO.userError "source result table empty")
    let changed := results.set 0 (if first.isNone then some ⟨source.schemas.length⟩ else none)
    if Source.Analysis.resultsValid source changed || Source.Analysis.resultsValid source results.tail then
      throw (IO.userError "source result table mutation admitted")
    for (literal, expected) in source.constants.zip context.constants do checkDecoded source literal.bytes expected
    for test in (← orError (array group "tests")) do
      try
        IO.println (← runCase context test).compress
      catch error =>
        let name ← orError (str test "name")
        IO.println (Lean.Json.mkObj [("name", toJson name), ("error", toJson error.toString)]).compress
  return 0
