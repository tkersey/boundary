import BoundaryV2.SourceScopeTreeHeap

namespace BoundaryV2.Profile.Source.Machine
namespace ScopeTree

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem enterTerm_formed (machine : State) (source : Module) (after : Transition)
    (formed : Formed machine.heap) (accepted : enterTerm machine source = .ok after) : Formed after.state.heap := by
  simp only [enterTerm, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only []

theorem enterExpression_formed (machine : State) (context : Context) (after : Transition)
    (formed : Formed machine.heap) (accepted : enterExpression machine context = .ok after) : Formed after.state.heap := by
  simp only [enterExpression, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, finishValue] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → scopedValue_formed, → makeClosure_formed]

theorem deliverOperand_formed (machine : State) (after : Transition)
    (formed : Formed machine.heap) (accepted : deliverOperand machine = .ok after) : Formed after.state.heap := by
  simp only [deliverOperand, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only []

theorem enterInvocation_formed (machine : State) (context : Context) (after : Transition)
    (formed : Formed machine.heap) (accepted : enterInvocation machine context = .ok after) : Formed after.state.heap := by
  unfold enterInvocation at accepted
  split at accepted <;> try contradiction
  exact invokeFunction_formed _ _ _ _ _ _ formed accepted

theorem enterBinding_formed (machine : State) (context : Context) (after : Transition)
    (formed : Formed machine.heap) (bounded : IdentitySupport.Valid machine) (accepted : enterBinding machine context = .ok after) : Formed after.state.heap := by
  unfold enterBinding at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i var next bindings parent tail stacked
  have parentOld : parent.value < machine.heap.nextScope :=
    bounded.frames (.binding var next bindings parent) (by simp [stacked])
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, created, rfl⟩ := accepted
  have next := createScope_formed _ _ _ _ _ _ _ _ formed (by simpa using parentOld) created
  exact next

theorem enterPattern_formed (machine : State) (context : Context) (vars : List VariableId)
    (parts : List SemanticValue) (owner : Custody.Owner) (body : TermId) (bindings : Environment) (after : Transition)
    (formed : Formed machine.heap) (bounded : IdentitySupport.Valid machine)
    (accepted : enterPattern machine context vars parts owner body bindings = .ok after) : Formed after.state.heap := by
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, created, rfl⟩ := accepted
  have next := createScope_formed _ _ _ _ _ _ _ _ formed
    (by simpa [IdentitySupport.Bound, IdentitySupport.limits] using bounded.scope) created
  exact next

theorem executeControlTerm_formed (machine : State) (context : Context) (after : Transition)
    (formed : Formed machine.heap) (bounded : IdentitySupport.Valid machine)
    (accepted : executeControlTerm machine context = .ok after) : Formed after.state.heap := by
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
    exact applyClosure_formed _ _ _ _ _ formed accepted
  · split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, rfl⟩ := accepted
    exact formed
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨var, body⟩, _, accepted⟩ := accepted
    exact enterPattern_formed _ _ _ _ _ _ _ _ formed bounded accepted
  · split at accepted <;> try contradiction
    exact enterPattern_formed _ _ _ _ _ _ _ _ formed bounded accepted

theorem leaveScope_formed (machine : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition) (formed : Formed machine.heap)
    (accepted : leaveScope machine parent invocation tail value = .ok after) : Formed after.state.heap := by
  simp only [leaveScope, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, heap, moved, delivered, finished, rfl⟩ := accepted
  have entered : Formed ({machine with scope := parent, invocation := invocation, stack := tail} : State).heap := formed
  have next := finishTemporary_formed (move_formed (temporary_formed entered temporaryOk) moved) finished
  exact next

theorem leaveInvocation_formed (machine : State) (after : Transition) (formed : Formed machine.heap)
    (accepted : leaveInvocation machine = .ok after) : Formed after.state.heap := by
  unfold leaveInvocation at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  exact leaveScope_formed _ _ _ _ _ _ formed accepted

theorem leaveLexical_formed (machine : State) (after : Transition) (formed : Formed machine.heap)
    (accepted : leaveLexical machine = .ok after) : Formed after.state.heap := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, record, _, parent, _, result, left, accepted⟩ := accepted
  have next := leaveScope_formed _ _ _ _ _ _ formed left
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨parentRecord, parentAt, heap, moved, rfl⟩ := accepted
  simp [moveValues, Option.bind_eq_some_iff] at moved
  obtain ⟨_, _, rfl⟩ := moved
  exact set_formed result.state.heap parent.value parentRecord _ parentAt rfl rfl next

theorem restoreResumeCaller_formed (machine : State) (after : Transition) (formed : Formed machine.heap)
    (accepted : restoreResumeCaller machine = .ok after) : Formed after.state.heap := by
  unfold restoreResumeCaller at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i caller parent tail _
  have entered : Formed ({machine with scope := parent, invocation := caller, stack := tail} : State).heap := formed
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, heap, moved, finished⟩ := accepted
  exact finishTemporary_formed (move_formed (temporary_formed entered temporaryOk) moved) finished

theorem completeHandler_formed (machine : State) (context : Context) (after : Transition)
    (formed : Formed machine.heap)
    (accepted : completeHandler machine context = .ok after) : Formed after.state.heap := by
  unfold completeHandler at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact formed

theorem releaseScope_formed (machine : State) (after : Transition) (formed : Formed machine.heap)
    (accepted : releaseScope machine = .ok after) : Formed after.state.heap := by
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

theorem installHandler_formed (machine : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (bindings : Environment) (after : Transition)
    (formed : Formed machine.heap)
    (accepted : installHandler machine context handler body arguments stored bindings = .ok after) : Formed after.state.heap := by
  simp only [installHandler, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, ⟨store, capabilities⟩, allocated, applied⟩ := accepted
  have heap : Formed store := by
    apply foldlM_preserves _ _ (fun pair : Heap × List Located => Formed pair.1) ?_ _ _ allocated formed
    intro before item after accepted bounded
    rcases before with ⟨heap, capabilities⟩
    rcases item with ⟨clause, schema⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, ⟨next, value⟩, allocated, rfl⟩ := accepted
    exact allocate_formed _ _ _ _ _ _ _ allocated bounded
  exact applyClosure_formed _ _ _ _ _ heap applied

theorem enterRegion_formed (machine : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition) (formed : Formed machine.heap)
    (accepted : enterRegion machine context descriptor body arguments = .ok after) : Formed after.state.heap := by
  simp only [enterRegion, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, ⟨store, region⟩, allocated, applied⟩ := accepted
  have next := allocate_formed _ _ _ _ _ _ _ allocated formed
  exact applyClosure_formed _ _ _ _ _ next applied

end ScopeTree
end BoundaryV2.Profile.Source.Machine
