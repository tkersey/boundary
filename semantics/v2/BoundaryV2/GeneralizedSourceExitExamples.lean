import BoundaryV2.GeneralizedExitSimulation
import BoundaryV2.GeneralizedCleanupContextExamples

namespace BoundaryV2.Generalized.Examples.SourceExit

open Defunctionalization

def fields : UseScope.State := ⟨[.owned ⟨900⟩ (.lexical ⟨0⟩ 1), .owned ⟨901⟩ (.lexical ⟨0⟩ 2)], [], []⟩
def sourceStore : Source.ControlHeap signature algebra [] := ⟨fields, [], []⟩
def targetStore : Target.ControlHeap signature algebra [] := ⟨fields, [], []⟩
def originalExit : ExitInfo Fault String := ⟨.failure Fault.overflow, [], none⟩
def normal : ExitInfo Fault String := ⟨.normal, [], none⟩
def cleanup : Source.Computation signature algebra [] [.exit] .unit := .yieldThen (.fail Fault.overflow)
def sourceBindings : Source.RuntimeEnvironment signature algebra [] [.exit] := .cons (.exit originalExit) .nil

def sourceBefore : Source.State signature algebra [] (.leaf .text) :=
  ⟨⟨sourceStore, CleanupContext.sourceOutside.plug (.protection ⟨7⟩ cleanup .nil (.failed Fault.overflow))⟩, [], []⟩
def targetBefore : Target.State signature algebra [] (.leaf .text) :=
  ⟨⟨targetStore, .failed Fault.overflow (.push (.protection ⟨7⟩ (computation cleanup) .nil) CleanupContext.outside)⟩, [], []⟩
def sourceStarted : Source.State signature algebra [] (.leaf .text) :=
  ⟨⟨sourceStore, CleanupContext.sourceOutside.plug
    (.cleaning ⟨7⟩ none originalExit (.evaluate cleanup sourceBindings))⟩, [], []⟩
def sourceInnerYield : Source.State signature algebra [] (.leaf .text) :=
  ⟨⟨sourceStore, CleanupContext.sourceOutside.plug
    (.cleaning ⟨7⟩ none originalExit (.yielded (.evaluate (.fail Fault.overflow) sourceBindings)))⟩, [], []⟩
def sourceWrappedYield : Source.State signature algebra [] (.leaf .text) :=
  ⟨⟨sourceStore, CleanupContext.sourceOutside.plug
    (.yielded (.cleaning ⟨7⟩ none originalExit (.evaluate (.fail Fault.overflow) sourceBindings)))⟩, [], []⟩
def sourceFuture : Source.Program signature algebra [] (.leaf .text) :=
  CleanupContext.sourceOutside.plug (.cleaning ⟨7⟩ none originalExit (.evaluate (.fail Fault.overflow) sourceBindings))
def sourceFinal : Source.State signature algebra [] (.leaf .text) := ⟨⟨sourceStore, .yielded sourceFuture⟩, [], []⟩

theorem initial_states_retain_independent_source_and_target_contexts : ExecutionStateRelated sourceBefore targetBefore := by
  have outside : ContextRelated signature algebra [] CleanupContext.sourceOutside CleanupContext.outside :=
    .push (.handler Effect.choose .deep ⟨8⟩ CleanupContext.normalReturn CleanupContext.sourceClauses .nil) .done
  exact ⟨⟨rfl, .nil, .nil⟩, rfl, rfl, outside.close_program (.protection ⟨7⟩ cleanup .nil (ProgramRelated.failed (signature := signature) (algebra := algebra) Fault.overflow _))⟩

theorem source_failure_cleanup_yields_under_its_actual_handler :
    Source.CleanupSteps (.nil : Source.Definitions signature algebra [])
      (.running (.reenter sourceBefore originalExit)) 4 (.running (.reenter sourceFinal normal)) := by
  refine .cons (middle := .running (.reenter sourceStarted normal)) .beginFailure ?_
  refine .cons (middle := .running (.reenter sourceInnerYield normal))
    (.execute ((Source.Step.cleaningStep Source.Step.yield).in_state_context rfl CleanupContext.sourceOutside sourceStore [] [])) ?_
  refine .cons (middle := .running (.reenter sourceWrappedYield normal))
    (.execute (Source.Step.cleaningYield.in_state_context rfl CleanupContext.sourceOutside sourceStore [] [])) ?_
  exact Source.CleanupSteps.of_execution
    (CleanupContext.sourceOutside.forward_yield_state (.nil : Source.Definitions signature algebra [])
      (.cleaning ⟨7⟩ none originalExit (.evaluate (.fail Fault.overflow) sourceBindings)) sourceStore [] []) normal

/-- The source oracle here is the higher-order source derivation above. Its
pending future, current owning fields, and original cleanup exit are preserved. -/
theorem source_cleanup_yield_has_a_related_target_future :
    ∃ count targetFinal targetObservation,
      ExitComposition.CleanupFrameSteps (.nil : Target.Definitions signature algebra [])
        (.running (.reenter targetBefore originalExit)) count (.running (.reenter targetFinal normal)) ∧
      Target.HeadObservation targetFinal.control.configuration targetObservation ∧
      StateObservationRelated sourceFinal targetFinal (.yielded sourceFuture) targetObservation :=
  cleanup_observation_preserved (.nil : Source.Definitions signature algebra [])
    (.running (.reenter initial_states_retain_independent_source_and_target_contexts))
    source_failure_cleanup_yields_under_its_actual_handler .yielded

def owned : Source.RuntimeValue signature algebra [] (.resource ⟨77⟩) :=
  .datum (.resource ⟨3⟩ ⟨900⟩ (.lexical ⟨0⟩ 1))
def ownerCaller : Source.Context signature algebra [] (.resource ⟨77⟩) .unit :=
  .push (.bindAuthored (.returnValue (.datum .unit)) .nil) .done
def targetOwnerCaller : Target.Stack signature algebra [] (.resource ⟨77⟩) .unit :=
  .push (.returnTo (.enter (.push .unit .ret)) .nil .nil) .done
def failedOwned : Source.State signature algebra [] .unit :=
  ⟨⟨sourceStore, ownerCaller.plug (.cleaning ⟨7⟩ (some owned) normal (.failed Fault.overflow))⟩, [], []⟩
def targetFailedOwned : Target.State signature algebra [] .unit :=
  ⟨⟨targetStore, .failed Fault.overflow (.push (.returnTo .ret (.nil : Target.RuntimeEnvironment signature algebra [] []) .nil)
    (.push (.cleanupReturn ⟨7⟩ (some (value owned)) normal) targetOwnerCaller))⟩, [], []⟩
def ownedExit : ExitInfo Fault String := ⟨.failure Fault.overflow, [Fault.overflow], none⟩
def sourceOwnedDisposal : Source.CleanupDisposal signature algebra [] .unit :=
  ⟨_, owned, ⟨⟨7⟩, .failed Fault.overflow, sourceStore, [], [], ownedExit⟩, ownerCaller⟩

theorem owned_saved_result_survives_administrative_target_frames :
    ∃ count targetAfter, 0 < count ∧
      ExitComposition.CleanupFrameSteps (.nil : Target.Definitions signature algebra [])
        (.running (.reenter targetFailedOwned normal)) count targetAfter ∧
      CleanupProgressRelated (.disposing sourceOwnedDisposal) targetAfter := by
  have outside : ContextRelated signature algebra [] ownerCaller targetOwnerCaller :=
    .push (.bind (.returnValue (.datum .unit)) .nil) .done
  have matching : ExecutionStateRelated failedOwned targetFailedOwned :=
    ⟨⟨rfl, .nil, .nil⟩, rfl, rfl, outside.close_program
      (.cleaning ⟨7⟩ (some owned) normal
        (.passthrough (.nil : Source.RuntimeEnvironment signature algebra [] []) (ProgramRelated.failed (signature := signature) (algebra := algebra) Fault.overflow _)))⟩
  exact failed_cleanup_preserved (.nil : Source.Definitions signature algebra []) ⟨7⟩ (some owned) Fault.overflow normal normal
    sourceStore [] [] ownerCaller matching rfl

def consumedStore : Source.ControlHeap signature algebra [] :=
  ⟨⟨[.owned ⟨901⟩ (.lexical ⟨0⟩ 2)], [], [⟨900⟩]⟩, [], []⟩
def consumedRuntime : Source.ExitRuntime signature algebra [] :=
  ⟨⟨7⟩, .failed Fault.overflow, consumedStore, [], [], ownedExit⟩
def disposedSource : Source.State signature algebra [] .unit :=
  ⟨⟨consumedStore, .failed Fault.overflow⟩, [], []⟩

theorem source_saved_result_disposes_its_real_grant_before_exit :
    Source.CleanupSteps (.nil : Source.Definitions signature algebra [])
      (.running (.reenter failedOwned normal)) 5 (.running (.reenter disposedSource ownedExit)) ∧
    UseScope.inventory consumedStore.fields = [⟨901⟩] ∧ consumedStore.fields.spent = [⟨900⟩] := by
  refine ⟨?_, rfl, rfl⟩
  refine .cons (middle := .disposing sourceOwnedDisposal)
    (Source.CleanupStep.failed (signature := signature) (algebra := algebra)
      (outcome := .disposing owned ownedExit) rfl) ?_
  refine .cons (middle := .values ⟨7⟩ (.failed Fault.overflow) ownerCaller
    (Source.ValueDisposal.start sourceOwnedDisposal.runtime owned))
      (Source.CleanupStep.enterValues (work := sourceOwnedDisposal)) ?_
  refine .cons (middle := .values ⟨7⟩ (.failed Fault.overflow) ownerCaller (.ready consumedRuntime []))
    (.values (Source.ValueDisposalStep.resource (runtime := sourceOwnedDisposal.runtime) rfl)) ?_
  refine .cons (middle := .running (.reenter ⟨⟨consumedStore, ownerCaller.plug (.failed Fault.overflow)⟩, [], []⟩ ownedExit))
    (Source.CleanupStep.finishValues (work := .ready consumedRuntime []) rfl) ?_
  exact .cons (.execute (.cell (.ordinary .bindFault rfl))) .refl

theorem source_disposal_reaches_the_matching_target_failure :
    ∃ count targetFinal targetObservation,
      ExitComposition.CleanupFrameSteps (.nil : Target.Definitions signature algebra [])
        (.running (.reenter targetFailedOwned normal)) count (.running (.reenter targetFinal ownedExit)) ∧
      Target.HeadObservation targetFinal.control.configuration targetObservation ∧
      StateObservationRelated disposedSource targetFinal (.failed Fault.overflow) targetObservation := by
  have outside : ContextRelated signature algebra [] ownerCaller targetOwnerCaller :=
    .push (.bind (.returnValue (.datum .unit)) .nil) .done
  have matching : ExecutionStateRelated failedOwned targetFailedOwned :=
    ⟨⟨rfl, .nil, .nil⟩, rfl, rfl, outside.close_program
      (.cleaning ⟨7⟩ (some owned) normal
        (.passthrough (.nil : Source.RuntimeEnvironment signature algebra [] [])
          (ProgramRelated.failed (signature := signature) (algebra := algebra) Fault.overflow _)))⟩
  exact cleanup_observation_preserved (.nil : Source.Definitions signature algebra []) (.running (.reenter matching))
    source_saved_result_disposes_its_real_grant_before_exit.1 .failed

def cancelledFuture : Source.Program signature algebra [] (.leaf .text) :=
  CleanupContext.sourceOutside.plug (.cleaning ⟨7⟩ none (originalExit.cancel "first")
    (.evaluate (.fail Fault.overflow) sourceBindings))
def cancelledYield : Source.State signature algebra [] (.leaf .text) :=
  ⟨⟨sourceStore, .yielded cancelledFuture⟩, [], []⟩
def continuedCleanup : Source.State signature algebra [] (.leaf .text) :=
  ⟨⟨sourceStore, cancelledFuture⟩, [], []⟩

/-- Capture, repeated cancellation, reattachment, parking, and continuation
retain the original running body and failure. The first reason wins across
both suspended locations, while unrelated owned grants remain untouched. -/
theorem source_captured_cleanup_keeps_its_future_and_first_reason :
    Source.CleanupSteps (.nil : Source.Definitions signature algebra [])
      (.running (.reenter sourceFinal normal)) 7 (.running (.reenter continuedCleanup normal)) ∧
    (originalExit.cancel "first").primary = .failure Fault.overflow ∧
    (originalExit.cancel "first").cancellation = some "first" ∧
    continuedCleanup.control.store.fields = fields := by
  refine ⟨?_, rfl, rfl, rfl⟩
  refine .cons (middle := .captured ⟨44⟩ (.reenter sourceFinal normal)) .captureYield ?_
  refine .cons (middle := .captured ⟨44⟩ (.reenter cancelledYield normal))
    (.cancelCaptured (reason := "first") rfl) ?_
  refine .cons (middle := .captured ⟨44⟩ (.reenter cancelledYield normal))
    (.cancelCaptured (reason := "second") rfl) ?_
  refine .cons (middle := .running (.reenter cancelledYield normal)) .reattach ?_
  refine .cons (middle := .parked (.reenter cancelledYield normal)) .parkYield ?_
  refine .cons (middle := .parked (.reenter cancelledYield normal))
    (.cancelParked (reason := "third") rfl) ?_
  exact .cons .continueYield .refl

theorem captured_source_cleanup_composes_with_target_execution :
    ∃ count targetAfter,
      ExitComposition.CleanupFrameSteps (.nil : Target.Definitions signature algebra [])
        (.running (.reenter targetBefore originalExit)) count targetAfter ∧
      CleanupProgressRelated (.running (.reenter continuedCleanup normal)) targetAfter := by
  obtain ⟨firstCount, middle, first, related⟩ := finite_cleanup_preserved (.nil : Source.Definitions signature algebra [])
    source_failure_cleanup_yields_under_its_actual_handler
    (.running (.reenter initial_states_retain_independent_source_and_target_contexts))
  obtain ⟨secondCount, final, second, joined⟩ := finite_cleanup_preserved (.nil : Source.Definitions signature algebra [])
    source_captured_cleanup_keeps_its_future_and_first_reason.1 related
  exact ⟨firstCount + secondCount, final, first.trans second, joined⟩

end BoundaryV2.Generalized.Examples.SourceExit
