import BoundaryV2.GeneralizedCellLowering
import BoundaryV2.GeneralizedControlStore

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {Body Before After : List (TypeOf signature) → TypeOf signature → Type}

/-- Entering a computation opens its actual captured fields. Owned computation
authority is consumed first; shared entry requires copyable captures. Code
admissibility and borrowed lifetime checks retain their separate obligations. -/
inductive ComputationHandoff (captured : Environment signature algebra Body types) :
    Use → Option (Id .custody × Owner) → UseScope.State → UseScope.State → Prop where
  | shared (use : Use) : use = .reusable ∨ use = .multi → captured.copyable = true →
      ComputationHandoff captured use none fields fields
  | owned (use : UseScope.OneShotUse) (token : Id .custody) (owner : Owner)
      (before after retained : List UseScope.Field) (spent : List (Id .custody)) :
      ComputationHandoff captured use.type (some (token, owner))
        ⟨before ++ .group [.owned token owner, .closure captured.owningFields] :: after, retained, spent⟩
        ⟨before ++ captured.owningFields ++ after, retained, token :: spent⟩
  | ownedFlat (use : UseScope.OneShotUse) (token : Id .custody) (owner : Owner)
      (before after retained : List UseScope.Field) (spent : List (Id .custody)) :
      ComputationHandoff captured use.type (some (token, owner))
        ⟨before ++ .owned token owner :: .closure captured.owningFields :: after, retained, spent⟩
        ⟨before ++ captured.owningFields ++ after, retained, token :: spent⟩

theorem ComputationHandoff.preserves_ownership
    (handoff : ComputationHandoff captured use authority before after) (valid : UseScope.Valid before) : UseScope.Valid after := by
  cases handoff with
  | shared use permitted copyable => exact valid
  | owned use token owner before after retained spent | ownedFlat use token owner before after retained spent =>
    have arranged : UseScope.Valid ⟨.owned token owner :: (before ++ captured.owningFields ++ after), retained, spent⟩ := by
      apply UseScope.valid_of_inventory _ ⟨.owned token owner :: (before ++ captured.owningFields ++ after), retained, spent⟩ valid ?_ rfl
      simp only [UseScope.inventory, UseScope.tokens_append, UseScope.tokens, UseScope.Field.tokens,
        List.nil_append, List.append_nil, List.append_assoc, List.cons_append]
      exact List.perm_middle
    exact UseScope.consume_preserves_ownership token owner _ retained spent arranged

theorem ComputationHandoff.owner_consumed_before_entry
    (handoff : ComputationHandoff captured use (some (token, owner)) before after)
    (valid : UseScope.Valid before) :
    token ∉ UseScope.inventory after ∧ after.spent = token :: before.spent := by
  have afterValid := handoff.preserves_ownership valid
  cases handoff with
  | owned use token owner before after retained spent | ownedFlat use token owner before after retained spent =>
    exact ⟨fun member => afterValid.2.2 token member List.mem_cons_self, rfl⟩

theorem ComputationHandoff.owner_was_present
    (handoff : ComputationHandoff captured use (some (token, owner)) before after) : token ∈ UseScope.inventory before := by
  cases handoff with
  | owned use token owner before after retained spent | ownedFlat use token owner before after retained spent =>
    simp [UseScope.inventory, UseScope.tokens_append, UseScope.tokens, UseScope.Field.tokens]

theorem ComputationHandoff.owned_entry_cannot_repeat
    (handoff : ComputationHandoff captured use (some (token, owner)) before after)
    (valid : UseScope.Valid before) : ¬ ComputationHandoff captured use (some (token, owner)) after later := by
  intro repeated
  exact (handoff.owner_consumed_before_entry valid).1 repeated.owner_was_present

theorem ComputationHandoff.unowned_is_shared (handoff : ComputationHandoff captured use none before after) :
    use = .reusable ∨ use = .multi := by
  cases handoff with
  | shared mode permitted copyable => exact permitted

theorem ComputationHandoff.preserves_spent (handoff : ComputationHandoff captured use authority before after) :
    ∀ token ∈ before.spent, token ∈ after.spent := by
  cases handoff with
  | shared => exact fun _ member => member
  | owned | ownedFlat => exact fun _ member => List.mem_cons_of_mem _ member

theorem ComputationHandoff.unowned_captures_copyable (handoff : ComputationHandoff captured use none before after) :
    captured.copyable = true := by
  cases handoff with
  | shared mode permitted copyable => exact copyable

theorem ComputationHandoff.missing_owned_authority_rejects
    (use : UseScope.OneShotUse) : ¬ ComputationHandoff captured use.type none before after := by
  intro handoff
  have permitted := handoff.unowned_is_shared
  cases use <;> simp [UseScope.OneShotUse.type] at permitted

theorem ComputationHandoff.map (transform : ∀ context type, Before context type → After context type)
    (handoff : ComputationHandoff (captured : Environment signature algebra Before types) use authority before after) :
    ComputationHandoff (captured.map transform) use authority before after := by
  cases handoff with
  | shared use permitted copyable =>
    exact .shared use permitted (by simpa only [Environment.copyable_map] using copyable)
  | owned use token owner before after retained spent =>
    simpa only [Environment.map_preserves_owning_fields] using
      ComputationHandoff.owned (captured := captured.map transform) use token owner before after retained spent
  | ownedFlat use token owner before after retained spent =>
    simpa only [Environment.map_preserves_owning_fields] using
      ComputationHandoff.ownedFlat (captured := captured.map transform) use token owner before after retained spent

end BoundaryV2.Generalized
