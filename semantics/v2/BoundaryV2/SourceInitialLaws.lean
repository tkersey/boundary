import BoundaryV2.SourceCapture

namespace BoundaryV2.Profile.Source.Machine

/-- External trees cannot hide runtime handles or custody tokens in recursive
products, variants, or containers. This is derived from the actual admission
function, not a producer-supplied externality flag. -/
theorem admitted_tree_has_no_runtime_handles (schemas : List (Schema .source)) (value : SemanticValue)
    (admitted : Profile.Value.treeValid schemas value = true) :
    valueReferences value = [] ∧ ownedTokens value = [] := by
  cases value with
  | scalar _ _ => simp [valueReferences, ownedTokens]
  | blob _ _ => simp [valueReferences, ownedTokens]
  | reference _ _ _ => simp [Profile.Value.treeValid] at admitted
  | product schema fields =>
    simp only [Profile.Value.treeValid] at admitted
    split at admitted
    · have checked := (Bool.and_eq_true_iff.mp admitted).2
      have children : ∀ child ∈ fields, valueReferences child = [] ∧ ownedTokens child = [] := by
        intro child member
        have valid := List.all_eq_true.mp checked ⟨child, member⟩ (List.mem_attach ..)
        exact admitted_tree_has_no_runtime_handles schemas child valid
      simp only [valueReferences, ownedTokens, List.flatMap_eq_nil_iff]
      exact ⟨fun child member => (children child member).1, fun child member => (children child member).2⟩
    · contradiction
  | sequence schema fields =>
    simp only [Profile.Value.treeValid] at admitted
    split at admitted
    · have checked := (Bool.and_eq_true_iff.mp admitted).2
      have children : ∀ child ∈ fields, valueReferences child = [] ∧ ownedTokens child = [] := by
        intro child member
        have valid := (Bool.and_eq_true_iff.mp (List.all_eq_true.mp checked ⟨child, member⟩ (List.mem_attach ..))).2
        exact admitted_tree_has_no_runtime_handles schemas child valid
      simp only [valueReferences, ownedTokens, List.flatMap_eq_nil_iff]
      exact ⟨fun child member => (children child member).1, fun child member => (children child member).2⟩
    · contradiction
  | variant schema tag payload =>
    simp only [Profile.Value.treeValid] at admitted
    split at admitted
    · simpa only [valueReferences, ownedTokens] using
        admitted_tree_has_no_runtime_handles schemas payload (Bool.and_eq_true_iff.mp admitted).2
    · contradiction
termination_by sizeOf value
decreasing_by
  all_goals subst value
  all_goals simp_wf
  all_goals first | omega | exact Nat.lt_trans (List.sizeOf_lt_of_mem member) (by omega)

theorem external_value_has_no_runtime_handles (schemas : List (Schema .source)) (value : SemanticValue)
    (admitted : Profile.Value.externalValid schemas value = true) :
    valueReferences value = [] ∧ ownedTokens value = [] :=
  admitted_tree_has_no_runtime_handles schemas value (Bool.and_eq_true_iff.mp admitted).2

private theorem bind_success (value : Except Invalid α) (next : α → Except Invalid β)
    (result : β) (accepted : value.bind next = .ok result) :
    ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value with
  | error error => cases accepted
  | ok input => exact ⟨input, rfl, accepted⟩

/-- The public source initializer has no hidden ambient handles: all entry
arguments are external trees and every runtime allocation inventory is empty. -/
theorem initialization_excludes_hidden_handles (context : Context) (arguments : List SemanticValue)
    (state : State) (accepted : initial context arguments = .ok state) :
    (∀ argument ∈ arguments, valueReferences argument = [] ∧ ownedTokens argument = []) ∧
      state.heap.objects = [] ∧ state.heap.custody.entries = [] ∧
      state.heap.nextAttachment = 0 ∧ state.heap.nextRegion = 0 ∧ state.heap.nextCell = 0 ∧
      state.heap.nextCustody = 0 ∧ state.heap.obligations = [] ∧ state.heap.loans = [] ∧
      state.heap.nextScope = state.heap.scopes.length ∧
      state.heap.nextInvocation = state.heap.invocations.length := by
  unfold initial at accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, external, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  have valid : arguments.all (Profile.Value.externalValid context.source.schemas) = true := by
    unfold require at external
    split at external
    · assumption
    · cases external
  cases accepted
  refine ⟨?_, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩
  intro argument member
  exact external_value_has_no_runtime_handles _ _ (List.all_eq_true.mp valid argument member)

end BoundaryV2.Profile.Source.Machine
