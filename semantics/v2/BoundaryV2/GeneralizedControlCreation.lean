import BoundaryV2.GeneralizedControlStore
import BoundaryV2.GeneralizedFreshNames

namespace BoundaryV2.Generalized.UseScope

/- Name support includes dormant containers and nonowning aliases. Allocation
must not make an old alias into a view of newly created authority. -/
mutual
  def Field.custodyNames : Field → List (Id .custody)
    | .owned name _ | .alias name => [name]
    | .borrowed _ => []
    | .group fields | .closure fields | .continuation _ fields | .package fields | .cleanup _ fields => custodyNames fields
  def custodyNames : List Field → List (Id .custody)
    | [] => []
    | field :: rest => field.custodyNames ++ custodyNames rest
end

mutual
  def Field.controlNames : Field → List (Id .control)
    | .owned _ _ | .alias _ | .borrowed _ => []
    | .continuation name fields => name :: controlNames fields
    | .group fields | .closure fields | .package fields | .cleanup _ fields => controlNames fields
  def controlNames : List Field → List (Id .control)
    | [] => []
    | field :: rest => field.controlNames ++ controlNames rest
end

mutual
  theorem field_tokens_are_supported (field : Field) :
      ∀ token ∈ field.tokens, token ∈ field.custodyNames := by
    cases field <;> simp only [Field.tokens, Field.custodyNames]
    all_goals first | exact fun _ member => member | exact tokens_are_supported _ | simp
  termination_by sizeOf field

  theorem tokens_are_supported (fields : List Field) :
      ∀ token ∈ tokens fields, token ∈ custodyNames fields := by
    cases fields with
    | nil => simp [tokens]
    | cons field rest =>
      intro token member
      rcases List.mem_append.mp member with first | later
      · exact List.mem_append_left _ (field_tokens_are_supported field token first)
      · exact List.mem_append_right _ (tokens_are_supported rest token later)
  termination_by sizeOf fields
end

def ControlStore.custodySupport (store : ControlStore Future) : List (Id .custody) :=
  custodyNames store.fields.active ++ custodyNames store.fields.retained ++ store.fields.spent ++
    (store.controls ++ store.disposing).map ControlInfo.authority

def ControlStore.controlSupport (store : ControlStore Future) : List (Id .control) :=
  controlNames store.fields.active ++ controlNames store.fields.retained ++
    (store.controls ++ store.disposing).map ControlInfo.identity

theorem inventory_is_supported (store : ControlStore Future) (member : token ∈ inventory store.fields) :
    token ∈ store.custodySupport := by
  rcases List.mem_append.mp member with active | retained
  · have found := tokens_are_supported store.fields.active token active
    simp only [ControlStore.custodySupport, List.mem_append]
    exact Or.inl (Or.inl (Or.inl found))
  · have found := tokens_are_supported store.fields.retained token retained
    simp only [ControlStore.custodySupport, List.mem_append]
    exact Or.inl (Or.inl (Or.inr found))

def freshName (support : List (Id domain)) : Id domain := ⟨FreshNames.bound support⟩

theorem fresh_name_not_supported (support : List (Id domain)) : freshName support ∉ support := by
  intro member
  have impossible := FreshNames.member_below_bound member
  exact Nat.lt_irrefl _ impossible

def freshControlView (owner : Owner) (store : ControlStore Future) : ControlView :=
  ⟨freshName store.controlSupport, freshName store.custodySupport, owner⟩

structure Creation (Future : Type) where
  store : ControlStore Future
  view : ControlView

/-- The partition is a physical move from the active scope, not a copied list
of roots. Existing registry entries are nonowning and remain available, including
those whose grants move into the new continuation's sealed fields. -/
def createControl (use : OneShotUse) (future : Future) (owner : Owner)
    (before selected after : List Field) (store : ControlStore Future)
    (_partition : store.fields.active = before ++ selected ++ after) : Creation Future :=
  let view := freshControlView owner store
  ⟨⟨⟨.owned view.authority owner :: (before ++ after),
      .continuation view.identity selected :: store.fields.retained, store.fields.spent⟩,
    ⟨view.identity, view.authority, use, future⟩ :: store.controls, store.disposing⟩, view⟩

theorem create_control_preserves_ownership (valid : ControlStore.Valid store)
    (partition : store.fields.active = before ++ selected ++ after) :
    ControlStore.Valid (createControl use future owner before selected after store partition).store := by
  have oldValid : Valid ⟨before ++ selected ++ after, store.fields.retained, store.fields.spent⟩ := by
    simpa only [← partition] using valid.1
  have moved := capture_preserves_ownership before selected after store.fields.retained store.fields.spent
    (freshControlView owner store).identity oldValid
  have permuted := capture_inventory before selected after store.fields.retained store.fields.spent
    (freshControlView owner store).identity
  have fresh := fresh_name_not_supported store.custodySupport
  have absent : (freshControlView owner store).authority ∉
      inventory (capture before selected after store.fields.retained store.fields.spent (freshControlView owner store).identity) := by
    intro member
    apply fresh
    apply inventory_is_supported store
    simpa only [inventory, ← partition, freshControlView] using permuted.mem_iff.mpr member
  have unspent : (freshControlView owner store).authority ∉ store.fields.spent := by
    intro member
    apply fresh
    simp only [ControlStore.custodySupport, List.mem_append]
    exact Or.inl (Or.inr member)
  refine ⟨?_, ?_, ?_⟩
  · refine ⟨List.nodup_cons.mpr ⟨absent, moved.1⟩, moved.2.1, ?_⟩
    intro token member
    rcases List.mem_cons.mp member with rfl | previous
    · exact unspent
    · exact moved.2.2 token previous
  · apply List.nodup_cons.mpr
    refine ⟨?_, valid.2.1⟩
    intro member
    apply fresh_name_not_supported store.controlSupport
    have old : (freshControlView owner store).identity ∈ store.controlSupport := by
      unfold ControlStore.controlSupport
      rw [List.map_append]
      exact List.mem_append_right _ (List.mem_append_left _ member)
    exact old
  · apply List.nodup_cons.mpr
    refine ⟨?_, valid.2.2⟩
    intro member
    apply fresh
    have old : (freshControlView owner store).authority ∈ store.custodySupport := by
      unfold ControlStore.custodySupport
      rw [List.map_append]
      exact List.mem_append_right _ (List.mem_append_left _ member)
    exact old

theorem created_control_acquires_its_own_future
    (partition : store.fields.active = before ++ selected ++ after) :
    let created := createControl use future owner before selected after store partition
    acquire created.view created.store = some ⟨
      ⟨⟨selected ++ activeFields (before ++ after), store.fields.retained,
        created.view.authority :: store.fields.spent⟩, store.controls, store.disposing⟩, future⟩ := by
  simp [createControl, acquire, takeControl, freshControlView, activeFields,
    exposeField, takeGrant, takeCapture]

theorem created_grant_is_not_an_old_alias
    (partition : store.fields.active = before ++ selected ++ after) :
    (createControl use future owner before selected after store partition).view.authority ∉ store.custodySupport :=
  fresh_name_not_supported _

end BoundaryV2.Generalized.UseScope
