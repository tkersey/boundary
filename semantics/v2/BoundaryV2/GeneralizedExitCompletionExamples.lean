import BoundaryV2.GeneralizedExitCompletion
import BoundaryV2.GeneralizedStatefulCleanupExamples

namespace BoundaryV2.Generalized.Examples

def completionOutside : Target.Stack signature algebra [] (.leaf .boolean) (.leaf .boolean) := .done

def normalExitBefore : Target.State signature algebra [] (.leaf .boolean) :=
  ⟨⟨⟨⟨[], [], []⟩, [], []⟩, .returned (.datum (.leaf true)) (.push (.protection ⟨30⟩ (.push .unit .ret) .nil) completionOutside)⟩,
    Defunctionalization.cells liveIntegerSourceCells, [⟨1⟩]⟩

def normalScope : ExitComposition.ScopeExit signature algebra [] (.leaf .boolean) :=
  ⟨⟨⟨30⟩, .pending ⟨[], .push .unit .ret, .nil⟩, normalExitBefore.control.store, normalExitBefore.cells,
    normalExitBefore.liveRegions, ⟨.normal, [], none⟩⟩, .returned (.datum (.leaf true)) completionOutside⟩

def normalScopeFinished : ExitComposition.Runtime signature algebra [] :=
  { normalScope.cleanup with phase := .finished .returned }

def normalExitAfter : Target.State signature algebra [] (.leaf .boolean) :=
  ⟨⟨normalExitBefore.control.store, .returned (.datum (.leaf true)) completionOutside⟩,
    normalExitBefore.cells, normalExitBefore.liveRegions⟩

theorem completed_protection_returns_to_its_outer_continuation :
    ExitComposition.beginReturnedProtection normalExitBefore = some normalScope ∧
    ExitComposition.RuntimeSteps (.nil : Target.Definitions signature algebra [])
      normalScope.cleanup 1 normalScopeFinished ∧
    ExitComposition.finish ⟨normalScopeFinished, normalScope.resume⟩ =
      some (.reenter normalExitAfter ⟨.normal, [], none⟩) := by
  let started : ExitComposition.Runtime signature algebra [] :=
    ⟨⟨30⟩, .running (.code (.push .unit .ret) (.cons (.exit ⟨.normal, [], none⟩) .nil) .nil .done) .active,
      normalExitBefore.control.store, normalExitBefore.cells, normalExitBefore.liveRegions, ⟨.normal, [], none⟩⟩
  let ready : ExitComposition.Runtime signature algebra [] := { started with phase := .running (.returned (.datum .unit) .done) .active }
  have began : ExitComposition.RuntimeStep (.nil : Target.Definitions signature algebra []) normalScope.cleanup 1 started :=
    .lifecycle .begin
  have executed : Target.ExecutionSteps (.nil : Target.Definitions signature algebra [])
      ⟨⟨started.store, .code (.push .unit .ret) (.cons (.exit started.exit) .nil) .nil .done⟩, started.cells, started.liveRegions⟩ 2
      ⟨⟨started.store, .returned (.datum .unit) .done⟩, started.cells, started.liveRegions⟩ :=
    .cons (.cell (.ordinary (.operand .push))) (.cons (.cell (.ordinary .returned)) .refl)
  have running : ExitComposition.RuntimeSteps (.nil : Target.Definitions signature algebra []) started 0 ready :=
    ExitComposition.stateful_cleanup_execution executed
  have ended : ExitComposition.RuntimeStep (.nil : Target.Definitions signature algebra []) ready 0 normalScopeFinished := .lifecycle .returned
  have run : ExitComposition.RuntimeSteps (.nil : Target.Definitions signature algebra []) normalScope.cleanup 1 normalScopeFinished :=
    .cons began (running.trans (.cons ended .refl))
  exact ⟨rfl, run, rfl⟩

def failedExitBefore : Target.State signature algebra [] (.leaf .boolean) :=
  ⟨⟨writingCleanupPending.store, .failed .overflow
    (.push (.protection ⟨20⟩ (Defunctionalization.computation writingCleanup)
      (Defunctionalization.environment integerCellSourceBindings)) completionOutside)⟩,
    writingCleanupPending.cells, writingCleanupPending.liveRegions⟩

theorem failed_scope_reentry_preserves_cleanup_updates_and_cancellation :
    ExitComposition.beginFailedProtection failedExitBefore [] none =
      some ⟨writingCleanupPending, .unwind completionOutside⟩ ∧
    ExitComposition.RuntimeSteps (.nil : Target.Definitions signature algebra [])
      writingCleanupPending 1 writingCleanupFinished ∧
    ExitComposition.finish ⟨writingCleanupFinished, .unwind completionOutside⟩ =
      some (.reenter ⟨⟨writingCleanupFinished.store, .failed .overflow completionOutside⟩,
        writingCleanupFinished.cells, writingCleanupFinished.liveRegions⟩ writingCleanupFinished.exit) ∧
    writingCleanupFinished.exit.cancellation = some "first" := by
  obtain ⟨run, _, _, _⟩ := captured_cleanup_finishes_without_losing_the_updated_cell
  exact ⟨rfl, run, rfl, rfl⟩

theorem next_scope_keeps_accumulated_cleanup_failures (original first second : Fault) :
    let exit : ExitInfo Fault String := ⟨.failure original, [first], some "first reason"⟩
    let runtime : ExitComposition.Runtime signature algebra [] :=
      ⟨⟨31⟩, .finished (.failed second), ⟨⟨[], [], []⟩, [], []⟩, [], [], exit.cleanupFailure second⟩
    ExitComposition.finish ⟨runtime, .unwind completionOutside⟩ =
      some (.reenter ⟨⟨runtime.store, .failed original completionOutside⟩, [], []⟩
        ⟨.failure original, [first, second], some "first reason"⟩) := rfl

theorem cancellation_and_abandonment_keep_distinct_unwind_states :
    let base := normalScopeFinished
    ExitComposition.finish ⟨{ base with exit := ⟨.cancelled, [], some "stop"⟩ }, .unwind completionOutside⟩ =
      some (.unwind { base with exit := ⟨.cancelled, [], some "stop"⟩ } completionOutside) ∧
    ExitComposition.finish ⟨{ base with phase := .finished .abandoned, exit := ⟨.abandoned, [], none⟩ }, .unwind completionOutside⟩ =
      some (.unwind { base with phase := .finished .abandoned, exit := ⟨.abandoned, [], none⟩ } completionOutside) := ⟨rfl, rfl⟩

end BoundaryV2.Generalized.Examples
