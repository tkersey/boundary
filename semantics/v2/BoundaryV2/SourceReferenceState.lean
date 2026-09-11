import BoundaryV2.SourceValueInventory
import BoundaryV2.SourceCustodyBounds

namespace BoundaryV2.Profile.Source.Machine

/-- The owned-reference component of state well-formedness. It includes stale
tokens in retained values, while requiring every live custody entry to name a
present object. Typing, reusable references, scopes, and obligations have
separate obligations. -/
structure State.OwnedReferenceWF (state : State) : Prop where
  aligned : ValueInventory.All (ValueAligned state.heap.custody) state
  tokens : ValueInventory.All (ValueTokensBounded state.heap.nextCustody) state
  live : state.heap.CustodyLive
  bounded : state.heap.CustodyBounded

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

theorem initial_owned_reference_wf (context : Context) (arguments : List SemanticValue) (state : State)
    (accepted : initial context arguments = .ok state) : state.OwnedReferenceWF := by
  have empty := initialization_excludes_hidden_handles _ _ _ accepted
  have values := ValueInventory.initial_has_no_runtime_handles _ _ _ accepted
  refine ⟨?_, ?_, ?_, initial_custody_bounded _ _ _ accepted⟩
  · exact ValueInventory.all_mono _ _ state values (fun value free => token_free_aligned _ _ free.2)
  · exact ValueInventory.all_mono _ _ state values
      (fun value free => by simp [ValueTokensBounded, free.2])
  · intro entry member
    rw [empty.2.2.1] at member
    contradiction

theorem external_retains_reference_custody (state : State) (context : Context) (action : External)
    (after : Transition) (accepted : external state context action = .ok after) :
    after.state.heap.objects = state.heap.objects ∧ after.state.heap.custody = state.heap.custody ∧
      after.state.heap.nextCustody = state.heap.nextCustody := by
  have temporarySame (state after : State) (owner : Custody.Owner)
      (accepted : temporary state = .ok (after, owner)) :
      after.heap.objects = state.heap.objects ∧ after.heap.custody = state.heap.custody ∧
        after.heap.nextCustody = state.heap.nextCustody := by
    unfold temporary at accepted
    split at accepted <;> try contradiction
    split at accepted <;> try contradiction
    cases accepted; exact ⟨rfl, rfl, rfl⟩
  have finishSame (state : State) (value : Located) (after : Transition)
      (accepted : finishTemporary state value = .ok after) :
      after.state.heap.objects = state.heap.objects ∧ after.state.heap.custody = state.heap.custody ∧
        after.state.heap.nextCustody = state.heap.nextCustody := by
    unfold finishTemporary at accepted
    split at accepted <;> try contradiction
    cases accepted; exact ⟨rfl, rfl, rfl⟩
  have scopedSame (state : State) (value : SemanticValue) (after : Transition)
      (accepted : scopedValue state value = .ok after) :
      after.state.heap.objects = state.heap.objects ∧ after.state.heap.custody = state.heap.custody ∧
        after.state.heap.nextCustody = state.heap.nextCustody := by
    simp only [scopedValue, bind] at accepted
    grind only [except_bind_ok]
  cases phase : state.status <;> cases action <;>
    simp only [external, phase, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw,
      Except.bind] at accepted <;> try contradiction
  all_goals grind (gen := 32) only []

theorem external_owned_reference_wf (state : State) (context : Context) (action : External)
    (after : Transition) (accepted : external state context action = .ok after)
    (formed : state.OwnedReferenceWF) : after.state.OwnedReferenceWF := by
  obtain ⟨objects, custody, supply⟩ := external_retains_reference_custody _ _ _ _ accepted
  refine ⟨?_, ?_, ?_, external_custody_bounded _ _ _ _ accepted formed.bounded⟩
  · rw [custody]
    apply ValueInventory.external_preserves_all _ _ _ _ accepted _ formed.aligned
    intro value checked
    exact token_free_aligned _ _ (external_value_has_no_runtime_handles _ _ checked).2
  · rw [supply]
    apply ValueInventory.external_preserves_all _ _ _ _ accepted _ formed.tokens
    intro value checked
    simp [ValueTokensBounded, (external_value_has_no_runtime_handles _ _ checked).2]
  · intro entry member
    simpa only [Heap.lookup, custody, objects] using formed.live entry (custody ▸ member)

end BoundaryV2.Profile.Source.Machine
