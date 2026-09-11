import BoundaryV2.SourceJson
import BoundaryV2.ProfileCodec

namespace BoundaryV2.Profile.SourceReader
open SourceJson

abbrev Reader (α : Type) := SourceJson.Value → Option α
abbrev Fields := List (Bytes × SourceJson.Value)

private def object (allowed : List String) : Reader Fields
  | .object fields =>
    if fields.all (fun field => allowed.any (fun key => text key == field.1)) ∧
        (fields.map Prod.fst).Nodup then some fields else none
  | _ => none

private def field (fields : Fields) (name : String) (read : Reader α) : Option α :=
  ((fields.find? fun entry => entry.1 == text name).map Prod.snd).bind read

private def defaultField (fields : Fields) (name : String) (read : Reader α) (fallback : α) : Option α :=
  match fields.find? fun entry => entry.1 == text name with
  | none => some fallback
  | some (_, value) => read value

private def natural : Reader Nat
  | .number value => if value < wordLimit then some value else none
  | _ => none
private def boolean : Reader Bool
  | .boolean value => some value
  | _ => none
private def unit : Reader Unit
  | .object [] => some ()
  | _ => none
private def reference (space : Space) (domain : Domain) : Reader (Ref space domain) :=
  fun value => (natural value).map Ref.mk
private def list (read : Reader α) : Reader (List α)
  | .array values => values.mapM read
  | _ => none
private def optional (read : Reader α) : Reader (Option α)
  | .null => some none
  | value => (read value).map some
private def bytes : Reader Bytes := list fun value => do
  let value ← natural value
  if value < 256 then some (UInt8.ofNat value) else none
private def enumeration (values : List (String × α)) : Reader α
  | .string key => (values.find? fun entry => text entry.1 == key).map Prod.snd
  | _ => none
private def tagged : Reader (Bytes × SourceJson.Value)
  | .object [entry] => some entry
  | _ => none
private def schemaRef := reference .source .schema
private def constantRef := reference .source .constant
private def effectRef := reference .source .effect
private def functionRef := reference .source .function
private def handlerRef := reference .source .handler
private def regionRef := reference .source .regionBinder
private def resourceRef := reference .source .resource
private def variableRef := reference .source .variable
private def valueRef := reference .source .value
private def termRef := reference .source .term

private def names (values : List α) (name : α → String) : Reader α :=
  enumeration (values.map fun value => (name value, value))
private def use : Reader Use := names Codecs.useValues Codecs.useName
private def mode : Reader Mode := names Codecs.modeValues Codecs.modeName
private def fault : Reader Fault := names Codecs.faultValues Codecs.faultName
private def opcode : Reader Opcode := names Codecs.opcodeValues Codecs.opcodeName

private def computationType : Reader (ComputationType .source) := fun input => do
  let fields ← object ["parameters", "result", "effects", "capture_bound", "use", "regions"] input
  return {
    parameters := ← field fields "parameters" (list schemaRef)
    result := ← field fields "result" schemaRef
    effects := ← defaultField fields "effects" (list effectRef) []
    captureBound := ← defaultField fields "capture_bound" (list schemaRef) []
    use := ← defaultField fields "use" use .reusable
    regions := ← defaultField fields "regions" (list regionRef) [] }

private def resumptionType : Reader (ResumptionType .source) := fun input => do
  let fields ← object ["effect", "input", "answer", "effects", "capture_bound", "handled", "escaping", "mode", "use", "owned_regions", "obligations"] input
  return {
    effect := ← field fields "effect" effectRef
    input := ← field fields "input" schemaRef
    answer := ← field fields "answer" schemaRef
    effects := ← defaultField fields "effects" (list effectRef) []
    captureBound := ← defaultField fields "capture_bound" (list schemaRef) []
    handled := ← field fields "handled" (list effectRef)
    escaping := ← defaultField fields "escaping" (list effectRef) []
    mode := ← field fields "mode" mode
    use := ← field fields "use" use
    ownedRegions := ← defaultField fields "owned_regions" (list regionRef) []
    obligations := ← defaultField fields "obligations" boolean false }

private def internal : Reader (Internal .source) := fun input => do
  let (key, value) ← tagged input
  if key == text "computation" then return .computation (← computationType value)
  else if key == text "capability" then return .capability (← effectRef value)
  else if key == text "cell" then
    let fields ← object ["element", "region"] value
    return .cell (← field fields "element" schemaRef) (← field fields "region" regionRef)
  else if key == text "region" then return .region (← regionRef value)
  else if key == text "resumption" then return .resumption (← resumptionType value)
  else if key == text "suspension_package" then return .suspensionPackage (← schemaRef value)
  else if key == text "abstract_resource" then return .abstractResource (← resourceRef value)
  else if key == text "borrowed" then
    let fields ← object ["value", "region"] value
    return .borrowed (← field fields "value" schemaRef) (← field fields "region" regionRef)
  else none

private def schema : Reader (Schema .source) := fun input => do
  let (key, value) ← tagged input
  let atoms : List (String × Schema .source) := [
    ("unit", .unit), ("boolean", .boolean), ("i8", .i8), ("i16", .i16), ("i32", .i32), ("i64", .i64),
    ("u8", .u8), ("u16", .u16), ("u32", .u32), ("u64", .u64), ("bytes", .bytes), ("text", .text)]
  if let some (_, atom) := atoms.find? (fun entry => text entry.1 == key) then
    let _ ← unit value
    return atom
  else if key == text "product" then return .product (← list schemaRef value)
  else if key == text "sum" then return .sum (← list schemaRef value)
  else if key == text "seq" then return .seq (← schemaRef value)
  else if key == text "vector" then
    let fields ← object ["element", "maximum"] value
    return .vector (← field fields "element" schemaRef) (← field fields "maximum" natural)
  else if key == text "internal" then return .internal (← internal value)
  else if key == text "array" then
    let fields ← object ["element", "length"] value
    return .array (← field fields "element" schemaRef) (← field fields "length" natural)
  else if key == text "bounded_bytes" then return .boundedBytes (← natural value)
  else if key == text "bounded_text" then return .boundedText (← natural value)
  else if key == text "enumeration" then
    let tags ← list natural value
    if tags.all (fun tag => tag < 2 ^ 32) then return .enumeration tags else none
  else none

private def literal : Reader (Literal .source) := fun input => do
  let fields ← object ["schema", "bytes"] input
  return ⟨← field fields "schema" schemaRef, ← field fields "bytes" bytes⟩

private def effect : Reader (Effect .source) := fun input => do
  let fields ← object ["identity", "payload", "result", "use_site_effects", "bodies", "control_use", "external"] input
  return {
    identity := ← field fields "identity" bytes
    payload := ← field fields "payload" schemaRef
    result := ← field fields "result" schemaRef
    useSiteEffects := ← defaultField fields "use_site_effects" (list effectRef) []
    bodies := ← defaultField fields "bodies" (list schemaRef) []
    controlUse := ← defaultField fields "control_use" use .linear
    external := ← defaultField fields "external" boolean true }

private def instructionFailure : Reader (InstructionFailure .source) := fun input => do
  let fields ← object ["kind", "value"] input
  return ⟨← field fields "kind" fault, ← field fields "value" constantRef⟩

private def clause : Reader (Clause .source) := fun input => do
  let fields ← object ["effect", "function", "resumption", "direct"] input
  return ⟨← field fields "effect" effectRef, ← field fields "function" functionRef,
    ← field fields "resumption" schemaRef, ← defaultField fields "direct" boolean false⟩

private def handler : Reader (Handler .source) := fun input => do
  let fields ← object ["mode", "input", "answer", "return_function", "clauses", "forward_function", "state", "effects"] input
  return {
    mode := ← field fields "mode" mode
    input := ← field fields "input" schemaRef
    answer := ← field fields "answer" schemaRef
    returnFunction := ← field fields "return_function" functionRef
    clauses := ← field fields "clauses" (list clause)
    forwardFunction := ← defaultField fields "forward_function" (optional functionRef) none
    state := ← defaultField fields "state" (list schemaRef) []
    effects := ← defaultField fields "effects" (list effectRef) [] }

private def resource : Reader (Resource .source) := fun input => do
  let fields ← object ["representation", "introducers", "eliminators"] input
  return ⟨← field fields "representation" schemaRef, ← field fields "introducers" (list functionRef),
    ← field fields "eliminators" (list functionRef)⟩

private def expression : Reader Source.Expression := fun input => do
  let (key, value) ← tagged input
  if key == text "variable" then return .variable (← variableRef value)
  else if key == text "literal" then return .literal (← constantRef value)
  else if key == text "lambda" then return .lambda (← functionRef value)
  else if key == text "primitive" then
    let fields ← object ["opcode", "operands", "immediate", "failures"] value
    return .primitive (← field fields "opcode" opcode) (← field fields "operands" (list valueRef))
      (← defaultField fields "immediate" natural 0) (← defaultField fields "failures" (list instructionFailure) [])
  else none

private def value : Reader Source.Value := fun input => do
  let fields ← object ["schema", "expression"] input
  return ⟨← field fields "schema" schemaRef, ← field fields "expression" expression⟩

private def operation : Reader Source.Operation := fun input => do
  let fields ← object ["effect", "capability", "payload", "bodies", "use_site_capabilities"] input
  return {
    effect := ← field fields "effect" effectRef
    capability := ← defaultField fields "capability" (optional valueRef) none
    payload := ← field fields "payload" valueRef
    bodies := ← defaultField fields "bodies" (list valueRef) []
    useSiteCapabilities := ← defaultField fields "use_site_capabilities" (list valueRef) [] }

private def matchCase : Reader (VariableId × TermId) := fun input => do
  let fields ← object ["variable", "body"] input
  return (← field fields "variable" variableRef, ← field fields "body" termRef)

private def term : Reader Source.Term := fun input => do
  let (key, value) ← tagged input
  if key == text "value" then return .value (← valueRef value)
  else if key == text "bind" then
    let fields ← object ["variable", "value", "next"] value
    return .bind (← field fields "variable" variableRef) (← field fields "value" termRef) (← field fields "next" termRef)
  else if key == text "conditional" then
    let fields ← object ["condition", "when_true", "when_false"] value
    return .conditional (← field fields "condition" valueRef) (← field fields "when_true" termRef) (← field fields "when_false" termRef)
  else if key == text "call" then
    let fields ← object ["function", "arguments"] value
    return .call (← field fields "function" functionRef) (← field fields "arguments" (list valueRef))
  else if key == text "apply" then
    let fields ← object ["computation", "arguments"] value
    return .apply (← field fields "computation" valueRef) (← field fields "arguments" (list valueRef))
  else if key == text "perform" then return .perform (← operation value)
  else if key == text "handle" then
    let fields ← object ["handler", "body", "arguments", "state"] value
    return .handle (← field fields "handler" handlerRef) (← field fields "body" valueRef)
      (← defaultField fields "arguments" (list valueRef) []) (← defaultField fields "state" (list valueRef) [])
  else if key == text "resume_value" then
    let fields ← object ["resumption", "argument"] value
    return .resumeValue (← field fields "resumption" valueRef) (← field fields "argument" valueRef)
  else if key == text "resume_with" then
    let fields ← object ["resumption", "argument", "handler", "state"] value
    return .resumeWith (← field fields "resumption" valueRef) (← field fields "argument" valueRef)
      (← field fields "handler" handlerRef) (← defaultField fields "state" (list valueRef) [])
  else if key == text "resume_computation" then
    let fields ← object ["resumption", "computation"] value
    return .resumeComputation (← field fields "resumption" valueRef) (← field fields "computation" valueRef)
  else if key == text "protect" then
    let fields ← object ["body", "cleanup", "arguments", "resource", "loan_region"] value
    return .protect (← field fields "body" valueRef) (← field fields "cleanup" valueRef)
      (← defaultField fields "arguments" (list valueRef) [])
      (← defaultField fields "resource" (optional valueRef) none)
      (← defaultField fields "loan_region" (optional regionRef) none)
  else if key == text "with_region" then
    let fields ← object ["region", "body", "arguments"] value
    return .withRegion (← field fields "region" regionRef) (← field fields "body" valueRef)
      (← defaultField fields "arguments" (list valueRef) [])
  else if key == text "dispose" then return .dispose (← valueRef value)
  else if key == text "fail" then return .fail (← valueRef value)
  else if key == text "yield_then" then return .yieldThen (← termRef value)
  else if key == text "match_sum" then
    let fields ← object ["value", "cases"] value
    return .matchSum (← field fields "value" valueRef) (← field fields "cases" (list matchCase))
  else if key == text "unpack_product" then
    let fields ← object ["value", "variables", "body"] value
    return .unpackProduct (← field fields "value" valueRef) (← field fields "variables" (list variableRef))
      (← field fields "body" termRef)
  else none

private def function : Reader Source.Function := fun input => do
  let fields ← object ["parameters", "result", "effects", "regions", "body"] input
  return {
    parameters := ← field fields "parameters" (list variableRef)
    result := ← field fields "result" schemaRef
    effects := ← defaultField fields "effects" (list effectRef) []
    regions := ← defaultField fields "regions" (list regionRef) []
    body := ← defaultField fields "body" (optional termRef) none }

private def module : Reader Source.Module := fun input => do
  let fields ← object ["entry", "failure", "schemas", "constants", "effects", "handlers", "region_count", "resources", "variables", "values", "terms", "functions"] input
  return {
    entry := ← field fields "entry" functionRef
    failure := ← field fields "failure" schemaRef
    schemas := ← field fields "schemas" (list schema)
    constants := ← field fields "constants" (list literal)
    effects := ← field fields "effects" (list effect)
    handlers := ← field fields "handlers" (list handler)
    regionCount := ← field fields "region_count" natural
    resources := ← defaultField fields "resources" (list resource) []
    variables := ← field fields "variables" (list schemaRef)
    values := ← field fields "values" (list value)
    terms := ← field fields "terms" (list term)
    functions := ← field fields "functions" (list function) }

/-- Complete staged Module interpretation. This retains all declarations;
semantic admission is responsible for types, scopes and syntax cycles before
any unreachable-code pruning is permitted. -/
def decode (bytes : Bytes) : Option Source.Module := (SourceJson.parse bytes).bind module

end BoundaryV2.Profile.SourceReader
