import BoundaryV2.GeneralizedExecutionRelocation
import BoundaryV2.GeneralizedExit

namespace BoundaryV2.Generalized.ExitComposition

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

def Location.relocate (relocation : UseScope.Relocation) : Location → Location
  | .active => .active
  | .captured identity => .captured (relocation.name .control identity)
  | .parked => .parked

def Cleanup.relocate (relocation : UseScope.Relocation) (cleanup : Cleanup signature algebra program) : Cleanup signature algebra program :=
  ⟨cleanup.context, cleanup.body.relocate relocation, Target.relocateEnvironment relocation cleanup.environment⟩

def Phase.relocate (relocation : UseScope.Relocation) : Phase signature algebra program → Phase signature algebra program
  | .pending cleanup => .pending (cleanup.relocate relocation)
  | .running cursor location => .running (cursor.relocate relocation) (location.relocate relocation)
  | .finished outcome => .finished outcome

def Obligation.relocate (relocation : UseScope.Relocation) (obligation : Obligation signature algebra program) : Obligation signature algebra program :=
  ⟨relocation.name .obligation obligation.id, obligation.phase.relocate relocation,
    UseScope.relocateFields relocation obligation.fields, obligation.exit⟩

theorem pending_protections_relocate (relocation : UseScope.Relocation)
    (future : Target.Stack signature algebra program input result) :
    pendingProtections (future.relocate relocation) = (pendingProtections future).map (relocation.name .obligation) := by
  induction future with
  | done => rfl
  | push frame rest induction => cases frame <;>
      simp only [Target.Stack.relocate, Target.Frame.relocate, pendingProtections, List.map_cons, induction]

theorem cursor_protections_relocate (relocation : UseScope.Relocation) (cursor : Cursor signature algebra program) :
    cursorProtections (cursor.relocate relocation) = (cursorProtections cursor).map (relocation.name .obligation) := by
  induction cursor with
  | code body bindings values future | returned value future | requested operation attachment payload bodies future | failed fault future =>
    exact pending_protections_relocate relocation future
  | yielded next induction => exact induction

theorem relocation_preserves_initiation_right (relocation : UseScope.Relocation) (phase : Phase signature algebra program) :
    (phase.relocate relocation).right = phase.right := by cases phase <;> rfl

theorem relocation_commutes_with_cancellation (relocation : UseScope.Relocation) (reason : algebra.Reason)
    (obligation : Obligation signature algebra program) :
    (cancel reason obligation).relocate relocation = cancel reason (obligation.relocate relocation) := rfl

theorem Step.relocate (relocation : UseScope.Relocation)
    (step : Step (table : Target.Definitions signature algebra program) before initiations after) :
    Step (Target.relocateDefinitions relocation table) (before.relocate relocation) initiations (after.relocate relocation) := by
  cases step with
  | begin => exact .begin
  | execute step => exact .execute (step.relocate relocation)
  | capture => exact .capture
  | reattach => exact .reattach
  | park => exact .park
  | parkYield => exact .parkYield
  | continueYield => exact .continueYield
  | response => exact .response
  | cancelled => exact .cancelled
  | returned => exact .returned
  | failed => exact .failed
  | abandoned clear =>
    apply Step.abandoned
    simp only [cursor_protections_relocate, clear, List.map_nil]

/-- The actual running cleanup cursor relocates with its capture location and
held fields. Relocation preserves every lifecycle transition and initiation count;
it cannot turn a captured or parked cleanup back into a pending initializer. -/
theorem Steps.relocate (relocation : UseScope.Relocation)
    (steps : Steps (table : Target.Definitions signature algebra program) before initiations after) :
    Steps (Target.relocateDefinitions relocation table) (before.relocate relocation) initiations (after.relocate relocation) := by
  induction steps with
  | refl => exact .refl
  | cons step tail induction => exact .cons (step.relocate relocation) induction

end BoundaryV2.Generalized.ExitComposition
