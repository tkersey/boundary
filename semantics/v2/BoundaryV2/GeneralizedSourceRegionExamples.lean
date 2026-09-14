import BoundaryV2.GeneralizedExitSimulation
import BoundaryV2.GeneralizedExamples

namespace BoundaryV2.Generalized.Examples.SourceRegion

open Defunctionalization

def first : Source.RuntimeValue signature algebra [] (.resource ⟨1⟩) :=
  .datum (.resource ⟨8⟩ ⟨300⟩ (.lexical ⟨0⟩ 1))
def second : Source.RuntimeValue signature algebra [] (.resource ⟨1⟩) :=
  .datum (.resource ⟨9⟩ ⟨400⟩ (.lexical ⟨0⟩ 2))
def plain : Source.RuntimeValue signature algebra [] (.leaf .integer) := .datum (.leaf 7)
def outer : Cell signature algebra (Source.Computation signature algebra []) :=
  ⟨⟨2⟩, ⟨2⟩, .leaf .integer, .datum (.leaf 9)⟩
def initialFields : UseScope.State := ⟨[.owned ⟨900⟩ (.lexical ⟨50⟩ 0)], [], [⟨700⟩]⟩
def initialCells : Cells signature algebra (Source.Computation signature algebra []) :=
  [⟨⟨3⟩, ⟨1⟩, .resource ⟨1⟩, second⟩, outer, ⟨⟨1⟩, ⟨1⟩, .resource ⟨1⟩, first⟩,
    ⟨⟨0⟩, ⟨1⟩, .leaf .integer, plain⟩]
def exit : ExitInfo Fault String := ⟨.failure .overflow, [.overflow], some "first"⟩
def normal : ExitInfo Fault String := ⟨.normal, [], none⟩
def original : Source.ExitRuntime signature algebra [] :=
  ⟨⟨7⟩, .abandoned, ⟨initialFields, [], []⟩, initialCells, [⟨1⟩, ⟨2⟩], exit⟩
def targetOriginal : ExitComposition.Runtime signature algebra [] :=
  ⟨⟨7⟩, .finished .abandoned, ⟨initialFields, [], []⟩, cells initialCells, [⟨1⟩, ⟨2⟩], exit⟩
def parent : Source.Context signature algebra [] .unit .unit :=
  .push (.cleanupReturn ⟨99⟩ (some (.datum .unit)) normal) .done
def targetParent : Target.Stack signature algebra [] .unit .unit :=
  .push (.cleanupReturn ⟨99⟩ (some (.datum .unit)) normal) .done
def start : Source.RegionHandoff signature algebra [] .unit .unit := ⟨⟨1⟩, original, parent, []⟩
def kept : Source.RegionHandoff signature algebra [] .unit .unit := { start with kept := [⟨0⟩] }
def offeredFirst : Source.ExitRuntime signature algebra [] :=
  { original with
    store := { original.store with fields := { initialFields with active := initialFields.active ++ [first.owningField] } }
    cells := [⟨⟨3⟩, ⟨1⟩, .resource ⟨1⟩, second⟩, outer, ⟨⟨0⟩, ⟨1⟩, .leaf .integer, plain⟩] }
def consumedFirst : Source.ExitRuntime signature algebra [] :=
  { offeredFirst with store := { offeredFirst.store with fields := { initialFields with spent := [⟨300⟩, ⟨700⟩] } } }
def middle : Source.RegionHandoff signature algebra [] .unit .unit := ⟨⟨1⟩, consumedFirst, parent, [⟨0⟩]⟩
def offeredSecond : Source.ExitRuntime signature algebra [] :=
  { consumedFirst with
    store := { consumedFirst.store with fields := { consumedFirst.store.fields with active := initialFields.active ++ [second.owningField] } }
    cells := [outer, ⟨⟨0⟩, ⟨1⟩, .leaf .integer, plain⟩] }
def consumedSecond : Source.ExitRuntime signature algebra [] :=
  { offeredSecond with store := { offeredSecond.store with fields := { initialFields with spent := [⟨400⟩, ⟨300⟩, ⟨700⟩] } } }
def ready : Source.RegionHandoff signature algebra [] .unit .unit := ⟨⟨1⟩, consumedSecond, parent, [⟨0⟩]⟩
def finishedRuntime : Source.ExitRuntime signature algebra [] := { consumedSecond with cells := [outer], regions := [⟨2⟩] }
def finished : Source.ExitResolution signature algebra [] .unit := .unwind finishedRuntime parent
def closedExit : ExitInfo Fault String := normal.nestedFailure .overflow exit.failures exit.cancellation
def closed : Source.State signature algebra [] .unit := ⟨⟨finishedRuntime.store, .failed .overflow⟩, [outer], [⟨2⟩]⟩

theorem actual_source_cells_handoff_in_creation_order (retained : List Reference := []) :
    Source.RegionDisposalSteps (.nil : Source.Definitions signature algebra [])
      (.offering start) 9 (.offering ready) retained := by
  refine .cons (middle := .disposing ⟨1⟩ parent [⟨0⟩] (Source.ValueDisposal.start original plain)) (.offer rfl) ?_
  refine .cons (middle := .disposing ⟨1⟩ parent [⟨0⟩] (.ready original [])) (.values (.stale rfl)) ?_
  refine .cons (middle := .offering kept) (.returnValue rfl) ?_
  refine .cons (middle := .disposing ⟨1⟩ parent [⟨0⟩] (Source.ValueDisposal.start offeredFirst first)) (.offer rfl) ?_
  refine .cons (middle := .disposing ⟨1⟩ parent [⟨0⟩] (.ready consumedFirst [])) (.values (.resource rfl)) ?_
  refine .cons (middle := .offering middle) (.returnValue rfl) ?_
  refine .cons (middle := .disposing ⟨1⟩ parent [⟨0⟩] (Source.ValueDisposal.start offeredSecond second)) (.offer rfl) ?_
  refine .cons (middle := .disposing ⟨1⟩ parent [⟨0⟩] (.ready consumedSecond [])) (.values (.resource rfl)) ?_
  exact .cons (.returnValue rfl) .refl

theorem source_storage_waits_for_disposal_and_retained_aliases :
    Cells.readCopy (signature := signature) (algebra := algebra) ⟨0⟩ ⟨1⟩ (.leaf .integer) offeredSecond.cells = some plain ∧
    Source.RegionDisposal.finish [] (.disposing ⟨1⟩ parent [⟨0⟩] (Source.ValueDisposal.start offeredSecond second)) = none ∧
    Source.RegionDisposal.finish [.name .cell ⟨0⟩] (.offering ready) = none ∧
    Source.RegionDisposal.finish [] (.offering ready) = some finished := by
  refine ⟨?_, rfl, rfl, rfl⟩
  simp [Cells.readCopy, Cells.read, Cells.lookup, offeredSecond, outer, plain, Value.copyable, Datum.copyable]

theorem source_region_exit_composes_under_running_parent_cleanup :
    Source.CleanupSteps (.nil : Source.Definitions signature algebra [])
      (.running (.unwind original (.push (.region ⟨1⟩) parent))) 12 (.running (.reenter closed closedExit)) := by
  refine .cons (middle := .region (.offering start)) (.enterRegion rfl) ?_
  have region := Source.CleanupSteps.of_region actual_source_cells_handoff_in_creation_order
  have finish : Source.CleanupSteps (.nil : Source.Definitions signature algebra [])
      (.region (.offering ready)) 2 (.running (.reenter closed closedExit)) := by
    refine .cons (middle := .running finished) (.finishRegion (external := []) rfl) ?_
    exact .cons (Source.CleanupStep.unwound (signature := signature) (algebra := algebra)
      (outcome := .exiting closedExit) rfl) .refl
  exact region.trans finish

theorem source_region_exit_has_the_same_target_failure :
    ∃ count targetFinal targetObservation,
      ExitComposition.CleanupFrameSteps (.nil : Target.Definitions signature algebra [])
        (.running (.unwind targetOriginal (.push (.region ⟨1⟩) targetParent))) count (.running (.reenter targetFinal closedExit)) ∧
      Target.HeadObservation targetFinal.control.configuration targetObservation ∧
      StateObservationRelated closed targetFinal (.failed .overflow) targetObservation := by
  have runtime : ExitRuntimeRelated original targetOriginal := ⟨rfl, rfl, ⟨rfl, .nil, .nil⟩, rfl, rfl, rfl⟩
  have contexts : ContextRelated signature algebra [] (.push (.region ⟨1⟩) parent) (.push (.region ⟨1⟩) targetParent) :=
    .push (.region ⟨1⟩) (.push (.cleanupReturn ⟨99⟩
      (some (.datum .unit : Source.RuntimeValue signature algebra [] .unit)) normal) .done)
  exact cleanup_observation_preserved (.nil : Source.Definitions signature algebra [])
    (.running (.unwind runtime contexts)) source_region_exit_composes_under_running_parent_cleanup .failed

theorem source_retirement_keeps_unrelated_owners_and_outer_storage :
    finishedRuntime.store.fields.active = initialFields.active ∧
    finishedRuntime.store.fields.spent = [⟨400⟩, ⟨300⟩, ⟨700⟩] ∧
    finishedRuntime.cells = [outer] ∧ finishedRuntime.regions = [⟨2⟩] ∧ finishedRuntime.exit = exit :=
  ⟨rfl, rfl, rfl, rfl, rfl⟩

end BoundaryV2.Generalized.Examples.SourceRegion
