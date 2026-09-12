import BoundaryV2.GeneralizedOwnership

namespace BoundaryV2.Generalized.UseScope

inductive OneShotUse where
  | affine | linear
  deriving DecidableEq

/-- A view names a grant at its current owner. It is not another owner. -/
structure ControlView where
  identity : Id .control
  authority : Id .custody
  owner : Owner
  deriving DecidableEq

/-- Registry entries are nonowning. Authority resides in the physical fields,
so moving a grant into a closure or package leaves its saved future available. -/
structure ControlInfo (Future : Type) where
  identity : Id .control
  authority : Id .custody
  use : OneShotUse
  future : Future

structure ControlStore (Future : Type) where
  fields : State
  controls : List (ControlInfo Future)
  disposing : List (ControlInfo Future)

def ControlStore.Valid (store : ControlStore Future) : Prop :=
  UseScope.Valid store.fields ∧ (store.controls.map ControlInfo.identity).Nodup ∧
    (store.controls.map ControlInfo.authority).Nodup

def takeControl (wanted : Id .control) : List (ControlInfo Future) → Option (ControlInfo Future × List (ControlInfo Future))
  | [] => none
  | record :: rest =>
    if wanted = record.identity then some (record, rest)
    else (takeControl wanted rest).map fun (found, remaining) => (found, record :: remaining)

theorem take_control_identifies_record (found : takeControl wanted records = some (record, remaining)) :
    wanted = record.identity ∧ records.Perm (record :: remaining) := by
  induction records generalizing remaining with
  | nil => simp [takeControl] at found
  | cons first rest induction =>
    simp only [takeControl] at found
    split at found
    · rename_i same
      cases found
      exact ⟨same, .refl _⟩
    · obtain ⟨⟨selected, tail⟩, taken, mapped⟩ := Option.map_eq_some_iff.mp found
      cases mapped
      obtain ⟨same, permuted⟩ := induction taken
      exact ⟨same, (permuted.cons first).trans (.swap _ _ _)⟩

/- Products are transparent in an active scope. Owned containers remain
sealed until their own activation or unpacking operation opens their fields. -/
mutual
  def activeFields : List Field → List Field
    | [] => []
    | field :: rest => exposeField field ++ activeFields rest
  def exposeField : Field → List Field
    | .group fields => activeFields fields
    | other => [other]
end

mutual
  theorem active_fields_preserve_tokens (fields : List Field) : tokens (activeFields fields) = tokens fields := by
    cases fields with
    | nil => rfl
    | cons field rest => simp only [activeFields, tokens_append, tokens, expose_field_preserves_tokens field, active_fields_preserve_tokens rest]
  termination_by sizeOf fields
  theorem expose_field_preserves_tokens (field : Field) : tokens (exposeField field) = field.tokens := by
    cases field <;> simp only [exposeField, tokens, List.append_nil, Field.tokens]
    exact active_fields_preserve_tokens _
  termination_by sizeOf field
end

def takeGrant (authority : Id .custody) (owner : Owner) : List Field → Option (List Field)
  | [] => none
  | .owned token holder :: rest =>
    if token = authority ∧ holder = owner then some rest
    else (takeGrant authority owner rest).map (Field.owned token holder :: ·)
  | field :: rest => (takeGrant authority owner rest).map (field :: ·)

theorem take_grant_inventory (found : takeGrant authority owner fields = some remaining) :
    (tokens fields).Perm (authority :: tokens remaining) := by
  induction fields generalizing remaining with
  | nil => simp [takeGrant] at found
  | cons field rest induction =>
    cases field <;> simp only [takeGrant] at found
    all_goals first
      | (split at found
         · rename_i same
           rcases same with ⟨rfl, rfl⟩
           cases found
           exact .refl _
         · obtain ⟨tail, taken, rfl⟩ := Option.map_eq_some_iff.mp found
           exact ((induction taken).append_left _).trans (List.perm_middle))
      | (obtain ⟨tail, taken, rfl⟩ := Option.map_eq_some_iff.mp found
         exact ((induction taken).append_left _).trans (List.perm_middle))

def takeCapture (wanted : Id .control) : List Field → Option (List Field × List Field)
  | [] => none
  | .continuation identity fields :: rest =>
    if identity = wanted then some (fields, rest)
    else (takeCapture wanted rest).map fun (found, remaining) => (found, .continuation identity fields :: remaining)
  | field :: rest => (takeCapture wanted rest).map fun (found, remaining) => (found, field :: remaining)

theorem take_capture_inventory (found : takeCapture wanted fields = some (saved, remaining)) :
    (tokens fields).Perm (tokens saved ++ tokens remaining) := by
  induction fields generalizing remaining with
  | nil => simp [takeCapture] at found
  | cons field rest induction =>
    cases field <;> simp only [takeCapture] at found
    all_goals first
      | (split at found
         · cases found
           exact .refl _
         · obtain ⟨⟨next, tail⟩, taken, mapped⟩ := Option.map_eq_some_iff.mp found
           cases mapped
           apply ((induction taken).append_left _).trans
           simpa only [List.append_assoc, tokens] using (List.perm_append_comm (l₁ := _) (l₂ := tokens next)).append_right (tokens tail))
      | (obtain ⟨⟨next, tail⟩, taken, mapped⟩ := Option.map_eq_some_iff.mp found
         cases mapped
         apply ((induction taken).append_left _).trans
         simpa only [List.append_assoc, tokens] using (List.perm_append_comm (l₁ := _) (l₂ := tokens next)).append_right (tokens tail))

structure Acquisition (Future : Type) where
  store : ControlStore Future
  future : Future

/-- Acquisition resolves the registry, removes the active grant, and opens its
saved fields before exposing the future. Read-only and sealed views cannot use
the presence of a registry row as authority. -/
def acquire (view : ControlView) (store : ControlStore Future) : Option (Acquisition Future) :=
  match takeControl view.identity store.controls with
  | none => none
  | some (record, records) =>
    if record.authority = view.authority then
      match takeGrant view.authority view.owner (activeFields store.fields.active), takeCapture view.identity store.fields.retained with
      | some active, some (saved, retained) =>
        some ⟨⟨⟨saved ++ active, retained, view.authority :: store.fields.spent⟩, records, store.disposing⟩, record.future⟩
      | _, _ => none
    else none

theorem grant_and_capture_consumption_preserves (valid : UseScope.Valid fields)
    (grant : takeGrant authority owner (activeFields fields.active) = some active)
    (capture : takeCapture identity fields.retained = some (saved, retained)) :
    UseScope.Valid ⟨saved ++ active, retained, authority :: fields.spent⟩ := by
  have granted := take_grant_inventory grant
  rw [active_fields_preserve_tokens] at granted
  have captured := take_capture_inventory capture
  have combined := granted.append captured
  have permuted : (inventory fields).Perm (authority :: (tokens saved ++ tokens active ++ tokens retained)) := by
    apply combined.trans
    simpa only [List.cons_append, List.append_assoc] using
      ((List.perm_append_comm (l₁ := tokens active) (l₂ := tokens saved)).append_right (tokens retained)).cons authority
  have prepared : UseScope.Valid ⟨.owned authority owner :: (saved ++ active), retained, fields.spent⟩ :=
    valid_of_inventory _ _ valid (by simpa only [inventory, tokens, Field.tokens, tokens_append, List.cons_append, List.nil_append] using permuted) rfl
  exact consume_preserves_ownership _ _ _ _ _ prepared

theorem acquire_preserves_ownership (valid : ControlStore.Valid store) (accepted : acquire view store = some result) :
    ControlStore.Valid result.store := by
  cases controlAt : takeControl view.identity store.controls with
  | none => simp [acquire, controlAt] at accepted
  | some selected =>
    rcases selected with ⟨record, records⟩
    simp only [acquire, controlAt] at accepted
    split at accepted
    · cases grantAt : takeGrant view.authority view.owner (activeFields store.fields.active) with
      | none => simp [grantAt] at accepted
      | some active =>
        cases captureAt : takeCapture view.identity store.fields.retained with
        | none => simp [grantAt, captureAt] at accepted
        | some captured =>
          rcases captured with ⟨saved, retained⟩
          simp only [grantAt, captureAt, Option.some.injEq] at accepted
          cases accepted
          have permuted := (take_control_identifies_record controlAt).2
          exact ⟨grant_and_capture_consumption_preserves valid.1 grantAt captureAt,
            (List.nodup_cons.mp ((permuted.map ControlInfo.identity).nodup_iff.mp valid.2.1)).2,
            (List.nodup_cons.mp ((permuted.map ControlInfo.authority).nodup_iff.mp valid.2.2)).2⟩
    · contradiction

theorem acquire_returns_stored_future (accepted : acquire view store = some result) :
    ∃ record records, takeControl view.identity store.controls = some (record, records) ∧
      record.authority = view.authority ∧ result.future = record.future ∧
      result.store.fields.spent = view.authority :: store.fields.spent := by
  cases controlAt : takeControl view.identity store.controls with
  | none => simp [acquire, controlAt] at accepted
  | some selected =>
    rcases selected with ⟨record, records⟩
    simp only [acquire, controlAt] at accepted
    split at accepted
    · rename_i same
      cases grantAt : takeGrant view.authority view.owner (activeFields store.fields.active) with
      | none => simp [grantAt] at accepted
      | some active =>
        cases captureAt : takeCapture view.identity store.fields.retained with
        | none => simp [grantAt, captureAt] at accepted
        | some captured =>
          rcases captured with ⟨saved, retained⟩
          simp only [grantAt, captureAt, Option.some.injEq] at accepted
          cases accepted
          exact ⟨record, records, rfl, same, rfl, rfl⟩
    · contradiction

theorem acquired_authority_not_live (valid : ControlStore.Valid store) (accepted : acquire view store = some result) :
    view.authority ∉ inventory result.store.fields := by
  have after := (acquire_preserves_ownership valid accepted).1
  obtain ⟨record, records, _, _, _, spent⟩ := acquire_returns_stored_future accepted
  intro member
  apply after.2.2 _ member
  simp [spent]

theorem acquired_view_cannot_repeat (valid : ControlStore.Valid store) (accepted : acquire view store = some result) :
    acquire view result.store = none := by
  cases retried : acquire view result.store with
  | none => rfl
  | some next =>
    have firstSpent := (acquire_returns_stored_future accepted).choose_spec.choose_spec.2.2.2
    have secondSpent := (acquire_returns_stored_future retried).choose_spec.choose_spec.2.2.2
    have unique := (acquire_preserves_ownership (acquire_preserves_ownership valid accepted) retried).1.2.1
    rw [secondSpent, firstSpent] at unique
    simp at unique

theorem sealed_grant_cannot_be_acquired (view : ControlView) (contents : List Field) :
    takeGrant view.authority view.owner (activeFields [.package contents]) = none := rfl

inductive Release where
  | explicit | affineDrop
  deriving DecidableEq

def permittedRelease (action : Release) (use : OneShotUse) : Bool :=
  match action, use with
  | .explicit, _ | .affineDrop, .affine => true
  | .affineDrop, .linear => false

/-- Disposal moves the future into pending work. Its captured physical scope
stays retained until the exit interpreter drains it, including nested owners. -/
def release (action : Release) (view : ControlView) (store : ControlStore Future) : Option (ControlStore Future) :=
  match takeControl view.identity store.controls with
  | none => none
  | some (record, records) =>
    if record.authority = view.authority ∧ permittedRelease action record.use then
      match takeGrant view.authority view.owner (activeFields store.fields.active), takeCapture view.identity store.fields.retained with
      | some active, some _ => some ⟨⟨active, store.fields.retained, view.authority :: store.fields.spent⟩, records, record :: store.disposing⟩
      | _, _ => none
    else none

theorem grant_consumption_preserves (valid : UseScope.Valid fields)
    (grant : takeGrant authority owner (activeFields fields.active) = some active) :
    UseScope.Valid ⟨active, fields.retained, authority :: fields.spent⟩ := by
  have removed := take_grant_inventory grant
  rw [active_fields_preserve_tokens] at removed
  have prepared : UseScope.Valid ⟨.owned authority owner :: active, fields.retained, fields.spent⟩ :=
    valid_of_inventory _ _ valid (by simpa only [inventory, tokens, Field.tokens, List.cons_append, List.nil_append] using removed.append_right (tokens fields.retained)) rfl
  exact consume_preserves_ownership _ _ _ _ _ prepared

theorem release_preserves_ownership (valid : ControlStore.Valid store) (accepted : release action view store = some result) :
    ControlStore.Valid result := by
  cases controlAt : takeControl view.identity store.controls with
  | none => simp [release, controlAt] at accepted
  | some selected =>
    rcases selected with ⟨record, records⟩
    simp only [release, controlAt] at accepted
    split at accepted
    · cases grantAt : takeGrant view.authority view.owner (activeFields store.fields.active) with
      | none => simp [grantAt] at accepted
      | some active =>
        cases captureAt : takeCapture view.identity store.fields.retained with
        | none => simp [grantAt, captureAt] at accepted
        | some captured =>
          simp only [grantAt, captureAt, Option.some.injEq] at accepted
          cases accepted
          have permuted := (take_control_identifies_record controlAt).2
          exact ⟨grant_consumption_preserves valid.1 grantAt,
            (List.nodup_cons.mp ((permuted.map ControlInfo.identity).nodup_iff.mp valid.2.1)).2,
            (List.nodup_cons.mp ((permuted.map ControlInfo.authority).nodup_iff.mp valid.2.2)).2⟩
    · contradiction

theorem release_keeps_captured_fields (accepted : release action view store = some result) :
    result.fields.retained = store.fields.retained := by
  cases controlAt : takeControl view.identity store.controls with
  | none => simp [release, controlAt] at accepted
  | some selected =>
    rcases selected with ⟨record, records⟩
    simp only [release, controlAt] at accepted
    split at accepted
    · cases grantAt : takeGrant view.authority view.owner (activeFields store.fields.active) with
      | none => simp [grantAt] at accepted
      | some active =>
        cases captureAt : takeCapture view.identity store.fields.retained with
        | none => simp [grantAt, captureAt] at accepted
        | some captured =>
          simp only [grantAt, captureAt, Option.some.injEq] at accepted
          cases accepted
          rfl
    · contradiction

theorem linear_drop_rejects (taken : takeControl view.identity store.controls = some (record, records))
    (linear : record.use = .linear) : release .affineDrop view store = none := by
  simp [release, taken, linear, permittedRelease]

end BoundaryV2.Generalized.UseScope
