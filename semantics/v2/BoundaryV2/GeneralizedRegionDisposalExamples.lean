import BoundaryV2.GeneralizedCleanupCompletion
import BoundaryV2.GeneralizedExamples
import BoundaryV2.GeneralizedDisposalExecution

namespace BoundaryV2.Generalized.Examples.RegionDisposal

open ExitComposition

def owner : Owner := .lexical ⟨0⟩ 1
def resource : Target.RuntimeValue signature algebra [] (.resource ⟨1⟩) :=
  .datum (.resource ⟨8⟩ ⟨300⟩ owner)
def plain : Target.RuntimeValue signature algebra [] (.leaf .integer) := .datum (.leaf 7)
def outer : Cell signature algebra (fun context result => Target.Code signature algebra [] context [] result) :=
  ⟨⟨2⟩, ⟨2⟩, .leaf .integer, .datum (.leaf 9)⟩
def original : Runtime signature algebra [] :=
  ⟨⟨7⟩, .finished .abandoned,
    ⟨⟨[.owned ⟨900⟩ (.lexical ⟨50⟩ 0)], [], [⟨700⟩]⟩, [], []⟩,
    [⟨⟨1⟩, ⟨1⟩, .resource ⟨1⟩, resource⟩, outer, ⟨⟨0⟩, ⟨1⟩, .leaf .integer, plain⟩],
    [⟨1⟩, ⟨2⟩], ⟨.failure .overflow, [.overflow], some "first"⟩⟩
def start : RegionHandoff signature algebra [] .unit .unit := beginRegionHandoff ⟨1⟩ original .done
def kept : RegionHandoff signature algebra [] .unit .unit := { start with kept := [⟨0⟩] }
def offered : Runtime signature algebra [] :=
  { original with
    store := { original.store with fields := { original.store.fields with
      active := original.store.fields.active ++ [resource.owningField] } }
    cells := [outer, ⟨⟨0⟩, ⟨1⟩, .leaf .integer, plain⟩] }
def consumed : Runtime signature algebra [] :=
  { offered with store := { offered.store with fields :=
      ⟨original.store.fields.active, [], [⟨300⟩, ⟨700⟩]⟩ } }
def ready : RegionHandoff signature algebra [] .unit .unit := ⟨⟨1⟩, consumed, .done, [⟨0⟩]⟩
def finished : Resolution signature algebra [] .unit :=
  .unwind { consumed with cells := [outer], liveRegions := [⟨2⟩] } .done

theorem actual_cell_values_are_disposed_in_creation_order (retained : List Reference := []) :
    RegionDisposalSteps (.nil : Target.Definitions signature algebra [])
      (.offering start) 6 (.offering ready) retained := by
  refine .cons (middle := .disposing ⟨1⟩ .done [⟨0⟩] (ValueDisposal.start original plain)) (.offer rfl) ?_
  refine .cons (middle := .disposing ⟨1⟩ .done [⟨0⟩] (.ready original [])) (.values (.stale rfl)) ?_
  refine .cons (middle := .offering kept) (.returnValue rfl) ?_
  refine .cons (middle := .disposing ⟨1⟩ .done [⟨0⟩] (ValueDisposal.start offered resource)) (.offer rfl) ?_
  refine .cons (middle := .disposing ⟨1⟩ .done [⟨0⟩] (.ready consumed [])) ?_ ?_
  · exact .values (.resource rfl)
  · exact .cons (.returnValue rfl) .refl

theorem handoff_keeps_plain_storage_until_disposal_finishes :
    Cells.readCopy (signature := signature) (algebra := algebra) ⟨0⟩ ⟨1⟩ (.leaf .integer) offered.cells = some plain ∧
    RegionDisposal.finish [] (.disposing ⟨1⟩ (.done : Target.Stack signature algebra [] .unit .unit)
      [⟨0⟩] (ValueDisposal.start offered resource)) = none ∧
    RegionDisposal.finish [.name .cell ⟨0⟩] (.offering ready) = none ∧
    RegionDisposal.finish [] (.offering ready) = some finished := by
  refine ⟨?_, rfl, rfl, rfl⟩
  simp [Cells.readCopy, Cells.read, Cells.lookup, offered, outer, plain, Value.copyable, Datum.copyable]

theorem cleanup_frame_execution_uses_the_same_region_disposal :
    CleanupFrameSteps (.nil : Target.Definitions signature algebra [])
      (.running (.unwind original (.push (.region ⟨1⟩) .done))) 8 (.running finished) := by
  refine .cons (middle := .region (.offering start)) (.enterRegion rfl) ?_
  have region := CleanupFrameSteps.of_region actual_cell_values_are_disposed_in_creation_order
  have finish : CleanupFrameSteps (.nil : Target.Definitions signature algebra [])
      (.region (.offering ready)) 1 (.running finished) := .cons (.finishRegion (external := []) rfl) .refl
  exact region.trans finish

theorem completed_region_keeps_unrelated_resources_and_original_exit :
    finished.store.fields.active = original.store.fields.active ∧
    finished.store.fields.spent = [⟨300⟩, ⟨700⟩] ∧
    finished.cells = [outer] ∧ finished.regions = [⟨2⟩] ∧ finished.exitInfo = original.exit :=
  ⟨rfl, rfl, rfl, rfl, rfl⟩

def parent : CleanupParent signature algebra [] :=
  ⟨⟨⟨99⟩, ⟨.normal, [], none⟩⟩, .returned (.datum .unit) .done⟩
def nestedBefore : NestedCleanup signature algebra [] :=
  ⟨CleanupMemory.ofRuntime original, CleanupInfo.ofRuntime original,
    .unwinding original.exit (.push (.region ⟨1⟩) .done), [parent]⟩
def nestedAfter : NestedCleanup signature algebra [] :=
  { nestedBefore with
    memory := CleanupMemory.ofRuntime { consumed with cells := [outer], liveRegions := [⟨2⟩] }
    focus := .unwinding original.exit (.done : Target.Stack signature algebra [] .unit .unit) }

def disposalCaller : Target.Stack signature algebra [] .unit (.leaf .integer) :=
  .push (.returnTo (.enter (.push (.leaf 42) .ret)) .nil .nil) .done
def abandonedResume : ResumePoint signature algebra [] .unit := .unwind .done

/-- The resource consumed inside the region stays consumed when the nested
cleanup resumes. Its suspended parent and the distinct disposal caller survive. -/
theorem nested_abandonment_uses_current_region_disposal :
    NestedProgressSteps (.nil : Target.Definitions signature algebra [])
      (.active nestedBefore) 8 (.active nestedAfter)
      (abandonedResume.references ++ disposalCaller.installationReferences) ∧
    Target.DisposalRun (.nil : Target.Definitions signature algebra [])
      (.nested (.active nestedBefore) abandonedResume disposalCaller) 8
      (.nested (.active nestedAfter) abandonedResume disposalCaller) ∧
    nestedAfter.memory.store.fields.spent = [⟨300⟩, ⟨700⟩] ∧
    nestedAfter.memory.store.fields.active = original.store.fields.active ∧
    nestedAfter.memory.cells = [outer] ∧ nestedAfter.memory.regions = [⟨2⟩] ∧
    nestedAfter.current = nestedBefore.current ∧ nestedAfter.parents = [parent] ∧
    nestedAfter.finished = none := by
  have run : NestedProgressSteps (.nil : Target.Definitions signature algebra [])
      (.active nestedBefore) 8 (.active nestedAfter)
      (abandonedResume.references ++ disposalCaller.installationReferences) :=
    nested_region_finite_handoff (external := []) rfl
      (actual_cell_values_are_disposed_in_creation_order _) rfl
  exact ⟨run, Target.DisposalRun.nested_progress_steps abandonedResume disposalCaller run,
    rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

def cellCaller : Target.Stack signature algebra [] (.cell (.leaf .integer)) .unit :=
  .push (.returnTo (.enter (.push .unit .ret)) .nil .nil) .done
def retainingParent : CleanupParent signature algebra [] :=
  { parent with resume := .returned (.cell ⟨0⟩ ⟨1⟩) cellCaller }

/-- Even after all offered values finish, a saved parent result keeps its
cell's storage live. The parent roots are supplied by the operation itself. -/
theorem nested_saved_result_prevents_early_retirement :
    NestedProgress.finishRegion []
      (.region nestedBefore.current [retainingParent] (.offering ready)) = none ∧
    NestedProgress.finishRegion retainingParent.resume.references
      (.region nestedBefore.current [] (.offering ready)) = none ∧
    NestedProgress.finished
      (.region nestedBefore.current [parent] (.disposing ⟨1⟩ .done [⟨0⟩]
        (ValueDisposal.start offered resource))) = none := ⟨rfl, rfl, rfl⟩

/-- This includes arbitrary executing and captured cleanup cursors. The old
entry points admitted all four handoffs even with an unfinished phase. -/
theorem unfinished_cleanup_retains_its_work (phase : Phase signature algebra [])
    (unfinished : phase.unfinished = true) :
    let runtime := { original with phase := phase }
    ExitComposition.RegionDisposal.begin
      (.unwind runtime (.push (.region ⟨1⟩) (.done : Target.Stack signature algebra [] .unit .unit))) = none ∧
    ExitComposition.RegionDisposal.offer
      (.offering (beginRegionHandoff ⟨1⟩ runtime (.done : Target.Stack signature algebra [] .unit .unit))) = none ∧
    beginAbruptCleanup (.unwind runtime
      (.push (.protection ⟨20⟩ (.fault .overflow) .nil) (.done : Target.Stack signature algebra [] .unit .unit))) = none ∧
    finishCleanupFrame (.unwind runtime
      (.push (.cleanupReturn ⟨20⟩ none ⟨.abandoned, [], none⟩) (.done : Target.Stack signature algebra [] .unit .unit))) = none := by
  cases phase <;> simp_all [Phase.unfinished, ExitComposition.RegionDisposal.begin,
    ExitComposition.RegionDisposal.offer, beginRegionHandoff, beginAbruptCleanup,
    finishCleanupFrame, Resolution.cleanupFinished]

end BoundaryV2.Generalized.Examples.RegionDisposal
