import BoundaryV2.SourceQueueCapture

namespace BoundaryV2.Profile.Source.Machine
namespace QueueCustody

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

private theorem mapM_output (function : α → Except Invalid β) (inputs : List α) (outputs : List β)
    (accepted : inputs.mapM function = .ok outputs) (output : β) (member : output ∈ outputs) :
    ∃ input ∈ inputs, function input = .ok output := by
  induction inputs generalizing outputs with
  | nil => cases accepted; simp at member
  | cons head tail induction =>
    simp only [List.mapM_cons, bind, except_bind_ok] at accepted
    obtain ⟨first, firstAt, rest, restAt, accepted⟩ := accepted
    cases accepted
    rcases List.mem_cons.mp member with equal | belongs
    · cases equal; exact ⟨head, by simp, firstAt⟩
    · obtain ⟨input, inputMember, checked⟩ := induction rest restAt belongs
      exact ⟨input, by simp [inputMember], checked⟩

private theorem flatMap_set_empty (values : List α) (index : Nat) (replacement : α) (f : α → List β)
    (empty : f replacement = []) : ((values.set index replacement).flatMap f).Sublist (values.flatMap f) := by
  induction values generalizing index with
  | nil => simp
  | cons value values induction =>
    cases index with
    | zero => simpa only [List.set_cons_zero, List.flatMap_cons, empty, List.nil_append] using List.sublist_append_right (f value) (values.flatMap f)
    | succ index => exact (induction index).append_left (f value)

def Separate (machine : State) (value : Located) : Prop :=
  ∀ pinned ∈ fields machine, value.owner ≠ pinned.owner ∨ ownedTokens value.value = []

theorem ordinary_separate (machine : State) (value : Located) (ordinary : OwnerLocations.Ordinary value) :
    Separate machine value := by
  intro pinned member
  rcases ordinary with inScope | free
  · left
    intro same
    rw [same] at inScope
    have closed := (List.mem_filter.mp member).2
    cases ownerAt : pinned.owner <;> simp_all [closureOwner, OwnerLocations.Scoped]
  · exact Or.inr free

theorem fields_retired (machine : State) (owners : OwnerLocations.Valid machine) (leaves : DisposalShape.Valid machine) :
    ∀ value ∈ fields machine, OwnerLocations.Retired machine.heap value.owner := by
  intro value member
  obtain ⟨member, closed⟩ := List.mem_filter.mp member
  exact closure_owner_retired _ _ (owners.2 value member) (raw_leaves machine leaves value member) closed

theorem live_parent_separate (machine : State) (value : Located) (node : NodeId) (index : Nat) (stored : Object)
    (ownerAt : value.owner = .closure node index) (found : machine.heap.lookup node = some stored)
    (retired : ∀ pinned ∈ fields machine, OwnerLocations.Retired machine.heap pinned.owner) : Separate machine value := by
  intro pinned member
  left
  intro same
  obtain ⟨parent, offset, atOwner, _, absent⟩ := retired pinned member
  have equal : node = parent := (Custody.Owner.closure.inj (ownerAt.symm.trans (same.trans atOwner))).1
  subst parent
  rw [found] at absent
  contradiction

theorem separate_sublist (before after : State) (value : Located) (included : (fields after).Sublist (fields before))
    (separate : Separate before value) : Separate after value :=
  fun pinned member => separate pinned (included.subset member)

theorem retired_fields_sublist (machine : State) (heap : Heap) (value : Located)
    (accepted : retireObject machine.heap value = some heap) :
    (fields {machine with heap := heap}).Sublist (fields machine) := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨_, _, middle, consumed, rfl⟩ := accepted
  have same := ObjectOwners.consume_objects _ _ _ consumed
  simpa only [fields_components, heapFields, same] using
    (flatMap_set_empty machine.heap.objects _ none (fun entry => entry.toList.flatMap objectFields) rfl).append_left
      (controlFields machine.control ++ machine.stack.flatMap frameFields)

theorem createScope_valid (machine : State) (context : Context) (invocation : InvocationId)
    (parent : Option LexicalScopeId) (vars : List VariableId) (values : List Located)
    (bindings : Environment) (after : State × Environment)
    (accepted : createScope machine context invocation parent vars values bindings = .ok after)
    (valid : Valid machine) (separate : ∀ value ∈ values, Separate machine value) :
    Valid after.1 ∧ after.1.control = machine.control ∧ after.1.stack = machine.stack ∧
      after.1.heap.objects = machine.heap.objects := by
  simp only [createScope, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · cases accepted; exact ⟨valid, rfl, rfl, rfl⟩
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, heap, moved, rfl⟩ := accepted
    have next := move_valid _ _ _ _ moved valid separate
    exact ⟨next, rfl, rfl, ObjectOwners.move_objects machine.heap heap values _ moved⟩

theorem lookup_variable_separate (machine : State) (bindings : Environment) (binder : VariableId) (value : Located)
    (looked : lookupVariable bindings binder = some value)
    (separate : ∀ binding ∈ bindings, Separate machine binding.located) : Separate machine value := by
  simp only [lookupVariable, Option.map_eq_some_iff] at looked
  obtain ⟨binding, found, rfl⟩ := looked
  exact separate binding (List.mem_of_find?_eq_some found)

theorem invokeFunction_valid (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction machine context function bindings arguments = .ok after) (valid : Valid machine)
    (environment : ∀ binding ∈ bindings, Separate machine binding.located)
    (operands : ∀ value ∈ arguments, Separate machine value) : Valid after.state := by
  simp only [invokeFunction, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨definition, _, body, _, captured, capturedAt, _, _, _, _, ⟨middle, entered⟩, created, rfl⟩ := accepted
  have next := createScope_valid _ _ _ _ _ _ _ _ created valid (by
    intro value member
    rcases List.mem_append.mp member with capture | argument
    · obtain ⟨binder, _, looked⟩ := mapM_output _ _ _ capturedAt value capture
      exact lookup_variable_separate machine bindings binder value ((fromOption_ok _ _ _).mp looked) environment
    · exact operands value argument)
  have stackSame : middle.stack = machine.stack := next.2.2.1
  have changed := empty_control_valid middle (.term body entered) next.1 rfl
  simpa only [Valid, fields_components, List.flatMap_cons, frameFields, DisposalShape.frame,
    List.filter_nil, List.nil_append, stackSame, heapFields, Linear, current] using changed

theorem consume_separate_valid (machine : State) (heap : Heap) (value : Located)
    (accepted : consumeValue machine.heap value = some heap) (valid : Valid machine)
    (separate : Separate machine value) : Valid {machine with heap := heap} := by
  have same := fields_same_objects machine heap (ObjectOwners.consume_objects _ _ _ accepted)
  unfold Valid
  rw [same]
  apply Linear.heap machine.heap heap (fields machine) valid
  intro pinned pinnedAt usable
  rcases separate pinned pinnedAt with different | free
  · exact consume_distinct_owner_keeps_current _ _ _ _ accepted usable different
  · exact consume_keeps_current _ _ _ _ accepted usable (by simp [free])

theorem retire_separate_valid (machine : State) (heap : Heap) (value : Located)
    (accepted : retireObject machine.heap value = some heap) (valid : Valid machine)
    (separate : Separate machine value) : Valid {machine with heap := heap} := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨_, _, middle, consumed, rfl⟩ := accepted
  exact erase_object_valid {machine with heap := middle} _ (consume_separate_valid _ _ _ consumed valid separate)

theorem applyClosure_valid (machine : State) (context : Context) (closure : Located)
    (arguments : List Located) (after : Transition)
    (accepted : applyClosure machine context closure arguments = .ok after) (valid : Valid machine)
    (separate : Separate machine closure)
    (operands : ∀ value ∈ arguments, Separate machine value)
    (retired : ∀ pinned ∈ fields machine, OwnerLocations.Retired machine.heap pinned.owner)
    (objects : ObjectOwners.Valid machine.heap) : Valid after.state := by
  simp only [applyClosure, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
  cases stored <;> try contradiction
  case closure schema function bindings =>
    obtain ⟨⟨schema, token, reference⟩, found⟩ := CellStability.lookupObject_reference _ _ _ _ looked
    have captures : ∀ binding ∈ bindings, Separate machine binding.located := by
      intro binding member
      obtain ⟨index, atIndex⟩ := List.mem_iff_getElem?.mp member
      exact live_parent_separate machine binding.located node index _
        (objects node _ found index binding atIndex) found retired
    rw [reference] at accepted
    cases token with
    | none =>
      simp only [pure, Except.pure, Except.bind] at accepted
      exact invokeFunction_valid _ _ _ _ _ _ accepted valid captures operands
    | some token =>
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨heap, consumed, accepted⟩ := accepted
      have included := retired_fields_sublist _ _ _ consumed
      exact invokeFunction_valid _ _ _ _ _ _ accepted (retire_separate_valid _ _ _ consumed valid separate)
        (fun binding member => separate_sublist _ _ _ included (captures binding member))
        (fun value member => separate_sublist _ _ _ included (operands value member))

theorem resumeComputation_valid (machine : State) (context : Context) (token computation : Located) (after : Transition)
    (accepted : resumeComputation machine context token computation = .ok after) (valid : Valid machine)
    (ordinaryToken : OwnerLocations.Ordinary token) (ordinaryComputation : OwnerLocations.Ordinary computation)
    (owners : OwnerLocations.Valid machine) (leaves : DisposalShape.Valid machine)
    (objects : ObjectOwners.Valid machine.heap) : Valid after.state := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, active, activated, applied⟩ := accepted
  have queueTaken := takeCapture_valid _ _ _ _ captured valid ordinaryToken
  have queueActive := activateCapture_valid _ _ _ _ _ activated queueTaken
  have ownerTaken := OwnerLocations.takeCapture_valid _ _ _ _ captured owners
  have ownerActive := OwnerLocations.activateCapture_valid _ _ _ _ _ activated ownerTaken.1 ownerTaken.2 (by simp)
  have leafTaken := DisposalShape.takeCapture_valid _ _ _ _ captured leaves
  have leafActive := DisposalShape.activateCapture_valid _ _ _ _ _ activated leafTaken.1 leafTaken.2
  have objectTaken := ObjectOwners.takeCapture_valid _ _ _ _ objects captured
  have objectActive := ObjectOwners.activateCapture_valid _ _ _ _ _ objectTaken activated
  apply applyClosure_valid _ _ _ _ _ applied queueActive (ordinary_separate active computation ordinaryComputation)
    ?_ (fields_retired active ownerActive leafActive) objectActive
  intro value member
  exact ordinary_separate active value
    (ownerTaken.2.1 value (List.mem_append_right _ member))

theorem temporary_fields (machine after : State) (owner : Custody.Owner)
    (accepted : temporary machine = .ok (after, owner)) : fields after = fields machine := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  rfl

theorem temporary_owner (machine after : State) (owner : Custody.Owner)
    (accepted : temporary machine = .ok (after, owner)) : OwnerLocations.Scoped owner := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  trivial

theorem scopedValue_valid (machine : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue machine value = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, reserved, finished⟩ := accepted
  exact finishTemporary_valid _ _ _ finished (temporary_valid _ _ _ reserved valid)

theorem makeClosureWithValues_valid (machine : State) (context : Context)
    (schema : SchemaId .source) (function : FunctionId .source) (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues machine context schema function values = .ok after) (valid : Valid machine)
    (separate : ∀ value ∈ values, Separate machine value) : Valid after.state := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, ⟨middle, owner⟩, reserved, moved, movedAt, ⟨heap, result⟩, allocated, finished⟩ := accepted
  have next := temporary_valid _ _ _ reserved valid
  have movedValid := move_valid _ _ _ _ movedAt next (by
    intro value member pinned pinnedAt
    rw [temporary_fields _ _ _ reserved] at pinnedAt
    exact separate value member pinned pinnedAt)
  have allocatedValid := allocate_empty_valid _ _ _ _ _ _ _ allocated movedValid rfl
  exact finishTemporary_valid _ _ _ finished allocatedValid

theorem makeClosure_valid (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (bindings : Environment) (after : Transition)
    (accepted : makeClosure machine context schema function bindings = .ok after) (valid : Valid machine)
    (separate : ∀ binding ∈ bindings, Separate machine binding.located) : Valid after.state := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  obtain ⟨values, captured, created⟩ := accepted
  apply makeClosureWithValues_valid _ _ _ _ _ _ created valid
  intro value member
  obtain ⟨binder, _, looked⟩ := mapM_output _ _ _ captured value member
  exact lookup_variable_separate machine bindings binder value ((fromOption_ok _ _ _).mp looked) separate

theorem consume_book_valid (machine : State) (book : Custody.Book) (removed : List CustodyToken) (owner : Custody.Owner)
    (accepted : Custody.consume machine.heap.custody removed owner = some book) (valid : Valid machine)
    (separate : ∀ pinned ∈ fields machine, owner ≠ pinned.owner) :
    Valid {machine with heap := {machine.heap with custody := book}} := by
  unfold Custody.consume at accepted
  split at accepted <;> try contradiction
  rename_i checked
  have senders := (Bool.and_eq_true_iff.mp checked).2
  cases accepted
  apply Linear.heap machine.heap _ (fields machine) valid
  intro pinned member usable
  apply current_of_entries machine.heap _ pinned _ usable
  intro entry entryAt _ ownerAt
  apply List.mem_filter.mpr
  refine ⟨entryAt, ?_⟩
  have absent : entry.token ∉ removed := by
    intro removedAt
    have held := List.all_eq_true.mp senders entry.token removedAt
    have owns : Custody.owns machine.heap.custody entry.token owner := by
      simpa only [Custody.has, Custody.owns, List.any_eq_true, Bool.and_eq_true, beq_iff_eq] using held
    exact separate pinned member (Custody.unique_custodian machine.heap.custody entry.token _ _ owns ⟨entry, entryAt, rfl, ownerAt⟩)
  simpa using absent

theorem commitPure_valid (machine : State) (opcode : Opcode) (operands : List Located)
    (result : SemanticValue) (after : Transition)
    (accepted : commitPure machine opcode operands result = .ok after) (valid : Valid machine)
    (separate : ∀ value ∈ operands, Separate machine value) : Valid after.state := by
  simp only [commitPure, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, reserved, accepted⟩ := accepted
  have next := temporary_valid _ _ _ reserved valid
  split at accepted
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, _, _, _, finished⟩ := accepted
    exact finishTemporary_valid _ _ _ finished next
  · simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨heap, moved, _, _, custody, consumed, finished⟩ := accepted
    have movedValid := move_valid _ _ _ _ moved next (by
      intro value member pinned pinnedAt
      rw [temporary_fields _ _ _ reserved] at pinnedAt
      exact separate value member pinned pinnedAt)
    have changed := consume_book_valid {middle with heap := heap} custody _ owner consumed movedValid (by
      intro pinned member same
      have inScope := temporary_owner _ _ _ reserved
      have closed := (List.mem_filter.mp member).2
      rw [same] at inScope
      cases ownerAt : pinned.owner <;> simp_all [OwnerLocations.Scoped, closureOwner])
    exact finishTemporary_valid _ _ _ finished changed

private theorem flatMap_set_same (values : List α) (index : Nat) (replacement original : α)
    (f : α → List β) (found : values[index]? = some original) (same : f replacement = f original) :
    (values.set index replacement).flatMap f = values.flatMap f := by
  induction values generalizing index with
  | nil => simp at found
  | cons value values induction =>
    cases index with
    | zero => cases found; simp [same]
    | succ index => simpa only [List.set_cons_succ, List.flatMap_cons] using congrArg (f value ++ ·) (induction index found)

theorem replace_empty_valid (machine : State) (heap : Heap) (node : NodeId) (before after : Object)
    (found : machine.heap.lookup node = some before)
    (accepted : replaceObject machine.heap node after = some heap) (valid : Valid machine)
    (emptyBefore : objectFields before = []) (emptyAfter : objectFields after = []) : Valid {machine with heap := heap} := by
  have position : machine.heap.objects[node.value]? = some (some before) := by
    simp only [Heap.lookup, Option.bind_eq_some_iff] at found
    obtain ⟨entry, atEntry, isStored⟩ := found
    cases entry <;> try contradiction
    cases isStored
    exact atEntry
  unfold replaceObject at accepted
  split at accepted <;> try contradiction
  cases accepted
  have same := flatMap_set_same machine.heap.objects node.value (some after) (some before)
    (fun entry => entry.toList.flatMap objectFields) position (by simp [emptyBefore, emptyAfter])
  simpa only [Valid, fields_components, heapFields, same, Linear, current] using valid

end QueueCustody
end BoundaryV2.Profile.Source.Machine
