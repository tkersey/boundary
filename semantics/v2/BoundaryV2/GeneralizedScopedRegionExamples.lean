import BoundaryV2.GeneralizedScopedRegions
import BoundaryV2.GeneralizedLifetimeExamples
import BoundaryV2.GeneralizedRegionExamples

namespace BoundaryV2.Generalized.Examples.ScopedRegions

def bindings : RegionBindings := [⟨⟨100⟩, ⟨1⟩⟩, ⟨⟨101⟩, ⟨3⟩⟩, ⟨⟨200⟩, ⟨2⟩⟩, ⟨⟨0⟩, ⟨0⟩⟩]

theorem original_and_retained_bindings_are_valid :
    bindings.valid ScopeExamples.original = true ∧ bindings.valid ScopeExamples.retained = true := ⟨rfl, rfl⟩

theorem actual_retention_keeps_region_owners_without_rebinding :
    Scope.retain ⟨2⟩ ⟨4⟩ [⟨2⟩, ⟨0⟩] ScopeExamples.original = some ⟨⟨5⟩, ScopeExamples.retained⟩ ∧
    bindings.valid ScopeExamples.retained = true :=
  ⟨rfl, RegionBindings.retaining_scopes_preserves_region_associations original_and_retained_bindings_are_valid.1
    (show Scope.retain ⟨2⟩ ⟨4⟩ [⟨2⟩, ⟨0⟩] ScopeExamples.original = some ⟨⟨5⟩, ScopeExamples.retained⟩ from rfl)⟩

def cells : Cells signature algebra (fun context result => Target.Code signature algebra [] context [] result) :=
  [⟨⟨10⟩, ⟨100⟩, .borrowed ⟨0⟩, .datum (.borrowed ⟨8⟩ ⟨3⟩)⟩,
    ⟨⟨11⟩, ⟨101⟩, .leaf .integer, .datum (.leaf 8)⟩,
    ⟨⟨20⟩, ⟨200⟩, .leaf .integer, .datum (.leaf 7)⟩]
def runtime : ExitComposition.Runtime signature algebra [] :=
  { Lifetime.completed with cells := cells, liveRegions := bindings.regions }
def scope : ExitComposition.ScopeExit signature algebra [] .unit :=
  ⟨runtime, .returned (.datum .unit) .done⟩
def after : ExitComposition.ScopedRegionExit signature algebra [] .unit :=
  ⟨.reenter ⟨⟨runtime.store, .returned (.datum .unit) .done⟩, cells.drop 2, [⟨200⟩, ⟨0⟩]⟩ runtime.exit,
    .node ⟨1⟩ [.node ⟨3⟩ []], ScopeExamples.afterCreatorClosed, bindings.drop 2⟩

theorem creator_close_derives_its_regions_and_preserves_retained_work :
    ExitComposition.finishScopedRegions ⟨1⟩ ScopeExamples.retained bindings scope [] = some after ∧
    after.resolution.regions = [⟨200⟩, ⟨0⟩] ∧ after.resolution.cells.identities = [⟨20⟩] ∧
    UseScope.inventory after.resolution.store.fields = [⟨7⟩] ∧
    Scope.path ⟨2⟩ after.forest = some [⟨0⟩, ⟨4⟩, ⟨5⟩, ⟨2⟩] := ⟨rfl, rfl, rfl, rfl, rfl⟩

theorem resulting_bindings_and_liveness_are_valid_together :
    after.bindings.valid after.forest = true ∧ after.resolution.regions.Perm after.bindings.regions :=
  ExitComposition.scoped_region_exit_keeps_bindings_and_runtime_in_agreement creator_close_derives_its_regions_and_preserves_retained_work.1

theorem binding_order_does_not_change_which_regions_close :
    ExitComposition.finishScopedRegions ⟨1⟩ ScopeExamples.retained bindings.reverse scope [] =
      some { after with bindings := after.bindings.reverse } := rfl

theorem a_surviving_younger_borrow_blocks_the_combined_close :
    ExitComposition.finishScopedRegions ⟨1⟩ ScopeExamples.retained bindings scope [.name .scope ⟨3⟩] = none ∧
    ExitComposition.finishScopedRegions ⟨1⟩ ScopeExamples.retained bindings
      (⟨runtime, .returned (.datum (.borrowed ⟨8⟩ ⟨3⟩))
        (.done : Target.Stack signature algebra [] (.borrowed ⟨0⟩) (.borrowed ⟨0⟩))⟩) [] = none := ⟨rfl, rfl⟩

theorem incomplete_duplicate_or_dead_scope_bindings_reject :
    ExitComposition.finishScopedRegions ⟨1⟩ ScopeExamples.retained (bindings.drop 1) scope [] = none ∧
    ExitComposition.finishScopedRegions ⟨1⟩ ScopeExamples.retained (⟨⟨100⟩, ⟨2⟩⟩ :: bindings)
      { scope with cleanup := { runtime with liveRegions := ⟨100⟩ :: runtime.liveRegions } } [] = none ∧
    ExitComposition.finishScopedRegions ⟨1⟩ ScopeExamples.retained (⟨⟨300⟩, ⟨99⟩⟩ :: bindings)
      { scope with cleanup := { runtime with liveRegions := ⟨300⟩ :: runtime.liveRegions } } [] = none := ⟨rfl, rfl, rfl⟩

theorem captured_cleanup_prevents_scope_and_region_retirement :
    ExitComposition.finishScopedRegions ⟨1⟩ ScopeExamples.retained bindings
      { scope with cleanup := { runtime with phase := .running (.returned (.datum .unit) .done) (.captured ⟨17⟩) } } [] = none := rfl

def entryBindings : RegionBindings := [⟨⟨1⟩, ⟨0⟩⟩, ⟨⟨50⟩, ⟨4⟩⟩]

theorem ordinary_region_entry_registers_its_computed_fresh_name :
    entryBindings.regions = regionEntryLive ∧
    RegionBindings.bind enteredRegion ⟨1⟩ ScopeExamples.original entryBindings =
      some (⟨enteredRegion, ⟨1⟩⟩ :: entryBindings) ∧
    RegionBindings.regions (⟨enteredRegion, ⟨1⟩⟩ :: entryBindings) = regionEntrySourceInside.liveRegions ∧
    RegionBindings.valid ScopeExamples.original (⟨enteredRegion, ⟨1⟩⟩ :: entryBindings) = true := ⟨rfl, rfl, rfl, rfl⟩

theorem registration_rejects_rebinding_and_unknown_scope :
    RegionBindings.bind ⟨1⟩ ⟨1⟩ ScopeExamples.original entryBindings = none ∧
    RegionBindings.bind ⟨51⟩ ⟨99⟩ ScopeExamples.original entryBindings = none := ⟨rfl, rfl⟩

end BoundaryV2.Generalized.Examples.ScopedRegions
