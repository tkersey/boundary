import BoundaryV2.Scalars
import BoundaryV2.Traits

namespace BoundaryV2.Profile.PrimitiveAdmission

/-- The primitive rules depend only on these declaration facts. Each language
constructs this view from its own syntax; no control graph is fabricated. -/
structure Context (space : Space) where
  schemas : List (Schema space)
  constants : List (Literal space)
  failure : SchemaId space
  resources : List (Resource space)
  constructor : Nat → Option (SchemaId space × List (SchemaId space))

structure Operation (space : Space) where
  opcode : Opcode
  resultType : SchemaId space
  immediate : Nat
  failures : List (InstructionFailure space)

def shape (program : Context space) (id : SchemaId space) : Option (Schema space) :=
  program.schemas[id.value]?

def integer (type : Schema space) : Bool := (Scalars.integerType type).isSome

def isText : Schema space → Bool
  | .text | .boundedText _ => true
  | _ => false

def isBytes : Schema space → Bool
  | .bytes | .boundedBytes _ => true
  | _ => false

def blobMaximum : Schema space → Nat
  | .boundedText bound | .boundedBytes bound => bound
  | _ => wordLimit - 1

def element : Schema space → Option (SchemaId space)
  | .seq type | .vector type _ | .array type _ => some type
  | _ => none

def collectionBound : Schema space → Option Nat
  | .vector _ bound | .array _ bound => some bound
  | _ => none

def optional (program : Context space) (type : Schema space) (item : SchemaId space) : Bool :=
  match type with
  | .sum [empty, value] => shape program empty == some .unit && value == item
  | _ => false

def conversionCanFail (program : Context space) (source target : SchemaId space) : Bool :=
  match shape program source >>= Scalars.integerType, shape program target >>= Scalars.integerType with
  | some source, some target => Scalars.conversionCanFail source target
  | _, _ => true

/-- The ordered authored-failure interface is part of instruction admission.
The input cannot omit a fault or swap the constants associated with two faults. -/
def requiredFaults (program : Context space) (opcode : Opcode) (result : SchemaId space)
    (operands : List (SchemaId space)) : List Fault :=
  match opcode with
  | .integerAdd | .integerSub | .integerMul => [.arithmeticOverflow]
  | .integerConvert => match operands with
    | [source] => if conversionCanFail program source result then [.arithmeticOverflow] else []
    | _ => [.arithmeticOverflow]
  | .integerDiv | .integerRem => [.arithmeticOverflow, .divisionByZero]
  | .sequenceSet => [.invalidIndex]
  | .variantPayload => [.invalidVariant]
  | .sequenceAppend | .sequenceConcat => match shape program result with
    | some (.vector ..) => [.capacityExceeded]
    | _ => []
  | .blobConcat => [.capacityExceeded]
  | .blobSlice => match shape program result with
    | some type => if isText type then [.capacityExceeded, .invalidUtf8] else [.capacityExceeded]
    | none => [.capacityExceeded]
  | .textScalar => [.invalidUtf8]
  | .constant | .move | .equal | .less | .booleanNot | .product | .field | .variant
  | .variantTag | .sequence | .sequenceLength | .sequenceGet | .sequencePop
  | .computation | .cellNew | .cellGet | .cellSet | .cloneResumption | .package
  | .unpack | .resourcePack | .resourceUnpack | .integerBitNot | .integerBitAnd
  | .integerBitOr | .integerBitXor | .enumTag | .blobLength | .blobCompare
  | .blobByte | .textInteger | .sequenceTake | .blobFromByte | .sequencePopLast
  | .select => []

def failuresValid (program : Context space) (instruction : Operation space)
    (operands : List (SchemaId space)) : Bool :=
  instruction.failures.map InstructionFailure.kind ==
      requiredFaults program instruction.opcode instruction.resultType operands &&
  instruction.failures.all fun failure =>
    (program.constants[failure.value.value]?).any (fun value => value.schema == program.failure)

def cloneCompatible (program : Context space) (source target : SchemaId space) : Bool :=
  match shape program source, shape program target with
  | some (.internal (.resumption owned)), some (.internal (.resumption template)) =>
    (owned.use == .linear || owned.use == .affine) && template.use == .multi &&
      { owned with use := .multi } == template
  | _, _ => false

def resourceDescriptor (program : Context space) (id : SchemaId space) : Option (Resource space) := do
  let .internal (.abstractResource resource) ← shape program id | none
  program.resources[resource.value]?

def resourceOperation (program : Context space) (opcode : Opcode)
    (result : SchemaId space) (operands : List (SchemaId space)) (immediate : Nat) : Option (Resource space) := do
    let [input] := operands | none
    let source ← shape program input
    let packed := opcode == .resourcePack
    let resource ← resourceDescriptor program (if packed then result else
      match source with | .internal (.borrowed value _) => value | _ => input)
    if immediate == 0 && resource.representation == (if packed then input else result) then
      some resource else none

def resourceInstruction (program : Context space) (owner : FunctionId space) (opcode : Opcode)
    (result : SchemaId space) (operands : List (SchemaId space)) (immediate : Nat) : Bool :=
  (resourceOperation program opcode result operands immediate).any (fun resource =>
    (if opcode == .resourcePack then resource.introducers else resource.eliminators).contains owner)

/-- Local typing checks inspect schema identities as well as shapes: two equal
integer shapes at distinct catalog positions do not make slot types interchangeable.
Declarations such as constructors and resource authority are checked at their
actual declaration references. Every baseline opcode has an explicit branch. -/
def operationType (program : Context space) (owner : FunctionId space) (instruction : Operation space)
    (operands : List (SchemaId space)) : Bool := ((do
  let type ← shape program instruction.resultType
  let result := instruction.resultType
  let immediate := instruction.immediate
  let opcode := instruction.opcode
  match opcode with
  | .constant =>
    let value ← program.constants[immediate]?
    return operands.isEmpty && value.schema == result
  | .move => return immediate == 0 && operands == [result]
  | .integerAdd | .integerSub | .integerMul | .integerDiv | .integerRem
  | .integerBitAnd | .integerBitOr | .integerBitXor | .equal | .less =>
    let [left, right] := operands | none
    let source ← shape program left
    return immediate == 0 && left == right &&
      (integer source || (opcode == .equal && source == .boolean)) &&
      (if opcode == .equal || opcode == .less then type == .boolean else result == left)
  | .integerBitNot | .integerConvert | .enumTag =>
    let [input] := operands | none
    let source ← shape program input
    return immediate == 0 && (if opcode == .enumTag then
      (match source with | .enumeration _ => true | _ => false) && type == .u32
      else integer source && integer type && (opcode != .integerBitNot || input == result))
  | .booleanNot => return immediate == 0 && type == .boolean && operands == [result]
  | .computation =>
    let (schema, fields) ← program.constructor immediate
    return schema == result && operands == fields
  | .product =>
    let .product fields := type | none
    return immediate == 0 && operands == fields
  | .field | .variantPayload =>
    let [input] := operands | none
    let source ← shape program input
    let fields ← match opcode, source with
      | .field, .product fields | .variantPayload, .sum fields => some fields
      | _, _ => none
    return fields[immediate]? == some result
  | .variant =>
    let .sum cases := type | none
    let [input] := operands | none
    return cases[immediate]? == some input
  | .variantTag =>
    let [input] := operands | none
    let .sum _ ← shape program input | none
    return immediate == 0 && type == .u64
  | .select =>
    let [condition, yes, no] := operands | none
    return immediate == 0 && shape program condition == some .boolean && yes == result && no == result
  | .sequence =>
    let item ← element type
    return immediate == 0 && operands.all (· == item) &&
      (match type with
       | .array _ length => operands.length == length
       | .vector _ maximum => operands.length ≤ maximum
       | _ => true)
  | .sequenceLength =>
    let [input] := operands | none
    let source ← shape program input
    let _ ← element source
    return immediate == 0 && (type == .u64 ||
      (type == .u32 && (collectionBound source).any (· < 2^32)))
  | .sequenceGet =>
    let [input, index] := operands | none
    let source ← shape program input
    let item ← element source
    return immediate == 0 && shape program index == some .u64 && optional program type item
  | .sequenceAppend | .sequenceConcat =>
    let item ← match type with | .seq item | .vector item _ => some item | _ => none
    return immediate == 0 && operands == [result, if opcode == .sequenceAppend then item else result]
  | .sequenceSet =>
    let item ← element type
    let [input, index, value] := operands | none
    return immediate == 0 && input == result && shape program index == some .u64 && value == item
  | .sequenceTake =>
    let _ ← match type with | .seq item | .vector item _ => some item | _ => none
    let [input, count] := operands | none
    return immediate == 0 && input == result && shape program count == some .u64
  | .sequencePop =>
    let [input] := operands | none
    let source ← shape program input
    let item ← match source with | .seq item | .vector item _ => some item | _ => none
    let .sum [empty, pair] := type | none
    return immediate == 0 && shape program empty == some .unit &&
      shape program pair == some (.product [item, input])
  | .sequencePopLast =>
    let [input] := operands | none
    let source ← shape program input
    let item ← match source with | .seq item | .vector item _ => some item | _ => none
    let .product [rest, popped] := type | none
    let popped ← shape program popped
    return immediate == 0 && rest == input && optional program popped item
  | .textScalar | .textInteger | .blobFromByte =>
    let [input] := operands | none
    let source ← shape program input
    return immediate == 0 && (match opcode with
      | .textScalar => source == .u32 && type == .text
      | .textInteger => integer source && type == .text
      | _ => source == .u8 && type == .bytes)
  | .blobLength =>
    let [input] := operands | none
    let source ← shape program input
    return immediate == 0 && (isText source || isBytes source) &&
      (type == .u64 || (type == .u32 && blobMaximum source < 2^32))
  | .blobConcat | .blobCompare =>
    let [left, right] := operands | none
    let left ← shape program left
    let right ← shape program right
    return immediate == 0 && (isText left || isBytes left) &&
      isText left == isText right && isBytes left == isBytes right &&
      (if opcode == .blobCompare then type == .i8
       else isText left == isText type && isBytes left == isBytes type)
  | .blobSlice =>
    let [input, start, count] := operands | none
    let source ← shape program input
    return immediate == 0 && (isText source || isBytes source) &&
      isText source == isText type && isBytes source == isBytes type &&
      shape program start == some .u64 && shape program count == some .u64
  | .blobByte =>
    let [input, index] := operands | none
    let source ← shape program input
    let .sum [empty, byte] := type | none
    return immediate == 0 && (isText source || isBytes source) &&
      shape program index == some .u64 && shape program empty == some .unit &&
      shape program byte == some .u8
  | .cellNew =>
    let .internal (.cell item region) := type | none
    let [scope, input] := operands | none
    return immediate == 0 && shape program scope == some (.internal (.region region)) && input == item
  | .cellGet =>
    let [input] := operands | none
    let .internal (.cell item _) ← shape program input | none
    return immediate == 0 && Traits.check program.schemas .copy item && result == item
  | .cellSet =>
    let [input, value] := operands | none
    let .internal (.cell item _) ← shape program input | none
    return immediate == 0 && Traits.check program.schemas .copy item && value == item && type == .unit
  | .package =>
    let .internal (.suspensionPackage token) := type | none
    return immediate == 0 && operands == [token]
  | .unpack =>
    let [input] := operands | none
    return immediate == 0 && shape program input == some (.internal (.suspensionPackage result))
  | .cloneResumption =>
    let [input] := operands | none
    return immediate == 0 && cloneCompatible program input result
  | .resourcePack | .resourceUnpack =>
    return resourceInstruction program owner opcode result operands immediate) : Option Bool).getD false

/-- The admitted direct-clause fragment has no authored failure and returns
from this block. Its whitelist is the baseline optimization's actual domain. -/
def directOperation (instruction : Operation space) : Bool :=
  instruction.failures.isEmpty && match instruction.opcode with
  | .constant | .move | .equal | .less | .booleanNot | .product | .field | .variant
  | .variantTag | .sequence | .sequenceLength | .sequenceGet | .sequenceAppend
  | .sequenceConcat | .sequencePop | .integerBitNot | .integerBitAnd | .integerBitOr
  | .integerBitXor | .integerConvert | .enumTag | .blobLength | .blobCompare | .blobByte
  | .textInteger | .blobFromByte | .sequenceTake | .sequencePopLast | .select
  | .cellGet | .cellSet => true
  | .integerAdd | .integerSub | .integerMul | .integerDiv | .variantPayload
  | .computation | .cellNew | .cloneResumption | .package | .unpack | .resourcePack
  | .resourceUnpack | .integerRem | .blobConcat | .blobSlice | .textScalar | .sequenceSet => false

end BoundaryV2.Profile.PrimitiveAdmission
