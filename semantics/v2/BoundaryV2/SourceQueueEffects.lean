import BoundaryV2.SourceQueueDisposal

namespace BoundaryV2.Profile.Source.Machine
namespace QueueCustody

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem nonclosure_separate (machine : State) (value : Located) (different : closureOwner value.owner = false) :
    Separate machine value := by
  intro pinned member
  left
  intro same
  have closed := (List.mem_filter.mp member).2
  rw [same] at different
  rw [closed] at different
  contradiction

theorem allocate_partition_valid (machine : State) (heap : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject machine.heap schema stored owner exclusive = some (heap, value))
    (valid : Linear machine.heap (fields machine ++ objectFields stored)) : Valid {machine with heap := heap} := by
  have objects : heap.objects = machine.heap.objects ++ [some stored] := by
    cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
    · obtain ⟨rfl, _⟩ := accepted; rfl
    · obtain ⟨_, _, rfl, _⟩ := accepted; rfl
  have kept := Linear.heap machine.heap heap _ valid (fun pinned _ usable => allocation_keeps_current _ _ _ _ _ _ _ _ accepted usable)
  simpa only [Valid, fields_components, heapFields, objects, List.flatMap_append, List.flatMap_cons,
    List.flatMap_nil, Option.toList_some, List.append_nil, List.append_assoc] using kept

theorem temporary_linear (machine after : State) (owner : Custody.Owner) (extra : List Located)
    (accepted : temporary machine = .ok (after, owner)) (valid : Linear machine.heap (fields machine ++ extra)) :
    Linear after.heap (fields after ++ extra) := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  exact valid

theorem allocation_result_nonowning (before after : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (value : Located)
    (accepted : allocateObject before schema stored owner false = some (after, value)) : ownedTokens value.value = [] := by
  cases accepted
  simp [ownedTokens]

theorem selected_queue_partition (machine : State) (context : Context) (identity : AttachmentId) (selected : Selection)
    (found : selectAttachment identity machine.stack = some selected) (valid : Valid machine) :
    Linear machine.heap (fields {machine with stack := selected.outside} ++
      (selected.inside.map (trimFrame context)).flatMap frameFields) := by
  have trimmed : (selected.inside.map (trimFrame context)).flatMap frameFields = selected.inside.flatMap frameFields := by
    simp only [List.flatMap_map, frameFields, OwnerLocations.trim_frame_queued]
    rfl
  rw [trimmed]
  have shape := selection_reconstructs _ _ _ found
  apply Linear.perm _ (fields machine) _ _ valid
  simp only [fields_components, shape, List.flatMap_append, List.flatMap_cons, frameFields,
    DisposalShape.frame, List.filter_nil, List.nil_append, List.append_assoc]
  simpa only [List.append_assoc] using List.Perm.append_left (controlFields machine.control)
    (List.perm_append_comm (l₁ := selected.inside.flatMap frameFields)
      (l₂ := selected.outside.flatMap frameFields ++ heapFields machine.heap))

theorem oneShot_fields (saved : Capture) : objectFields (.oneShot saved) = saved.frames.flatMap frameFields :=
  capture_fields saved

theorem multiTemplate_fields (saved : Capture) : objectFields (.multiTemplate saved) = saved.frames.flatMap frameFields :=
  capture_fields saved

theorem openRequest_valid (machine : State) (context : Context) (operation : Operation)
    (operands : List Located) (after : Transition)
    (accepted : openRequest machine context operation operands = .ok after) (valid : Valid machine)
    (owners : OwnerLocations.Valid machine) (ordinary : ∀ value ∈ operands, OwnerLocations.Ordinary value) : Valid after.state := by
  simp only [openRequest, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨effect, _, _, _, payload, payloadAt, _, _, accepted⟩ := accepted
  have payloadOrdinary := ordinary payload (List.mem_of_mem_drop (List.mem_of_head? payloadAt))
  have bodies : ∀ value ∈ ((operands.drop operation.capability.toList.length).drop 1).take operation.bodies.length,
      OwnerLocations.Ordinary value := by
    intro value member
    exact ordinary value (List.mem_of_mem_drop (List.mem_of_mem_drop (List.mem_of_mem_take member)))
  split at accepted
  · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    exact valid
  · simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, _, accepted⟩ := accepted
    cases stored <;> try contradiction
    rename_i identity nominal looked
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, selected, selectedAt, definition, _, clause, _, accepted⟩ := accepted
    have activeOrdinary := OwnerLocations.normal_frame machine (.handler selected.activation)
      (by simp [selection_reconstructs _ _ _ selectedAt]) owners.1
    have environment : ∀ binding ∈ selected.activation.environment, OwnerLocations.Ordinary binding.located := by
      intro binding member
      exact activeOrdinary binding.located (List.mem_append_left _ (List.mem_map.mpr ⟨binding, member, rfl⟩))
    have stored : ∀ value ∈ selected.activation.state, OwnerLocations.Ordinary value := by
      intro value member
      exact activeOrdinary value (List.mem_append_right _ member)
    split at accepted
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, _, _, invoked⟩ := accepted
      apply invokeFunction_valid _ _ _ _ _ _ invoked valid
        (fun binding member => ordinary_separate _ _ (environment binding member))
      intro value member
      exact ordinary_separate _ _ (by
        rcases List.mem_append.mp member with old | result
        · exact stored value old
        · cases List.mem_singleton.mp result; exact payloadOrdinary)
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨shape, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      rename_i signature shapeAt
      obtain ⟨store, moved, accepted⟩ := (except_bind_ok _ _ _).mp accepted
      have moved := (fromOption_ok _ _ _).mp moved
      have storeValid := move_ordinary_valid _ _ _ _ moved valid (by
        intro value member
        rcases List.mem_cons.mp member with rfl | member
        · exact payloadOrdinary
        · exact bodies value member)
      have partition := selected_queue_partition {machine with heap := store} context identity selected selectedAt storeValid
      split at accepted
      all_goals
        simp only [except_bind_ok, fromOption_ok] at accepted
        try
          obtain ⟨gate, guard, rest⟩ := accepted
          have _ : Unit := gate
          clear guard
          have accepted := rest
        obtain ⟨⟨outside, owner⟩, reserved, ⟨finalStore, token⟩, allocated, staged, stagedOk, invoked⟩ := accepted
        have temporaryValid := temporary_linear _ _ _ _ reserved partition
        have created := allocate_partition_valid _ _ _ _ _ _ _ allocated (by
          first
          | simpa only [oneShot_fields, multiTemplate_fields] using temporaryValid
          | split <;> simpa only [oneShot_fields, multiTemplate_fields] using temporaryValid)
        have stagedValid := finishTemporary_valid _ _ _ stagedOk created
        have tokenOrdinary := OwnerLocations.allocation_result_ordinary _ _ _ _ _ _ _ allocated (temporary_owner _ _ _ reserved)
        apply invokeFunction_valid _ _ _ _ _ _ invoked stagedValid
          (fun binding member => ordinary_separate _ _ (environment binding member))
        intro value member
        rcases List.mem_append.mp member with (member | member)
        · rcases List.mem_append.mp member with old | outgoing
          · exact ordinary_separate _ _ (stored value old)
          · obtain ⟨index, _, rfl⟩ := List.exists_of_mem_mapIdx outgoing
            exact nonclosure_separate _ _ rfl
        · cases List.mem_singleton.mp member
          exact ordinary_separate _ _ tokenOrdinary

theorem allocate_empty_fields (machine : State) (heap : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject machine.heap schema stored owner exclusive = some (heap, value))
    (empty : objectFields stored = []) : fields {machine with heap := heap} = fields machine := by
  have objects : heap.objects = machine.heap.objects ++ [some stored] := by
    cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
    · obtain ⟨rfl, _⟩ := accepted; rfl
    · obtain ⟨_, _, rfl, _⟩ := accepted; rfl
  simp only [fields_components, heapFields, objects, List.flatMap_append, List.flatMap_cons,
    List.flatMap_nil, Option.toList_some, empty, List.append_nil]

theorem allocate_empty_retired (machine : State) (heap : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject machine.heap schema stored owner exclusive = some (heap, value))
    (empty : objectFields stored = [])
    (retired : ∀ pinned ∈ fields machine, OwnerLocations.Retired machine.heap pinned.owner) :
    ∀ pinned ∈ fields {machine with heap := heap}, OwnerLocations.Retired heap pinned.owner := by
  intro pinned member
  rw [allocate_empty_fields _ _ _ _ _ _ _ accepted empty] at member
  exact OwnerLocations.retired_mono _ _ _ (OwnerLocations.allocation_retains _ _ _ _ _ _ _ accepted) (retired pinned member)

private theorem foldlM_preserves (items : List β) (step : α → β → Except Invalid α)
    (property : α → Prop) (preserved : ∀ before item after, step before item = .ok after → property before → property after)
    (before after : α) (accepted : items.foldlM step before = .ok after) (holds : property before) : property after := by
  induction items generalizing before with
  | nil => cases accepted; exact holds
  | cons item items induction =>
    simp only [List.foldlM_cons, bind, except_bind_ok] at accepted
    obtain ⟨middle, stepped, rest⟩ := accepted
    exact induction middle rest (preserved before item middle stepped holds)

theorem installHandler_valid (machine : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (bindings : Environment) (after : Transition)
    (accepted : installHandler machine context handler body arguments stored bindings = .ok after) (valid : Valid machine)
    (bodyOrdinary : OwnerLocations.Ordinary body) (ordinary : ∀ value ∈ arguments, OwnerLocations.Ordinary value)
    (retired : ∀ pinned ∈ fields machine, OwnerLocations.Retired machine.heap pinned.owner)
    (objects : ObjectOwners.Valid machine.heap) : Valid after.state := by
  simp only [installHandler, bind, except_bind_ok] at accepted
  obtain ⟨definition, _, _, _, _, _, _, _, signature, _, _, _, ⟨store, capabilities⟩, allocated, applied⟩ := accepted
  have heap : Valid {machine with heap := store} ∧
      (∀ pinned ∈ fields {machine with heap := store}, OwnerLocations.Retired store pinned.owner) ∧
      ObjectOwners.Valid store ∧ ∀ value ∈ capabilities, ownedTokens value.value = [] := by
    apply foldlM_preserves _ _ (fun pair : Heap × List Located =>
      Valid {machine with heap := pair.1} ∧
      (∀ pinned ∈ fields {machine with heap := pair.1}, OwnerLocations.Retired pair.1 pinned.owner) ∧
      ObjectOwners.Valid pair.1 ∧ ∀ value ∈ pair.2, ownedTokens value.value = []) ?_ _ _ allocated
      ⟨valid, retired, objects, by simp⟩
    intro before item after accepted formed
    rcases before with ⟨heap, capabilities⟩
    rcases item with ⟨clause, schema⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, ⟨next, value⟩, allocated, rfl⟩ := accepted
    refine ⟨allocate_empty_valid {machine with heap := heap} _ _ _ _ _ _ allocated formed.1 rfl,
      allocate_empty_retired {machine with heap := heap} _ _ _ _ _ _ allocated rfl formed.2.1,
      ObjectOwners.allocation_valid _ _ _ _ _ _ _ allocated formed.2.2.1 (by trivial), ?_⟩
    intro added member
    rcases List.mem_append.mp member with old | created
    · exact formed.2.2.2 added old
    · cases List.mem_singleton.mp created
      exact allocation_result_nonowning _ _ _ _ _ _ allocated
  let active : Activation := ⟨⟨machine.heap.nextAttachment⟩, handler, handlerEnvironment context definition bindings,
    stored, machine.invocation, machine.scope, (activeAttachments machine.stack).head?⟩
  have next := stack_fields_valid {machine with heap := store} (.handler active :: machine.stack) heap.1 rfl
  apply applyClosure_valid _ _ _ _ _ applied next (ordinary_separate _ _ bodyOrdinary) ?_ ?_ heap.2.2.1
  · intro value member
    rcases List.mem_append.mp member with capability | argument
    · exact ordinary_separate _ _ (Or.inr (heap.2.2.2 value capability))
    · exact ordinary_separate _ _ (ordinary value argument)
  · intro pinned member
    exact heap.2.1 pinned member

theorem completeHandler_valid (machine : State) (context : Context) (after : Transition)
    (accepted : completeHandler machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold completeHandler at accepted
  split at accepted <;> try contradiction
  rename_i value executing
  split at accepted <;> try contradiction
  rename_i active tail stacked
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  have remaining := substack_valid machine tail valid (by rw [stacked]; exact List.sublist_cons_self _ _)
  exact empty_control_valid _ _ remaining rfl

theorem enterRegion_valid (machine : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition)
    (accepted : enterRegion machine context descriptor body arguments = .ok after) (valid : Valid machine)
    (bodyOrdinary : OwnerLocations.Ordinary body) (ordinary : ∀ value ∈ arguments, OwnerLocations.Ordinary value)
    (retired : ∀ pinned ∈ fields machine, OwnerLocations.Retired machine.heap pinned.owner)
    (objects : ObjectOwners.Valid machine.heap) : Valid after.state := by
  simp only [enterRegion, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, signature, _, schema, _, _, _, ⟨heap, value⟩, allocated, applied⟩ := accepted
  have seed := same_storage_valid machine {machine.heap with nextRegion := machine.heap.nextRegion + 1} valid rfl rfl
  have next := allocate_empty_valid _ _ _ _ _ _ _ allocated seed rfl
  have retiredNext := allocate_empty_retired
    {machine with heap := {machine.heap with nextRegion := machine.heap.nextRegion + 1}} heap _ _ _ _ _ allocated rfl retired
  have objectNext := ObjectOwners.allocation_valid _ _ _ _ _ _ _ allocated objects (by trivial)
  have stacked := stack_fields_valid {machine with heap := heap} (.region ⟨machine.heap.nextRegion⟩ :: machine.stack) next rfl
  apply applyClosure_valid _ _ _ _ _ applied stacked (ordinary_separate _ _ bodyOrdinary) ?_ ?_ objectNext
  · intro child member
    rcases List.mem_cons.mp member with rfl | member
    · exact ordinary_separate _ _ (Or.inr (allocation_result_nonowning _ _ _ _ _ _ allocated))
    · exact ordinary_separate _ _ (ordinary child member)
  · intro pinned member
    exact retiredNext pinned member

theorem executeEffectTerm_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executeEffectTerm machine context = .ok after) (valid : Valid machine)
    (owners : OwnerLocations.Valid machine) (leaves : DisposalShape.Valid machine)
    (objects : ObjectOwners.Valid machine.heap) : Valid after.state := by
  unfold executeEffectTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  have ordinary : ∀ value ∈ operands, OwnerLocations.Ordinary value := by
    intro value member
    exact OwnerLocations.normal_control machine owners.1 value (by
      simp only [executing, OwnerLocations.controlValues]
      exact List.mem_append_right _ member)
  have retired := fields_retired machine owners leaves
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · exact openRequest_valid _ _ _ _ _ accepted valid owners ordinary
  · split at accepted <;> try contradiction
    apply installHandler_valid _ _ _ _ _ _ _ _ accepted valid
      (by grind only [List.mem_cons, List.not_mem_nil]) ?_ retired objects
    intro value member
    exact ordinary value (List.mem_cons_of_mem _ (List.mem_of_mem_take member))
  · split at accepted <;> try contradiction
    exact resumeValue_valid _ _ _ _ _ _ accepted valid
      (by grind only [List.mem_cons, List.not_mem_nil]) (by grind only [List.mem_cons, List.not_mem_nil])
  · split at accepted <;> try contradiction
    exact resumeValue_valid _ _ _ _ _ _ accepted valid
      (by grind only [List.mem_cons, List.not_mem_nil]) (by grind only [List.mem_cons, List.not_mem_nil])
  · split at accepted <;> try contradiction
    exact resumeComputation_valid _ _ _ _ _ accepted valid
      (by grind only [List.mem_cons, List.not_mem_nil]) (by grind only [List.mem_cons, List.not_mem_nil]) owners leaves objects
  · split at accepted <;> try contradiction
    exact enterRegion_valid _ _ _ _ _ _ accepted valid
      (by grind only [List.mem_cons, List.not_mem_nil])
      (by intro value member; grind only [List.mem_cons, List.not_mem_nil]) retired objects

end QueueCustody
end BoundaryV2.Profile.Source.Machine
