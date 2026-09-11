import BoundaryV2.Effects

namespace BoundaryV2.Effects

open Core

def ambientCollisionBody : Flow Expr 0 1 [] .number :=
  .handle ⟨.ref .here, .dispose (.literal (.number 7))⟩
    (.perform 1 (.literal (.number 9)))

theorem colliding_raw_state_satisfies_old_custody :
    (rawInitial ambientCollisionBody #[0].toVector 0).Valid :=
  raw_initial_is_well_owned _ _ _

theorem colliding_raw_state_intercepts_ambient_operation :
    observe (tick Expr.eval (tick Expr.eval (tick Expr.eval
      (rawInitial ambientCollisionBody #[0].toVector 0)))) = some (.returned (.number 7)) := rfl

theorem checked_collision_rejects :
    initialWithSupply? ambientCollisionBody #[0].toVector 0 = none := rfl

theorem derived_supply_preserves_ambient_operation :
    observe (tick Expr.eval (tick Expr.eval (initial ambientCollisionBody #[0].toVector))) =
      some (.request 0 9) := rfl

end BoundaryV2.Effects
