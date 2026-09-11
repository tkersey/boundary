import BoundaryV2.PrimitiveValueTypes
namespace BoundaryV2.Profile.Primitives
private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β)
    (result : β) : value.bind next = .ok result ↔
      ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem checked_condition (condition : Bool) (reason : Invalid) (result : Unit)
    (accepted : require condition reason = .ok result) : condition = true := by
  unfold require at accepted
  split at accepted <;> first | assumption | contradiction

private theorem integerResult_schema (type : SchemaId space) (response : Except Fault (Scalars.Integer kind))
    (result : Value space) (accepted : integerResult type response = .value result) : result.schema = type := by
  cases response with
  | error fault => contradiction
  | ok value => cases accepted; rfl

private theorem optionalValue_schema (schemas : List (Schema space)) (type : SchemaId space)
    (item : Option (Value space)) (result : Value space)
    (accepted : optionalValue schemas type item = .ok result) : result.schema = type := by
  simp only [optionalValue, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  cases item <;> grind (gen := 32) only [except_bind_ok, Value.schema]

private theorem arithmetic_schema (schemas : List (Schema space)) (operation : Scalars.Arithmetic)
    (type : SchemaId space) (operands : List (Value space)) (result : Value space)
    (accepted : arithmetic schemas operation type operands = .ok (.value result)) : result.schema = type := by
  simp only [arithmetic, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, → integerResult_schema, Value.schema]

private theorem bitwise_schema (schemas : List (Schema space)) (operation : Scalars.Bitwise)
    (type : SchemaId space) (operands : List (Value space)) (result : Value space)
    (accepted : bitwise schemas operation type operands = .ok (.value result)) : result.schema = type := by
  simp only [bitwise, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, → integerResult_schema, Value.schema]

private theorem compare_schema (schemas : List (Schema space)) (less : Bool)
    (type : SchemaId space) (operands : List (Value space)) (result : Value space)
    (accepted : compare schemas less type operands = .ok (.value result)) : result.schema = type := by
  simp only [compare, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, → integerResult_schema, Value.schema]

private theorem convert_schema (schemas : List (Schema space))
    (type : SchemaId space) (operands : List (Value space)) (result : Value space)
    (accepted : convert schemas type operands = .ok (.value result)) : result.schema = type := by
  simp only [convert, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, → integerResult_schema, Value.schema]

private theorem naturalResult_schema (schemas : List (Schema space)) (number : Nat)
    (type : SchemaId space) (result : Value space)
    (accepted : naturalResult schemas type number = .ok (.value result)) : result.schema = type := by
  simp only [naturalResult, bind, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, → integerResult_schema, Value.schema]

private theorem collection_schema (schemas : List (Schema space))
    (type : SchemaId space) (operands : List (Value space)) (result : Value space)
    (accepted : collection schemas type operands = .ok (.value result)) : result.schema = type := by
  simp only [collection, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, → integerResult_schema, Value.schema]

private theorem blob_schema (schemas : List (Schema space)) (bytes : Bytes)
    (type : SchemaId space) (result : Value space)
    (accepted : blob schemas type bytes = .ok (.value result)) : result.schema = type := by
  simp only [blob, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, → integerResult_schema, Value.schema]

private theorem sliceBlob_schema (schemas : List (Schema space)) (type : SchemaId space)
    (bytes : Bytes) (start stop : Nat) (result : Value space)
    (accepted : sliceBlob schemas type bytes start stop = .ok (.value result)) : result.schema = type := by
  unfold sliceBlob at accepted
  split at accepted
  · cases accepted
  · exact blob_schema _ _ _ _ accepted

set_option maxRecDepth 4096 in
set_option maxHeartbeats 1600000 in
theorem evaluate_result_schema (schemas : List (Schema space)) (constants : List (Value space))
    (opcode : Opcode) (type : SchemaId space) (immediate : Nat) (operands : List (Value space))
    (result : Value space)
    (accepted : evaluate schemas constants opcode type immediate operands = .ok (.value result)) :
    result.schema = type := by
  cases opcode <;> simp only [evaluate, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  all_goals try split at accepted
  all_goals grind (gen := 32) only [except_bind_ok, → checked_condition, Value.schema,
    → arithmetic_schema, → bitwise_schema, → compare_schema, → convert_schema,
    → naturalResult_schema, → optionalValue_schema, → collection_schema, → blob_schema,
    → sliceBlob_schema, graphArity]
end BoundaryV2.Profile.Primitives
