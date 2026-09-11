import BoundaryV2.ProgramMapLaws

namespace BoundaryV2.Profile.Target.Canonical

def LiteralDistinct (program : Program) (order : List Reference) : Prop :=
  (orderOf order .constant).Pairwise (fun left right => program.constants[left]? ≠ program.constants[right]?)

theorem literalDistinct_append (program : Program) (order : List Reference) (reference : Reference)
    (distinct : LiteralDistinct program order) (existsRecord : (nodeReferences program reference).isSome = true)
    (freshLiteral : interned program order reference ≠ true) : LiteralDistinct program (order ++ [reference]) := by
  by_cases constant : reference.kind = .constant
  · obtain ⟨literal, atLiteral⟩ : ∃ literal, program.constants[reference.index]? = some literal := by
      simpa only [nodeReferences, constant, Option.isSome_map, Option.isSome_iff_exists] using existsRecord
    have absent : ∀ old ∈ orderOf order .constant, program.constants[old]? ≠ some literal := by
      intro old member same
      apply freshLiteral
      simp only [interned, constant, beq_self_eq_true, Bool.true_and, atLiteral, Option.any_some]
      exact List.any_eq_true.mpr ⟨old, member, by simp [same]⟩
    have orderEq : orderOf (order ++ [reference]) .constant = orderOf order .constant ++ [reference.index] := by
      simp [orderOf, constant]
    unfold LiteralDistinct
    rw [orderEq, List.pairwise_append]
    refine ⟨distinct, by simp, ?_⟩
    intro old member right rightMember
    simp only [List.mem_singleton] at rightMember
    subst right
    simpa only [atLiteral] using absent old member
  · simpa [LiteralDistinct, orderOf, constant] using distinct

theorem walk_preserves_literal_distinct (program : Program) (remaining pending order found : List Reference)
    (distinct : LiteralDistinct program order)
    (accepted : walk program remaining pending order = some found) : LiteralDistinct program found := by
  induction remaining, pending, order using walk.induct program generalizing found with
  | case1 remaining order =>
    simp only [walk, Option.some.injEq] at accepted
    subst found
    exact distinct
  | case2 remaining order reference tail missing => simp only [walk, missing] at accepted; cases accepted
  | case3 remaining order reference tail children record region ih =>
    simp only [walk, record, region, ↓reduceIte] at accepted
    apply ih found (accepted := accepted)
    split
    · exact distinct
    · have notConstant : reference.kind ≠ .constant := by simp only [beq_iff_eq] at region; simp [region]
      simpa [LiteralDistinct, orderOf, notConstant] using distinct
  | case4 remaining order reference tail children record region fresh duplicate ih =>
    simp only [walk, record, region, fresh, duplicate, ↓reduceIte] at accepted
    exact ih found distinct accepted
  | case5 remaining order reference tail children record region fresh notDuplicate ih =>
    simp only [walk, record, region, fresh, notDuplicate] at accepted
    exact ih found (literalDistinct_append program order reference distinct (by simp [record]) notDuplicate) accepted
  | case6 remaining order reference tail children record region visited ih =>
    simp only [walk, record, region, visited] at accepted
    exact ih found distinct accepted

theorem discovery_constants_distinct (program : Program) (found : List Reference)
    (accepted : discover program = some found) : LiteralDistinct program found :=
  walk_preserves_literal_distinct program _ _ [] found (by simp [LiteralDistinct, orderOf]) accepted

theorem canonical_constants_distinct (program : Program) (accepted : check program = true) :
    (List.range program.constants.length).Pairwise (fun left right => program.constants[left]? ≠ program.constants[right]?) := by
  obtain ⟨order, found, numbered⟩ := (check_exact program).mp accepted
  have distinct := discovery_constants_distinct program order found
  simpa only [LiteralDistinct, numbered .constant, count] using distinct

end BoundaryV2.Profile.Target.Canonical
