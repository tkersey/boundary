import BoundaryV2.ValueTyping
import BoundaryV2.SchemaAdmission

namespace BoundaryV2.Profile

theorem integer_schema_scalar_valid (shape : Schema space) (kind : Scalars.IntegerType) (number : Int)
    (found : Scalars.integerType shape = some kind) (bounded : kind.Contains number) :
    Value.scalarValid shape number = true := by
  cases shape <;> simp only [Scalars.integerType] at found <;> try contradiction
  all_goals cases found
  all_goals simpa only [Value.scalarValid, Scalars.integerType, decide_eq_true_eq] using bounded

theorem integer_value_typed (schemas : List (Schema space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (schema : SchemaId space) (shape : Schema space) (kind : Scalars.IntegerType) (value : Scalars.Integer kind)
    (found : schemas[schema.value]? = some shape) (typeFound : Scalars.integerType shape = some kind) :
    Value.Typed schemas references (.scalar schema value.value) :=
  .scalar found (integer_schema_scalar_valid shape kind value.value typeFound value.valid)

namespace UTF8

theorem encoded_scalar_length_le_four (number : Nat) (bytes : Bytes) (encoded : encodeScalar number = some bytes) :
    bytes.length ≤ 4 := by
  unfold encodeScalar at encoded
  repeat' split at encoded <;> try contradiction
  all_goals cases encoded
  all_goals simp

end UTF8

theorem text_scalar_typed (schemas : List (Schema space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (schema : SchemaId space) (number : Nat) (bytes : Bytes)
    (found : schemas[schema.value]? = some .text) (encoded : UTF8.encodeScalar number = some bytes) :
    Value.Typed schemas references (.blob schema bytes) := by
  refine .blob found ?_
  have valid := UTF8.encoded_scalar_valid number bytes encoded
  have bounded := UTF8.encoded_scalar_length_le_four number bytes encoded
  simp only [Value.blobValid, Value.blobMaximum, Value.isText, valid, Bool.not_true, Bool.false_or,
    Bool.and_true, Bool.and_eq_true, decide_eq_true_eq]
  constructor <;> simp only [wordLimit] <;> omega

namespace SchemaAdmission

theorem member_wire_valid (schemas : List (Schema space)) (shape : Schema space)
    (accepted : valid schemas = true) (member : shape ∈ schemas) : (Codecs.schema space).valid shape = true := by
  simp only [valid, Bool.and_eq_true] at accepted
  have encoded := accepted.1.1
  change (_ && schemas.all (Codecs.schema space).valid) = true at encoded
  exact List.all_eq_true.mp (Bool.and_eq_true_iff.mp encoded).2 shape member

theorem array_length_bounded (schemas : List (Schema space)) (schema element : SchemaId space) (count : Nat)
    (accepted : valid schemas = true) (found : schemas[schema.value]? = some (.array element count)) : count < wordLimit := by
  have encoded := member_wire_valid schemas (.array element count) accepted (List.mem_of_getElem? found)
  simp only [Codecs.schema, Wire.NonemptyCodec.iso, Wire.Codec.iso, Wire.NonemptyCodec.dependent,
    Wire.Codec.dependent, Codecs.schemaView, Codecs.schemaFields, Wire.NonemptyCodec.pair,
    Wire.Codec.pair, Wire.NonemptyCodec.natural, Wire.Codec.natural, Bool.and_eq_true] at encoded
  exact of_decide_eq_true encoded.2.2

end SchemaAdmission

namespace Primitives

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem table_lookup_ok (items : List α) (index : Nat) (value : α)
    (accepted : lookup items index = .ok value) :
    items[index]? = some value := by
  unfold lookup at accepted
  cases found : items[index]? <;> simp [found] at accepted
  cases accepted
  rfl

private theorem checked_condition (condition : Bool) (reason : Invalid) (result : Unit)
    (accepted : require condition reason = .ok result) : condition = true := by
  unfold require at accepted
  split at accepted <;> first | assumption | contradiction

theorem collection_preserves_types (schemas : List (Schema space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (schema : SchemaId space) (fields : List (Value space)) (result : Value space)
    (accepted : collection schemas schema fields = .ok (.value result))
    (catalog : SchemaAdmission.valid schemas = true)
    (typed : ∀ value ∈ fields, Value.Typed schemas references value) : Value.Typed schemas references result := by
  simp only [collection, bind, except_bind_ok] at accepted
  obtain ⟨shape, looked, accepted⟩ := accepted
  have found := table_lookup_ok schemas schema.value shape looked
  cases shape <;> try contradiction
  case seq element =>
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq, Result.value.injEq] at accepted
    obtain ⟨_, fieldsOk, _, lengthOk, rfl⟩ := accepted
    have fieldsOk := checked_condition _ _ _ fieldsOk
    have lengthOk := checked_condition _ _ _ lengthOk
    refine .sequence found ?_ ?_ typed
    · simpa only [Value.sequenceLengthValid, Bool.and_true] using lengthOk
    · intro child member
      have same : child.schema = element := by simpa using List.all_eq_true.mp fieldsOk child member
      simp [Value.sequenceElement, same]
  case vector element maximum =>
    simp only [except_bind_ok] at accepted
    obtain ⟨_, fieldsOk, accepted⟩ := accepted
    split at accepted
    · simp [pure, Except.pure] at accepted
    · rename_i bounded
      simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq, Result.value.injEq] at accepted
      obtain ⟨_, lengthOk, rfl⟩ := accepted
      have fieldsOk := checked_condition _ _ _ fieldsOk
      have lengthOk := checked_condition _ _ _ lengthOk
      refine .sequence found ?_ ?_ typed
      · simpa [Value.sequenceLengthValid, Nat.le_of_not_gt bounded] using lengthOk
      · intro child member
        have same : child.schema = element := by simpa using List.all_eq_true.mp fieldsOk child member
        simp [Value.sequenceElement, same]
  case array element count =>
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq, Result.value.injEq] at accepted
    obtain ⟨_, fieldsOk, rfl⟩ := accepted
    have checked := checked_condition _ _ _ fieldsOk
    have fieldsOk := (Bool.and_eq_true_iff.mp checked).1
    have lengthOk : fields.length = count := by simpa using (Bool.and_eq_true_iff.mp checked).2
    have bounded := SchemaAdmission.array_length_bounded schemas schema element count catalog found
    refine .sequence found ?_ ?_ typed
    · simp [Value.sequenceLengthValid, lengthOk, bounded]
    · intro child member
      have same : child.schema = element := by simpa using List.all_eq_true.mp fieldsOk child member
      simp [Value.sequenceElement, same]

theorem integer_type_lookup (schemas : List (Schema space)) (value : Value space) (kind : Scalars.IntegerType)
    (accepted : integerType schemas value = .ok kind) :
    ∃ shape, schemas[value.schema.value]? = some shape ∧ Scalars.integerType shape = some kind := by
  simp only [integerType, bind, except_bind_ok] at accepted
  obtain ⟨shape, looked, accepted⟩ := accepted
  have found := table_lookup_ok schemas value.schema.value shape looked
  split at accepted <;> try contradiction
  cases accepted
  exact ⟨shape, found, by assumption⟩

theorem integer_result_typed (schemas : List (Schema space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (schema : SchemaId space) (shape : Schema space) (kind : Scalars.IntegerType)
    (response : Except Fault (Scalars.Integer kind)) (result : Value space)
    (found : schemas[schema.value]? = some shape) (kindAt : Scalars.integerType shape = some kind)
    (accepted : integerResult schema response = .value result) : Value.Typed schemas references result := by
  cases response with
  | error fault => contradiction
  | ok value => cases accepted; exact integer_value_typed schemas references schema shape kind value found kindAt

theorem arithmetic_preserves_types (schemas : List (Schema space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (operation : Scalars.Arithmetic) (schema : SchemaId space) (operands : List (Value space)) (result : Value space)
    (accepted : arithmetic schemas operation schema operands = .ok (.value result)) : Value.Typed schemas references result := by
  unfold arithmetic at accepted
  split at accepted <;> try contradiction
  rename_i left right
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, checked, kind, kindAt, first, _, second, _, evaluated⟩ := accepted
  have same : left.schema = schema := by simpa using (Bool.and_eq_true_iff.mp (checked_condition _ _ _ checked)).2
  obtain ⟨shape, found, typeAt⟩ := integer_type_lookup schemas left kind kindAt
  exact integer_result_typed schemas references schema shape kind _ result (by simpa only [same] using found) typeAt evaluated

theorem bitwise_preserves_types (schemas : List (Schema space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (operation : Scalars.Bitwise) (schema : SchemaId space) (operands : List (Value space)) (result : Value space)
    (accepted : bitwise schemas operation schema operands = .ok (.value result)) : Value.Typed schemas references result := by
  unfold bitwise at accepted
  split at accepted <;> try contradiction
  rename_i left right
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq, Result.value.injEq] at accepted
  obtain ⟨_, checked, kind, kindAt, first, _, second, _, rfl⟩ := accepted
  have same : left.schema = schema := by simpa using (Bool.and_eq_true_iff.mp (checked_condition _ _ _ checked)).2
  obtain ⟨shape, found, typeAt⟩ := integer_type_lookup schemas left kind kindAt
  exact integer_value_typed schemas references schema shape kind (Scalars.bitwise operation first second)
    (by simpa only [same] using found) typeAt

theorem convert_preserves_types (schemas : List (Schema space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (schema : SchemaId space) (operands : List (Value space)) (result : Value space)
    (accepted : convert schemas schema operands = .ok (.value result)) : Value.Typed schemas references result := by
  unfold convert at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨kind, _, value, _, shape, looked, accepted⟩ := accepted
  have found := table_lookup_ok schemas schema.value shape looked
  split at accepted <;> try contradiction
  simp only [pure, Except.pure, Except.ok.injEq] at accepted
  exact integer_result_typed schemas references schema shape _ _ result found (by assumption) accepted

theorem natural_result_typed (schemas : List (Schema space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (schema : SchemaId space) (number : Nat) (result : Value space)
    (accepted : naturalResult schemas schema number = .ok (.value result)) : Value.Typed schemas references result := by
  simp only [naturalResult, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq, Result.value.injEq] at accepted
  obtain ⟨shape, looked, _, checked, rfl⟩ := accepted
  exact .scalar (table_lookup_ok schemas schema.value shape looked)
    (Bool.and_eq_true_iff.mp (checked_condition _ _ _ checked)).2

theorem compare_preserves_types (schemas : List (Schema space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (less : Bool) (schema : SchemaId space) (operands : List (Value space)) (result : Value space)
    (accepted : compare schemas less schema operands = .ok (.value result)) : Value.Typed schemas references result := by
  unfold compare at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq, Result.value.injEq] at accepted
  obtain ⟨_, _, booleanSchema, booleanAt, _, isBoolean, shape, _, first, _, second, _, _, _, _, _, rfl⟩ := accepted
  have booleanShape : booleanSchema = .boolean := by simpa using checked_condition _ _ _ isBoolean
  have found : schemas[schema.value]? = some .boolean := by simpa only [booleanShape] using table_lookup_ok schemas schema.value booleanSchema booleanAt
  refine .scalar found ?_
  repeat' split
  all_goals rfl

theorem optional_value_typed (schemas : List (Schema space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (schema : SchemaId space) (item : Option (Value space)) (result : Value space)
    (accepted : optionalValue schemas schema item = .ok result)
    (typed : ∀ value ∈ item, Value.Typed schemas references value) :
    Value.Typed schemas references result ∧ result.schema = schema := by
  simp only [optionalValue, bind, except_bind_ok] at accepted
  obtain ⟨shape, looked, accepted⟩ := accepted
  have found := table_lookup_ok schemas schema.value shape looked
  split at accepted <;> try contradiction
  rename_i empty element
  simp only [except_bind_ok] at accepted
  obtain ⟨unitShape, unitLooked, _, unitChecked, accepted⟩ := accepted
  have unitIs : unitShape = .unit := by simpa using checked_condition _ _ _ unitChecked
  have unitAt : schemas[empty.value]? = some .unit := by simpa only [unitIs] using table_lookup_ok schemas empty.value unitShape unitLooked
  cases item with
  | none =>
    cases accepted
    exact ⟨.variant found (by decide) rfl (.scalar unitAt rfl), rfl⟩
  | some value =>
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, checked, rfl⟩ := accepted
    have same : value.schema = element := by simpa using checked_condition _ _ _ checked
    exact ⟨.variant found (by decide) (by simp [same]) (typed value rfl), rfl⟩

theorem blob_preserves_types (schemas : List (Schema space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (schema : SchemaId space) (bytes : Bytes) (result : Value space)
    (accepted : blob schemas schema bytes = .ok (.value result)) : Value.Typed schemas references result := by
  simp only [blob, bind, except_bind_ok] at accepted
  obtain ⟨shape, looked, accepted⟩ := accepted
  have found := table_lookup_ok schemas schema.value shape looked
  split at accepted <;> try contradiction
  rename_i maximum maximumAt
  split at accepted
  · simp [pure, Except.pure] at accepted
  · rename_i bounded
    simp only [except_bind_ok] at accepted
    obtain ⟨_, lengthOk, accepted⟩ := accepted
    have lengthOk := checked_condition _ _ _ lengthOk
    split at accepted
    · simp [pure, Except.pure] at accepted
    · rename_i textValid
      cases accepted
      refine .blob found ?_
      have capacity : bytes.length ≤ maximum := by omega
      have text : (!Value.isText shape || UTF8.valid bytes) = true := by
        cases isText : Value.isText shape <;> cases valid : UTF8.valid bytes <;> simp_all
      simp only [Value.blobValid, maximumAt, lengthOk, capacity, text, decide_true, Bool.true_and]

theorem slice_blob_preserves_types (schemas : List (Schema space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (schema : SchemaId space) (bytes : Bytes) (start stop : Nat) (result : Value space)
    (accepted : sliceBlob schemas schema bytes start stop = .ok (.value result)) : Value.Typed schemas references result := by
  unfold sliceBlob at accepted
  split at accepted
  · cases accepted
  · exact blob_preserves_types schemas references schema _ result accepted

theorem byte_order_bounded (left right : Bytes) : -1 ≤ byteOrder left right ∧ byteOrder left right ≤ 1 := by
  induction left generalizing right with
  | nil => cases right <;> simp [byteOrder]
  | cons first rest induction =>
    cases right with
    | nil => simp [byteOrder]
    | cons second tail =>
      simp only [byteOrder]
      split
      · decide
      · split
        · decide
        · exact induction tail

end Primitives
end BoundaryV2.Profile
