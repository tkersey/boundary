import BoundaryV2.GeneralizedComputationHandoff
import BoundaryV2.GeneralizedControlCorrespondence
import BoundaryV2.GeneralizedCellReservations

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {Body Before After : List (TypeOf signature) → TypeOf signature → Type}
  {Future : Type}
  {parameters capturedTypes : List (TypeOf signature)} {result : TypeOf signature}
  {body : Body (parameters ++ capturedTypes) result}

structure ComputationCreation (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (Body : List (TypeOf signature) → TypeOf signature → Type) (Future : Type)
    (use : UseScope.OneShotUse) (parameters : List (TypeOf signature)) (result : TypeOf signature) where
  authority : Id .custody
  value : Value signature algebra Body (.computation use.type parameters result)
  store : UseScope.ControlStore Future

/-- The caller identifies actual capture fields. Creation moves those fields
into the new closure and mints one fresh grant. External support includes cells
and any other references maintained by the enclosing scope owner. -/
def createOwnedComputation (use : UseScope.OneShotUse) (body : Body (parameters ++ capturedTypes) result)
    (captured : Environment signature algebra Body capturedTypes) (owner : Owner)
    (before after : List UseScope.Field) (store : UseScope.ControlStore Future)
    (_partition : store.fields.active = before ++ captured.owningFields ++ after)
    (reserved : List (Id .custody)) : ComputationCreation signature algebra Body Future use parameters result :=
  let token := UseScope.freshName (reserved ++ store.custodySupport)
  let closure : Value signature algebra Body (.computation use.type parameters result) := .closure body captured (some (token, owner))
  ⟨token, closure, { store with fields := ⟨before ++ closure.owningField :: after, store.fields.retained, store.fields.spent⟩ }⟩

theorem created_computation_authority_is_fresh
    (partition : store.fields.active = before ++ (captured : Environment signature algebra Body capturedTypes).owningFields ++ after) :
    (createOwnedComputation use body captured owner before after store partition reserved).authority ∉ reserved ++ store.custodySupport :=
  UseScope.fresh_name_not_supported _

theorem created_computation_inventory
    (partition : store.fields.active = before ++ (captured : Environment signature algebra Body capturedTypes).owningFields ++ after) :
    ((createOwnedComputation use body captured owner before after store partition reserved).authority :: UseScope.inventory store.fields).Perm
      (UseScope.inventory (createOwnedComputation use body captured owner before after store partition reserved).store.fields) := by
  simp only [createOwnedComputation, UseScope.inventory, partition, Value.owningField, authorityFields,
    Option.toList_some, List.map_cons, List.map_nil, List.cons_append, List.nil_append,
    UseScope.tokens_append, UseScope.tokens, UseScope.Field.tokens, List.append_nil, List.append_assoc]
  exact List.perm_middle.symm

theorem created_computation_preserves_ownership
    (valid : UseScope.ControlStore.Valid store)
    (partition : store.fields.active = before ++ (captured : Environment signature algebra Body capturedTypes).owningFields ++ after) :
    UseScope.ControlStore.Valid (createOwnedComputation use body captured owner before after store partition reserved).store := by
  let created := createOwnedComputation use body captured owner before after store partition reserved
  have fresh := created_computation_authority_is_fresh (use := use) (body := body) (owner := owner) (reserved := reserved) partition
  have absent : created.authority ∉ UseScope.inventory store.fields := by
    intro member
    exact fresh (List.mem_append_right _ (UseScope.inventory_is_supported store member))
  have unspent : created.authority ∉ store.fields.spent := by
    intro member
    apply fresh
    apply List.mem_append_right
    simp only [UseScope.ControlStore.custodySupport, List.mem_append]
    exact Or.inl (Or.inr member)
  have permuted := created_computation_inventory (use := use) (body := body) (owner := owner) (reserved := reserved) partition
  refine ⟨⟨permuted.nodup_iff.mp (List.nodup_cons.mpr ⟨absent, valid.1.1⟩), valid.1.2.1, ?_⟩, valid.2⟩
  intro token member
  have original := permuted.mem_iff.mpr member
  rcases List.mem_cons.mp original with rfl | existing
  · exact unspent
  · exact valid.1.2.2 token existing

/-- Entering a freshly created closure consumes its new grant and restores
the captured physical fields. Captured values and unrelated owners are retained. -/
theorem created_computation_can_enter
    (partition : store.fields.active = before ++ (captured : Environment signature algebra Body capturedTypes).owningFields ++ after) :
    ComputationHandoff captured use.type
      (some ((createOwnedComputation use body captured owner before after store partition reserved).authority, owner))
      (createOwnedComputation use body captured owner before after store partition reserved).store.fields
      ⟨before ++ captured.owningFields ++ after, store.fields.retained,
        (createOwnedComputation use body captured owner before after store partition reserved).authority :: store.fields.spent⟩ :=
  ComputationHandoff.owned use _ owner before after store.fields.retained store.fields.spent

theorem creation_preserves_code_and_capture_order
    (partition : store.fields.active = before ++ (captured : Environment signature algebra Body capturedTypes).owningFields ++ after) :
    (createOwnedComputation use body captured owner before after store partition reserved).value =
      .closure body captured (some ((createOwnedComputation use body captured owner before after store partition reserved).authority, owner)) := rfl

theorem created_computation_preserves_combined_inventory
    (partition : store.fields.active = before ++ (captured : Environment signature algebra Body capturedTypes).owningFields ++ after)
    (external : List (Id .custody)) (unique : (UseScope.inventory store.fields ++ external).Nodup)
    (supported : ∀ token ∈ external, token ∈ reserved) :
    (UseScope.inventory (createOwnedComputation use body captured owner before after store partition reserved).store.fields ++ external).Nodup := by
  have fresh := created_computation_authority_is_fresh (use := use) (body := body) (owner := owner) (reserved := reserved) partition
  have absent : (createOwnedComputation use body captured owner before after store partition reserved).authority ∉
      UseScope.inventory store.fields ++ external := by
    intro member
    rcases List.mem_append.mp member with internal | outside
    · exact fresh (List.mem_append_right _ (UseScope.inventory_is_supported store internal))
    · exact fresh (List.mem_append_left _ (supported _ outside))
  have prepared := List.nodup_cons.mpr ⟨absent, unique⟩
  exact ((created_computation_inventory (use := use) (body := body) (owner := owner) (reserved := reserved) partition).append_right external).nodup_iff.mp prepared

/-- Construction cannot hide duplicated captures by sealing them in a closure. -/
theorem created_computation_ownership_iff
    (partition : store.fields.active = before ++ (captured : Environment signature algebra Body capturedTypes).owningFields ++ after) :
    UseScope.ControlStore.Valid (createOwnedComputation use body captured owner before after store partition reserved).store ↔
      UseScope.ControlStore.Valid store := by
  constructor
  · intro valid
    have permuted := created_computation_inventory (use := use) (body := body) (owner := owner) (reserved := reserved) partition
    refine ⟨⟨(List.nodup_cons.mp (permuted.nodup_iff.mpr valid.1.1)).2, valid.1.2.1, ?_⟩, valid.2⟩
    intro token member
    exact valid.1.2.2 token (permuted.mem_iff.mp (List.mem_cons_of_mem _ member))
  · exact fun valid => created_computation_preserves_ownership valid partition

theorem created_computation_avoids_cell_owners
    (partition : store.fields.active = before ++ (captured : Environment signature algebra Body capturedTypes).owningFields ++ after)
    (cells : Cells signature algebra Body) :
    (createOwnedComputation use body captured owner before after store partition cells.reservations.custody).authority ∉
      UseScope.tokens cells.fields := by
  intro member
  exact created_computation_authority_is_fresh partition
    (List.mem_append_left _ (cells.owning_tokens_reserved member))

theorem created_computation_entry_cannot_repeat
    (valid : UseScope.ControlStore.Valid store)
    (partition : store.fields.active = before ++ (captured : Environment signature algebra Body capturedTypes).owningFields ++ after)
    (later : UseScope.State) :
    let created := createOwnedComputation use body captured owner before after store partition reserved
    ¬ ComputationHandoff captured use.type (some (created.authority, owner))
      ⟨before ++ captured.owningFields ++ after, store.fields.retained, created.authority :: store.fields.spent⟩ later := by
  exact (created_computation_can_enter partition).owned_entry_cannot_repeat
    (created_computation_preserves_ownership valid partition).1

theorem owned_computation_creation_corresponds
    {SourceFuture TargetFuture : Type} (related : SourceFuture → TargetFuture → Prop)
    (transform : ∀ context type, Before context type → After context type)
    (use : UseScope.OneShotUse) (body : Before (parameters ++ capturedTypes) result)
    (captured : Environment signature algebra Before capturedTypes) (owner : Owner)
    (before after : List UseScope.Field) (reserved : List (Id .custody))
    {source : UseScope.ControlStore SourceFuture} {target : UseScope.ControlStore TargetFuture}
    (stores : UseScope.ControlStore.Related related source target)
    (sourcePartition : source.fields.active = before ++ captured.owningFields ++ after)
    (targetPartition : target.fields.active = before ++ (captured.map transform).owningFields ++ after) :
    let sourceCreated := createOwnedComputation use body captured owner before after source sourcePartition reserved
    let targetCreated := createOwnedComputation use (transform _ _ body) (captured.map transform) owner before after target targetPartition reserved
    sourceCreated.authority = targetCreated.authority ∧ targetCreated.value = sourceCreated.value.map transform ∧
      UseScope.ControlStore.Related related sourceCreated.store targetCreated.store := by
  have fresh := congrArg UseScope.ControlView.authority (UseScope.related_fresh_views related stores owner ⟨[], reserved⟩)
  change UseScope.freshName (reserved ++ source.custodySupport) = UseScope.freshName (reserved ++ target.custodySupport) at fresh
  refine ⟨fresh, ?_, ?_⟩
  · simp only [createOwnedComputation, Value.map, fresh]
  · refine ⟨?_, stores.controls, stores.disposing⟩
    simp only [createOwnedComputation, Value.owningField, Environment.map_preserves_owning_fields, fresh, stores.fields]

end BoundaryV2.Generalized
