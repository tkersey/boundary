import BoundaryV2.GeneralizedSourceDisposalExecution
import BoundaryV2.GeneralizedDisposalExamples

namespace BoundaryV2.Generalized.Examples.SourceDisposal

open Defunctionalization

def initial : Source.State signature algebra [] (.leaf .integer) :=
  ⟨⟨disposalSourceStore, disposalSourceOutside.plug (.evaluate (.dispose (.reference .here)) disposalBindings)⟩, [], []⟩
def targetInitial : Target.State signature algebra [] (.leaf .integer) :=
  ⟨⟨disposalTargetStore, .code (computation (.dispose (.reference .here))) (environment disposalBindings) .nil disposalTargetOutside⟩, [], []⟩
def start : Source.DisposalStart signature algebra [] (.leaf .integer) :=
  ⟨disposalSourceAfter, [], [], ⟨disposeShape, disposalSourceFuture⟩, disposalSourceOutside⟩
def abandoned : ExitInfo Fault String := ⟨.abandoned, [], none⟩
def normal : ExitInfo Fault String := ⟨.normal, [], none⟩
def bindings : Source.RuntimeEnvironment signature algebra [] [.exit] := .cons (.exit abandoned) .nil
def tail : Source.Context signature algebra [] (.leaf .boolean) .unit :=
  .push (.bindAuthored disposalReturn .nil) .done
def frames (body : Source.Program signature algebra [] .unit) : Source.CleanupProgress signature algebra [] .unit :=
  .running (.reenter ⟨⟨disposalSourceAfter, body⟩, [], []⟩ normal)
def running : Source.Program signature algebra [] .unit := tail.plug (.cleaning ⟨7⟩ none abandoned (.evaluate disposalCleanup bindings))
def innerYield : Source.Program signature algebra [] .unit :=
  tail.plug (.cleaning ⟨7⟩ none abandoned (.yielded (.evaluate (.returnValue (.datum .unit)) bindings)))
def wrappedYield : Source.Program signature algebra [] .unit :=
  tail.plug (.yielded (.cleaning ⟨7⟩ none abandoned (.evaluate (.returnValue (.datum .unit)) bindings)))
def future : Source.Program signature algebra [] .unit :=
  tail.plug (.cleaning ⟨7⟩ none abandoned (.evaluate (.returnValue (.datum .unit)) bindings))
def yielded : Source.ExitResolution signature algebra [] .unit := .reenter ⟨⟨disposalSourceAfter, .yielded future⟩, [], []⟩ normal
def cleaned : Source.Program signature algebra [] .unit := tail.plug (.cleaning ⟨7⟩ none abandoned (.returned (.datum .unit)))
def completed : Source.ExitRuntime signature algebra [] := ⟨⟨7⟩, .returned, disposalSourceAfter, [], [], abandoned⟩
def progress (state : Source.ControlProgress signature algebra [] .unit) : Source.DisposalProgress signature algebra [] (.leaf .integer) :=
  .disposing ⟨.unit, state, disposalSourceOutside⟩
def resolved : Source.ExitResolution signature algebra [] (.leaf .integer) :=
  .reenter ⟨⟨disposalSourceAfter, disposalSourceOutside.plug (.returned (.datum .unit))⟩, [], []⟩ normal

theorem source_authored_disposal_runs_its_yielding_cleanup :
    Source.DisposalRun (.nil : Source.Definitions signature algebra []) (.evaluating initial) 12 (.resolved resolved) := by
  refine .cons (middle := .disposing start.begin) (.enter authored_dispose_has_corresponding_owned_entry.1) ?_
  refine .cons (middle := progress (.frames ⟨0⟩ (frames running))) (.dispose (.frames .beginUnwind)) ?_
  refine .cons (middle := progress (.frames ⟨0⟩ (frames innerYield)))
    (.dispose (.frames (.execute ((Source.Step.cleaningStep Source.Step.yield).in_state_context rfl tail disposalSourceAfter [] [])))) ?_
  refine .cons (middle := progress (.frames ⟨0⟩ (frames wrappedYield)))
    (.dispose (.frames (.execute (Source.Step.cleaningYield.in_state_context rfl tail disposalSourceAfter [] [])))) ?_
  refine .cons (middle := progress (.frames ⟨0⟩ (.running yielded)))
    (.dispose (.frames (.execute (.cell (.ordinary .bindYield))))) ?_
  refine .cons (middle := progress (.frames ⟨0⟩ (.parked yielded))) (.dispose (.frames .parkYield)) ?_
  refine .cons (middle := progress (.frames ⟨0⟩ (frames future))) (.dispose (.frames .continueYield)) ?_
  refine .cons (middle := progress (.frames ⟨0⟩ (frames cleaned)))
    (.dispose (.frames (.execute ((Source.Step.cleaningStep (Source.Step.returnValue rfl)).in_state_context rfl tail disposalSourceAfter [] [])))) ?_
  refine .cons (middle := progress (.frames ⟨0⟩ (.running (.unwind completed tail))))
    (.dispose (.frames (Source.CleanupStep.returned (signature := signature) (algebra := algebra)
      (outcome := .exiting abandoned) rfl))) ?_
  refine .cons (middle := progress (.frames ⟨0⟩ (.running (.unwind completed .done)))) (.dispose (.frames .unwindBind)) ?_
  refine .cons (middle := progress (.complete completed)) (.dispose .unwindDone) ?_
  exact .cons (.finish rfl) .refl

theorem authored_disposal_has_the_same_target_continuation :
    ∃ count targetAfter, Target.DisposalRun (.nil : Target.Definitions signature algebra [])
      (.evaluating targetInitial) count targetAfter ∧ DisposalProgressRelated (.resolved resolved) targetAfter := by
  have future : ResumptionRelated disposalSourceFuture disposalTargetFuture :=
    ⟨rfl, .push (.protection ⟨7⟩ disposalCleanup .nil) (.push (.bind disposalReturn .nil) .done)⟩
  have stores : ControlHeapRelated disposalSourceStore disposalTargetStore :=
    ⟨rfl, .cons ⟨rfl, rfl, rfl, .same future⟩ .nil, .nil⟩
  have outside : ContextRelated signature algebra [] disposalSourceOutside disposalTargetOutside := .push (.bind disposalCaller .nil) .done
  have initialRelated : ExecutionStateRelated initial targetInitial :=
    ⟨stores, rfl, rfl, outside.close_program (.evaluate (.dispose (.reference .here)) disposalBindings _)⟩
  exact finite_authored_disposal_preserved (.nil : Source.Definitions signature algebra [])
    source_authored_disposal_runs_its_yielding_cleanup (.evaluating initialRelated)

theorem yielding_disposal_retains_its_caller_and_consumed_authority :
    Source.Disposal.finish ⟨.unit, .frames ⟨0⟩ (.parked yielded), disposalSourceOutside⟩ = none ∧
    Source.Disposal.finish ⟨.unit, .complete completed, disposalSourceOutside⟩ = some resolved ∧
    disposalSourceAfter.fields.spent = [⟨100⟩] ∧
    UseScope.inventory disposalSourceAfter.fields = [⟨900⟩] := ⟨rfl, rfl, rfl, rfl⟩

def callerState : Source.State signature algebra [] (.leaf .integer) :=
  ⟨⟨disposalSourceAfter, disposalSourceOutside.plug (.returned (.datum .unit))⟩, [], []⟩
def callerFinal : Source.State signature algebra [] (.leaf .integer) :=
  ⟨⟨disposalSourceAfter, .returned (.datum (.leaf 42))⟩, [], []⟩

theorem source_disposal_returns_to_its_integer_caller :
    Source.StateObserves (.nil : Source.Definitions signature algebra []) callerState callerFinal
      (.returned (.datum (.leaf 42))) := by
  refine ⟨2, .cons (.cell (.ordinary .bindValue)) (.cons (.cell (.ordinary (.returnValue rfl))) .refl), .returned⟩

theorem source_and_target_disposal_continue_through_the_original_caller :
    ∃ count targetCaller targetFinal targetObservation,
      Target.DisposalRun (.nil : Target.Definitions signature algebra []) (.evaluating targetInitial) count
        (.resolved (.reenter targetCaller normal)) ∧
      Target.StateObserves (.nil : Target.Definitions signature algebra []) targetCaller targetFinal targetObservation ∧
      StateObservationRelated callerFinal targetFinal (.returned (.datum (.leaf 42))) targetObservation := by
  obtain ⟨count, targetAfter, run, related⟩ := authored_disposal_has_the_same_target_continuation
  cases related with
  | resolved resolution =>
    cases resolution with
    | reenter states =>
      obtain ⟨final, observation, observed, matched⟩ := stateful_observation_preserved
        (.nil : Source.Definitions signature algebra []) states source_disposal_returns_to_its_integer_caller
      exact ⟨count, _, final, observation, run, observed, matched⟩

end BoundaryV2.Generalized.Examples.SourceDisposal
