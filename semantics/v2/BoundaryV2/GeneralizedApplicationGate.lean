import BoundaryV2.GeneralizedSourceExecution

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

/-- The pure source model exposes application before ownership is interpreted.
The stateful layer must use a handoff once both operands have succeeded. -/
def Source.Program.needsComputationEntry : Source.Program signature algebra program result → Bool
  | .evaluate body bindings => match body with
    | .apply function arguments => ((Source.Arguments.cons function arguments).evaluate bindings).isOk
    | _ => false
  | .bind body _ | .handler _ _ _ _ _ _ body | .region _ body | .protection _ _ _ body => body.needsComputationEntry
  | .returned _ | .failed _ | .yielded _ | .request _ _ _ _ _ => false

def Target.Code.needsComputationEntry : Target.Code signature algebra program context operands result → Bool
  | .callClosure _ => true
  | _ => false

def Target.Configuration.needsComputationEntry : Target.Configuration signature algebra program result → Bool
  | .code body _ _ _ => body.needsComputationEntry
  | .returned _ _ | .failed _ _ | .yielded _ | .requested _ _ _ _ _ => false

theorem Source.Frame.computation_entry_flag
    (frame : Source.Frame signature algebra program input result) (body : Source.Program signature algebra program input) :
    (frame.plug body).needsComputationEntry = body.needsComputationEntry := by cases frame <;> rfl

theorem Source.Context.computation_entry_flag
    (outside : Source.Context signature algebra program input result) (body : Source.Program signature algebra program input) :
    (outside.plug body).needsComputationEntry = body.needsComputationEntry := by
  cases outside with
  | done => rfl
  | push frame rest => exact (rest.computation_entry_flag (frame.plug body)).trans (frame.computation_entry_flag body)
termination_by outside.length
decreasing_by simp_all [Source.Context.length]

theorem Source.operand_fault_does_not_enter_computation
    (body : Source.Computation signature algebra program context result)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (failed : body.operandPrefix.arguments.evaluate bindings = .error fault) :
    (Source.Program.evaluate body bindings).needsComputationEntry = false := by
  cases body <;> first | rfl | exact congrArg Except.isOk failed

theorem Source.ready_application_requires_handoff
    (function : Source.Expression signature algebra program context (.computation use parameters answer))
    (arguments : Source.Arguments signature algebra program context parameters)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (ready : (Source.Arguments.cons function arguments).evaluate bindings = .ok values) :
    (Source.Program.evaluate (.apply function arguments) bindings).needsComputationEntry = true :=
  congrArg Except.isOk ready

theorem Target.OperandStep.no_computation_entry
    {bindings : Target.RuntimeEnvironment signature algebra program context}
    {before after : Target.Operands signature algebra program context input}
    (step : Target.OperandStep bindings before after) (outside : Target.Stack signature algebra program input result) :
    (Target.Configuration.code before.code bindings before.values outside).needsComputationEntry = false := by
  cases step <;> rfl

end BoundaryV2.Generalized
