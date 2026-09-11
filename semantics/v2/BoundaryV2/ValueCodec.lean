import BoundaryV2.Values

namespace BoundaryV2.Profile.Value

/-- A schema-directed parser may be given a finite value-tree depth budget by
proof tooling. Running out is failure to decode, never a program outcome. The
completeness theorem below supplies a sufficient budget for every finite valid
value, including values of recursive schemas. -/
def readFields (read : SchemaId space → Bytes → Option (Value space × Bytes)) :
    List (SchemaId space) → Bytes → Option (List (Value space) × Bytes)
  | [], input => some ([], input)
  | type :: types, input => do
    let (value, tail) ← read type input
    let (values, rest) ← readFields read types tail
    return (value :: values, rest)

def readWord (width : Nat) (input : Bytes) : Option (Nat × Bytes) :=
  if width ≤ input.length then some (Wire.unsigned (input.take width), input.drop width) else none

theorem readWord_complete (width number : Nat) (rest : Bytes) (bounded : number < 256 ^ width) :
    readWord width (Wire.fixed width number ++ rest) = some (number, rest) := by
  have size := Wire.fixed_length width number
  simp only [readWord, List.length_append, size]
  rw [if_pos (by omega), List.take_left' size, List.drop_left' size, Wire.unsigned_fixed _ _ bounded]

def readScalar (shape : Schema space) (input : Bytes) : Option (Int × Bytes) :=
  match shape with
  | .unit => some (0, input)
  | .boolean => (Wire.Codec.byte.read input).map (fun (byte, rest) => (byte.toNat, rest))
  | .enumeration _ => (readWord 4 input).map (fun (number, rest) => (number, rest))
  | _ => do
    let type ← Scalars.integerType shape
    let (number, rest) ← readWord type.width.bytes input
    return ((Scalars.interpretBits type (BitVec.ofNat type.width.bits number)).value, rest)

def readTree (schemas : List (Schema space)) : Nat → SchemaId space → Bytes → Option (Value space × Bytes)
  | 0, _, _ => none
  | depth + 1, id, input => do
    let shape ← schemas[id.value]?
    match shape with
    | .bytes | .text | .boundedBytes _ | .boundedText _ =>
      let (bytes, rest) ← Wire.Codec.blob.read input
      return (.blob id bytes, rest)
    | .product types =>
      let (fields, rest) ← readFields (readTree schemas depth) types input
      return (.product id fields, rest)
    | .sum cases =>
      let (tag, tail) ← Wire.readNatural input
      let type ← cases[tag]?
      let (payload, rest) ← readTree schemas depth type tail
      return (.variant id tag payload, rest)
    | .seq type | .vector type _ =>
      let (count, tail) ← Wire.readNatural input
      let (fields, rest) ← readFields (readTree schemas depth) (List.replicate count type) tail
      return (.sequence id fields, rest)
    | .array type count =>
      let (fields, rest) ← readFields (readTree schemas depth) (List.replicate count type) input
      return (.sequence id fields, rest)
    | .internal _ => none
    | _ =>
      let (number, rest) ← readScalar shape input
      return (.scalar id number, rest)

/-- The parser is only a witness producer. Exact admission independently
checks the full finite value, its external trait, and every input byte. -/
def decodeAt (schemas : List (Schema space)) (depth : Nat) (type : SchemaId space)
    (input : Bytes) : Option (Value space) := do
  let (value, rest) ← readTree schemas depth type input
  if rest.isEmpty && checkExternal schemas type input value then some value else none

theorem decodeAt_sound (schemas : List (Schema space)) (depth : Nat) (type : SchemaId space)
    (input : Bytes) (value : Value space) (accepted : decodeAt schemas depth type input = some value) :
    value.schema = type ∧ externalValid schemas value = true ∧ encode schemas value = input := by
  unfold decodeAt at accepted
  cases read : readTree schemas depth type input with
  | none => simp [read] at accepted
  | some parsed =>
    rcases parsed with ⟨decoded, rest⟩
    rw [read] at accepted
    dsimp only [Bind.bind, Option.bind] at accepted
    split at accepted
    · rename_i checked
      cases accepted
      have both : rest.isEmpty = true ∧ checkExternal schemas type input value = true := by
        simpa only [Bool.and_eq_true] using checked
      exact checkExternal_sound _ _ _ _ both.2
    · cases accepted

private theorem fields_complete (schemas : List (Schema space)) (depth : Nat)
    (fields : List (Value space))
    (children : ∀ field ∈ fields, ∀ rest,
      readTree schemas depth field.schema (encode schemas field ++ rest) = some (field, rest)) :
    ∀ rest, readFields (readTree schemas depth) (fields.map schema)
      (fields.flatMap (encode schemas) ++ rest) = some (fields, rest) := by
  induction fields with
  | nil => intro rest; rfl
  | cons head tail ih =>
    intro rest
    have first := children head (by simp)
    have later := ih (fun field member => children field (by simp [member])) rest
    simp [List.append_assoc, readFields, first, later]

private theorem integer_complete (type : Scalars.IntegerType) (number : Int) (rest : Bytes)
    (valid : type.Contains number) :
    ((readWord type.width.bytes (Wire.fixed type.width.bytes
        (number % 2 ^ type.width.bits).toNat ++ rest)).bind fun (bits, tail) =>
      some ((Scalars.interpretBits type (BitVec.ofNat type.width.bits bits)).value, tail)) =
      some (number, rest) := by
  let integer : Scalars.Integer type := ⟨number, valid⟩
  have representation : (number % 2 ^ type.width.bits).toNat = (Scalars.bits integer).toNat := by
    simp [Scalars.bits, integer]
  have width : 256 ^ type.width.bytes = 2 ^ type.width.bits := by
    cases type with
    | signed width | unsigned width => cases width <;> decide
  have bound : (Scalars.bits integer).toNat < 256 ^ type.width.bytes := by
    rw [width]
    exact (Scalars.bits integer).isLt
  rw [representation, readWord_complete _ _ _ bound]
  simp only [Option.bind_some, BitVec.ofNat_toNat]
  simp [Scalars.interpret_bits_roundtrip, integer]

theorem scalar_complete (schemas : List (Schema space)) (id : SchemaId space)
    (shape : Schema space) (number : Int) (rest : Bytes)
    (lookup : schemas[id.value]? = some shape) (valid : scalarValid shape number = true) :
    readScalar shape (encode schemas (.scalar id number) ++ rest) = some (number, rest) := by
  cases shape <;> simp_all [scalarValid, Scalars.integerType, encode, readScalar]
  case boolean =>
    rcases valid with rfl | rfl <;> simp [Wire.Codec.byte]
  case enumeration tags =>
    rw [readWord_complete _ _ _ (by omega)]
    exact ⟨_, rfl, Int.toNat_of_nonneg valid.1.1⟩
  all_goals exact integer_complete _ _ _ valid

/-- Executable syntax depth. Unlike Lean's proof-oriented SizeOf instance,
this is available to native certificate producers as ordinary code. -/
def height : Value space → Nat
  | .scalar .. | .blob .. | .reference .. => 1
  | .variant _ _ payload => height payload + 1
  | .product _ fields | .sequence _ fields => (fields.map height).foldr max 0 + 1

private theorem maximum_member (values : List Nat) (value : Nat) (member : value ∈ values) :
    value ≤ values.foldr max 0 := by
  induction values with
  | nil => simp at member
  | cons head tail ih =>
    simp only [List.mem_cons] at member
    rcases member with rfl | later
    · exact Nat.le_max_left _ _
    · exact Nat.le_trans (ih later) (Nat.le_max_right _ _)

/-- Every admitted finite tree parses with its exact following field. The
budget is only an upper bound on syntax depth; arbitrary recursive execution
is unrelated to this parser. -/
theorem readTree_complete (schemas : List (Schema space)) (value : Value space)
    (valid : treeValid schemas value = true) (depth : Nat) (enough : height value ≤ depth)
    (rest : Bytes) :
    readTree schemas depth value.schema (encode schemas value ++ rest) = some (value, rest) := by
  induction depth generalizing value rest with
  | zero => cases value <;> simp_all [height]
  | succ depth ih =>
    cases value with
    | reference id node token => simp [treeValid] at valid
    | scalar id number =>
      cases lookup : schemas[id.value]? with
      | none => simp [treeValid, lookup] at valid
      | some shape =>
        have admitted : scalarValid shape number = true := by simpa [treeValid, lookup] using valid
        have parsed := scalar_complete schemas id shape number rest lookup admitted
        cases shape <;> simp_all [readTree, schema, scalarValid, Scalars.integerType]
    | blob id bytes =>
      cases lookup : schemas[id.value]? with
      | none => simp [treeValid, lookup] at valid
      | some shape =>
        have admitted : blobValid shape bytes = true := by simpa [treeValid, lookup] using valid
        have bounded : bytes.length < wordLimit := by
          cases shape <;> simp_all [blobValid, blobMaximum]
        have parsed := Wire.Codec.blob.readComplete bytes rest (by
          simpa [Wire.Codec.blob, Wire.Codec.sizedBytes, Wire.Codec.iso,
            Wire.Codec.dependent, Wire.Codec.natural, Wire.Codec.fixedBytes] using bounded)
        change Wire.Codec.blob.read ((Wire.natural bytes.length ++ bytes) ++ rest) = some (bytes, rest) at parsed
        cases shape <;> simp_all [blobValid, blobMaximum, readTree, schema, encode]
    | product id fields =>
      cases lookup : schemas[id.value]? with
      | none => simp [treeValid, lookup] at valid
      | some shape =>
        cases shape <;> simp only [treeValid, lookup, Bool.false_eq_true] at valid
        rename_i types
        have admitted : types = fields.map schema ∧ ∀ field ∈ fields, treeValid schemas field = true := by
          simpa [List.all_eq_true] using valid
        have parsed := fields_complete schemas depth fields (fun field member suffix =>
          ih field (admitted.2 field member) (by
            have smaller := maximum_member (fields.map height) (height field) (List.mem_map.mpr ⟨field, member, rfl⟩)
            simp only [height] at enough
            omega) suffix) rest
        simp [readTree, schema, lookup, admitted.1, encode, parsed]
    | variant id tag payload =>
      cases lookup : schemas[id.value]? with
      | none => simp [treeValid, lookup] at valid
      | some shape =>
        cases shape <;> simp only [treeValid, lookup, Bool.false_eq_true] at valid
        rename_i types
        have admitted : (tag < wordLimit ∧ types[tag]? = some payload.schema) ∧ treeValid schemas payload = true := by
          simpa [Bool.and_eq_true] using valid
        have child := ih payload admitted.2 (by simp only [height] at enough; omega) rest
        change readTree schemas (depth + 1) id (encode schemas (.variant id tag payload) ++ rest) = _
        simp [readTree, lookup, encode, List.append_assoc,
          Wire.readNatural_complete _ _ admitted.1.1, admitted.1.2, child]
    | sequence id fields =>
      cases lookup : schemas[id.value]? with
      | none => simp [treeValid, lookup] at valid
      | some shape =>
        have admitted : sequenceLengthValid shape fields.length = true ∧
            ∀ field ∈ fields, sequenceElement shape = some field.schema ∧ treeValid schemas field = true := by
          simpa [treeValid, lookup, Bool.and_eq_true, List.all_eq_true] using valid
        have parsed := fields_complete schemas depth fields (fun field member suffix =>
          ih field (admitted.2 field member).2 (by
            have smaller := maximum_member (fields.map height) (height field) (List.mem_map.mpr ⟨field, member, rfl⟩)
            simp only [height] at enough
            omega) suffix) rest
        cases shape <;> simp only [sequenceLengthValid, Bool.and_eq_true, Bool.false_eq_true, and_false] at admitted
        all_goals
          rcases admitted with ⟨lengths, children⟩
          have same : fields.map schema = List.replicate fields.length (by assumption) := by
            apply List.ext_getElem
            · simp
            · intro index left right
              simp only [List.getElem_map, List.getElem_replicate]
              have one := (children _ (List.getElem_mem (by simpa using left))).1
              simpa [sequenceElement] using one.symm
          rw [same] at parsed
          simp_all [readTree, schema, encode, List.append_assoc, Wire.readNatural_complete]

/-- No two finite admitted trees of the same schema can consume different
prefixes of one byte stream. Zero-width products and arrays are included. -/
theorem encoding_prefix_unique (schemas : List (Schema space)) (left right : Value space)
    (leftValid : treeValid schemas left = true) (rightValid : treeValid schemas right = true)
    (sameSchema : left.schema = right.schema) (leftRest rightRest : Bytes)
    (sameBytes : encode schemas left ++ leftRest = encode schemas right ++ rightRest) :
    left = right ∧ leftRest = rightRest := by
  let depth := max (height left) (height right)
  have first := readTree_complete schemas left leftValid depth (Nat.le_max_left _ _) leftRest
  have second := readTree_complete schemas right rightValid depth (Nat.le_max_right _ _) rightRest
  rw [sameSchema, sameBytes] at first
  exact Prod.mk.inj (Option.some.inj (first.symm.trans second))

theorem encode_injective (schemas : List (Schema space)) (left right : Value space)
    (leftValid : treeValid schemas left = true) (rightValid : treeValid schemas right = true)
    (sameSchema : left.schema = right.schema) (sameBytes : encode schemas left = encode schemas right) :
    left = right :=
  (encoding_prefix_unique schemas left right leftValid rightValid sameSchema [] []
    (by simpa using sameBytes)).1

/-- A native witness cannot choose a different meaning for the same admitted
bytes, even by changing the value's aggregate shape or signed interpretation. -/
theorem checked_candidates_unique (schemas : List (Schema space)) (type : SchemaId space)
    (input : Bytes) (left right : Value space)
    (leftAccepted : checkExternal schemas type input left = true)
    (rightAccepted : checkExternal schemas type input right = true) : left = right := by
  have l := checkExternal_sound _ _ _ _ leftAccepted
  have r := checkExternal_sound _ _ _ _ rightAccepted
  have lv : treeValid schemas left = true := by
    have both : Traits.check schemas .external left.schema = true ∧ treeValid schemas left = true := by
      simpa only [externalValid, Bool.and_eq_true] using l.2.1
    exact both.2
  have rv : treeValid schemas right = true := by
    have both : Traits.check schemas .external right.schema = true ∧ treeValid schemas right = true := by
      simpa only [externalValid, Bool.and_eq_true] using r.2.1
    exact both.2
  exact encode_injective schemas left right lv rv (l.1.trans r.1.symm) (l.2.2.trans r.2.2.symm)

theorem decodeAt_complete (value : External schemas type) (depth : Nat) (enough : height value.value ≤ depth) :
    decodeAt schemas depth type (encode schemas value.value) = some value.value := by
  have both : Traits.check schemas .external value.value.schema = true ∧ treeValid schemas value.value = true := by
    simpa only [externalValid, Bool.and_eq_true] using value.valid
  have parsed := readTree_complete schemas value.value both.2 depth enough []
  simp only [List.append_nil, value.schema_eq] at parsed
  simp [decodeAt, parsed, checkExternal_complete value]

theorem every_external_value_has_a_decoding (value : External schemas type) :
    ∃ depth, decodeAt schemas depth type (encode schemas value.value) = some value.value :=
  ⟨height value.value, decodeAt_complete value _ (Nat.le_refl _)⟩

theorem recursive_value_decodes :
    let value : Value .target := .variant 1 1 (.variant 1 1 (.variant 1 0 (.scalar 0 0)))
    decodeAt [.unit, .sum [0, 1]] (height value) 1 [1, 1, 0] = some value := by
  let value : External ([.unit, .sum [0, 1]] : List (Schema .target)) 1 :=
    ⟨.variant 1 1 (.variant 1 1 (.variant 1 0 (.scalar 0 0))), rfl, by decide +kernel⟩
  have result := decodeAt_complete value _ (Nat.le_refl _)
  have bytes : encode [.unit, .sum [0, 1]] value.value = [1, 1, 0] := by
    simp [value, encode, Wire.natural]
    decide +kernel
  rw [bytes] at result
  exact result

theorem short_budget_is_no_decoding :
    decodeAt ([.unit, .sum [0, 1]] : List (Schema .target)) 2 1 [1, 1, 0] = none := by decide +kernel

theorem signed_boundary_decodes :
    let value : Value .target := .scalar 0 (-128)
    decodeAt [.i8] (height value) 0 [128] = some value := by
  let value : External ([.i8] : List (Schema .target)) 0 := ⟨.scalar 0 (-128), rfl, by decide +kernel⟩
  have result := decodeAt_complete value _ (Nat.le_refl _)
  have bytes : encode [.i8] value.value = [128] := by
    simp [value, encode, Scalars.integerType]
    decide +kernel
  rw [bytes] at result
  exact result

theorem unsigned_boundary_decodes :
    let value : Value .target := .scalar 0 18446744073709551615
    decodeAt [.u64] (height value) 0 [255, 255, 255, 255, 255, 255, 255, 255] = some value := by
  let value : External ([.u64] : List (Schema .target)) 0 :=
    ⟨.scalar 0 18446744073709551615, rfl, by decide +kernel⟩
  have result := decodeAt_complete value _ (Nat.le_refl _)
  have bytes : encode [.u64] value.value = [255, 255, 255, 255, 255, 255, 255, 255] := by
    simp [value, encode, Scalars.integerType]
    decide +kernel
  rw [bytes] at result
  exact result

theorem malformed_external_bytes_rejected :
    let schemas : List (Schema .target) := [.boolean, .text, .vector 0 2, .enumeration [2, 9]]
    decodeAt schemas 3 0 [2] = none ∧
    decodeAt schemas 3 1 [2, 192, 128] = none ∧
    decodeAt schemas 3 2 [3, 0, 0, 0] = none ∧
    decodeAt schemas 3 2 [128, 0] = none ∧
    decodeAt schemas 3 3 [3, 0, 0, 0] = none ∧
    decodeAt schemas 3 3 [2, 0, 0] = none ∧
    decodeAt schemas 3 3 [2, 0, 0, 0, 0] = none := by decide +kernel

end BoundaryV2.Profile.Value
