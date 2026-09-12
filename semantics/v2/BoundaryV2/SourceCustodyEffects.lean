import BoundaryV2.SourceCustodyDisposal

namespace BoundaryV2.Profile.Source.Machine
namespace CustodyCoverage

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem finishTemporary_control (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) : after.state.control = .delivered value := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  cases accepted
  rfl

theorem invokeFunction_transit_valid (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction machine context function bindings arguments = .ok after)
    (valid : Covered machine.heap.custody (fields machine ++ arguments))
    (empty : QueueCustody.controlFields machine.control = []) : Valid after.state := by
  have actual := accepted
  simp only [invokeFunction, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at actual
  obtain ⟨_, _, _, _, captured, capturedAt, _⟩ := actual
  apply invokeFunction_covered _ _ _ _ _ captured _ capturedAt accepted ?_ empty
  apply Covered.mono _ _ _ valid
  intro field member
  rcases List.mem_append.mp member with old | argument
  · exact List.mem_append_left _ old
  · exact List.mem_append_right _ (List.mem_append_right _ argument)

theorem selected_capture_covered (machine : State) (context : Context) (identity : AttachmentId) (selected : Selection)
    (extra : List Located) (found : selectAttachment identity machine.stack = some selected)
    (valid : Covered machine.heap.custody (fields machine ++ extra)) :
    Covered machine.heap.custody (fields {machine with stack := selected.outside} ++
      (selected.inside.map (trimFrame context)).flatMap QueueCustody.frameFields ++ extra) := by
  have trimmed : (selected.inside.map (trimFrame context)).flatMap QueueCustody.frameFields =
      selected.inside.flatMap QueueCustody.frameFields := by
    simp only [List.flatMap_map, QueueCustody.frameFields, OwnerLocations.trim_frame_queued]
    rfl
  rw [trimmed]
  have shape := selection_reconstructs _ _ _ found
  apply Covered.mono _ _ _ valid
  intro field member
  simp only [fields, QueueCustody.fields_components, shape, List.flatMap_append, List.flatMap_cons,
    QueueCustody.frameFields, DisposalShape.frame, List.filter_nil, List.nil_append, List.mem_append] at member ⊢
  grind only []

theorem openRequest_valid (machine : State) (context : Context) (operation : Operation)
    (operands : List Located) (after : Transition)
    (accepted : openRequest machine context operation operands = .ok after) (valid : Valid machine)
    (empty : QueueCustody.controlFields machine.control = []) : Valid after.state := by
  simp only [openRequest, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨effect, _, _, _, payload, _, _, _, accepted⟩ := accepted
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
    split at accepted
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, _, _, invoked⟩ := accepted
      exact invokeFunction_valid _ _ _ _ _ _ invoked valid empty
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨shape, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      rename_i signature shapeAt
      obtain ⟨store, moved, accepted⟩ := (except_bind_ok _ _ _).mp accepted
      have moved := (fromOption_ok _ _ _).mp moved
      let outgoing := payload :: ((operands.drop operation.capability.toList.length).drop 1).take operation.bodies.length
      let forwarded := outgoing.mapIdx (fun index value => retainAt value (.receiver ⟨machine.heap.nextInvocation⟩ index))
      have movedCover := moveValues_covered _ _ _ _ _ moved valid
      rw [← move_fields _ _ _ _ moved] at movedCover
      have partition := selected_capture_covered {machine with heap := store} context identity selected forwarded selectedAt movedCover
      split at accepted
      all_goals
        simp only [except_bind_ok, fromOption_ok] at accepted
        try
          obtain ⟨gate, guard, rest⟩ := accepted
          have _ : Unit := gate
          clear guard
          have accepted := rest
        obtain ⟨⟨outside, owner⟩, reserved, ⟨finalStore, token⟩, allocated, staged, stagedOk, invoked⟩ := accepted
        have temporaryCover := temporary_covered _ _ _
          ((selected.inside.map (trimFrame context)).flatMap QueueCustody.frameFields ++ forwarded) reserved
          (by simpa only [List.append_assoc, fields, OwningFields.heap, QueueCustody.fields_components, QueueCustody.heapFields] using partition)
        have allocatedCover := allocate_covered _ _ _ _ _ _ _ forwarded allocated (by
          first
          | simpa only [OwningFields.object, QueueCustody.oneShot_fields, QueueCustody.multiTemplate_fields,
              List.nil_append, List.append_assoc] using temporaryCover
          | split <;> simpa only [OwningFields.object, QueueCustody.oneShot_fields, QueueCustody.multiTemplate_fields,
              List.nil_append, List.append_assoc] using temporaryCover)
        have stagedCover := finishTemporary_covered _ _ forwarded _ stagedOk
          (by rw [temporary_control _ _ _ reserved]; exact empty) allocatedCover
        apply invokeFunction_transit_valid _ _ _ _ _ _ invoked ?_
          (by rw [finishTemporary_control _ _ _ stagedOk]; rfl)
        apply Covered.mono _ _ _ stagedCover
        intro field member
        rcases List.mem_append.mp member with prior | outgoingAt
        · exact List.mem_append_left _ prior
        · exact List.mem_append_right _ (List.mem_append_left _ (List.mem_append_right _ outgoingAt))

private theorem foldlM_preserves (items : List β) (step : α → β → Except Invalid α)
    (property : α → Prop) (preserved : ∀ before item after, step before item = .ok after → property before → property after)
    (before after : α) (accepted : items.foldlM step before = .ok after) (holds : property before) : property after := by
  induction items generalizing before with
  | nil => cases accepted; exact holds
  | cons item items induction =>
    simp only [List.foldlM_cons, bind, except_bind_ok] at accepted
    obtain ⟨middle, stepped, rest⟩ := accepted
    exact induction middle rest (preserved before item middle stepped holds)

theorem allocate_nonowning_valid (machine : State) (heap : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (value : Located)
    (accepted : allocateObject machine.heap schema stored owner false = some (heap, value)) (valid : Valid machine) :
    Valid {machine with heap := heap} := by
  apply Covered.drop_free _ _ _ (allocation_from_valid _ _ _ _ _ _ _ accepted valid)
  intro field member
  cases List.mem_singleton.mp member
  exact QueueCustody.allocation_result_nonowning _ _ _ _ _ _ accepted

theorem installHandler_valid (machine : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (bindings : Environment) (after : Transition)
    (accepted : installHandler machine context handler body arguments stored bindings = .ok after) (valid : Valid machine)
    (empty : QueueCustody.controlFields machine.control = [])
    (contracts : ClosureContracts.Valid context machine.heap.objects) : Valid after.state := by
  simp only [installHandler, bind, except_bind_ok] at accepted
  obtain ⟨definition, _, _, _, _, _, _, _, signature, _, _, _, ⟨store, capabilities⟩, allocated, applied⟩ := accepted
  have heap : Valid {machine with heap := store} ∧ ClosureContracts.Valid context store.objects := by
    apply foldlM_preserves _ _ (fun pair : Heap × List Located =>
      Valid {machine with heap := pair.1} ∧ ClosureContracts.Valid context pair.1.objects) ?_ _ _ allocated
      ⟨valid, contracts⟩
    intro before item after accepted formed
    rcases before with ⟨heap, capabilities⟩
    rcases item with ⟨clause, schema⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, ⟨next, value⟩, allocated, rfl⟩ := accepted
    exact ⟨allocate_nonowning_valid {machine with heap := heap} _ _ _ _ _ allocated formed.1,
      ClosureContracts.allocate_valid _ _ _ _ _ _ _ _ allocated formed.2 trivial⟩
  let active : Activation := ⟨⟨machine.heap.nextAttachment⟩, handler, handlerEnvironment context definition bindings,
    stored, machine.invocation, machine.scope, (activeAttachments machine.stack).head?⟩
  have next := stack_fields_valid {machine with heap := store} (.handler active :: machine.stack) heap.1 rfl
  exact applyClosure_valid _ _ _ _ _ applied next empty heap.2

theorem completeHandler_valid (machine : State) (context : Context) (after : Transition)
    (accepted : completeHandler machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold completeHandler at accepted
  split at accepted <;> try contradiction
  rename_i value executing
  split at accepted <;> try contradiction
  rename_i active tail stacked
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  have remaining := stack_fields_valid machine tail valid (by simp [stacked, QueueCustody.frameFields, DisposalShape.frame])
  exact control_valid _ _ remaining (by rw [executing]; rfl)

theorem enterRegion_valid (machine : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition)
    (accepted : enterRegion machine context descriptor body arguments = .ok after) (valid : Valid machine)
    (empty : QueueCustody.controlFields machine.control = [])
    (contracts : ClosureContracts.Valid context machine.heap.objects) : Valid after.state := by
  simp only [enterRegion, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, signature, _, schema, _, _, _, ⟨heap, value⟩, allocated, applied⟩ := accepted
  have seed : Valid {machine with heap := {machine.heap with nextRegion := machine.heap.nextRegion + 1}} := valid
  have next := allocate_nonowning_valid _ _ _ _ _ _ allocated seed
  have typed := ClosureContracts.allocate_valid context _ _ _ _ _ _ _ allocated contracts trivial
  have stacked := stack_fields_valid {machine with heap := heap} (.region ⟨machine.heap.nextRegion⟩ :: machine.stack) next rfl
  exact applyClosure_valid _ _ _ _ _ applied stacked empty typed

theorem executeEffectTerm_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executeEffectTerm machine context = .ok after) (valid : Valid machine)
    (contracts : ClosureContracts.Valid context machine.heap.objects) : Valid after.state := by
  unfold executeEffectTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  have empty : QueueCustody.controlFields machine.control = [] := by rw [executing]; rfl
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · exact openRequest_valid _ _ _ _ _ accepted valid empty
  · split at accepted <;> try contradiction
    exact installHandler_valid _ _ _ _ _ _ _ _ accepted valid empty contracts
  · split at accepted <;> try contradiction
    exact resumeValue_valid _ _ _ _ _ _ accepted valid empty
  · split at accepted <;> try contradiction
    exact resumeValue_valid _ _ _ _ _ _ accepted valid empty
  · split at accepted <;> try contradiction
    exact resumeComputation_valid _ _ _ _ _ accepted valid empty contracts
  · split at accepted <;> try contradiction
    exact enterRegion_valid _ _ _ _ _ _ accepted valid empty contracts

end CustodyCoverage
end BoundaryV2.Profile.Source.Machine
