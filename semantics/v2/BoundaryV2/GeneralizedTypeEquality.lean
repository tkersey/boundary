import BoundaryV2.GeneralizedTypes

namespace BoundaryV2.Generalized

/- Lean 4.33.1 does not derive DecidableEq for nested inductive types. This
structural comparison handles the parameter lists inside computation types.
Only equality of the signature's data/effect indices is an interface premise.
Constructing Decidable through an iff keeps its decision tag reducible instead
of transporting the entire decision value through propositional equality. -/
mutual
  def typeDecEq [DecidableEq Data] [DecidableEq Effect] (left right : Ty Data Effect) : Decidable (left = right) := by
    cases left <;> cases right
    all_goals first | (apply isFalse; intro equal; cases equal; done) | skip
    case leaf.leaf first second => exact decidable_of_iff' (first = second) (by simp only [Ty.leaf.injEq])
    case unit.unit => exact isTrue rfl
    case product.product a b c d =>
      letI := typeDecEq a c
      letI := typeDecEq b d
      exact decidable_of_iff' (a = c ∧ b = d) (by simp only [Ty.product.injEq])
    case sum.sum a b c d =>
      letI := typeDecEq a c
      letI := typeDecEq b d
      exact decidable_of_iff' (a = c ∧ b = d) (by simp only [Ty.sum.injEq])
    case computation.computation use parameters result nextUse nextParameters nextResult =>
      letI := typesDecEq parameters nextParameters
      letI := typeDecEq result nextResult
      exact decidable_of_iff' (use = nextUse ∧ parameters = nextParameters ∧ result = nextResult)
        (by simp only [Ty.computation.injEq])
    case capability.capability first second => exact decidable_of_iff' (first = second) (by simp only [Ty.capability.injEq])
    case package.package first second =>
      letI := typeDecEq first second
      exact decidable_of_iff' (first = second) (by simp only [Ty.package.injEq])
    case region.region => exact isTrue rfl
    case cell.cell first second =>
      letI := typeDecEq first second
      exact decidable_of_iff' (first = second) (by simp only [Ty.cell.injEq])
    case exit.exit => exact isTrue rfl
    case resource.resource first second => exact decidable_of_iff' (first = second) (by simp only [Ty.resource.injEq])
    case borrowed.borrowed first second => exact decidable_of_iff' (first = second) (by simp only [Ty.borrowed.injEq])
    case continuation.continuation mode use effect input answer nextMode nextUse nextEffect nextInput nextAnswer =>
      letI := typeDecEq input nextInput
      letI := typeDecEq answer nextAnswer
      exact decidable_of_iff' (mode = nextMode ∧ use = nextUse ∧ effect = nextEffect ∧ input = nextInput ∧ answer = nextAnswer)
        (by simp only [Ty.continuation.injEq])
  termination_by sizeOf left

  def typesDecEq [DecidableEq Data] [DecidableEq Effect] (left right : List (Ty Data Effect)) : Decidable (left = right) := by
    cases left with
    | nil => cases right with
      | nil => exact isTrue rfl
      | cons head tail => exact isFalse (by intro equal; cases equal)
    | cons head tail => cases right with
      | nil => exact isFalse (by intro equal; cases equal)
      | cons next rest =>
        letI := typeDecEq head next
        letI := typesDecEq tail rest
        exact decidable_of_iff' (head = next ∧ tail = rest) (by simp only [List.cons.injEq])
  termination_by sizeOf left
end

instance [DecidableEq Data] [DecidableEq Effect] : DecidableEq (Ty Data Effect) := typeDecEq

end BoundaryV2.Generalized
