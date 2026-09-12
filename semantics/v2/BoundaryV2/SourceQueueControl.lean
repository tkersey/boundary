import BoundaryV2.SourceQueueCalls

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

theorem heapPrimitive_valid (machine : State) (context : Context) (operation : Primitives.GraphOperation)
    (schema : SchemaId .source) (immediate : Nat) (operands : List Located) (after : Transition)
    (formed : Valid machine)
    (ordinary : ∀ value ∈ operands, OwnerLocations.Ordinary value)
    (retiredParents : ∀ pinned ∈ fields machine, OwnerLocations.Retired machine.heap pinned.owner)
    (objects : ObjectOwners.Valid machine.heap)
    (accepted : heapPrimitive machine context operation schema immediate operands = .ok after) : Valid after.state := by
  cases operation <;> simp only [heapPrimitive, bind, except_bind_ok, fromOption_ok] at accepted
  case computation =>
    obtain ⟨_, _, _, _, accepted⟩ := accepted
    exact makeClosureWithValues_valid _ _ _ _ _ _ accepted formed (fun value member => ordinary_separate _ _ (ordinary value member))
  case cellNew =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, ⟨middle, owner⟩, temporaryOk, moved, moveOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have temporary := temporary_valid _ _ _ temporaryOk formed
    have movedValid := move_ordinary_valid _ _ _ _ moveOk temporary (by grind only [List.mem_cons, List.not_mem_nil])
    have staged := same_storage_valid {middle with heap := moved} {moved with nextCell := moved.nextCell + 1} movedValid rfl rfl
    have next := allocate_empty_valid _ _ _ _ _ _ _ allocated staged rfl
    exact finishTemporary_valid _ _ _ finished next
  case cellGet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact scopedValue_valid _ _ _ accepted formed
  case cellSet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, store, replaced, accepted⟩ := accepted
    have next := replace_empty_valid _ _ _ _ _ (CellStability.lookupObject_reference _ _ _ _ looked).2 replaced formed rfl rfl
    exact scopedValue_valid _ _ _ accepted next
  case package =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, ⟨middle, owner⟩, temporaryOk, moved, moveOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have temporary := temporary_valid _ _ _ temporaryOk formed
    have movedValid := move_ordinary_valid _ _ _ _ moveOk temporary (by grind only [List.mem_cons, List.not_mem_nil])
    have next := allocate_empty_valid _ _ _ _ _ _ _ allocated movedValid rfl
    exact finishTemporary_valid _ _ _ finished next
  case unpack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, store, retired, accepted⟩ := accepted
    have found := (CellStability.lookupObject_reference _ _ _ _ looked).2
    have separate := live_parent_separate machine _ node 0 _ (objects node _ found) found retiredParents
    apply commitPure_valid _ _ _ _ _ accepted
      (retire_ordinary_valid _ _ _ retired formed (by grind only [List.mem_cons, List.not_mem_nil]))
    intro value member
    simp only [List.mem_singleton] at member
    subst value
    exact separate_sublist _ _ _ (retired_fields_sublist _ _ _ retired) separate
  case cloneResumption =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    rename_i saved
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, cloneChecked, retired, retireOk, ⟨middle, owner⟩, temporaryOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have safe := (clone_safe_has_no_captured_custody _ _ _ (require_ok _ _ _ cloneChecked)).1
    have retiredValid := retire_ordinary_valid _ _ _ retireOk formed (by grind only [List.mem_cons, List.not_mem_nil])
    have temporary := temporary_valid _ _ _ temporaryOk retiredValid
    have next := allocate_empty_valid _ _ _ _ _ _ _ allocated temporary (by
      simp only [objectFields, DisposalShape.object, OwnerLocations.clone_capture_has_no_queue context.source saved safe, List.filter_nil])
    exact finishTemporary_valid _ _ _ finished next
  case resourcePack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, ⟨middle, owner⟩, temporaryOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have temporary := temporary_valid _ _ _ temporaryOk formed
    have next := allocate_empty_valid _ _ _ _ _ _ _ allocated temporary rfl
    exact finishTemporary_valid _ _ _ finished next
  case resourceUnpack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, ⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    case resource =>
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, store, retired, accepted⟩ := accepted
      exact scopedValue_valid _ _ _ accepted (retire_ordinary_valid _ _ _ retired formed (by grind only [List.mem_cons, List.not_mem_nil]))
    case borrow =>
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      exact scopedValue_valid _ _ _ accepted formed

theorem authoredFailure_valid (machine : State) (context : Context)
    (failures : List (InstructionFailure .source)) (fault : Fault) (after : Transition)
    (valid : Valid machine)
    (accepted : authoredFailure machine context failures fault = .ok after) : Valid after.state := by
  simp only [authoredFailure, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  exact empty_control_valid machine _ valid rfl

theorem executePrimitive_valid (machine : State) (context : Context) (after : Transition)
    (valid : Valid machine) (owners : OwnerLocations.Valid machine) (leaves : DisposalShape.Valid machine)
    (objects : ObjectOwners.Valid machine.heap)
    (accepted : executePrimitive machine context = .ok after) : Valid after.state := by
  unfold executePrimitive at accepted
  split at accepted <;> try contradiction
  rename_i schema opcode immediate failures bindings operands executing
  have ordinary : ∀ value ∈ operands, OwnerLocations.Ordinary value := by
    intro value member
    exact OwnerLocations.normal_control machine owners.1 value (by
      simp only [executing, OwnerLocations.controlValues]
      exact List.mem_append_right _ member)
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · exact authoredFailure_valid _ _ _ _ _ valid accepted
  · exact commitPure_valid _ _ _ _ _ accepted valid (fun value member => ordinary_separate _ _ (ordinary value member))
  · exact heapPrimitive_valid _ _ _ _ _ _ _ valid ordinary (fields_retired _ owners leaves) objects accepted

theorem enterTerm_valid (machine : State) (source : Module) (after : Transition)
    (accepted : enterTerm machine source = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold enterTerm at accepted
  split at accepted <;> try contradiction
  rename_i reference bindings executing
  split at accepted <;> try contradiction
  rename_i term found
  cases term <;> simp only at accepted
  all_goals try (split at accepted)
  all_goals cases accepted
  all_goals simpa only [Valid, fields_components, controlFields, frameFields, DisposalShape.control,
    DisposalShape.frame, executing, List.flatMap_cons, List.filter_nil, List.nil_append] using valid

theorem deliverOperand_valid (machine : State) (after : Transition)
    (accepted : deliverOperand machine = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold deliverOperand at accepted
  split at accepted <;> try contradiction
  rename_i value executing
  split at accepted <;> try contradiction
  rename_i intent bindings remaining evaluated tail stacked
  split at accepted
  all_goals cases accepted
  all_goals simpa only [Valid, fields_components, controlFields, frameFields, DisposalShape.control,
    DisposalShape.frame, executing, stacked, List.flatMap_cons, List.filter_nil, List.nil_append] using valid

theorem enterExpression_valid (machine : State) (context : Context) (after : Transition)
    (accepted : enterExpression machine context = .ok after) (valid : Valid machine)
    (owners : OwnerLocations.Valid machine) : Valid after.state := by
  unfold enterExpression at accepted
  split at accepted <;> try contradiction
  rename_i reference bindings executing
  have outer : ∀ binding ∈ bindings, Separate machine binding.located := by
    intro binding member
    apply ordinary_separate
    apply OwnerLocations.normal_control machine owners.1
    simp only [executing, OwnerLocations.controlValues]
    exact List.mem_map.mpr ⟨binding, member, rfl⟩
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨schema, expression⟩, _, accepted⟩ := accepted
  cases expression with
  | «variable» binder =>
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨value, _, _, _, _, _, rfl⟩ := accepted
    exact empty_control_valid machine (.delivered value) valid rfl
  | literal constant =>
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, accepted⟩ := accepted
    exact scopedValue_valid _ _ _ accepted valid
  | lambda function => exact makeClosure_valid _ _ _ _ _ _ accepted valid outer
  | primitive opcode operands immediate failures =>
    cases operands <;> cases accepted
    all_goals simpa only [Valid, fields_components, controlFields, frameFields, DisposalShape.control,
      DisposalShape.frame, executing, List.flatMap_cons, List.filter_nil, List.nil_append] using valid

theorem enterInvocation_valid (machine : State) (context : Context) (after : Transition)
    (accepted : enterInvocation machine context = .ok after) (valid : Valid machine)
    (owners : OwnerLocations.Valid machine) : Valid after.state := by
  unfold enterInvocation at accepted
  split at accepted <;> try contradiction
  rename_i function bindings arguments executing
  apply invokeFunction_valid _ _ _ _ _ _ accepted valid
  · intro binding member
    apply ordinary_separate
    exact OwnerLocations.normal_control machine owners.1 binding.located (by
      simp only [executing, OwnerLocations.controlValues]
      exact List.mem_append_left _ (List.mem_map.mpr ⟨binding, member, rfl⟩))
  · intro value member
    apply ordinary_separate
    exact OwnerLocations.normal_control machine owners.1 value (by
      simp only [executing, OwnerLocations.controlValues]
      exact List.mem_append_right _ member)

theorem stack_fields_valid (machine : State) (next : List Frame) (valid : Valid machine)
    (same : next.flatMap frameFields = machine.stack.flatMap frameFields) : Valid {machine with stack := next} := by
  simpa only [Valid, fields_components, same] using valid

theorem enterBinding_valid (machine : State) (context : Context) (after : Transition)
    (accepted : enterBinding machine context = .ok after) (valid : Valid machine)
    (owners : OwnerLocations.Valid machine) : Valid after.state := by
  unfold enterBinding at accepted
  split at accepted <;> try contradiction
  rename_i value executing
  split at accepted <;> try contradiction
  rename_i binder body bindings parent tail stacked
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, created, rfl⟩ := accepted
  have separate := ordinary_separate machine value (OwnerLocations.normal_delivered machine value owners.1 executing)
  have next := createScope_valid _ _ _ _ _ _ _ _ created valid (by simpa using separate)
  have stackSame : middle.stack = machine.stack := next.2.2.1
  have stackedValid := stack_fields_valid middle (if middle.scope == parent then tail else .lexical middle.scope :: tail) next.1 (by
    split <;> simp only [stackSame, stacked, List.flatMap_cons, frameFields, DisposalShape.frame, List.filter_nil, List.nil_append])
  exact empty_control_valid _ (.term body entered) stackedValid rfl

theorem enterPattern_valid (machine : State) (context : Context) (vars : List VariableId)
    (parts : List SemanticValue) (owner : Custody.Owner) (body : TermId) (bindings : Environment) (after : Transition)
    (accepted : enterPattern machine context vars parts owner body bindings = .ok after)
    (valid : Valid machine) (separate : ∀ part ∈ parts, Separate machine ⟨part, owner⟩) : Valid after.state := by
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, created, rfl⟩ := accepted
  have next := createScope_valid _ _ _ _ _ _ _ _ created valid (by
    intro value member
    obtain ⟨part, partAt, rfl⟩ := List.mem_map.mp member
    exact separate part partAt)
  have stackSame : middle.stack = machine.stack := next.2.2.1
  have stackedValid := stack_fields_valid middle (if middle.scope == machine.scope then machine.stack else .lexical middle.scope :: machine.stack) next.1 (by
    split <;> simp only [stackSame, List.flatMap_cons, frameFields, DisposalShape.frame, List.filter_nil, List.nil_append])
  exact empty_control_valid _ (.term body entered) stackedValid rfl

theorem ordinary_variant_payload (schema : SchemaId .source) (tag : Nat) (payload : SemanticValue) (owner : Custody.Owner)
    (ordinary : OwnerLocations.Ordinary ⟨.variant schema tag payload, owner⟩) : OwnerLocations.Ordinary ⟨payload, owner⟩ := by
  simpa only [OwnerLocations.Ordinary, ownedTokens] using ordinary

theorem ordinary_product_parts (schema : SchemaId .source) (parts : List SemanticValue) (owner : Custody.Owner)
    (ordinary : OwnerLocations.Ordinary ⟨.product schema parts, owner⟩) :
    ∀ part ∈ parts, OwnerLocations.Ordinary ⟨part, owner⟩ := by
  intro part member
  rcases ordinary with inScope | free
  · exact Or.inl inScope
  · simp only [ownedTokens] at free
    exact Or.inr (List.flatMap_eq_nil_iff.mp free part member)

theorem executeControlTerm_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executeControlTerm machine context = .ok after) (valid : Valid machine)
    (owners : OwnerLocations.Valid machine) (leaves : DisposalShape.Valid machine)
    (objects : ObjectOwners.Valid machine.heap) : Valid after.state := by
  unfold executeControlTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  have ordinary : ∀ value ∈ operands, OwnerLocations.Ordinary value := by
    intro value member
    exact OwnerLocations.normal_control machine owners.1 value (by
      simp only [executing, OwnerLocations.controlValues]
      exact List.mem_append_right _ member)
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    exact empty_control_valid _ _ valid rfl
  · cases accepted; exact empty_control_valid _ _ valid rfl
  · split at accepted <;> try contradiction
    apply applyClosure_valid _ _ _ _ _ accepted valid
      (ordinary_separate _ _ (by grind only [List.mem_cons, List.not_mem_nil]))
      ?_ (fields_retired machine owners leaves) objects
    intro value member
    exact ordinary_separate _ _ (by grind only [List.mem_cons, List.not_mem_nil])
  · split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, rfl⟩ := accepted
    exact empty_control_valid _ _ valid rfl
  · split at accepted <;> try contradiction
    rename_i schema tag payload owner operandsAt
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨binder, body⟩, _, accepted⟩ := accepted
    apply enterPattern_valid _ _ _ _ _ _ _ _ accepted valid
    intro part member
    simp only [List.mem_singleton] at member
    subst part
    exact ordinary_separate _ _ (ordinary_variant_payload schema tag payload owner (by
      apply ordinary
      simp))
  · split at accepted <;> try contradiction
    rename_i schema parts owner operandsAt
    apply enterPattern_valid _ _ _ _ _ _ _ _ accepted valid
    intro part member
    exact ordinary_separate _ _ (ordinary_product_parts schema parts owner (by
      apply ordinary
      simp) part member)

theorem leaveScope_valid (machine : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition)
    (accepted : leaveScope machine parent invocation tail value = .ok after) (valid : Valid machine)
    (included : tail.Sublist machine.stack) (ordinary : OwnerLocations.Ordinary value) : Valid after.state := by
  simp only [leaveScope, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, owner⟩, reserved, heap, moved, delivered, finished, rfl⟩ := accepted
  have entered : Valid {machine with scope := parent, invocation := invocation, stack := tail} :=
    substack_valid machine tail valid included
  have next := temporary_valid _ _ _ reserved entered
  have movedValid := move_ordinary_valid _ _ _ _ moved next (by simpa using ordinary)
  exact empty_control_valid _ _ (finishTemporary_valid _ _ _ finished movedValid) rfl

theorem leaveInvocation_valid (machine : State) (after : Transition)
    (accepted : leaveInvocation machine = .ok after) (valid : Valid machine)
    (owners : OwnerLocations.Valid machine) : Valid after.state := by
  unfold leaveInvocation at accepted
  split at accepted <;> try contradiction
  rename_i value executing
  split at accepted <;> try contradiction
  rename_i caller parent tail stacked
  exact leaveScope_valid _ _ _ _ _ _ accepted valid (by rw [stacked]; exact List.sublist_cons_self _ _)
    (OwnerLocations.normal_delivered machine value owners.1 executing)

theorem restoreResumeCaller_valid (machine : State) (after : Transition)
    (accepted : restoreResumeCaller machine = .ok after) (valid : Valid machine)
    (owners : OwnerLocations.Valid machine) : Valid after.state := by
  unfold restoreResumeCaller at accepted
  split at accepted <;> try contradiction
  rename_i value executing
  split at accepted <;> try contradiction
  rename_i caller parent tail stacked
  have entered : Valid {machine with scope := parent, invocation := caller, stack := tail} :=
    substack_valid machine tail valid (by rw [stacked]; exact List.sublist_cons_self _ _)
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨middle, owner⟩, reserved, heap, moved, finished⟩ := accepted
  have next := temporary_valid _ _ _ reserved entered
  exact finishTemporary_valid _ _ _ finished (move_ordinary_valid _ _ _ _ moved next (by
    simpa using OwnerLocations.normal_delivered machine value owners.1 executing))

theorem leaveLexical_valid (machine : State) (after : Transition)
    (accepted : leaveLexical machine = .ok after) (valid : Valid machine)
    (owners : OwnerLocations.Valid machine) : Valid after.state := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  rename_i value executing
  split at accepted <;> try contradiction
  rename_i scope tail stacked
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, record, recordAt, parent, _, result, left, accepted⟩ := accepted
  have next := leaveScope_valid _ _ _ _ _ _ left valid (by rw [stacked]; exact List.sublist_cons_self _ _)
    (OwnerLocations.normal_delivered machine value owners.1 executing)
  split at accepted <;> try contradiction
  rename_i departed delivered deliveredAt
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨parentRecord, _, heap, moved, rfl⟩ := accepted
  have holdings := (OwnerLocations.heap_valid machine owners).2 record (List.mem_of_getElem? recordAt)
  have movedValid := move_ordinary_valid _ _ _ _ moved next (by
    intro child member
    obtain ⟨original, originalAt, childAt⟩ := List.mem_flatMap.mp member
    exact OwnerLocations.ordinary_liveOwned result.state.heap original (holdings original originalAt) child childAt)
  have finished := empty_control_valid {result.state with heap := heap} (.delivered delivered) movedValid rfl
  simpa only [Valid, fields_components, Linear, current, heapFields] using finished

theorem ordinary_live_fields_empty (heap : Heap) (value : Located) (ordinary : OwnerLocations.Ordinary value) :
    (liveOwned heap value).filter (fun value => closureOwner value.owner) = [] :=
  ordinary_fields_empty _ (OwnerLocations.ordinary_liveOwned heap value ordinary)
    (DisposalProgress.liveOwnedValue_leaf heap value.owner value.value)

theorem ordinary_lives_fields_empty (heap : Heap) (values : List Located)
    (ordinary : ∀ value ∈ values, OwnerLocations.Ordinary value) :
    (values.flatMap (liveOwned heap)).filter (fun value => closureOwner value.owner) = [] := by
  rw [List.filter_flatMap]
  exact List.flatMap_eq_nil_iff.mpr (fun value member => ordinary_live_fields_empty heap value (ordinary value member))

theorem releaseScope_valid (machine : State) (after : Transition)
    (accepted : releaseScope machine = .ok after) (valid : Valid machine)
    (owners : OwnerLocations.Valid machine) : Valid after.state := by
  unfold releaseScope at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨record, found, _, _, rfl⟩ := accepted
  have holdings := (OwnerLocations.heap_valid machine owners).2 record (List.mem_of_getElem? found)
  exact empty_control_valid machine _ valid (ordinary_lives_fields_empty machine.heap record.holdings holdings)

theorem finishDisposal_valid (machine : State) (after : Transition)
    (accepted : finishDisposal machine = .ok after) (valid : Valid machine)
    (owners : OwnerLocations.Valid machine) : Valid after.state := by
  unfold finishDisposal at accepted
  split at accepted <;> try contradiction
  rename_i value executing
  split at accepted <;> try contradiction
  rename_i remaining released invocation scope tail stacked
  cases accepted
  have empty := ordinary_live_fields_empty machine.heap value (OwnerLocations.normal_delivered machine value owners.1 executing)
  simpa only [Valid, fields_components, controlFields, frameFields, DisposalShape.control, DisposalShape.frame,
    executing, stacked, List.filter_append, empty, List.filter_nil, List.flatMap_cons, List.nil_append] using valid

end QueueCustody
end BoundaryV2.Profile.Source.Machine
