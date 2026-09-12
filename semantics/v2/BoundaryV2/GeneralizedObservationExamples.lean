import BoundaryV2.GeneralizedObservations
import BoundaryV2.GeneralizedExamples

namespace BoundaryV2.Generalized.Examples

def textSourceObservation : Source.Observation signature algebra [] (.leaf .text) :=
  .requested Operation.text ⟨4⟩ (.datum (.leaf true)) .nil .done

def textTargetFuture : Target.Stack signature algebra [] (.leaf .text) (.leaf .text) :=
  .push (.returnTo .ret (Defunctionalization.environment textBodyBindings) .nil) textCaller

def textTargetObservation : Target.Observation signature algebra [] (.leaf .text) :=
  .requested Operation.text ⟨4⟩ (.datum (.leaf true)) .nil textTargetFuture

theorem source_captured_closure_observes_open_effect :
    Source.Observes .nil (.evaluate (.apply textClosure textArguments) textBindings) textSourceObservation := by
  exact ⟨2, _, .cons (.apply rfl rfl) (.cons (.perform rfl rfl rfl) .refl), .requested⟩

theorem target_captured_closure_observes_open_effect :
    Target.Observes .nil
      (.code (Defunctionalization.computation (.apply textClosure textArguments))
        (Defunctionalization.environment textBindings) .nil .done) textTargetObservation := by
  obtain ⟨count, steps⟩ := compiled_captured_closure_opens_effect
  exact ⟨count, _, steps, .requested (Target.no_selection_is_external (signature := signature) (algebra := algebra)
    Operation.text ⟨4⟩ textTargetFuture rfl)⟩

theorem captured_closure_observations_correspond :
    Defunctionalization.ObservationRelated textSourceObservation textTargetObservation :=
  .requested (signature := signature) (algebra := algebra) Operation.text ⟨4⟩ (.datum (.leaf true)) .nil
    (.passthrough textBodyBindings (.passthrough textBindings .done))

/-- The future accepts every typed text response, not just one fixture value. -/
theorem captured_closure_future_accepts_every_text (text : String) :
    Source.Observes (signature := signature) (algebra := algebra) .nil
      (.returned (.datum (.leaf (type := Data.text) text))) (.returned (.datum (.leaf text))) ∧
      Target.Observes .nil (.returned (.datum (.leaf text)) textTargetFuture) (.returned (.datum (.leaf text))) := by
  exact Defunctionalization.empty_future_preserves_every_response
    (signature := signature) (algebra := algebra) .nil
    (.passthrough textBodyBindings (.passthrough textBindings .done)) (.datum (.leaf (type := Data.text) text))

def choiceClauses : Target.Clauses signature algebra [] .choose .deep [] .unit .unit :=
  .cons Operation.choice .linear (.push .unit .ret) .nil

def handledChoiceFuture : Target.Stack signature algebra [] (.leaf .boolean) .unit :=
  cleanupFuture.append (.push (.handler .choose .deep ⟨8⟩ (.load .here .ret) choiceClauses .nil) .done)

theorem choice_has_an_active_handler : Target.Handles (signature := signature) (algebra := algebra)
    Operation.choice ⟨8⟩ handledChoiceFuture := by
  exact ⟨.deep, [], .unit, .unit, .load .here .ret, choiceClauses, .nil, cleanupFuture, .done, rfl, List.mem_cons_self⟩

theorem handled_choice_is_not_an_external_request :
    ¬ Target.HeadObservation (signature := signature) (algebra := algebra)
      (.requested Operation.choice ⟨8⟩ (.datum .unit) .nil handledChoiceFuture)
      (.requested Operation.choice ⟨8⟩ (.datum .unit) .nil handledChoiceFuture) :=
  Target.handled_dispatch_is_not_external choice_has_an_active_handler

end BoundaryV2.Generalized.Examples
