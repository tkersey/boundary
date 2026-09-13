import BoundaryV2.GeneralizedSourceExecution

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

mutual
  def Source.Expression.containsClosure : Source.Expression signature algebra program context type → Bool
    | .lambda _ _ => true
    | .pair first second => first.containsClosure || second.containsClosure
    | .first operand | .second operand | .left operand | .right operand => operand.containsClosure
    | .primitive _ inputs => inputs.containsClosure
    | .datum _ | .reference _ => false

  def Source.Arguments.containsClosure : Source.Arguments signature algebra program context types → Bool
    | .nil => false
    | .cons first rest => first.containsClosure || rest.containsClosure
end

/-- Closure-producing operands require the owning evaluator even when a later
operand fails. A ready application additionally requires its consumption handoff. -/
def Source.Program.needsOwnershipStep : Source.Program signature algebra program result → Bool
  | .evaluate body bindings => body.operandPrefix.arguments.containsClosure || match body with
    | .apply function arguments => ((Source.Arguments.cons function arguments).evaluate bindings).isOk
    | _ => false
  | .bind body _ | .handler _ _ _ _ _ _ body | .region _ body | .protection _ _ _ body => body.needsOwnershipStep
  | .returned _ | .failed _ | .yielded _ | .request _ _ _ _ _ => false

def Target.Code.needsOwnershipStep : Target.Code signature algebra program context operands result → Bool
  | .callClosure _ | .close _ _ => true
  | _ => false

def Target.Configuration.needsOwnershipStep : Target.Configuration signature algebra program result → Bool
  | .code body _ _ _ => body.needsOwnershipStep
  | .returned _ _ | .failed _ _ | .yielded _ | .requested _ _ _ _ _ => false

theorem Source.Frame.computation_entry_flag
    (frame : Source.Frame signature algebra program input result) (body : Source.Program signature algebra program input) :
    (frame.plug body).needsOwnershipStep = body.needsOwnershipStep := by cases frame <;> rfl

theorem Source.Context.computation_entry_flag
    (outside : Source.Context signature algebra program input result) (body : Source.Program signature algebra program input) :
    (outside.plug body).needsOwnershipStep = body.needsOwnershipStep := by
  cases outside with
  | done => rfl
  | push frame rest => exact (rest.computation_entry_flag (frame.plug body)).trans (frame.computation_entry_flag body)
termination_by outside.length
decreasing_by simp_all [Source.Context.length]

theorem Source.ready_application_requires_handoff
    (function : Source.Expression signature algebra program context (.computation use parameters answer))
    (arguments : Source.Arguments signature algebra program context parameters)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (ready : (Source.Arguments.cons function arguments).evaluate bindings = .ok values) :
    (Source.Program.evaluate (.apply function arguments) bindings).needsOwnershipStep = true := by
  simp only [Source.Program.needsOwnershipStep, ready, Except.isOk, Except.toBool, Bool.or_true]

end BoundaryV2.Generalized
