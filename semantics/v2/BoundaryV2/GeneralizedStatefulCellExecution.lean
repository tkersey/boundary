import BoundaryV2.GeneralizedStateExecution

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

theorem compiled_cell_read
    (table : Source.Definitions signature algebra program)
    (reference : Source.Expression signature algebra program context (.cell type))
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (identity : Id .cell) (region : Id .region) (value : Source.RuntimeValue signature algebra program type)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program))
    (regions : List (Id .region)) (live : region ∈ regions)
    {sourceStore sourceEvaluated : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (evaluated : Source.ExpressionEvaluation bindings sourceCells.reservations.custody sourceStore reference
      (.ok (.cell identity region)) sourceEvaluated)
    (read : Cells.readCopy identity region type sourceCells = some value)
    (stores : ControlHeapRelated sourceStore targetStore)
    {sourceOutside : Source.Context signature algebra program type result}
    {targetOutside : Target.Stack signature algebra program type result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    ∃ count, 0 < count ∧
      Source.CellStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.cellRead reference) bindings)⟩, sourceCells, regions⟩
        ⟨⟨sourceEvaluated, sourceOutside.plug (.returned value)⟩, sourceCells, regions⟩ ∧
      Target.ExecutionSteps (definitions table)
        ⟨⟨targetStore, .code (computation (.cellRead reference)) (environment bindings) .nil targetOutside⟩, cells sourceCells, regions⟩ count
        ⟨⟨{ targetStore with fields := sourceEvaluated.fields }, .returned (Defunctionalization.value value) targetOutside⟩, cells sourceCells, regions⟩ ∧
      CellStateRelated ⟨⟨sourceEvaluated, sourceOutside.plug (.returned value)⟩, sourceCells, regions⟩
        ⟨⟨{ targetStore with fields := sourceEvaluated.fields }, .returned (Defunctionalization.value value) targetOutside⟩, cells sourceCells, regions⟩ := by
  have targetRead : Cells.readCopy identity region type (cells sourceCells) = some (Defunctionalization.value value) := by
    unfold cells
    rw [Cells.readCopy_mapBodies, read]
    rfl
  obtain ⟨count, targetAfter, _, operands, related⟩ := owned_expression_drains
    (UseScope.PackedControlRelated controlPayloadRelated) bindings sourceCells.reservations.custody reference
    (.cell identity region) evaluated (.cellRead .ret) .nil stores
  have reservations : (cells sourceCells).reservations = sourceCells.reservations := Cells.reservations_mapBodies _ sourceCells
  rw [← reservations] at operands
  have replaced : targetAfter = { targetStore with fields := sourceEvaluated.fields } := by
    have updated := operands.store_is_field_update
    rw [← related.fields] at updated
    exact updated
  rw [← replaced]
  refine ⟨count + 2, by omega, .read evaluated live read, ?_, ⟨⟨related, .returned value outside⟩, rfl, rfl⟩⟩
  exact (operands.in_execution (definitions table) targetOutside (cells sourceCells) regions).trans
    (.cons (.cell (.read live targetRead)) (.single (.cell (.ordinary .returned))))

theorem compiled_cell_write
    (table : Source.Definitions signature algebra program)
    (reference : Source.Expression signature algebra program context (.cell type))
    (replacement : Source.Expression signature algebra program context type)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (identity : Id .cell) (region : Id .region) (value : Source.RuntimeValue signature algebra program type)
    (sourceCells afterCells : Cells signature algebra (Source.Computation signature algebra program))
    (regions : List (Id .region)) (live : region ∈ regions)
    {sourceStore sourceEvaluated : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (evaluated : Source.ArgumentsEvaluation bindings sourceCells.reservations.custody sourceStore (.cons reference (.cons replacement .nil))
      (.ok (.cons (.cell identity region) (.cons value .nil))) sourceEvaluated)
    (written : Cells.writeCopy identity region value sourceCells = some afterCells)
    (stores : ControlHeapRelated sourceStore targetStore)
    {sourceOutside : Source.Context signature algebra program .unit result}
    {targetOutside : Target.Stack signature algebra program .unit result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    ∃ count, 0 < count ∧
      Source.CellStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.cellWrite reference replacement) bindings)⟩, sourceCells, regions⟩
        ⟨⟨sourceEvaluated, sourceOutside.plug (.returned (.datum .unit))⟩, afterCells, regions⟩ ∧
      Target.ExecutionSteps (definitions table)
        ⟨⟨targetStore, .code (computation (.cellWrite reference replacement)) (environment bindings) .nil targetOutside⟩, cells sourceCells, regions⟩ count
        ⟨⟨{ targetStore with fields := sourceEvaluated.fields }, .returned (.datum .unit) targetOutside⟩, cells afterCells, regions⟩ ∧
      CellStateRelated ⟨⟨sourceEvaluated, sourceOutside.plug (.returned (.datum .unit))⟩, afterCells, regions⟩
        ⟨⟨{ targetStore with fields := sourceEvaluated.fields }, .returned (.datum .unit) targetOutside⟩, cells afterCells, regions⟩ := by
  have targetWritten : Cells.writeCopy identity region (Defunctionalization.value value) (cells sourceCells) = some (cells afterCells) := by
    unfold cells Defunctionalization.value
    rw [Cells.writeCopy_mapBodies, written]
    rfl
  obtain ⟨count, targetAfter, operands, related⟩ := owned_two_operands_drains
    (UseScope.PackedControlRelated controlPayloadRelated) bindings sourceCells.reservations.custody reference replacement
    (.cell identity region) value evaluated (.cellWrite .ret) stores
  have reservations : (cells sourceCells).reservations = sourceCells.reservations := Cells.reservations_mapBodies _ sourceCells
  rw [← reservations] at operands
  have replaced : targetAfter = { targetStore with fields := sourceEvaluated.fields } := by
    have updated := operands.store_is_field_update
    rw [← related.fields] at updated
    exact updated
  rw [← replaced]
  refine ⟨count + 2, by omega, .write evaluated live written, ?_,
    ⟨⟨related, .returned (.datum .unit) outside⟩, rfl, rfl⟩⟩
  exact (operands.in_execution (definitions table) targetOutside (cells sourceCells) regions).trans
    (.cons (.cell (.write live targetWritten)) (.single (.cell (.ordinary .returned))))

theorem compiled_cell_allocation
    (table : Source.Definitions signature algebra program)
    (regionExpr : Source.Expression signature algebra program context .region)
    (valueExpr : Source.Expression signature algebra program context type)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (region : Id .region) (value : Source.RuntimeValue signature algebra program type)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (reserved : List (Id .cell))
    (regions : List (Id .region)) (live : region ∈ regions)
    {sourceStore sourceEvaluated : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (evaluated : Source.ArgumentsEvaluation bindings sourceCells.reservations.custody sourceStore (.cons regionExpr (.cons valueExpr .nil))
      (.ok (.cons (.datum (.region region)) (.cons value .nil))) sourceEvaluated)
    (stores : ControlHeapRelated sourceStore targetStore) (fields : UseScope.State)
    (handoff : ValueHandoff value sourceEvaluated.fields fields)
    {sourceOutside : Source.Context signature algebra program (.cell type) result}
    {targetOutside : Target.Stack signature algebra program (.cell type) result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    let allocated := Cells.allocate region value sourceCells reserved
    ∃ count, 0 < count ∧
      Source.CellStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.cellNew regionExpr valueExpr) bindings)⟩, sourceCells, regions⟩
        ⟨⟨{ sourceEvaluated with fields := fields }, sourceOutside.plug (.returned (.cell allocated.identity region))⟩, allocated.cells, regions⟩ ∧
      Target.ExecutionSteps (definitions table)
        ⟨⟨targetStore, .code (computation (.cellNew regionExpr valueExpr)) (environment bindings) .nil targetOutside⟩, cells sourceCells, regions⟩ count
        ⟨⟨{ targetStore with fields := fields }, .returned (.cell allocated.identity region) targetOutside⟩, cells allocated.cells, regions⟩ ∧
      CellStateRelated
        ⟨⟨{ sourceEvaluated with fields := fields }, sourceOutside.plug (.returned (.cell allocated.identity region))⟩, allocated.cells, regions⟩
        ⟨⟨{ targetStore with fields := fields }, .returned (.cell allocated.identity region) targetOutside⟩, cells allocated.cells, regions⟩ := by
  dsimp only
  have allocation := Cells.allocate_mapBodies (fun _ _ body => computation body) region value sourceCells reserved
  obtain ⟨count, targetEvaluated, operands, related⟩ := owned_two_operands_drains
    (UseScope.PackedControlRelated controlPayloadRelated) bindings sourceCells.reservations.custody regionExpr valueExpr
    (.datum (.region region)) value evaluated (.cellNew .ret) stores
  have targetHandoff := cell_handoff_corresponds value handoff
  rw [related.fields] at targetHandoff
  have reservations : (cells sourceCells).reservations = sourceCells.reservations := Cells.reservations_mapBodies _ sourceCells
  rw [← reservations] at operands
  have replaced : { targetEvaluated with fields := fields } = { targetStore with fields := fields } :=
    congrArg (fun store => { store with fields := fields }) operands.store_is_field_update
  refine ⟨count + 2, by omega, .allocate evaluated live handoff, ?_, ?_⟩
  · rw [← replaced]
    apply (operands.in_execution (definitions table) targetOutside (cells sourceCells) regions).trans
    have entered := Target.ExecutionSteps.cons (.cell (Target.CellStep.allocate (table := definitions table) (reserved := reserved)
      (next := .ret) (bindings := environment bindings) (values := .nil) (outside := targetOutside) (cells := cells sourceCells) live targetHandoff))
      (.single (.cell (.ordinary .returned)))
    simpa only [Defunctionalization.value, Value.map, cells, allocation.1, allocation.2] using entered
  · rw [← replaced]
    exact ⟨⟨⟨rfl, related.controls, related.disposing⟩, .returned (.cell _ region) outside⟩, rfl, rfl⟩

end BoundaryV2.Generalized.Defunctionalization
