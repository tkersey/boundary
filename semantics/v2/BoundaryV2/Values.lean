import BoundaryV2.Scalars
import BoundaryV2.Wire
import BoundaryV2.Traits

namespace BoundaryV2.Profile

namespace UTF8
def continuation (byte : UInt8) : Bool := 128 ≤ byte.toNat && byte.toNat < 192

/-- Unicode scalar values exclude the surrogate interval. -/
def scalar (value : Nat) : Bool :=
  value ≤ 0x10ffff && !(0xd800 ≤ value && value ≤ 0xdfff)

/-- Strict UTF-8: shortest forms only, no surrogates, and no values beyond
U+10FFFF. Recursion consumes a complete code point, not execution fuel. -/
def valid : Bytes → Bool
  | [] => true
  | a :: rest =>
    if a.toNat < 128 then valid rest
    else if 194 ≤ a.toNat && a.toNat ≤ 223 then
      match rest with
      | b :: tail => continuation b && valid tail
      | [] => false
    else if 224 ≤ a.toNat && a.toNat ≤ 239 then
      match rest with
      | b :: c :: tail =>
        continuation b && continuation c &&
        (a.toNat != 224 || 160 ≤ b.toNat) &&
        (a.toNat != 237 || b.toNat < 160) && valid tail
      | _ => false
    else if 240 ≤ a.toNat && a.toNat ≤ 244 then
      match rest with
      | b :: c :: d :: tail =>
        continuation b && continuation c && continuation d &&
        (a.toNat != 240 || 144 ≤ b.toNat) &&
        (a.toNat != 244 || b.toNat < 144) && valid tail
      | _ => false
    else false

def encodeScalar (value : Nat) : Option Bytes :=
  if !scalar value then none
  else if value < 128 then some [UInt8.ofNat value]
  else if value < 2048 then
    some [UInt8.ofNat (192 + value / 64), UInt8.ofNat (128 + value % 64)]
  else if value < 65536 then
    some [UInt8.ofNat (224 + value / 4096), UInt8.ofNat (128 + value / 64 % 64),
      UInt8.ofNat (128 + value % 64)]
  else
    some [UInt8.ofNat (240 + value / 262144), UInt8.ofNat (128 + value / 4096 % 64),
      UInt8.ofNat (128 + value / 64 % 64), UInt8.ofNat (128 + value % 64)]

theorem surrogate_rejected (value : Nat) (lower : 0xd800 ≤ value) (upper : value ≤ 0xdfff) :
    encodeScalar value = none := by simp [encodeScalar, scalar, lower, upper]

theorem out_of_range_rejected (value : Nat) (outside : 0x10ffff < value) :
    encodeScalar value = none := by
  have above : ¬ value ≤ 0x10ffff := by omega
  simp [encodeScalar, scalar, above]

theorem encoded_scalar_valid (value : Nat) (bytes : Bytes) (encoded : encodeScalar value = some bytes) :
    valid bytes = true := by
  unfold encodeScalar at encoded
  split at encoded
  · cases encoded
  · rename_i admitted
    have scalarBounds : value ≤ 0x10ffff ∧ ¬ (0xd800 ≤ value ∧ value ≤ 0xdfff) := by
      simpa [scalar, Bool.and_eq_true] using admitted
    split at encoded
    · cases encoded
      simp [valid]
      omega
    · split at encoded
      · cases encoded
        simp [valid, continuation, UInt8.toNat_ofNat']
        split <;> omega
      · split at encoded
        · cases encoded
          simp [valid, continuation, UInt8.toNat_ofNat']
          repeat' split
          all_goals omega
        · cases encoded
          simp [valid, continuation, UInt8.toNat_ofNat']
          repeat' split
          all_goals omega

theorem malformed_sequences_rejected :
    valid [0xc0, 0x80] = false ∧ valid [0xed, 0xa0, 0x80] = false ∧
    valid [0xf4, 0x90, 0x80, 0x80] = false ∧ valid [0xe2, 0x82] = false ∧
    valid [0x80] = false := by decide

theorem boundary_sequences_accepted :
    valid [0x00, 0x7f, 0xc2, 0x80, 0xdf, 0xbf, 0xe0, 0xa0, 0x80,
      0xed, 0x9f, 0xbf, 0xee, 0x80, 0x80, 0xef, 0xbf, 0xbf,
      0xf0, 0x90, 0x80, 0x80, 0xf4, 0x8f, 0xbf, 0xbf] = true := by decide
end UTF8

/-- Semantic values retain their schema and aggregate shape. Runtime references
are logical handles; their admission additionally depends on the heap and its
custody/borrow relation. Such handles cannot acquire an external encoding. -/
inductive Value (space : Space) where
  | scalar : SchemaId space → Int → Value space
  | blob : SchemaId space → Bytes → Value space
  | product : SchemaId space → List (Value space) → Value space
  | variant : SchemaId space → Nat → Value space → Value space
  | sequence : SchemaId space → List (Value space) → Value space
  | reference : SchemaId space → NodeId → Option CustodyToken → Value space

namespace Value
def schema : Value space → SchemaId space
  | .scalar id _ | .blob id _ | .product id _ | .variant id _ _
  | .sequence id _ | .reference id _ _ => id

/-- Structural equality has an ordinary kernel-visible definition. Lean's
stock nested BEq derivation generates an opaque executable helper. -/
def equal : (left right : Value space) → Bool
  | .scalar left a, .scalar right b => left == right && a == b
  | .blob left a, .blob right b => left == right && a == b
  | .reference left a ta, .reference right b tb => left == right && a == b && ta == tb
  | .product left a, .product right b | .sequence left a, .sequence right b =>
    left == right && a.length == b.length && (a.attach.zip b).all (fun (x, y) => equal x.val y)
  | .variant left ta a, .variant right tb b => left == right && ta == tb && equal a b
  | _, _ => false
termination_by left _ => sizeOf left
decreasing_by
  all_goals simp_wf
  all_goals first | omega | exact Nat.lt_trans (List.sizeOf_lt_of_mem x.property) (by omega)

instance : BEq (Value space) := ⟨equal⟩

def scalarValid (shape : Schema space) (value : Int) : Bool :=
  match shape with
  | .unit => value == 0
  | .boolean => value == 0 || value == 1
  | .enumeration tags => 0 ≤ value && value < 2 ^ 32 && tags.contains value.toNat
  | _ => match Scalars.integerType shape with
    | some type => decide (type.Contains value)
    | none => false

def blobMaximum : Schema space → Option Nat
  | .bytes | .text => some (wordLimit - 1)
  | .boundedBytes n | .boundedText n => some n
  | _ => none

def isText : Schema space → Bool
  | .text | .boundedText _ => true
  | _ => false

def blobValid (shape : Schema space) (bytes : Bytes) : Bool :=
  match blobMaximum shape with
  | none => false
  | some maximum => bytes.length < wordLimit && bytes.length ≤ maximum &&
      (!isText shape || UTF8.valid bytes)

def sequenceElement : Schema space → Option (SchemaId space)
  | .seq element | .vector element _ | .array element _ => some element
  | _ => none

def sequenceLengthValid (shape : Schema space) (length : Nat) : Bool :=
  length < wordLimit && match shape with
  | .seq _ => true
  | .vector _ maximum => length ≤ maximum
  | .array _ count => length == count
  | _ => false

/-- External admission checks the finite value tree, so recursive algebraic
schemas require neither a bounded unfolding of execution nor an acyclic schema
catalog. Every visited schema reference is checked. -/
def treeValid (schemas : List (Schema space)) (value : Value space) : Bool :=
  match value with
  | .scalar id number => match schemas[id.value]? with
    | some shape => scalarValid shape number
    | none => false
  | .blob id bytes => match schemas[id.value]? with
    | some shape => blobValid shape bytes
    | none => false
  | .product id fields => match schemas[id.value]? with
    | some (.product types) => types == fields.map schema &&
        fields.attach.all (fun field => treeValid schemas field.val)
    | _ => false
  | .variant id tag payload => match schemas[id.value]? with
    | some (.sum cases) => tag < wordLimit && cases[tag]? == some payload.schema && treeValid schemas payload
    | _ => false
  | .sequence id fields => match schemas[id.value]? with
    | some shape => sequenceLengthValid shape fields.length &&
        fields.attach.all (fun field => sequenceElement shape == some field.val.schema && treeValid schemas field.val)
    | none => false
  | .reference _ _ _ => false
termination_by sizeOf value
decreasing_by
  all_goals simp_wf
  all_goals first | omega | exact Nat.lt_trans (List.sizeOf_lt_of_mem field.property) (by omega)

/-- Schema-directed bytes. This function is only a serializer; treeValid
is checked independently, including bounds, variant membership, and UTF-8. -/
def encode (schemas : List (Schema space)) (value : Value space) : Bytes :=
  match value with
  | .scalar id number => match schemas[id.value]? with
    | some .unit => []
    | some .boolean => [UInt8.ofNat number.toNat]
    | some (.enumeration _) => Wire.fixed 4 number.toNat
    | some shape => match Scalars.integerType shape with
      | some type => Wire.fixed type.width.bytes (number % (2 ^ type.width.bits)).toNat
      | none => []
    | none => []
  | .blob _ bytes => Wire.natural bytes.length ++ bytes
  | .product _ fields => fields.flatMap (encode schemas)
  | .variant _ tag payload => Wire.natural tag ++ encode schemas payload
  | .sequence id fields =>
    let body := fields.flatMap (encode schemas)
    match schemas[id.value]? with
    | some (.array _ _) => body
    | _ => Wire.natural fields.length ++ body
  | .reference _ _ _ => []

def externalValid (schemas : List (Schema space)) (value : Value space) : Bool :=
  Traits.check schemas .external value.schema && treeValid schemas value

structure External (schemas : List (Schema space)) (type : SchemaId space) where
  value : Value space
  schema_eq : value.schema = type
  valid : externalValid schemas value = true

/-- Value trees are untrusted witnesses for exact external bytes. Neither a
native parser nor a producer's assertion of validity supplies this proof. -/
def checkExternal (schemas : List (Schema space)) (type : SchemaId space)
    (bytes : Bytes) (candidate : Value space) : Bool :=
  candidate.schema == type && externalValid schemas candidate && encode schemas candidate == bytes

theorem checkExternal_sound (schemas : List (Schema space)) (type : SchemaId space)
    (bytes : Bytes) (candidate : Value space) (accepted : checkExternal schemas type bytes candidate = true) :
    candidate.schema = type ∧ externalValid schemas candidate = true ∧ encode schemas candidate = bytes := by
  simpa [checkExternal, Bool.and_eq_true, and_assoc] using accepted

theorem checkExternal_complete (value : External schemas type) :
    checkExternal schemas type (encode schemas value.value) value.value = true := by
  simp [checkExternal, value.schema_eq, value.valid]

theorem reference_is_not_external (schemas : List (Schema space)) (type : SchemaId space)
    (node : NodeId) (custody : Option CustodyToken) :
    externalValid schemas (.reference type node custody) = false := by simp [externalValid, treeValid]

theorem integer_value_is_in_range (schemas : List (Schema space)) (id : SchemaId space)
    (value : Int) (shape : Schema space) (type : Scalars.IntegerType)
    (lookup : schemas[id.value]? = some shape) (integer : Scalars.integerType shape = some type)
    (admitted : externalValid schemas (.scalar id value) = true) : type.Contains value := by
  have both : Traits.check schemas .external id = true ∧
      treeValid schemas (.scalar id value) = true := by
    simpa [externalValid, schema, Bool.and_eq_true] using admitted
  have valid := both.2
  simp only [treeValid, lookup] at valid
  cases shape <;> simp_all [scalarValid, Scalars.integerType]

theorem recursive_sum_witness :
    checkExternal ([.unit, .sum [0, 1]] : List (Schema .target)) 1 [1, 1, 0]
      (.variant 1 1 (.variant 1 1 (.variant 1 0 (.scalar 0 0)))) = true := by
  simp [checkExternal, externalValid, treeValid, schema, encode, scalarValid, Wire.natural]
  decide +kernel

theorem nested_internal_rejected :
    externalValid ([.product [1], .internal (.capability 0)] : List (Schema .target))
      (.product 0 [.reference 1 0 none]) = false := by decide +kernel

theorem signed_wire_boundary :
    checkExternal ([.i8, .i64, .u64] : List (Schema .target)) 0 [128] (.scalar 0 (-128)) = true ∧
    checkExternal ([.i8, .i64, .u64] : List (Schema .target)) 1 [0, 0, 0, 0, 0, 0, 0, 128]
      (.scalar 1 (-9223372036854775808)) = true ∧
    checkExternal ([.i8, .i64, .u64] : List (Schema .target)) 2 [255, 255, 255, 255, 255, 255, 255, 255]
      (.scalar 2 18446744073709551615) = true := by
  simp only [checkExternal, externalValid, treeValid, schema, encode]
  decide +kernel

theorem unselected_internal_case_rejected :
    externalValid ([.unit, .sum [0, 2], .internal (.capability 0)] : List (Schema .target))
      (.variant 1 0 (.scalar 0 0)) = false := by decide +kernel

end Value
end BoundaryV2.Profile
