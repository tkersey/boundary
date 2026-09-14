import BoundaryV2.GeneralizedOwnedRelocation
import BoundaryV2.GeneralizedRelocationExamples
import BoundaryV2.GeneralizedControlExamples
import BoundaryV2.GeneralizedSuccessorExamples

namespace BoundaryV2.Generalized.Examples

theorem shift_owners_is_injective (first second : Owner)
    (same : shiftReferences.owner first = shiftReferences.owner second) : first = second := by
  cases first <;> cases second
  all_goals first | (cases same; done) | skip
  case lexical.lexical firstScope firstSlot secondScope secondSlot =>
    have equal := Owner.lexical.inj same
    have scopes := shift_references_is_injective equal.1
    cases scopes
    cases equal.2
    rfl
  case control.control firstId firstSlot secondId secondSlot =>
    have equal := Owner.control.inj same
    have identities := Nat.add_right_cancel equal.1
    cases identities
    cases equal.2
    rfl
  case package.package firstId firstSlot secondId secondSlot =>
    have equal := Owner.package.inj same
    have identities := Nat.add_right_cancel equal.1
    cases identities
    cases equal.2
    rfl
  case cleanup.cleanup firstId secondId =>
    have identities := Nat.add_right_cancel (Owner.cleanup.inj same)
    cases identities
    rfl

theorem shift_lookup_faithful (view : UseScope.ControlView) (store : UseScope.ControlStore Future) :
    UseScope.LookupRelocation shiftReferences view store :=
  .of_injective shiftReferences view store
    (fun _ _ same => shift_references_is_injective same)
    (fun _ _ same => shift_references_is_injective same) shift_owners_is_injective

theorem relocated_nested_store_preserves_physical_ownership :
    (nestedControlStore.relocate shiftReferences (Target.Resumption.relocate shiftReferences)).Valid := by
  apply UseScope.control_store_relocation_preserves_ownership _ _ _ nested_control_store_valid
  all_goals intro first _ second _ same; exact shift_references_is_injective same

theorem relocated_sealed_child_still_rejects :
    UseScope.acquire (childView.relocate shiftReferences)
      (nestedControlStore.relocate shiftReferences (Target.Resumption.relocate shiftReferences)) = none := by
  rw [UseScope.acquire_relocate _ _ _ _ (shift_lookup_faithful _ _), sealed_child_cannot_resume]
  rfl

theorem relocated_parent_opens_the_same_child_scope :
    UseScope.acquire (parentView.relocate shiftReferences)
      (nestedControlStore.relocate shiftReferences (Target.Resumption.relocate shiftReferences)) =
      some ⟨activatedParentStore.relocate shiftReferences (Target.Resumption.relocate shiftReferences),
        parentFuture.relocate shiftReferences⟩ := by
  rw [UseScope.acquire_relocate _ _ _ _ (shift_lookup_faithful _ _), parent_acquisition_exposes_child_without_losing_its_future]
  rfl

theorem relocated_child_owner_still_rejects_a_stale_view :
    UseScope.acquire (({ childView with owner := .lexical ⟨0⟩ 1 }).relocate shiftReferences)
      (activatedParentStore.relocate shiftReferences (Target.Resumption.relocate shiftReferences)) = none := by
  rw [UseScope.acquire_relocate _ _ _ _ (shift_lookup_faithful _ _), old_child_owner_is_stale]
  rfl

theorem relocated_disposal_keeps_nested_cleanup_work :
    UseScope.release .explicit (parentView.relocate shiftReferences)
      (nestedControlStore.relocate shiftReferences (Target.Resumption.relocate shiftReferences)) =
      some (UseScope.ControlStore.relocate shiftReferences (Target.Resumption.relocate shiftReferences)
        (⟨⟨[], nestedControlStore.fields.retained, [parentView.authority]⟩, [childInfo], [parentInfo]⟩ : UseScope.ControlStore SavedChoice)) := by
  rw [UseScope.release_relocate _ _ _ _ _ (shift_lookup_faithful _ _), disposal_preserves_nested_child_and_cleanup_work]
  rfl

theorem relocated_typed_lookup_preserves_rejection :
    UseScope.acquireAt textShape (successorView.relocate shiftReferences)
      (Target.relocateControlHeap shiftReferences mixedTargetControls) = none := by
  rw [Target.typed_acquisition_relocation (signature := signature) (algebra := algebra)
    shiftReferences textShape successorView mixedTargetControls (shift_lookup_faithful _ _), matching_identity_with_wrong_type_rejects]
  rfl

def lookupSupport : ∀ domain, List (Id domain)
  | .control => [⟨10⟩, ⟨11⟩]
  | .custody => [⟨100⟩, ⟨101⟩]
  | _ => []

def lookupLocals : ∀ domain, List (Id domain)
  | .control => [⟨10⟩]
  | .custody => [⟨100⟩]
  | _ => []

def moveOneControl : UseScope.Relocation :=
  UseScope.freshRelocation lookupSupport lookupLocals (fun owner => owner)

/-- This allocator is injective on the current finite support, even though a
fresh image can coincide with an unused name outside that support. -/
theorem local_lookup_map_is_not_globally_injective :
    moveOneControl.name .control ⟨10⟩ = moveOneControl.name .control ⟨22⟩ ∧
      (⟨10⟩ : Id .control) ≠ ⟨22⟩ := ⟨rfl, by decide⟩

theorem local_lookup_map_is_faithful : UseScope.LookupRelocation moveOneControl successorView mixedTargetControls := by
  constructor
  · simp [mixedTargetControls, successorView, moveOneControl, UseScope.freshRelocation,
      lookupSupport, lookupLocals, FreshNames.rename, FreshNames.bound]
  · simp [mixedTargetControls, successorView, moveOneControl, UseScope.freshRelocation,
      lookupSupport, lookupLocals, FreshNames.rename, FreshNames.bound]
  · intro token holder member same
    simp only [mixedTargetControls, mixedControlFields, UseScope.activeFields, UseScope.exposeField,
      List.singleton_append, List.append_nil, List.mem_cons, List.not_mem_nil, or_false, UseScope.Field.owned.injEq] at member
    rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    · exact ⟨rfl, rfl⟩
    · simp [moveOneControl, UseScope.freshRelocation, lookupSupport, lookupLocals, FreshNames.rename,
        FreshNames.bound, successorView] at same
  · intro identity saved member same
    simp only [mixedTargetControls, mixedControlFields, List.mem_cons, List.not_mem_nil, or_false,
      UseScope.Field.continuation.injEq] at member
    rcases member with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    · rfl
    · simp [moveOneControl, UseScope.freshRelocation, lookupSupport, lookupLocals, FreshNames.rename,
        FreshNames.bound, successorView] at same

theorem finite_local_lookup_commutes :
    UseScope.acquireAt choiceShape (successorView.relocate moveOneControl)
        (Target.relocateControlHeap moveOneControl mixedTargetControls) =
      (UseScope.acquireAt choiceShape successorView mixedTargetControls).map (Target.relocateTypedAcquisition moveOneControl) :=
  Target.typed_acquisition_relocation moveOneControl choiceShape successorView mixedTargetControls local_lookup_map_is_faithful

def collapseOwners : UseScope.Relocation := ⟨fun _ identity => identity, fun _ => .lexical ⟨0⟩ 0⟩
def staleParentOwner : UseScope.ControlView := { parentView with owner := .lexical ⟨0⟩ 1 }

/-- Injective control and custody names alone are insufficient: merging owner
labels admits a view that previously had no authority. The grants premise blocks it. -/
theorem collapsing_owners_can_admit_a_stale_view :
    UseScope.acquire staleParentOwner nestedControlStore = none ∧
      ∃ result, UseScope.acquire (staleParentOwner.relocate collapseOwners)
        (nestedControlStore.relocate collapseOwners (Target.Resumption.relocate collapseOwners)) = some result := by
  exact ⟨rfl, ⟨_, rfl⟩⟩

end BoundaryV2.Generalized.Examples
