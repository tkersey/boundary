import BoundaryV2.GeneralizedDisposalExecution
import BoundaryV2.GeneralizedExamples

namespace BoundaryV2.Generalized.Examples

def disposeView : UseScope.ControlView := ⟨⟨10⟩, ⟨100⟩, .lexical ⟨0⟩ 0⟩
abbrev DisposeType : TypeOf signature := .continuation .shallow .linear .choose (.leaf .boolean) .unit
abbrev disposeShape : ControlShape signature := ⟨.shallow, .choose, .leaf .boolean, .unit⟩
def disposalCleanup : Source.Computation signature algebra [] [.exit] .unit :=
  .yieldThen (.returnValue (.datum .unit))
def disposalReturn : Source.Computation signature algebra [] [.leaf .boolean] .unit := .returnValue (.datum .unit)
def disposalCaller : Source.Computation signature algebra [] [.unit] (.leaf .integer) := .returnValue (.datum (.leaf 42))
def disposalSourceFuture : Source.Resumption signature algebra [] .shallow .choose (.leaf .boolean) .unit :=
  ⟨⟨8⟩, .push (.protection ⟨7⟩ disposalCleanup .nil)
    (.push (.bindAuthored disposalReturn .nil) .done)⟩
def disposalTargetFuture : Target.Resumption signature algebra [] .shallow .choose (.leaf .boolean) .unit :=
  ⟨⟨8⟩, .push (.protection ⟨7⟩ (Defunctionalization.computation disposalCleanup) .nil)
    (.push (.returnTo (.enter (Defunctionalization.computation disposalReturn)) .nil .nil) .done)⟩
def disposalFields : UseScope.State :=
  ⟨[.owned ⟨100⟩ disposeView.owner, .owned ⟨900⟩ (.lexical ⟨0⟩ 1)], [.continuation ⟨10⟩ [.cleanup ⟨7⟩ []]], []⟩
def disposalSourceStore : Source.ControlHeap signature algebra [] :=
  ⟨disposalFields, [⟨⟨10⟩, ⟨100⟩, .linear, ⟨disposeShape, disposalSourceFuture⟩⟩], []⟩
def disposalTargetStore : Target.ControlHeap signature algebra [] :=
  ⟨disposalFields, [⟨⟨10⟩, ⟨100⟩, .linear, ⟨disposeShape, disposalTargetFuture⟩⟩], []⟩
def disposalFinishedFields : UseScope.State :=
  ⟨[.cleanup ⟨7⟩ [], .owned ⟨900⟩ (.lexical ⟨0⟩ 1)], [], [⟨100⟩]⟩
def disposalSourceAfter : Source.ControlHeap signature algebra [] := ⟨disposalFinishedFields, [], []⟩
def disposalTargetAfter : Target.ControlHeap signature algebra [] := ⟨disposalFinishedFields, [], []⟩
def disposalBindings : Source.RuntimeEnvironment signature algebra [] [DisposeType] :=
  .cons (.continuation disposeView.identity (some (disposeView.authority, disposeView.owner))) .nil

def disposalSourceOutside : Source.Context signature algebra [] .unit (.leaf .integer) :=
  .push (.bindAuthored disposalCaller .nil) .done
def disposalTargetOutside : Target.Stack signature algebra [] .unit (.leaf .integer) :=
  .push (.returnTo (.enter (Defunctionalization.computation disposalCaller)) .nil .nil) .done

def disposalTargetStart : Target.DisposalStart signature algebra [] (.leaf .integer) :=
  ⟨disposalTargetAfter, [], [], ⟨disposeShape, disposalTargetFuture⟩,
    .push (.returnTo .ret (Defunctionalization.environment disposalBindings) .nil) disposalTargetOutside⟩

theorem authored_dispose_has_corresponding_owned_entry :
    Source.DisposeEntry (.nil : Source.Definitions signature algebra [])
      ⟨⟨disposalSourceStore, disposalSourceOutside.plug (.evaluate (.dispose (.reference .here)) disposalBindings)⟩, [], []⟩
      ⟨disposalSourceAfter, [], [], ⟨disposeShape, disposalSourceFuture⟩, disposalSourceOutside⟩ ∧
    ∃ start count, 0 < count ∧ Defunctionalization.DisposalStartRelated
      ⟨disposalSourceAfter, [], [], ⟨disposeShape, disposalSourceFuture⟩, disposalSourceOutside⟩ start ∧
      Target.DisposalRun (.nil : Target.Definitions signature algebra [])
        (.evaluating ⟨⟨disposalTargetStore, .code (Defunctionalization.computation (.dispose (.reference .here)))
          (Defunctionalization.environment disposalBindings) .nil disposalTargetOutside⟩, [], []⟩) count (.disposing start.begin) := by
  have future : Defunctionalization.ResumptionRelated disposalSourceFuture disposalTargetFuture :=
    ⟨rfl, .push (.protection ⟨7⟩ disposalCleanup .nil) (.push (.bind disposalReturn .nil) .done)⟩
  exact Defunctionalization.compiled_disposal_entry (signature := signature) (algebra := algebra)
    .nil .linear (.reference .here) disposalBindings disposeView [] []
    (sourceStore := disposalSourceStore) (evaluated := disposalSourceStore) (targetStore := disposalTargetStore) .reference
    ⟨rfl, .cons ⟨rfl, rfl, rfl, .same future⟩ .nil, .nil⟩
    ⟨disposalSourceAfter, ⟨disposeShape, disposalSourceFuture⟩⟩ rfl (.push (.bind disposalCaller .nil) .done)

open ExitComposition

def disposalRuntime (phase : Phase signature algebra []) : Runtime signature algebra [] :=
  ⟨⟨7⟩, phase, disposalTargetAfter, [], [], ⟨.abandoned, [], none⟩⟩
def disposalCompleted := disposalRuntime (.finished .returned)
def disposalTail : Target.Stack signature algebra [] (.leaf .boolean) .unit :=
  .push (.returnTo (.enter (Defunctionalization.computation disposalReturn)) .nil .nil) .done

def disposalRunningFuture : Target.Stack signature algebra [] .unit .unit :=
  .push (.cleanupReturn ⟨7⟩ none ⟨.abandoned, [], none⟩) disposalTail
def disposalCleanupBindings : Target.RuntimeEnvironment signature algebra [] [.exit] :=
  .cons (.exit ⟨.abandoned, [], none⟩) .nil

def disposalFrameState (cursor : Target.Configuration signature algebra [] .unit) :
    CleanupFrameProgress signature algebra [] .unit :=
  .running (.reenter ⟨⟨disposalTargetAfter, cursor⟩, [], []⟩ ⟨.normal, [], none⟩)
def disposalUnwind : CleanupFrameProgress signature algebra [] .unit :=
  .running (.unwind ⟨⟨0⟩, .finished .abandoned, disposalTargetAfter, [], [], ⟨.abandoned, [], none⟩⟩ disposalTargetFuture.future)
def disposalYieldCursor : Target.Configuration signature algebra [] .unit :=
  .yielded (.code (.push .unit .ret) disposalCleanupBindings .nil disposalRunningFuture)
def disposalYieldedFrames : CleanupFrameProgress signature algebra [] .unit :=
  .parked (.reenter ⟨⟨disposalTargetAfter, disposalYieldCursor⟩, [], []⟩ ⟨.normal, [], none⟩)
def disposalCompletedFrames : CleanupFrameProgress signature algebra [] .unit := .running (.unwind disposalCompleted .done)

theorem explicit_disposal_runs_cleanup_through_its_real_yield (retained : List Reference := []) :
    CleanupFrameSteps (.nil : Target.Definitions signature algebra []) disposalUnwind 3 disposalYieldedFrames retained ∧
    CleanupFrameSteps (.nil : Target.Definitions signature algebra []) disposalYieldedFrames 5 disposalCompletedFrames retained := by
  constructor
  · refine .cons (middle := disposalFrameState (.code (Defunctionalization.computation disposalCleanup)
      disposalCleanupBindings .nil disposalRunningFuture)) (.begin rfl) ?_
    refine .cons (middle := disposalFrameState disposalYieldCursor) (.execute (.cell (.ordinary .yield))) ?_
    exact .cons .parkYield .refl
  · refine .cons (middle := disposalFrameState (.code (.push .unit .ret) disposalCleanupBindings .nil disposalRunningFuture)) .continueYield ?_
    refine .cons (middle := disposalFrameState (.code .ret disposalCleanupBindings (.cons (.datum .unit) .nil) disposalRunningFuture))
      (.execute (.cell (.ordinary (.operand .push)))) ?_
    refine .cons (middle := disposalFrameState (.returned (.datum .unit) disposalRunningFuture))
      (.execute (.cell (.ordinary .returned))) ?_
    refine .cons (middle := .running (.unwind disposalCompleted disposalTail))
      (.finish (after := .resolved (.unwind disposalCompleted disposalTail)) rfl) ?_
    exact .cons (middle := disposalCompletedFrames) (.unwind rfl) .refl

theorem yielding_disposal_has_not_returned_to_its_caller :
    Target.Disposal.finish ⟨.unit, .frames ⟨0⟩ disposalYieldedFrames, disposalTargetStart.outside⟩ = none := rfl

def disposedResolution : Resolution signature algebra [] (.leaf .integer) :=
  .reenter ⟨⟨disposalTargetAfter, .returned (.datum .unit) disposalTargetStart.outside⟩, [], []⟩ ⟨.normal, [], none⟩

theorem explicit_disposal_completes_before_returning_unit_to_its_caller :
    Target.DisposalRun (.nil : Target.Definitions signature algebra [])
      (.evaluating ⟨⟨disposalTargetStore, .code (Defunctionalization.computation (.dispose (.reference .here)))
        (Defunctionalization.environment disposalBindings) .nil disposalTargetOutside⟩, [], []⟩) 12
      (.resolved disposedResolution) := by
  have admission : Target.DisposalRun (.nil : Target.Definitions signature algebra [])
      (.evaluating ⟨⟨disposalTargetStore, .code (Defunctionalization.computation (.dispose (.reference .here)))
        (Defunctionalization.environment disposalBindings) .nil disposalTargetOutside⟩, [], []⟩) 2
      (.disposing disposalTargetStart.begin) :=
    .cons (.evaluate (.cell (.ordinary (.operand .load))))
      (.cons (.enter (Target.DisposeEntry.enter (use := .linear) rfl)) .refl)
  have cleanupRun := explicit_disposal_runs_cleanup_through_its_real_yield disposalTargetStart.outside.installationReferences
  have body := Target.DisposalRun.frame_steps ⟨0⟩ disposalTargetStart.outside (cleanupRun.1.trans cleanupRun.2)
  have finish : Target.DisposalRun (.nil : Target.Definitions signature algebra [])
      (.disposing ⟨.unit, .frames ⟨0⟩ disposalCompletedFrames, disposalTargetStart.outside⟩) 2 (.resolved disposedResolution) :=
    .cons (middle := .disposing ⟨.unit, .complete disposalCompleted, disposalTargetStart.outside⟩)
      (.dispose (.finishFrames rfl)) (.cons (.finish rfl) .refl)
  exact (admission.trans body).trans finish

theorem disposed_grant_is_spent_and_other_owner_is_preserved :
    disposalTargetAfter.fields.spent = [⟨100⟩] ∧ UseScope.inventory disposalTargetAfter.fields = [⟨900⟩] ∧
    UseScope.disposeOwned disposeView disposalTargetAfter = none := ⟨rfl, rfl, rfl⟩

theorem disposal_caller_can_continue_after_cleanup :
    Target.ExecutionSteps (.nil : Target.Definitions signature algebra [])
      ⟨⟨disposalTargetAfter, .returned (.datum .unit) disposalTargetStart.outside⟩, [], []⟩ 6
      ⟨⟨disposalTargetAfter, .returned (.datum (.leaf (type := Data.integer) 42)) .done⟩, [], []⟩ := by
  refine .cons (.cell (.ordinary .caller)) ?_
  refine .cons (.cell (.ordinary .returned)) ?_
  refine .cons (.cell (.ordinary .caller)) ?_
  refine .cons (.cell (.ordinary .enter)) ?_
  refine .cons (.cell (.ordinary (.operand .push))) ?_
  exact .single (.cell (.ordinary .returned))

theorem disposal_failure_and_cancellation_keep_their_distinct_outcomes :
    let failed := { disposalCompleted with exit := ⟨.failure .overflow, [.overflow], some "first"⟩ }
    let cancelled := { disposalCompleted with exit := (disposalCompleted.exit.cancel "first").cancel "later" }
    Target.Disposal.finish ⟨.unit, .complete failed, disposalTargetStart.outside⟩ =
      some (.reenter ⟨⟨disposalTargetAfter, .failed .overflow disposalTargetStart.outside⟩, [], []⟩ failed.exit) ∧
    Target.Disposal.finish ⟨.unit, .complete cancelled, disposalTargetStart.outside⟩ =
      some (.unwind cancelled disposalTargetStart.outside) ∧
    cancelled.exit.cancellation = some "first" := ⟨rfl, rfl, rfl⟩

end BoundaryV2.Generalized.Examples
