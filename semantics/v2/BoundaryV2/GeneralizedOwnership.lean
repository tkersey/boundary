import BoundaryV2.GeneralizedTypes

namespace BoundaryV2.Generalized.UseScope

/-- Physical owning fields are explicit. An alias carries a reference but no
second grant. Code environments may contain aliases to these fields. -/
inductive Field where
  | owned : Id .custody → Owner → Field
  | alias : Id .custody → Field
  | borrowed : Id .scope → Field
  | group : List Field → Field
  | closure : List Field → Field
  | continuation : Id .control → List Field → Field
  | package : List Field → Field
  | cleanup : Id .obligation → List Field → Field

mutual
  def Field.tokens : Field → List (Id .custody)
    | .owned token _ => [token]
    | .alias _ | .borrowed _ => []
    | .group fields | .closure fields | .continuation _ fields | .package fields | .cleanup _ fields => tokens fields

  def tokens : List Field → List (Id .custody)
    | [] => []
    | field :: rest => field.tokens ++ tokens rest
end

theorem tokens_append (first second : List Field) : tokens (first ++ second) = tokens first ++ tokens second := by
  induction first with
  | nil => rfl
  | cons field rest induction => simp [tokens, induction, List.append_assoc]

structure State where
  active : List Field
  retained : List Field
  spent : List (Id .custody)

def inventory (state : State) := tokens state.active ++ tokens state.retained

def Valid (state : State) : Prop :=
  (inventory state).Nodup ∧ state.spent.Nodup ∧ ∀ token ∈ inventory state, token ∉ state.spent

/-- Move the selected owning fields from the active boundary into one retained
continuation. This transfers the fields themselves, preserving multiplicity. -/
def capture (before selected after : List Field) (retained : List Field) (spent : List (Id .custody)) (id : Id .control) : State :=
  ⟨before ++ after, .continuation id selected :: retained, spent⟩

theorem capture_inventory (before selected after retained : List Field) (spent : List (Id .custody)) (id : Id .control) :
    (inventory ⟨before ++ selected ++ after, retained, spent⟩).Perm
      (inventory (capture before selected after retained spent id)) := by
  simp only [inventory, capture, tokens_append, tokens, Field.tokens, List.append_assoc]
  simpa only [List.append_assoc] using List.Perm.append_left (tokens before)
    ((List.perm_append_comm (l₁ := tokens selected) (l₂ := tokens after)).append_right (tokens retained))

theorem valid_of_inventory (before after : State) (valid : Valid before)
    (same : (inventory before).Perm (inventory after)) (spent : after.spent = before.spent) : Valid after := by
  refine ⟨same.nodup_iff.mp valid.1, spent ▸ valid.2.1, ?_⟩
  intro token member
  rw [spent]
  exact valid.2.2 token (same.mem_iff.mpr member)

theorem capture_preserves_ownership (before selected after retained : List Field) (spent : List (Id .custody)) (id : Id .control)
    (valid : Valid ⟨before ++ selected ++ after, retained, spent⟩) : Valid (capture before selected after retained spent id) :=
  valid_of_inventory _ _ valid (capture_inventory _ _ _ _ _ _) rfl

def activate (active saved retained : List Field) (spent : List (Id .custody)) : State :=
  ⟨saved ++ active, retained, spent⟩

theorem activate_preserves_ownership (active saved retained : List Field) (spent : List (Id .custody)) (id : Id .control)
    (valid : Valid ⟨active, .continuation id saved :: retained, spent⟩) : Valid (activate active saved retained spent) := by
  apply valid_of_inventory _ (activate active saved retained spent) valid ?_ rfl
  simp only [inventory, activate, tokens, Field.tokens, tokens_append, List.append_assoc]
  simpa only [List.append_assoc] using
    (List.perm_append_comm (l₁ := tokens active) (l₂ := tokens saved)).append_right (tokens retained)

def package (before selected after retained : List Field) (spent : List (Id .custody)) : State :=
  ⟨before ++ after, .package selected :: retained, spent⟩

theorem package_preserves_ownership (before selected after retained : List Field) (spent : List (Id .custody))
    (valid : Valid ⟨before ++ selected ++ after, retained, spent⟩) : Valid (package before selected after retained spent) :=
  valid_of_inventory _ _ valid (capture_inventory before selected after retained spent ⟨0⟩) rfl

/-- Taking one-shot authority removes its physical owning occurrence before
any future is entered. The spent name remains unavailable for reuse. -/
def consume (token : Id .custody) (rest retained : List Field) (spent : List (Id .custody)) : State :=
  ⟨rest, retained, token :: spent⟩

theorem consume_preserves_ownership (token : Id .custody) (owner : Owner) (rest retained : List Field) (spent : List (Id .custody))
    (valid : Valid ⟨.owned token owner :: rest, retained, spent⟩) : Valid (consume token rest retained spent) := by
  have formed : (token :: (tokens rest ++ tokens retained)).Nodup := valid.1
  have absent : token ∉ spent := valid.2.2 token (by simp [inventory, tokens, Field.tokens])
  refine ⟨(List.nodup_cons.mp formed).2, List.nodup_cons.mpr ⟨absent, valid.2.1⟩, ?_⟩
  intro other member
  simp only [consume, List.mem_cons, not_or]
  refine ⟨?_, valid.2.2 other (by simp only [inventory, tokens, Field.tokens, List.cons_append]; exact List.mem_cons_of_mem _ member)⟩
  intro equal
  subst other
  exact (List.nodup_cons.mp formed).1 member

theorem consumed_authority_is_not_live (token : Id .custody) (rest retained : List Field) (spent : List (Id .custody))
    (valid : Valid (consume token rest retained spent)) : token ∉ inventory (consume token rest retained spent) := by
  intro live
  exact valid.2.2 token live (List.mem_cons_self)

theorem duplicated_physical_owner_is_invalid (token : Id .custody) (first second : Owner) (rest retained : List Field)
    (spent : List (Id .custody)) : ¬ Valid ⟨.owned token first :: .owned token second :: rest, retained, spent⟩ := by
  intro valid
  have unique := valid.1
  simp [inventory, tokens, Field.tokens, List.nodup_cons] at unique

end BoundaryV2.Generalized.UseScope
