import BoundaryV2.GeneralizedFieldRelocation

namespace BoundaryV2.Generalized.UseScope

variable {Before After : Type}

def ControlView.relocate (relocation : Relocation) (view : ControlView) : ControlView :=
  ⟨relocation.name .control view.identity, relocation.name .custody view.authority, relocation.owner view.owner⟩

def ControlInfo.relocate (relocation : Relocation) (future : Before → After) (record : ControlInfo Before) : ControlInfo After :=
  ⟨relocation.name .control record.identity, relocation.name .custody record.authority, record.use, future record.future⟩

def ControlStore.relocate (relocation : Relocation) (future : Before → After) (store : ControlStore Before) : ControlStore After :=
  ⟨store.fields.relocate relocation, store.controls.map (ControlInfo.relocate relocation future),
    store.disposing.map (ControlInfo.relocate relocation future)⟩

def Acquisition.relocate (relocation : Relocation) (future : Before → After) (acquired : Acquisition Before) : Acquisition After :=
  ⟨acquired.store.relocate relocation future, future acquired.future⟩

theorem control_store_relocation_preserves_ownership (relocation : Relocation) (future : Before → After)
    (store : ControlStore Before) (valid : store.Valid)
    (fields : ∀ first ∈ inventory store.fields ++ store.fields.spent, ∀ second ∈ inventory store.fields ++ store.fields.spent,
      relocation.name .custody first = relocation.name .custody second → first = second)
    (controls : ∀ first ∈ store.controls.map ControlInfo.identity, ∀ second ∈ store.controls.map ControlInfo.identity,
      relocation.name .control first = relocation.name .control second → first = second)
    (authorities : ∀ first ∈ store.controls.map ControlInfo.authority, ∀ second ∈ store.controls.map ControlInfo.authority,
      relocation.name .custody first = relocation.name .custody second → first = second) :
    (store.relocate relocation future).Valid := by
  refine ⟨relocation_preserves_ownership relocation store.fields valid.1 fields, ?_, ?_⟩
  · simpa only [ControlStore.relocate, List.map_map, Function.comp_def, ControlInfo.relocate] using
      nodup_map_on (relocation.name .control) valid.2.1 controls
  · simpa only [ControlStore.relocate, List.map_map, Function.comp_def, ControlInfo.relocate] using
      nodup_map_on (relocation.name .custody) valid.2.2 authorities

mutual
  theorem active_fields_relocate (relocation : Relocation) (fields : List Field) :
      activeFields (relocateFields relocation fields) = relocateFields relocation (activeFields fields) := by
    cases fields with
    | nil => rfl
    | cons field rest => simp only [relocateFields, activeFields, expose_field_relocate relocation field,
        active_fields_relocate relocation rest, relocate_fields_append]
  termination_by sizeOf fields

  theorem expose_field_relocate (relocation : Relocation) (field : Field) :
      exposeField (field.relocate relocation) = relocateFields relocation (exposeField field) := by
    cases field <;> simp only [Field.relocate, exposeField, relocateFields]
    exact active_fields_relocate relocation _
  termination_by sizeOf field
end

/-- The key premise reflects equality only against keys actually inspected by
this lookup. Injectivity on the finite support including `wanted` implies it. -/
theorem take_control_relocate (relocation : Relocation) (future : Before → After) (wanted : Id .control)
    (records : List (ControlInfo Before))
    (faithful : ∀ record ∈ records, relocation.name .control wanted = relocation.name .control record.identity → wanted = record.identity) :
    takeControl (relocation.name .control wanted) (records.map (ControlInfo.relocate relocation future)) =
      (takeControl wanted records).map (fun pair =>
        (pair.1.relocate relocation future, pair.2.map (ControlInfo.relocate relocation future))) := by
  induction records with
  | nil => rfl
  | cons record rest induction =>
    have tail := induction (fun record member same => faithful record (List.mem_cons_of_mem _ member) same)
    by_cases same : wanted = record.identity
    · simp only [List.map_cons, takeControl, ControlInfo.relocate, same, ite_true, Option.map_some]
    · have different : relocation.name .control wanted ≠ relocation.name .control record.identity :=
        fun equal => same (faithful record List.mem_cons_self equal)
      simp only [List.map_cons, takeControl, ControlInfo.relocate, if_neg same, if_neg different, tail, Option.map_map]
      rfl

theorem take_grant_relocate (relocation : Relocation) (authority : Id .custody) (owner : Owner) (fields : List Field)
    (faithful : ∀ token holder, Field.owned token holder ∈ fields →
      relocation.name .custody token = relocation.name .custody authority ∧ relocation.owner holder = relocation.owner owner →
        token = authority ∧ holder = owner) :
    takeGrant (relocation.name .custody authority) (relocation.owner owner) (relocateFields relocation fields) =
      (takeGrant authority owner fields).map (relocateFields relocation) := by
  induction fields with
  | nil => rfl
  | cons field rest induction =>
    have tail := induction (fun token holder member same => faithful token holder (List.mem_cons_of_mem _ member) same)
    cases field <;> simp only [relocateFields, Field.relocate, takeGrant]
    all_goals first
      | (rename_i token holder
         by_cases same : token = authority ∧ holder = owner
         · rcases same with ⟨rfl, rfl⟩
           simp only [and_self, ite_true, Option.map_some]
         · have different : ¬ (relocation.name .custody token = relocation.name .custody authority ∧ relocation.owner holder = relocation.owner owner) :=
             fun equal => same (faithful token holder List.mem_cons_self equal)
           simp only [if_neg same, if_neg different, tail, Option.map_map]
           rfl)
      | (simp only [tail, Option.map_map]; rfl)

theorem take_capture_relocate (relocation : Relocation) (wanted : Id .control) (fields : List Field)
    (faithful : ∀ identity saved, Field.continuation identity saved ∈ fields →
      relocation.name .control identity = relocation.name .control wanted → identity = wanted) :
    takeCapture (relocation.name .control wanted) (relocateFields relocation fields) =
      (takeCapture wanted fields).map (fun pair => (relocateFields relocation pair.1, relocateFields relocation pair.2)) := by
  induction fields with
  | nil => rfl
  | cons field rest induction =>
    have tail := induction (fun identity saved member same => faithful identity saved (List.mem_cons_of_mem _ member) same)
    cases field <;> simp only [relocateFields, Field.relocate, takeCapture]
    all_goals first
      | (rename_i identity saved
         by_cases same : identity = wanted
         · subst identity
           simp only [ite_true, Option.map_some]
         · have different : relocation.name .control identity ≠ relocation.name .control wanted :=
             fun equal => same (faithful identity saved List.mem_cons_self equal)
           simp only [if_neg same, if_neg different, tail, Option.map_map]
           rfl)
      | (simp only [tail, Option.map_map]; rfl)

/-- These are finite equality-reflection premises for the actual registry and
physical fields, including the queried owner. They assume no result of `acquire`
or `release` and can be discharged from injective name/owner maps. -/
structure LookupRelocation (relocation : Relocation) (view : ControlView) (store : ControlStore Before) : Prop where
  controls : ∀ record ∈ store.controls,
    relocation.name .control view.identity = relocation.name .control record.identity → view.identity = record.identity
  authorities : ∀ record ∈ store.controls,
    relocation.name .custody record.authority = relocation.name .custody view.authority → record.authority = view.authority
  grants : ∀ token holder, Field.owned token holder ∈ activeFields store.fields.active →
    relocation.name .custody token = relocation.name .custody view.authority ∧ relocation.owner holder = relocation.owner view.owner →
      token = view.authority ∧ holder = view.owner
  captures : ∀ identity saved, Field.continuation identity saved ∈ store.fields.retained →
    relocation.name .control identity = relocation.name .control view.identity → identity = view.identity

theorem acquire_relocate (relocation : Relocation) (future : Before → After) (view : ControlView) (store : ControlStore Before)
    (faithful : LookupRelocation relocation view store) :
    acquire (view.relocate relocation) (store.relocate relocation future) =
      (acquire view store).map (Acquisition.relocate relocation future) := by
  have controls := take_control_relocate relocation future view.identity store.controls faithful.controls
  have grants := take_grant_relocate relocation view.authority view.owner (activeFields store.fields.active) faithful.grants
  have captures := take_capture_relocate relocation view.identity store.fields.retained faithful.captures
  unfold acquire
  simp only [ControlView.relocate, ControlStore.relocate, State.relocate, active_fields_relocate,
    controls, grants, captures]
  cases picked : takeControl view.identity store.controls with
  | none => rfl
  | some pair =>
    rcases pair with ⟨record, records⟩
    have member := (take_control_identifies_record picked).2.mem_iff.mpr (List.mem_cons_self : record ∈ record :: records)
    dsimp only [Option.map, ControlInfo.relocate]
    by_cases same : record.authority = view.authority
    · simp only [same, ite_true]
      cases takeGrant view.authority view.owner (activeFields store.fields.active) <;>
        cases takeCapture view.identity store.fields.retained
      all_goals first | rfl | (rename_i pair; cases pair; simp only [Acquisition.relocate,
        ControlStore.relocate, State.relocate, relocate_fields_append, List.map_cons])
    · have different : relocation.name .custody record.authority ≠ relocation.name .custody view.authority :=
        fun equal => same (faithful.authorities record member equal)
      simp only [if_neg same, if_neg different]

theorem release_relocate (relocation : Relocation) (future : Before → After) (action : Release)
    (view : ControlView) (store : ControlStore Before) (faithful : LookupRelocation relocation view store) :
    release action (view.relocate relocation) (store.relocate relocation future) =
      (release action view store).map (ControlStore.relocate relocation future) := by
  have controls := take_control_relocate relocation future view.identity store.controls faithful.controls
  have grants := take_grant_relocate relocation view.authority view.owner (activeFields store.fields.active) faithful.grants
  have captures := take_capture_relocate relocation view.identity store.fields.retained faithful.captures
  unfold release
  simp only [ControlView.relocate, ControlStore.relocate, State.relocate, active_fields_relocate,
    controls, grants, captures]
  cases picked : takeControl view.identity store.controls with
  | none => rfl
  | some pair =>
    rcases pair with ⟨record, records⟩
    have member := (take_control_identifies_record picked).2.mem_iff.mpr (List.mem_cons_self : record ∈ record :: records)
    dsimp only [Option.map, ControlInfo.relocate]
    have authority : (relocation.name .custody record.authority = relocation.name .custody view.authority) =
        (record.authority = view.authority) := propext ⟨faithful.authorities record member, congrArg _⟩
    simp only [authority]
    by_cases allowed : record.authority = view.authority ∧ permittedRelease action record.use
    · simp only [if_pos allowed]
      cases takeGrant view.authority view.owner (activeFields store.fields.active) <;>
        cases takeCapture view.identity store.fields.retained
      all_goals first | rfl | (rename_i pair; cases pair; rfl)
    · simp only [if_neg allowed]

/-- A convenient sufficient premise. The operational theorems above need only
finite key reflection, so local fresh maps need not be injective on unused names. -/
theorem LookupRelocation.of_injective (relocation : Relocation) (view : ControlView) (store : ControlStore Before)
    (controls : ∀ first second, relocation.name .control first = relocation.name .control second → first = second)
    (custody : ∀ first second, relocation.name .custody first = relocation.name .custody second → first = second)
    (owners : ∀ first second, relocation.owner first = relocation.owner second → first = second) :
    LookupRelocation relocation view store := by
  exact ⟨fun record _ same => controls _ _ same, fun record _ same => custody _ _ same,
    fun token holder _ same => ⟨custody _ _ same.1, owners _ _ same.2⟩,
    fun identity _ _ same => controls _ _ same⟩

end BoundaryV2.Generalized.UseScope
