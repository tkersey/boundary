import BoundaryV2.SourceCustodyControl

namespace BoundaryV2.Profile.Source.Machine
namespace CustodyCoverage

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem live_owned_token (heap : Heap) (value : Located) (entry : Custody.Entry)
    (member : entry ∈ heap.custody.entries) (ownerAt : value.owner = entry.owner)
    (tokenAt : entry.token ∈ ownedTokens value.value) :
    ∃ child ∈ liveOwned heap value, child.owner = entry.owner ∧ entry.token ∈ ownedTokens child.value := by
  have held : Custody.has heap.custody entry.token value.owner = true := by
    apply List.any_eq_true.mpr
    exact ⟨entry, member, by simp [ownerAt]⟩
  have present : entry.token ∈ QueueCustody.tokens (liveOwned heap value) := by
    rw [liveOwned, QueueCustody.live_tokens]
    exact List.mem_filter.mpr ⟨tokenAt, held⟩
  obtain ⟨child, childAt, childToken⟩ := List.mem_flatMap.mp present
  exact ⟨child, childAt, (OwnerLocations.liveOwnedValue_owner _ _ _ _ childAt).trans ownerAt, childToken⟩

theorem Covered.live_transit (heap : Heap) (values transit : List Located)
    (covered : Covered heap.custody (values ++ transit)) :
    Covered heap.custody (values ++ transit.flatMap (liveOwned heap)) := by
  intro entry member
  obtain ⟨field, fieldAt, ownerAt, tokenAt⟩ := covered entry member
  rcases List.mem_append.mp fieldAt with old | moving
  · exact ⟨field, List.mem_append_left _ old, ownerAt, tokenAt⟩
  · obtain ⟨child, childAt, childOwner, childToken⟩ := live_owned_token heap field entry member ownerAt tokenAt
    exact ⟨child, List.mem_append_right _ (List.mem_flatMap.mpr ⟨field, moving, childAt⟩), childOwner, childToken⟩

theorem discard_tail_covered (machine : State) (value : Located) (rest : List Located) (released : AfterRelease)
    (extra : List Located) (executing : machine.control = .discard (value :: rest) released)
    (covered : Covered machine.heap.custody (fields machine ++ extra))
    (inactive : ∀ entry ∈ machine.heap.custody.entries, value.owner = entry.owner → entry.token ∉ ownedTokens value.value) :
    Covered machine.heap.custody (fields {machine with control := .discard rest released} ++ extra) := by
  intro entry member
  obtain ⟨field, fieldAt, ownerAt, tokenAt⟩ := covered entry member
  rcases List.mem_append.mp fieldAt with physical | transit
  · rcases List.mem_append.mp physical with heap | queue
    · exact ⟨field, List.mem_append_left _ (List.mem_append_left _ heap), ownerAt, tokenAt⟩
    · rw [QueueCustody.drop_head_fields _ _ _ _ executing] at queue
      rcases List.mem_append.mp queue with head | tail
      · split at head
        · have same := List.mem_singleton.mp head
          subst field
          exact False.elim (inactive entry member ownerAt tokenAt)
        · simp at head
      · exact ⟨field, List.mem_append_left _ (List.mem_append_right _ tail), ownerAt, tokenAt⟩
  · exact ⟨field, List.mem_append_right _ transit, ownerAt, tokenAt⟩

theorem retire_excludes_tokens (before after : Heap) (value : Located)
    (accepted : retireObject before value = some after) :
    ∀ entry ∈ after.custody.entries, entry.token ∉ ownedTokens value.value := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨_, _, middle, consumed, rfl⟩ := accepted
  simp only [consumeValue, bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at consumed
  obtain ⟨book, consumed, rfl⟩ := consumed
  unfold Custody.consume at consumed
  split at consumed <;> try contradiction
  cases consumed
  intro entry member
  have absent := (List.mem_filter.mp member).2
  intro present
  rw [List.contains_iff_mem.mpr present] at absent
  contradiction

theorem retire_head_covered (machine : State) (heap : Heap) (value : Located) (rest : List Located)
    (released : AfterRelease) (node : NodeId) (stored : Object)
    (executing : machine.control = .discard (value :: rest) released)
    (looked : lookupObject machine value = .ok (node, stored))
    (accepted : retireObject machine.heap value = some heap) (valid : Valid machine) :
    Covered heap.custody (fields {machine with heap := heap, control := .discard rest released} ++
      (OwningFields.object stored ++ QueueCustody.objectFields stored)) := by
  have next := retireObject_covered machine heap value node stored [] looked accepted (by simpa [Valid] using valid)
  exact discard_tail_covered {machine with heap := heap} value rest released _ executing
    (by simpa only [List.append_nil] using next)
    (fun entry member _ => retire_excludes_tokens _ _ _ accepted entry member)

theorem prepend_discard_covered (machine : State) (values rest : List Located) (released : AfterRelease)
    (executing : machine.control = .discard rest released)
    (covered : Covered machine.heap.custody (fields machine ++ values))
    (closed : ∀ value ∈ values, QueueCustody.closureOwner value.owner = true) :
    Valid {machine with control := .discard (values ++ rest) released} := by
  have selected : values.filter (fun value => QueueCustody.closureOwner value.owner) = values :=
    List.filter_eq_self.mpr closed
  apply Covered.mono _ _ _ covered
  intro field member
  simp only [fields, QueueCustody.fields_components, executing, QueueCustody.controlFields,
    DisposalShape.control, List.filter_append, selected, List.mem_append] at member ⊢
  grind only []

theorem discardValues_valid (machine : State) (context : Context) (after : Transition)
    (accepted : discardValues machine context = .ok after) (valid : Valid machine)
    (layouts : ObjectOwners.Valid machine.heap)
    (resourcesFree : ∀ node schema content,
      machine.heap.lookup node = some (.resource schema content) → ownedTokens content.value = []) : Valid after.state := by
  unfold discardValues at accepted
  split at accepted <;> try contradiction
  rename_i values released executing
  cases values with
  | nil =>
    cases accepted
    cases released <;> exact control_valid _ _ valid (by rw [executing]; rfl)
  | cons value rest =>
    simp only at accepted
    split at accepted
    · rename_i empty
      cases accepted
      have next := discard_tail_covered machine value rest released [] executing (by simpa [Valid] using valid) (by
        intro entry member ownerAt tokenAt
        obtain ⟨child, childAt, _⟩ := live_owned_token machine.heap value entry member ownerAt tokenAt
        have noChildren := List.nil_of_isEmpty empty
        simp [noChildren] at childAt)
      simpa only [Valid, List.append_nil] using next
    · simp only [bind, except_bind_ok] at accepted
      obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
      have found := (CellStability.lookupObject_reference _ _ _ _ looked).2
      have layout := layouts node stored found
      cases stored <;> try contradiction
      all_goals simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
      all_goals obtain ⟨heap, retired, rfl⟩ := accepted
      all_goals have partition := retire_head_covered _ _ _ _ _ _ _ executing looked retired valid
      case oneShot saved =>
        simp only [OwningFields.object, QueueCustody.objectFields, DisposalShape.object,
          QueueCustody.capture_fields, List.nil_append] at partition
        apply Covered.mono _ _ _ partition
        intro field member
        simp only [fields, QueueCustody.fields_components,
          QueueCustody.controlFields, QueueCustody.frameFields, DisposalShape.control,
          DisposalShape.frame, List.flatMap_append,
          List.flatMap_cons, List.flatMap_nil, List.append_nil, List.filter_nil, List.nil_append,
          List.mem_append] at member ⊢
        grind only []
      case closure schema function bindings =>
        have childrenCover := Covered.live_transit heap (fields {machine with heap := heap, control := .discard rest released})
          (bindings.map Binding.located) (by
            simpa only [OwningFields.object, QueueCustody.objectFields, DisposalShape.object,
              List.filter_nil, List.append_nil] using partition)
        apply prepend_discard_covered {machine with heap := heap, control := .discard rest released}
          (bindings.flatMap fun binding => liveOwned heap binding.located) rest released rfl
          (by simpa only [List.flatMap_map] using childrenCover)
        intro child member
        obtain ⟨binding, bindingAt, childAt⟩ := List.mem_flatMap.mp member
        obtain ⟨index, atIndex⟩ := List.mem_iff_getElem?.mp bindingAt
        rw [OwnerLocations.liveOwnedValue_owner heap binding.located.owner binding.located.value child childAt,
          layout index binding atIndex]
        rfl
      case package schema content =>
        have childrenCover := Covered.live_transit heap (fields {machine with heap := heap, control := .discard rest released})
          [content] (by
            simpa only [OwningFields.object, QueueCustody.objectFields, DisposalShape.object,
              List.filter_nil, List.append_nil] using partition)
        apply prepend_discard_covered {machine with heap := heap, control := .discard rest released}
          (liveOwned heap content) rest released rfl
          (by simpa only [List.flatMap_singleton] using childrenCover)
        intro child member
        rw [OwnerLocations.liveOwnedValue_owner heap content.owner content.value child member, layout]
        rfl
      case resource schema content =>
        apply Covered.drop_free _ _ _ partition
        intro field member
        simp only [OwningFields.object, QueueCustody.objectFields, DisposalShape.object,
          List.filter_nil, List.append_nil, List.mem_singleton] at member
        subst field
        exact resourcesFree _ _ _ found

end CustodyCoverage
end BoundaryV2.Profile.Source.Machine
