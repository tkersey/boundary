import BoundaryV2.GeneralizedUnwinding

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {Body Before After : List (TypeOf signature) → TypeOf signature → Type}

namespace Cells

/-- Pending cells retain their typed current values and physical owners until
handed to disposal. The remaining table retains its lookup order. -/
structure RegionHandoff (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (Body : List (TypeOf signature) → TypeOf signature → Type) where
  pending : Cells signature algebra Body
  remaining : Cells signature algebra Body

/-- Allocation prepends records. Reversing only the selected records puts older
cells first without sorting nominal identities. This transfers storage; it does
not dispose values or close a lifetime. -/
def handoffRegion (region : Id .region) (cells : Cells signature algebra Body) : RegionHandoff signature algebra Body :=
  ⟨(cells.filter (fun cell => cell.region == region)).reverse, cells.filter (fun cell => !(cell.region == region))⟩

theorem handoff_partitions_actual_cells (region : Id .region) (cells : Cells signature algebra Body) :
    cells.Perm ((handoffRegion region cells).pending ++ (handoffRegion region cells).remaining) :=
  (List.filter_append_perm (fun cell => cell.region == region) cells).symm.trans
    ((List.reverse_perm _).symm.append_right _)

private theorem tokens_flatMap (fields : List UseScope.Field) :
    fields.flatMap UseScope.Field.tokens = UseScope.tokens fields := by
  induction fields with
  | nil => rfl
  | cons first rest induction => simp only [List.flatMap_cons, UseScope.tokens, induction]

theorem handoff_preserves_owning_occurrences (region : Id .region) (cells : Cells signature algebra Body) :
    (UseScope.tokens cells.fields).Perm
      (UseScope.tokens (handoffRegion region cells).pending.fields ++
        UseScope.tokens (handoffRegion region cells).remaining.fields) := by
  have moved := (handoff_partitions_actual_cells region cells).map (fun cell => cell.value.owningField)
  have owners := moved.flatMap_right UseScope.Field.tokens
  simpa only [List.map_append, List.flatMap_append, tokens_flatMap, fields] using owners

theorem handoff_appends_each_new_allocation (region : Id .region) (value : Value signature algebra Body type)
    (cells : Cells signature algebra Body) (reserved : List (Id .cell)) :
    (handoffRegion region (allocate region value cells reserved).cells).pending =
      (handoffRegion region cells).pending ++ [⟨(allocate region value cells reserved).identity, region, type, value⟩] := by
  simp [handoffRegion, allocate, List.reverse_cons]

theorem handoff_leaves_no_selected_cells (region : Id .region) (cells : Cells signature algebra Body)
    (member : cell ∈ (handoffRegion region cells).remaining) : cell.region ≠ region := by
  have keep := (List.mem_filter.mp member).2
  simpa using keep

theorem handoff_selects_only_its_region (region : Id .region) (cells : Cells signature algebra Body)
    (member : cell ∈ (handoffRegion region cells).pending) : cell.region = region := by
  have selected := (List.mem_filter.mp (List.mem_reverse.mp member)).2
  simpa using selected

theorem handoff_commutes_with_body_mapping
    (transform : ∀ context type, Before context type → After context type)
    (region : Id .region) (cells : Cells signature algebra Before) :
    handoffRegion region (cells.mapBodies transform) =
      ⟨(handoffRegion region cells).pending.mapBodies transform,
        (handoffRegion region cells).remaining.mapBodies transform⟩ := by
  simp [handoffRegion, mapBodies, List.filter_map, Function.comp_def, Cell.map, List.map_reverse]

/-- Take one oldest cell from the current table. Untaken cells remain available
while disposal runs; no queue of stale copied values is consulted. -/
def takeOldest (region : Id .region) (cells : Cells signature algebra Body) (kept : List (Id .cell) := []) :
    Option (Cell signature algebra Body × Cells signature algebra Body) :=
  match cells with
  | [] => none
  | first :: rest => match takeOldest region rest kept with
    | some (selected, remaining) => some (selected, first :: remaining)
    | none => if first.region == region && !(kept.contains first.identity && first.value.owningField.tokens.isEmpty) then some (first, rest) else none

theorem take_oldest_preserves_cells (cells : Cells signature algebra Body)
    (taken : takeOldest region cells kept = some (selected, remaining)) : cells.Perm (selected :: remaining) := by
  induction cells generalizing remaining with
  | nil => cases taken
  | cons first rest induction =>
    simp only [takeOldest] at taken
    split at taken
    · cases taken
      exact ((induction ‹_›).cons first).trans (.swap _ _ _)
    · split at taken
      · cases taken; exact .refl _
      · cases taken

theorem take_oldest_transfers_owning_fields (cells : Cells signature algebra Body)
    (taken : takeOldest region cells kept = some (selected, remaining)) :
    (UseScope.tokens cells.fields).Perm (selected.value.owningField.tokens ++ UseScope.tokens remaining.fields) := by
  have owners := ((take_oldest_preserves_cells cells taken).map (fun cell => cell.value.owningField)).flatMap_right UseScope.Field.tokens
  simpa only [List.map_cons, List.flatMap_cons, tokens_flatMap, fields] using owners

theorem take_oldest_preserves_other_lookup (cells : Cells signature algebra Body)
    (taken : takeOldest region cells kept = some (selected, remaining))
    (different : identity ≠ selected.identity) : lookup identity remaining = lookup identity cells := by
  induction cells generalizing remaining with
  | nil => cases taken
  | cons first rest induction =>
    simp only [takeOldest] at taken
    split at taken
    · cases taken
      simp only [lookup]
      split
      · rfl
      · exact induction ‹_›
    · split at taken
      · cases taken; simp only [lookup, if_neg (Ne.symm different)]
      · cases taken

theorem take_oldest_preserves_other_reads [DecidableEq (TypeOf signature)]
    (cells : Cells signature algebra Body)
    (taken : takeOldest region cells kept = some (selected, remaining))
    (different : identity ≠ selected.identity) :
    readCopy identity otherRegion type remaining = readCopy identity otherRegion type cells := by
  simp only [readCopy, read, take_oldest_preserves_other_lookup cells taken different]

theorem no_oldest_means_no_pending (cells : Cells signature algebra Body)
    (finished : takeOldest region cells = none) : (handoffRegion region cells).pending = [] := by
  induction cells with
  | nil => rfl
  | cons first rest induction =>
    simp only [takeOldest, List.contains_nil, Bool.false_and, Bool.not_false, Bool.and_true] at finished
    split at finished
    · cases finished
    · split at finished
      · cases finished
      · simpa [handoffRegion, List.filter_cons, ‹¬(first.region == region) = true›] using induction ‹_›

theorem take_oldest_follows_handoff_order (cells : Cells signature algebra Body)
    (taken : takeOldest region cells = some (selected, remaining)) :
    (handoffRegion region cells).pending = selected :: (handoffRegion region remaining).pending := by
  induction cells generalizing remaining with
  | nil => cases taken
  | cons first rest induction =>
    simp only [takeOldest, List.contains_nil, Bool.false_and, Bool.not_false, Bool.and_true] at taken
    split at taken
    · cases taken
      have tail := induction ‹_›
      by_cases same : first.region == region
      · simpa [handoffRegion, same, List.reverse_cons] using congrArg (· ++ [first]) tail
      · simpa [handoffRegion, same] using tail
    · have empty := no_oldest_means_no_pending rest ‹_›
      split at taken
      · cases taken
        change (rest.filter (fun cell => cell.region == region)).reverse = [] at empty
        simp [handoffRegion, ‹(selected.region == region) = true›, List.reverse_cons, empty]
      · cases taken

theorem take_oldest_precedes_a_new_allocation (region : Id .region) (value : Value signature algebra Body type)
    (cells : Cells signature algebra Body) (reserved : List (Id .cell))
    (taken : takeOldest region cells = some (selected, remaining)) :
    takeOldest region (allocate region value cells reserved).cells =
      some (selected, ⟨(allocate region value cells reserved).identity, region, type, value⟩ :: remaining) := by
  simp only [allocate, takeOldest, taken]

inductive Retires (region : Id .region) : Cells signature algebra Body → Cells signature algebra Body →
    Cells signature algebra Body → Prop where
  | refl : Retires region cells [] cells
  | cons : takeOldest region before = some (first, middle) → Retires region middle rest after →
      Retires region before (first :: rest) after

theorem Retires.exact_prefix {before after : Cells signature algebra Body}
    (steps : Retires region before taken after) :
    (handoffRegion region before).pending = taken ++ (handoffRegion region after).pending := by
  induction steps with
  | refl => rfl
  | cons first rest induction => rw [take_oldest_follows_handoff_order _ first, induction]; rfl

theorem complete_handoff_uses_creation_order (region : Id .region) (cells : Cells signature algebra Body)
    (steps : Retires region cells taken after) (finished : takeOldest region after = none) :
    taken = (cells.filter (fun cell => cell.region == region)).reverse := by
  have empty := no_oldest_means_no_pending after finished
  have ordered := steps.exact_prefix
  rw [empty, List.append_nil] at ordered
  exact ordered.symm

theorem taken_cell_is_no_longer_owned_by_the_table (cells : Cells signature algebra Body)
    (unique : cells.identities.Nodup) (taken : takeOldest region cells = some (selected, remaining)) :
    selected.identity ∉ remaining.identities := by
  have ordered := (take_oldest_preserves_cells cells taken).map Cell.identity
  exact (List.nodup_cons.mp (ordered.nodup_iff.mp unique)).1

end Cells

namespace ExitComposition

variable {program : List (BodyType signature.Data signature.Effect)}

/-- Cell storage remains in the live runtime while this region is being drained.
The handoff carries the outer continuation and never closes the lifetime early. -/
structure RegionHandoff (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (input result : TypeOf signature) where
  identity : Id .region
  runtime : Runtime signature algebra program
  outside : Target.Stack signature algebra program input result
  /-- Nonowning references to previously offered zero-owner values. Their cell
  storage stays readable by later cleanup until the lifetime actually closes. -/
  kept : List (Id .cell)

def beginRegionHandoff (identity : Id .region) (runtime : Runtime signature algebra program)
    (outside : Target.Stack signature algebra program input result) : RegionHandoff signature algebra program input result :=
  ⟨identity, runtime, outside, []⟩

/-- The returned value is a view for the disposal interpreter. Its actual owning
field has moved from the removed cell to the runtime's active fields, where
ordinary permission-checked control release can consume it. -/
def RegionHandoff.offerNext (handoff : RegionHandoff signature algebra program input result) :
    Option ((Sigma (Target.RuntimeValue signature algebra program)) × RegionHandoff signature algebra program input result) :=
  (Cells.takeOldest handoff.identity handoff.runtime.cells handoff.kept).map fun (cell, remaining) =>
    if cell.value.owningField.tokens.isEmpty then
      (⟨cell.type, cell.value⟩, { handoff with kept := cell.identity :: handoff.kept })
    else
    let fields := { handoff.runtime.store.fields with active := handoff.runtime.store.fields.active ++ [cell.value.owningField] }
    let runtime := { handoff.runtime with cells := remaining, store := { handoff.runtime.store with fields := fields } }
    (⟨cell.type, cell.value⟩, { handoff with runtime := runtime })

theorem offered_cell_preserves_physical_owners
    (handoff : RegionHandoff signature algebra program input result)
    (offered : handoff.offerNext = some (value, after)) :
    handoff.runtime.physicalInventory.Perm after.runtime.physicalInventory := by
  obtain ⟨⟨cell, remaining⟩, taken, result⟩ := Option.map_eq_some_iff.mp offered
  dsimp only at result
  split at result
  · cases result; exact .refl _
  · cases result
    have moved := Cells.take_oldest_transfers_owning_fields handoff.runtime.cells taken
    have grouped := moved.append_left (UseScope.inventory handoff.runtime.store.fields)
    apply grouped.trans
    simp only [Runtime.physicalInventory, UseScope.inventory, UseScope.tokens_append, UseScope.tokens,
      List.append_nil, List.append_assoc]
    simpa only [List.append_assoc] using
      ((List.perm_append_comm (l₁ := UseScope.tokens handoff.runtime.store.fields.retained)
        (l₂ := cell.value.owningField.tokens)).append_right (UseScope.tokens remaining.fields)).append_left
        (UseScope.tokens handoff.runtime.store.fields.active)

theorem offered_cell_retains_exit_and_lifetime
    (handoff : RegionHandoff signature algebra program input result)
    (offered : handoff.offerNext = some (value, after)) :
    after.runtime.exit = handoff.runtime.exit ∧ after.runtime.phase = handoff.runtime.phase ∧
    after.runtime.liveRegions = handoff.runtime.liveRegions ∧ after.outside = handoff.outside ∧
    after.runtime.store.fields.spent = handoff.runtime.store.fields.spent := by
  obtain ⟨⟨cell, remaining⟩, _, result⟩ := Option.map_eq_some_iff.mp offered
  dsimp only at result
  split at result <;> cases result <;> exact ⟨rfl, rfl, rfl, rfl, rfl⟩

theorem offering_a_copyable_value_keeps_its_cell_storage
    (handoff : RegionHandoff signature algebra program input result)
    (offered : handoff.offerNext = some (value, after)) (copyable : value.snd.copyable = true) :
    after.runtime.cells = handoff.runtime.cells := by
  obtain ⟨⟨cell, remaining⟩, _, result⟩ := Option.map_eq_some_iff.mp offered
  dsimp only at result
  split at result
  · cases result; rfl
  · cases result
    have empty := cell.value.copyable_has_no_owner copyable
    simp only [empty, List.isEmpty_nil] at *
    contradiction

/-- Disposal starts by unwinding the stored context, without manufacturing a
response for its input type. The actual cells and exit history accompany it. -/
def beginControlUnwind (runtime : Runtime signature algebra program) :
    Option (Sigma fun shape : ControlShape signature => UnwindProgress signature algebra program shape.answer) :=
  (UseScope.beginDisposal runtime.store).map fun started =>
    ⟨started.future.fst, .seeking { runtime with store := started.store } started.future.snd.future⟩

theorem released_control_unwinds_its_actual_future
    (runtime : Runtime signature algebra program) (future : Target.ControlPayload signature algebra program shape)
    (started : UseScope.beginDisposal runtime.store = some ⟨store, ⟨shape, future⟩⟩) :
    beginControlUnwind runtime = some ⟨shape, .seeking { runtime with store := store } future.future⟩ := by
  simp only [beginControlUnwind, started, Option.map_some]

end ExitComposition
end BoundaryV2.Generalized
