import BoundaryV2.GeneralizedRegionRetirement
import BoundaryV2.GeneralizedControlExamples
import BoundaryV2.GeneralizedRegionExamples

namespace BoundaryV2.Generalized.Examples

def retirementFirstView : UseScope.ControlView := ⟨⟨11⟩, ⟨101⟩, .lexical ⟨0⟩ 0⟩
def retirementSecondView : UseScope.ControlView := ⟨⟨12⟩, ⟨102⟩, .lexical ⟨0⟩ 1⟩
abbrev RetirementType := Ty.continuation (Data := Data) .shallow .linear Effect.choose (.leaf .boolean) .unit

def retirementValue (view : UseScope.ControlView) : Target.RuntimeValue signature algebra [] RetirementType :=
  .continuation view.identity (some (view.authority, view.owner))
def retirementFuture (view : UseScope.ControlView) : SavedChoice :=
  ⟨⟨9⟩, .push (.protection ⟨view.identity.index + 70⟩ (.fault .overflow) .nil) cleanupFuture⟩
def retirementInfo (view : UseScope.ControlView) : UseScope.ControlInfo (Sigma (Target.ControlPayload signature algebra [])) :=
  ⟨view.identity, view.authority, .linear, ⟨⟨.shallow, .choose, .leaf .boolean, .unit⟩, retirementFuture view⟩⟩

def retirementFirst := Cells.allocate (signature := signature) (algebra := algebra) ⟨1⟩ (retirementValue retirementFirstView) [] []
def retirementOuter := Cells.allocate (signature := signature) (algebra := algebra) ⟨2⟩ (.datum (.leaf (type := Data.integer) 7)) retirementFirst.cells []
def retirementSecond := Cells.allocate (signature := signature) (algebra := algebra) ⟨1⟩ (retirementValue retirementSecondView) retirementOuter.cells []
def retirementCounter := Cells.allocate (signature := signature) (algebra := algebra) ⟨1⟩ (.datum (.leaf (type := Data.integer) 8)) retirementSecond.cells []

def retirementStore : Target.ControlHeap signature algebra [] :=
  ⟨⟨[.owned ⟨900⟩ (.lexical ⟨50⟩ 0)], [.continuation ⟨11⟩ [.cleanup ⟨81⟩ []], .continuation ⟨12⟩ [.cleanup ⟨82⟩ []]], [⟨700⟩]⟩,
    [retirementInfo retirementFirstView, retirementInfo retirementSecondView], []⟩
def retirementRuntime : ExitComposition.Runtime signature algebra [] :=
  ⟨⟨0⟩, .finished .abandoned, retirementStore, retirementCounter.cells, [⟨1⟩, ⟨2⟩],
    ⟨.failure .overflow, [.overflow], some "first"⟩⟩
def retirementStart : ExitComposition.RegionHandoff signature algebra [] .unit .unit :=
  ExitComposition.beginRegionHandoff ⟨1⟩ retirementRuntime .done

def retirementAfterFirst : ExitComposition.RegionHandoff signature algebra [] .unit .unit :=
  { retirementStart with runtime := { retirementRuntime with
      cells := retirementCounter.cells.take 3,
      store := { retirementStore with fields := { retirementStore.fields with
        active := retirementStore.fields.active ++ [(retirementValue retirementFirstView).owningField] } } } }

theorem first_cell_hands_its_actual_grant_to_disposal :
    retirementStart.offerNext = some (⟨RetirementType, retirementValue retirementFirstView⟩, retirementAfterFirst) ∧
    retirementAfterFirst.runtime.physicalInventory = [⟨900⟩, ⟨101⟩, ⟨102⟩] ∧
    retirementAfterFirst.runtime.exit = retirementRuntime.exit ∧
    retirementAfterFirst.runtime.liveRegions = [⟨1⟩, ⟨2⟩] := ⟨rfl, rfl, rfl, rfl⟩

def retirementReleasedStore : Target.ControlHeap signature algebra [] :=
  ⟨⟨retirementStore.fields.active, retirementStore.fields.retained, [⟨101⟩, ⟨700⟩]⟩,
    [retirementInfo retirementSecondView], [retirementInfo retirementFirstView]⟩

theorem offered_linear_continuation_requires_and_accepts_explicit_release :
    UseScope.release .affineDrop retirementFirstView retirementAfterFirst.runtime.store = none ∧
    UseScope.release .explicit retirementFirstView retirementAfterFirst.runtime.store = some retirementReleasedStore ∧
    retirementReleasedStore.disposing = [retirementInfo retirementFirstView] ∧
    UseScope.release .explicit retirementFirstView retirementReleasedStore = none := ⟨rfl, rfl, rfl, rfl⟩

def retirementDisposingStore : Target.ControlHeap signature algebra [] :=
  ⟨⟨.cleanup ⟨81⟩ [] :: retirementStore.fields.active, [.continuation ⟨12⟩ [.cleanup ⟨82⟩ []]], [⟨101⟩, ⟨700⟩]⟩,
    [retirementInfo retirementSecondView], []⟩
def retirementDisposingRuntime : ExitComposition.Runtime signature algebra [] :=
  { retirementAfterFirst.runtime with store := retirementDisposingStore }

theorem released_cell_opens_its_actual_saved_cleanup_context :
    UseScope.beginDisposal retirementReleasedStore =
      some ⟨retirementDisposingStore, (retirementInfo retirementFirstView).future⟩ ∧
    ExitComposition.beginControlUnwind { retirementAfterFirst.runtime with store := retirementReleasedStore } =
      some ⟨⟨.shallow, .choose, .leaf .boolean, .unit⟩,
        .seeking retirementDisposingRuntime (retirementFuture retirementFirstView).future⟩ := ⟨rfl, rfl⟩

def retirementCleanupPending : ExitComposition.Runtime signature algebra [] :=
  { retirementDisposingRuntime with id := ⟨81⟩, phase := .pending ⟨[], .fault .overflow, .nil⟩ }
def retirementCleanupFinished : ExitComposition.Runtime signature algebra [] :=
  { retirementCleanupPending with
    phase := .finished (.failed .overflow)
    exit := retirementCleanupPending.exit.cleanupFailure .overflow }

theorem cell_disposal_runs_saved_cleanup_and_preserves_prior_failure :
    ExitComposition.UnwindSteps (.nil : Target.Definitions signature algebra [])
      (.seeking retirementDisposingRuntime (retirementFuture retirementFirstView).future) [⟨81⟩]
      (.complete retirementCleanupFinished) ∧
    retirementCleanupFinished.exit = ⟨.failure .overflow, [.overflow, .overflow], some "first"⟩ ∧
    retirementCleanupFinished.cells = retirementAfterFirst.runtime.cells := by
  let started : ExitComposition.Runtime signature algebra [] :=
    { retirementCleanupPending with
      phase := .running (.code (.fault .overflow) (.cons (.exit retirementCleanupPending.exit) .nil) .nil .done) .active }
  let failed : ExitComposition.Runtime signature algebra [] :=
    { started with phase := .running (.failed .overflow (.done : Target.Stack signature algebra [] .unit .unit)) .active }
  have beginStep : ExitComposition.RuntimeStep (.nil : Target.Definitions signature algebra []) retirementCleanupPending 1 started :=
    .lifecycle .begin
  have faultStep : ExitComposition.RuntimeStep (.nil : Target.Definitions signature algebra []) started 0 failed :=
    .execute (Target.ExecutionStep.cell (signature := signature) (algebra := algebra) (.ordinary .fault))
  have finishStep : ExitComposition.RuntimeStep (.nil : Target.Definitions signature algebra []) failed 0 retirementCleanupFinished :=
    .lifecycle .failed
  have cleanup : ExitComposition.RuntimeSteps (.nil : Target.Definitions signature algebra []) retirementCleanupPending 1 retirementCleanupFinished :=
    .cons beginStep (.cons faultStep (.cons finishStep .refl))
  have unwound := ExitComposition.run_selected_cleanup cleanupFuture cleanup rfl (by intro impossible; cases impossible)
  refine ⟨?_, rfl, rfl⟩
  exact ExitComposition.UnwindSteps.cons (signature := signature) (algebra := algebra)
    (.select (by intro impossible; cases impossible) rfl)
    (unwound.trans (.cons (.complete rfl) .refl))

def retirementUpdatedCells : Cells signature algebra (fun context result => Target.Code signature algebra [] context [] result) :=
  ⟨⟨3⟩, ⟨1⟩, .leaf .integer, .datum (.leaf 9)⟩ :: retirementAfterFirst.runtime.cells.drop 1

theorem untaken_cells_remain_available_and_keep_current_contents :
    Cells.writeCopy (signature := signature) (algebra := algebra) ⟨3⟩ ⟨1⟩ (.datum (.leaf (type := Data.integer) 9))
      retirementAfterFirst.runtime.cells = some retirementUpdatedCells ∧
    Cells.takeOldest ⟨1⟩ retirementUpdatedCells =
      some (⟨⟨2⟩, ⟨1⟩, RetirementType, retirementValue retirementSecondView⟩,
        [⟨⟨3⟩, ⟨1⟩, .leaf .integer, .datum (.leaf 9)⟩, ⟨⟨1⟩, ⟨2⟩, .leaf .integer, .datum (.leaf 7)⟩]) ∧
    Cells.takeOldest (signature := signature) (algebra := algebra) ⟨1⟩
      ([⟨⟨3⟩, ⟨1⟩, .leaf .integer, .datum (.leaf 9)⟩, ⟨⟨1⟩, ⟨2⟩, .leaf .integer, .datum (.leaf 7)⟩] :
        Cells signature algebra (fun context result => Target.Code signature algebra [] context [] result)) =
      some (⟨⟨3⟩, ⟨1⟩, .leaf .integer, .datum (.leaf 9)⟩, [⟨⟨1⟩, ⟨2⟩, .leaf .integer, .datum (.leaf 7)⟩]) := by
  refine ⟨?_, rfl, rfl⟩
  simp [Cells.writeCopy, Cells.exchange, retirementAfterFirst, retirementRuntime, retirementCounter,
    retirementSecond, retirementOuter, retirementFirst, Cells.allocate, Cells.identities, FreshNames.bound,
    retirementUpdatedCells, Value.copyable, Datum.copyable]

theorem retiring_cells_follows_allocation_order_and_keeps_outer_storage :
    Cells.Retires ⟨1⟩ retirementCounter.cells
      [⟨⟨0⟩, ⟨1⟩, RetirementType, retirementValue retirementFirstView⟩,
        ⟨⟨2⟩, ⟨1⟩, RetirementType, retirementValue retirementSecondView⟩,
        ⟨⟨3⟩, ⟨1⟩, .leaf .integer, .datum (.leaf 8)⟩]
      [⟨⟨1⟩, ⟨2⟩, .leaf .integer, .datum (.leaf 7)⟩] :=
  .cons rfl (.cons rfl (.cons rfl .refl))

theorem region_handoff_maps_dormant_computation_bodies :
    Cells.handoffRegion ⟨1⟩ (Defunctionalization.cells regionEntryCells) =
      ⟨Defunctionalization.cells (Cells.handoffRegion ⟨1⟩ regionEntryCells).pending,
        Defunctionalization.cells (Cells.handoffRegion ⟨1⟩ regionEntryCells).remaining⟩ :=
  Cells.handoff_commutes_with_body_mapping (fun _ _ body => Defunctionalization.computation body) _ _

/-- A later cleanup can borrow an earlier plain cell. Retiring that cell's
zero-owner value must not remove the storage needed by the cleanup. -/
def retirementEarlierPlainRuntime : ExitComposition.Runtime signature algebra [] :=
  { retirementRuntime with cells :=
    [⟨⟨1⟩, ⟨1⟩, RetirementType, retirementValue retirementFirstView⟩,
      ⟨⟨0⟩, ⟨1⟩, .leaf .integer, .datum (.leaf 7)⟩] }
def retirementEarlierPlainStart : ExitComposition.RegionHandoff signature algebra [] .unit .unit :=
  ExitComposition.beginRegionHandoff ⟨1⟩ retirementEarlierPlainRuntime .done
def retirementEarlierPlainKept := { retirementEarlierPlainStart with kept := [⟨0⟩] }
def retirementLaterOwner : ExitComposition.RegionHandoff signature algebra [] .unit .unit :=
  { retirementEarlierPlainKept with runtime := { retirementEarlierPlainRuntime with
      cells := [⟨⟨0⟩, ⟨1⟩, .leaf .integer, .datum (.leaf 7)⟩]
      store := retirementAfterFirst.runtime.store } }

theorem earlier_plain_cell_remains_readable_for_later_cleanup :
    retirementEarlierPlainStart.offerNext = some (⟨.leaf .integer, .datum (.leaf 7)⟩, retirementEarlierPlainKept) ∧
    retirementEarlierPlainKept.offerNext = some (⟨RetirementType, retirementValue retirementFirstView⟩, retirementLaterOwner) ∧
    retirementLaterOwner.offerNext = none ∧
    Cells.readCopy (signature := signature) (algebra := algebra) ⟨0⟩ ⟨1⟩ (.leaf .integer)
      retirementLaterOwner.runtime.cells = some (.datum (.leaf 7)) := by
  refine ⟨rfl, rfl, rfl, ?_⟩
  simp [Cells.readCopy, Cells.read, Cells.lookup, retirementLaterOwner, Value.copyable, Datum.copyable]

theorem later_cleanup_can_execute_the_preserved_cell_read :
    Target.ExecutionStep (.nil : Target.Definitions signature algebra [])
      (⟨⟨retirementLaterOwner.runtime.store, .code (.cellRead .ret) .nil (.cons (.cell ⟨0⟩ ⟨1⟩) .nil) .done⟩,
        retirementLaterOwner.runtime.cells, retirementLaterOwner.runtime.liveRegions⟩ : Target.State signature algebra [] (.leaf .integer))
      ⟨⟨retirementLaterOwner.runtime.store, .code .ret .nil (.cons (.datum (.leaf 7)) .nil) .done⟩,
        retirementLaterOwner.runtime.cells, retirementLaterOwner.runtime.liveRegions⟩ := by
  exact .cell (.read List.mem_cons_self earlier_plain_cell_remains_readable_for_later_cleanup.2.2.2)

end BoundaryV2.Generalized.Examples
