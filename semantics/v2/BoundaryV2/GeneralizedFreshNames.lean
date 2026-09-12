import BoundaryV2.GeneralizedTypes

namespace BoundaryV2.Generalized.FreshNames

/-- A strict upper bound is computed from actual finite support, including
repeated aliases. It is not supplied as a claim that allocation is correct. -/
def bound (names : List (Id domain)) : Nat :=
  names.foldr (fun name rest => max (name.index + 1) rest) 0

theorem member_below_bound (member : name ∈ names) : name.index < bound names := by
  induction names with
  | nil => contradiction
  | cons first rest induction =>
    rcases List.mem_cons.mp member with rfl | later
    · simp only [bound, List.foldr_cons]
      exact Nat.lt_of_lt_of_le (Nat.lt_succ_self _) (Nat.le_max_left _ _)
    · exact Nat.lt_of_lt_of_le (induction later) (Nat.le_max_right _ _)

/-- All occurrences of a local name receive the same fresh name. External
names remain unchanged; the occurrence lists themselves are never deduplicated. -/
def rename (locals : List (Id domain)) (start : Nat) (name : Id domain) : Id domain :=
  if name ∈ locals then ⟨start + name.index⟩ else name

structure Allocation (domain : Domain) where
  locals : List (Id domain)
  start : Nat
  next : Nat

def allocate (support locals : List (Id domain)) : Allocation domain :=
  ⟨locals, bound support, bound support + bound locals⟩

theorem external_names_unchanged (external : name ∉ locals) : rename locals start name = name := by
  simp only [rename, if_neg external]

theorem local_name_is_fresh (member : name ∈ locals) : start ≤ (rename locals start name).index := by
  simp only [rename, if_pos member]
  omega

theorem local_name_inside_reservation (member : name ∈ locals) :
    (rename locals start name).index < start + bound locals := by
  have bounded := member_below_bound member
  simp only [rename, if_pos member]
  omega

theorem fresh_from_existing_support (member : name ∈ locals) (existing : old ∈ support) :
    rename locals (bound support) name ≠ old := by
  have newLower := local_name_is_fresh (start := bound support) member
  have oldUpper := member_below_bound existing
  intro same
  have equal := congrArg Id.index same
  omega

/-- Injectivity is required on the supported names, not on unused natural
numbers outside the modeled state. This also separates local and external names. -/
theorem injective_on_support (firstSupported : first ∈ support) (secondSupported : second ∈ support)
    (same : rename locals (bound support) first = rename locals (bound support) second) : first = second := by
  by_cases firstLocal : first ∈ locals
  · by_cases secondLocal : second ∈ locals
    · have equal := congrArg Id.index same
      simp only [rename, if_pos firstLocal, if_pos secondLocal] at equal
      have sameIndex : first.index = second.index := Nat.add_left_cancel equal
      cases first
      cases second
      cases sameIndex
      rfl
    · rw [external_names_unchanged secondLocal] at same
      exact False.elim (fresh_from_existing_support firstLocal secondSupported same)
  · by_cases secondLocal : second ∈ locals
    · rw [external_names_unchanged firstLocal] at same
      exact False.elim (fresh_from_existing_support secondLocal firstSupported same.symm)
    · simpa only [external_names_unchanged firstLocal, external_names_unchanged secondLocal] using same

theorem successive_branches_are_disjoint (firstLocal : first ∈ locals) (secondLocal : second ∈ locals)
    (later : start + bound locals ≤ nextStart) :
    rename locals start first ≠ rename locals nextStart second := by
  have earlier := local_name_inside_reservation (start := start) firstLocal
  have following := local_name_is_fresh (start := nextStart) secondLocal
  intro same
  have equal := congrArg Id.index same
  omega

theorem aliases_remain_aliases (same : first = second) : rename locals start first = rename locals start second :=
  congrArg (rename locals start) same

theorem every_repeated_occurrence_is_retained (name : Id domain) :
    [name, name].map (rename locals start) = [rename locals start name, rename locals start name] := rfl

end BoundaryV2.Generalized.FreshNames
