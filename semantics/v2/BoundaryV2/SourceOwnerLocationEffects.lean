import BoundaryV2.SourceOwnerLocationControl

namespace BoundaryV2.Profile.Source.Machine
namespace OwnerLocations

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem handler_environment_ordinary (context : Context) (handler : Handler .source) (bindings : Environment)
    (ordinary : ∀ binding ∈ bindings, Ordinary binding.located) :
    ∀ binding ∈ handlerEnvironment context handler bindings, Ordinary binding.located := by
  intro binding member
  exact ordinary binding (List.mem_filter.mp member).1

theorem takeCapture_valid (machine : State) (context : Context) (token : Located) (after : State × Capture)
    (accepted : takeCapture machine context token = .ok after) (valid : Valid machine) :
    Valid after.1 ∧ CaptureValid after.1.heap after.2 := by
  simp only [takeCapture, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
  have found := (CellStability.lookupObject_reference _ _ _ _ looked).2
  have object := lookup_valid machine node stored valid found
  cases stored <;> try contradiction
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨heap, retired, rfl⟩ := accepted
    exact ⟨retire_valid _ _ _ retired valid, CaptureValid.mono _ _ _ (retire_retains _ _ _ retired) object⟩
  · exact instantiateCapture_valid _ _ _ _ _ accepted valid

theorem activated_stack_valid (machine : State) (saved : Capture) (delimiter : Activation) (reinstall : Bool)
    (valid : Valid machine) (captured : CaptureValid machine.heap saved)
    (ordinary : ∀ value ∈ activationValues delimiter, Ordinary value) :
    Valid {machine with
      stack := saved.frames ++ (if reinstall then [.handler delimiter] else []) ++ [.restore machine.invocation machine.scope] ++ machine.stack
      scope := saved.scope
      invocation := saved.invocation} := by
  have originalNormal := normal_stack machine valid.1
  have originalQueue := pending_stack machine valid.2
  have next := with_stack machine
    (saved.frames ++ (if reinstall then [.handler delimiter] else []) ++ [.restore machine.invocation machine.scope] ++ machine.stack) valid
    (by
      have normal := captured.1
      simp only [captureValues, List.mem_append] at normal
      split <;> simp only [List.flatMap_append, List.flatMap_cons, List.flatMap_nil, frameValues,
        List.append_nil, List.mem_append] <;> grind only [])
    (by
      have queued := captured.2
      split <;> simp only [List.flatMap_append, List.flatMap_cons, List.flatMap_nil, DisposalShape.frame,
        List.append_nil, List.mem_append] <;> grind only [])
  exact next

theorem activateCapture_valid (machine : State) (context : Context) (saved : Capture)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : State)
    (accepted : activateCapture machine context saved successor = .ok after)
    (valid : Valid machine) (captured : CaptureValid machine.heap saved)
    (successorOrdinary : ∀ handler stored bindings, successor = some (handler, stored, bindings) →
      (∀ value ∈ stored, Ordinary value) ∧ (∀ binding ∈ bindings, Ordinary binding.located)) : Valid after := by
  simp only [activateCapture, bind, except_bind_ok, pure, Except.pure] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  cases successor with
  | none =>
    cases accepted
    apply activated_stack_valid _ _ _ _ valid captured
    intro value member
    exact captured.1 value (List.mem_append_left _ (List.mem_append_right _ member))
  | some successor =>
    rcases successor with ⟨handler, stored, bindings⟩
    have ordinary := successorOrdinary handler stored bindings rfl
    simp only [except_bind_ok, Except.ok.injEq] at accepted
    obtain ⟨definition, _, _, _, _, _, _, rfl, rfl⟩ := accepted
    apply activated_stack_valid _ _ _ _ valid captured
    intro value member
    rcases List.mem_append.mp member with environment | state
    · obtain ⟨binding, bindingAt, rfl⟩ := List.mem_map.mp environment
      exact handler_environment_ordinary _ _ _ ordinary.2 binding bindingAt
    · exact ordinary.1 value state

theorem resumeValue_valid (machine : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (accepted : resumeValue machine context token argument successor = .ok after) (valid : Valid machine)
    (successorOrdinary : ∀ handler stored bindings, successor = some (handler, stored, bindings) →
      (∀ value ∈ stored, Ordinary value) ∧ (∀ binding ∈ bindings, Ordinary binding.located)) : Valid after.state := by
  simp only [resumeValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, saved⟩, taken, _, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, active, activated, ⟨temporary, owner⟩, reserved, store, moved, finished⟩ := accepted
  have captured := takeCapture_valid _ _ _ _ taken valid
  have next := activateCapture_valid _ _ _ _ _ activated captured.1 captured.2 successorOrdinary
  have temporaryValid := temporary_valid _ _ _ reserved next
  exact finishTemporary_valid _ _ _ finished (move_valid _ _ _ _ moved temporaryValid.1) (Or.inl temporaryValid.2)

theorem resumeComputation_valid (machine : State) (context : Context) (token computation : Located) (after : Transition)
    (accepted : resumeComputation machine context token computation = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, saved⟩, taken, active, activated, applied⟩ := accepted
  have captured := takeCapture_valid _ _ _ _ taken valid
  have next := activateCapture_valid _ _ _ _ _ activated captured.1 captured.2 (by simp)
  exact applyClosure_valid _ _ _ _ _ applied next

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
    (outer : ∀ binding ∈ bindings, Ordinary binding.located) (ordinary : ∀ value ∈ stored, Ordinary value) : Valid after.state := by
  simp only [installHandler, bind, except_bind_ok] at accepted
  obtain ⟨definition, _, _, _, _, _, _, _, signature, _, _, _, ⟨store, capabilities⟩, allocated, applied⟩ := accepted
  have heap : Valid {machine with heap := store} := by
    apply foldlM_preserves _ _ (fun pair : Heap × List Located => Valid {machine with heap := pair.1}) ?_ _ _ allocated
      (same_storage machine {machine.heap with nextAttachment := machine.heap.nextAttachment + 1} valid rfl rfl)
    intro before item after accepted formed
    rcases before with ⟨heap, capabilities⟩
    rcases item with ⟨clause, schema⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, ⟨next, value⟩, allocated, rfl⟩ := accepted
    exact allocation_valid {machine with heap := heap} _ _ _ _ _ _ allocated formed (by simp [ObjectValid, objectValues, DisposalShape.object])
  let active : Activation := ⟨⟨machine.heap.nextAttachment⟩, handler, handlerEnvironment context definition bindings,
    stored, machine.invocation, machine.scope, (activeAttachments machine.stack).head?⟩
  have activeOrdinary : ∀ value ∈ activationValues active, Ordinary value := by
    intro value member
    rcases List.mem_append.mp member with environment | state
    · obtain ⟨binding, bindingAt, rfl⟩ := List.mem_map.mp environment
      exact handler_environment_ordinary _ _ _ outer binding bindingAt
    · exact ordinary value state
  have next := with_stack {machine with heap := store} (.handler active :: machine.stack) heap
    (by
      have prior := normal_stack {machine with heap := store} heap.1
      simp only [List.flatMap_cons, frameValues, List.mem_append]
      grind only [])
    (by simpa only [List.flatMap_cons, DisposalShape.frame, List.nil_append] using pending_stack {machine with heap := store} heap.2)
  exact applyClosure_valid _ _ _ _ _ applied next

theorem completeHandler_valid (machine : State) (context : Context) (after : Transition)
    (accepted : completeHandler machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold completeHandler at accepted
  split at accepted <;> try contradiction
  rename_i value executing
  split at accepted <;> try contradiction
  rename_i active tail stacked
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨definition, _, _, _, rfl⟩ := accepted
  have normal := normal_frame machine (.handler active) (by simp [stacked]) valid.1
  have result := normal_delivered machine value valid.1 executing
  have next := tail_valid machine tail valid (by intro frame member; simp [stacked, member])
  exact with_control _ (.invoke definition.returnFunction active.environment (active.state ++ [value])) next
    (by
      simp only [frameValues, activationValues, List.mem_append] at normal
      simp only [controlValues, List.mem_append, List.mem_singleton]
      grind only []) (by simp [DisposalShape.control])

theorem enterRegion_valid (machine : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition)
    (accepted : enterRegion machine context descriptor body arguments = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [enterRegion, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, signature, _, schema, _, _, _, ⟨heap, value⟩, allocated, applied⟩ := accepted
  have seed := same_storage machine {machine.heap with nextRegion := machine.heap.nextRegion + 1} valid rfl rfl
  have next := allocation_valid _ _ _ _ _ _ _ allocated seed (by simp [ObjectValid, objectValues, DisposalShape.object])
  have stacked := with_stack {machine with heap := heap} (.region ⟨machine.heap.nextRegion⟩ :: machine.stack) next
    (by simpa only [List.flatMap_cons, frameValues, List.nil_append] using normal_stack {machine with heap := heap} next.1)
    (by simpa only [List.flatMap_cons, DisposalShape.frame, List.nil_append] using pending_stack {machine with heap := heap} next.2)
  exact applyClosure_valid _ _ _ _ _ applied stacked

theorem selected_capture_valid (machine : State) (context : Context) (identity : AttachmentId) (selected : Selection)
    (schema : SchemaId .source) (capabilities : List Located) (cells : List FrozenCell)
    (found : selectAttachment identity machine.stack = some selected) (valid : Valid machine)
    (ordinary : ∀ value ∈ capabilities, Ordinary value) :
    CaptureValid machine.heap ⟨schema, selected.inside.map (trimFrame context), selected.activation, capabilities,
      activeRegions (selected.inside.map (trimFrame context)), cells, machine.scope, machine.invocation⟩ := by
  have shape := selection_reconstructs _ _ _ found
  constructor
  · intro value member
    simp only [captureValues, List.mem_append] at member
    rcases member with (frames | activation) | capability
    · obtain ⟨frame, frameAt, valueAt⟩ := List.mem_flatMap.mp frames
      obtain ⟨original, originalAt, rfl⟩ := List.mem_map.mp frameAt
      exact normal_frame machine original (by simp [shape, originalAt]) valid.1 value
        (trim_frame_normal context original valueAt)
    · exact normal_frame machine (.handler selected.activation) (by simp [shape]) valid.1 value activation
    · exact ordinary value capability
  · intro value member
    obtain ⟨frame, frameAt, valueAt⟩ := List.mem_flatMap.mp member
    obtain ⟨original, originalAt, rfl⟩ := List.mem_map.mp frameAt
    exact pending_frame machine original (by simp [shape, originalAt]) valid.2 value
      ((trim_frame_queued context original) ▸ valueAt)

theorem openRequest_valid (machine : State) (context : Context) (operation : Operation)
    (operands : List Located) (after : Transition)
    (accepted : openRequest machine context operation operands = .ok after) (valid : Valid machine)
    (ordinary : ∀ value ∈ operands, Ordinary value) : Valid after.state := by
  simp only [openRequest, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨effect, _, _, _, payload, _, _, _, accepted⟩ := accepted
  have bodies : ∀ value ∈ ((operands.drop operation.capability.toList.length).drop 1).take operation.bodies.length,
      Ordinary value := by
    intro value member
    exact ordinary value (List.mem_of_mem_drop (List.mem_of_mem_drop (List.mem_of_mem_take member)))
  have capabilities : ∀ value ∈ (operands.drop operation.capability.toList.length).drop (1 + operation.bodies.length),
      Ordinary value := by
    intro value member
    exact ordinary value (List.mem_of_mem_drop (List.mem_of_mem_drop member))
  split at accepted
  · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    let request : Request := ⟨⟨machine.nextOccurrence⟩, operation.effect, payload.value,
      ((operands.drop operation.capability.toList.length).drop 1).take operation.bodies.length,
      (operands.drop operation.capability.toList.length).drop (1 + operation.bodies.length), effect.result⟩
    have next := with_status machine (.parked request) valid (by
      simp only [statusValues, request, List.mem_append]
      grind only [])
    exact next
  · simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, _, accepted⟩ := accepted
    cases stored <;> try contradiction
    rename_i identity nominal looked
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, selected, selectedAt, definition, _, clause, _, accepted⟩ := accepted
    split at accepted
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, _, _, invoked⟩ := accepted
      exact invokeFunction_valid _ _ _ _ _ _ invoked valid
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨shape, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      rename_i signature shapeAt
      obtain ⟨store, moved, accepted⟩ := (except_bind_ok _ _ _).mp accepted
      have moved := (fromOption_ok _ _ _).mp moved
      have storeValid := move_valid _ _ _ _ moved valid
      have objects := ObjectOwners.move_objects _ _ _ _ moved
      have retained := RetainsRetired.of_objects machine.heap store objects
      have captured := selected_capture_valid machine context identity selected clause.resumption _
        (frozenCells store (activeRegions (selected.inside.map (trimFrame context)))) selectedAt valid capabilities
      have outsideValid := tail_valid {machine with heap := store} selected.outside storeValid (by
        intro frame member
        simp [selection_reconstructs _ _ _ selectedAt, member])
      split at accepted
      all_goals
        simp only [except_bind_ok, fromOption_ok] at accepted
        try
          obtain ⟨gate, guard, rest⟩ := accepted
          have _ : Unit := gate
          clear guard
          have accepted := rest
        obtain ⟨⟨outside, owner⟩, reserved, ⟨finalStore, token⟩, allocated, staged, stagedOk, invoked⟩ := accepted
        have temporaryValid := temporary_valid _ _ _ reserved outsideValid
        have temporaryRetained := RetainsRetired.of_objects store outside.heap (ObjectOwners.temporary_objects _ _ _ reserved)
        have finalRetained := (retained.trans temporaryRetained).trans (allocation_retains _ _ _ _ _ _ _ allocated)
        have captured := CaptureValid.mono _ _ _ finalRetained captured
        have created := allocation_valid _ _ _ _ _ _ _ allocated temporaryValid.1 (by
          first | exact captured | (split <;> exact captured))
        have tokenOrdinary := allocation_result_ordinary _ _ _ _ _ _ _ allocated temporaryValid.2
        exact invokeFunction_valid _ _ _ _ _ _ invoked (finishTemporary_valid _ _ _ stagedOk created tokenOrdinary)

theorem executeEffectTerm_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executeEffectTerm machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold executeEffectTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  have outer : ∀ binding ∈ bindings, Ordinary binding.located := by
    intro binding member
    exact normal_control machine valid.1 binding.located (by
      simp only [executing, controlValues, List.mem_append]
      exact Or.inl (List.mem_map.mpr ⟨binding, member, rfl⟩))
  have ordinary : ∀ value ∈ operands, Ordinary value := by
    intro value member
    exact normal_control machine valid.1 value (by simp only [executing, controlValues, List.mem_append]; exact Or.inr member)
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · exact openRequest_valid _ _ _ _ _ accepted valid ordinary
  · split at accepted <;> try contradiction
    exact installHandler_valid _ _ _ _ _ _ _ _ accepted valid outer (by
      intro value member
      exact ordinary value (List.mem_cons_of_mem _ (List.mem_of_mem_drop member)))
  · split at accepted <;> try contradiction
    exact resumeValue_valid _ _ _ _ _ _ accepted valid (by simp)
  · split at accepted <;> try contradiction
    apply resumeValue_valid _ _ _ _ _ _ accepted valid
    intro handler stored environment same
    cases same
    exact ⟨fun value member => ordinary value (by simp [member]), outer⟩
  · split at accepted <;> try contradiction
    exact resumeComputation_valid _ _ _ _ _ accepted valid
  · split at accepted <;> try contradiction
    exact enterRegion_valid _ _ _ _ _ _ accepted valid

end OwnerLocations
end BoundaryV2.Profile.Source.Machine
