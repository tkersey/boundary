import BoundaryV2.Values

namespace BoundaryV2.Profile.Primitives

/-- Malformed proof states are distinct from authored instruction faults. -/
inductive Invalid where
  | operands | schema | value | immediate
  deriving DecidableEq, Repr

/-- These instructions require the machine's heap/custody transition. Returning
an action is not executing it or asserting that its admission checks passed. -/
inductive GraphOperation where
  | computation | cellNew | cellGet | cellSet | cloneResumption
  | package | unpack | resourcePack | resourceUnpack
  deriving DecidableEq, Repr

inductive Result (space : Space) where
  | value : Value space → Result space
  | fault : Fault → Result space
  | graph : GraphOperation → Result space

abbrev Evaluation (space : Space) := Except Invalid (Result space)

private def require (condition : Bool) (reason : Invalid) : Except Invalid Unit :=
  if condition then .ok () else .error reason

private def lookup (items : List α) (index : Nat) : Except Invalid α :=
  match items[index]? with | some value => .ok value | none => .error .schema

private def number : Value space → Except Invalid Int
  | .scalar _ n => .ok n | _ => .error .value

private def index (value : Value space) : Except Invalid Nat := do
  let n ← number value
  require (0 ≤ n && n < wordLimit) .value
  return n.toNat

private def blobBytes : Value space → Except Invalid Bytes
  | .blob _ bytes => .ok bytes | _ => .error .value

private def elements : Value space → Except Invalid (List (Value space))
  | .sequence _ fields => .ok fields | _ => .error .value

private def integer (type : Scalars.IntegerType) (value : Value space) : Except Invalid (Scalars.Integer type) := do
  let n ← number value
  if valid : type.Contains n then return ⟨n, valid⟩ else throw .value

private def integerType (schemas : List (Schema space)) (value : Value space) : Except Invalid Scalars.IntegerType := do
  let shape ← lookup schemas value.schema.value
  match Scalars.integerType shape with | some type => return type | none => throw .schema

private def integerResult {kind : Scalars.IntegerType} (type : SchemaId space) : Except Fault (Scalars.Integer kind) → Result space
  | .ok value => .value (.scalar type value.value)
  | .error fault => .fault fault

def arithmetic (schemas : List (Schema space)) (operation : Scalars.Arithmetic)
    (resultType : SchemaId space) (operands : List (Value space)) : Evaluation space := do
  match operands with
  | [left, right] =>
    require (left.schema == right.schema && left.schema == resultType) .schema
    let type ← integerType schemas left
    let a ← integer type left
    let b ← integer type right
    return integerResult resultType (Scalars.arithmetic operation a b)
  | _ => throw .operands

def bitwise (schemas : List (Schema space)) (operation : Scalars.Bitwise)
    (resultType : SchemaId space) (operands : List (Value space)) : Evaluation space := do
  match operands with
  | [left, right] =>
    require (left.schema == right.schema && left.schema == resultType) .schema
    let type ← integerType schemas left
    let a ← integer type left
    let b ← integer type right
    return .value (.scalar resultType (Scalars.bitwise operation a b).value)
  | _ => throw .operands

def compare (schemas : List (Schema space)) (less : Bool)
    (resultType : SchemaId space) (operands : List (Value space)) : Evaluation space := do
  match operands with
  | [left, right] =>
    require (left.schema == right.schema) .schema
    require ((← lookup schemas resultType.value) == .boolean) .schema
    let shape ← lookup schemas left.schema.value
    let a ← number left
    let b ← number right
    require (Value.scalarValid shape a && Value.scalarValid shape b) .value
    require ((Scalars.integerType shape).isSome || (!less && shape == .boolean)) .schema
    return .value (.scalar resultType (if (if less then a < b else a == b) then 1 else 0))
  | _ => throw .operands

def convert (schemas : List (Schema space))
    (resultType : SchemaId space) (operands : List (Value space)) : Evaluation space := do
  match operands with
  | [source] =>
    let type ← integerType schemas source
    let a ← integer type source
    let shape ← lookup schemas resultType.value
    match Scalars.integerType shape with
    | some target => return integerResult resultType (Scalars.convert target a)
    | none => throw .schema
  | _ => throw .operands

private def naturalResult (schemas : List (Schema space)) (type : SchemaId space) (n : Nat) : Evaluation space := do
  let shape ← lookup schemas type.value
  require ((shape == .u64 || shape == .u32) && Value.scalarValid shape n) .schema
  return .value (.scalar type n)

private def optionalValue (schemas : List (Schema space)) (type : SchemaId space)
    (item : Option (Value space)) : Except Invalid (Value space) := do
  match ← lookup schemas type.value with
  | .sum [empty, element] =>
    require ((← lookup schemas empty.value) == .unit) .schema
    match item with
    | none => return .variant type 0 (.scalar empty 0)
    | some value =>
      require (value.schema == element) .schema
      return .variant type 1 value
  | _ => throw .schema

/-- Capacity is an authored failure only for an operation whose contract has
that role. Fixed arrays are checked by formation, never resized here. -/
def collection (schemas : List (Schema space)) (type : SchemaId space)
    (fields : List (Value space)) : Evaluation space := do
  let shape ← lookup schemas type.value
  match shape with
  | .seq element =>
    require (fields.all (fun field => field.schema == element)) .schema
    require (fields.length < wordLimit) .value
    return .value (.sequence type fields)
  | .vector element maximum =>
    require (fields.all (fun field => field.schema == element)) .schema
    if fields.length > maximum then return .fault .capacityExceeded
    require (fields.length < wordLimit) .value
    return .value (.sequence type fields)
  | .array element count =>
    require (fields.all (fun field => field.schema == element) && fields.length == count) .schema
    return .value (.sequence type fields)
  | _ => throw .schema

def blob (schemas : List (Schema space)) (type : SchemaId space) (bytes : Bytes) : Evaluation space := do
  let shape ← lookup schemas type.value
  match Value.blobMaximum shape with
  | none => throw .schema
  | some maximum =>
    if bytes.length > maximum then return .fault .capacityExceeded
    require (bytes.length < wordLimit) .value
    if Value.isText shape && !UTF8.valid bytes then return .fault .invalidUtf8
    return .value (.blob type bytes)

/-- Bounds and capacity precede UTF-8 validation, including slices cutting a
code point. An invalid offset is capacity-exceeded in the baseline contract. -/
def sliceBlob (schemas : List (Schema space)) (type : SchemaId space)
    (bytes : Bytes) (start stop : Nat) : Evaluation space :=
  if start > stop || stop > bytes.length then .ok (.fault .capacityExceeded)
  else blob schemas type ((bytes.drop start).take (stop - start))

private def byteOrder : Bytes → Bytes → Int
  | [], [] => 0
  | [], _ :: _ => -1
  | _ :: _, [] => 1
  | a :: as, b :: bs =>
    if a.toNat < b.toNat then -1 else if b.toNat < a.toNat then 1 else byteOrder as bs

private def graphArity (operation : GraphOperation) (operands : List (Value space)) : Evaluation space :=
  let valid := match operation with
    | .computation => true
    | .cellNew | .cellSet => operands.length == 2
    | .cellGet | .cloneResumption | .package | .unpack | .resourcePack | .resourceUnpack => operands.length == 1
  if valid then .ok (.graph operation) else .error .operands

/-- Complete baseline primitive dispatch shared by the independent source and
target control languages. Stateful instructions produce explicit graph actions;
the enclosing machine must prove and apply their heap and ownership rules. -/
def evaluate (schemas : List (Schema space)) (constants : List (Value space))
    (opcode : Opcode) (resultType : SchemaId space) (immediate : Nat)
    (operands : List (Value space)) : Evaluation space := do
  match opcode with
  | .constant =>
    require operands.isEmpty .operands
    let value ← lookup constants immediate
    require (value.schema == resultType) .schema
    return .value value
  | .move => match operands with
    | [value] => require (value.schema == resultType) .schema; return .value value
    | _ => throw .operands
  | .integerAdd => arithmetic schemas .add resultType operands
  | .integerSub => arithmetic schemas .sub resultType operands
  | .integerMul => arithmetic schemas .mul resultType operands
  | .integerDiv => arithmetic schemas .div resultType operands
  | .integerRem => arithmetic schemas .rem resultType operands
  | .integerBitAnd => bitwise schemas .and resultType operands
  | .integerBitOr => bitwise schemas .or resultType operands
  | .integerBitXor => bitwise schemas .xor resultType operands
  | .integerBitNot => match operands with
    | [value] =>
      require (value.schema == resultType) .schema
      let type ← integerType schemas value
      let n ← integer type value
      return .value (.scalar resultType (Scalars.complement n).value)
    | _ => throw .operands
  | .integerConvert => convert schemas resultType operands
  | .equal => compare schemas false resultType operands
  | .less => compare schemas true resultType operands
  | .booleanNot => match operands with
    | [.scalar type value] =>
      require (type == resultType && (← lookup schemas type.value) == .boolean) .schema
      require (value == 0 || value == 1) .value
      return .value (.scalar type (1 - value))
    | _ => throw .operands
  | .product =>
    match ← lookup schemas resultType.value with
    | .product fields =>
      require (fields == operands.map Value.schema) .schema
      return .value (.product resultType operands)
    | _ => throw .schema
  | .field => match operands with
    | [.product _ fields] =>
      let value ← lookup fields immediate
      require (value.schema == resultType) .schema
      return .value value
    | _ => throw .operands
  | .variant => match operands with
    | [payload] => match ← lookup schemas resultType.value with
      | .sum cases =>
        require (cases[immediate]? == some payload.schema) .schema
        return .value (.variant resultType immediate payload)
      | _ => throw .schema
    | _ => throw .operands
  | .variantTag => match operands with
    | [.variant _ tag _] => naturalResult schemas resultType tag
    | _ => throw .operands
  | .variantPayload => match operands with
    | [.variant _ tag payload] =>
      if tag != immediate then return .fault .invalidVariant
      require (payload.schema == resultType) .schema
      return .value payload
    | _ => throw .operands
  | .sequence => collection schemas resultType operands
  | .sequenceLength => match operands with
    | [.sequence _ fields] => naturalResult schemas resultType fields.length
    | _ => throw .operands
  | .sequenceGet => match operands with
    | [.sequence _ fields, selected] =>
      return .value (← optionalValue schemas resultType fields[← index selected]?)
    | _ => throw .operands
  | .sequenceAppend => match operands with
    | [.sequence type fields, value] =>
      require (type == resultType) .schema
      collection schemas resultType (fields ++ [value])
    | _ => throw .operands
  | .sequenceConcat => match operands with
    | [.sequence left a, .sequence right b] =>
      require (left == right && left == resultType) .schema
      collection schemas resultType (a ++ b)
    | _ => throw .operands
  | .sequencePop => match operands with
    | [.sequence type fields] =>
      let .sum [_, pairType] ← lookup schemas resultType.value | throw .schema
      let payload ← match fields with
        | [] => pure none
        | head :: tail =>
          require ((← lookup schemas pairType.value) == .product [head.schema, type]) .schema
          pure (some (.product pairType [head, .sequence type tail]))
      return .value (← optionalValue schemas resultType payload)
    | _ => throw .operands
  | .sequenceSet => match operands with
    | [.sequence type fields, selected, replacement] =>
      require (type == resultType) .schema
      let n ← index selected
      if fields.length ≤ n then return .fault .invalidIndex
      collection schemas resultType (fields.set n replacement)
    | _ => throw .operands
  | .sequenceTake => match operands with
    | [.sequence type fields, selected] =>
      require (type == resultType) .schema
      collection schemas resultType (fields.take (← index selected))
    | _ => throw .operands
  | .sequencePopLast => match operands with
    | [.sequence type fields] =>
      let .product [remainingType, optionalType] ← lookup schemas resultType.value | throw .schema
      require (remainingType == type) .schema
      let last ← optionalValue schemas optionalType fields.getLast?
      return .value (.product resultType [.sequence type fields.dropLast, last])
    | _ => throw .operands
  | .select => match operands with
    | [.scalar conditionType condition, left, right] =>
      require ((← lookup schemas conditionType.value) == .boolean && left.schema == right.schema && left.schema == resultType) .schema
      require (condition == 0 || condition == 1) .value
      return .value (if condition == 1 then left else right)
    | _ => throw .operands
  | .enumTag => match operands with
    | [.scalar type n] =>
      let .enumeration tags ← lookup schemas type.value | throw .schema
      require (0 ≤ n && n < 2 ^ 32 && tags.contains n.toNat) .value
      require ((← lookup schemas resultType.value) == .u32) .schema
      return .value (.scalar resultType n)
    | _ => throw .operands
  | .blobLength => match operands with
    | [.blob _ bytes] => naturalResult schemas resultType bytes.length
    | _ => throw .operands
  | .blobConcat => match operands with
    | [left, right] => blob schemas resultType ((← blobBytes left) ++ (← blobBytes right))
    | _ => throw .operands
  | .blobSlice => match operands with
    | [.blob _ bytes, start, stop] => sliceBlob schemas resultType bytes (← index start) (← index stop)
    | _ => throw .operands
  | .blobCompare => match operands with
    | [left, right] =>
      require ((← lookup schemas resultType.value) == .i8) .schema
      return .value (.scalar resultType (byteOrder (← blobBytes left) (← blobBytes right)))
    | _ => throw .operands
  | .blobByte => match operands with
    | [.blob _ bytes, selected] =>
      let .sum [_, element] ← lookup schemas resultType.value | throw .schema
      require ((← lookup schemas element.value) == .u8) .schema
      let payload := bytes[← index selected]?
      return .value (← optionalValue schemas resultType (payload.map (fun byte => .scalar element byte.toNat)))
    | _ => throw .operands
  | .textScalar => match operands with
    | [value] =>
      require ((← lookup schemas value.schema.value) == .u32 && (← lookup schemas resultType.value) == .text) .schema
      let n ← index value
      match UTF8.encodeScalar n with
      | none => return .fault .invalidUtf8
      | some bytes => return .value (.blob resultType bytes)
    | _ => throw .operands
  | .textInteger => match operands with
    | [value] =>
      require ((← lookup schemas resultType.value) == .text) .schema
      let type ← integerType schemas value
      let n ← integer type value
      return .value (.blob resultType (toString n.value).toUTF8.toList)
    | _ => throw .operands
  | .blobFromByte => match operands with
    | [value] =>
      require ((← lookup schemas value.schema.value) == .u8 && (← lookup schemas resultType.value) == .bytes) .schema
      let n ← number value
      require (0 ≤ n && n < 256) .value
      return .value (.blob resultType [UInt8.ofNat n.toNat])
    | _ => throw .operands
  | .computation => graphArity .computation operands
  | .cellNew => graphArity .cellNew operands
  | .cellGet => graphArity .cellGet operands
  | .cellSet => graphArity .cellSet operands
  | .cloneResumption => graphArity .cloneResumption operands
  | .package => graphArity .package operands
  | .unpack => graphArity .unpack operands
  | .resourcePack => graphArity .resourcePack operands
  | .resourceUnpack => graphArity .resourceUnpack operands

theorem slice_bounds_precede_text_validation (schemas : List (Schema space)) (type : SchemaId space)
    (bytes : Bytes) (start stop : Nat) (bad : stop < start ∨ bytes.length < stop) :
    sliceBlob schemas type bytes start stop = .ok (.fault .capacityExceeded) := by
  rcases bad with bad | bad <;> simp [sliceBlob, bad]

theorem equal_signed_boundary_faults :
    arithmetic ([.i8] : List (Schema .target)) .div 0 [.scalar 0 (-128), .scalar 0 (-1)] = .ok (.fault .arithmeticOverflow) ∧
    arithmetic ([.i8] : List (Schema .target)) .rem 0 [.scalar 0 (-128), .scalar 0 (-1)] = .ok (.fault .arithmeticOverflow) := by
  constructor <;> rfl

theorem clipped_multibyte_text_fault :
    sliceBlob ([.text, .boundedText 0] : List (Schema .target)) 0 [0xc2, 0xa2] 0 1 = .ok (.fault .invalidUtf8) ∧
    sliceBlob ([.text, .boundedText 0] : List (Schema .target)) 1 [0xc2, 0xa2] 0 1 = .ok (.fault .capacityExceeded) := by
  constructor <;> rfl

end BoundaryV2.Profile.Primitives

namespace BoundaryV2.Profile.Primitives

def ReferencesSatisfy (accept : SchemaId space → NodeId → Option CustodyToken → Prop) : Value space → Prop
  | .reference schema node token => accept schema node token
  | .product _ fields | .sequence _ fields => ∀ child ∈ fields, ReferencesSatisfy accept child
  | .variant _ _ payload => ReferencesSatisfy accept payload
  | .scalar .. | .blob .. => True

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β)
    (result : β) : value.bind next = .ok result ↔
      ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem lookup_member (items : List α) (index : Nat) (value : α)
    (accepted : lookup items index = .ok value) : value ∈ items := by
  unfold lookup at accepted
  split at accepted <;> try contradiction
  cases accepted
  exact List.mem_of_getElem? (by assumption)

private theorem integerResult_references (accept : SchemaId space → NodeId → Option CustodyToken → Prop)
    (type : SchemaId space) (response : Except Fault (Scalars.Integer kind)) (result : Value space)
    (accepted : integerResult type response = .value result) : ReferencesSatisfy accept result := by
  cases response with
  | error fault => contradiction
  | ok value => cases accepted; simp [ReferencesSatisfy]

private theorem arithmetic_references (accept : SchemaId space → NodeId → Option CustodyToken → Prop)
    (schemas : List (Schema space)) (operation : Scalars.Arithmetic) (type : SchemaId space)
    (operands : List (Value space)) (result : Value space)
    (accepted : arithmetic schemas operation type operands = .ok (.value result)) : ReferencesSatisfy accept result := by
  simp only [arithmetic, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, (integerResult_references accept)]

private theorem bitwise_references (accept : SchemaId space → NodeId → Option CustodyToken → Prop)
    (schemas : List (Schema space)) (operation : Scalars.Bitwise) (type : SchemaId space)
    (operands : List (Value space)) (result : Value space)
    (accepted : bitwise schemas operation type operands = .ok (.value result)) : ReferencesSatisfy accept result := by
  simp only [bitwise, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, ReferencesSatisfy]

private theorem compare_references (accept : SchemaId space → NodeId → Option CustodyToken → Prop)
    (schemas : List (Schema space)) (less : Bool) (type : SchemaId space)
    (operands : List (Value space)) (result : Value space)
    (accepted : compare schemas less type operands = .ok (.value result)) : ReferencesSatisfy accept result := by
  simp only [compare, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, ReferencesSatisfy]

private theorem convert_references (accept : SchemaId space → NodeId → Option CustodyToken → Prop)
    (schemas : List (Schema space)) (type : SchemaId space)
    (operands : List (Value space)) (result : Value space)
    (accepted : convert schemas type operands = .ok (.value result)) : ReferencesSatisfy accept result := by
  simp only [convert, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, (integerResult_references accept)]

private theorem naturalResult_references (accept : SchemaId space → NodeId → Option CustodyToken → Prop)
    (schemas : List (Schema space)) (type : SchemaId space) (number : Nat) (result : Value space)
    (accepted : naturalResult schemas type number = .ok (.value result)) : ReferencesSatisfy accept result := by
  simp only [naturalResult, bind, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, ReferencesSatisfy]

private theorem optionalValue_references (accept : SchemaId space → NodeId → Option CustodyToken → Prop)
    (schemas : List (Schema space)) (type : SchemaId space) (item : Option (Value space)) (result : Value space)
    (accepted : optionalValue schemas type item = .ok result)
    (valid : ∀ value ∈ item.toList, ReferencesSatisfy accept value) : ReferencesSatisfy accept result := by
  simp only [optionalValue, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  cases item <;> simp only [Option.toList_some, Option.toList_none, List.mem_singleton, forall_eq] at valid
  all_goals grind (gen := 32) only [except_bind_ok, ReferencesSatisfy]


private theorem collection_references (accept : SchemaId space → NodeId → Option CustodyToken → Prop)
    (schemas : List (Schema space)) (type : SchemaId space) (fields : List (Value space)) (result : Value space)
    (accepted : collection schemas type fields = .ok (.value result))
    (valid : ∀ value ∈ fields, ReferencesSatisfy accept value) : ReferencesSatisfy accept result := by
  simp only [collection, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, ReferencesSatisfy]

private theorem blob_references (accept : SchemaId space → NodeId → Option CustodyToken → Prop)
    (schemas : List (Schema space)) (type : SchemaId space) (bytes : Bytes) (result : Value space)
    (accepted : blob schemas type bytes = .ok (.value result)) : ReferencesSatisfy accept result := by
  simp only [blob, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, ReferencesSatisfy]

private theorem sliceBlob_references (accept : SchemaId space → NodeId → Option CustodyToken → Prop)
    (schemas : List (Schema space)) (type : SchemaId space) (bytes : Bytes) (start stop : Nat) (result : Value space)
    (accepted : sliceBlob schemas type bytes start stop = .ok (.value result)) : ReferencesSatisfy accept result := by
  unfold sliceBlob at accepted
  split at accepted
  · cases accepted
  · exact blob_references accept _ _ _ _ accepted

/-- Every successful pure primitive preserves an arbitrary predicate of each
reference's complete schema, physical node, and custody token. Graph actions
remain the enclosing machine's responsibility. -/
theorem evaluate_preserves_references (accept : SchemaId space → NodeId → Option CustodyToken → Prop)
    (schemas : List (Schema space)) (constants : List (Value space)) (opcode : Opcode)
    (type : SchemaId space) (immediate : Nat) (operands : List (Value space)) (result : Value space)
    (constantsValid : ∀ value ∈ constants, ReferencesSatisfy accept value)
    (operandsValid : ∀ value ∈ operands, ReferencesSatisfy accept value)
    (accepted : evaluate schemas constants opcode type immediate operands = .ok (.value result)) :
    ReferencesSatisfy accept result := by
  cases opcode <;> simp only [evaluate, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  case sequencePop =>
    split at accepted
    · rename_i sourceType fields
      have fieldsValid : ∀ value ∈ fields, ReferencesSatisfy accept value := by
        have checked := operandsValid (.sequence sourceType fields) (by simp)
        simpa only [ReferencesSatisfy] using checked
      simp only [except_bind_ok] at accepted
      obtain ⟨schema, _, accepted⟩ := accepted
      split at accepted
      · rename_i empty pairType matched
        cases fields with
        | nil =>
          simp only [except_bind_ok, Except.ok.injEq] at accepted
          obtain ⟨_, rfl, value, optional, equal⟩ := accepted
          cases equal
          exact optionalValue_references accept _ _ _ _ optional (by simp)
        | cons head tail =>
          have packed : ReferencesSatisfy accept (.product pairType [head, .sequence sourceType tail]) := by
            simp only [ReferencesSatisfy, List.mem_cons, List.not_mem_nil, or_false, forall_eq_or_imp, forall_eq]
            exact ⟨fieldsValid head (by simp), fun value member => fieldsValid value (List.mem_cons_of_mem _ member)⟩
          simp only [except_bind_ok, Except.ok.injEq] at accepted
          obtain ⟨_, _, _, _, _, rfl, value, optional, equal⟩ := accepted
          cases equal
          exact optionalValue_references accept _ _ _ _ optional (by simpa using packed)
      · contradiction
    · contradiction
  case sequencePopLast =>
    split at accepted
    · rename_i sourceType fields
      have fieldsValid : ∀ value ∈ fields, ReferencesSatisfy accept value := by
        have checked := operandsValid (.sequence sourceType fields) (by simp)
        simpa only [ReferencesSatisfy] using checked
      simp only [except_bind_ok] at accepted
      obtain ⟨schema, _, accepted⟩ := accepted
      split at accepted
      · rename_i remainingType optionalType
        simp only [except_bind_ok] at accepted
        obtain ⟨_, _, last, optional, equal⟩ := accepted
        cases equal
        have lastValid := optionalValue_references accept _ _ _ _ optional (by
          intro value member
          exact fieldsValid value (List.mem_of_mem_getLast? (by simpa using member)))
        simp only [ReferencesSatisfy, List.mem_cons, List.not_mem_nil, or_false, forall_eq_or_imp, forall_eq]
        exact ⟨fun value member => fieldsValid value (List.dropLast_subset fields member), lastValid⟩
      · contradiction
    · contradiction
  all_goals try (split at accepted)
  all_goals try simp_all only [List.mem_cons, List.not_mem_nil, or_false, forall_eq_or_imp, forall_eq, ReferencesSatisfy]
  all_goals grind (gen := 32) only [except_bind_ok, → lookup_member, ReferencesSatisfy,
    → (arithmetic_references accept), → (bitwise_references accept), → (compare_references accept),
    → (convert_references accept), → (naturalResult_references accept), → (optionalValue_references accept),
    → (collection_references accept), → (blob_references accept), → (sliceBlob_references accept),
    List.mem_cons, List.mem_singleton, List.mem_append, Option.toList_some, Option.toList_none,
    → List.mem_of_getElem?, Option.mem_toList, Option.mem_def, Option.map_eq_some_iff,
    List.mem_cons_self, List.mem_cons_of_mem, → List.mem_or_eq_of_mem_set,
    → List.mem_of_mem_take, List.dropLast_subset, → List.mem_of_mem_getLast?, graphArity]

end BoundaryV2.Profile.Primitives
