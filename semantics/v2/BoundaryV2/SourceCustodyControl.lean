import BoundaryV2.SourceCustodyHeap

namespace BoundaryV2.Profile.Source.Machine
namespace CustodyCoverage

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

private theorem flatMap_set_mono (values : List α) (index : Nat) (replacement original : α)
    (f : α → List β) (found : values[index]? = some original) (included : f original ⊆ f replacement) :
    values.flatMap f ⊆ (values.set index replacement).flatMap f := by
  induction values generalizing index with
  | nil => simp at found
  | cons value values induction =>
    cases index with
    | zero =>
      cases found
      intro child member
      rcases List.mem_append.mp member with originalAt | tailAt
      · exact List.mem_append_left _ (included originalAt)
      · exact List.mem_append_right _ tailAt
    | succ index =>
      intro child member
      rcases List.mem_append.mp member with first | rest
      · exact List.mem_append_left _ first
      · exact List.mem_append_right _ (induction index found rest)

theorem control_valid (machine : State) (control : Control) (valid : Valid machine)
    (empty : QueueCustody.controlFields machine.control = []) : Valid {machine with control := control} := by
  apply Covered.mono _ _ _ valid
  intro field member
  simp only [fields, QueueCustody.fields_components, empty, List.nil_append, List.mem_append] at member ⊢
  grind only []

theorem stack_fields_valid (machine : State) (next : List Frame) (valid : Valid machine)
    (same : next.flatMap QueueCustody.frameFields = machine.stack.flatMap QueueCustody.frameFields) :
    Valid {machine with stack := next} := by
  simpa only [Valid, fields, QueueCustody.fields_components, same] using valid

theorem authoredFailure_valid (machine : State) (context : Context)
    (failures : List (InstructionFailure .source)) (fault : Fault) (after : Transition)
    (valid : Valid machine) (empty : QueueCustody.controlFields machine.control = [])
    (accepted : authoredFailure machine context failures fault = .ok after) : Valid after.state := by
  simp only [authoredFailure, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  exact control_valid _ _ valid empty

theorem executePrimitive_valid (machine : State) (context : Context) (after : Transition)
    (valid : Valid machine)
    (cellsFree : ∀ node identity schema region content,
      machine.heap.lookup node = some (.cell identity schema region content) → ownedTokens content.value = [])
    (resourcesFree : ∀ node schema content,
      machine.heap.lookup node = some (.resource schema content) → ownedTokens content.value = [])
    (accepted : executePrimitive machine context = .ok after) : Valid after.state := by
  unfold executePrimitive at accepted
  split at accepted <;> try contradiction
  rename_i schema opcode immediate failures bindings operands executing
  have empty : QueueCustody.controlFields machine.control = [] := by rw [executing]; rfl
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · exact authoredFailure_valid _ _ _ _ _ valid empty accepted
  · exact commitPure_valid _ _ _ _ _ accepted valid empty
  · exact heapPrimitive_valid _ _ _ _ _ _ _ valid empty cellsFree resourcesFree accepted

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
  all_goals simpa only [Valid, fields, OwningFields.heap, QueueCustody.fields_components, QueueCustody.controlFields,
    QueueCustody.frameFields, DisposalShape.control, DisposalShape.frame, executing, List.flatMap_cons,
    List.filter_nil, List.nil_append] using valid

theorem deliverOperand_valid (machine : State) (after : Transition)
    (accepted : deliverOperand machine = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold deliverOperand at accepted
  split at accepted <;> try contradiction
  rename_i value executing
  split at accepted <;> try contradiction
  rename_i intent bindings remaining evaluated tail stacked
  split at accepted
  all_goals cases accepted
  all_goals simpa only [Valid, fields, OwningFields.heap, QueueCustody.fields_components, QueueCustody.controlFields,
    QueueCustody.frameFields, DisposalShape.control, DisposalShape.frame, executing, stacked, List.flatMap_cons,
    List.filter_nil, List.nil_append] using valid

theorem enterExpression_valid (machine : State) (context : Context) (after : Transition)
    (accepted : enterExpression machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold enterExpression at accepted
  split at accepted <;> try contradiction
  rename_i reference bindings executing
  have empty : QueueCustody.controlFields machine.control = [] := by rw [executing]; rfl
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨schema, expression⟩, _, accepted⟩ := accepted
  cases expression with
  | «variable» binder =>
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨value, _, _, _, _, _, rfl⟩ := accepted
    exact control_valid machine (.delivered value) valid empty
  | literal constant =>
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, accepted⟩ := accepted
    exact scopedValue_valid _ _ _ accepted valid empty
  | lambda function => exact makeClosure_valid _ _ _ _ _ _ accepted valid empty
  | primitive opcode operands immediate failures =>
    cases operands <;> cases accepted
    all_goals simpa only [Valid, fields, OwningFields.heap, QueueCustody.fields_components, QueueCustody.controlFields,
      QueueCustody.frameFields, DisposalShape.control, DisposalShape.frame, executing, List.flatMap_cons,
      List.filter_nil, List.nil_append] using valid

theorem enterInvocation_valid (machine : State) (context : Context) (after : Transition)
    (accepted : enterInvocation machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold enterInvocation at accepted
  split at accepted <;> try contradiction
  rename_i function bindings arguments executing
  exact invokeFunction_valid _ _ _ _ _ _ accepted valid (by rw [executing]; rfl)

theorem enterBinding_valid (machine : State) (context : Context) (after : Transition)
    (accepted : enterBinding machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold enterBinding at accepted
  split at accepted <;> try contradiction
  rename_i value executing
  split at accepted <;> try contradiction
  rename_i binder body bindings parent tail stacked
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, created, rfl⟩ := accepted
  have next := createScope_valid _ _ _ _ _ _ _ _ created
    (Covered.mono _ _ _ valid (fun _ member => List.mem_append_left _ member))
  have same := createScope_control_stack _ _ _ _ _ _ _ _ created
  have stackSame : middle.stack = machine.stack := same.2
  have stackedValid := stack_fields_valid middle (if middle.scope == parent then tail else .lexical middle.scope :: tail) next (by
    split <;> simp only [stackSame, stacked, List.flatMap_cons, QueueCustody.frameFields, DisposalShape.frame, List.filter_nil, List.nil_append])
  exact control_valid _ (.term body entered) stackedValid (by rw [same.1, executing]; rfl)

theorem enterPattern_valid (machine : State) (context : Context) (vars : List VariableId)
    (parts : List SemanticValue) (owner : Custody.Owner) (body : TermId) (bindings : Environment) (after : Transition)
    (accepted : enterPattern machine context vars parts owner body bindings = .ok after)
    (valid : Valid machine) (empty : QueueCustody.controlFields machine.control = []) : Valid after.state := by
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, created, rfl⟩ := accepted
  have next := createScope_valid _ _ _ _ _ _ _ _ created
    (Covered.mono _ _ _ valid (fun _ member => List.mem_append_left _ member))
  have same := createScope_control_stack _ _ _ _ _ _ _ _ created
  have stackSame : middle.stack = machine.stack := same.2
  have stackedValid := stack_fields_valid middle (if middle.scope == machine.scope then machine.stack else .lexical middle.scope :: machine.stack) next (by
    split <;> simp only [stackSame, List.flatMap_cons, QueueCustody.frameFields, DisposalShape.frame, List.filter_nil, List.nil_append])
  exact control_valid _ (.term body entered) stackedValid (by rw [same.1]; exact empty)

theorem executeControlTerm_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executeControlTerm machine context = .ok after) (valid : Valid machine)
    (contracts : ClosureContracts.Valid context machine.heap.objects) : Valid after.state := by
  unfold executeControlTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  have empty : QueueCustody.controlFields machine.control = [] := by rw [executing]; rfl
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    exact control_valid _ _ valid empty
  · cases accepted; exact control_valid _ _ valid empty
  · split at accepted <;> try contradiction
    exact applyClosure_valid _ _ _ _ _ accepted valid empty contracts
  · split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, rfl⟩ := accepted
    exact control_valid _ _ valid empty
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨binder, body⟩, _, accepted⟩ := accepted
    exact enterPattern_valid _ _ _ _ _ _ _ _ accepted valid empty
  · split at accepted <;> try contradiction
    exact enterPattern_valid _ _ _ _ _ _ _ _ accepted valid empty

theorem leaveScope_valid (machine : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition)
    (accepted : leaveScope machine parent invocation tail value = .ok after) (valid : Valid machine)
    (same : tail.flatMap QueueCustody.frameFields = machine.stack.flatMap QueueCustody.frameFields)
    (empty : QueueCustody.controlFields machine.control = []) : Valid after.state := by
  simp only [leaveScope, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, owner⟩, reserved, heap, moved, delivered, finished, rfl⟩ := accepted
  have entered : Valid {machine with scope := parent, invocation := invocation, stack := tail} := stack_fields_valid _ _ valid same
  have next := temporary_covered _ _ _ [] reserved (by simpa [Valid] using entered)
  have movedCover := moveValues_covered _ _ _ _ _ moved (by simpa using next)
  rw [← move_fields _ _ _ _ moved] at movedCover
  have done := finishTemporary_covered _ _ [] _ finished
    (by rw [temporary_control _ _ _ reserved]; exact empty) (by simpa using movedCover)
  have deliveredValid : Valid delivered.state := by simpa only [Valid, List.append_nil] using done
  have deliveredControl : delivered.state.control = .delivered (retainAt value owner) := by
    unfold finishTemporary at finished
    split at finished <;> try contradiction
    cases finished
    rfl
  exact control_valid _ _ deliveredValid (by rw [deliveredControl]; rfl)

theorem leaveInvocation_valid (machine : State) (after : Transition)
    (accepted : leaveInvocation machine = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold leaveInvocation at accepted
  split at accepted <;> try contradiction
  rename_i value executing
  split at accepted <;> try contradiction
  rename_i caller parent tail stacked
  exact leaveScope_valid _ _ _ _ _ _ accepted valid
    (by simp [stacked, QueueCustody.frameFields, DisposalShape.frame]) (by rw [executing]; rfl)

theorem restoreResumeCaller_valid (machine : State) (after : Transition)
    (accepted : restoreResumeCaller machine = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold restoreResumeCaller at accepted
  split at accepted <;> try contradiction
  rename_i value executing
  split at accepted <;> try contradiction
  rename_i caller parent tail stacked
  have entered : Valid {machine with scope := parent, invocation := caller, stack := tail} :=
    stack_fields_valid machine tail valid (by simp [stacked, QueueCustody.frameFields, DisposalShape.frame])
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨middle, owner⟩, reserved, heap, moved, finished⟩ := accepted
  have next := temporary_covered _ _ _ [] reserved (by simpa [Valid] using entered)
  have movedCover := moveValues_covered _ _ _ _ _ moved (by simpa using next)
  rw [← move_fields _ _ _ _ moved] at movedCover
  have done := finishTemporary_covered _ _ [] _ finished
    (by rw [temporary_control _ _ _ reserved, executing]; rfl) (by simpa using movedCover)
  simpa only [Valid, List.append_nil] using done

theorem replace_scope_covered (machine : State) (index : Nat) (original replacement : Scope) (extra : List Located)
    (found : machine.heap.scopes[index]? = some original)
    (prior : original.holdings ⊆ replacement.holdings) (added : extra ⊆ replacement.holdings)
    (covered : Covered machine.heap.custody (fields machine ++ extra)) :
    Valid {machine with heap := {machine.heap with scopes := machine.heap.scopes.set index replacement}} := by
  have holdingSubset := flatMap_set_mono machine.heap.scopes index replacement original Scope.holdings found prior
  have bounded := (List.getElem?_eq_some_iff.mp found).1
  have updatedAt : replacement ∈ machine.heap.scopes.set index replacement :=
    List.mem_of_getElem? (List.getElem?_set_self bounded)
  apply Covered.mono _ _ _ covered
  intro field member
  rcases List.mem_append.mp member with old | extraAt
  · simp only [fields, OwningFields.heap, List.mem_append] at old ⊢
    rcases old with ((object | protection) | holding) | queued
    · exact Or.inl (Or.inl (Or.inl object))
    · exact Or.inl (Or.inl (Or.inr protection))
    · exact Or.inl (Or.inr (holdingSubset holding))
    · exact Or.inr queued
  · apply List.mem_append_left
    apply List.mem_append_right
    exact List.mem_flatMap.mpr ⟨replacement, updatedAt, added extraAt⟩

theorem move_scopes (before after : Heap) (values : List Located) (receiver : Nat → Custody.Owner)
    (accepted : moveValues before values receiver = some after) : after.scopes = before.scopes := by
  simp only [moveValues, bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  rfl

theorem leaveLexical_valid (machine : State) (after : Transition)
    (accepted : leaveLexical machine = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  rename_i value executing
  split at accepted <;> try contradiction
  rename_i scope tail stacked
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, record, recordAt, parent, _, result, left, accepted⟩ := accepted
  have next := leaveScope_valid _ _ _ _ _ _ left valid
    (by simp [stacked, QueueCustody.frameFields, DisposalShape.frame]) (by rw [executing]; rfl)
  split at accepted <;> try contradiction
  rename_i departed delivered deliveredAt
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨parentRecord, parentAt, heap, moved, rfl⟩ := accepted
  have movedCover := moveValues_covered _ _ _ _ _ moved next
  rw [← move_fields _ _ _ _ moved] at movedCover
  let remaining := record.holdings.flatMap (liveOwned result.state.heap)
  let incoming := remaining.mapIdx (fun index located => retainAt located (.temporary parent (parentRecord.nextOwner + index)))
  let updated : Scope := {parentRecord with nextOwner := parentRecord.nextOwner + remaining.length, holdings := incoming ++ parentRecord.holdings}
  have inherited := replace_scope_covered {result.state with heap := heap} parent.value parentRecord updated incoming
    (by simpa only [move_scopes _ _ _ _ moved] using parentAt)
    (fun _ member => List.mem_append_right _ member)
    (fun _ member => List.mem_append_left _ member) movedCover
  exact control_valid _ (.delivered delivered) inherited (by rw [deliveredAt]; rfl)

theorem releaseScope_valid (machine : State) (after : Transition)
    (accepted : releaseScope machine = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold releaseScope at accepted
  split at accepted <;> try contradiction
  rename_i scope released executing
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact control_valid _ _ valid (by rw [executing]; rfl)

theorem finishDisposal_valid (machine : State) (after : Transition)
    (accepted : finishDisposal machine = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold finishDisposal at accepted
  split at accepted <;> try contradiction
  rename_i value executing
  split at accepted <;> try contradiction
  rename_i remaining released invocation scope tail stacked
  cases accepted
  apply Covered.mono _ _ _ valid
  intro field member
  simp only [fields, QueueCustody.fields_components, QueueCustody.controlFields, QueueCustody.frameFields,
    DisposalShape.control, DisposalShape.frame, executing, stacked, List.filter_append, List.filter_nil,
    List.flatMap_cons, List.nil_append, List.mem_append] at member ⊢
  grind only []

end CustodyCoverage
end BoundaryV2.Profile.Source.Machine
