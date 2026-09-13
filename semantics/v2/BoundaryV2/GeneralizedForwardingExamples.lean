import BoundaryV2.GeneralizedProgramObservations
import BoundaryV2.GeneralizedProgramExamples

namespace BoundaryV2.Generalized.Examples

def outerChoiceClauses : Target.Clauses signature algebra [] .choose .deep [] (.leaf .boolean) .unit :=
  .cons Operation.choice .linear (.push .unit .ret) .nil

def collidingForwardingStack : Target.Stack signature algebra [] (.leaf .boolean) .unit :=
  .push (.handler .choose .deep ⟨8⟩ (.load .here .ret) .nil .nil)
    (.push (.handler .choose .deep ⟨8⟩ (.push .unit .ret) outerChoiceClauses .nil) .done)

/-- The previous nearest-only check misses the outer matching operation. -/
theorem nearest_nonhandling_frame_is_insufficient :
    ¬ Target.Handles (signature := signature) (algebra := algebra) Operation.choice ⟨8⟩ collidingForwardingStack := by
  rintro ⟨mode, context, body, answer, returned, clauses, bindings, inside, outside, selected, member⟩
  simp only [collidingForwardingStack, Target.select, if_true] at selected
  cases selected
  cases member

theorem colliding_forwarding_stack_is_not_external :
    ¬ Target.HeadObservation (signature := signature) (algebra := algebra)
      (.requested Operation.choice ⟨8⟩ (.datum .unit) .nil collidingForwardingStack)
      (.requested Operation.choice ⟨8⟩ (.datum .unit) .nil collidingForwardingStack) := by
  intro observed
  cases observed with
  | requested forward =>
    cases forward with
    | different effect mode identity returned clauses bindings different tail => exact different rfl
    | unhandled mode returned clauses bindings absent tail =>
      cases tail with
      | different effect mode identity returned clauses bindings different tail => exact different rfl
      | unhandled mode returned clauses bindings absent tail =>
        exact absent (by simp [outerChoiceClauses, Target.Clauses.operations])

def validForwardingStack : Target.Stack signature algebra [] (.leaf .boolean) .unit :=
  .push (.handler .choose .deep ⟨8⟩ (.load .here .ret) .nil .nil)
    (.push (.handler .choose .deep ⟨9⟩ (.push .unit .ret) outerChoiceClauses .nil) .done)

theorem unlisted_operation_still_forwards_through_distinct_handlers :
    Target.HeadObservation (signature := signature) (algebra := algebra)
      (.requested Operation.choice ⟨8⟩ (.datum .unit) .nil validForwardingStack)
      (.requested Operation.choice ⟨8⟩ (.datum .unit) .nil validForwardingStack) :=
  .requested (.unhandled (signature := signature) (algebra := algebra) (program := [])
    (operation := Operation.choice) (attachment := ⟨8⟩) .deep (.load .here .ret) .nil .nil (by simp [Target.Clauses.operations])
    (.different (signature := signature) (algebra := algebra) (program := [])
      (operation := Operation.choice) (attachment := ⟨8⟩) Effect.choose .deep ⟨9⟩ (.push .unit .ret) outerChoiceClauses .nil (by decide) .done))

def mismatchedForwardingStack : Target.Stack signature algebra [] (.leaf .text) (.leaf .text) :=
  .push (.handler .choose .deep ⟨8⟩ (.load .here .ret) .nil .nil) .done

theorem incompatible_nominal_family_is_not_external :
    ¬ Target.HeadObservation (signature := signature) (algebra := algebra)
      (.requested Operation.text ⟨8⟩ (.datum (.leaf true)) .nil mismatchedForwardingStack)
      (.requested Operation.text ⟨8⟩ (.datum (.leaf true)) .nil mismatchedForwardingStack) := by
  intro observed
  cases observed with
  | requested forward =>
    cases forward with
    | different effect mode identity returned clauses bindings different tail => exact different rfl

theorem whole_open_closure_observation_reflects_to_source :
    ∃ sourceObservation, Source.Observes (.nil : Source.Definitions signature algebra [])
      (.evaluate (.apply textClosure textArguments) textBindings) sourceObservation ∧
      Defunctionalization.ObservationRelated sourceObservation textTargetObservation :=
  Defunctionalization.ordinary_observation_reflected .nil (.evaluate (.apply textClosure textArguments) textBindings .done)
    target_captured_closure_observes_open_effect

theorem whole_nested_failure_observation_reflects_to_source :
    ∃ sourceObservation, Source.Observes (.nil : Source.Definitions signature algebra [])
      (.evaluate ordinaryFailureProgram .nil) sourceObservation ∧
      Defunctionalization.ObservationRelated sourceObservation (.failed .overflow) := by
  obtain ⟨count, run⟩ := general_simulation_preserves_nested_failure
  exact Defunctionalization.ordinary_observation_reflected .nil (.evaluate ordinaryFailureProgram .nil .done) ⟨count, _, run, .failed⟩

end BoundaryV2.Generalized.Examples
