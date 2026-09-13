import BoundaryV2.GeneralizedTemplates
import BoundaryV2.GeneralizedProgramSimulation
import BoundaryV2.GeneralizedExit

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

/-- Identity return frames do not inspect their saved bindings or operand tail.
Remove them before freezing a future, so dead views do not become captures. -/
def Target.Frame.passthroughEquality : Target.Frame signature algebra program input result → Option (PLift (input = result))
  | .returnTo .ret _ _ => some ⟨rfl⟩
  | _ => none

def Target.Stack.cloneView : Target.Stack signature algebra program input result → Target.Stack signature algebra program input result
  | .done => .done
  | .push frame rest => match frame.passthroughEquality with
    | some same => same.down.symm ▸ rest.cloneView
    | none => .push frame rest.cloneView

theorem Defunctionalization.clone_view_preserves_context_relation
    (related : ContextRelated signature algebra program source target) :
    ContextRelated signature algebra program source target.cloneView := by
  induction related with
  | done => exact .done
  | push frame rest induction =>
    cases frame with
    | bind body bindings => exact .push (.bind body bindings) induction
    | handler effect mode identity returned clauses bindings => exact .push (.handler effect mode identity returned clauses bindings) induction
    | region identity => exact .push (.region identity) induction
    | protection identity cleanup bindings => exact .push (.protection identity cleanup bindings) induction
  | passthrough bindings rest induction => exact induction

theorem Target.clone_view_keeps_pending_protections (future : Target.Stack signature algebra program input result) :
    ExitComposition.pendingProtections future.cloneView = ExitComposition.pendingProtections future := by
  induction future with
  | done => rfl
  | push frame rest induction =>
    cases identified : frame.passthroughEquality with
    | none =>
      simp only [Stack.cloneView, identified]
      cases frame with
      | returnTo | handler | region => exact induction
      | protection => exact congrArg (_ :: ·) induction
    | some same =>
      rcases same with ⟨same⟩
      cases same
      simp only [Stack.cloneView, identified]
      cases frame with
      | returnTo => exact induction
      | handler | region | protection => simp [Frame.passthroughEquality] at identified

end BoundaryV2.Generalized
