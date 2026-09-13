import BoundaryV2.GeneralizedRegionExecution
import BoundaryV2.GeneralizedStatefulCellExecution
import BoundaryV2.GeneralizedExamples

namespace BoundaryV2.Generalized.Examples

def regionEntryBody : Source.Computation signature algebra [] [.region, .leaf .integer] (.cell (.leaf .integer)) :=
  .cellNew (.reference .here) (.reference (.there .here))

def regionEntryProgram := Source.Computation.withRegion regionEntryBody
def regionEntryBindings : Source.RuntimeEnvironment signature algebra [] [.leaf .integer] :=
  .cons (.datum (.leaf 11)) .nil
def dormantRegionCode : Source.Computation signature algebra [] [] .region := .returnValue (.datum (.region ⟨60⟩))
def regionEntryCells : Cells signature algebra (Source.Computation signature algebra []) :=
  [⟨⟨3⟩, ⟨1⟩, .leaf .integer, .datum (.leaf 7)⟩,
    ⟨⟨4⟩, ⟨1⟩, .computation .reusable [] .region, .closure dormantRegionCode .nil none⟩]
def regionEntrySourceStore : Source.ControlHeap signature algebra [] := ⟨⟨[], [], []⟩, [], []⟩
def regionEntryTargetStore : Target.ControlHeap signature algebra [] := ⟨⟨[], [], []⟩, [], []⟩
def regionEntryLive : List (Id .region) := [⟨1⟩, ⟨50⟩]
def enteredRegion := Target.freshRegion (.nil : Target.Definitions signature algebra [])
  (Defunctionalization.computation regionEntryProgram) (Defunctionalization.environment regionEntryBindings) .nil
  .done regionEntryTargetStore (Defunctionalization.cells regionEntryCells) regionEntryLive []

theorem region_entry_reserves_live_regions_and_dormant_code :
    enteredRegion = ⟨61⟩ ∧
    Target.freshRegion (.nil : Target.Definitions signature algebra [])
      (Defunctionalization.computation regionEntryProgram) (Defunctionalization.environment regionEntryBindings) .nil
      .done regionEntryTargetStore [] regionEntryLive [] = ⟨51⟩ := ⟨rfl, rfl⟩

def regionEntrySourceInside : Source.State signature algebra [] (.cell (.leaf .integer)) :=
  ⟨⟨regionEntrySourceStore, .region enteredRegion
    (.evaluate regionEntryBody (.cons (.datum (.region enteredRegion)) regionEntryBindings))⟩,
    regionEntryCells, enteredRegion :: regionEntryLive⟩

def regionEntrySourceAfter : Source.State signature algebra [] (.cell (.leaf .integer)) :=
  ⟨⟨regionEntrySourceStore, .region enteredRegion (.returned (.cell ⟨5⟩ enteredRegion))⟩,
    ⟨⟨5⟩, enteredRegion, .leaf .integer, .datum (.leaf 11)⟩ :: regionEntryCells, enteredRegion :: regionEntryLive⟩

def regionEntryTargetOutside : Target.Stack signature algebra [] (.cell (.leaf .integer)) (.cell (.leaf .integer)) :=
  .push (.region enteredRegion) (.push (.returnTo .ret (Defunctionalization.environment regionEntryBindings) .nil) .done)

def regionEntryTargetAfter : Target.State signature algebra [] (.cell (.leaf .integer)) :=
  ⟨⟨regionEntryTargetStore, .returned (.cell ⟨5⟩ enteredRegion) regionEntryTargetOutside⟩,
    ⟨⟨5⟩, enteredRegion, .leaf .integer, .datum (.leaf 11)⟩ :: Defunctionalization.cells regionEntryCells,
    enteredRegion :: regionEntryLive⟩

/-- The initializer reads the caller's captured integer. Region liveness is
produced by the authored entry step, then consumed as evidence by allocation.
The returned cell is still inside its explicit close boundary. -/
theorem authored_region_makes_its_body_cell_allocation_live :
    Source.ExecutionStep (.nil : Source.Definitions signature algebra [])
      ⟨⟨regionEntrySourceStore, .evaluate regionEntryProgram regionEntryBindings⟩, regionEntryCells, regionEntryLive⟩
      regionEntrySourceInside ∧
    Source.ExecutionStep (.nil : Source.Definitions signature algebra []) regionEntrySourceInside regionEntrySourceAfter ∧
    (∃ count, 0 < count ∧ Target.ExecutionSteps (.nil : Target.Definitions signature algebra [])
      ⟨⟨regionEntryTargetStore, .code (Defunctionalization.computation regionEntryProgram)
        (Defunctionalization.environment regionEntryBindings) .nil .done⟩,
        Defunctionalization.cells regionEntryCells, regionEntryLive⟩ count regionEntryTargetAfter) ∧
    Defunctionalization.CellStateRelated regionEntrySourceAfter regionEntryTargetAfter := by
  obtain ⟨sourceEnter, targetEnter, _⟩ := Defunctionalization.compiled_region_entry
    (signature := signature) (algebra := algebra) .nil regionEntryBody regionEntryBindings .done
    (sourceStore := regionEntrySourceStore) (targetStore := regionEntryTargetStore) ⟨rfl, .nil, .nil⟩
    regionEntryCells regionEntryLive []
  have evaluated : Source.ArgumentsEvaluation (.cons (.datum (.region enteredRegion)) regionEntryBindings)
      regionEntryCells.reservations.custody regionEntrySourceStore
      (.cons (.reference .here) (.cons (.reference (.there .here)) .nil))
      (.ok (.cons (.datum (.region enteredRegion)) (.cons (.datum (.leaf (type := Data.integer) 11)) .nil))) regionEntrySourceStore :=
    .cons .reference (.cons .reference .nil)
  obtain ⟨count, positive, sourceAllocate, targetAllocate, related⟩ := Defunctionalization.compiled_cell_allocation
    (signature := signature) (algebra := algebra) .nil (.reference .here) (.reference (.there .here))
    (.cons (.datum (.region enteredRegion)) regionEntryBindings) enteredRegion (.datum (.leaf (type := Data.integer) 11))
    regionEntryCells [] (enteredRegion :: regionEntryLive) List.mem_cons_self
    (targetStore := regionEntryTargetStore) evaluated ⟨rfl, .nil, .nil⟩ regionEntrySourceStore.fields (.unowned rfl)
    (.push (.region enteredRegion) (.passthrough regionEntryBindings .done))
  exact ⟨sourceEnter, .cell sourceAllocate, ⟨1 + count, by omega, targetEnter.trans targetAllocate⟩, related⟩

theorem region_allocation_preserves_the_outer_cell_value :
    Cells.readCopy (signature := signature) (algebra := algebra) ⟨3⟩ ⟨1⟩ (.leaf .integer)
      regionEntryTargetAfter.cells = some (.datum (.leaf 7)) ∧
    Cells.readCopy (signature := signature) (algebra := algebra) ⟨5⟩ enteredRegion (.leaf .integer)
      regionEntryTargetAfter.cells = some (.datum (.leaf 11)) := by
  constructor <;> simp [Cells.readCopy, Cells.read, Cells.lookup, regionEntryTargetAfter, regionEntryCells,
    Defunctionalization.cells, Cells.mapBodies, Cell.map, Value.map, Value.copyable, Datum.copyable]

end BoundaryV2.Generalized.Examples
