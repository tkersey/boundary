import BoundaryV2.GeneralizedLifetimeExit
import BoundaryV2.GeneralizedRegionRetirement

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {Body Before After : List (TypeOf signature) → TypeOf signature → Type}

namespace Cells

def outsideRegions (retiring : List (Id .region)) (cells : Cells signature algebra Body) : Cells signature algebra Body :=
  cells.filter fun cell => !(retiring.contains cell.region)

def inRegions (retiring : List (Id .region)) (cells : Cells signature algebra Body) : Cells signature algebra Body :=
  cells.filter fun cell => retiring.contains cell.region

/-- Storage can disappear only after its actual physical owning fields have
been handed off. Empty custody metadata elsewhere is not a substitute. -/
def regionsUnowned (retiring : List (Id .region)) (cells : Cells signature algebra Body) : Bool :=
  (cells.inRegions retiring).all fun cell => cell.value.owningField.tokens.isEmpty

theorem outside_regions_excludes_retired_storage
    (member : cell ∈ outsideRegions retiring cells) : cell.region ∉ retiring := by
  simpa using (List.mem_filter.mp member).2

theorem outside_regions_preserves_owning_occurrences
    (cells : Cells signature algebra Body) (unowned : regionsUnowned retiring cells = true) :
    UseScope.tokens (outsideRegions retiring cells).fields = UseScope.tokens cells.fields := by
  induction cells with
  | nil => rfl
  | cons first rest induction =>
    by_cases selected : first.region ∈ retiring
    · have facts : first.value.owningField.tokens = [] ∧ regionsUnowned retiring rest = true := by
        simpa [regionsUnowned, inRegions, selected] using unowned
      simpa [outsideRegions, selected, fields, UseScope.tokens, facts.1] using induction facts.2
    · have tail : regionsUnowned retiring rest = true := by
        simpa [regionsUnowned, inRegions, selected] using unowned
      simpa [outsideRegions, selected, fields, UseScope.tokens] using
        congrArg (first.value.owningField.tokens ++ ·) (induction tail)

theorem outside_regions_preserves_other_lookup (cells : Cells signature algebra Body)
    (absent : identity ∉ (cells.inRegions retiring).identities) :
    lookup identity (outsideRegions retiring cells) = lookup identity cells := by
  induction cells with
  | nil => rfl
  | cons first rest induction =>
    by_cases selected : first.region ∈ retiring
    · have facts : first.identity ≠ identity ∧ identity ∉ (inRegions retiring rest).identities := by
        simpa [inRegions, selected, identities, eq_comm] using absent
      simpa [outsideRegions, selected, lookup, facts.1] using induction facts.2
    · have tail : identity ∉ (inRegions retiring rest).identities := by
        simpa [inRegions, selected, identities] using absent
      simp only [outsideRegions, List.filter_cons]
      simp only [List.contains_eq_mem, selected, decide_false, Bool.not_false, if_true]
      simp only [lookup]
      have same := induction tail
      simp only [outsideRegions, List.contains_eq_mem] at same
      rw [same]

theorem outside_regions_commutes_with_body_mapping
    (transform : ∀ context type, Before context type → After context type)
    (retiring : List (Id .region)) (cells : Cells signature algebra Before) :
    outsideRegions retiring (cells.mapBodies transform) = (outsideRegions retiring cells).mapBodies transform := by
  simp [outsideRegions, mapBodies, List.filter_map, Function.comp_def, Cell.map]
  rfl

theorem in_regions_commutes_with_body_mapping
    (transform : ∀ context type, Before context type → After context type)
    (retiring : List (Id .region)) (cells : Cells signature algebra Before) :
    inRegions retiring (cells.mapBodies transform) = (inRegions retiring cells).mapBodies transform := by
  simp [inRegions, mapBodies, List.filter_map, Function.comp_def, Cell.map]
  rfl

theorem regions_unowned_commutes_with_body_mapping
    (transform : ∀ context type, Before context type → After context type)
    (retiring : List (Id .region)) (cells : Cells signature algebra Before) :
    regionsUnowned retiring (cells.mapBodies transform) = regionsUnowned retiring cells := by
  rw [regionsUnowned, in_regions_commutes_with_body_mapping]
  simp only [mapBodies, List.all_map, Cell.map, Value.map_preserves_owning_fields, Function.comp_def]
  rfl

end Cells

/-- Check region and cell names separately: a stale cell alias cannot survive
merely by carrying a different region annotation. All other domains are left
to their existing lifetime and permission owners. -/
def excludesRetiredStorage (regions : List (Id .region)) (cells : List (Id .cell)) (support : List Reference) : Bool :=
  (referenceNames support .region).all (fun identity => !regions.contains identity) &&
    (referenceNames support .cell).all (fun identity => !cells.contains identity)

theorem excluded_storage_has_no_surviving_alias
    (accepted : excludesRetiredStorage regions cells support = true) :
    (∀ identity ∈ referenceNames support .region, identity ∉ regions) ∧
      (∀ identity ∈ referenceNames support .cell, identity ∉ cells) := by
  simpa [excludesRetiredStorage, List.all_eq_true] using accepted

def canRetireStorage (retiring live : List (Id .region)) (cells : Cells signature algebra Body)
    (surviving : List Reference) : Bool :=
  retiring.all (fun region => live.contains region) && cells.regionsUnowned retiring &&
    excludesRetiredStorage retiring (cells.inRegions retiring).identities surviving

theorem storage_retirement_check_commutes_with_body_mapping
    (transform : ∀ context type, Before context type → After context type)
    (retiring live : List (Id .region)) (cells : Cells signature algebra Before) (surviving : List Reference) :
    canRetireStorage retiring live (cells.mapBodies transform) surviving = canRetireStorage retiring live cells surviving := by
  simp only [canRetireStorage, Cells.regions_unowned_commutes_with_body_mapping,
    Cells.in_regions_commutes_with_body_mapping, Cells.mapBodies_identities]

variable {program : List (BodyType signature.Data signature.Effect)}

/-- The higher-order return boundary performs its own support collection and
storage transition. The native caller remains executable after retirement. -/
def Source.retireReturnedRegions (retiring live : List (Id .region))
    (store : ControlHeap signature algebra program)
    (cells : Cells signature algebra (Computation signature algebra program))
    (returned : RuntimeValue signature algebra program input)
    (outside : Context signature algebra program input result) (external : List Reference) : Option (State signature algebra program result) :=
  let remaining := cells.outsideRegions retiring
  let support := storeReferences store ++ cellsReferences remaining ++ valueReferences returned ++ outside.referenceSupport ++ external
  if canRetireStorage retiring live cells support then
    some ⟨⟨store, outside.plug (.returned returned)⟩, remaining, live.filter fun region => !retiring.contains region⟩
  else none

namespace ExitComposition

variable {program : List (BodyType signature.Data signature.Effect)}

def Resolution.cells : Resolution signature algebra program result →
    Cells signature algebra (fun context result => Target.Code signature algebra program context [] result)
  | .reenter state _ => state.cells
  | .unwind runtime _ => runtime.cells

def Resolution.regions : Resolution signature algebra program result → List (Id .region)
  | .reenter state _ => state.liveRegions
  | .unwind runtime _ => runtime.liveRegions

def Resolution.store : Resolution signature algebra program result → Target.ControlHeap signature algebra program
  | .reenter state _ => state.control.store
  | .unwind runtime _ => runtime.store

def Resolution.exitInfo : Resolution signature algebra program result → ExitInfo algebra.Fault algebra.Reason
  | .reenter _ exit => exit
  | .unwind runtime _ => runtime.exit

/-- This changes only storage and its liveness; saved return/failure/unwind
control, custody, cancellation, and ordered failure history stay intact. -/
def Resolution.withStorage (resolution : Resolution signature algebra program result)
    (cells : Cells signature algebra (fun context result => Target.Code signature algebra program context [] result))
    (regions : List (Id .region)) : Resolution signature algebra program result :=
  match resolution with
  | .reenter state exit => .reenter { state with cells := cells, liveRegions := regions } exit
  | .unwind runtime outside => .unwind { runtime with cells := cells, liveRegions := regions } outside

def Resolution.withoutRegions (resolution : Resolution signature algebra program result)
    (retiring : List (Id .region)) : Resolution signature algebra program result :=
  resolution.withStorage (resolution.cells.outsideRegions retiring)
    (resolution.regions.filter fun region => !retiring.contains region)

/-- The argument is a completed exit resolution. Check the actual surviving
control, retained/disposal futures, remaining cells, and declared external
roots before publishing the storage/liveness change together. -/
def Resolution.retireRegions (resolution : Resolution signature algebra program result)
    (retiring : List (Id .region)) (external : List Reference) : Option (Resolution signature algebra program result) :=
  let after := resolution.withoutRegions retiring
  if resolution.cleanupFinished && canRetireStorage retiring resolution.regions resolution.cells (after.referenceSupport ++ external)
    then some after else none

/-- Normal lexical return keeps its actual value and outside context. Only
storage whose ownership has already been discharged may retire here. -/
def finishReturnedRegion (external : List Reference) :
    Resolution signature algebra program result → Option (Resolution signature algebra program result)
  | .reenter state diagnostics => match state.control.configuration with
    | .returned value (.push (.region identity) outside) =>
        (Resolution.reenter ⟨⟨state.control.store, .returned value outside⟩, state.cells, state.liveRegions⟩ diagnostics).retireRegions [identity] external
    | _ => none
  | _ => none

def finishRegions (retiring : List (Id .region)) (scope : ScopeExit signature algebra program result)
    (external : List Reference) : Option (Resolution signature algebra program result) :=
  (finish scope).bind fun resolution => resolution.retireRegions retiring external

variable {result : TypeOf signature} {resolution after : Resolution signature algebra program result}

theorem region_retirement_is_checked_storage_removal
    (accepted : resolution.retireRegions retiring external = some after) :
    after = resolution.withoutRegions retiring ∧
      resolution.cells.regionsUnowned retiring = true ∧
      excludesRetiredStorage retiring (resolution.cells.inRegions retiring).identities (after.referenceSupport ++ external) = true := by
  unfold Resolution.retireRegions canRetireStorage at accepted
  dsimp only at accepted
  split at accepted
  · rename_i permitted
    cases accepted
    have permitted := (Bool.and_eq_true_iff.mp permitted).2
    exact ⟨rfl, (Bool.and_eq_true_iff.mp (Bool.and_eq_true_iff.mp permitted).1).2, (Bool.and_eq_true_iff.mp permitted).2⟩
  · cases accepted

theorem region_retirement_preserves_owners_and_exit
    (accepted : resolution.retireRegions retiring external = some after) :
    after.store = resolution.store ∧ after.exitInfo = resolution.exitInfo ∧
      UseScope.tokens after.cells.fields = UseScope.tokens resolution.cells.fields := by
  obtain ⟨rfl, unowned, _⟩ := region_retirement_is_checked_storage_removal accepted
  have owners := Cells.outside_regions_preserves_owning_occurrences resolution.cells unowned
  cases resolution <;> exact ⟨rfl, rfl, owners⟩

theorem region_retirement_preserves_surviving_storage_dependencies
    (accepted : resolution.retireRegions retiring external = some after) :
    (∀ region ∈ referenceNames (after.referenceSupport ++ external) .region, region ∉ retiring) ∧
      (∀ cell ∈ referenceNames (after.referenceSupport ++ external) .cell,
        cell ∉ (resolution.cells.inRegions retiring).identities) :=
  excluded_storage_has_no_surviving_alias (region_retirement_is_checked_storage_removal accepted).2.2

theorem region_retirement_removes_liveness_and_storage
    (accepted : resolution.retireRegions retiring external = some after) :
    (∀ region ∈ after.regions, region ∉ retiring) ∧
      (∀ cell ∈ after.cells, cell.region ∉ retiring) := by
  obtain ⟨rfl, _, _⟩ := region_retirement_is_checked_storage_removal accepted
  cases resolution <;> constructor
  all_goals intro item member
  all_goals simpa using (List.mem_filter.mp member).2

theorem region_retirement_preserves_unrelated_reads [DecidableEq (TypeOf signature)]
    (accepted : resolution.retireRegions retiring external = some after)
    (absent : identity ∉ (resolution.cells.inRegions retiring).identities) :
    Cells.readCopy identity region type after.cells = Cells.readCopy identity region type resolution.cells := by
  obtain ⟨rfl, _, _⟩ := region_retirement_is_checked_storage_removal accepted
  have lookup := Cells.outside_regions_preserves_other_lookup resolution.cells absent
  have projected : (resolution.withoutRegions retiring).cells = resolution.cells.outsideRegions retiring := by
    cases resolution <;> rfl
  rw [projected]
  simp only [Cells.readCopy, Cells.read, lookup]

theorem pending_cleanup_cannot_retire_regions
    (scope : ScopeExit signature algebra program result) (pending : scope.cleanup.phase = .pending cleanup) :
    finishRegions retiring scope external = none := by
  simp only [finishRegions, pending_cleanup_cannot_reenter scope pending, Option.bind_none]

theorem running_cleanup_cannot_retire_regions
    (scope : ScopeExit signature algebra program result) (running : scope.cleanup.phase = .running cursor location) :
    finishRegions retiring scope external = none := by
  simp only [finishRegions, unfinished_cleanup_cannot_reenter scope running, Option.bind_none]

theorem finished_regions_follow_completed_cleanup
    (accepted : finishRegions retiring scope external = some after) :
    ∃ resolution, finish scope = some resolution ∧ resolution.retireRegions retiring external = some after :=
  Option.bind_eq_some_iff.mp accepted

theorem unfinished_unwind_resolution_cannot_retire_regions
    (runtime : Runtime signature algebra program)
    (outside : Target.Stack signature algebra program input result)
    (unfinished : runtime.phase = .pending cleanup ∨ runtime.phase = .running cursor location) :
    (Resolution.unwind runtime outside).retireRegions retiring external = none := by
  rcases unfinished with pending | running
  all_goals simp only [Resolution.retireRegions, Resolution.cleanupFinished, *, Bool.false_and, Bool.false_eq_true, if_false]

end ExitComposition

namespace Defunctionalization

theorem returned_region_retirement_corresponds
    (retiring live : List (Id .region))
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program))
    (returned : Source.RuntimeValue signature algebra program input)
    {sourceOutside : Source.Context signature algebra program input result}
    {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (exit : ExitInfo algebra.Fault algebra.Reason) (external : List Reference) :
    (ExitComposition.Resolution.reenter
      ⟨⟨targetStore, .returned (value returned) targetOutside⟩, cells sourceCells, live⟩ exit).retireRegions retiring external =
      (Source.retireReturnedRegions retiring live sourceStore sourceCells returned sourceOutside external).map fun next =>
        ExitComposition.Resolution.reenter
          ⟨⟨targetStore, .returned (value returned) targetOutside⟩, cells next.cells, next.liveRegions⟩ exit := by
  have remaining := Cells.outside_regions_commutes_with_body_mapping
    (fun _ _ body => computation body) retiring sourceCells
  change Cells.outsideRegions retiring (cells sourceCells) = cells (Cells.outsideRegions retiring sourceCells) at remaining
  simp only [ExitComposition.Resolution.retireRegions, ExitComposition.Resolution.withoutRegions,
    ExitComposition.Resolution.cleanupFinished, Bool.true_and,
    ExitComposition.Resolution.withStorage, ExitComposition.Resolution.cells, ExitComposition.Resolution.regions,
    ExitComposition.Resolution.referenceSupport, Target.Configuration.referenceSupport, remaining,
    store_reference_support stores, cell_installation_support, value_reference_support,
    context_reference_support outside, List.append_assoc]
  rw [show canRetireStorage retiring live (cells sourceCells) _ = canRetireStorage retiring live sourceCells _ from
    storage_retirement_check_commutes_with_body_mapping (fun _ _ body => computation body) retiring live sourceCells _]
  unfold Source.retireReturnedRegions
  dsimp only
  simp only [List.append_assoc]
  split <;> rfl

theorem returned_region_retirement_preserves_the_state_relation
    (retiring live : List (Id .region))
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program))
    (returned : Source.RuntimeValue signature algebra program input)
    {sourceOutside : Source.Context signature algebra program input result}
    {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (exit : ExitInfo algebra.Fault algebra.Reason) (external : List Reference)
    (accepted : Source.retireReturnedRegions retiring live sourceStore sourceCells returned sourceOutside external = some next) :
    ∃ after, (ExitComposition.Resolution.reenter
        ⟨⟨targetStore, .returned (value returned) targetOutside⟩, cells sourceCells, live⟩ exit).retireRegions retiring external =
        some (.reenter after exit) ∧ CellStateRelated next after := by
  have agrees := returned_region_retirement_corresponds retiring live stores sourceCells returned outside exit external
  rw [accepted] at agrees
  refine ⟨_, agrees, ?_⟩
  unfold Source.retireReturnedRegions at accepted
  dsimp only at accepted
  split at accepted
  · cases accepted
    exact ⟨⟨stores, .returned returned outside⟩, rfl, rfl⟩
  · cases accepted

end Defunctionalization
end BoundaryV2.Generalized
