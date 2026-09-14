import BoundaryV2.GeneralizedValueHandoff
import BoundaryV2.GeneralizedControlCorrespondence

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {Body Before After : List (TypeOf signature) → TypeOf signature → Type}
  {Future : Type}

structure PackageCreation (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (Body : List (TypeOf signature) → TypeOf signature → Type) (Future : Type) (content : TypeOf signature) where
  authority : Id .custody
  value : Value signature algebra Body (.package content)
  store : UseScope.ControlStore Future

/-- Packaging seals the actual operand fields under one fresh package grant.
Borrow lifetime checks belong to the enclosing scope/retention operation; this
local constructor does not extend any borrowed lifetime. -/
def createPackage (value : Value signature algebra Body content) (owner : Owner)
    (store : UseScope.ControlStore Future) (moved : UseScope.State)
    (_handoff : ValueHandoff value store.fields moved) (reserved : List (Id .custody)) :
    PackageCreation signature algebra Body Future content :=
  let token := UseScope.freshName (reserved ++ store.custodySupport)
  let packaged : Value signature algebra Body (.package content) := .package token owner value
  ⟨token, packaged, { store with fields := { moved with active := moved.active ++ [packaged.owningField] } }⟩

theorem created_package_authority_is_fresh (value : Value signature algebra Body content)
    (handoff : ValueHandoff value store.fields moved) :
    (createPackage value owner store moved handoff reserved).authority ∉ reserved ++ store.custodySupport :=
  UseScope.fresh_name_not_supported _

theorem created_package_inventory (value : Value signature algebra Body content)
    (handoff : ValueHandoff value store.fields moved) :
    ((createPackage value owner store moved handoff reserved).authority :: UseScope.inventory store.fields).Perm
      (UseScope.inventory (createPackage value owner store moved handoff reserved).store.fields) := by
  have transferred := (handoff.conserves_owners.1).cons (createPackage value owner store moved handoff reserved).authority
  apply transferred.trans
  simp only [createPackage, UseScope.inventory, Value.owningField, UseScope.Field.tokens, UseScope.tokens,
    UseScope.tokens_append, List.append_nil, List.nil_append, List.cons_append, List.append_assoc]
  simpa only [createPackage, List.append_assoc, List.cons_append] using
    (List.perm_append_comm
      (l₁ := (createPackage value owner store moved handoff reserved).authority :: value.owningField.tokens)
      (l₂ := UseScope.tokens moved.active)).append_right (UseScope.tokens moved.retained)

theorem created_package_preserves_ownership (value : Value signature algebra Body content)
    (valid : UseScope.ControlStore.Valid store) (handoff : ValueHandoff value store.fields moved) :
    UseScope.ControlStore.Valid (createPackage value owner store moved handoff reserved).store := by
  let created := createPackage value owner store moved handoff reserved
  have fresh := created_package_authority_is_fresh (owner := owner) (reserved := reserved) value handoff
  have absent : created.authority ∉ UseScope.inventory store.fields := fun member =>
    fresh (List.mem_append_right _ (UseScope.inventory_is_supported store member))
  have unspent : created.authority ∉ store.fields.spent := by
    intro member
    apply fresh
    apply List.mem_append_right
    simp only [UseScope.ControlStore.custodySupport, List.mem_append]
    exact Or.inl (Or.inr member)
  have permuted := created_package_inventory (owner := owner) (reserved := reserved) value handoff
  have sameSpent := handoff.conserves_owners.2
  refine ⟨⟨permuted.nodup_iff.mp (List.nodup_cons.mpr ⟨absent, valid.1.1⟩), ?_, ?_⟩, valid.2⟩
  · simpa only [created, createPackage, sameSpent] using valid.1.2.1
  · intro token member
    change token ∉ moved.spent
    rw [sameSpent]
    rcases List.mem_cons.mp (permuted.mem_iff.mpr member) with rfl | old
    · exact unspent
    · exact valid.1.2.2 token old

theorem created_package_preserves_external_owners (value : Value signature algebra Body content)
    (handoff : ValueHandoff value store.fields moved) (external : List (Id .custody))
    (unique : (UseScope.inventory store.fields ++ external).Nodup)
    (supported : ∀ token ∈ external, token ∈ reserved) :
    (UseScope.inventory (createPackage value owner store moved handoff reserved).store.fields ++ external).Nodup := by
  have fresh := created_package_authority_is_fresh (owner := owner) (reserved := reserved) value handoff
  have absent : (createPackage value owner store moved handoff reserved).authority ∉
      UseScope.inventory store.fields ++ external := by
    intro member
    rcases List.mem_append.mp member with internal | outside
    · exact fresh (List.mem_append_right _ (UseScope.inventory_is_supported store internal))
    · exact fresh (List.mem_append_left _ (supported _ outside))
  have prepared := List.nodup_cons.mpr ⟨absent, unique⟩
  exact ((created_package_inventory (owner := owner) (reserved := reserved) value handoff).append_right external).nodup_iff.mp prepared

/-- Unpacking consumes the package grant and restores its actual inline field.
A view of a consumed package cannot unpack the same grant again. -/
inductive PackageHandoff (value : Value signature algebra Body content) (token : Id .custody) (owner : Owner) :
    UseScope.State → UseScope.State → Prop where
  | unpack (before after retained : List UseScope.Field) (spent : List (Id .custody)) :
      PackageHandoff value token owner
        ⟨before ++ (Value.package token owner value).owningField :: after, retained, spent⟩
        ⟨before ++ value.owningField :: after, retained, token :: spent⟩
  | unpackFlat (before after retained : List UseScope.Field) (spent : List (Id .custody)) :
      PackageHandoff value token owner
        ⟨before ++ .owned token owner :: .package [value.owningField] :: after, retained, spent⟩
        ⟨before ++ value.owningField :: after, retained, token :: spent⟩

theorem PackageHandoff.preserves_ownership (handoff : PackageHandoff value token owner before after)
    (valid : UseScope.Valid before) : UseScope.Valid after := by
  cases handoff with
  | unpack leftFields rightFields retained spent | unpackFlat leftFields rightFields retained spent =>
    have prepared : UseScope.Valid ⟨.owned token owner :: (leftFields ++ value.owningField :: rightFields), retained, spent⟩ := by
      apply UseScope.valid_of_inventory _
        ⟨.owned token owner :: (leftFields ++ value.owningField :: rightFields), retained, spent⟩ valid ?_ rfl
      simp only [UseScope.inventory, UseScope.tokens_append, UseScope.tokens, UseScope.Field.tokens,
        Value.owningField, List.append_nil, List.nil_append, List.cons_append, List.append_assoc]
      exact List.perm_middle
    exact UseScope.consume_preserves_ownership token owner _ retained spent prepared

theorem PackageHandoff.grant_was_present (handoff : PackageHandoff value token owner before after) :
    token ∈ UseScope.inventory before := by
  cases handoff <;>
    simp [UseScope.inventory, UseScope.tokens_append, UseScope.tokens, Value.owningField, UseScope.Field.tokens]

theorem PackageHandoff.cannot_repeat (handoff : PackageHandoff value token owner before after)
    (valid : UseScope.Valid before) : ¬ PackageHandoff value token owner after later := by
  intro repeated
  have afterValid := handoff.preserves_ownership valid
  cases handoff <;> exact afterValid.2.2 token repeated.grant_was_present List.mem_cons_self

theorem PackageHandoff.spends_outer_grant (handoff : PackageHandoff value token owner before after) :
    after.spent = token :: before.spent := by cases handoff <;> rfl

theorem PackageHandoff.map (transform : ∀ context type, Before context type → After context type)
    (handoff : PackageHandoff (value : Value signature algebra Before content) token owner before after) :
    PackageHandoff (value.map transform) token owner before after := by
  cases handoff with
  | unpack leftFields rightFields retained spent =>
    simpa only [Value.owningField, Value.map_preserves_owning_fields] using
      PackageHandoff.unpack (value := value.map transform) (token := token) (owner := owner) leftFields rightFields retained spent
  | unpackFlat leftFields rightFields retained spent =>
    simpa only [Value.map_preserves_owning_fields] using
      PackageHandoff.unpackFlat (value := value.map transform) (token := token) (owner := owner) leftFields rightFields retained spent

theorem package_creation_corresponds
    {SourceFuture TargetFuture : Type} (related : SourceFuture → TargetFuture → Prop)
    (transform : ∀ context type, Before context type → After context type)
    (value : Value signature algebra Before content) (owner : Owner) (reserved : List (Id .custody))
    {source : UseScope.ControlStore SourceFuture} {target : UseScope.ControlStore TargetFuture}
    (stores : UseScope.ControlStore.Related related source target)
    (sourceHandoff : ValueHandoff value source.fields moved)
    (targetHandoff : ValueHandoff (value.map transform) target.fields moved) :
    let left := createPackage value owner source moved sourceHandoff reserved
    let right := createPackage (value.map transform) owner target moved targetHandoff reserved
    left.authority = right.authority ∧ right.value = left.value.map transform ∧
      UseScope.ControlStore.Related related left.store right.store := by
  have fresh := congrArg UseScope.ControlView.authority (UseScope.related_fresh_views related stores owner ⟨[], reserved⟩)
  change UseScope.freshName (reserved ++ source.custodySupport) = UseScope.freshName (reserved ++ target.custodySupport) at fresh
  refine ⟨fresh, ?_, ?_⟩
  · simp only [createPackage, Value.map, fresh]
  · refine ⟨?_, stores.controls, stores.disposing⟩
    simp only [createPackage, Value.owningField, Value.map_preserves_owning_fields, fresh]

end BoundaryV2.Generalized
