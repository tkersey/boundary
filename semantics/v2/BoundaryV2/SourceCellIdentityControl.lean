import BoundaryV2.SourceCellIdentityHeap

namespace BoundaryV2.Profile.Source.Machine
namespace CellIdentities

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem enterTerm_unique (machine : State) (source : Module) (after : Transition)
    (formed : Unique machine.heap) (accepted : enterTerm machine source = .ok after) : Unique after.state.heap := by
  simp only [enterTerm, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only []

theorem enterExpression_unique (machine : State) (context : Context) (after : Transition)
    (formed : Unique machine.heap) (accepted : enterExpression machine context = .ok after) : Unique after.state.heap := by
  simp only [enterExpression, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, finishValue] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → scopedValue_unique, → makeClosure_unique]

theorem deliverOperand_unique (machine : State) (after : Transition)
    (formed : Unique machine.heap) (accepted : deliverOperand machine = .ok after) : Unique after.state.heap := by
  simp only [deliverOperand, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only []

theorem enterInvocation_unique (machine : State) (context : Context) (after : Transition)
    (formed : Unique machine.heap) (accepted : enterInvocation machine context = .ok after) : Unique after.state.heap := by
  unfold enterInvocation at accepted
  split at accepted <;> try contradiction
  exact invokeFunction_unique _ _ _ _ _ _ formed accepted

theorem enterBinding_unique (machine : State) (context : Context) (after : Transition)
    (formed : Unique machine.heap) (accepted : enterBinding machine context = .ok after) : Unique after.state.heap := by
  unfold enterBinding at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, created, rfl⟩ := accepted
  have next := createScope_unique _ _ _ _ _ _ _ _ _ formed created
  exact next

theorem enterPattern_unique (machine : State) (context : Context) (vars : List VariableId)
    (parts : List SemanticValue) (owner : Custody.Owner) (body : TermId) (bindings : Environment) (after : Transition)
    (formed : Unique machine.heap)
    (accepted : enterPattern machine context vars parts owner body bindings = .ok after) : Unique after.state.heap := by
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, created, rfl⟩ := accepted
  have next := createScope_unique _ _ _ _ _ _ _ _ _ formed created
  exact next

theorem executeControlTerm_unique (machine : State) (context : Context) (after : Transition)
    (formed : Unique machine.heap)
    (accepted : executeControlTerm machine context = .ok after) : Unique after.state.heap := by
  unfold executeControlTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    exact formed
  · cases accepted; exact formed
  · split at accepted <;> try contradiction
    exact applyClosure_unique _ _ _ _ _ formed accepted
  · split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, rfl⟩ := accepted
    exact formed
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨var, body⟩, _, accepted⟩ := accepted
    exact enterPattern_unique _ _ _ _ _ _ _ _ formed accepted
  · split at accepted <;> try contradiction
    exact enterPattern_unique _ _ _ _ _ _ _ _ formed accepted

theorem leaveScope_unique (machine : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition) (formed : Unique machine.heap)
    (accepted : leaveScope machine parent invocation tail value = .ok after) : Unique after.state.heap := by
  simp only [leaveScope, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, heap, moved, delivered, finished, rfl⟩ := accepted
  have entered : Unique ({machine with scope := parent, invocation := invocation, stack := tail} : State).heap := formed
  have next := finishTemporary_unique (move_unique (temporary_unique entered temporaryOk) moved) finished
  exact next

theorem leaveInvocation_unique (machine : State) (after : Transition) (formed : Unique machine.heap)
    (accepted : leaveInvocation machine = .ok after) : Unique after.state.heap := by
  unfold leaveInvocation at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  exact leaveScope_unique _ _ _ _ _ _ formed accepted

theorem leaveLexical_unique (machine : State) (after : Transition) (formed : Unique machine.heap)
    (accepted : leaveLexical machine = .ok after) : Unique after.state.heap := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, record, _, parent, _, result, left, accepted⟩ := accepted
  have next := leaveScope_unique _ _ _ _ _ _ formed left
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨parentRecord, _, heap, moved, rfl⟩ := accepted
  have movedUnique := move_unique next moved
  exact movedUnique

theorem restoreResumeCaller_unique (machine : State) (after : Transition) (formed : Unique machine.heap)
    (accepted : restoreResumeCaller machine = .ok after) : Unique after.state.heap := by
  unfold restoreResumeCaller at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i caller parent tail _
  have entered : Unique ({machine with scope := parent, invocation := caller, stack := tail} : State).heap := formed
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, heap, moved, finished⟩ := accepted
  exact finishTemporary_unique (move_unique (temporary_unique entered temporaryOk) moved) finished

theorem completeHandler_unique (machine : State) (context : Context) (after : Transition)
    (formed : Unique machine.heap)
    (accepted : completeHandler machine context = .ok after) : Unique after.state.heap := by
  unfold completeHandler at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact formed

theorem releaseScope_unique (machine : State) (after : Transition) (formed : Unique machine.heap)
    (accepted : releaseScope machine = .ok after) : Unique after.state.heap := by
  unfold releaseScope at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact formed

private theorem foldlM_preserves (items : List β) (step : α → β → Except Invalid α)
    (property : α → Prop) (preserved : ∀ before item after, step before item = .ok after → property before → property after)
    (before after : α) (accepted : items.foldlM step before = .ok after) (holds : property before) : property after := by
  induction items generalizing before with
  | nil => cases accepted; exact holds
  | cons item items induction =>
    simp only [List.foldlM_cons, bind, except_bind_ok] at accepted
    obtain ⟨middle, stepped, rest⟩ := accepted
    exact induction middle rest (preserved before item middle stepped holds)

theorem installHandler_unique (machine : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (bindings : Environment) (after : Transition)
    (formed : Unique machine.heap)
    (accepted : installHandler machine context handler body arguments stored bindings = .ok after) : Unique after.state.heap := by
  simp only [installHandler, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, ⟨store, capabilities⟩, allocated, applied⟩ := accepted
  have heap : Unique store := by
    apply foldlM_preserves _ _ (fun pair : Heap × List Located => Unique pair.1) ?_ _ _ allocated formed
    intro before item after accepted bounded
    rcases before with ⟨heap, capabilities⟩
    rcases item with ⟨clause, schema⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, ⟨next, value⟩, allocated, rfl⟩ := accepted
    exact allocate_noncell_unique _ _ _ _ _ _ _ allocated rfl bounded
  exact applyClosure_unique _ _ _ _ _ heap applied

theorem enterRegion_unique (machine : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition) (formed : Unique machine.heap)
    (accepted : enterRegion machine context descriptor body arguments = .ok after) : Unique after.state.heap := by
  simp only [enterRegion, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, ⟨store, region⟩, allocated, applied⟩ := accepted
  have next := allocate_noncell_unique _ _ _ _ _ _ _ allocated rfl formed
  exact applyClosure_unique _ _ _ _ _ next applied

end CellIdentities
end BoundaryV2.Profile.Source.Machine
