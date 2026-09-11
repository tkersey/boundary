import BoundaryV2.ReferenceStructure

namespace BoundaryV2.Profile
namespace ReferencePrimitives
open Primitives
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

theorem collection_preserves_structure (schemas : List (Schema space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (schema : SchemaId space) (fields : List (Value space)) (result : Value space)
    (accepted : collection schemas schema fields = .ok (.value result))
    (typed : ∀ value ∈ fields, Value.ReferenceStructure schemas references value) : Value.ReferenceStructure schemas references result := by
  simp only [collection, bind, except_bind_ok] at accepted
  obtain ⟨shape, looked, accepted⟩ := accepted
  have found := table_lookup_ok schemas schema.value shape looked
  cases shape <;> try contradiction
  case seq element =>
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq, Result.value.injEq] at accepted
    obtain ⟨_, fieldsOk, _, lengthOk, rfl⟩ := accepted
    have fieldsOk := checked_condition _ _ _ fieldsOk
    have lengthOk := checked_condition _ _ _ lengthOk
    refine .sequenceAny found ?_ typed
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
      refine .sequenceAny found ?_ typed
      · intro child member
        have same : child.schema = element := by simpa using List.all_eq_true.mp fieldsOk child member
        simp [Value.sequenceElement, same]
  case array element count =>
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq, Result.value.injEq] at accepted
    obtain ⟨_, fieldsOk, rfl⟩ := accepted
    have checked := checked_condition _ _ _ fieldsOk
    have fieldsOk := (Bool.and_eq_true_iff.mp checked).1
    have lengthOk : fields.length = count := by simpa using (Bool.and_eq_true_iff.mp checked).2
    refine .sequenceAny found ?_ typed
    · intro child member
      have same : child.schema = element := by simpa using List.all_eq_true.mp fieldsOk child member
      simp [Value.sequenceElement, same]

theorem optional_value_structure (schemas : List (Schema space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (schema : SchemaId space) (item : Option (Value space)) (result : Value space)
    (accepted : optionalValue schemas schema item = .ok result)
    (typed : ∀ value ∈ item, Value.ReferenceStructure schemas references value) :
    Value.ReferenceStructure schemas references result ∧ result.schema = schema := by
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

theorem evaluate_preserves_reference_structure (schemas : List (Schema space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (constants : List (Value space)) (opcode : Opcode) (resultType : SchemaId space) (immediate : Nat)
    (operands : List (Value space)) (result : Value space)
    (constantsTyped : ∀ value ∈ constants, Value.ReferenceStructure schemas references value)
    (operandsTyped : ∀ value ∈ operands, Value.ReferenceStructure schemas references value)
    (accepted : evaluate schemas constants opcode resultType immediate operands = .ok (.value result)) :
    Value.ReferenceStructure schemas references result := by
  cases opcode <;> simp only [evaluate, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  case integerAdd | integerSub | integerMul | integerDiv | integerRem =>
    apply Value.ReferenceStructure.of_typed
    exact arithmetic_preserves_types _ references _ _ _ _ accepted
  case integerBitAnd | integerBitOr | integerBitXor =>
    apply Value.ReferenceStructure.of_typed
    exact bitwise_preserves_types _ references _ _ _ _ accepted
  case integerConvert =>
    apply Value.ReferenceStructure.of_typed
    exact convert_preserves_types _ references _ _ _ accepted
  case equal | less =>
    apply Value.ReferenceStructure.of_typed
    exact compare_preserves_types _ references _ _ _ _ accepted
  case sequence => exact collection_preserves_structure _ references _ _ _ accepted operandsTyped
  case constant =>
    simp only [except_bind_ok, Except.ok.injEq, Result.value.injEq] at accepted
    obtain ⟨_, _, value, looked, _, _, rfl⟩ := accepted
    exact constantsTyped value (List.mem_of_getElem? (table_lookup_ok _ _ _ looked))
  case move =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, Except.ok.injEq, Result.value.injEq] at accepted
    obtain ⟨_, _, rfl⟩ := accepted
    exact operandsTyped _ (by simp)
  case integerBitNot =>
    split at accepted <;> try contradiction
    rename_i value
    simp only [except_bind_ok, Except.ok.injEq, Result.value.injEq] at accepted
    obtain ⟨_, checked, kind, kindAt, number, _, rfl⟩ := accepted
    have same : value.schema = resultType := by simpa using checked_condition _ _ _ checked
    obtain ⟨shape, found, typeAt⟩ := integer_type_lookup _ value kind kindAt
    apply Value.ReferenceStructure.of_typed
    exact integer_value_typed _ references resultType shape kind (Scalars.complement number)
      (by simpa only [same] using found) typeAt
  case booleanNot =>
    split at accepted <;> try contradiction
    rename_i sourceType number
    simp only [except_bind_ok, Except.ok.injEq, Result.value.injEq] at accepted
    obtain ⟨shape, looked, _, checked, _, valid, rfl⟩ := accepted
    have checked := (Bool.and_eq_true_iff.mp (checked_condition _ _ _ checked)).2
    have isBoolean : shape = .boolean := by simpa using checked
    have found : schemas[sourceType.value]? = some .boolean := by
      simpa only [isBoolean] using table_lookup_ok _ _ _ looked
    have bounded : number = 0 ∨ number = 1 := by simpa using checked_condition _ _ _ valid
    refine .scalar found ?_
    rcases bounded with rfl | rfl <;> rfl
  case product =>
    simp only [except_bind_ok] at accepted
    obtain ⟨shape, looked, accepted⟩ := accepted
    split at accepted <;> try contradiction
    rename_i fields
    simp only [except_bind_ok, Except.ok.injEq, Result.value.injEq] at accepted
    obtain ⟨_, checked, rfl⟩ := accepted
    exact .product (table_lookup_ok _ _ _ looked)
      (by simpa using checked_condition _ _ _ checked) operandsTyped
  case field =>
    split at accepted <;> try contradiction
    rename_i sourceType fields
    simp only [except_bind_ok, Except.ok.injEq, Result.value.injEq] at accepted
    obtain ⟨value, looked, _, _, rfl⟩ := accepted
    exact (operandsTyped (.product sourceType fields) (by simp)).product_children value
      (List.mem_of_getElem? (table_lookup_ok _ _ _ looked))
  case variant =>
    split at accepted <;> try contradiction
    rename_i payload
    simp only [except_bind_ok] at accepted
    obtain ⟨shape, looked, accepted⟩ := accepted
    split at accepted <;> try contradiction
    rename_i alternatives
    simp only [except_bind_ok, Except.ok.injEq, Result.value.injEq] at accepted
    obtain ⟨_, checked, rfl⟩ := accepted
    have found : schemas[resultType.value]? = some (.sum alternatives) := by
      exact table_lookup_ok _ _ _ looked
    have selected : alternatives[immediate]? = some payload.schema := by simpa using checked_condition _ _ _ checked
    exact .variantAny found selected (operandsTyped payload (by simp))
  case variantTag | sequenceLength | blobLength =>
    split at accepted <;> try contradiction
    apply Value.ReferenceStructure.of_typed
    exact natural_result_typed _ references _ _ _ accepted
  case variantPayload =>
    split at accepted <;> try contradiction
    rename_i sourceType tag payload
    split at accepted
    · cases accepted
    ·
      simp only [except_bind_ok, Except.ok.injEq, Result.value.injEq] at accepted
      obtain ⟨_, _, rfl⟩ := accepted
      exact (operandsTyped (.variant sourceType tag payload) (by simp)).variant_payload
  case sequenceGet =>
    split at accepted <;> try contradiction
    rename_i sourceType fields selected
    simp only [except_bind_ok, Except.ok.injEq, Result.value.injEq] at accepted
    obtain ⟨index, _, value, optional, rfl⟩ := accepted
    exact (optional_value_structure _ references _ _ _ optional (fun value member =>
      (operandsTyped (.sequence sourceType fields) (by simp)).sequence_children value
        (List.mem_of_getElem? member))).1
  case sequenceAppend =>
    split at accepted <;> try contradiction
    rename_i sourceType fields value
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    apply collection_preserves_structure _ references _ _ _ accepted
    intro child member
    rcases List.mem_append.mp member with member | member
    · exact (operandsTyped (.sequence sourceType fields) (by simp)).sequence_children child member
    · have same := List.mem_singleton.mp member
      subst child
      exact operandsTyped value (by simp)
  case sequenceConcat =>
    split at accepted <;> try contradiction
    rename_i left first right second
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    apply collection_preserves_structure _ references _ _ _ accepted
    intro child member
    rcases List.mem_append.mp member with member | member
    · exact (operandsTyped (.sequence left first) (by simp)).sequence_children child member
    · exact (operandsTyped (.sequence right second) (by simp)).sequence_children child member
  case sequenceSet =>
    split at accepted <;> try contradiction
    rename_i sourceType fields selected replacement
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, index, _, accepted⟩ := accepted
    split at accepted
    · cases accepted
    · apply collection_preserves_structure _ references _ _ _ accepted
      intro child member
      rcases List.mem_or_eq_of_mem_set member with member | rfl
      · exact (operandsTyped (.sequence sourceType fields) (by simp)).sequence_children child member
      · exact operandsTyped child (by simp)
  case sequenceTake =>
    split at accepted <;> try contradiction
    rename_i sourceType fields selected
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, index, _, accepted⟩ := accepted
    apply collection_preserves_structure _ references _ _ _ accepted
    intro child member
    exact (operandsTyped (.sequence sourceType fields) (by simp)).sequence_children child (List.mem_of_mem_take member)
  case sequencePop =>
    split at accepted <;> try contradiction
    rename_i sourceType fields
    have sourceTyped := operandsTyped (.sequence sourceType fields) (by simp)
    simp only [except_bind_ok] at accepted
    obtain ⟨shape, outerLooked, accepted⟩ := accepted
    split at accepted <;> try contradiction
    rename_i empty pairType
    cases fields with
    | nil =>
      simp only [except_bind_ok, Except.ok.injEq] at accepted
      obtain ⟨_, rfl, value, optional, equal⟩ := accepted
      cases equal
      exact (optional_value_structure _ references _ _ _ optional (by simp)).1
    | cons head tail =>
      simp only [except_bind_ok, Except.ok.injEq] at accepted
      obtain ⟨pairShape, pairLooked, _, pairChecked, _, rfl, value, optional, equal⟩ := accepted
      cases equal
      have pairIs : pairShape = .product [head.schema, sourceType] := by
        simpa using checked_condition _ _ _ pairChecked
      have pairAt : schemas[pairType.value]? = some (.product [head.schema, sourceType]) := by
        simpa only [pairIs] using table_lookup_ok _ _ _ pairLooked
      have tailTyped := sourceTyped.subset_sequence
        (remaining := tail) (fun child member => List.mem_cons_of_mem head member)
      have packed : Value.ReferenceStructure schemas references (.product pairType [head, .sequence sourceType tail]) := by
        refine .product pairAt rfl ?_
        simp only [List.mem_cons, List.not_mem_nil, or_false, forall_eq_or_imp, forall_eq]
        exact ⟨sourceTyped.sequence_children head (by simp), tailTyped⟩
      exact (optional_value_structure _ references _ _ _ optional (by simpa using packed)).1
  case sequencePopLast =>
    split at accepted <;> try contradiction
    rename_i sourceType fields
    have sourceTyped := operandsTyped (.sequence sourceType fields) (by simp)
    simp only [except_bind_ok] at accepted
    obtain ⟨shape, looked, accepted⟩ := accepted
    split at accepted <;> try contradiction
    rename_i remainingType optionalType
    simp only [except_bind_ok, Except.ok.injEq, Result.value.injEq] at accepted
    obtain ⟨_, checked, last, optional, rfl⟩ := accepted
    have same : remainingType = sourceType := by simpa using checked_condition _ _ _ checked
    have lastTyped := optional_value_structure _ references optionalType fields.getLast? last optional
      (fun child member => sourceTyped.sequence_children child (List.mem_of_mem_getLast? member))
    have restTyped := sourceTyped.subset_sequence (remaining := fields.dropLast)
      (List.dropLast_subset fields)
    refine .product (table_lookup_ok _ _ _ looked) ?_ ?_
    · change [remainingType, optionalType] = [sourceType, last.schema]
      rw [same, lastTyped.2]
    · simp only [List.mem_cons, List.not_mem_nil, or_false, forall_eq_or_imp, forall_eq]
      exact ⟨restTyped, lastTyped.1⟩
  case select =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, Except.ok.injEq, Result.value.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
    split <;> apply operandsTyped <;> simp
  case enumTag =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨shape, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, Except.ok.injEq, Result.value.injEq] at accepted
    obtain ⟨_, valid, target, looked, _, checked, rfl⟩ := accepted
    have targetIs : target = .u32 := by simpa using checked_condition _ _ _ checked
    have found : schemas[resultType.value]? = some .u32 := by
      simpa only [targetIs] using table_lookup_ok _ _ _ looked
    have bounded := (Bool.and_eq_true_iff.mp (checked_condition _ _ _ valid)).1
    refine .scalar found ?_
    simp only [Value.scalarValid, Scalars.integerType, Scalars.IntegerType.Contains,
      Scalars.IntegerType.minimum, Scalars.IntegerType.upper, Scalars.Width.bits]
    exact decide_eq_true (by simpa using bounded)
  case blobConcat =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨first, _, second, _, accepted⟩ := accepted
    apply Value.ReferenceStructure.of_typed
    exact blob_preserves_types _ references _ _ _ accepted
  case blobSlice =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨start, _, stop, _, accepted⟩ := accepted
    apply Value.ReferenceStructure.of_typed
    exact slice_blob_preserves_types _ references _ _ _ _ _ accepted
  case blobCompare =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, Except.ok.injEq, Result.value.injEq] at accepted
    obtain ⟨shape, looked, _, checked, first, _, second, _, rfl⟩ := accepted
    have isSigned : shape = .i8 := by simpa using checked_condition _ _ _ checked
    have found : schemas[resultType.value]? = some .i8 := by
      simpa only [isSigned] using table_lookup_ok _ _ _ looked
    have bounded := byte_order_bounded first second
    refine .scalar found ?_
    simp [Value.scalarValid, Scalars.integerType, Scalars.IntegerType.Contains,
      Scalars.IntegerType.minimum, Scalars.IntegerType.upper, Scalars.Width.bits]
    exact decide_eq_true (by omega)
  case blobByte =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨shape, outerLooked, accepted⟩ := accepted
    split at accepted <;> try contradiction
    rename_i empty element
    simp only [except_bind_ok, Except.ok.injEq, Result.value.injEq] at accepted
    obtain ⟨byteShape, byteLooked, _, byteChecked, index, _, value, optional, rfl⟩ := accepted
    have byteIs : byteShape = .u8 := by simpa using checked_condition _ _ _ byteChecked
    have byteAt : schemas[element.value]? = some .u8 := by
      simpa only [byteIs] using table_lookup_ok _ _ _ byteLooked
    apply (optional_value_structure _ references _ _ _ optional ?_).1
    intro child member
    obtain ⟨byte, _, rfl⟩ := Option.map_eq_some_iff.mp member
    refine .scalar byteAt ?_
    simp only [Value.scalarValid, Scalars.integerType, Scalars.IntegerType.Contains,
      Scalars.IntegerType.minimum, Scalars.IntegerType.upper, Scalars.Width.bits]
    have bounded := byte.toNat_lt
    exact decide_eq_true (by omega)
  case textScalar =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, shape, looked, _, checked, index, _, accepted⟩ := accepted
    have targetIs : shape = .text := by
      simpa using (Bool.and_eq_true_iff.mp (checked_condition _ _ _ checked)).2
    have found : schemas[resultType.value]? = some .text := by
      simpa only [targetIs] using table_lookup_ok _ _ _ looked
    split at accepted
    · cases accepted
    · cases accepted
      apply Value.ReferenceStructure.of_typed
      exact text_scalar_typed _ references resultType index _ found (by assumption)
  case textInteger =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, Except.ok.injEq, Result.value.injEq] at accepted
    obtain ⟨shape, looked, _, checked, kind, _, number, _, rfl⟩ := accepted
    have targetIs : shape = .text := by simpa using checked_condition _ _ _ checked
    have found : schemas[resultType.value]? = some .text := by
      simpa only [targetIs] using table_lookup_ok _ _ _ looked
    apply Value.ReferenceStructure.of_typed
    exact integer_text_typed _ references resultType kind number found
  case blobFromByte =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, Except.ok.injEq, Result.value.injEq] at accepted
    obtain ⟨_, _, shape, looked, _, checked, _, _, _, _, rfl⟩ := accepted
    have targetIs : shape = .bytes := by
      simpa using (Bool.and_eq_true_iff.mp (checked_condition _ _ _ checked)).2
    have found : schemas[resultType.value]? = some .bytes := by
      simpa only [targetIs] using table_lookup_ok _ _ _ looked
    exact .blob found (by simp [Value.blobValid, Value.blobMaximum, Value.isText, wordLimit])
  case computation | cellNew | cellGet | cellSet | cloneResumption | package | unpack | resourcePack | resourceUnpack =>
    simp only [graphArity] at accepted
    split at accepted <;> cases accepted

end ReferencePrimitives
end BoundaryV2.Profile
