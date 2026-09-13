import BoundaryV2.GeneralizedStatefulCellExecution
import BoundaryV2.GeneralizedOwnedOperandExamples

namespace BoundaryV2.Generalized.Examples

def closureCellProgram : Source.Computation signature algebra []
    [.leaf .boolean, .resource ⟨0⟩, .leaf .integer] (.cell OwnedApplicationType) :=
  .cellNew (.datum (.region ⟨1⟩)) compoundOwnedFunction

def closureCellFields : UseScope.State :=
  ⟨[.owned ⟨100⟩ (.lexical ⟨0⟩ 1)], creationSourceStore.fields.retained, creationSourceStore.fields.spent⟩

def closureCellTargetAfter : Target.State signature algebra [] (.cell OwnedApplicationType) :=
  ⟨⟨{ creationTargetStore with fields := closureCellFields }, .returned (.cell ⟨4⟩ ⟨1⟩) .done⟩,
    ⟨⟨4⟩, ⟨1⟩, OwnedApplicationType, Defunctionalization.value createdSourceComputation.value⟩ ::
      Defunctionalization.cells creationCells, [⟨1⟩]⟩

theorem closure_initializer_moves_grant_and_capture_into_its_cell :
    (∃ count, 0 < count ∧ Target.ExecutionSteps (.nil : Target.Definitions signature algebra [])
      ⟨⟨creationTargetStore, .code (Defunctionalization.computation closureCellProgram)
        (Defunctionalization.environment lambdaBindings) .nil .done⟩,
        Defunctionalization.cells creationCells, [⟨1⟩]⟩ count closureCellTargetAfter) ∧
    UseScope.inventory closureCellTargetAfter.control.store.fields = [⟨100⟩] ∧
    UseScope.tokens closureCellTargetAfter.cells.fields = [⟨301⟩, ⟨6⟩, ⟨300⟩] ∧
    closureCellTargetAfter.control.store.fields.spent = [⟨17⟩] := by
  have evaluated : Source.ArgumentsEvaluation lambdaBindings creationCells.reservations.custody creationSourceStore
      closureCellProgram.operandPrefix.arguments
      (.ok (.cons (.datum (.region ⟨1⟩)) (.cons createdSourceComputation.value .nil))) createdSourceComputation.store :=
    .cons .datum (.cons compound_function_evaluates_with_its_grant .nil)
  have handoff : ValueHandoff createdSourceComputation.value createdSourceComputation.store.fields closureCellFields :=
    .move (before := [.owned ⟨100⟩ (.lexical ⟨0⟩ 1)]) (after := [])
  obtain ⟨count, positive, _, steps, _⟩ := Defunctionalization.compiled_cell_allocation
    (signature := signature) (algebra := algebra) .nil (.datum (.region ⟨1⟩)) compoundOwnedFunction lambdaBindings
    ⟨1⟩ createdSourceComputation.value creationCells [] [⟨1⟩] List.mem_cons_self
    (targetStore := creationTargetStore) evaluated ⟨rfl, .nil, .nil⟩ closureCellFields handoff .done
  exact ⟨⟨count, positive, steps⟩, rfl, rfl, rfl⟩

def writtenIntegerCells : Cells signature algebra (Source.Computation signature algebra []) :=
  [⟨⟨3⟩, ⟨1⟩, .leaf .integer, .datum (.leaf 9)⟩]

theorem compiled_write_changes_the_value_seen_through_the_cell_reference :
    (∃ count, 0 < count ∧ Target.ExecutionSteps (.nil : Target.Definitions signature algebra [])
      ⟨⟨⟨⟨[], [], []⟩, [], []⟩, .code (Defunctionalization.computation
        (.cellWrite (.reference .here) (.datum (.leaf (type := Data.integer) 9))))
        (Defunctionalization.environment integerCellSourceBindings) .nil .done⟩,
        Defunctionalization.cells liveIntegerSourceCells, [⟨1⟩]⟩ count
      ⟨⟨⟨⟨[], [], []⟩, [], []⟩, .returned (.datum .unit) .done⟩,
        Defunctionalization.cells writtenIntegerCells, [⟨1⟩]⟩) ∧
    Cells.readCopy (signature := signature) (algebra := algebra) ⟨3⟩ ⟨1⟩ (.leaf .integer)
      (Defunctionalization.cells writtenIntegerCells) = some (.datum (.leaf 9)) := by
  have written : Cells.writeCopy (signature := signature) (algebra := algebra) ⟨3⟩ ⟨1⟩ (.datum (.leaf (type := Data.integer) 9))
      liveIntegerSourceCells = some writtenIntegerCells := by
    simp [Cells.writeCopy, Cells.exchange, liveIntegerSourceCells, writtenIntegerCells, Value.copyable, Datum.copyable]
  obtain ⟨count, positive, _, steps, _⟩ := Defunctionalization.compiled_cell_write
    (signature := signature) (algebra := algebra) .nil (.reference .here) (.datum (.leaf (type := Data.integer) 9))
    integerCellSourceBindings ⟨3⟩ ⟨1⟩ (.datum (.leaf 9)) liveIntegerSourceCells writtenIntegerCells
    [⟨1⟩] List.mem_cons_self (sourceStore := ⟨⟨[], [], []⟩, [], []⟩)
    (sourceEvaluated := ⟨⟨[], [], []⟩, [], []⟩) (targetStore := ⟨⟨[], [], []⟩, [], []⟩)
    (.cons .reference (.cons .datum .nil)) written ⟨rfl, .nil, .nil⟩ .done
  refine ⟨⟨count, positive, steps⟩, ?_⟩
  simp [Cells.readCopy, Cells.read, Cells.lookup, Defunctionalization.cells, Cells.mapBodies, Cell.map,
    writtenIntegerCells, Value.map, Value.copyable, Datum.copyable]

theorem an_ordinary_cell_step_cannot_create_an_unowned_linear_closure
    (store : Target.ControlHeap signature algebra []) :
    ¬ Target.CellStep (.nil : Target.Definitions signature algebra [])
      (⟨⟨store, .code (.close (Defunctionalization.computation applicationBody) .ret)
        (Defunctionalization.environment lambdaBindings)
        ((Defunctionalization.environment applicationCaptures).pushReverse .nil) .done⟩, [], []⟩ :
        Target.State signature algebra [] OwnedApplicationType)
      ⟨⟨store, .code .ret (Defunctionalization.environment lambdaBindings)
        (.cons (.closure (Defunctionalization.computation applicationBody)
          (Defunctionalization.environment applicationCaptures) none) .nil) .done⟩, [], []⟩ := by
  intro step
  cases step with
  | ordinary step neutral => contradiction

end BoundaryV2.Generalized.Examples
