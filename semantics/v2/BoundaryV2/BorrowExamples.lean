import BoundaryV2.BorrowRequirements

namespace BoundaryV2.Profile.Target.Borrow

theorem body_result_retains_ancestry_projection (block : BlockId) (component : Ambient) :
    selectedComponent (.bodyResult block [.field 2, .outer (some component)]) = some component := by
  rfl

/-- No origin summary is needed for an empty Cartesian product. Fresh-owner
validation still runs first, so an empty source trace list cannot hide escape. -/
theorem empty_transfer_needs_no_origin (program : Program) (witness : Witness) (start : BlockId)
    (binding : Binding) (constraint : Constraint) (values owners : Mapped)
    (valueMap : mapInput program binding constraint.value = some values)
    (ownerMap : mapOwner program binding constraint.owner constraint.bound = some owners)
    (safe : mappedConstraintValid values owners = true)
    (empty : values.traces = [] ∨ owners.traces = []) :
    transferConstraint program witness start binding constraint = some [] := by
  rcases empty with empty | empty <;>
    simp [transferConstraint, valueMap, ownerMap, safe, empty]

theorem fresh_escape_rejects_before_empty_transfer (program : Program) (witness : Witness) (start : BlockId)
    (binding : Binding) (constraint : Constraint) (values owners : Mapped)
    (valueMap : mapInput program binding constraint.value = some values)
    (ownerMap : mapOwner program binding constraint.owner constraint.bound = some owners)
    (escape : mappedConstraintValid values owners = false) :
    transferConstraint program witness start binding constraint = none := by
  simp [transferConstraint, valueMap, ownerMap, escape]

end BoundaryV2.Profile.Target.Borrow
