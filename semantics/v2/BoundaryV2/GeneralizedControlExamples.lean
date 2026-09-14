import BoundaryV2.GeneralizedExamples
import BoundaryV2.GeneralizedOwnedResume

namespace BoundaryV2.Generalized.Examples

def parentView : UseScope.ControlView := ⟨⟨10⟩, ⟨100⟩, .lexical ⟨0⟩ 0⟩
def childView : UseScope.ControlView := ⟨⟨11⟩, ⟨101⟩, .control 10 0⟩

abbrev SavedChoice := Target.Resumption signature algebra [] .shallow .choose (.leaf .boolean) .unit

def childFuture : SavedChoice := ⟨⟨9⟩, cleanupFuture⟩

def childBinding : Target.RuntimeEnvironment signature algebra []
    [.continuation .shallow .linear .choose (.leaf .boolean) .unit] :=
  .cons (.continuation childView.identity (some (childView.authority, childView.owner))) .nil

/-- The parent's actual saved code refers to the child by its current view. -/
def parentFuture : SavedChoice :=
  ⟨⟨8⟩, .push (.returnTo
      (.enter (.load (.there .here) (.load .here (.resume .ret))))
      childBinding .nil) .done⟩

def parentInfo : UseScope.ControlInfo SavedChoice := ⟨parentView.identity, parentView.authority, .affine, parentFuture⟩
def childInfo : UseScope.ControlInfo SavedChoice := ⟨childView.identity, childView.authority, .linear, childFuture⟩

/-- The child grant lives inside the parent, while the child's nonowning
registry entry and its separately stored capture scope remain available. -/
def nestedControlStore : UseScope.ControlStore SavedChoice :=
  ⟨⟨[.owned parentView.authority parentView.owner],
      [.continuation parentView.identity [.owned childView.authority childView.owner],
        .continuation childView.identity []], []⟩,
    [parentInfo, childInfo], []⟩

def activatedParentStore : UseScope.ControlStore SavedChoice :=
  ⟨⟨[.owned childView.authority childView.owner], [.continuation childView.identity []], [parentView.authority]⟩,
    [childInfo], []⟩

def activatedChildStore : UseScope.ControlStore SavedChoice :=
  ⟨⟨[], [], [childView.authority, parentView.authority]⟩, [], []⟩

theorem nested_control_has_two_physical_owners :
    UseScope.inventory nestedControlStore.fields = [parentView.authority, childView.authority] := rfl

theorem nested_control_store_valid : UseScope.ControlStore.Valid nestedControlStore := by
  simp [UseScope.ControlStore.Valid, UseScope.Valid, UseScope.inventory, UseScope.tokens, UseScope.Field.tokens,
    nestedControlStore, parentInfo, childInfo, parentView, childView]

theorem sealed_child_cannot_resume : UseScope.acquire childView nestedControlStore = none := rfl

theorem parent_acquisition_exposes_child_without_losing_its_future :
    UseScope.acquire parentView nestedControlStore = some ⟨activatedParentStore, parentFuture⟩ := rfl

theorem old_child_owner_is_stale :
    UseScope.acquire { childView with owner := .lexical ⟨0⟩ 1 } activatedParentStore = none := rfl

theorem child_acquisition_uses_original_future :
    UseScope.acquire childView activatedParentStore = some ⟨activatedChildStore, childFuture⟩ := rfl

theorem owned_child_resume_consumes_before_execution :
    Target.resumeOwned childView activatedParentStore (.datum (.leaf true)) .done =
      some ⟨activatedChildStore, .returned (.datum (.leaf true)) cleanupFuture⟩ := rfl

theorem child_cannot_resume_twice : UseScope.acquire childView activatedChildStore = none := rfl

theorem linear_child_requires_explicit_disposition :
    UseScope.release .affineDrop childView activatedParentStore = none := rfl

theorem disposal_preserves_nested_child_and_cleanup_work :
    UseScope.release .explicit parentView nestedControlStore =
      some ⟨⟨[], nestedControlStore.fields.retained, [parentView.authority]⟩, [childInfo], [parentInfo]⟩ := rfl

end BoundaryV2.Generalized.Examples
