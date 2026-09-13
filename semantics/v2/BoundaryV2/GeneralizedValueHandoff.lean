import BoundaryV2.GeneralizedFields

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {Body : List (TypeOf signature) → TypeOf signature → Type}

/-- Ownership moves only once the value operand is complete. Copyable/plain
values need no owning-field transfer; an owned value moves its actual field. -/
inductive ValueHandoff (value : Value signature algebra Body type) : UseScope.State → UseScope.State → Prop where
  | unowned : value.owningField.tokens = [] → ValueHandoff value fields fields
  | move : ValueHandoff value
      ⟨before ++ value.owningField :: after, retained, spent⟩ ⟨before ++ after, retained, spent⟩

theorem ValueHandoff.conserves_owners (handoff : ValueHandoff value before after) :
    (UseScope.inventory before).Perm (value.owningField.tokens ++ UseScope.inventory after) ∧ after.spent = before.spent := by
  cases handoff with
  | unowned empty => exact ⟨by simp only [empty, List.nil_append]; exact .refl _, rfl⟩
  | move =>
    constructor
    · simp only [UseScope.inventory, UseScope.tokens_append, UseScope.tokens, List.append_assoc]
      simpa only [List.append_assoc] using
        (List.perm_append_comm (l₁ := UseScope.tokens _) (l₂ := value.owningField.tokens)).append_right _
    · rfl

theorem ValueHandoff.map
    {Before After : List (TypeOf signature) → TypeOf signature → Type}
    {value : Value signature algebra Before type}
    (transform : ∀ context type, Before context type → After context type)
    (handoff : ValueHandoff value before after) :
    ValueHandoff (value.map transform) before after := by
  cases handoff with
  | unowned empty => exact .unowned (by simpa only [Value.map_preserves_owning_fields] using empty)
  | move =>
    simpa only [Value.map_preserves_owning_fields] using ValueHandoff.move (value := value.map transform)

end BoundaryV2.Generalized
