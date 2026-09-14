import BoundaryV2.GeneralizedRegionClosure

namespace BoundaryV2.Generalized

/-- A region follows its nominal owning scope when that scope moves. The
association does not depend on the scope's current parent or creation site. -/
structure RegionBinding where
  region : Id .region
  owner : Id .scope
  deriving DecidableEq

abbrev RegionBindings := List RegionBinding

namespace RegionBindings

def regions (bindings : RegionBindings) : List (Id .region) := bindings.map RegionBinding.region

def valid (forest : Scope.Forest) (bindings : RegionBindings) : Bool :=
  decide (Scope.names forest).Nodup && decide bindings.regions.Nodup &&
    bindings.all (fun binding => Scope.names forest |>.contains binding.owner)

theorem validity (accepted : valid forest bindings = true) :
    Scope.Valid forest ∧ bindings.regions.Nodup ∧ ∀ binding ∈ bindings, binding.owner ∈ Scope.names forest := by
  simpa [valid, Scope.Valid, List.all_eq_true, and_assoc] using accepted

theorem valid_of_scopes (scopes : Scope.Valid forest) (unique : bindings.regions.Nodup)
    (live : ∀ binding ∈ bindings, binding.owner ∈ Scope.names forest) : valid forest bindings = true := by
  simpa [valid, Scope.Valid, List.all_eq_true, and_assoc] using And.intro scopes (And.intro unique live)

/-- Register the region chosen by ordinary fresh region entry. Existing
bindings cannot be replaced, and an unknown scope cannot acquire a region. -/
def bind (region : Id .region) (owner : Id .scope) (forest : Scope.Forest)
    (bindings : RegionBindings) : Option RegionBindings :=
  if region ∉ bindings.regions ∧ owner ∈ Scope.names forest then some (⟨region, owner⟩ :: bindings) else none

theorem binding_preserves_validity (before : valid forest bindings = true)
    (accepted : bind region owner forest bindings = some after) : valid forest after = true := by
  obtain ⟨scopes, unique, live⟩ := validity before
  unfold bind at accepted
  split at accepted
  · rename_i permitted
    cases accepted
    apply valid_of_scopes (bindings := ⟨region, owner⟩ :: bindings) scopes (List.nodup_cons.mpr ⟨permitted.1, unique⟩)
    intro binding member
    rcases List.mem_cons.mp member with rfl | old
    · exact permitted.2
    · exact live binding old
  · cases accepted

theorem fresh_region_can_bind (fresh : region ∉ bindings.regions) (live : owner ∈ Scope.names forest) :
    bind region owner forest bindings = some (⟨region, owner⟩ :: bindings) := if_pos ⟨fresh, live⟩

theorem moving_scopes_preserves_region_associations (before : valid forest bindings = true)
    (moved : Scope.move wanted destination forest = some after) : valid after bindings = true := by
  obtain ⟨scopes, unique, live⟩ := validity before
  apply valid_of_scopes (Scope.move_preserves_validity scopes moved) unique
  exact fun binding member => (Scope.move_preserves_names moved).mem_iff.mp (live binding member)

theorem retaining_scopes_preserves_region_associations (before : valid forest bindings = true)
    (retained : Scope.retain wanted destination borrowed forest = some after) : valid after.forest bindings = true := by
  obtain ⟨scopes, unique, live⟩ := validity before
  apply valid_of_scopes (Scope.retain_preserves_validity scopes retained) unique
  exact fun binding member => (Scope.retain_preserves_old_scopes retained).mem_iff.mp (List.mem_cons_of_mem _ (live binding member))

def within (scopes : List (Id .scope)) (bindings : RegionBindings) : RegionBindings :=
  bindings.filter fun binding => scopes.contains binding.owner

def outside (scopes : List (Id .scope)) (bindings : RegionBindings) : RegionBindings :=
  bindings.filter fun binding => !scopes.contains binding.owner

theorem equal_region_has_one_owner (bindings : RegionBindings) (unique : bindings.regions.Nodup)
    (firstIn : first ∈ bindings) (secondIn : second ∈ bindings) (same : first.region = second.region) : first = second := by
  induction bindings with
  | nil => cases firstIn
  | cons head rest induction =>
    obtain ⟨absent, tail⟩ := List.nodup_cons.mp unique
    rcases List.mem_cons.mp firstIn with rfl | firstRest
    · rcases List.mem_cons.mp secondIn with rfl | secondRest
      · rfl
      · exact False.elim (absent (List.mem_map.mpr ⟨second, secondRest, same.symm⟩))
    · rcases List.mem_cons.mp secondIn with rfl | secondRest
      · exact False.elim (absent (List.mem_map.mpr ⟨first, firstRest, same⟩))
      · exact induction tail firstRest secondRest

theorem region_selected_iff_owner_selected (unique : bindings.regions.Nodup) (member : binding ∈ bindings) :
    binding.region ∈ (within scopes bindings).regions ↔ binding.owner ∈ scopes := by
  constructor
  · intro selected
    obtain ⟨other, selected, same⟩ := List.mem_map.mp selected
    obtain ⟨otherIn, chosen⟩ := List.mem_filter.mp selected
    have equal := equal_region_has_one_owner bindings unique otherIn member same
    subst other
    simpa using chosen
  · intro selected
    exact List.mem_map.mpr ⟨binding, List.mem_filter.mpr ⟨member, by simpa using selected⟩, rfl⟩

theorem remaining_regions_are_exactly_the_unretired_names (unique : bindings.regions.Nodup) :
    (outside scopes bindings).regions = bindings.regions.filter (fun region => !(within scopes bindings).regions.contains region) := by
  simp only [outside, regions, List.filter_map]
  congr 1
  apply List.filter_congr
  intro binding member
  simp only [Function.comp_def, List.contains_eq_mem]
  have same : binding.region ∈ List.map RegionBinding.region (within scopes bindings) ↔ binding.owner ∈ scopes :=
    region_selected_iff_owner_selected unique member
  simp only [same]

theorem remaining_bindings_are_valid (before : valid forest bindings = true)
    (closed : Scope.close wanted forest = some (retired, remaining)) :
    valid remaining (outside retired.names bindings) = true := by
  obtain ⟨scopes, unique, live⟩ := validity before
  have forestUnique := (Scope.detach_names forest closed).nodup_iff.mp scopes
  have remainingUnique := (List.nodup_append.mp forestUnique).2.1
  have bindingUnique : (outside retired.names bindings).regions.Nodup :=
    unique.sublist (List.filter_sublist.map RegionBinding.region)
  apply valid_of_scopes remainingUnique bindingUnique
  intro binding member
  obtain ⟨old, kept⟩ := List.mem_filter.mp member
  have anywhere := (Scope.detach_names forest closed).mem_iff.mp (live binding old)
  have notRetired : binding.owner ∉ retired.names := by simpa using kept
  exact (List.mem_append.mp anywhere).resolve_left notRetired

end RegionBindings

namespace ExitComposition

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

structure ScopedRegionExit (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  resolution : Resolution signature algebra program result
  retired : Scope.Tree
  forest : Scope.Forest
  bindings : RegionBindings

/-- Resolve cleanup, detach the actual scope subtree, and derive its region
set from the complete live bindings. Publish no part of the change if a cell
owner, saved future, or surviving scope borrow prevents retirement. -/
def finishScopedRegions (wanted : Id .scope) (forest : Scope.Forest) (bindings : RegionBindings)
    (scope : ScopeExit signature algebra program result) (external : List Reference) :
    Option (ScopedRegionExit signature algebra program result) :=
  (finish scope).bind fun resolution =>
    if bindings.valid forest && decide (resolution.regions.Perm bindings.regions) then
      (Scope.close wanted forest).bind fun (retired, remaining) =>
        (resolution.retireRegions (bindings.within retired.names).regions external).bind fun after =>
          if (referenceNames (after.referenceSupport ++ external) .scope).all (fun name => (Scope.names remaining).contains name) then
            some ⟨after, retired, remaining, bindings.outside retired.names⟩
          else none
    else none

variable {result : TypeOf signature} {after : ScopedRegionExit signature algebra program result}

theorem scoped_region_exit_uses_actual_bindings
    (accepted : finishScopedRegions wanted forest bindings scope external = some after) :
    ∃ before, finish scope = some before ∧ bindings.valid forest = true ∧ before.regions.Perm bindings.regions ∧
      Scope.close wanted forest = some (after.retired, after.forest) ∧
      before.retireRegions (bindings.within after.retired.names).regions external = some after.resolution ∧
      after.bindings = bindings.outside after.retired.names ∧
      ∀ dependency ∈ referenceNames (after.resolution.referenceSupport ++ external) .scope,
        dependency ∈ Scope.names after.forest := by
  obtain ⟨before, completed, accepted⟩ := Option.bind_eq_some_iff.mp accepted
  split at accepted
  · rename_i consistent
    have consistent : bindings.valid forest = true ∧ before.regions.Perm bindings.regions := by simpa using consistent
    obtain ⟨⟨retired, remaining⟩, detached, accepted⟩ := Option.bind_eq_some_iff.mp accepted
    obtain ⟨resolution, closed, accepted⟩ := Option.bind_eq_some_iff.mp accepted
    split at accepted
    · rename_i supported
      cases accepted
      exact ⟨before, completed, consistent.1, consistent.2, detached, closed, rfl,
        by simpa [List.all_eq_true] using supported⟩
    · cases accepted
  · cases accepted

theorem scoped_region_exit_keeps_bindings_and_runtime_in_agreement
    (accepted : finishScopedRegions wanted forest bindings scope external = some after) :
    after.bindings.valid after.forest = true ∧ after.resolution.regions.Perm after.bindings.regions := by
  obtain ⟨before, _, valid, agreement, detached, closed, bindingEq, _⟩ := scoped_region_exit_uses_actual_bindings accepted
  rw [bindingEq]
  refine ⟨RegionBindings.remaining_bindings_are_valid valid detached, ?_⟩
  have exactStorage := (region_retirement_is_checked_storage_removal closed).1
  have regions : after.resolution.regions = before.regions.filter
      (fun region => !(bindings.within after.retired.names).regions.contains region) := by
    rw [exactStorage]
    cases before <;> rfl
  rw [regions, RegionBindings.remaining_regions_are_exactly_the_unretired_names (RegionBindings.validity valid).2.1]
  exact agreement.filter _

theorem closed_scope_regions_cannot_survive
    (accepted : finishScopedRegions wanted forest bindings scope external = some after)
    (member : binding ∈ bindings) (owned : binding.owner ∈ after.retired.names) :
    binding.region ∉ after.resolution.regions := by
  obtain ⟨_, _, valid, _, _, closed, _, _⟩ := scoped_region_exit_uses_actual_bindings accepted
  have selected := (RegionBindings.region_selected_iff_owner_selected (RegionBindings.validity valid).2.1 member).2 owned
  intro surviving
  exact (region_retirement_removes_liveness_and_storage closed).1 binding.region surviving selected

theorem retained_scope_regions_stay_live
    (accepted : finishScopedRegions wanted forest bindings scope external = some after)
    (member : binding ∈ bindings) (survives : binding.owner ∉ after.retired.names) :
    binding ∈ after.bindings ∧ binding.region ∈ after.resolution.regions := by
  obtain ⟨_, _, _, _, _, _, bindingEq, _⟩ := scoped_region_exit_uses_actual_bindings accepted
  have kept : binding ∈ after.bindings := by rw [bindingEq]; exact List.mem_filter.mpr ⟨member, by simpa using survives⟩
  refine ⟨kept, ?_⟩
  apply (scoped_region_exit_keeps_bindings_and_runtime_in_agreement accepted).2.mem_iff.mpr
  exact List.mem_map.mpr ⟨binding, kept, rfl⟩

theorem scoped_region_exit_preserves_surviving_scope_borrows
    (accepted : finishScopedRegions wanted forest bindings scope external = some after) :
    ∀ dependency ∈ referenceNames (after.resolution.referenceSupport ++ external) .scope,
      dependency ∉ after.retired.names := by
  obtain ⟨_, _, valid, _, detached, _, _, supported⟩ := scoped_region_exit_uses_actual_bindings accepted
  intro dependency member retired
  exact Scope.closed_scopes_are_removed (RegionBindings.validity valid).1 detached dependency retired (supported dependency member)

theorem pending_cleanup_cannot_close_scoped_regions
    (scope : ScopeExit signature algebra program result) (pending : scope.cleanup.phase = .pending cleanup) :
    finishScopedRegions wanted forest bindings scope external = none := by
  simp only [finishScopedRegions, pending_cleanup_cannot_reenter scope pending, Option.bind_none]

theorem running_cleanup_cannot_close_scoped_regions
    (scope : ScopeExit signature algebra program result) (running : scope.cleanup.phase = .running cursor location) :
    finishScopedRegions wanted forest bindings scope external = none := by
  simp only [finishScopedRegions, unfinished_cleanup_cannot_reenter scope running, Option.bind_none]

end ExitComposition
end BoundaryV2.Generalized
