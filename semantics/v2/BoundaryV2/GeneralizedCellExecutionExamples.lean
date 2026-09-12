import BoundaryV2.GeneralizedCellExecution
import BoundaryV2.GeneralizedCellExamples

namespace BoundaryV2.Generalized.Examples

def ownedCellSourceValue : Source.RuntimeValue signature algebra [] (.resource ⟨0⟩) :=
  .datum (.resource ⟨5⟩ ⟨6⟩ (.lexical ⟨0⟩ 0))

def ownedCellSourceBindings : Source.RuntimeEnvironment signature algebra [] [.resource ⟨0⟩] :=
  .cons ownedCellSourceValue .nil

def ownedCellSourceStore : Source.ControlHeap signature algebra [] :=
  ⟨⟨[ownedCellSourceValue.owningField], [], []⟩, [], []⟩

def ownedCellTargetStore : Target.ControlHeap signature algebra [] :=
  ⟨⟨[exclusiveResource.owningField], [], []⟩, [], []⟩

def ownedCellProgram : Source.Computation signature algebra [] [.resource ⟨0⟩] (.cell (.resource ⟨0⟩)) :=
  .cellNew (.datum (.region ⟨0⟩)) (.reference .here)

def ownedCellTargetBefore : Target.State signature algebra [] (.cell (.resource ⟨0⟩)) :=
  ⟨⟨ownedCellTargetStore, .code (Defunctionalization.computation ownedCellProgram)
    (Defunctionalization.environment ownedCellSourceBindings) .nil .done⟩, [], [⟨0⟩]⟩

def ownedCellTargetAfter : Target.State signature algebra [] (.cell (.resource ⟨0⟩)) :=
  ⟨⟨⟨⟨[], [], []⟩, [], []⟩, .returned (.cell ⟨0⟩ ⟨0⟩) .done⟩,
    [⟨⟨0⟩, ⟨0⟩, .resource ⟨0⟩, exclusiveResource⟩], [⟨0⟩]⟩

theorem compiled_owned_initializer_moves_into_its_cell :
    ∃ count, 0 < count ∧ Target.CellSteps .nil ownedCellTargetBefore count ownedCellTargetAfter := by
  obtain ⟨count, positive, _, executed, _⟩ := Defunctionalization.compiled_cell_allocation
    (signature := signature) (algebra := algebra) .nil (.datum (.region ⟨0⟩)) (.reference .here)
    ownedCellSourceBindings ⟨0⟩ ownedCellSourceValue rfl rfl [] [] [⟨0⟩] List.mem_cons_self
    (sourceStore := ownedCellSourceStore) (targetStore := ownedCellTargetStore)
    ⟨rfl, .nil, .nil⟩ ⟨[], [], []⟩ (CellHandoff.move (before := []) (after := [])) .done
  exact ⟨count, positive, executed⟩

theorem owned_initializer_has_one_physical_holder_after_handoff :
    UseScope.inventory ownedCellTargetAfter.control.store.fields = [] ∧
      UseScope.tokens (Cells.fields ownedCellTargetAfter.cells) = [⟨6⟩] ∧
      ownedCellTargetBefore.physicalInventory = ownedCellTargetAfter.physicalInventory := ⟨rfl, rfl, rfl⟩

def liveIntegerSourceCells : Cells signature algebra (Source.Computation signature algebra []) :=
  [⟨⟨3⟩, ⟨1⟩, .leaf .integer, .datum (.leaf 7)⟩]

def integerCellSourceBindings : Source.RuntimeEnvironment signature algebra [] [.cell (.leaf .integer)] :=
  .cons (.cell ⟨3⟩ ⟨1⟩) .nil

theorem compiled_cell_read_preserves_the_typed_value :
    ∃ count, 0 < count ∧ Target.CellSteps (.nil : Target.Definitions signature algebra [])
      ⟨⟨⟨⟨[], [], []⟩, [], []⟩, .code (Defunctionalization.computation (.cellRead (.reference .here)))
        (Defunctionalization.environment integerCellSourceBindings) .nil .done⟩,
        Defunctionalization.cells liveIntegerSourceCells, [⟨1⟩]⟩ count
      ⟨⟨⟨⟨[], [], []⟩, [], []⟩, .returned (.datum (.leaf 7)) .done⟩,
        Defunctionalization.cells liveIntegerSourceCells, [⟨1⟩]⟩ := by
  have read : Cells.readCopy (signature := signature) (algebra := algebra) ⟨3⟩ ⟨1⟩ (.leaf .integer)
      liveIntegerSourceCells = some (.datum (.leaf 7)) := by
    simp [Cells.readCopy, Cells.read, Cells.lookup, liveIntegerSourceCells, Value.copyable, Datum.copyable]
  obtain ⟨count, positive, _, executed, _⟩ := Defunctionalization.compiled_cell_read
    (signature := signature) (algebra := algebra) .nil (.reference .here) integerCellSourceBindings
    ⟨3⟩ ⟨1⟩ (.datum (.leaf 7)) rfl liveIntegerSourceCells [⟨1⟩] List.mem_cons_self read
    (sourceStore := ⟨⟨[], [], []⟩, [], []⟩) (targetStore := ⟨⟨[], [], []⟩, [], []⟩) ⟨rfl, .nil, .nil⟩ .done
  exact ⟨count, positive, executed⟩

end BoundaryV2.Generalized.Examples
