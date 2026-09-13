import BoundaryV2.GeneralizedUnwinding
import BoundaryV2.GeneralizedStatefulCleanupExamples

namespace BoundaryV2.Generalized.Examples

def unwindStore : Target.ControlHeap signature algebra [] := ⟨⟨[], [], []⟩, [], []⟩
def unwindCells := Defunctionalization.cells liveIntegerSourceCells
def cancellingExit : ExitInfo Fault String := ⟨.cancelled, [], some "stop"⟩

def pendingFailingCleanup (identity : Id .obligation) (exit : ExitInfo Fault String) : ExitComposition.Runtime signature algebra [] :=
  ⟨identity, .pending ⟨[], .fault .overflow, .nil⟩, unwindStore, unwindCells, [⟨1⟩], exit⟩

def finishedFailingCleanup (identity : Id .obligation) (exit : ExitInfo Fault String) : ExitComposition.Runtime signature algebra [] :=
  { pendingFailingCleanup identity exit with phase := .finished (.failed .overflow), exit := exit.cleanupFailure .overflow }

theorem failing_cleanup_keeps_the_current_exit (identity : Id .obligation) (exit : ExitInfo Fault String) :
    ExitComposition.RuntimeSteps (.nil : Target.Definitions signature algebra []) (pendingFailingCleanup identity exit) 1
      (finishedFailingCleanup identity exit) := by
  let started : ExitComposition.Runtime signature algebra [] :=
    ⟨identity, .running (.code (.fault .overflow) (.cons (.exit exit) .nil) .nil .done) .active,
      unwindStore, unwindCells, [⟨1⟩], exit⟩
  let faulted : ExitComposition.Runtime signature algebra [] :=
    { started with phase := .running (.failed .overflow .done) .active }
  have first : ExitComposition.RuntimeStep (.nil : Target.Definitions signature algebra []) (pendingFailingCleanup identity exit) 1 started :=
    .lifecycle .begin
  have second : ExitComposition.RuntimeStep (.nil : Target.Definitions signature algebra []) started 0 faulted :=
    .execute (Target.ExecutionStep.cell (signature := signature) (algebra := algebra) (.ordinary .fault))
  have last : ExitComposition.RuntimeStep (.nil : Target.Definitions signature algebra []) faulted 0 (finishedFailingCleanup identity exit) :=
    .lifecycle .failed
  exact .cons first (.cons second (.cons last .refl))

def outerUnwindStack : Target.Stack signature algebra [] .unit .unit :=
  .push (.returnTo (.enter (.fault .overflow) : Target.Code signature algebra [] [] [.unit] .unit) .nil .nil)
    (.push (.handler .text .deep ⟨8⟩ (.fault .overflow) .nil .nil)
      (.push (.protection ⟨2⟩ (.fault .overflow) .nil) .done))

def innerUnwindStack : Target.Stack signature algebra [] .unit .unit :=
  .push (.protection ⟨1⟩ (.fault .overflow) .nil) outerUnwindStack

def initialUnwindRuntime : ExitComposition.Runtime signature algebra [] :=
  ⟨⟨0⟩, .finished .abandoned, unwindStore, unwindCells, [⟨1⟩], cancellingExit⟩

def firstUnwindFinished := finishedFailingCleanup ⟨1⟩ cancellingExit
def secondUnwindFinished := finishedFailingCleanup ⟨2⟩ firstUnwindFinished.exit

/-- The ordinary return code and handler return clause both fail if executed.
Unwinding skips them and records only the two actual cleanup failures. -/
theorem cancellation_runs_inner_then_outer_cleanup :
    ExitComposition.UnwindSteps (.nil : Target.Definitions signature algebra [])
      (.seeking initialUnwindRuntime innerUnwindStack) [⟨1⟩, ⟨2⟩] (.complete secondUnwindFinished) ∧
    secondUnwindFinished.exit = ⟨.cancelled, [.overflow, .overflow], some "stop"⟩ ∧
    secondUnwindFinished.cells = unwindCells := by
  have inner : ExitComposition.UnwindSteps (.nil : Target.Definitions signature algebra [])
      (.cleaning ⟨pendingFailingCleanup ⟨1⟩ cancellingExit, .unwind outerUnwindStack⟩) []
      (.seeking firstUnwindFinished outerUnwindStack) :=
    ExitComposition.run_selected_cleanup outerUnwindStack (failing_cleanup_keeps_the_current_exit ⟨1⟩ cancellingExit) rfl (by intro impossible; cases impossible)
  have outer : ExitComposition.UnwindSteps (.nil : Target.Definitions signature algebra [])
      (.cleaning ⟨pendingFailingCleanup ⟨2⟩ firstUnwindFinished.exit, .unwind (.done : Target.Stack signature algebra [] .unit .unit)⟩) []
      (.seeking secondUnwindFinished (.done : Target.Stack signature algebra [] .unit .unit)) :=
    ExitComposition.run_selected_cleanup .done (failing_cleanup_keeps_the_current_exit ⟨2⟩ firstUnwindFinished.exit) rfl (by intro impossible; cases impossible)
  have afterInner : ExitComposition.UnwindSteps (.nil : Target.Definitions signature algebra [])
      (.seeking firstUnwindFinished outerUnwindStack) [⟨2⟩] (.complete secondUnwindFinished) :=
    ExitComposition.UnwindSteps.cons (signature := signature) (algebra := algebra)
      (.select (by intro impossible; cases impossible) rfl) (outer.trans (.cons (.complete rfl) .refl))
  exact ⟨ExitComposition.UnwindSteps.cons (signature := signature) (algebra := algebra)
    (.select (by intro impossible; cases impossible) rfl) (inner.trans afterInner), rfl, rfl⟩

def regionSeparatedStack : Target.Stack signature algebra [] .unit .unit :=
  .push (.region ⟨1⟩) (.push (.protection ⟨2⟩ (.fault .overflow) .nil) .done)

theorem unwinding_hands_a_region_to_its_close_operation :
    ExitComposition.followUnwind firstUnwindFinished regionSeparatedStack =
      .region ⟨1⟩ firstUnwindFinished (.push (.protection ⟨2⟩ (.fault .overflow) .nil) .done) ∧
    firstUnwindFinished.liveRegions = [⟨1⟩] := ⟨rfl, rfl⟩

def sourceUnwindStack : Source.Context signature algebra [] .unit .unit :=
  .push (.bindAuthored (.fail .overflow : Source.Computation signature algebra [] [.unit] .unit) .nil)
    (.push (.handler .text .deep ⟨8⟩ (.fail .overflow) .nil .nil)
      (.push (.protection ⟨2⟩ (.fail .overflow) .nil) .done))

theorem source_and_target_choose_the_same_outer_cleanup :
    Defunctionalization.UnwindBoundaryRelated (Source.unwindBoundary sourceUnwindStack)
      (Target.unwindBoundary outerUnwindStack) := by
  have related : Defunctionalization.ContextRelated signature algebra [] sourceUnwindStack outerUnwindStack :=
    .push (Defunctionalization.FrameRelated.bind (signature := signature) (algebra := algebra) (.fail .overflow) .nil)
      (.push (Defunctionalization.FrameRelated.handler (signature := signature) (algebra := algebra) .text .deep ⟨8⟩ (.fail .overflow) .nil .nil)
        (.push (Defunctionalization.FrameRelated.protection (signature := signature) (algebra := algebra) ⟨2⟩ (.fail .overflow) .nil) .done))
  exact Defunctionalization.unwind_boundary_corresponds related

theorem completed_cancellation_selects_the_next_cleanup :
    ExitComposition.followUnwindResolution (.unwind firstUnwindFinished outerUnwindStack) =
      some (.cleanup ⟨pendingFailingCleanup ⟨2⟩ firstUnwindFinished.exit,
        .unwind (.done : Target.Stack signature algebra [] .unit .unit)⟩) := rfl

theorem failure_propagation_preserves_prior_cleanup_failures :
    let exit : ExitInfo Fault String := ⟨.failure .overflow, [.overflow], some "first"⟩
    let first : ExitComposition.Resolution signature algebra [] .unit :=
      .reenter ⟨⟨unwindStore, .failed .overflow outerUnwindStack⟩, unwindCells, [⟨1⟩]⟩ exit
    (ExitComposition.advanceFailedResolution first).bind ExitComposition.advanceFailedResolution =
      some (.reenter ⟨⟨unwindStore, .failed .overflow (.push (.protection ⟨2⟩ (.fault .overflow) .nil) .done)⟩,
        unwindCells, [⟨1⟩]⟩ exit) := rfl

end BoundaryV2.Generalized.Examples
