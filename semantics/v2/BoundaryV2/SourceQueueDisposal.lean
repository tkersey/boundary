import BoundaryV2.SourceQueueControl

namespace BoundaryV2.Profile.Source.Machine
namespace QueueCustody

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

private theorem require_ok (condition : Bool) (reason : Invalid) (result : Unit)
    (accepted : require condition reason = .ok result) : condition = true := by
  unfold require at accepted
  split at accepted <;> first | assumption | contradiction

theorem live_entry_tokens (heap : Heap) (value : Located) :
    (OwningFields.live heap.custody value).map Custody.Entry.token = tokens (liveOwned heap value) := by
  simp only [OwningFields.live, List.map_map, Function.comp_def, liveOwned, live_tokens]
  rw [← ownedReferences_tokens value.value, List.filter_map]
  rfl

theorem lives_linear (heap : Heap) (values : List Located)
    (owners : (values.map Located.owner).Nodup)
    (linear : ∀ value ∈ values, (ownedTokens value.value).Nodup) :
    Linear heap (values.flatMap (liveOwned heap)) := by
  constructor
  · have unique := OwningFields.unique_owners_give_unique_live_tokens heap.custody values owners linear
    simpa only [List.map_flatMap, live_entry_tokens, tokens, List.flatMap_assoc] using unique
  · intro child member
    obtain ⟨original, _, childAt⟩ := List.mem_flatMap.mp member
    exact live_current heap original.owner original.value child childAt

theorem current_owns (heap : Heap) (value : Located) (usable : current heap value = true)
    (token : CustodyToken) (member : token ∈ ownedTokens value.value) : Custody.owns heap.custody token value.owner := by
  have held := List.all_eq_true.mp (Bool.and_eq_true_iff.mp usable).2 token member
  simpa only [Custody.has, Custody.owns, List.any_eq_true, Bool.and_eq_true, beq_iff_eq] using held

theorem current_tokens_disjoint (heap : Heap) (first second : Located)
    (firstCurrent : current heap first = true) (secondCurrent : current heap second = true)
    (different : first.owner ≠ second.owner) :
    ∀ token ∈ ownedTokens first.value, token ∉ ownedTokens second.value := by
  intro token firstAt secondAt
  exact different (Custody.unique_custodian heap.custody token _ _
    (current_owns heap first firstCurrent token firstAt) (current_owns heap second secondCurrent token secondAt))

theorem drop_head_fields (machine : State) (value : Located) (rest : List Located) (released : AfterRelease)
    (executing : machine.control = .discard (value :: rest) released) :
    fields machine = (if closureOwner value.owner then [value] else []) ++
      fields {machine with control := .discard rest released} := by
  simp only [fields_components, controlFields, executing, DisposalShape.control, List.filter_cons]
  split <;> simp only [List.cons_append, List.nil_append]

theorem drop_head_valid (machine : State) (value : Located) (rest : List Located) (released : AfterRelease)
    (executing : machine.control = .discard (value :: rest) released) (valid : Valid machine) :
    Valid {machine with control := .discard rest released} := by
  have all := valid
  rw [Valid, drop_head_fields _ _ _ _ executing] at all
  exact (Linear.parts _ _ _ all).2.1

theorem drop_head_disjoint (machine : State) (value : Located) (rest : List Located) (released : AfterRelease)
    (executing : machine.control = .discard (value :: rest) released) (valid : Valid machine)
    (usable : current machine.heap value = true) :
    ∀ token ∈ tokens (fields {machine with control := .discard rest released}), token ∉ ownedTokens value.value := by
  have all := valid
  rw [Valid, drop_head_fields _ _ _ _ executing] at all
  have remaining := (Linear.parts _ _ _ all).2.1
  by_cases closed : closureOwner value.owner = true
  · simp only [closed, if_true] at all
    have separate := (Linear.parts _ _ _ all).2.2
    intro token member tokenAt
    exact separate token (by simpa [tokens] using tokenAt) member
  · intro token member tokenAt
    obtain ⟨pinned, pinnedAt, pinnedToken⟩ := List.mem_flatMap.mp member
    have pinnedClosed := (List.mem_filter.mp pinnedAt).2
    have different : pinned.owner ≠ value.owner := by intro same; rw [same] at pinnedClosed; contradiction
    exact current_tokens_disjoint machine.heap pinned value (remaining.2 pinned pinnedAt) usable different token pinnedToken tokenAt

theorem lookup_current (machine : State) (value : Located) (node : NodeId) (stored : Object)
    (accepted : lookupObject machine value = .ok (node, stored)) : current machine.heap value = true := by
  unfold lookupObject at accepted
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, checked, _⟩ := accepted
  exact require_ok _ _ _ checked

theorem retire_head_partition_linear (machine : State) (heap : Heap) (value : Located) (rest : List Located)
    (released : AfterRelease) (node : NodeId) (stored : Object)
    (executing : machine.control = .discard (value :: rest) released)
    (looked : lookupObject machine value = .ok (node, stored))
    (accepted : retireObject machine.heap value = some heap) (valid : Valid machine) :
    Linear heap (fields {machine with heap := heap, control := .discard rest released} ++ objectFields stored) := by
  let reduced := {machine with control := .discard rest released}
  have reducedValid := drop_head_valid _ _ _ _ executing valid
  have separate := drop_head_disjoint _ _ _ _ executing valid (lookup_current _ _ _ _ looked)
  have kept : Linear heap (fields reduced) := Linear.heap _ _ _ reducedValid (by
    intro pinned pinnedAt usable
    apply retire_keeps_current _ _ _ _ accepted usable
    intro token member
    exact separate token (List.mem_flatMap.mpr ⟨pinned, pinnedAt, member⟩))
  exact Linear.perm _ _ _ (retire_partition reduced heap value node stored looked accepted) kept

theorem drop_head_fields_sublist (machine : State) (value : Located) (rest : List Located) (released : AfterRelease)
    (executing : machine.control = .discard (value :: rest) released) :
    (fields {machine with control := .discard rest released}).Sublist (fields machine) := by
  rw [drop_head_fields _ _ _ _ executing]
  exact List.sublist_append_right _ _

theorem retired_head_fields_sublist (machine : State) (heap : Heap) (value : Located) (rest : List Located) (released : AfterRelease)
    (executing : machine.control = .discard (value :: rest) released)
    (accepted : retireObject machine.heap value = some heap) :
    (fields {machine with heap := heap, control := .discard rest released}).Sublist (fields machine) :=
  (retired_fields_sublist {machine with control := .discard rest released} heap value accepted).trans
    (drop_head_fields_sublist _ _ _ _ executing)

theorem linear_tokens_separate (before after : State) (values : List Located)
    (valid : Valid after) (ready : Linear after.heap values)
    (included : (fields after).Sublist (fields before)) (separate : ∀ value ∈ values, Separate before value) :
    ∀ token ∈ tokens values, token ∉ tokens (fields after) := by
  intro token member pending
  obtain ⟨value, valueAt, tokenAt⟩ := List.mem_flatMap.mp member
  obtain ⟨pinned, pinnedAt, pinnedToken⟩ := List.mem_flatMap.mp pending
  rcases separate value valueAt pinned (included.subset pinnedAt) with different | free
  · exact current_tokens_disjoint after.heap value pinned (ready.2 value valueAt) (valid.2 pinned pinnedAt)
      different token tokenAt pinnedToken
  · simp [free] at tokenAt

theorem prepend_discard_valid (machine : State) (values rest : List Located) (released : AfterRelease)
    (executing : machine.control = .discard rest released) (valid : Valid machine) (ready : Linear machine.heap values)
    (separate : ∀ token ∈ tokens values, token ∉ tokens (fields machine)) :
    Valid {machine with control := .discard (values ++ rest) released} := by
  let selected := values.filter (fun value => closureOwner value.owner)
  have next := Linear.append machine.heap selected (fields machine)
    (Linear.sublist _ _ _ List.filter_sublist ready) valid (by
      intro token member
      obtain ⟨value, valueAt, tokenAt⟩ := List.mem_flatMap.mp member
      exact separate token (List.mem_flatMap.mpr ⟨value, (List.mem_filter.mp valueAt).1, tokenAt⟩))
  simpa only [Valid, fields_components, controlFields, DisposalShape.control, executing, List.filter_append,
    selected, List.append_assoc] using next

theorem discardValues_valid (machine : State) (context : Context) (after : Transition)
    (accepted : discardValues machine context = .ok after) (valid : Valid machine)
    (retiredParents : ∀ pinned ∈ fields machine, OwnerLocations.Retired machine.heap pinned.owner)
    (layouts : ObjectOwners.Valid machine.heap)
    (linear : ValueInventory.All (fun value => (ownedTokens value).Nodup) machine) : Valid after.state := by
  unfold discardValues at accepted
  split at accepted <;> try contradiction
  rename_i values released executing
  cases values with
  | nil =>
    cases accepted
    cases released <;> exact empty_control_valid _ _ valid rfl
  | cons value rest =>
    simp only at accepted
    split at accepted
    · cases accepted; exact drop_head_valid _ _ _ _ executing valid
    · simp only [bind, except_bind_ok] at accepted
      obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
      have found := (CellStability.lookupObject_reference _ _ _ _ looked).2
      have layout := layouts node stored found
      have storedLinear := ValueInventory.lookup_preserves_all machine node stored found _ linear
      cases stored <;> try contradiction
      all_goals simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
      all_goals obtain ⟨heap, retired, rfl⟩ := accepted
      all_goals have partition := retire_head_partition_linear _ _ _ _ _ _ _ executing looked retired valid
      all_goals have included := retired_head_fields_sublist _ _ _ _ _ executing retired
      case oneShot saved =>
        have permuted := Linear.perm heap _ _
          (List.perm_append_comm (l₁ := fields {machine with heap := heap, control := .discard rest released})
            (l₂ := saved.frames.flatMap frameFields))
          (by simpa only [objectFields, DisposalShape.object, capture_fields] using partition)
        simpa only [Valid, fields_components, controlFields, DisposalShape.control, List.flatMap_append,
          List.flatMap_cons, List.flatMap_nil, frameFields, DisposalShape.frame, List.filter_nil,
          List.nil_append, List.append_nil, List.append_assoc] using permuted
      case closure schema function bindings =>
        have remaining : Valid {machine with heap := heap, control := .discard rest released} := by
          simpa only [Valid, objectFields, DisposalShape.object, List.filter_nil, List.append_nil] using partition
        let children := bindings.flatMap (fun binding => liveOwned heap binding.located)
        have childrenReady : Linear heap children := by
          have unique := lives_linear heap (bindings.map Binding.located)
            (by simpa only [List.map_map, Function.comp_def] using OwningFields.closure_owners_unique node schema function bindings layout)
            (by
              intro field member
              obtain ⟨binding, bindingAt, rfl⟩ := List.mem_map.mp member
              exact storedLinear binding.located.value (by
                simp only [ValueInventory.object, ValueInventory.environment]
                exact List.mem_map.mpr ⟨binding, bindingAt, rfl⟩))
          simpa only [List.flatMap_map, children] using unique
        have separate : ∀ child ∈ children, Separate machine child := by
          intro child member
          obtain ⟨binding, bindingAt, childAt⟩ := List.mem_flatMap.mp member
          obtain ⟨index, atIndex⟩ := List.mem_iff_getElem?.mp bindingAt
          exact live_parent_separate machine child node index _
            ((OwnerLocations.liveOwnedValue_owner heap binding.located.owner binding.located.value child childAt).trans (layout index binding atIndex)) found retiredParents
        exact prepend_discard_valid _ children rest released rfl remaining childrenReady
          (linear_tokens_separate machine _ children remaining childrenReady included separate)
      case package schema content =>
        have remaining : Valid {machine with heap := heap, control := .discard rest released} := by
          simpa only [Valid, objectFields, DisposalShape.object, List.filter_nil, List.append_nil] using partition
        have childrenReady := live_linear heap content (storedLinear content.value (by simp [ValueInventory.object]))
        have separate : ∀ child ∈ liveOwned heap content, Separate machine child := by
          intro child member
          exact live_parent_separate machine child node 0 _
            ((OwnerLocations.liveOwnedValue_owner heap content.owner content.value child member).trans layout) found retiredParents
        exact prepend_discard_valid _ _ rest released rfl remaining childrenReady
          (linear_tokens_separate machine _ _ remaining childrenReady included separate)
      case resource schema content =>
        simpa only [Valid, objectFields, DisposalShape.object, List.filter_nil, List.append_nil] using partition

end QueueCustody
end BoundaryV2.Profile.Source.Machine
