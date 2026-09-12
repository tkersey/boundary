import BoundaryV2.GeneralizedControlStore
import BoundaryV2.GeneralizedFreshNames

namespace BoundaryV2.Generalized.UseScope

/-- Relocation gives each logical namespace one consistent map. Owner labels
are explicit too; operations below pass those labels through unchanged except
for this map. Lifetime/owner-role coherence is a separate scope obligation. -/
structure Relocation where
  name : ∀ domain, Id domain → Id domain
  owner : Owner → Owner

mutual
  def Field.relocate (relocation : Relocation) : Field → Field
    | .owned token owner => .owned (relocation.name .custody token) (relocation.owner owner)
    | .alias token => .alias (relocation.name .custody token)
    | .borrowed scope => .borrowed (relocation.name .scope scope)
    | .group fields => .group (relocateFields relocation fields)
    | .closure fields => .closure (relocateFields relocation fields)
    | .continuation identity fields => .continuation (relocation.name .control identity) (relocateFields relocation fields)
    | .package fields => .package (relocateFields relocation fields)
    | .cleanup identity fields => .cleanup (relocation.name .obligation identity) (relocateFields relocation fields)

  def relocateFields (relocation : Relocation) : List Field → List Field
    | [] => []
    | field :: rest => field.relocate relocation :: relocateFields relocation rest
end

theorem relocate_fields_append (relocation : Relocation) (first second : List Field) :
    relocateFields relocation (first ++ second) = relocateFields relocation first ++ relocateFields relocation second := by
  induction first with
  | nil => rfl
  | cons field rest induction => simp only [List.cons_append, relocateFields, induction]

mutual
  theorem relocate_field_tokens (relocation : Relocation) (field : Field) :
      (field.relocate relocation).tokens = field.tokens.map (relocation.name .custody) := by
    cases field <;> simp only [Field.relocate, Field.tokens, List.map_cons, List.map_nil]
    all_goals exact relocate_fields_tokens relocation _
  termination_by sizeOf field

  theorem relocate_fields_tokens (relocation : Relocation) (fields : List Field) :
      tokens (relocateFields relocation fields) = (tokens fields).map (relocation.name .custody) := by
    cases fields with
    | nil => rfl
    | cons field rest => simp only [relocateFields, tokens, List.map_append,
        relocate_field_tokens relocation field, relocate_fields_tokens relocation rest]
  termination_by sizeOf fields
end

def State.relocate (relocation : Relocation) (state : State) : State :=
  ⟨relocateFields relocation state.active, relocateFields relocation state.retained, state.spent.map (relocation.name .custody)⟩

theorem relocate_inventory (relocation : Relocation) (state : State) :
    inventory (state.relocate relocation) = (inventory state).map (relocation.name .custody) := by
  simp only [inventory, State.relocate, relocate_fields_tokens, List.map_append]

private theorem nodup_map_on {First Second : Type} {values : List First}
    (function : First → Second) (unique : values.Nodup)
    (injective : ∀ first ∈ values, ∀ second ∈ values, function first = function second → first = second) :
    (values.map function).Nodup := by
  induction values with
  | nil => exact .nil
  | cons first rest induction =>
    rw [List.nodup_cons] at unique
    apply List.nodup_cons.mpr
    constructor
    · intro repeated
      obtain ⟨second, member, equal⟩ := List.mem_map.mp repeated
      have same := injective first (by simp) second (by simp [member]) equal.symm
      exact unique.1 (same ▸ member)
    · exact induction unique.2 (fun first firstAt second secondAt equal =>
        injective first (by simp [firstAt]) second (by simp [secondAt]) equal)

/-- Injectivity is checked on this state's live and spent support. No global
injectivity assumption over unused natural numbers is needed. -/
theorem relocation_preserves_ownership (relocation : Relocation) (state : State) (valid : Valid state)
    (injective : ∀ first ∈ inventory state ++ state.spent, ∀ second ∈ inventory state ++ state.spent,
      relocation.name .custody first = relocation.name .custody second → first = second) : Valid (state.relocate relocation) := by
  constructor
  · rw [relocate_inventory]
    exact nodup_map_on _ valid.1 (fun first firstAt second secondAt equal =>
      injective first (List.mem_append_left _ firstAt) second (List.mem_append_left _ secondAt) equal)
  · constructor
    · exact nodup_map_on _ valid.2.1 (fun first firstAt second secondAt equal =>
        injective first (List.mem_append_right _ firstAt) second (List.mem_append_right _ secondAt) equal)
    · intro token live spent
      rw [relocate_inventory] at live
      obtain ⟨original, originalLive, rfl⟩ := List.mem_map.mp live
      obtain ⟨used, usedAt, same⟩ := List.mem_map.mp spent
      have equal := injective used (List.mem_append_right _ usedAt) original (List.mem_append_left _ originalLive) same
      exact valid.2.2 original originalLive (equal ▸ usedAt)

theorem relocation_commutes_with_capture (relocation : Relocation) (before selected after retained : List Field)
    (spent : List (Id .custody)) (identity : Id .control) :
    (capture before selected after retained spent identity).relocate relocation =
      capture (relocateFields relocation before) (relocateFields relocation selected) (relocateFields relocation after)
        (relocateFields relocation retained) (spent.map (relocation.name .custody)) (relocation.name .control identity) := by
  simp only [capture, State.relocate, relocate_fields_append, relocateFields, Field.relocate]

theorem relocation_commutes_with_activation (relocation : Relocation) (active saved retained : List Field)
    (spent : List (Id .custody)) :
    (activate active saved retained spent).relocate relocation =
      activate (relocateFields relocation active) (relocateFields relocation saved) (relocateFields relocation retained)
        (spent.map (relocation.name .custody)) := by
  simp only [activate, State.relocate, relocate_fields_append]

theorem relocation_commutes_with_package (relocation : Relocation) (before selected after retained : List Field)
    (spent : List (Id .custody)) :
    (package before selected after retained spent).relocate relocation =
      package (relocateFields relocation before) (relocateFields relocation selected) (relocateFields relocation after)
        (relocateFields relocation retained) (spent.map (relocation.name .custody)) := by
  simp only [package, State.relocate, relocate_fields_append, relocateFields, Field.relocate]

theorem relocation_commutes_with_consumption (relocation : Relocation) (token : Id .custody)
    (rest retained : List Field) (spent : List (Id .custody)) :
    (consume token rest retained spent).relocate relocation =
      consume (relocation.name .custody token) (relocateFields relocation rest) (relocateFields relocation retained)
        (spent.map (relocation.name .custody)) := rfl

def freshRelocation (support locals : ∀ domain, List (Id domain)) (owner : Owner → Owner) : Relocation :=
  ⟨fun domain => FreshNames.rename (locals domain) (FreshNames.bound (support domain)), owner⟩

theorem fresh_relocation_preserves_ownership (support locals : ∀ domain, List (Id domain)) (owner : Owner → Owner)
    (state : State) (valid : Valid state)
    (supported : ∀ token ∈ inventory state ++ state.spent, token ∈ support .custody) :
    Valid (state.relocate (freshRelocation support locals owner)) := by
  apply relocation_preserves_ownership _ state valid
  intro first firstAt second secondAt same
  exact FreshNames.injective_on_support (supported first firstAt) (supported second secondAt) same

end BoundaryV2.Generalized.UseScope
