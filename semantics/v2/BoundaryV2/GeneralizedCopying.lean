import BoundaryV2.GeneralizedCells

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {Body : List (TypeOf signature) → TypeOf signature → Type}

def Datum.copyable : Datum (Effect := signature.Effect) algebra type → Bool
  | .leaf _ | .unit | .capability _ | .region _ | .borrowed _ _ => true
  | .resource _ _ _ => false
  | .pair first second => first.copyable && second.copyable
  | .left value | .right value => value.copyable

/- This value permission checks actual captures, not just a use-mode label.
Referenced template validity and borrowed lifetimes remain obligations of their
respective owners; this predicate does not grant permission to retain a borrow. -/
mutual
  def Value.copyable : {type : TypeOf signature} → Value signature algebra Body type → Bool
    | _, .datum datum => datum.copyable
    | _, .pair first second => first.copyable && second.copyable
    | _, .left value | _, .right value => value.copyable
    | .computation use _ _, .closure _ captured authority =>
      (use == .reusable || use == .multi) && authority.isNone && captured.copyable
    | .continuation _ use _ _ _, .continuation _ authority => use == .multi && authority.isNone
    | _, .package _ _ _ => false
    | _, .cell _ _ | _, .exit _ => true

  def Environment.copyable : {types : List (TypeOf signature)} → Environment signature algebra Body types → Bool
    | _, .nil => true
    | _, .cons value rest => value.copyable && rest.copyable
end

theorem Datum.copyable_has_no_owner (datum : Datum (Effect := signature.Effect) algebra type)
    (allowed : datum.copyable = true) : datum.owningField.tokens = [] := by
  induction datum <;> simp_all [Datum.copyable, Datum.owningField, UseScope.Field.tokens, UseScope.tokens]

private theorem copyable_owner_bound (bound : Nat) :
    (∀ {type} (value : Value signature algebra Body type), sizeOf value < bound →
      value.copyable = true → value.owningField.tokens = []) ∧
    (∀ {types} (values : Environment signature algebra Body types), sizeOf values < bound →
      values.copyable = true → UseScope.tokens values.owningFields = []) := by
  induction bound with
  | zero => constructor <;> intros <;> omega
  | succ bound induction =>
    constructor
    · intro type value sized allowed
      cases value with
      | datum datum => exact datum.copyable_has_no_owner allowed
      | pair first second =>
        have both := Bool.and_eq_true_iff.mp allowed
        have left := induction.1 first (by simp_all; omega) both.1
        have right := induction.1 second (by simp_all; omega) both.2
        simp only [Value.owningField, UseScope.Field.tokens, UseScope.tokens, left, right, List.nil_append]
      | left value | right value => exact induction.1 value (by simp_all; omega) allowed
      | closure body captured authority =>
        cases authority with
        | none =>
          have captures : captured.copyable = true := (Bool.and_eq_true_iff.mp allowed).2
          have empty := induction.2 captured (by simp_all; omega) captures
          simpa only [Value.owningField, authorityFields, Option.toList_none, List.map_nil, List.nil_append,
            UseScope.Field.tokens, UseScope.tokens, List.append_nil] using empty
        | some authority => simp [Value.copyable] at allowed
      | continuation identity authority =>
        cases authority with
        | none => rfl
        | some authority => simp [Value.copyable] at allowed
      | package token owner content => contradiction
      | cell identity region | exit information => rfl
    · intro types values sized allowed
      cases values with
      | nil => rfl
      | cons value rest =>
        have both := Bool.and_eq_true_iff.mp allowed
        have first := induction.1 value (by simp_all; omega) both.1
        have tail := induction.2 rest (by simp_all; omega) both.2
        simp only [Environment.owningFields, UseScope.tokens, first, tail, List.nil_append]

theorem Value.copyable_has_no_owner {type : TypeOf signature} (value : Value signature algebra Body type)
    (allowed : value.copyable = true) : value.owningField.tokens = [] :=
  (copyable_owner_bound (sizeOf value + 1)).1 value (by omega) allowed

theorem Environment.copyable_has_no_owner {types : List (TypeOf signature)} (values : Environment signature algebra Body types)
    (allowed : values.copyable = true) : UseScope.tokens values.owningFields = [] :=
  (copyable_owner_bound (sizeOf values + 1)).2 values (by omega) allowed

namespace Cells

def readCopy [DecidableEq (TypeOf signature)] (identity : Id .cell) (region : Id .region) (type : TypeOf signature)
    (cells : Cells signature algebra Body) : Option (Value signature algebra Body type) :=
  (read identity region type cells).filter Value.copyable

def writeCopy [DecidableEq (TypeOf signature)] (identity : Id .cell) (region : Id .region)
    (value : Value signature algebra Body type) (cells : Cells signature algebra Body) : Option (Cells signature algebra Body) :=
  if value.copyable then
    (exchange identity region value cells).bind fun (old, after) => if old.copyable then some after else none
  else none

theorem copied_read_has_no_owner [DecidableEq (TypeOf signature)]
    {cells : Cells signature algebra Body} {value : Value signature algebra Body type}
    (accepted : readCopy identity region type cells = some value) : value.owningField.tokens = [] := by
  obtain ⟨_, allowed⟩ := Option.filter_eq_some_iff.mp accepted
  exact value.copyable_has_no_owner allowed

theorem write_copy_preserves_other_cells [DecidableEq (TypeOf signature)]
    {cells after : Cells signature algebra Body} {value : Value signature algebra Body type}
    (accepted : writeCopy identity region value cells = some after) (different : other ≠ identity) :
    lookup other after = lookup other cells := by
  unfold writeCopy at accepted
  split at accepted
  · obtain ⟨⟨old, result⟩, exchanged, accepted⟩ := Option.bind_eq_some_iff.mp accepted
    dsimp only at accepted
    by_cases allowed : old.copyable = true
    · simp only [if_pos allowed, Option.some.injEq] at accepted
      cases accepted
      exact exchange_preserves_other_lookup exchanged different
    · simp only [if_neg allowed] at accepted
      contradiction
  · contradiction

theorem write_copy_preserves_ownership_inventory [DecidableEq (TypeOf signature)]
    {cells after : Cells signature algebra Body} {value : Value signature algebra Body type}
    (accepted : writeCopy identity region value cells = some after) :
    UseScope.tokens (fields after) = UseScope.tokens (fields cells) := by
  unfold writeCopy at accepted
  split at accepted
  · rename_i newAllowed
    obtain ⟨⟨old, result⟩, exchanged, accepted⟩ := Option.bind_eq_some_iff.mp accepted
    dsimp only at accepted
    by_cases oldAllowed : old.copyable = true
    · simp only [if_pos oldAllowed, Option.some.injEq] at accepted
      cases accepted
      exact exchange_without_owners_preserves_inventory exchanged
        (value.copyable_has_no_owner newAllowed) (old.copyable_has_no_owner oldAllowed)
    · simp only [if_neg oldAllowed] at accepted
      contradiction
  · contradiction

end Cells
end BoundaryV2.Generalized
