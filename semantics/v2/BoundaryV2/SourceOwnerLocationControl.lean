import BoundaryV2.SourceOwnerLocationStorage

namespace BoundaryV2.Profile.Source.Machine
namespace OwnerLocations

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

theorem authoredFailure_valid (machine : State) (context : Context)
    (failures : List (InstructionFailure .source)) (fault : Fault) (after : Transition)
    (formed : Valid machine)
    (accepted : authoredFailure machine context failures fault = .ok after) : Valid after.state := by
  simp only [authoredFailure, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  exact with_control machine _ formed (by simp [controlValues]) (by simp [DisposalShape.control])

theorem heapPrimitive_valid (machine : State) (context : Context) (operation : Primitives.GraphOperation)
    (schema : SchemaId .source) (immediate : Nat) (operands : List Located) (after : Transition)
    (formed : Valid machine)
    (accepted : heapPrimitive machine context operation schema immediate operands = .ok after) : Valid after.state := by
  cases operation <;> simp only [heapPrimitive, bind, except_bind_ok, fromOption_ok] at accepted
  case computation =>
    obtain ⟨_, _, _, _, accepted⟩ := accepted
    exact makeClosureWithValues_valid _ _ _ _ _ _ accepted formed
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
    have movedValid := move_valid _ _ _ _ moveOk temporary.1
    have staged := same_storage {middle with heap := moved} {moved with nextCell := moved.nextCell + 1} movedValid rfl rfl
    have next := allocation_valid _ _ _ _ _ _ _ allocated staged (by simp [ObjectValid, objectValues, DisposalShape.object])
    exact finishTemporary_valid _ _ _ finished next (allocation_result_ordinary _ _ _ _ _ _ _ allocated temporary.2)
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
    have next := replace_valid _ _ _ _ _ (CellStability.lookupObject_reference _ _ _ _ looked).2 replaced formed
      (by simp [ObjectValid, objectValues, DisposalShape.object])
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
    have movedValid := move_valid _ _ _ _ moveOk temporary.1
    have next := allocation_valid _ _ _ _ _ _ _ allocated movedValid (by simp [ObjectValid, objectValues, DisposalShape.object])
    exact finishTemporary_valid _ _ _ finished next (allocation_result_ordinary _ _ _ _ _ _ _ allocated temporary.2)
  case unpack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, store, retired, accepted⟩ := accepted
    exact commitPure_valid _ _ _ _ _ accepted (retire_valid _ _ _ retired formed)
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
    have retiredValid := retire_valid _ _ _ retireOk formed
    have temporary := temporary_valid _ _ _ temporaryOk retiredValid
    have next := allocation_valid _ _ _ _ _ _ _ allocated temporary.1
      (clone_capture_valid context.source store saved safe)
    exact finishTemporary_valid _ _ _ finished next (allocation_result_ordinary _ _ _ _ _ _ _ allocated temporary.2)
  case resourcePack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, ⟨middle, owner⟩, temporaryOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have temporary := temporary_valid _ _ _ temporaryOk formed
    have next := allocation_valid _ _ _ _ _ _ _ allocated temporary.1 (by simp [ObjectValid, objectValues, DisposalShape.object])
    exact finishTemporary_valid _ _ _ finished next (allocation_result_ordinary _ _ _ _ _ _ _ allocated temporary.2)
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
      exact scopedValue_valid _ _ _ accepted (retire_valid _ _ _ retired formed)
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

theorem executePrimitive_valid (machine : State) (context : Context) (after : Transition)
    (formed : Valid machine)
    (accepted : executePrimitive machine context = .ok after) : Valid after.state := by
  unfold executePrimitive at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · exact authoredFailure_valid _ _ _ _ _ formed accepted
  · exact commitPure_valid _ _ _ _ _ accepted formed
  · exact heapPrimitive_valid _ _ _ _ _ _ _ formed accepted



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
  all_goals simp only [Valid, Normal, Pending, ordinaryValues, queuedValues, executing,
    controlValues, frameValues, statusValues, DisposalShape.control, DisposalShape.frame,
    List.flatMap_cons, List.nil_append, List.append_nil, List.mem_append] at valid ⊢
  all_goals grind only []

theorem deliverOperand_valid (machine : State) (after : Transition)
    (accepted : deliverOperand machine = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold deliverOperand at accepted
  split at accepted <;> try contradiction
  rename_i value executing
  split at accepted <;> try contradiction
  rename_i intent bindings remaining evaluated tail stacked
  split at accepted
  all_goals cases accepted
  all_goals simp only [Valid, Normal, Pending, ordinaryValues, queuedValues, executing, stacked,
    controlValues, frameValues, DisposalShape.control, DisposalShape.frame,
    List.flatMap_cons, List.nil_append, List.mem_append,
    List.mem_singleton] at valid ⊢
  all_goals grind only []

theorem lookup_variable_ordinary (bindings : Environment) (binder : VariableId) (value : Located)
    (found : lookupVariable bindings binder = some value)
    (valid : ∀ binding ∈ bindings, Ordinary binding.located) : Ordinary value := by
  unfold lookupVariable at found
  obtain ⟨binding, bindingAt, rfl⟩ := Option.map_eq_some_iff.mp found
  exact valid binding (List.mem_of_find?_eq_some bindingAt)

theorem enterExpression_valid (machine : State) (context : Context) (after : Transition)
    (accepted : enterExpression machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold enterExpression at accepted
  split at accepted <;> try contradiction
  rename_i reference bindings executing
  have outer : ∀ binding ∈ bindings, Ordinary binding.located := by
    intro binding member
    apply normal_control machine valid.1
    simp only [executing, controlValues]
    exact List.mem_map.mpr ⟨binding, member, rfl⟩
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨schema, expression⟩, _, accepted⟩ := accepted
  cases expression with
  | «variable» binder =>
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨value, found, _, _, _, _, rfl⟩ := accepted
    exact with_control machine (.delivered value) valid
      (by simpa [controlValues] using lookup_variable_ordinary bindings binder value found outer)
      (by simp [DisposalShape.control])
  | literal constant =>
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, accepted⟩ := accepted
    exact scopedValue_valid _ _ _ accepted valid
  | lambda function => exact makeClosure_valid _ _ _ _ _ _ accepted valid
  | primitive opcode operands immediate failures =>
    cases operands <;> cases accepted
    all_goals simp only [Valid, Normal, Pending, ordinaryValues, queuedValues, executing,
      controlValues, frameValues, DisposalShape.control, DisposalShape.frame,
      List.flatMap_cons, List.nil_append, List.append_nil, List.mem_append] at valid ⊢
    all_goals grind only []

theorem enterInvocation_valid (machine : State) (context : Context) (after : Transition)
    (accepted : enterInvocation machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold enterInvocation at accepted
  split at accepted <;> try contradiction
  exact invokeFunction_valid _ _ _ _ _ _ accepted valid

theorem normal_frame (machine : State) (frame : Frame) (member : frame ∈ machine.stack)
    (valid : Normal machine) : ∀ value ∈ frameValues frame, Ordinary value := by
  intro value valueAt
  exact normal_stack machine valid value (List.mem_flatMap.mpr ⟨frame, member, valueAt⟩)

theorem pending_frame (machine : State) (frame : Frame) (member : frame ∈ machine.stack)
    (valid : Pending machine) : ∀ value ∈ DisposalShape.frame frame, Queued machine.heap value := by
  intro value valueAt
  exact pending_stack machine valid value (List.mem_flatMap.mpr ⟨frame, member, valueAt⟩)

theorem tail_valid (machine : State) (tail : List Frame) (valid : Valid machine)
    (included : ∀ frame ∈ tail, frame ∈ machine.stack) : Valid {machine with stack := tail} := by
  apply with_stack machine tail valid
  · intro value member
    obtain ⟨frame, frameAt, valueAt⟩ := List.mem_flatMap.mp member
    exact normal_frame machine frame (included frame frameAt) valid.1 value valueAt
  · intro value member
    obtain ⟨frame, frameAt, valueAt⟩ := List.mem_flatMap.mp member
    exact pending_frame machine frame (included frame frameAt) valid.2 value valueAt

theorem normal_delivered (machine : State) (value : Located) (valid : Normal machine)
    (executing : machine.control = .delivered value) : Ordinary value :=
  normal_control machine valid value (by simp [executing, controlValues])

theorem enterBinding_valid (machine : State) (context : Context) (after : Transition)
    (accepted : enterBinding machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold enterBinding at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i binder body bindings parent tail stacked
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, created, rfl⟩ := accepted
  have outer : ∀ binding ∈ bindings, Ordinary binding.located := by
    intro binding member
    exact normal_frame machine (.binding binder body bindings parent) (by simp [stacked]) valid.1 binding.located (by
      simpa only [frameValues] using List.mem_map.mpr ⟨binding, member, rfl⟩)
  have next := createScope_valid _ _ _ _ _ _ _ _ created valid outer
  have retained := RetainsRetired.of_objects machine.heap middle.heap next.2.2
  have normalTail : ∀ value ∈ tail.flatMap frameValues, Ordinary value := by
    intro value member
    exact normal_stack machine valid.1 value (by simp only [stacked, List.flatMap_cons, List.mem_append]; exact Or.inr member)
  have queuedTail : ∀ value ∈ tail.flatMap DisposalShape.frame, Queued middle.heap value := by
    intro value member
    apply queued_mono _ _ _ retained
    exact pending_stack machine valid.2 value (by simp only [stacked, List.flatMap_cons, DisposalShape.frame, List.nil_append]; exact member)
  have stack := with_stack middle (if middle.scope == parent then tail else .lexical middle.scope :: tail) next.1
    (by split <;> simpa [List.flatMap_cons, frameValues] using normalTail)
    (by split <;> simpa [List.flatMap_cons, DisposalShape.frame] using queuedTail)
  exact with_control _ (.term body entered) stack (by
    intro value member
    obtain ⟨binding, bindingAt, rfl⟩ := List.mem_map.mp member
    exact next.2.1 binding bindingAt) (by simp [DisposalShape.control])

theorem enterPattern_valid (machine : State) (context : Context) (vars : List VariableId)
    (parts : List SemanticValue) (owner : Custody.Owner) (body : TermId) (bindings : Environment) (after : Transition)
    (accepted : enterPattern machine context vars parts owner body bindings = .ok after)
    (valid : Valid machine) (outer : ∀ binding ∈ bindings, Ordinary binding.located) : Valid after.state := by
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, created, rfl⟩ := accepted
  have next := createScope_valid _ _ _ _ _ _ _ _ created valid outer
  have retained := RetainsRetired.of_objects machine.heap middle.heap next.2.2
  have queued : ∀ value ∈ machine.stack.flatMap DisposalShape.frame, Queued middle.heap value := by
    intro value member
    exact queued_mono _ _ _ retained (pending_stack machine valid.2 value member)
  have stack := with_stack middle (if middle.scope == machine.scope then machine.stack else .lexical middle.scope :: machine.stack) next.1
    (by split <;> simpa [List.flatMap_cons, frameValues] using normal_stack machine valid.1)
    (by split <;> simpa [List.flatMap_cons, DisposalShape.frame] using queued)
  exact with_control _ (.term body entered) stack (by
    intro value member
    obtain ⟨binding, bindingAt, rfl⟩ := List.mem_map.mp member
    exact next.2.1 binding bindingAt) (by simp [DisposalShape.control])

theorem executeControlTerm_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executeControlTerm machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold executeControlTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  have outer : ∀ binding ∈ bindings, Ordinary binding.located := by
    intro binding member
    apply normal_control machine valid.1
    simp only [executing, controlValues, List.mem_append]
    exact Or.inl (List.mem_map.mpr ⟨binding, member, rfl⟩)
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    apply with_control _ _ valid
    · intro value member
      obtain ⟨binding, bindingAt, rfl⟩ := List.mem_map.mp member
      exact outer binding bindingAt
    · simp [DisposalShape.control]
  · cases accepted
    exact with_control _ _ valid (by simpa only [executing, controlValues] using normal_control machine valid.1)
      (by simp [DisposalShape.control])
  · split at accepted <;> try contradiction
    exact applyClosure_valid _ _ _ _ _ accepted valid
  · split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, rfl⟩ := accepted
    exact with_control _ _ valid (by simp [controlValues]) (by simp [DisposalShape.control])
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨binder, body⟩, _, accepted⟩ := accepted
    exact enterPattern_valid _ _ _ _ _ _ _ _ accepted valid outer
  · split at accepted <;> try contradiction
    exact enterPattern_valid _ _ _ _ _ _ _ _ accepted valid outer

theorem leaveScope_valid (machine : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition)
    (accepted : leaveScope machine parent invocation tail value = .ok after) (valid : Valid machine)
    (included : ∀ frame ∈ tail, frame ∈ machine.stack) : Valid after.state := by
  simp only [leaveScope, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, owner⟩, reserved, heap, moved, delivered, finished, rfl⟩ := accepted
  have entered : Valid {machine with scope := parent, invocation := invocation, stack := tail} :=
    tail_valid machine tail valid included
  have next := temporary_valid _ _ _ reserved entered
  have movedValid := move_valid _ _ _ _ moved next.1
  have resultOrdinary : Ordinary (retainAt value owner) := Or.inl next.2
  have result := finishTemporary_valid _ _ _ finished movedValid resultOrdinary
  exact with_control _ _ result (by simpa [controlValues, afterValues] using resultOrdinary)
    (by simp [DisposalShape.control])

theorem leaveInvocation_valid (machine : State) (after : Transition)
    (accepted : leaveInvocation machine = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold leaveInvocation at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i caller parent tail stacked
  exact leaveScope_valid _ _ _ _ _ _ accepted valid (by intro frame member; simp [stacked, member])

theorem restoreResumeCaller_valid (machine : State) (after : Transition)
    (accepted : restoreResumeCaller machine = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold restoreResumeCaller at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i caller parent tail stacked
  have entered : Valid {machine with scope := parent, invocation := caller, stack := tail} :=
    tail_valid machine tail valid (by intro frame member; simp [stacked, member])
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨middle, owner⟩, reserved, heap, moved, finished⟩ := accepted
  have next := temporary_valid _ _ _ reserved entered
  exact finishTemporary_valid _ _ _ finished (move_valid _ _ _ _ moved next.1) (Or.inl next.2)

theorem leaveLexical_valid (machine : State) (after : Transition)
    (accepted : leaveLexical machine = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i scope tail stacked
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, record, _, parent, _, result, left, accepted⟩ := accepted
  have next := leaveScope_valid _ _ _ _ _ _ left valid (by intro frame member; simp [stacked, member])
  split at accepted <;> try contradiction
  rename_i departed delivered executing
  have resultOrdinary : Ordinary delivered := normal_control result.state next.1 delivered
    (by simp [executing, controlValues, afterValues])
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨parentRecord, found, heap, moved, rfl⟩ := accepted
  have parentOrdinary := (heap_valid result.state next).2 parentRecord (List.mem_of_getElem? found)
  have movedValid := move_valid _ _ _ _ moved next
  have stored := set_scope {result.state with heap := heap} parent.value
    {parentRecord with
      nextOwner := parentRecord.nextOwner + (record.holdings.flatMap (liveOwned result.state.heap)).length
      holdings := (record.holdings.flatMap (liveOwned result.state.heap)).mapIdx
        (fun index located => retainAt located (.temporary parent (parentRecord.nextOwner + index))) ++ parentRecord.holdings}
    movedValid (by
      intro value member
      rcases List.mem_append.mp member with added | original
      · obtain ⟨index, _, rfl⟩ := List.exists_of_mem_mapIdx added
        exact Or.inl trivial
      · exact parentOrdinary value original)
  exact with_control _ (.delivered delivered) stored (by simpa [controlValues] using resultOrdinary)
    (by simp [DisposalShape.control])

theorem releaseScope_valid (machine : State) (after : Transition)
    (accepted : releaseScope machine = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold releaseScope at accepted
  split at accepted <;> try contradiction
  rename_i scope released executing
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨record, found, _, _, rfl⟩ := accepted
  have holdings := (heap_valid machine valid).2 record (List.mem_of_getElem? found)
  apply with_control machine _ valid
  · simpa only [executing, controlValues] using normal_control machine valid.1
  · intro value member
    obtain ⟨original, originalAt, valueAt⟩ := List.mem_flatMap.mp member
    exact Or.inl (ordinary_liveOwned machine.heap original (holdings original originalAt) value valueAt)

theorem finishDisposal_valid (machine : State) (after : Transition)
    (accepted : finishDisposal machine = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold finishDisposal at accepted
  split at accepted <;> try contradiction
  rename_i value executing
  split at accepted <;> try contradiction
  rename_i remaining released invocation scope tail stacked
  cases accepted
  have result := normal_delivered machine value valid.1 executing
  have ordinary := normal_frame machine (.disposalReturn remaining released invocation scope)
    (by simp [stacked]) valid.1
  have pending := pending_frame machine (.disposalReturn remaining released invocation scope)
    (by simp [stacked]) valid.2
  have next := tail_valid machine tail valid (by intro frame member; simp [stacked, member])
  have finished := with_control {machine with stack := tail} (.discard (liveOwned machine.heap value ++ remaining) released) next
    ordinary (by
      intro child member
      rcases List.mem_append.mp member with childAt | rest
      · exact Or.inl (ordinary_liveOwned machine.heap value result child childAt)
      · exact pending child rest)
  exact finished

theorem retire_target (machine : State) (value : Located) (node : NodeId) (stored : Object) (heap : Heap)
    (looked : lookupObject machine value = .ok (node, stored))
    (accepted : retireObject machine.heap value = some heap) :
    node.value < heap.objects.length ∧ heap.lookup node = none := by
  obtain ⟨⟨schema, token, reference⟩, found⟩ := CellStability.lookupObject_reference _ _ _ _ looked
  have bounded : node.value < machine.heap.objects.length := by
    simp only [Heap.lookup, Option.bind_eq_some_iff] at found
    obtain ⟨entry, entryAt, _⟩ := found
    exact (List.getElem?_eq_some_iff.mp entryAt).1
  unfold retireObject at accepted
  rw [reference] at accepted
  cases token <;> try contradiction
  simp only [bind, Option.bind_eq_some_iff, pure, Option.some.injEq] at accepted
  obtain ⟨_, _, middle, consumed, rfl⟩ := accepted
  have same := ObjectOwners.consume_objects _ _ _ consumed
  refine ⟨by simpa only [List.length_set, same] using bounded, ?_⟩
  simp only [Heap.lookup, List.getElem?_set_self (show node.value < middle.objects.length by simpa only [same] using bounded), Option.bind_some]
  rfl

theorem discardValues_valid (machine : State) (context : Context) (after : Transition)
    (accepted : discardValues machine context = .ok after) (valid : Valid machine)
    (layouts : ObjectOwners.Valid machine.heap) : Valid after.state := by
  unfold discardValues at accepted
  split at accepted <;> try contradiction
  rename_i values released executing
  have releasedOrdinary : ∀ value ∈ afterValues released, Ordinary value := by
    simpa only [executing, controlValues] using normal_control machine valid.1
  have queued : ∀ value ∈ values, Queued machine.heap value := by
    simpa only [executing, DisposalShape.control] using pending_control machine valid.2
  cases values with
  | nil =>
    cases accepted
    cases released <;> exact with_control _ _ valid releasedOrdinary (by simp [DisposalShape.control])
  | cons value rest =>
    simp only at accepted
    split at accepted
    · cases accepted
      exact with_control _ _ valid releasedOrdinary (fun child member => queued child (List.mem_cons_of_mem _ member))
    · simp only [bind, except_bind_ok] at accepted
      obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
      have found := (CellStability.lookupObject_reference _ _ _ _ looked).2
      have layout := layouts node stored found
      have object := lookup_valid machine node stored valid found
      cases stored <;> try contradiction
      all_goals simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
      all_goals obtain ⟨heap, retired, rfl⟩ := accepted
      all_goals have retained := retire_retains _ _ _ retired
      all_goals have next := retire_valid _ _ _ retired valid
      all_goals
        have restQueued : ∀ child ∈ rest, Queued heap child := by
          intro child member
          exact queued_mono _ _ _ retained (queued child (List.mem_cons_of_mem _ member))
      case oneShot saved =>
        have captured : CaptureValid heap saved := CaptureValid.mono _ _ _ retained object
        have originalQueue := pending_stack {machine with heap := heap} next.2
        have originalNormal := normal_stack {machine with heap := heap} next.1
        have stacked := with_stack {machine with heap := heap}
          (saved.frames ++ [.handler saved.delimiter, .disposalReturn rest released machine.invocation machine.scope] ++ machine.stack) next
          (by
            have ordinary := captured.1
            simp only [captureValues, List.mem_append] at ordinary
            simp only [List.flatMap_append, List.flatMap_cons, List.flatMap_nil, frameValues,
              List.append_nil, List.mem_append]
            grind only [])
          (by
            simp only [List.flatMap_append, List.flatMap_cons, List.flatMap_nil, DisposalShape.frame,
              List.nil_append, List.append_nil, List.mem_append]
            have pending := captured.2
            grind only [])
        exact with_control _ (.unwind _) stacked (by simp [controlValues]) (by simp [DisposalShape.control])
      case closure schema function bindings =>
        have target := retire_target machine value node (.closure schema function bindings) heap looked retired
        apply with_control _ (.discard (bindings.flatMap (fun binding => liveOwned heap binding.located) ++ rest) released) next releasedOrdinary
        intro child member
        rcases List.mem_append.mp member with fromChild | fromRest
        · obtain ⟨binding, bindingAt, childAt⟩ := List.mem_flatMap.mp fromChild
          obtain ⟨index, atIndex⟩ := List.getElem?_of_mem bindingAt
          have owner := layout index binding atIndex
          exact Or.inr ⟨node, index, (liveOwnedValue_owner heap binding.located.owner binding.located.value child childAt).trans owner, target⟩
        · exact restQueued child fromRest
      case package schema content =>
        have target := retire_target machine value node (.package schema content) heap looked retired
        apply with_control _ (.discard (liveOwned heap content ++ rest) released) next releasedOrdinary
        intro child member
        rcases List.mem_append.mp member with fromChild | fromRest
        · exact Or.inr ⟨node, 0, (liveOwnedValue_owner heap content.owner content.value child fromChild).trans layout, target⟩
        · exact restQueued child fromRest
      case resource schema content =>
        exact with_control _ _ next releasedOrdinary restQueued

end OwnerLocations
end BoundaryV2.Profile.Source.Machine
