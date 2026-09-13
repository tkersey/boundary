import BoundaryV2.GeneralizedProgramSimulation
import BoundaryV2.GeneralizedObservationExamples

namespace BoundaryV2.Generalized.Examples

def ordinaryFailureProgram : Source.Computation signature algebra [] [] .unit :=
  .bind (input := .unit) (.handle .choose .deep (.yieldThen (.returnValue (.reference .here))) .nil (.fail .overflow))
    (.yieldThen (.returnValue (.datum .unit)))

theorem nested_failure_skips_normal_return_and_caller_work :
    Source.Steps (.nil : Source.Definitions signature algebra []) (.evaluate ordinaryFailureProgram .nil) 5 (.failed .overflow) :=
  .cons .bind (.cons (.bindStep (.handle (attachment := ⟨8⟩)))
    (.cons (.bindStep (.handlerStep .fail)) (.cons (.bindStep .handlerFault) (.cons .bindFault .refl))))

/-- The target run comes from the general simulation, rather than a separately
enumerated target trace. Both skipped clauses contain authored yields. -/
theorem general_simulation_preserves_nested_failure :
    ∃ count, Target.CallSteps (.nil : Target.Definitions signature algebra [])
      (.code (Defunctionalization.computation ordinaryFailureProgram) .nil .nil .done) count (.failed .overflow .done) :=
  Defunctionalization.compiled_finite_fault .nil ordinaryFailureProgram .nil .overflow nested_failure_skips_normal_return_and_caller_work

theorem general_simulation_preserves_open_closure_future :
    ∃ count future, Target.CallSteps (.nil : Target.Definitions signature algebra [])
      (.code (Defunctionalization.computation (.apply textClosure textArguments))
        (Defunctionalization.environment textBindings) .nil .done) count
      (.requested Operation.text ⟨4⟩ (.datum (.leaf true)) .nil future) ∧
      Defunctionalization.ContextRelated signature algebra [] .done future ∧
      ∀ response : Source.RuntimeValue signature algebra [] (.leaf .text),
        Target.Observes .nil (.returned (Defunctionalization.value response) future)
          (.returned (Defunctionalization.value response)) := by
  have source : Source.Steps (.nil : Source.Definitions signature algebra [])
      (.evaluate (.apply textClosure textArguments) textBindings) 2
      (.request Operation.text ⟨4⟩ (.datum (.leaf true)) .nil .done) :=
    .cons (.apply rfl rfl) (.cons (.perform rfl rfl rfl) .refl)
  obtain ⟨count, future, steps, related⟩ := Defunctionalization.compiled_finite_request
    .nil (.apply textClosure textArguments) textBindings Operation.text ⟨4⟩ (.datum (.leaf true)) .nil .done source
  refine ⟨count, future, steps, related, ?_⟩
  intro response
  exact (Defunctionalization.empty_future_preserves_every_response .nil related response).2

def ordinaryYieldProgram : Source.Computation signature algebra [] [] .unit :=
  .bind (.yieldThen (.returnValue (.datum .unit))) (.returnValue (.reference .here))

def ordinaryYieldFuture : Source.Program signature algebra [] .unit :=
  .bind (.evaluate (.returnValue (.datum .unit)) .nil)
    (fun value => .evaluate (.returnValue (.reference .here)) (.cons value .nil))

theorem source_yield_retains_lexical_caller :
    Source.Steps (.nil : Source.Definitions signature algebra []) (.evaluate ordinaryYieldProgram .nil) 3 (.yielded ordinaryYieldFuture) :=
  .cons .bind (.cons (.bindStep .yield) (.cons .bindYield .refl))

theorem source_yield_future_returns :
    Source.Steps (.nil : Source.Definitions signature algebra []) ordinaryYieldFuture 3 (.returned (.datum .unit)) :=
  .cons (.bindStep (.returnValue rfl)) (.cons .bindValue (.cons (.returnValue rfl) .refl))

theorem general_simulation_preserves_yield_and_its_future :
    ∃ beforeCount afterCount future,
      Target.CallSteps (.nil : Target.Definitions signature algebra [])
        (.code (Defunctionalization.computation ordinaryYieldProgram) .nil .nil .done) beforeCount (.yielded future) ∧
      Target.CallSteps (.nil : Target.Definitions signature algebra []) future afterCount (.returned (.datum .unit) .done) := by
  obtain ⟨beforeCount, future, beforeSteps, related⟩ := Defunctionalization.compiled_finite_yield
    .nil ordinaryYieldProgram .nil ordinaryYieldFuture source_yield_retains_lexical_caller
  obtain ⟨afterCount, final, afterSteps, finalRelated⟩ := Defunctionalization.finite_program_steps_simulate
    .nil source_yield_future_returns related
  obtain ⟨drainCount, drain⟩ := finalRelated.returned_drains .nil (.datum .unit) rfl
  exact ⟨beforeCount, afterCount + drainCount, future, beforeSteps, afterSteps.trans drain⟩

end BoundaryV2.Generalized.Examples
