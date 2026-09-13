import BoundaryV2.GeneralizedRegionClosure
import BoundaryV2.GeneralizedLifetimeExamples
import BoundaryV2.GeneralizedRegionRetirementExamples

namespace BoundaryV2.Generalized.Examples.RegionClosure

def cells : Cells signature algebra (fun context result => Target.Code signature algebra [] context [] result) :=
  [⟨⟨10⟩, ⟨1⟩, .leaf .integer, .datum (.leaf 8)⟩,
    ⟨⟨20⟩, ⟨2⟩, .leaf .integer, .datum (.leaf 7)⟩]
def runtime : ExitComposition.Runtime signature algebra [] :=
  { Lifetime.completed with cells := cells, liveRegions := [⟨1⟩, ⟨2⟩] }
def scope : ExitComposition.ScopeExit signature algebra [] .unit :=
  ⟨runtime, .returned (.datum .unit) .done⟩
def after : ExitComposition.Resolution signature algebra [] .unit :=
  .reenter ⟨⟨runtime.store, .returned (.datum .unit) .done⟩, cells.drop 1, [⟨2⟩]⟩ runtime.exit

theorem completed_region_removes_storage_and_liveness_together :
    ExitComposition.finishRegions [⟨1⟩] scope [] = some after ∧
    after.cells.identities = [⟨20⟩] ∧ after.regions = [⟨2⟩] ∧
    UseScope.inventory after.store.fields = [⟨7⟩] := ⟨rfl, rfl, rfl, rfl⟩

theorem outer_cell_keeps_its_value_and_closed_cell_is_unavailable :
    Cells.readCopy (signature := signature) (algebra := algebra) ⟨20⟩ ⟨2⟩ (.leaf .integer) after.cells = some (.datum (.leaf 7)) ∧
    Cells.readCopy (signature := signature) (algebra := algebra) ⟨10⟩ ⟨1⟩ (.leaf .integer) after.cells = none := by
  constructor <;> simp [after, cells, ExitComposition.Resolution.cells, Cells.readCopy, Cells.read,
    Cells.lookup, Value.copyable, Datum.copyable]

theorem an_unhanded_linear_owner_prevents_storage_retirement :
    ExitComposition.finishRegions [⟨1⟩]
      (⟨retirementRuntime, .unwind (.done : Target.Stack signature algebra [] .unit .unit)⟩) [] = none := rfl

theorem returned_cell_and_misannotated_cell_aliases_both_prevent_retirement :
    ExitComposition.finishRegions [⟨1⟩]
      (⟨runtime, .returned (.cell ⟨10⟩ ⟨1⟩) (.done : Target.Stack signature algebra [] (.cell (.leaf .integer)) (.cell (.leaf .integer)))⟩) [] = none ∧
    ExitComposition.finishRegions [⟨1⟩]
      (⟨runtime, .returned (.cell ⟨10⟩ ⟨2⟩) (.done : Target.Stack signature algebra [] (.cell (.leaf .integer)) (.cell (.leaf .integer)))⟩) [] = none :=
  ⟨rfl, rfl⟩

def outerAlias : Cell signature algebra (fun context result => Target.Code signature algebra [] context [] result) :=
  ⟨⟨30⟩, ⟨2⟩, .cell (.leaf .integer), .cell ⟨10⟩ ⟨1⟩⟩

theorem a_borrow_in_surviving_storage_prevents_retirement :
    ExitComposition.finishRegions [⟨1⟩]
      { scope with cleanup := { runtime with cells := outerAlias :: cells } } [] = none := rfl

def savedRegion : UseScope.ControlInfo (Sigma (Target.ControlPayload signature algebra [])) :=
  { retirementInfo retirementFirstView with
    future := ⟨⟨.shallow, .choose, .leaf .boolean, .unit⟩, ⟨⟨9⟩, .push (.region ⟨1⟩) cleanupFuture⟩⟩ }

theorem retained_and_disposing_futures_are_mandatory_roots :
    ExitComposition.finishRegions [⟨1⟩]
      { scope with cleanup := { runtime with store := { runtime.store with controls := [savedRegion] } } } [] = none ∧
    ExitComposition.finishRegions [⟨1⟩]
      { scope with cleanup := { runtime with store := { runtime.store with disposing := [savedRegion] } } } [] = none :=
  ⟨rfl, rfl⟩

theorem pending_and_captured_running_cleanup_keep_region_storage_live :
    ExitComposition.finishRegions [⟨1⟩]
      { scope with cleanup := { runtime with phase := .pending ⟨[], .push .unit .ret, .nil⟩ } } [] = none ∧
    ExitComposition.finishRegions [⟨1⟩]
      { scope with cleanup := { runtime with phase := .running (.returned (.datum .unit) .done) (.captured ⟨17⟩) } } [] = none :=
  ⟨rfl, rfl⟩

theorem external_saved_work_prevents_retirement :
    ExitComposition.finishRegions [⟨1⟩] scope [.name .region ⟨1⟩] = none ∧
    ExitComposition.finishRegions [⟨1⟩] scope [.name .cell ⟨10⟩] = none := ⟨rfl, rfl⟩

theorem retirement_keeps_first_reason_and_ordered_failures :
    let failed := { runtime with
      phase := .finished (.failed .overflow)
      exit := (⟨.failure .overflow, [.overflow, .overflow], some "first"⟩ : ExitInfo Fault String) }
    ExitComposition.finishRegions [⟨1⟩]
      (⟨failed, .unwind (.done : Target.Stack signature algebra [] .unit .unit)⟩) [] =
      some (.reenter ⟨⟨runtime.store, .failed .overflow .done⟩, cells.drop 1, [⟨2⟩]⟩
        ⟨.failure .overflow, [.overflow, .overflow], some "first"⟩) := rfl

theorem cancellation_keeps_its_unwind_continuation_after_retirement :
    let cancelled := { runtime with exit := (⟨.cancelled, [.overflow], some "first"⟩ : ExitInfo Fault String) }
    ExitComposition.finishRegions [⟨1⟩]
      (⟨cancelled, .unwind (.done : Target.Stack signature algebra [] .unit .unit)⟩) [] =
      some (.unwind { cancelled with cells := cells.drop 1, liveRegions := [⟨2⟩] } .done) := rfl

end BoundaryV2.Generalized.Examples.RegionClosure
