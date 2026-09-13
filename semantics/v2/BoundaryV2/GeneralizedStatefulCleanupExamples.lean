import BoundaryV2.GeneralizedStatefulCleanup
import BoundaryV2.GeneralizedOwnedCellExamples
import BoundaryV2.GeneralizedProtectionExamples

namespace BoundaryV2.Generalized.Examples

def statefulCleanupExit : ExitInfo Fault String := ⟨.failure .overflow, [], none⟩

def writingCleanup : Source.Computation signature algebra [] [.exit, .cell (.leaf .integer)] .unit :=
  .cellWrite (.reference (.there .here)) (.datum (.leaf 9))

def writingCleanupBindings : Source.RuntimeEnvironment signature algebra [] [.exit, .cell (.leaf .integer)] :=
  .cons (.exit statefulCleanupExit) integerCellSourceBindings

def writingCleanupPending : ExitComposition.Runtime signature algebra [] :=
  ⟨⟨20⟩, .pending ⟨[.cell (.leaf .integer)], Defunctionalization.computation writingCleanup,
    Defunctionalization.environment integerCellSourceBindings⟩, ⟨⟨[], [], []⟩, [], []⟩,
    Defunctionalization.cells liveIntegerSourceCells, [⟨1⟩], statefulCleanupExit⟩

def writingCleanupReady : ExitComposition.Runtime signature algebra [] :=
  ⟨⟨20⟩, .running (.returned (.datum .unit) .done) .active, ⟨⟨[], [], []⟩, [], []⟩,
    Defunctionalization.cells writtenIntegerCells, [⟨1⟩], statefulCleanupExit⟩

def writingCleanupStarted : ExitComposition.Runtime signature algebra [] :=
  ⟨⟨20⟩, .running (.code (Defunctionalization.computation writingCleanup)
    (Defunctionalization.environment writingCleanupBindings) .nil .done) .active, ⟨⟨[], [], []⟩, [], []⟩,
    Defunctionalization.cells liveIntegerSourceCells, [⟨1⟩], statefulCleanupExit⟩

theorem cleanup_execution_retains_its_cell_write :
    ExitComposition.RuntimeSteps (.nil : Target.Definitions signature algebra []) writingCleanupPending 1 writingCleanupReady := by
  have written : Cells.writeCopy (signature := signature) (algebra := algebra) ⟨3⟩ ⟨1⟩ (.datum (.leaf (type := Data.integer) 9))
      liveIntegerSourceCells = some writtenIntegerCells := by
    simp [Cells.writeCopy, Cells.exchange, liveIntegerSourceCells, writtenIntegerCells, Value.copyable, Datum.copyable]
  obtain ⟨count, _, _, steps, _⟩ := Defunctionalization.compiled_cell_write
    (signature := signature) (algebra := algebra) .nil (.reference (.there .here)) (.datum (.leaf (type := Data.integer) 9))
    writingCleanupBindings ⟨3⟩ ⟨1⟩ (.datum (.leaf 9)) liveIntegerSourceCells writtenIntegerCells [⟨1⟩] List.mem_cons_self
    (sourceStore := ⟨⟨[], [], []⟩, [], []⟩) (sourceEvaluated := ⟨⟨[], [], []⟩, [], []⟩) (targetStore := ⟨⟨[], [], []⟩, [], []⟩)
    (.cons .reference (.cons .datum .nil)) written ⟨rfl, .nil, .nil⟩ .done
  have run := ExitComposition.stateful_cleanup_execution (identity := ⟨20⟩) (exit := statefulCleanupExit) steps
  have started : ExitComposition.RuntimeStep (.nil : Target.Definitions signature algebra [])
      writingCleanupPending 1 writingCleanupStarted := by
    apply ExitComposition.RuntimeStep.lifecycle
    exact .begin
  have running : ExitComposition.RuntimeSteps (.nil : Target.Definitions signature algebra [])
      writingCleanupStarted 0 writingCleanupReady := run
  exact .cons started running

def writingCleanupFinished : ExitComposition.Runtime signature algebra [] :=
  { writingCleanupReady with phase := .finished .returned, exit := (statefulCleanupExit.cancel "first").cancel "later" }

theorem captured_cleanup_finishes_without_losing_the_updated_cell :
    ExitComposition.RuntimeSteps (.nil : Target.Definitions signature algebra []) writingCleanupPending 1 writingCleanupFinished ∧
    Cells.readCopy (signature := signature) (algebra := algebra) ⟨3⟩ ⟨1⟩ (.leaf .integer) writingCleanupFinished.cells = some (.datum (.leaf 9)) ∧
    writingCleanupFinished.exit.cancellation = some "first" ∧ writingCleanupFinished.exit.primary = .failure .overflow := by
  have finished : ExitComposition.RuntimeSteps (.nil : Target.Definitions signature algebra []) writingCleanupReady 0 writingCleanupFinished := by
    dsimp only [writingCleanupFinished, writingCleanupReady]
    refine ExitComposition.RuntimeSteps.cons (count := 0) (rest := 0)
      (ExitComposition.RuntimeStep.lifecycle (signature := signature) (algebra := algebra) (.capture (controlId := ⟨55⟩))) ?_
    refine ExitComposition.RuntimeSteps.cons (count := 0) (rest := 0)
      (ExitComposition.RuntimeStep.lifecycle (signature := signature) (algebra := algebra) (.cancelled (reason := "first"))) ?_
    refine ExitComposition.RuntimeSteps.cons (count := 0) (rest := 0)
      (ExitComposition.RuntimeStep.lifecycle (signature := signature) (algebra := algebra) (.cancelled (reason := "later"))) ?_
    refine ExitComposition.RuntimeSteps.cons (count := 0) (rest := 0)
      (ExitComposition.RuntimeStep.lifecycle (signature := signature) (algebra := algebra) .reattach) ?_
    exact ExitComposition.RuntimeSteps.cons (count := 0) (rest := 0)
      (ExitComposition.RuntimeStep.lifecycle (signature := signature) (algebra := algebra) .returned) .refl
  refine ⟨cleanup_execution_retains_its_cell_write.trans finished, ?_, rfl, rfl⟩
  simp [writingCleanupFinished, writingCleanupReady, writtenIntegerCells, Defunctionalization.cells, Cells.mapBodies,
    Cell.map, Value.map, Cells.readCopy, Cells.read, Cells.lookup, Value.copyable, Datum.copyable]

abbrev CleanupControl : TypeOf signature := .continuation .shallow .linear .choose (.leaf .boolean) .unit
abbrev cleanupControlShape : ControlShape signature := ⟨.shallow, .choose, .leaf .boolean, .unit⟩

def cleanupControlView : UseScope.ControlView := ⟨⟨0⟩, ⟨5⟩, .cleanup 21⟩

def cleanupControlSourceFuture : Source.Resumption signature algebra [] .shallow .choose (.leaf .boolean) .unit :=
  ⟨⟨4⟩, .push (.bind (fun value => .evaluate (.returnValue (.datum .unit)) (.cons value .nil))) .done⟩

def cleanupControlTargetFuture : Target.Resumption signature algebra [] .shallow .choose (.leaf .boolean) .unit :=
  ⟨⟨4⟩, .push (.returnTo (.enter (.push .unit .ret)) .nil .nil) .done⟩

def cleanupControlSourceStore : Source.ControlHeap signature algebra [] :=
  ⟨⟨[.owned ⟨5⟩ (.cleanup 21)], [.continuation ⟨0⟩ []], []⟩,
    [⟨⟨0⟩, ⟨5⟩, .linear, ⟨cleanupControlShape, cleanupControlSourceFuture⟩⟩], []⟩

def cleanupControlTargetStore : Target.ControlHeap signature algebra [] :=
  ⟨cleanupControlSourceStore.fields, [⟨⟨0⟩, ⟨5⟩, .linear, ⟨cleanupControlShape, cleanupControlTargetFuture⟩⟩], []⟩

def resumingCleanupBindings : Source.RuntimeEnvironment signature algebra [] [.exit, CleanupControl] :=
  .cons (.exit statefulCleanupExit)
    (.cons (.continuation cleanupControlView.identity (some (cleanupControlView.authority, cleanupControlView.owner))) .nil)

def resumingCleanup : Source.Computation signature algebra [] [.exit, CleanupControl] .unit :=
  .resume (.reference (.there .here)) (.datum (.leaf true))

def resumedCleanupSource : Source.ControlState signature algebra [] .unit :=
  ⟨⟨⟨[], [], [⟨5⟩]⟩, [], []⟩, Source.reenter cleanupControlSourceFuture (.returned (.datum (.leaf true)))⟩

theorem cleanup_can_consume_owned_continuation_authority :
    ∃ targetAfter : Target.ControlState signature algebra [] .unit, ExitComposition.RuntimeSteps (.nil : Target.Definitions signature algebra [])
      ⟨⟨21⟩, .running (.code (Defunctionalization.computation resumingCleanup)
        (Defunctionalization.environment resumingCleanupBindings) .nil .done) .active,
        cleanupControlTargetStore, [], [], statefulCleanupExit⟩ 0
      ⟨⟨21⟩, .running targetAfter.configuration .active, targetAfter.store, [], [], statefulCleanupExit⟩ ∧
      targetAfter.store.fields.spent = [⟨5⟩] ∧ UseScope.inventory targetAfter.store.fields = [] := by
  have related : Defunctionalization.ControlHeapRelated cleanupControlSourceStore cleanupControlTargetStore :=
    ⟨rfl, .cons ⟨rfl, rfl, rfl, .same ⟨rfl, .push (.bind (.returnValue (.datum .unit)) .nil) .done⟩⟩ .nil, .nil⟩
  have accepted : Source.resumeControl cleanupControlShape cleanupControlView cleanupControlSourceStore
      (.datum (.leaf (type := Data.boolean) true)) .done = some resumedCleanupSource := by
    simp [Source.resumeControl, UseScope.acquireAt, UseScope.acquire, cleanupControlSourceStore, cleanupControlView,
      UseScope.takeControl, UseScope.takeGrant, UseScope.takeCapture, UseScope.activeFields, UseScope.exposeField,
      UseScope.unpack_control_exact, resumedCleanupSource, Source.Context.plug]
  obtain ⟨targetAfter, count, _, matched, _, steps⟩ := Defunctionalization.compiled_owned_resumption
    (signature := signature) (algebra := algebra) .nil {} .linear (.reference (.there .here)) (.datum (.leaf true))
    resumingCleanupBindings cleanupControlView (.datum (.leaf true)) (sourceEvaluated := cleanupControlSourceStore)
    (.cons .reference (.cons .datum .nil)) related .done accepted
  refine ⟨targetAfter, ExitComposition.stateful_cleanup_execution (steps.in_execution [] []), ?_, ?_⟩
  · rw [← matched.store.fields]; rfl
  · rw [← matched.store.fields]; rfl

end BoundaryV2.Generalized.Examples
