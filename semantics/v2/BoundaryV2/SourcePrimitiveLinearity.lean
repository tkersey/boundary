import BoundaryV2.PrimitiveResultSchema
import BoundaryV2.SourcePrimitiveCustody
import BoundaryV2.SourceOperandLaws

namespace BoundaryV2.Profile.Source.Machine
namespace PrimitiveLinearity

private theorem except_bind_ok (value : Except ε α) (next : α → Except ε β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem lookup_ok (items : List α) (index : Nat) (value : α)
    (accepted : Primitives.lookup items index = .ok value) : items[index]? = some value := by
  unfold Primitives.lookup at accepted
  cases found : items[index]? <;> simp [found] at accepted
  cases accepted; rfl

private theorem member_linear (values : List SemanticValue) (value : SemanticValue)
    (linear : (values.flatMap ownedTokens).Nodup) (member : value ∈ values) : (ownedTokens value).Nodup :=
  (List.pairwise_flatMap.mp linear).1 value member

private theorem integerResult_free (schema : SchemaId .source) (calculated : Except Fault (Scalars.Integer kind))
    (result : SemanticValue) (accepted : Primitives.integerResult schema calculated = .value result) : ownedTokens result = [] := by
  cases calculated <;> cases accepted
  simp [ownedTokens]

private theorem arithmetic_free (schemas : List (Schema .source)) (operation : Scalars.Arithmetic)
    (schema : SchemaId .source) (operands : List SemanticValue) (result : SemanticValue)
    (accepted : Primitives.arithmetic schemas operation schema operands = .ok (.value result)) : ownedTokens result = [] := by
  simp only [Primitives.arithmetic, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, → integerResult_free]

private theorem bitwise_free (schemas : List (Schema .source)) (operation : Scalars.Bitwise)
    (schema : SchemaId .source) (operands : List SemanticValue) (result : SemanticValue)
    (accepted : Primitives.bitwise schemas operation schema operands = .ok (.value result)) : ownedTokens result = [] := by
  simp only [Primitives.bitwise, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, ownedTokens]

private theorem compare_free (schemas : List (Schema .source)) (less : Bool)
    (schema : SchemaId .source) (operands : List SemanticValue) (result : SemanticValue)
    (accepted : Primitives.compare schemas less schema operands = .ok (.value result)) : ownedTokens result = [] := by
  simp only [Primitives.compare, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, ownedTokens]

private theorem convert_free (schemas : List (Schema .source))
    (schema : SchemaId .source) (operands : List SemanticValue) (result : SemanticValue)
    (accepted : Primitives.convert schemas schema operands = .ok (.value result)) : ownedTokens result = [] := by
  simp only [Primitives.convert, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, → integerResult_free]

private theorem natural_free (schemas : List (Schema .source)) (schema : SchemaId .source)
    (number : Nat) (result : SemanticValue)
    (accepted : Primitives.naturalResult schemas schema number = .ok (.value result)) : ownedTokens result = [] := by
  simp only [Primitives.naturalResult, bind, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, ownedTokens]

private theorem collection_tokens (schemas : List (Schema .source)) (schema : SchemaId .source)
    (fields : List SemanticValue) (result : SemanticValue)
    (accepted : Primitives.collection schemas schema fields = .ok (.value result)) :
    ownedTokens result = fields.flatMap ownedTokens := by
  simp only [Primitives.collection, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, ownedTokens]

private theorem optional_tokens (schemas : List (Schema .source)) (schema : SchemaId .source)
    (value : Option SemanticValue) (result : SemanticValue)
    (accepted : Primitives.optionalValue schemas schema value = .ok result) :
    ownedTokens result = value.toList.flatMap ownedTokens := by
  simp only [Primitives.optionalValue, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, ownedTokens, Option.toList, List.flatMap_cons, List.flatMap_nil, List.append_nil]

private theorem flatMap_sublist (first second : List α) (f : α → List β) (contained : first.Sublist second) :
    (first.flatMap f).Sublist (second.flatMap f) := by
  induction contained with
  | slnil => exact .slnil
  | cons _ _ ih => simpa only [List.flatMap_cons] using ih.trans (List.sublist_append_right _ _)
  | cons_cons _ _ ih => simpa only [List.flatMap_cons] using ih.append_left _

private theorem set_tokens_subset (fields : List SemanticValue) (index : Nat) (replacement : SemanticValue) :
    (fields.set index replacement).flatMap ownedTokens ⊆ fields.flatMap ownedTokens ++ ownedTokens replacement := by
  intro token member
  obtain ⟨value, atField, atValue⟩ := List.mem_flatMap.mp member
  rcases List.mem_or_eq_of_mem_set atField with original | rfl
  · exact List.mem_append_left _ (List.mem_flatMap.mpr ⟨value, original, atValue⟩)
  · exact List.mem_append_right _ atValue

private theorem set_tokens_linear (fields : List SemanticValue) (index : Nat) (replacement : SemanticValue)
    (linear : (fields.flatMap ownedTokens ++ ownedTokens replacement).Nodup) :
    ((fields.set index replacement).flatMap ownedTokens).Nodup := by
  induction fields generalizing index with
  | nil => simp
  | cons head tail ih =>
    have separated : (ownedTokens head ++ (tail.flatMap ownedTokens ++ ownedTokens replacement)).Nodup := by
      simpa only [List.flatMap_cons, List.append_assoc] using linear
    obtain ⟨headLinear, restLinear, disjoint⟩ := List.nodup_append.mp separated
    cases index with
    | zero =>
      simpa only [List.set_cons_zero, List.flatMap_cons] using restLinear.perm List.perm_append_comm
    | succ index =>
      simp only [List.set_cons_succ, List.flatMap_cons]
      exact List.nodup_append.mpr ⟨headLinear, ih index restLinear,
        fun first firstAt second secondAt => disjoint first firstAt second (set_tokens_subset tail index replacement secondAt)⟩

private theorem blob_free (schemas : List (Schema .source)) (schema : SchemaId .source)
    (bytes : Bytes) (result : SemanticValue)
    (accepted : Primitives.blob schemas schema bytes = .ok (.value result)) : ownedTokens result = [] := by
  simp only [Primitives.blob, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, ownedTokens]

private theorem sliceBlob_free (schemas : List (Schema .source)) (schema : SchemaId .source)
    (bytes : Bytes) (start length : Nat) (result : SemanticValue)
    (accepted : Primitives.sliceBlob schemas schema bytes start length = .ok (.value result)) : ownedTokens result = [] := by
  simp only [Primitives.sliceBlob] at accepted
  grind (gen := 32) only [except_bind_ok, → blob_free]

private theorem optional_linear (schemas : List (Schema .source)) (schema : SchemaId .source)
    (value : Option SemanticValue) (result : SemanticValue)
    (accepted : Primitives.optionalValue schemas schema value = .ok result)
    (linear : ∀ item ∈ value, (ownedTokens item).Nodup) : (ownedTokens result).Nodup := by
  rw [optional_tokens _ _ _ _ accepted]
  cases value with
  | none => simp
  | some value => simpa using linear value rfl


private theorem take_tokens_linear (fields : List SemanticValue) (index : Nat)
    (linear : (fields.flatMap ownedTokens).Nodup) : ((fields.take index).flatMap ownedTokens).Nodup :=
  (flatMap_sublist _ _ _ (List.take_sublist index fields)).nodup linear

private theorem lookup_optional_linear (schemas : List (Schema .source)) (schema : SchemaId .source)
    (fields : List SemanticValue) (index : Nat) (result : SemanticValue)
    (accepted : Primitives.optionalValue schemas schema fields[index]? = .ok result)
    (linear : (fields.flatMap ownedTokens).Nodup) : (ownedTokens result).Nodup := by
  apply optional_linear _ _ _ _ accepted
  intro value member
  exact member_linear fields value linear (List.mem_of_getElem? member)

private theorem dropLast_tokens (fields : List SemanticValue) :
    fields.dropLast.flatMap ownedTokens ++ fields.getLast?.toList.flatMap ownedTokens = fields.flatMap ownedTokens := by
  by_cases empty : fields = []
  · simp [empty]
  · rw [List.getLast?_eq_some_getLast empty]
    simpa only [List.flatMap_append, List.flatMap_cons, List.flatMap_nil, List.append_nil,
      Option.toList_some] using congrArg (List.flatMap ownedTokens) (List.dropLast_concat_getLast empty)


private theorem optional_byte_linear (schemas : List (Schema .source)) (schema element : SchemaId .source)
    (byte : Option UInt8) (result : SemanticValue)
    (accepted : Primitives.optionalValue schemas schema (byte.map fun byte => .scalar element byte.toNat) = .ok result) :
    (ownedTokens result).Nodup := by
  apply optional_linear _ _ _ _ accepted
  intro value member
  cases byte <;> cases member
  simp [ownedTokens]

/-- The pure evaluator cannot duplicate an exclusive token in its output.
The premise counts input occurrences, including nested aggregates, and does
not collapse equal tokens into a set. -/
theorem evaluate_preserves_unique_owned_tokens (schemas : List (Schema .source))
    (constants operands : List SemanticValue) (opcode : Opcode) (schema : SchemaId .source) (immediate : Nat)
    (result : SemanticValue)
    (constantsLinear : ∀ value ∈ constants, (ownedTokens value).Nodup)
    (inputsLinear : (operands.flatMap ownedTokens).Nodup)
    (accepted : Primitives.evaluate schemas constants opcode schema immediate operands = .ok (.value result)) :
    (ownedTokens result).Nodup := by
  cases opcode <;> simp only [Primitives.evaluate, Primitives.graphArity, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  case integerAdd | integerSub | integerMul | integerDiv | integerRem =>
    rw [arithmetic_free _ _ _ _ _ accepted]; exact List.nodup_nil
  case integerBitAnd | integerBitOr | integerBitXor =>
    rw [bitwise_free _ _ _ _ _ accepted]; exact List.nodup_nil
  case integerConvert => rw [convert_free _ _ _ _ accepted]; exact List.nodup_nil
  case equal | less => rw [compare_free _ _ _ _ _ accepted]; exact List.nodup_nil
  case sequence => rw [collection_tokens _ _ _ _ accepted]; exact inputsLinear
  case field =>
    split at accepted <;> try contradiction
    rename_i fieldSchema fields
    simp only [except_bind_ok, Except.ok.injEq, Primitives.Result.value.injEq] at accepted
    obtain ⟨value, looked, _, _, rfl⟩ := accepted
    exact member_linear fields value (by simpa [ownedTokens] using inputsLinear) (List.mem_of_getElem? (lookup_ok _ _ _ looked))
  case sequenceAppend | sequenceConcat =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, collected⟩ := accepted
    rw [collection_tokens _ _ _ _ collected]
    simpa [ownedTokens, List.flatMap_append] using inputsLinear
  case sequenceTake =>
    split at accepted <;> try contradiction
    rename_i itemSchema fields selected
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, index, _, collected⟩ := accepted
    rw [collection_tokens _ _ _ _ collected]
    apply take_tokens_linear
    exact (List.nodup_append.mp (by simpa [ownedTokens] using inputsLinear)).1
  case sequenceSet =>
    split at accepted <;> try contradiction
    rename_i itemSchema fields selected replacement
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, index, _, collected⟩ := accepted
    split at collected
    · cases collected
    rw [collection_tokens _ _ _ _ collected]
    apply set_tokens_linear
    have original : (fields.flatMap ownedTokens ++ (ownedTokens selected ++ ownedTokens replacement)).Nodup := by
      simpa [ownedTokens] using inputsLinear
    exact ((List.sublist_append_right (ownedTokens selected) (ownedTokens replacement)).append_left _).nodup original
  case sequencePop =>
    split at accepted <;> try contradiction
    rename_i itemSchema fields
    simp only [except_bind_ok] at accepted
    obtain ⟨shape, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    rename_i empty pairType
    cases fields with
    | nil =>
      simp only [except_bind_ok, Except.ok.injEq, Primitives.Result.value.injEq] at accepted
      obtain ⟨payload, rfl, value, optional, rfl⟩ := accepted
      rw [optional_tokens _ _ _ _ optional]
      simp
    | cons head tail =>
      simp only [except_bind_ok, Except.ok.injEq, Primitives.Result.value.injEq] at accepted
      obtain ⟨_, _, _, _, payload, rfl, value, optional, rfl⟩ := accepted
      rw [optional_tokens _ _ _ _ optional]
      simpa [ownedTokens] using inputsLinear
  case blobByte =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨shape, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, Except.ok.injEq, Primitives.Result.value.injEq] at accepted
    obtain ⟨_, _, _, _, index, _, value, optional, rfl⟩ := accepted
    exact optional_byte_linear _ _ _ _ _ optional
  all_goals try (split at accepted <;> try contradiction)
  all_goals grind (gen := 32) only [except_bind_ok, → lookup_ok, → member_linear,
    → natural_free, → blob_free, → sliceBlob_free, → optional_linear, → lookup_optional_linear, ← take_tokens_linear, ← set_tokens_linear, dropLast_tokens,
    collection_tokens, optional_tokens, ownedTokens, Primitives.graphArity,
    List.flatMap_cons, List.flatMap_nil, List.flatMap_append, List.append_nil, List.append_assoc,
    List.nodup_nil, List.nodup_append, List.mem_cons, List.mem_singleton, → List.mem_of_getElem?]

private theorem moves_tokens (values : List Located) (receiver : Nat → Custody.Owner) :
    ((values.mapIdx fun index value => value.moves (receiver index)).flatten).map Custody.Move.token =
      values.flatMap (fun value => ownedTokens value.value) := by
  induction values generalizing receiver with
  | nil => rfl
  | cons head tail ih =>
    simp only [List.mapIdx_cons, List.flatten_cons, List.map_append, List.flatMap_cons]
    rw [ih]
    simp [Located.moves, List.map_map, Function.comp_def]

theorem move_values_checks_unique_input_occurrences (before after : Heap) (values : List Located)
    (receiver : Nat → Custody.Owner) (accepted : moveValues before values receiver = some after) :
    (values.flatMap fun value => ownedTokens value.value).Nodup := by
  simp only [moveValues, bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨book, committed, rfl⟩ := accepted
  unfold Custody.commit at committed
  split at committed
  · rename_i admitted
    have unique := (Bool.and_eq_true_iff.mp admitted).1
    have checked : (((values.mapIdx fun index value => value.moves (receiver index)).flatten).map Custody.Move.token).Nodup :=
      of_decide_eq_true unique
    simpa only [moves_tokens] using checked
  · cases committed

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

private theorem require_ok (condition : Bool) (reason : Invalid) (result : Unit)
    (accepted : require condition reason = .ok result) : condition = true := by
  unfold require at accepted
  split at accepted <;> first | assumption | contradiction

/-- Successful source commit supplies its own input-linearity premise. The
observing branch produces no owning result; every other branch has already
checked all input occurrences together in the actual custody transaction. -/
theorem committed_primitive_result_unique (machine : State) (context : Context) (opcode : Opcode)
    (schema : SchemaId .source) (immediate : Nat) (operands : List Located) (result : SemanticValue) (after : Transition)
    (typed : context.typingValid = true)
    (evaluated : Primitives.evaluate context.source.schemas context.executionConstants opcode schema immediate
      (operands.map Located.value) = .ok (.value result))
    (accepted : commitPure machine opcode operands result = .ok after) : (ownedTokens result).Nodup := by
  have constantsLinear : ∀ value ∈ context.executionConstants, (ownedTokens value).Nodup := by
    intro value member
    rw [(checked_execution_constants_have_no_handles context typed value member).2]
    exact List.nodup_nil
  simp only [commitPure, bind, except_bind_ok] at accepted
  obtain ⟨middle, _, accepted⟩ := accepted
  split at accepted
  · have free : (ownedTokens result).isEmpty = true := by
      grind only [except_bind_ok, → require_ok]
    simp [List.isEmpty_iff.mp free]
  · have inputsLinear : (operands.flatMap fun value => ownedTokens value.value).Nodup := by
      grind only [except_bind_ok, fromOption_ok, → move_values_checks_unique_input_occurrences]
    apply evaluate_preserves_unique_owned_tokens _ _ _ _ _ _ _ constantsLinear ?_ evaluated
    simpa only [List.flatMap_map] using inputsLinear

private theorem moved_to_owner (before after : Heap) (values : List Located) (owner : Custody.Owner)
    (accepted : moveValues before values (fun _ => owner) = some after) (token : CustodyToken)
    (member : token ∈ values.flatMap (fun value => ownedTokens value.value)) : Custody.has after.custody token owner = true := by
  obtain ⟨value, valueAt, tokenAt⟩ := List.mem_flatMap.mp member
  obtain ⟨index, bounded, rfl⟩ := List.mem_iff_getElem.mp valueAt
  have owned := (move_values_transfers_each_operand before after values (fun _ => owner) index bounded token tokenAt accepted).2
  simpa only [Custody.has, Custody.owns, List.any_eq_true, Bool.and_eq_true, beq_iff_eq] using owned

private theorem consume_keeps_other (before after : Custody.Book) (tokens : List CustodyToken) (owner : Custody.Owner)
    (accepted : Custody.consume before tokens owner = some after) (token : CustodyToken) (notRemoved : token ∉ tokens)
    (owned : Custody.has before token owner = true) : Custody.has after token owner = true := by
  unfold Custody.consume at accepted
  split at accepted <;> try contradiction
  cases accepted
  obtain ⟨entry, member, same, located⟩ : ∃ entry ∈ before.entries, entry.token = token ∧ entry.owner = owner := by
    simpa [Custody.has, List.any_eq_true, Bool.and_eq_true] using owned
  apply List.any_eq_true.mpr
  exact ⟨entry, List.mem_filter.mpr ⟨member, by simpa [same] using notRemoved⟩, by simp [same, located]⟩

private theorem finish_current (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) (owned : current machine.heap value = true) :
    after.state.control = .delivered value ∧ current after.state.heap value = true := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  cases accepted
  exact ⟨rfl, owned⟩

/-- Atomic success returns a result with unique tokens held by its actual
receiving owner. Tokens discarded by the commit do not invalidate those
retained in the returned value. -/
theorem committed_primitive_result_current (machine : State) (context : Context) (opcode : Opcode)
    (schema : SchemaId .source) (immediate : Nat) (operands : List Located) (result : SemanticValue) (after : Transition)
    (typed : context.typingValid = true)
    (evaluated : Primitives.evaluate context.source.schemas context.executionConstants opcode schema immediate
      (operands.map Located.value) = .ok (.value result))
    (accepted : commitPure machine opcode operands result = .ok after) :
    ∃ value, after.state.control = .delivered value ∧ value.value = result ∧ current after.state.heap value = true := by
  have unique := committed_primitive_result_unique machine context opcode schema immediate operands result after typed evaluated accepted
  simp only [commitPure, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, _, accepted⟩ := accepted
  split at accepted
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, free, _, _, finished⟩ := accepted
    have free := List.isEmpty_iff.mp (require_ok _ _ _ free)
    have currentResult : current middle.heap ⟨result, owner⟩ = true := by simp [current, free]
    have delivered := finish_current _ _ _ finished currentResult
    exact ⟨⟨result, owner⟩, delivered.1, rfl, delivered.2⟩
  · simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨heap, moved, _, kept, custody, consumed, finished⟩ := accepted
    have kept := List.all_eq_true.mp (require_ok _ _ _ kept)
    have currentResult : current { heap with custody := custody } ⟨result, owner⟩ = true := by
      apply Bool.and_eq_true_iff.mpr
      refine ⟨decide_eq_true unique, List.all_eq_true.mpr ?_⟩
      intro token member
      have tokenAt : token ∈ operands.flatMap (fun value => ownedTokens value.value) := by
        simpa using kept token member
      have has := moved_to_owner _ _ _ _ moved token tokenAt
      exact consume_keeps_other _ _ _ _ consumed token (by simp [member]) has
    have delivered := finish_current _ _ _ finished currentResult
    exact ⟨⟨result, owner⟩, delivered.1, rfl, delivered.2⟩

end PrimitiveLinearity
end BoundaryV2.Profile.Source.Machine
