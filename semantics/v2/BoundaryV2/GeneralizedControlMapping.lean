import BoundaryV2.GeneralizedControlPayload

namespace BoundaryV2.Generalized.UseScope

variable {Before After : Type}

def ControlInfo.mapFuture (convert : Before → After) (record : ControlInfo Before) : ControlInfo After :=
  ⟨record.identity, record.authority, record.use, convert record.future⟩

def ControlStore.mapFuture (convert : Before → After) (store : ControlStore Before) : ControlStore After :=
  ⟨store.fields, store.controls.map (ControlInfo.mapFuture convert), store.disposing.map (ControlInfo.mapFuture convert)⟩

def Acquisition.mapFuture (convert : Before → After) (acquired : Acquisition Before) : Acquisition After :=
  ⟨acquired.store.mapFuture convert, convert acquired.future⟩

/-- A representation projection changes only the future relation, preserving
every control entry, authority, and physical field on both sides. -/
theorem ControlStore.related_map_left_iff {Target : Type}
    (convert : Before → After) (related : After → Target → Prop)
    (source : ControlStore Before) (target : ControlStore Target) :
    ControlStore.Related related (source.mapFuture convert) target ↔
      ControlStore.Related (fun first second => related (convert first) second) source target := by
  have records : ∀ (first : List (ControlInfo Before)) (second : List (ControlInfo Target)),
      ControlInfosRelated related (first.map (ControlInfo.mapFuture convert)) second ↔
        ControlInfosRelated (fun a b => related (convert a) b) first second := by
    intro first
    induction first with
    | nil => intro second; constructor <;> intro matched <;> cases matched <;> exact .nil
    | cons first rest induction =>
      intro second
      constructor
      · intro matched
        cases matched with
        | cons head tail => exact .cons ⟨head.identity, head.authority, head.use, head.future⟩ ((induction _).mp tail)
      · intro matched
        cases matched with
        | cons head tail => exact .cons ⟨head.identity, head.authority, head.use, head.future⟩ ((induction _).mpr tail)
  constructor
  · intro matched
    exact ⟨matched.fields, (records _ _).mp matched.controls, (records _ _).mp matched.disposing⟩
  · intro matched
    exact ⟨matched.fields, (records _ _).mpr matched.controls, (records _ _).mpr matched.disposing⟩

theorem ControlStore.map_related (convert : Before → After) (source : ControlStore Before) :
    ControlStore.Related (fun first second => convert first = second) source (source.mapFuture convert) := by
  have records : ∀ items : List (ControlInfo Before),
      ControlInfosRelated (fun first second => convert first = second) items (items.map (ControlInfo.mapFuture convert)) := by
    intro items
    induction items with
    | nil => exact .nil
    | cons first rest induction => exact .cons ⟨rfl, rfl, rfl, rfl⟩ induction
  exact ⟨rfl, records source.controls, records source.disposing⟩

theorem ControlStore.related_map_eq (convert : Before → After)
    (related : ControlStore.Related (fun first second => convert first = second) source target) :
    source.mapFuture convert = target := by
  have records : ∀ {first : List (ControlInfo Before)} {second : List (ControlInfo After)},
      ControlInfosRelated (fun first second => convert first = second) first second →
      first.map (ControlInfo.mapFuture convert) = second := by
    intro first second matching
    induction matching with
    | nil => rfl
    | @cons first second left right paired rest induction =>
      have equal : first.mapFuture convert = second := by
        cases first
        cases second
        rcases paired with ⟨identity, authority, use, future⟩
        simp_all [ControlInfo.mapFuture]
      rw [List.map_cons, equal, induction]
  cases source
  cases target
  rcases related with ⟨fields, controls, disposing⟩
  simp_all [ControlStore.mapFuture, records controls, records disposing]

theorem take_control_map (convert : Before → After) (records : List (ControlInfo Before)) :
    takeControl identity (records.map (ControlInfo.mapFuture convert)) =
      (takeControl identity records).map (fun (record, rest) => (record.mapFuture convert, rest.map (ControlInfo.mapFuture convert))) := by
  induction records with
  | nil => rfl
  | cons first rest induction =>
    simp only [List.map_cons, takeControl, ControlInfo.mapFuture]
    split
    · rfl
    · rw [induction]
      cases takeControl identity rest <;> rfl

/-- Transforming future representations does not change grant consumption,
captured field handoff, or refusal of a missing/wrong owner. -/
theorem acquire_map (convert : Before → After) (store : ControlStore Before) :
    acquire view (store.mapFuture convert) = (acquire view store).map (Acquisition.mapFuture convert) := by
  unfold acquire
  simp only [ControlStore.mapFuture, take_control_map]
  cases selectionResult : takeControl view.identity store.controls with
  | none => rfl
  | some selected =>
    rcases selected with ⟨record, rest⟩
    dsimp only [Option.map, ControlInfo.mapFuture]
    split
    · cases takeGrant view.authority view.owner (activeFields store.fields.active) <;>
        cases takeCapture view.identity store.fields.retained <;> rfl
    · rfl

variable {Index : Type} {SourcePayload TargetPayload : Index → Type}

def mapPacked (convert : ∀ index, SourcePayload index → TargetPayload index) (packed : Sigma SourcePayload) : Sigma TargetPayload :=
  ⟨packed.fst, convert packed.fst packed.snd⟩

def TypedAcquisition.mapFuture (convert : ∀ index, SourcePayload index → TargetPayload index)
    (acquired : TypedAcquisition SourcePayload shape) : TypedAcquisition TargetPayload shape :=
  ⟨acquired.store.mapFuture (mapPacked convert), convert shape acquired.future⟩

theorem acquire_at_map [DecidableEq Index] (convert : ∀ index, SourcePayload index → TargetPayload index)
    (store : ControlStore (Sigma SourcePayload)) :
    acquireAt shape view (store.mapFuture (mapPacked convert)) =
      (acquireAt shape view store).map (TypedAcquisition.mapFuture convert) := by
  unfold acquireAt
  rw [acquire_map]
  cases acquisitionResult : acquire view store with
  | none => rfl
  | some acquired =>
    rcases acquired with ⟨after, ⟨original, future⟩⟩
    simp only [Option.map_some, Option.bind_some, Acquisition.mapFuture, mapPacked, unpackControl]
    by_cases same : original = shape
    · subst original
      simp only [↓reduceDIte, Option.map_some, TypedAcquisition.mapFuture]
    · simp only [dif_neg same, Option.map_none]

end BoundaryV2.Generalized.UseScope
