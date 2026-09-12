import BoundaryV2.SourceObjectOwners

namespace BoundaryV2.Profile.Source.Machine
namespace ObjectOwners

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem move_valid {before after : Heap} {values : List Located} {receiver : Nat → Custody.Owner}
    (formed : Valid before) (accepted : moveValues before values receiver = some after) : Valid after := by
  simpa only [Valid, Heap.lookup, move_objects _ _ _ _ accepted] using formed

theorem temporary_valid {before after : State} {owner : Custody.Owner}
    (formed : Valid before.heap) (accepted : temporary before = .ok (after, owner)) : Valid after.heap := by
  simpa only [Valid, Heap.lookup, temporary_objects _ _ _ accepted] using formed

theorem finishTemporary_valid {machine : State} {value : Located} {after : Transition}
    (formed : Valid machine.heap) (accepted : finishTemporary machine value = .ok after) : Valid after.state.heap := by
  simpa only [Valid, Heap.lookup, finishTemporary_objects _ _ _ accepted] using formed

theorem replace_valid (heap after : Heap) (node : NodeId) (stored : Object)
    (accepted : replaceObject heap node stored = some after) (formed : Valid heap)
    (added : Layout node stored) : Valid after := by
  unfold replaceObject at accepted
  split at accepted <;> try contradiction
  rename_i bounded
  cases accepted
  apply set_valid heap node (some stored) bounded formed
  intro actual equal
  cases equal
  exact added

theorem commitPure_valid (machine : State) (opcode : Opcode) (operands : List Located)
    (value : SemanticValue) (after : Transition) (formed : Valid machine.heap)
    (accepted : commitPure machine opcode operands value = .ok after) : Valid after.state.heap := by
  have same := (commitPure_retains_storage_and_supply _ _ _ _ _ accepted).1
  simpa only [Valid, Heap.lookup, same] using formed

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
    exact makeClosureWithValues_valid _ _ _ _ _ _ formed accepted
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
    have movedValid := move_valid (temporary_valid formed temporaryOk) moveOk
    have next := allocation_valid _ _ _ _ _ _ _ allocated movedValid trivial
    exact finishTemporary_valid next finished
  case cellGet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact scopedValue_valid _ _ _ formed accepted
  case cellSet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, store, replaced, accepted⟩ := accepted
    have next := replace_valid _ _ _ _ replaced formed trivial
    exact scopedValue_valid _ _ _ next accepted
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
    have next := allocation_valid _ _ _ _ _ _ _ allocated
      (move_valid (temporary_valid formed temporaryOk) moveOk)
      (by simp only [Layout, retainAt, move_objects _ _ _ _ moveOk])
    exact finishTemporary_valid next finished
  case unpack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, store, retired, accepted⟩ := accepted
    exact commitPure_valid _ _ _ _ _ (retire_valid _ _ _ retired formed) accepted
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
    exact finishTemporary_valid (allocation_valid _ _ _ _ _ _ _ allocated
      (temporary_valid (retire_valid _ _ _ retireOk formed) temporaryOk) (by trivial)) finished
  case resourcePack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, ⟨middle, owner⟩, temporaryOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    exact finishTemporary_valid (allocation_valid _ _ _ _ _ _ _ allocated
      (temporary_valid formed temporaryOk) (by rfl)) finished
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
      exact scopedValue_valid _ _ _ (retire_valid _ _ _ retired formed) accepted
    case borrow =>
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      exact scopedValue_valid _ _ _ formed accepted

theorem executePrimitive_valid (machine : State) (context : Context) (after : Transition)
    (formed : Valid machine.heap)
    (accepted : executePrimitive machine context = .ok after) : Valid after.state.heap := by
  unfold executePrimitive at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · exact authoredFailure_valid _ _ _ _ _ formed accepted
  · exact commitPure_valid _ _ _ _ _ formed accepted
  · exact heapPrimitive_valid _ _ _ _ _ _ _ formed accepted

theorem makeClosure_valid (machine : State) (context : Context)
    (schema : SchemaId .source) (function : FunctionId .source) (bindings : Environment) (after : Transition)
    (formed : Valid machine.heap)
    (accepted : makeClosure machine context schema function bindings = .ok after) : Valid after.state.heap := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  obtain ⟨values, _, created⟩ := accepted
  exact makeClosureWithValues_valid _ _ _ _ _ _ formed created

theorem createScope_valid (machine : State) (context : Context) (invocation : InvocationId)
    (parent : Option LexicalScopeId) (vars : List VariableId) (values : List Located) (bindings : Environment)
    (after : State) (entered : Environment) (formed : Valid machine.heap)
    (accepted : createScope machine context invocation parent vars values bindings = .ok (after, entered)) : Valid after.heap := by
  simp only [createScope, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · cases accepted; exact formed
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at accepted
    obtain ⟨_, _, store, moved, rfl, rfl⟩ := accepted
    have next := move_valid formed moved
    exact next

theorem invokeFunction_valid (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (formed : Valid machine.heap)
    (accepted : invokeFunction machine context function bindings arguments = .ok after) : Valid after.state.heap := by
  simp only [invokeFunction, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, ⟨middle, entered⟩, created, rfl⟩ := accepted
  have next := createScope_valid _ _ _ _ _ _ _ _ _ formed created
  exact next

theorem applyClosure_valid (machine : State) (context : Context) (closure : Located)
    (arguments : List Located) (after : Transition) (formed : Valid machine.heap)
    (accepted : applyClosure machine context closure arguments = .ok after) : Valid after.state.heap := by
  simp only [applyClosure, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
  cases stored <;> try contradiction
  obtain ⟨⟨schema, token, reference⟩, _⟩ := CellStability.lookupObject_reference _ _ _ _ looked
  rw [reference] at accepted
  cases token with
  | none =>
    simp only [pure, Except.pure, Except.bind] at accepted
    exact invokeFunction_valid _ _ _ _ _ _ formed accepted
  | some token =>
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨store, retired, accepted⟩ := accepted
    exact invokeFunction_valid _ _ _ _ _ _ (retire_valid _ _ _ retired formed) accepted

theorem takeCapture_valid (machine : State) (context : Context) (token : Located) (after : State × Capture)
    (formed : Valid machine.heap)
    (accepted : takeCapture machine context token = .ok after) : Valid after.1.heap := by
  simp only [takeCapture, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, _, accepted⟩ := accepted
  cases stored <;> try contradiction
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨heap, retired, rfl⟩ := accepted
    exact retire_valid _ _ _ retired formed
  · exact instantiateCapture_valid _ _ _ _ formed accepted

theorem activateCapture_valid (machine : State) (context : Context) (saved : Capture)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : State)
    (formed : Valid machine.heap)
    (accepted : activateCapture machine context saved successor = .ok after) : Valid after.heap := by
  simp only [activateCapture, bind, except_bind_ok, pure, Except.pure] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  cases successor with
  | none => cases accepted; exact formed
  | some successor =>
    rcases successor with ⟨handler, stored, bindings⟩
    simp only [except_bind_ok, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, _, rfl, rfl⟩ := accepted
    exact formed

theorem resumeValue_valid (machine : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (formed : Valid machine.heap)
    (accepted : resumeValue machine context token argument successor = .ok after) : Valid after.state.heap := by
  simp only [resumeValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, saved⟩, captured, _, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, active, activated, ⟨temporary, owner⟩, temporaryOk, store, moved, finished⟩ := accepted
  exact finishTemporary_valid (move_valid (temporary_valid
    (activateCapture_valid _ _ _ _ _ (takeCapture_valid _ _ _ _ formed captured) activated) temporaryOk) moved) finished

theorem resumeComputation_valid (machine : State) (context : Context) (token computation : Located) (after : Transition)
    (formed : Valid machine.heap)
    (accepted : resumeComputation machine context token computation = .ok after) : Valid after.state.heap := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, saved⟩, captured, active, activated, applied⟩ := accepted
  exact applyClosure_valid _ _ _ _ _
    (activateCapture_valid _ _ _ _ _ (takeCapture_valid _ _ _ _ formed captured) activated) applied

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
  exact invokeFunction_valid _ _ _ _ _ _ formed accepted

theorem enterBinding_valid (machine : State) (context : Context) (after : Transition)
    (formed : Valid machine.heap) (accepted : enterBinding machine context = .ok after) : Valid after.state.heap := by
  unfold enterBinding at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, created, rfl⟩ := accepted
  have next := createScope_valid _ _ _ _ _ _ _ _ _ formed created
  exact next

theorem enterPattern_valid (machine : State) (context : Context) (vars : List VariableId)
    (parts : List SemanticValue) (owner : Custody.Owner) (body : TermId) (bindings : Environment) (after : Transition)
    (formed : Valid machine.heap)
    (accepted : enterPattern machine context vars parts owner body bindings = .ok after) : Valid after.state.heap := by
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, created, rfl⟩ := accepted
  have next := createScope_valid _ _ _ _ _ _ _ _ _ formed created
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
    exact applyClosure_valid _ _ _ _ _ formed accepted
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

theorem leaveScope_valid (machine : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition) (formed : Valid machine.heap)
    (accepted : leaveScope machine parent invocation tail value = .ok after) : Valid after.state.heap := by
  simp only [leaveScope, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, heap, moved, delivered, finished, rfl⟩ := accepted
  have entered : Valid ({machine with scope := parent, invocation := invocation, stack := tail} : State).heap := formed
  have next := finishTemporary_valid (move_valid (temporary_valid entered temporaryOk) moved) finished
  exact next

theorem leaveInvocation_valid (machine : State) (after : Transition) (formed : Valid machine.heap)
    (accepted : leaveInvocation machine = .ok after) : Valid after.state.heap := by
  unfold leaveInvocation at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  exact leaveScope_valid _ _ _ _ _ _ formed accepted

theorem leaveLexical_valid (machine : State) (after : Transition) (formed : Valid machine.heap)
    (accepted : leaveLexical machine = .ok after) : Valid after.state.heap := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, record, _, parent, _, result, left, accepted⟩ := accepted
  have next := leaveScope_valid _ _ _ _ _ _ formed left
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨parentRecord, _, heap, moved, rfl⟩ := accepted
  have movedValid := move_valid next moved
  exact movedValid

theorem restoreResumeCaller_valid (machine : State) (after : Transition) (formed : Valid machine.heap)
    (accepted : restoreResumeCaller machine = .ok after) : Valid after.state.heap := by
  unfold restoreResumeCaller at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i caller parent tail _
  have entered : Valid ({machine with scope := parent, invocation := caller, stack := tail} : State).heap := formed
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, heap, moved, finished⟩ := accepted
  exact finishTemporary_valid (move_valid (temporary_valid entered temporaryOk) moved) finished

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
    exact allocation_valid _ _ _ _ _ _ _ allocated bounded (by trivial)
  exact applyClosure_valid _ _ _ _ _ heap applied

theorem enterRegion_valid (machine : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition) (formed : Valid machine.heap)
    (accepted : enterRegion machine context descriptor body arguments = .ok after) : Valid after.state.heap := by
  simp only [enterRegion, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, ⟨store, region⟩, allocated, applied⟩ := accepted
  have next := allocation_valid _ _ _ _ _ _ _ allocated formed (by trivial)
  exact applyClosure_valid _ _ _ _ _ next applied

end ObjectOwners
end BoundaryV2.Profile.Source.Machine
