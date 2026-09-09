import BoundaryV2.EffectsLowering

namespace BoundaryV2.Effects.Examples

open Core Control

-- These are kernel reductions of closed examples, not native evaluations.
set_option maxRecDepth 10000

def ticks (eval : Evaluator A) : Nat → Machine A outside result → Machine A outside result
  | 0, machine => machine
  | count + 1, machine => ticks eval count (tick eval machine)

def constant (value : Nat) : Expr ctx .number := .literal (.number value)

def nonTailHandler : Mode → Handler Expr [] .number .number
  | .deep => ⟨.add (.ref .here) (constant 10),
      .once .deep (constant 3) (.add (.ref .here) (constant 100))⟩
  | .shallow => ⟨.add (.ref .here) (constant 10),
      .once .shallow (constant 3) (.add (.ref .here) (constant 100))⟩

def nonTail (mode : Mode) : Flow Expr 0 0 [] .number :=
  .handle (nonTailHandler mode)
    (.bind (.perform 0 (constant 0)) (.pure (.add (.ref .here) (constant 1))))

theorem deep_non_tail_applies_return_once :
    observe (ticks Expr.eval 16 (initial (nonTail .deep) #[].toVector 0)) =
      some (.returned (.number 114)) := rfl

theorem shallow_non_tail_omits_original_return :
    observe (ticks Expr.eval 16 (initial (nonTail .shallow) #[].toVector 0)) =
      some (.returned (.number 104)) := rfl

theorem compiled_deep_non_tail :
    observe (ticks evaluateBlock 16 (compileMachine (initial (nonTail .deep) #[].toVector 0))) =
      some (.returned (.number 114)) := rfl

def disposing : Flow Expr 0 0 [] .number :=
  .handle ⟨.add (.ref .here) (constant 100), .dispose (constant 7)⟩ (.perform 0 (constant 0))

theorem operation_clause_answer_bypasses_return :
    observe (ticks Expr.eval 8 (initial disposing #[].toVector 0)) = some (.returned (.number 7)) := rfl

def choiceHandler : Handler Expr [] .number (.product .number .number) :=
  ⟨.pair (.ref .here) (.ref .here),
    .multi .deep [constant 0, constant 1] (.pair (constant 0) (constant 0))
      (.pair (.second (.ref (.there .here))) (.second (.ref .here)))⟩

def incrementAfterChoice : Flow Expr 1 1 [] .number :=
  .bind (.perform 0 (constant 0))
    (.bind (.read 0)
      (.bind (.write 0 (.add (.ref .here) (constant 1))) (.read 0)))

def localState : Flow Expr 0 0 [] (.product .number .number) :=
  .handle choiceHandler (.region (constant 0) incrementAfterChoice)

def sharedState : Flow Expr 0 0 [] (.product .number .number) :=
  .region (constant 0) (.handle choiceHandler incrementAfterChoice)

theorem choice_outside_state_returns_one_one :
    observe (ticks Expr.eval 32 (initial localState #[].toVector 0)) =
      some (.returned (.pair (.number 1) (.number 1))) := rfl

theorem state_outside_choice_returns_one_two :
    observe (ticks Expr.eval 32 (initial sharedState #[].toVector 0)) =
      some (.returned (.pair (.number 1) (.number 2))) := rfl

theorem compiled_state_outside_choice :
    observe (ticks evaluateBlock 32 (compileMachine (initial sharedState #[].toVector 0))) =
      some (.returned (.pair (.number 1) (.number 2))) := rfl

def twoResiduals : Flow Expr 0 1 [] .number :=
  .bind (.perform 0 (constant 41))
    (.bind (.perform 0 (.add (.ref .here) (constant 1)))
      (.pure (.add (.ref .here) (constant 1))))

def residualStart : Machine Expr 0 .number := initial twoResiduals #[7].toVector 8

def residualInputs : List Input := [.internal, .internal, .resume 10,
  .internal, .internal, .internal, .resume 20, .internal, .internal, .internal]

theorem effectful_second_bind_reaches_residual :
    (drive Expr.eval residualStart [.internal, .internal, .resume 10, .internal, .internal, .internal]).map
      (fun pair => observe pair.1) = some (some (.request 7 11)) := rfl

theorem supplied_responses_return_through_both_binds :
    (drive Expr.eval residualStart residualInputs).map (fun pair => observe pair.1) =
      some (some (.returned (.number 21))) := rfl

theorem compiled_residual_script :
    (drive evaluateBlock (compileMachine residualStart) residualInputs).map (fun pair => observe pair.1) =
      some (some (.returned (.number 21))) := rfl

theorem disposal_terminates_pending_ownership :
    (drive Expr.eval residualStart [.internal, .internal, .dispose]).map (fun pair => pair.1.ownership.live) =
      some [] := rfl

theorem transfer_consumes_sender_custody :
    (drive Expr.eval residualStart [.internal, .internal, .transfer]).map (fun pair => pair.1.ownership.live) =
      some [] := rfl

end BoundaryV2.Effects.Examples
