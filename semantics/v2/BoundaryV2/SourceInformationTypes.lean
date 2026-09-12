import BoundaryV2.SourceValueTypes

namespace BoundaryV2.Profile.Source.Machine

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

private theorem require_ok (condition : Bool) (reason : Invalid) (result : Unit)
    (accepted : require condition reason = .ok result) : condition = true := by
  unfold require at accepted
  split at accepted <;> first | assumption | contradiction

/-- Cleanup information is constructed from a typed failure sequence and an
admissible cancellation reason. Size and text checks belong to the actual constructor. -/
theorem cleanupInformation_preserves_value_shapes (context : Context) (schema : SchemaId .source)
    (exit : Cleanup.Exit .source) (information : SemanticValue)
    (accepted : cleanupInformation context schema exit = .ok information)
    (failureTypes : ∀ value, exit.primary = .failure value ∨ value ∈ exit.failures →
      ValueShape context.source.schemas value ∧ value.schema = context.source.failure)
    : ValueShape context.source.schemas information := by
  simp only [cleanupInformation, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, dimensions, _, textGate, shape, productAt, accepted⟩ := accepted
  have dimensions := require_ok _ _ _ dimensions
  have textGate := require_ok _ _ _ textGate
  simp only [Bool.and_eq_true, decide_eq_true_eq] at dimensions
  have failureBound := dimensions.1
  have reasonTypes (reason : Protocol.Reason) (found : exit.cancellation = some reason) :
      match reason with
      | .text data => data.length < wordLimit ∧ UTF8.valid data = true
      | .bytes data => data.length < wordLimit := by
    have raw : Codecs.reason.valid reason = true := by simpa only [found, Option.all_some] using dimensions.2
    have text : Protocol.reasonValid reason = true := by simpa only [found, Option.all_some] using textGate
    cases reason with
    | text data =>
      change (decide (data.length < wordLimit) && true) = true at raw
      exact ⟨by simpa using raw, text⟩
    | bytes data =>
      change (decide (data.length < wordLimit) && true) = true at raw
      simpa using raw
  split at accepted <;> try contradiction
  rename_i primary optional failures
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨shape, primaryAt, accepted⟩ := accepted
  split at accepted <;> try contradiction
  rename_i unit failure reason abandoned
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨shape, optionalAt, accepted⟩ := accepted
  split at accepted <;> try contradiction
  rename_i absent present
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨shape, reasonAt, accepted⟩ := accepted
  split at accepted <;> try contradiction
  rename_i textSchema bytesSchema
  simp only [except_bind_ok] at accepted
  obtain ⟨_, identities, _, shapes, accepted⟩ := accepted
  have identities := require_ok _ _ _ identities
  have shapes := require_ok _ _ _ shapes
  simp only [Bool.and_eq_true, beq_iff_eq] at identities shapes
  obtain ⟨⟨⟨unitAbandoned, unitAbsent⟩, reasonPresent⟩, failureType⟩ := identities
  obtain ⟨⟨⟨unitAt, textAt⟩, bytesAt⟩, failuresAt⟩ := shapes
  have unitTyped : ValueShape context.source.schemas (.scalar unit 0) := .scalar unitAt rfl
  let cancelled : Option SemanticValue := exit.cancellation.map fun cancellation => match cancellation with
    | .text data => .variant reason 0 (.blob textSchema data)
    | .bytes data => .variant reason 1 (.blob bytesSchema data)
  let optionalValue : SemanticValue := match cancelled with
    | none => .variant optional 0 (.scalar unit 0)
    | some value => .variant optional 1 value
  have cancelledTyped : ∀ value, cancelled = some value → ValueShape context.source.schemas value ∧ value.schema = reason := by
    intro value found
    obtain ⟨cancellation, cancellationAt, valueAt⟩ := Option.map_eq_some_iff.mp found
    have cancellationTyped := reasonTypes cancellation cancellationAt
    cases cancellation with
    | text data =>
      cases valueAt
      refine ⟨.variant reasonAt (by decide) rfl (.blob textAt ?_), rfl⟩
      simp only [Profile.Value.blobValid, Profile.Value.blobMaximum, Profile.Value.isText, Bool.not_true,
        Bool.false_or, Bool.and_eq_true, decide_eq_true_eq]
      exact ⟨⟨cancellationTyped.1, by omega⟩, cancellationTyped.2⟩
    | bytes data =>
      cases valueAt
      refine ⟨.variant reasonAt (by decide) rfl (.blob bytesAt ?_), rfl⟩
      simp only [Profile.Value.blobValid, Profile.Value.blobMaximum, Profile.Value.isText, Bool.not_false,
        Bool.true_or, Bool.and_true, Bool.and_eq_true, decide_eq_true_eq]
      exact ⟨cancellationTyped, by omega⟩
  have optionalTyped : ValueShape context.source.schemas optionalValue := by
    unfold optionalValue
    cases found : cancelled with
    | none => exact .variant optionalAt (by decide) (by simp [Profile.Value.schema, unitAbsent]) unitTyped
    | some value =>
      have child := cancelledTyped value found
      exact .variant optionalAt (by decide) (by simp [child.2, reasonPresent]) child.1
  have failuresTyped : ValueShape context.source.schemas (.sequence failures exit.failures) := by
    refine .sequence failuresAt ?_ ?_ ?_
    · simpa [Profile.Value.sequenceLengthValid] using failureBound
    · intro child member
      simp [Profile.Value.sequenceElement, (failureTypes child (Or.inr member)).2]
    · exact fun child member => (failureTypes child (Or.inr member)).1
  have primaryTyped : ∀ value,
      (match exit.primary with
        | .normal _ => pure (.variant primary 0 (.scalar unit 0))
        | .failure value => pure (.variant primary 1 value)
        | .cancellation => do
          let value ← fromOption cancelled .type
          pure (.variant primary 2 value)
        | .abandoned => pure (.variant primary 3 (.scalar unit 0))) = (Except.ok value : Except Invalid SemanticValue) →
      ValueShape context.source.schemas value ∧ value.schema = primary := by
    intro value found
    cases primaryIs : exit.primary with
    | normal original =>
      simp only [primaryIs, pure, Except.pure, Except.ok.injEq] at found
      cases found
      exact ⟨.variant primaryAt (by decide) rfl unitTyped, rfl⟩
    | failure original =>
      simp only [primaryIs, pure, Except.pure, Except.ok.injEq] at found
      cases found
      have child := failureTypes original (Or.inl primaryIs)
      exact ⟨.variant primaryAt (by decide) (by simp [child.2, failureType]) child.1, rfl⟩
    | cancellation =>
      simp only [primaryIs, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at found
      obtain ⟨child, childAt, rfl⟩ := found
      have childTyped := cancelledTyped child childAt
      exact ⟨.variant primaryAt (by decide) (by simp [childTyped.2]) childTyped.1, rfl⟩
    | abandoned =>
      simp only [primaryIs, pure, Except.pure, Except.ok.injEq] at found
      cases found
      exact ⟨.variant primaryAt (by decide) (by simp [Profile.Value.schema, unitAbandoned]) unitTyped, rfl⟩
  have finish (primaryValue : SemanticValue)
      (primaryValueTyped : ValueShape context.source.schemas primaryValue ∧ primaryValue.schema = primary) :
      ValueShape context.source.schemas (.product schema [primaryValue, optionalValue, .sequence failures exit.failures]) := by
    refine .product productAt ?_ ?_
    · have optionalSchema : optionalValue.schema = optional := by
        unfold optionalValue
        cases cancelled <;> rfl
      change [primary, optional, failures] = [primaryValue.schema, optionalValue.schema, failures]
      rw [primaryValueTyped.2, optionalSchema]
    · intro child member
      rcases List.mem_cons.mp member with equal | member
      · cases equal; exact primaryValueTyped.1
      · rcases List.mem_cons.mp member with equal | member
        · cases equal; exact optionalTyped
        · cases List.mem_singleton.mp member; exact failuresTyped
  cases primaryIs : exit.primary with
  | normal original =>
    simp only [primaryIs, pure, Except.pure, Except.bind, Except.ok.injEq] at accepted
    cases accepted
    exact finish _ (primaryTyped _ (by simp [primaryIs, pure, Except.pure]))
  | failure original =>
    simp only [primaryIs, pure, Except.pure, Except.bind, Except.ok.injEq] at accepted
    cases accepted
    exact finish _ (primaryTyped _ (by simp [primaryIs, pure, Except.pure]))
  | cancellation =>
    simp only [primaryIs] at accepted
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨value, valueAt, _, rfl, rfl⟩ := accepted
    apply finish _
    apply primaryTyped
    simp only [primaryIs, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq]
    exact ⟨value, valueAt, rfl⟩
  | abandoned =>
    simp only [primaryIs, pure, Except.pure, Except.bind, Except.ok.injEq] at accepted
    cases accepted
    exact finish _ (primaryTyped _ (by simp [primaryIs, pure, Except.pure]))

end BoundaryV2.Profile.Source.Machine
