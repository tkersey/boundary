import BoundaryV2.GeneralizedStateExecution
import BoundaryV2.GeneralizedOwnedClauseExamples

namespace BoundaryV2.Generalized.Examples

local instance stateExecutionChoiceDecidable : DecidableEq (signature.operation .choose) := fun first second => by
  cases first
  cases second
  exact isTrue rfl

def cellHeldAuthority : Target.RuntimeValue signature algebra [] (.resource ⟨0⟩) :=
  .datum (.resource ⟨9⟩ ⟨0⟩ (.lexical ⟨0⟩ 0))

def reservedTargetCells : Cells signature algebra (fun context result => Target.Code signature algebra [] context [] result) :=
  [⟨⟨0⟩, ⟨0⟩, .resource ⟨0⟩, cellHeldAuthority⟩]

def reservedSourceCells : Cells signature algebra (Source.Computation signature algebra []) :=
  [⟨⟨0⟩, ⟨0⟩, .resource ⟨0⟩, .datum (.resource ⟨9⟩ ⟨0⟩ (.lexical ⟨0⟩ 0))⟩]

def emptySourceControls : Source.ControlHeap signature algebra [] := ⟨⟨[], [], []⟩, [], []⟩
def emptyTargetControls : Target.ControlHeap signature algebra [] := ⟨⟨[], [], []⟩, [], []⟩

def reservedSourceCapture := Source.captureOwnedClause effectfulOwnedClause .affine rfl ⟨8⟩
  distinctNormalReturn effectfulOwnedClauses textBindings .done (.datum .unit) .nil .done
  (.lexical ⟨1⟩ 0) [] [] [] emptySourceControls rfl reservedSourceCells.reservations

def reservedTargetCapture := Target.captureOwnedClause (Defunctionalization.selectedClause effectfulOwnedClause) .affine rfl ⟨8⟩
  (Defunctionalization.computation distinctNormalReturn) (Defunctionalization.clauses effectfulOwnedClauses)
  (Defunctionalization.environment textBindings) .done (.datum .unit) .nil .done
  (.lexical ⟨1⟩ 0) [] [] [] emptyTargetControls rfl reservedTargetCells.reservations

theorem captured_grant_avoids_cell_held_authority :
    reservedTargetCapture.view.authority = ⟨1⟩ ∧
      (⟨reservedTargetCapture.state, reservedTargetCells, [⟨0⟩]⟩ : Target.State signature algebra [] (.leaf .text)).physicalInventory =
        [⟨1⟩, ⟨0⟩] := ⟨rfl, rfl⟩

theorem omitting_cell_reservations_would_duplicate_authority :
    let omitted := Target.captureOwnedClause (Defunctionalization.selectedClause effectfulOwnedClause) .affine rfl ⟨8⟩
      (Defunctionalization.computation distinctNormalReturn) (Defunctionalization.clauses effectfulOwnedClauses)
      (Defunctionalization.environment textBindings) .done (.datum .unit) .nil .done
      (.lexical ⟨1⟩ 0) [] [] [] emptyTargetControls rfl
    ¬ (⟨omitted.state, reservedTargetCells, [⟨0⟩]⟩ : Target.State signature algebra [] (.leaf .text)).physicalInventory.Nodup := by
  change ¬ ([⟨0⟩, ⟨0⟩] : List (Id .custody)).Nodup
  decide

theorem handler_capture_with_cells_has_corresponding_execution :
    ∃ targetAfter : Target.OwnedClause signature algebra [] (.leaf .text),
      Defunctionalization.CellStateRelated ⟨reservedSourceCapture.state, reservedSourceCells, [⟨0⟩]⟩
        ⟨targetAfter.state, reservedTargetCells, [⟨0⟩]⟩ ∧
      Target.ExecutionSteps .nil
        ⟨⟨emptyTargetControls, .requested Operation.choice ⟨8⟩ (.datum .unit) .nil
          (.push (.handler .choose .shallow ⟨8⟩ (Defunctionalization.computation distinctNormalReturn)
            (Defunctionalization.clauses effectfulOwnedClauses) (Defunctionalization.environment textBindings)) .done)⟩,
          reservedTargetCells, [⟨0⟩]⟩ 1 ⟨targetAfter.state, reservedTargetCells, [⟨0⟩]⟩ := by
  obtain ⟨targetAfter, related, _, executed⟩ := Defunctionalization.handled_operation_with_cells_corresponds (retained := [])
    (signature := signature) (algebra := algebra) .nil Operation.choice ⟨8⟩ distinctNormalReturn effectfulOwnedClauses
    textBindings .done (.datum .unit) .nil .done (.lexical ⟨1⟩ 0) [] [] []
    (sourceStore := emptySourceControls) (targetStore := emptyTargetControls) ⟨rfl, .nil, .nil⟩
    reservedSourceCells [⟨0⟩] rfl rfl rfl (show _ = some reservedSourceCapture from rfl)
  exact ⟨targetAfter, related, executed⟩

theorem ordinary_execution_retains_the_cell_holder :
    ∃ count future, Target.ExecutionSteps .nil ⟨reservedTargetCapture.state, reservedTargetCells, [⟨0⟩]⟩ count
      ⟨⟨reservedTargetCapture.store, .requested Operation.text ⟨4⟩ (.datum (.leaf true)) .nil future⟩,
        reservedTargetCells, [⟨0⟩]⟩ := by
  exact ⟨3, _, .cons (.cell (.ordinary (.operand .load)))
    (.cons (.cell (.ordinary (.operand .load)))
      (.cons (.cell (.ordinary (.dispatch (signature := signature) (algebra := algebra)
        (operation := Operation.text) (bodies := .nil) (payload := .datum (.leaf true)) (attachment := ⟨4⟩)))) .refl))⟩

end BoundaryV2.Generalized.Examples
