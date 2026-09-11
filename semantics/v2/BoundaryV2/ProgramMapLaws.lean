import BoundaryV2.ProgramRemap

namespace BoundaryV2.Profile.Target.Canonical

theorem catalogMap_nominal_bounded (program : Program) (order : List Reference) (kind : Kind)
    (nominal : kind ≠ .constant) (index : Nat) (live : index ∈ orderOf order kind) :
    catalogMap program order kind index < (orderOf order kind).length := by
  simpa [catalogMap, nominal] using List.idxOf_lt_length_of_mem live

/-- Distinct live declarations remain distinct regardless of equal text or
equal structure. Only the explicitly separate literal case admits interning. -/
theorem catalogMap_nominal_injective (program : Program) (order : List Reference) (kind : Kind)
    (nominal : kind ≠ .constant) (left right : Nat)
    (leftLive : left ∈ orderOf order kind) (rightLive : right ∈ orderOf order kind)
    (same : catalogMap program order kind left = catalogMap program order kind right) : left = right := by
  simp only [catalogMap, beq_iff_eq, nominal, ↓reduceIte] at same
  have leftAt : (orderOf order kind)[(orderOf order kind).idxOf left]? = some left := by
    rw [List.getElem?_eq_getElem (List.idxOf_lt_length_of_mem leftLive), List.getElem_idxOf]
  have rightAt : (orderOf order kind)[(orderOf order kind).idxOf right]? = some right := by
    rw [List.getElem?_eq_getElem (List.idxOf_lt_length_of_mem rightLive), List.getElem_idxOf]
  rw [same] at leftAt
  exact Option.some.inj (leftAt.symm.trans rightAt)

theorem catalogMap_equal_literals (program : Program) (order : List Reference) (left right : Nat)
    (same : program.constants[left]? = program.constants[right]?) :
    catalogMap program order .constant left = catalogMap program order .constant right := by
  simp only [catalogMap, beq_self_eq_true, ↓reduceIte, same]

theorem catalogMap_constant_selects_equal_literal (program : Program) (order : List Reference) (index : Nat)
    (present : ∃ old ∈ orderOf order .constant, program.constants[old]? = program.constants[index]?) :
    ∃ old, (orderOf order .constant)[catalogMap program order .constant index]? = some old ∧
      program.constants[old]? = program.constants[index]? := by
  obtain ⟨old, member, same⟩ := present
  have found := List.findIdx?_eq_some_of_exists (p := fun old => program.constants[old]? == program.constants[index]?)
    ⟨old, member, by simp only [same, beq_self_eq_true]⟩
  obtain ⟨bounded, matching, _⟩ := List.findIdx?_eq_some_iff_getElem.mp found
  simp only [catalogMap, beq_self_eq_true, ↓reduceIte, found, Option.getD_some]
  refine ⟨_, List.getElem?_eq_getElem bounded, ?_⟩
  exact eq_of_beq matching

theorem catalogMap_constant_interning_exact (program : Program) (order : List Reference) (left right : Nat)
    (leftPresent : ∃ old ∈ orderOf order .constant, program.constants[old]? = program.constants[left]?)
    (rightPresent : ∃ old ∈ orderOf order .constant, program.constants[old]? = program.constants[right]?) :
    catalogMap program order .constant left = catalogMap program order .constant right ↔
      program.constants[left]? = program.constants[right]? := by
  constructor
  · intro same
    obtain ⟨leftOld, leftAt, leftSame⟩ := catalogMap_constant_selects_equal_literal program order left leftPresent
    obtain ⟨rightOld, rightAt, rightSame⟩ := catalogMap_constant_selects_equal_literal program order right rightPresent
    rw [same] at leftAt
    have oldSame := Option.some.inj (leftAt.symm.trans rightAt)
    subst rightOld
    exact leftSame.symm.trans rightSame
  · exact catalogMap_equal_literals program order left right

end BoundaryV2.Profile.Target.Canonical
