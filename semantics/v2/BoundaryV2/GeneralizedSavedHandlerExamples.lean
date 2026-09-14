import BoundaryV2.GeneralizedFiniteReflection
import BoundaryV2.GeneralizedHandlerExecutionExamples

namespace BoundaryV2.Generalized.Examples.SavedHandler

local instance : DecidableEq (signature.operation .choose) := fun first second => by
  cases first
  cases second
  exact isTrue rfl

/-- This request already owns its saved handler context as continuation data.
The source selector inspects it together with the surrounding syntax context. -/
def saved : Source.Context signature algebra [] (.leaf .boolean) (.leaf .text) :=
  sourceNegateFuture.append (.push (.handler .choose .shallow ⟨8⟩ distinctNormalReturn resumingChoiceClauses textBindings) .done)

def parked : Source.ControlState signature algebra [] (.leaf .text) :=
  ⟨mixedSourceControls, .request Operation.choice ⟨8⟩ (.datum .unit) .nil saved⟩

theorem saved_handler_selects_its_actual_clause : Source.Handles Operation.choice ⟨8⟩ saved := by
  refine ⟨.shallow, _, _, _, distinctNormalReturn, resumingChoiceClauses, textBindings, sourceNegateFuture, .done, rfl, ?_⟩
  simp only [resumingChoiceClauses, Source.Clauses.operations, List.mem_cons, true_or]

theorem saved_request_is_related_before_dispatch :
    Defunctionalization.ExecutionStateRelated ⟨parked, [], []⟩ ⟨targetHandledChoice, [], []⟩ := by
  have futures : Defunctionalization.ContextRelated signature algebra [] saved
      (targetNegateFuture.append (.push (.handler .choose .shallow ⟨8⟩
        (Defunctionalization.computation distinctNormalReturn) (Defunctionalization.clauses resumingChoiceClauses)
        (Defunctionalization.environment textBindings)) .done)) :=
    .push (.bind negateFutureBody textBindings)
      (.push (.handler (signature := signature) (algebra := algebra) .choose .shallow ⟨8⟩ distinctNormalReturn resumingChoiceClauses textBindings) .done)
  refine ⟨mixed_controls_correspond, rfl, rfl, ?_⟩
  simpa only [Target.Stack.append_done, parked, targetHandledChoice, Defunctionalization.value, Defunctionalization.environment, Value.map, Environment.map] using
    Defunctionalization.ProgramRelated.requested (signature := signature) (algebra := algebra) Operation.choice ⟨8⟩ (.datum .unit) .nil futures .done

/-- The general source request rule selects the saved delimiter and uses the
same physical capture operation as the existing syntactic-handler path. -/
theorem saved_handler_dispatches_once :
    Source.OwnedStep (.nil : Source.Definitions signature algebra []) {} parked capturedSourceChoice.state :=
  .handledRequest (signature := signature) (algebra := algebra)
    (around := .done) (saved := saved) (clause := capturedSourceChoice)
    (attachment := ⟨8⟩) (returned := distinctNormalReturn) (clauses := resumingChoiceClauses)
    (bindings := textBindings) (inside := sourceNegateFuture) (outside := .done)
    (operation := Operation.choice) (owner := .lexical ⟨3⟩ 0) (before := []) (captured := [])
    (after := mixedControlFields.active) (partition := rfl) rfl rfl

theorem saved_handler_capture_resume_and_effectful_caller :
    Source.OwnedSteps (.nil : Source.Definitions signature algebra []) {} parked 7
      ⟨sourceAfterCapturedChoice, .request Operation.text ⟨4⟩ (.datum (.leaf false)) .nil .done⟩ ∧
    Target.OwnedSteps (.nil : Target.Definitions signature algebra []) {} targetHandledChoice 17
      ⟨targetAfterCapturedChoice, .requested Operation.text ⟨4⟩ (.datum (.leaf false)) .nil afterChoiceRequestFuture⟩ :=
  ⟨.cons saved_handler_dispatches_once source_captured_choice_resume_and_postprocessing,
    target_handler_capture_resume_and_postprocessing⟩

theorem saved_handled_request_is_not_an_external_opening :
    ¬ Source.HeadObservation parked.computation
      (.requested Operation.choice ⟨8⟩ (.datum .unit) .nil saved) := by
  intro observed
  cases observed with
  | requested forward => exact forward.not_handles saved_handler_selects_its_actual_clause

theorem saved_handler_run_retains_unrelated_owners_and_consumes_once :
    UseScope.inventory targetAfterCapturedChoice.fields = [⟨100⟩, ⟨101⟩] ∧
    UseScope.acquire capturedTargetChoice.view targetAfterCapturedChoice = none := ⟨rfl, rfl⟩

/-- The general finite inverse reconstructs this complete handled execution
from the independent target trace, including the final open request and store. -/
theorem finite_reflection_recovers_saved_handler_execution :
    ∃ sourceFinal sourceObservation,
      Source.StateObserves (.nil : Source.Definitions signature algebra []) ⟨parked, [], []⟩ sourceFinal sourceObservation ∧
      Defunctionalization.StateObservationRelated sourceFinal
        ⟨⟨targetAfterCapturedChoice, .requested Operation.text ⟨4⟩ (.datum (.leaf false)) .nil afterChoiceRequestFuture⟩, [], []⟩
        sourceObservation (.requested Operation.text ⟨4⟩ (.datum (.leaf false)) .nil afterChoiceRequestFuture) ∧
      sourceFinal.control.store.fields = sourceAfterCapturedChoice.fields := by
  have targetRun := target_handler_capture_resume_and_postprocessing.in_execution (retained := []) [] []
  have targetHead : Target.HeadObservation
      (Target.Configuration.requested (signature := signature) (algebra := algebra) Operation.text ⟨4⟩
        (.datum (.leaf false)) .nil afterChoiceRequestFuture)
      (.requested Operation.text ⟨4⟩ (.datum (.leaf false)) .nil afterChoiceRequestFuture) :=
    .requested (.returnTo .ret _ .nil .done)
  obtain ⟨sourceFinal, sourceObservation, sourceRun, matched⟩ :=
    Defunctionalization.stateful_observation_reflected .nil saved_request_is_related_before_dispatch ⟨17, targetRun, targetHead⟩
  exact ⟨sourceFinal, sourceObservation, sourceRun, matched, matched.store.fields⟩

end BoundaryV2.Generalized.Examples.SavedHandler
