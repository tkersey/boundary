import BoundaryV2.GeneralizedControlCreation

namespace BoundaryV2.Generalized.UseScope

variable {SourceFuture TargetFuture : Type} (related : SourceFuture → TargetFuture → Prop)

/-- Metadata and physical custody agree; future representations can differ. In
the defunctionalization instance those futures are source functions versus data
stacks. This relation supplies no execution theorem as a premise. -/
structure ControlInfo.Related (source : ControlInfo SourceFuture) (target : ControlInfo TargetFuture) : Prop where
  identity : source.identity = target.identity
  authority : source.authority = target.authority
  use : source.use = target.use
  future : related source.future target.future

inductive ControlInfosRelated : List (ControlInfo SourceFuture) → List (ControlInfo TargetFuture) → Prop where
  | nil : ControlInfosRelated [] []
  | cons : ControlInfo.Related related first second → ControlInfosRelated rest tail →
      ControlInfosRelated (first :: rest) (second :: tail)

structure ControlStore.Related (source : ControlStore SourceFuture) (target : ControlStore TargetFuture) : Prop where
  fields : source.fields = target.fields
  controls : ControlInfosRelated related source.controls target.controls
  disposing : ControlInfosRelated related source.disposing target.disposing

theorem related_control_identities (records : ControlInfosRelated related source target) :
    source.map ControlInfo.identity = target.map ControlInfo.identity := by
  induction records with
  | nil => rfl
  | cons first rest induction => simp only [List.map_cons, first.identity, induction]

theorem related_control_authorities (records : ControlInfosRelated related source target) :
    source.map ControlInfo.authority = target.map ControlInfo.authority := by
  induction records with
  | nil => rfl
  | cons first rest induction => simp only [List.map_cons, first.authority, induction]

theorem related_fresh_views (stores : ControlStore.Related related source target) (owner : Owner) :
    freshControlView owner source = freshControlView owner target := by
  simp only [freshControlView, ControlStore.controlSupport, ControlStore.custodySupport, stores.fields,
    List.map_append, related_control_identities related stores.controls,
    related_control_identities related stores.disposing, related_control_authorities related stores.controls,
    related_control_authorities related stores.disposing]

theorem create_control_corresponds (stores : ControlStore.Related related source target)
    (futures : related sourceFuture targetFuture)
    (sourcePartition : source.fields.active = before ++ selected ++ after)
    (targetPartition : target.fields.active = before ++ selected ++ after) :
    let left := createControl use sourceFuture owner before selected after source sourcePartition
    let right := createControl use targetFuture owner before selected after target targetPartition
    left.view = right.view ∧ ControlStore.Related related left.store right.store := by
  have views := related_fresh_views related stores owner
  refine ⟨views, ?_, ?_, stores.disposing⟩
  · simp only [createControl, views, stores.fields]
  · exact .cons ⟨congrArg ControlView.identity views, congrArg ControlView.authority views, rfl, futures⟩ stores.controls

theorem take_control_corresponds (records : ControlInfosRelated related source target)
    (wanted : Id .control) :
    Option.Rel (fun first second => ControlInfo.Related related first.1 second.1 ∧
      ControlInfosRelated related first.2 second.2)
      (takeControl wanted source) (takeControl wanted target) := by
  induction records with
  | nil => exact .none
  | @cons first second left right matching rest induction =>
    simp only [takeControl, matching.identity]
    by_cases found : wanted = second.identity
    · simp only [if_pos found]
      exact .some ⟨matching, rest⟩
    · simp only [if_neg found]
      generalize sourceAt : takeControl wanted left = sourceTaken at induction ⊢
      generalize targetAt : takeControl wanted right = targetTaken at induction ⊢
      cases induction with
      | none => exact .none
      | some pair => exact .some ⟨pair.1, .cons matching pair.2⟩

structure Acquisition.Related (source : Acquisition SourceFuture) (target : Acquisition TargetFuture) : Prop where
  store : ControlStore.Related related source.store target.store
  future : related source.future target.future

theorem acquire_corresponds (stores : ControlStore.Related related source target) (view : ControlView) :
    Option.Rel (Acquisition.Related related) (acquire view source) (acquire view target) := by
  have records := take_control_corresponds related stores.controls view.identity
  unfold acquire
  generalize sourceAt : takeControl view.identity source.controls = sourceTaken at records ⊢
  generalize targetAt : takeControl view.identity target.controls = targetTaken at records ⊢
  cases records with
  | none => exact .none
  | @some first second pair =>
    rcases first with ⟨sourceRecord, sourceRest⟩
    rcases second with ⟨targetRecord, targetRest⟩
    dsimp only
    have authorities : sourceRecord.authority = targetRecord.authority := pair.1.authority
    simp only [authorities, stores.fields]
    by_cases allowed : targetRecord.authority = view.authority
    · simp only [if_pos allowed]
      cases takeGrant view.authority view.owner (activeFields target.fields.active) with
      | none =>
        cases takeCapture view.identity target.fields.retained <;> exact .none
      | some active =>
        cases takeCapture view.identity target.fields.retained with
        | none => exact .none
        | some captured =>
          rcases captured with ⟨saved, retained⟩
          exact .some ⟨⟨rfl, pair.2, stores.disposing⟩, pair.1.future⟩
    · simp only [if_neg allowed]
      exact .none

end BoundaryV2.Generalized.UseScope
