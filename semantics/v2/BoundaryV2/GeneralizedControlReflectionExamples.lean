import BoundaryV2.GeneralizedControlReflection
import BoundaryV2.GeneralizedApplicationExamples

namespace BoundaryV2.Generalized.Examples.ControlReflection

def sourceCall : Source.Computation signature algebra [] [OwnedApplicationType] (.leaf .boolean) :=
  .apply (.reference .here) applicationArguments

def before : Target.State signature algebra [] (.leaf .boolean) :=
  ⟨⟨applicationTargetStore, .code (Defunctionalization.computation sourceCall)
    (Defunctionalization.environment applicationBindings) .nil .done⟩, [], []⟩

def caller : Target.Stack signature algebra [] (.leaf .boolean) (.leaf .boolean) :=
  .push (.returnTo .ret (Defunctionalization.environment applicationBindings) .nil) .done

def yielded : Target.State signature algebra [] (.leaf .boolean) :=
  ⟨⟨{ applicationTargetStore with fields := applicationFieldsAfter },
    .yielded (.code (.load .here .ret)
      (Defunctionalization.environment (.cons (.datum (.leaf false)) applicationCaptures)) .nil caller)⟩, [], []⟩

/-- A target-only trace loads a saved owned closure, evaluates its argument,
consumes the actual grant, and suspends inside its body with the caller intact. -/
theorem target_owned_call_and_yield :
    Target.ExecutionSteps (.nil : Target.Definitions signature algebra []) before 4 yielded := by
  refine .cons (.cell (.ordinary (.operand .load))) ?_
  refine .cons (.cell (.ordinary (.operand .push))) ?_
  refine .cons (.control (.application (body := Defunctionalization.computation applicationBody)
    (arguments := .cons (.datum (.leaf false)) .nil) (next := .ret)
    (bindings := Defunctionalization.environment applicationBindings) (values := .nil) (outside := .done)
    (ComputationHandoff.owned (captured := Defunctionalization.environment applicationCaptures)
    .linear ⟨8⟩ applicationOwner [.owned ⟨100⟩ (.lexical ⟨0⟩ 1)] [] [] []))) ?_
  exact .cons (.cell (.ordinary .yield)) .refl

theorem source_call_is_recovered_from_target_run :
    ∃ sourceAfter targetAfter remaining, remaining < 4 ∧
      Source.ExecutionStep (.nil : Source.Definitions signature algebra [])
        ⟨⟨applicationSourceStore, .evaluate sourceCall applicationBindings⟩, [], []⟩ sourceAfter ∧
      Defunctionalization.ExecutionStateRelated sourceAfter targetAfter ∧
      Target.ExecutionSteps (.nil : Target.Definitions signature algebra []) targetAfter remaining yielded :=
  Defunctionalization.applied_computation_step_reflected .nil (.reference .here) applicationArguments applicationBindings [] []
    ⟨rfl, .nil, .nil⟩ .done target_owned_call_and_yield .yielded

theorem target_call_spends_once_and_retains_captured_and_unrelated_owners :
    yielded.control.store.fields.spent = [⟨8⟩] ∧
    UseScope.inventory yielded.control.store.fields = [⟨100⟩, ⟨6⟩] ∧
    ¬ ComputationHandoff applicationCaptures .linear (some (⟨8⟩, applicationOwner)) applicationFieldsAfter later :=
  ⟨rfl, rfl, application_cannot_reuse_a_consumed_grant later⟩

end BoundaryV2.Generalized.Examples.ControlReflection
