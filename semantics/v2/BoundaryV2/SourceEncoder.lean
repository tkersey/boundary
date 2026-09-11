import BoundaryV2.ProfileCodec

namespace BoundaryV2.Profile.SourceEncoder

private def join (separator : String) (values : List String) : String := String.intercalate separator values
private def array (encode : α → String) (values : List α) : String := "[" ++ join "," (values.map encode) ++ "]"
private def object (fields : List (String × String)) : String :=
  "{" ++ join "," (fields.map fun (key, value) => "\"" ++ key ++ "\":" ++ value) ++ "}"
private def tag (name value : String) : String := object [(name, value)]
private def reference (value : Ref space domain) : String := toString value.value
private def optional (encode : α → String) : Option α → String
  | none => "null"
  | some value => encode value
private def boolean (value : Bool) : String := if value then "true" else "false"
private def bytes (value : Bytes) : String := array (toString ∘ UInt8.toNat) value
private def named (name : α → String) (value : α) : String := "\"" ++ name value ++ "\""

private def computationType (value : ComputationType .source) : String := object [
  ("parameters", array reference value.parameters), ("result", reference value.result),
  ("effects", array reference value.effects), ("capture_bound", array reference value.captureBound),
  ("use", named Codecs.useName value.use), ("regions", array reference value.regions)]

private def resumptionType (value : ResumptionType .source) : String := object [
  ("effect", reference value.effect), ("input", reference value.input), ("answer", reference value.answer),
  ("effects", array reference value.effects), ("capture_bound", array reference value.captureBound),
  ("handled", array reference value.handled), ("escaping", array reference value.escaping),
  ("mode", named Codecs.modeName value.mode), ("use", named Codecs.useName value.use),
  ("owned_regions", array reference value.ownedRegions), ("obligations", boolean value.obligations)]

private def internal : Internal .source → String
  | .computation value => tag "computation" (computationType value)
  | .capability effect => tag "capability" (reference effect)
  | .cell element region => tag "cell" (object [("element", reference element), ("region", reference region)])
  | .region region => tag "region" (reference region)
  | .resumption value => tag "resumption" (resumptionType value)
  | .suspensionPackage value => tag "suspension_package" (reference value)
  | .abstractResource resource => tag "abstract_resource" (reference resource)
  | .borrowed value region => tag "borrowed" (object [("value", reference value), ("region", reference region)])

private def schema : Schema .source → String
  | .unit => tag "unit" "{}" | .boolean => tag "boolean" "{}"
  | .i8 => tag "i8" "{}" | .i16 => tag "i16" "{}" | .i32 => tag "i32" "{}" | .i64 => tag "i64" "{}"
  | .u8 => tag "u8" "{}" | .u16 => tag "u16" "{}" | .u32 => tag "u32" "{}" | .u64 => tag "u64" "{}"
  | .bytes => tag "bytes" "{}" | .text => tag "text" "{}"
  | .product fields => tag "product" (array reference fields)
  | .sum cases => tag "sum" (array reference cases)
  | .seq element => tag "seq" (reference element)
  | .vector element maximum => tag "vector" (object [("element", reference element), ("maximum", toString maximum)])
  | .internal value => tag "internal" (internal value)
  | .array element length => tag "array" (object [("element", reference element), ("length", toString length)])
  | .boundedBytes maximum => tag "bounded_bytes" (toString maximum)
  | .boundedText maximum => tag "bounded_text" (toString maximum)
  | .enumeration tags => tag "enumeration" (array toString tags)

private def literal (value : Literal .source) : String :=
  object [("schema", reference value.schema), ("bytes", bytes value.bytes)]
private def effect (value : Effect .source) : String := object [
  ("identity", bytes value.identity), ("payload", reference value.payload), ("result", reference value.result),
  ("use_site_effects", array reference value.useSiteEffects), ("bodies", array reference value.bodies),
  ("control_use", named Codecs.useName value.controlUse), ("external", boolean value.external)]
private def instructionFailure (value : InstructionFailure .source) : String :=
  object [("kind", named Codecs.faultName value.kind), ("value", reference value.value)]
private def clause (value : Clause .source) : String := object [
  ("effect", reference value.effect), ("function", reference value.function),
  ("resumption", reference value.resumption), ("direct", boolean value.direct)]
private def handler (value : Handler .source) : String := object [
  ("mode", named Codecs.modeName value.mode), ("input", reference value.input), ("answer", reference value.answer),
  ("return_function", reference value.returnFunction), ("clauses", array clause value.clauses),
  ("forward_function", optional reference value.forwardFunction), ("state", array reference value.state),
  ("effects", array reference value.effects)]
private def resource (value : Resource .source) : String := object [
  ("representation", reference value.representation), ("introducers", array reference value.introducers),
  ("eliminators", array reference value.eliminators)]

private def expression : Source.Expression → String
  | .variable value => tag "variable" (reference value)
  | .literal value => tag "literal" (reference value)
  | .lambda value => tag "lambda" (reference value)
  | .primitive opcode operands immediate failures => tag "primitive" (object [
      ("opcode", named Codecs.opcodeName opcode), ("operands", array reference operands),
      ("immediate", toString immediate), ("failures", array instructionFailure failures)])
private def value (value : Source.Value) : String :=
  object [("schema", reference value.schema), ("expression", expression value.expression)]
private def operation (value : Source.Operation) : String := object [
  ("effect", reference value.effect), ("capability", optional reference value.capability),
  ("payload", reference value.payload), ("bodies", array reference value.bodies),
  ("use_site_capabilities", array reference value.useSiteCapabilities)]
private def matchCase (value : VariableId × TermId) : String :=
  object [("variable", reference value.1), ("body", reference value.2)]

private def term : Source.Term → String
  | .value value => tag "value" (reference value)
  | .bind binder value next => tag "bind" (object [
      ("variable", reference binder), ("value", reference value), ("next", reference next)])
  | .conditional condition yes no => tag "conditional" (object [
      ("condition", reference condition), ("when_true", reference yes), ("when_false", reference no)])
  | .call function arguments => tag "call" (object [
      ("function", reference function), ("arguments", array reference arguments)])
  | .apply computation arguments => tag "apply" (object [
      ("computation", reference computation), ("arguments", array reference arguments)])
  | .perform value => tag "perform" (operation value)
  | .handle handler body arguments state => tag "handle" (object [
      ("handler", reference handler), ("body", reference body), ("arguments", array reference arguments), ("state", array reference state)])
  | .resumeValue resumption argument => tag "resume_value" (object [
      ("resumption", reference resumption), ("argument", reference argument)])
  | .resumeWith resumption argument handler state => tag "resume_with" (object [
      ("resumption", reference resumption), ("argument", reference argument), ("handler", reference handler), ("state", array reference state)])
  | .resumeComputation resumption computation => tag "resume_computation" (object [
      ("resumption", reference resumption), ("computation", reference computation)])
  | .protect body cleanup arguments resource loanRegion => tag "protect" (object [
      ("body", reference body), ("cleanup", reference cleanup), ("arguments", array reference arguments),
      ("resource", optional reference resource), ("loan_region", optional reference loanRegion)])
  | .withRegion region body arguments => tag "with_region" (object [
      ("region", reference region), ("body", reference body), ("arguments", array reference arguments)])
  | .dispose value => tag "dispose" (reference value)
  | .fail value => tag "fail" (reference value)
  | .yieldThen next => tag "yield_then" (reference next)
  | .matchSum value cases => tag "match_sum" (object [("value", reference value), ("cases", array matchCase cases)])
  | .unpackProduct value variables body => tag "unpack_product" (object [
      ("value", reference value), ("variables", array reference variables), ("body", reference body)])
private def function (value : Source.Function) : String := object [
  ("parameters", array reference value.parameters), ("result", reference value.result),
  ("effects", array reference value.effects), ("regions", array reference value.regions),
  ("body", optional reference value.body)]

/-- Complete canonical emitter-shaped JSON, including every defaulted field.
This encoder describes staged data; it does not execute native authoring. -/
def encode (source : Source.Module) : Bytes :=
  (object [
    ("entry", reference source.entry), ("failure", reference source.failure),
    ("schemas", array schema source.schemas), ("constants", array literal source.constants),
    ("effects", array effect source.effects), ("handlers", array handler source.handlers),
    ("region_count", toString source.regionCount), ("resources", array resource source.resources),
    ("variables", array reference source.variables), ("values", array value source.values),
    ("terms", array term source.terms), ("functions", array function source.functions)] ++ "\n").toUTF8.data.toList

end BoundaryV2.Profile.SourceEncoder
