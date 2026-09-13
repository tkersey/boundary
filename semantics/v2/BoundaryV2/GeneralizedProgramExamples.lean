import BoundaryV2.GeneralizedProgramSimulation
import BoundaryV2.GeneralizedComputationReflection
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

theorem observed_closure_run_reflects_a_source_step :
    ∃ sourceAfter targetAfter,
      Source.Step (.nil : Source.Definitions signature algebra []) (.evaluate (.apply textClosure textArguments) textBindings) sourceAfter ∧
      Defunctionalization.ProgramRelated sourceAfter .done targetAfter ∧
      Target.Observes .nil targetAfter textTargetObservation :=
  Defunctionalization.observing_computation_reflects .nil (.apply textClosure textArguments) textBindings .done
    target_captured_closure_observes_open_effect

def reflectedHandler : Source.Computation signature algebra [] [] .unit :=
  .handle .choose .deep (.returnValue (.reference .here)) .nil (.yieldThen (.returnValue (.datum .unit)))

def reflectedHandlerAfter (attachment : Id .attachment) : Target.Configuration signature algebra [] .unit :=
  .code (Defunctionalization.computation (.returnValue (.datum .unit))) (.cons (.datum (.capability (effect := Effect.choose) attachment)) .nil) .nil
    (.push (.handler .choose .deep attachment (.load .here .ret) .nil .nil) (.push (.returnTo .ret .nil .nil) .done))

theorem every_chosen_handler_name_has_a_matching_source_step (attachment : Id .attachment) :
    ∃ sourceAfter targetAfter remaining, remaining < 2 ∧
      Source.Step (.nil : Source.Definitions signature algebra []) (.evaluate reflectedHandler .nil) sourceAfter ∧
      Defunctionalization.ProgramRelated sourceAfter .done targetAfter ∧
      Target.CallSteps .nil targetAfter remaining (.yielded (reflectedHandlerAfter attachment)) := by
  have run : Target.CallSteps (.nil : Target.Definitions signature algebra [])
      (.code (Defunctionalization.computation reflectedHandler) .nil .nil .done) 2 (.yielded (reflectedHandlerAfter attachment)) :=
    .cons (.attach (attachment := attachment)) (.cons .yield .refl)
  exact Defunctionalization.computation_step_reflects .nil reflectedHandler .nil .done run .yielded

end BoundaryV2.Generalized.Examples
