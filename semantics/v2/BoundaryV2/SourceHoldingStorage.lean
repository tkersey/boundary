import BoundaryV2.SourceHoldingOwners

namespace BoundaryV2.Profile.Source.Machine
namespace HoldingOwners

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem makeClosure_valid (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (bindings : Environment) (after : Transition)
    (formed : Valid machine.heap)
    (accepted : makeClosure machine context schema function bindings = .ok after) : Valid after.state.heap := by
  simp only [makeClosure, bind] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → makeClosureWithValues_valid]

theorem authoredFailure_valid (machine : State) (context : Context)
    (failures : List (InstructionFailure .source)) (fault : Fault) (after : Transition)
    (formed : Valid machine.heap)
    (accepted : authoredFailure machine context failures fault = .ok after) : Valid after.state.heap := by
  simp only [authoredFailure, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  exact formed

theorem heapPrimitive_valid (machine : State) (context : Context) (operation : Primitives.GraphOperation)
    (schema : SchemaId .source) (immediate : Nat) (operands : List Located) (after : Transition)
    (formed : Valid machine.heap)
    (accepted : heapPrimitive machine context operation schema immediate operands = .ok after) : Valid after.state.heap := by
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
    have ready := temporary_valid _ _ _ temporaryOk formed
    have movedScopes := move_scopes _ _ _ _ moveOk
    have allocatedFields := allocation_scopes _ _ _ _ _ _ _ allocated
    apply finish_reserved _ _ _ finished
    · simpa only [Valid, allocatedFields.1, movedScopes] using ready.1
    · simpa only [Ready, allocatedFields.1, allocatedFields.2, movedScopes] using ready.2
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
    have next : Valid store := by simpa only [Valid, replace_scopes _ _ _ _ replaced] using formed
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
    have ready := temporary_valid _ _ _ temporaryOk formed
    have movedScopes := move_scopes _ _ _ _ moveOk
    have allocatedFields := allocation_scopes _ _ _ _ _ _ _ allocated
    apply finish_reserved _ _ _ finished
    · simpa only [Valid, allocatedFields.1, movedScopes] using ready.1
    · simpa only [Ready, allocatedFields.1, allocatedFields.2, movedScopes] using ready.2
  case unpack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, store, retired, accepted⟩ := accepted
    exact commitPure_valid _ _ _ _ _ accepted (by simpa only [Valid, retire_scopes _ _ _ retired] using formed)
  case cloneResumption =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, retired, retireOk, ⟨middle, owner⟩, temporaryOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have retiredValid : Valid retired := by simpa only [Valid, retire_scopes _ _ _ retireOk] using formed
    have ready := temporary_valid _ _ _ temporaryOk retiredValid
    have allocatedFields := allocation_scopes _ _ _ _ _ _ _ allocated
    apply finish_reserved _ _ _ finished
    · simpa only [Valid, allocatedFields.1] using ready.1
    · simpa only [Ready, allocatedFields.1, allocatedFields.2] using ready.2
  case resourcePack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, ⟨middle, owner⟩, temporaryOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have ready := temporary_valid _ _ _ temporaryOk formed
    have allocatedFields := allocation_scopes _ _ _ _ _ _ _ allocated
    apply finish_reserved _ _ _ finished
    · simpa only [Valid, allocatedFields.1] using ready.1
    · simpa only [Ready, allocatedFields.1, allocatedFields.2] using ready.2
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
      exact scopedValue_valid _ _ _ accepted (by simpa only [Valid, retire_scopes _ _ _ retired] using formed)
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
    (formed : Valid machine.heap)
    (accepted : executePrimitive machine context = .ok after) : Valid after.state.heap := by
  unfold executePrimitive at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · exact authoredFailure_valid _ _ _ _ _ formed accepted
  · exact commitPure_valid _ _ _ _ _ accepted formed
  · exact heapPrimitive_valid _ _ _ _ _ _ _ formed accepted


theorem enterTerm_valid (machine : State) (source : Module) (after : Transition)
    (formed : Valid machine.heap) (accepted : enterTerm machine source = .ok after) : Valid after.state.heap := by
  simp only [enterTerm, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only []

theorem enterExpression_valid (machine : State) (context : Context) (after : Transition)
    (formed : Valid machine.heap) (accepted : enterExpression machine context = .ok after) : Valid after.state.heap := by
  simp only [enterExpression, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, finishValue] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → scopedValue_valid, → makeClosure_valid]

theorem deliverOperand_valid (machine : State) (after : Transition)
    (formed : Valid machine.heap) (accepted : deliverOperand machine = .ok after) : Valid after.state.heap := by
  simp only [deliverOperand, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only []

theorem enterInvocation_valid (machine : State) (context : Context) (after : Transition)
    (formed : Valid machine.heap) (accepted : enterInvocation machine context = .ok after) : Valid after.state.heap := by
  unfold enterInvocation at accepted
  split at accepted <;> try contradiction
  exact invokeFunction_valid _ _ _ _ _ _ accepted formed

theorem enterBinding_valid (machine : State) (context : Context) (after : Transition)
    (formed : Valid machine.heap) (accepted : enterBinding machine context = .ok after) : Valid after.state.heap := by
  unfold enterBinding at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i var next bindings parent tail stacked
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, created, rfl⟩ := accepted
  have next := createScope_valid _ _ _ _ _ _ _ _ created formed
  exact next

theorem enterPattern_valid (machine : State) (context : Context) (vars : List VariableId)
    (parts : List SemanticValue) (owner : Custody.Owner) (body : TermId) (bindings : Environment) (after : Transition)
    (formed : Valid machine.heap)
    (accepted : enterPattern machine context vars parts owner body bindings = .ok after) : Valid after.state.heap := by
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, created, rfl⟩ := accepted
  have next := createScope_valid _ _ _ _ _ _ _ _ created formed
  exact next

theorem executeControlTerm_valid (machine : State) (context : Context) (after : Transition)
    (formed : Valid machine.heap)
    (accepted : executeControlTerm machine context = .ok after) : Valid after.state.heap := by
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
    exact applyClosure_valid _ _ _ _ _ accepted formed
  · split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, rfl⟩ := accepted
    exact formed
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨var, body⟩, _, accepted⟩ := accepted
    exact enterPattern_valid _ _ _ _ _ _ _ _ formed accepted
  · split at accepted <;> try contradiction
    exact enterPattern_valid _ _ _ _ _ _ _ _ formed accepted

theorem leaveInvocation_valid (machine : State) (after : Transition) (formed : Valid machine.heap)
    (accepted : leaveInvocation machine = .ok after) : Valid after.state.heap := by
  unfold leaveInvocation at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  exact leaveScope_valid _ _ _ _ _ _ formed accepted

theorem restoreResumeCaller_valid (machine : State) (after : Transition) (formed : Valid machine.heap)
    (accepted : restoreResumeCaller machine = .ok after) : Valid after.state.heap := by
  unfold restoreResumeCaller at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i caller parent tail _
  have entered : Valid ({machine with scope := parent, invocation := caller, stack := tail} : State).heap := formed
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, heap, moved, finished⟩ := accepted
  have ready := temporary_valid _ _ _ temporaryOk entered
  have same := move_scopes _ _ _ _ moved
  apply finish_reserved _ _ _ finished
  · simpa only [Valid, same] using ready.1
  · simpa only [Ready, same, retainAt] using ready.2

theorem completeHandler_valid (machine : State) (context : Context) (after : Transition)
    (formed : Valid machine.heap)
    (accepted : completeHandler machine context = .ok after) : Valid after.state.heap := by
  unfold completeHandler at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact formed

theorem releaseScope_valid (machine : State) (after : Transition) (formed : Valid machine.heap)
    (accepted : releaseScope machine = .ok after) : Valid after.state.heap := by
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

theorem installHandler_valid (machine : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (bindings : Environment) (after : Transition)
    (formed : Valid machine.heap)
    (accepted : installHandler machine context handler body arguments stored bindings = .ok after) : Valid after.state.heap := by
  simp only [installHandler, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, ⟨store, capabilities⟩, allocated, applied⟩ := accepted
  have heap : Valid store := by
    apply foldlM_preserves _ _ (fun pair : Heap × List Located => Valid pair.1) ?_ _ _ allocated formed
    intro before item after accepted bounded
    rcases before with ⟨heap, capabilities⟩
    rcases item with ⟨clause, schema⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, ⟨next, value⟩, allocated, rfl⟩ := accepted
    simpa only [Valid, (allocation_scopes _ _ _ _ _ _ _ allocated).1] using bounded
  exact applyClosure_valid _ _ _ _ _ applied heap

theorem enterRegion_valid (machine : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition) (formed : Valid machine.heap)
    (accepted : enterRegion machine context descriptor body arguments = .ok after) : Valid after.state.heap := by
  simp only [enterRegion, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, ⟨store, region⟩, allocated, applied⟩ := accepted
  have next : Valid store := by simpa only [Valid, (allocation_scopes _ _ _ _ _ _ _ allocated).1] using formed
  exact applyClosure_valid _ _ _ _ _ applied next

end HoldingOwners
end BoundaryV2.Profile.Source.Machine
