import BoundaryV2.GeneralizedDisposalExamples
import BoundaryV2.GeneralizedValueDisposal

namespace BoundaryV2.Generalized.Examples.NestedDisposal

open ExitComposition

def cleanup : Source.Computation signature algebra [] [.exit] .unit :=
  .protect (.yieldThen (.returnValue (.datum .unit))) (.returnValue (.datum .unit))
def cleanupCode := Defunctionalization.computation cleanup
def innerCode : Target.Code signature algebra [] [.exit, .exit] [] .unit := .yieldThen (.push .unit .ret)
def sourceFuture : Source.Resumption signature algebra [] .shallow .choose (.leaf .boolean) .unit :=
  ⟨⟨8⟩, .push (.protection ⟨7⟩ cleanup .nil) (.push (.bindAuthored disposalReturn .nil) .done)⟩
def targetFuture : Target.Resumption signature algebra [] .shallow .choose (.leaf .boolean) .unit :=
  ⟨⟨8⟩, .push (.protection ⟨7⟩ cleanupCode .nil) disposalTail⟩
def sourceStore : Source.ControlHeap signature algebra [] :=
  { disposalSourceStore with controls := [⟨⟨10⟩, ⟨100⟩, .linear, ⟨disposeShape, sourceFuture⟩⟩] }
def targetStore : Target.ControlHeap signature algebra [] :=
  { disposalTargetStore with controls := [⟨⟨10⟩, ⟨100⟩, .linear, ⟨disposeShape, targetFuture⟩⟩] }
def start : Target.DisposalStart signature algebra [] (.leaf .integer) :=
  { disposalTargetStart with future := ⟨disposeShape, targetFuture⟩ }

theorem authored_nested_dispose_has_corresponding_owned_entry :
    Source.DisposeEntry (.nil : Source.Definitions signature algebra [])
      ⟨⟨sourceStore, disposalSourceOutside.plug (.evaluate (.dispose (.reference .here)) disposalBindings)⟩, [], []⟩
      ⟨disposalSourceAfter, [], [], ⟨disposeShape, sourceFuture⟩, disposalSourceOutside⟩ ∧
    ∃ targetStart count, 0 < count ∧ Defunctionalization.DisposalStartRelated
      ⟨disposalSourceAfter, [], [], ⟨disposeShape, sourceFuture⟩, disposalSourceOutside⟩ targetStart ∧
      Target.DisposalRun (.nil : Target.Definitions signature algebra [])
        (.evaluating ⟨⟨targetStore, .code (Defunctionalization.computation (.dispose (.reference .here)))
          (Defunctionalization.environment disposalBindings) .nil disposalTargetOutside⟩, [], []⟩) count (.disposing targetStart.begin) := by
  have future : Defunctionalization.ResumptionRelated sourceFuture targetFuture :=
    ⟨rfl, .push (.protection ⟨7⟩ cleanup .nil) (.push (.bind disposalReturn .nil) .done)⟩
  exact Defunctionalization.compiled_disposal_entry (signature := signature) (algebra := algebra)
    .nil .linear (.reference .here) disposalBindings disposeView [] []
    (sourceStore := sourceStore) (evaluated := sourceStore) (targetStore := targetStore) .reference
    ⟨rfl, .cons ⟨rfl, rfl, rfl, .same future⟩ .nil, .nil⟩
    ⟨disposalSourceAfter, ⟨disposeShape, sourceFuture⟩⟩ rfl (.push (.bind disposalCaller .nil) .done)

def abandonedExit : ExitInfo Fault String := ⟨.abandoned, [], none⟩
def normalExit : ExitInfo Fault String := ⟨.normal, [], none⟩
def rootBindings : Target.RuntimeEnvironment signature algebra [] [.exit] := .cons (.exit abandonedExit) .nil
def innerBindings : Target.RuntimeEnvironment signature algebra [] [.exit, .exit] := .cons (.exit normalExit) rootBindings
def rootFuture : Target.Stack signature algebra [] .unit .unit := .push (.cleanupReturn ⟨7⟩ none abandonedExit) disposalTail
def rootReturn : Target.Stack signature algebra [] .unit .unit := .push (.returnTo .ret rootBindings .nil) rootFuture
def nestedOutside : Target.Stack signature algebra [] .unit .unit := .push (.protection ⟨8⟩ innerCode rootBindings) rootReturn
def innerFuture : Target.Stack signature algebra [] .unit .unit :=
  .push (.cleanupReturn ⟨8⟩ (some (.datum .unit)) normalExit) rootReturn

def frame (cursor : Target.Configuration signature algebra [] .unit) : CleanupFrameProgress signature algebra [] .unit :=
  .running (.reenter ⟨⟨disposalTargetAfter, cursor⟩, [], []⟩ normalExit)
def root : CleanupFrameProgress signature algebra [] .unit :=
  .running (.unwind ⟨⟨0⟩, .finished .abandoned, disposalTargetAfter, [], [], abandonedExit⟩ targetFuture.future)
def yielded : Target.Configuration signature algebra [] .unit :=
  .yielded (.code (.push .unit .ret) innerBindings .nil innerFuture)
def parked : CleanupFrameProgress signature algebra [] .unit :=
  .parked (.reenter ⟨⟨disposalTargetAfter, yielded⟩, [], []⟩ normalExit)
def finished : CleanupFrameProgress signature algebra [] .unit := .running (.unwind disposalCompleted .done)

/-- The fixture fixes the fresh identity at eight. Each use below computes
this local equality from its actual caller/queue support. -/
theorem nested_cleanup_reaches_its_actual_yield (retained : List Reference)
    (allocation : (⟨8⟩ : Id .obligation) = Target.freshObligation (.nil : Target.Definitions signature algebra [])
      cleanupCode rootBindings .nil rootFuture disposalTargetAfter [] retained) :
    CleanupFrameSteps (.nil : Target.Definitions signature algebra []) root 7 parked retained := by
  refine .cons (middle := frame (.code cleanupCode rootBindings .nil rootFuture)) (.begin rfl) ?_
  refine .cons (middle := frame (.code (.push .unit .ret) rootBindings .nil nestedOutside))
    (.execute (.enterProtection [] (by simpa [cleanupCode, cleanup, Defunctionalization.computation] using allocation))) ?_
  refine .cons (middle := frame (.code .ret rootBindings (.cons (.datum .unit) .nil) nestedOutside))
    (.execute (.cell (.ordinary (.operand .push)))) ?_
  refine .cons (middle := frame (.returned (.datum .unit) nestedOutside)) (.execute (.cell (.ordinary .returned))) ?_
  refine .cons (middle := frame (.code innerCode innerBindings .nil innerFuture)) (.execute (.cell (.ordinary .protectionReturn))) ?_
  refine .cons (middle := frame yielded) (.execute (.cell (.ordinary .yield))) ?_
  exact .cons .parkYield .refl

theorem nested_cleanup_finishes_on_the_live_parent_stack (retained : List Reference := []) :
    CleanupFrameSteps (.nil : Target.Definitions signature algebra []) parked 8 finished retained := by
  refine .cons (middle := frame (.code (.push .unit .ret) innerBindings .nil innerFuture)) .continueYield ?_
  refine .cons (middle := frame (.code .ret innerBindings (.cons (.datum .unit) .nil) innerFuture))
    (.execute (.cell (.ordinary (.operand .push)))) ?_
  refine .cons (middle := frame (.returned (.datum .unit) innerFuture)) (.execute (.cell (.ordinary .returned))) ?_
  refine .cons (middle := frame (.returned (.datum .unit) rootReturn))
    (.finish (after := .resolved (.reenter ⟨⟨disposalTargetAfter, .returned (.datum .unit) rootReturn⟩, [], []⟩ normalExit)) rfl) ?_
  refine .cons (middle := frame (.code .ret rootBindings (.cons (.datum .unit) .nil) rootFuture))
    (.execute (.cell (.ordinary .caller))) ?_
  refine .cons (middle := frame (.returned (.datum .unit) rootFuture)) (.execute (.cell (.ordinary .returned))) ?_
  refine .cons (middle := .running (.unwind disposalCompleted disposalTail))
    (.finish (after := .resolved (.unwind disposalCompleted disposalTail)) rfl) ?_
  exact .cons (middle := finished) (.unwind rfl) .refl

theorem authored_disposal_finishes_nested_cleanup_before_reentering_its_caller :
    Target.DisposalRun (.nil : Target.Definitions signature algebra [])
      (.evaluating ⟨⟨targetStore, .code (Defunctionalization.computation (.dispose (.reference .here)))
        (Defunctionalization.environment disposalBindings) .nil disposalTargetOutside⟩, [], []⟩) 19
      (.resolved disposedResolution) := by
  have admission : Target.DisposalRun (.nil : Target.Definitions signature algebra [])
      (.evaluating ⟨⟨targetStore, .code (Defunctionalization.computation (.dispose (.reference .here)))
        (Defunctionalization.environment disposalBindings) .nil disposalTargetOutside⟩, [], []⟩) 2 (.disposing start.begin) :=
    .cons (.evaluate (.cell (.ordinary (.operand .load)))) (.cons (.enter (Target.DisposeEntry.enter (use := .linear) rfl)) .refl)
  have frames := (nested_cleanup_reaches_its_actual_yield start.outside.installationReferences rfl).trans
    (nested_cleanup_finishes_on_the_live_parent_stack start.outside.installationReferences)
  have body := Target.DisposalRun.frame_steps ⟨0⟩ start.outside frames
  have last : Target.DisposalRun (.nil : Target.Definitions signature algebra [])
      (.disposing ⟨.unit, .frames ⟨0⟩ finished, start.outside⟩) 2 (.resolved disposedResolution) :=
    .cons (middle := .disposing ⟨.unit, .complete disposalCompleted, start.outside⟩)
      (.dispose (.finishFrames rfl)) (.cons (.finish rfl) .refl)
  exact (admission.trans body).trans last

def pendingResource : Target.RuntimeValue signature algebra [] (.resource ⟨77⟩) :=
  .datum (.resource ⟨3⟩ ⟨900⟩ (.lexical ⟨0⟩ 1))
def pendingValues : DisposalValues signature algebra [] := [⟨_, pendingResource⟩]
def allDisposed : Runtime signature algebra [] :=
  { disposalCompleted with store := { disposalCompleted.store with fields := ⟨[.cleanup ⟨7⟩ []], [], [⟨900⟩, ⟨100⟩]⟩ } }

theorem owned_value_disposal_retains_a_visible_nested_yield :
    ValueDisposalSteps (.nil : Target.Definitions signature algebra []) (.control (.frames ⟨0⟩ root) pendingValues) 7
      (.control (.frames ⟨0⟩ parked) pendingValues) ∧
    ValueDisposal.finished (.control (.frames ⟨0⟩ parked) pendingValues) = none ∧
    disposalTargetAfter.fields.spent = [⟨100⟩] ∧ UseScope.inventory disposalTargetAfter.fields = pendingResource.owningField.tokens := by
  have frames := nested_cleanup_reaches_its_actual_yield
    (pendingValues.flatMap (fun value => Target.valueReferences value.snd) ++ []) rfl
  exact ⟨ValueDisposalSteps.of_control pendingValues (ControlProgressSteps.of_frames ⟨0⟩ frames), rfl, rfl, rfl⟩

theorem pending_owned_value_runs_only_after_nested_cleanup_finishes :
    ValueDisposalSteps (.nil : Target.Definitions signature algebra [])
      (.control (.frames ⟨0⟩ parked) pendingValues) 11 (.ready allDisposed []) ∧
      allDisposed.store.fields.spent.reverse = [⟨100⟩, ⟨900⟩] ∧ allDisposed.exit = disposalCompleted.exit := by
  have frames := nested_cleanup_finishes_on_the_live_parent_stack
    (pendingValues.flatMap (fun value => Target.valueReferences value.snd) ++ [])
  have body := ValueDisposalSteps.of_control (retained := []) pendingValues (ControlProgressSteps.of_frames ⟨0⟩ frames)
  have last : ValueDisposalSteps (.nil : Target.Definitions signature algebra [])
      (.control (.frames ⟨0⟩ finished) pendingValues) 3 (.ready allDisposed []) := by
    refine .cons (middle := .control (.complete (answer := .unit) disposalCompleted) pendingValues) (.control (.finishFrames rfl)) ?_
    refine .cons (middle := .ready disposalCompleted pendingValues) .finishControl ?_
    exact .cons (middle := .ready allDisposed []) (.resource rfl) .refl
  exact ⟨body.trans last, rfl, rfl⟩

def answerRuntime : Runtime signature algebra [] :=
  ⟨⟨0⟩, .finished .returned, disposalTargetAfter, [], [], normalExit⟩
def answerConsumed : Runtime signature algebra [] :=
  { answerRuntime with store := { answerRuntime.store with fields := ⟨[.cleanup ⟨7⟩ []], [], [⟨900⟩, ⟨100⟩]⟩ } }
def ownedAnswer : ControlProgress signature algebra [] (.resource ⟨77⟩) :=
  .frames ⟨0⟩ (.running (.reenter ⟨⟨disposalTargetAfter, .returned pendingResource .done⟩, [], []⟩ normalExit))

theorem handler_answer_ownership_is_consumed_before_disposal_returns_unit :
    Target.DisposalRun (.nil : Target.Definitions signature algebra [])
      (.disposing ⟨.resource ⟨77⟩, ownedAnswer, disposalTargetOutside⟩) 4
      (.resolved (.reenter ⟨⟨answerConsumed.store, .returned (.datum .unit) disposalTargetOutside⟩, [], []⟩ normalExit)) := by
  have consume : ControlProgressSteps (.nil : Target.Definitions signature algebra []) ownedAnswer 3
      (.complete answerConsumed) disposalTargetOutside.installationReferences := by
    refine .cons (middle := .returnedValue (ValueDisposal.start answerRuntime pendingResource)) (.finishFrames rfl) ?_
    refine .cons (middle := .returnedValue (.ready answerConsumed [])) (.returnedValue (.resource rfl)) ?_
    exact .cons (middle := .complete answerConsumed) (.finishAnswer rfl) .refl
  exact (Target.DisposalRun.control_steps disposalTargetOutside consume).trans (.cons (.finish rfl) .refl)

end BoundaryV2.Generalized.Examples.NestedDisposal
