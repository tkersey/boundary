import BoundaryV2.SourceIdentityClone

namespace BoundaryV2.Profile.Source.Machine
namespace IdentitySupport

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem enterInvocation_valid (machine : State) (context : Context) (after : Transition)
    (bounded : ValidAt limit machine) (upper : Upper limit after.state.heap)
    (accepted : enterInvocation machine context = .ok after) : ValidAt limit after.state := by
  unfold enterInvocation at accepted
  split at accepted <;> try contradiction
  exact invokeFunction_valid _ _ _ _ _ _ bounded upper accepted

theorem enterBinding_valid (machine : State) (context : Context) (after : Transition)
    (bounded : ValidAt limit machine) (upper : Upper limit after.state.heap)
    (accepted : enterBinding machine context = .ok after) : ValidAt limit after.state := by
  unfold enterBinding at accepted
  split at accepted <;> try contradiction
  rename_i value executing
  split at accepted <;> try contradiction
  rename_i var next bindings parent tail stacked
  have parentBound : Bound limit parent := bounded.frames (.binding var next bindings parent) (by simp [stacked])
  have tailBound : ∀ frame ∈ tail, FrameValid limit frame := fun frame member => bounded.frames frame (by simp [stacked, member])
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have middleBounded := createScope_valid machine context machine.invocation (some parent) [var] [value] bindings middle entered bounded bounded.invocation
    (by simpa using parentBound) upper scopeOk
  refine ⟨middleBounded.heap, ?_, trivial, middleBounded.scope, middleBounded.invocation⟩
  split
  · exact tailBound
  · intro frame member
    rcases List.mem_cons.mp member with head | tail
    · cases head; exact middleBounded.scope
    · exact tailBound frame tail

theorem enterPattern_valid (machine : State) (context : Context) (vars : List VariableId)
    (parts : List SemanticValue) (owner : Custody.Owner) (body : TermId) (bindings : Environment) (after : Transition)
    (bounded : ValidAt limit machine) (upper : Upper limit after.state.heap)
    (accepted : enterPattern machine context vars parts owner body bindings = .ok after) : ValidAt limit after.state := by
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have middleBounded := createScope_valid machine context machine.invocation (some machine.scope) vars
    (parts.map (fun value => Located.mk value owner)) bindings middle entered bounded bounded.invocation
    (by simpa using bounded.scope) upper scopeOk
  refine ⟨middleBounded.heap, ?_, trivial, middleBounded.scope, middleBounded.invocation⟩
  split
  · exact bounded.frames
  · intro frame member
    rcases List.mem_cons.mp member with head | tail
    · cases head; exact middleBounded.scope
    · exact bounded.frames frame tail

theorem leaveScope_valid (machine : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition)
    (bounded : ValidAt limit machine) (parentBound : Bound limit parent) (invocationBound : Bound limit invocation)
    (framesBound : ∀ frame ∈ tail, FrameValid limit frame)
    (accepted : leaveScope machine parent invocation tail value = .ok after) : ValidAt limit after.state := by
  simp only [leaveScope, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, heap, moved, delivered, finished, rfl⟩ := accepted
  have entered : ValidAt limit {machine with scope := parent, invocation := invocation, stack := tail} :=
    ⟨bounded.heap, framesBound, bounded.control, parentBound, invocationBound⟩
  have deliveredBounded := finishTemporary_valid (move_valid (temporary_valid entered temporaryOk) moved) finished
  exact ⟨deliveredBounded.heap, deliveredBounded.frames, bounded.scope, deliveredBounded.scope, deliveredBounded.invocation⟩

theorem leaveInvocation_valid (machine : State) (after : Transition) (bounded : ValidAt limit machine)
    (accepted : leaveInvocation machine = .ok after) : ValidAt limit after.state := by
  unfold leaveInvocation at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i caller parent tail stacked
  have frameBound : Bound limit caller ∧ Bound limit parent := bounded.frames (.invocation caller parent) (by simp [stacked])
  exact leaveScope_valid _ _ _ _ _ _ bounded frameBound.2 frameBound.1
    (fun frame member => bounded.frames frame (by simp [stacked, member])) accepted

theorem restoreResumeCaller_valid (machine : State) (after : Transition) (bounded : ValidAt limit machine)
    (accepted : restoreResumeCaller machine = .ok after) : ValidAt limit after.state := by
  unfold restoreResumeCaller at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i caller parent tail stacked
  have frameBound : Bound limit caller ∧ Bound limit parent := bounded.frames (.restore caller parent) (by simp [stacked])
  have entered : ValidAt limit {machine with scope := parent, invocation := caller, stack := tail} :=
    ⟨bounded.heap, fun frame member => bounded.frames frame (by simp [stacked, member]),
      bounded.control, frameBound.2, frameBound.1⟩
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, heap, moved, finished⟩ := accepted
  exact finishTemporary_valid (move_valid (temporary_valid entered temporaryOk) moved) finished

theorem completeHandler_valid (machine : State) (context : Context) (after : Transition)
    (bounded : ValidAt limit machine)
    (accepted : completeHandler machine context = .ok after) : ValidAt limit after.state := by
  unfold completeHandler at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i activation tail stacked
  have activationBound : ActivationValid limit activation := bounded.frames (.handler activation) (by simp [stacked])
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact ⟨bounded.heap, fun frame member => bounded.frames frame (by simp [stacked, member]),
    trivial, activationBound.2.1, activationBound.2.2.1⟩

theorem enterTerm_valid (machine : State) (source : Module) (after : Transition)
    (bounded : ValidAt limit machine) (accepted : enterTerm machine source = .ok after) : ValidAt limit after.state := by
  simp only [enterTerm, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, FrameValid, ControlValid,
    List.mem_cons, List.not_mem_nil, ← ValidAt.mk, cases ValidAt]

theorem enterExpression_valid (machine : State) (context : Context) (after : Transition)
    (bounded : ValidAt limit machine) (accepted : enterExpression machine context = .ok after) : ValidAt limit after.state := by
  simp only [enterExpression, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, finishValue] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → scopedValue_valid, → makeClosure_valid,
    FrameValid, ControlValid, List.mem_cons, List.not_mem_nil, ← ValidAt.mk, cases ValidAt]

theorem deliverOperand_valid (machine : State) (after : Transition)
    (bounded : ValidAt limit machine) (accepted : deliverOperand machine = .ok after) : ValidAt limit after.state := by
  simp only [deliverOperand, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, FrameValid, ControlValid,
    List.mem_cons, List.not_mem_nil, ← ValidAt.mk, cases ValidAt]

theorem authoredFailure_valid (machine : State) (context : Context)
    (failures : List (InstructionFailure .source)) (fault : Fault) (after : Transition)
    (bounded : ValidAt limit machine) (accepted : authoredFailure machine context failures fault = .ok after) : ValidAt limit after.state := by
  simp only [authoredFailure, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  exact ⟨bounded.heap, bounded.frames, trivial, bounded.scope, bounded.invocation⟩

theorem commitPure_valid (machine : State) (opcode : Opcode) (operands : List Located)
    (result : SemanticValue) (after : Transition) (bounded : ValidAt limit machine)
    (accepted : commitPure machine opcode operands result = .ok after) : ValidAt limit after.state := by
  simp only [commitPure, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, accepted⟩ := accepted
  have middleBounded := temporary_valid bounded temporaryOk
  split at accepted
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, _, _, _, finished⟩ := accepted
    exact finishTemporary_valid middleBounded finished
  · simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨heap, moved, _, _, custody, consumed, finished⟩ := accepted
    have movedBounded := move_valid middleBounded moved
    have consumedBounded : ValidAt limit {middle with heap := {heap with custody := custody}} :=
      ⟨⟨movedBounded.heap.objects, movedBounded.heap.scopes, movedBounded.heap.invocations,
        movedBounded.heap.obligations, movedBounded.heap.loans⟩, movedBounded.frames,
        movedBounded.control, movedBounded.scope, movedBounded.invocation⟩
    exact finishTemporary_valid consumedBounded finished

theorem invokeFunction_invocation_counter (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction machine context function bindings arguments = .ok after) :
    after.state.heap.nextInvocation = machine.heap.nextInvocation + 1 := by
  simp only [invokeFunction, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, ⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  exact congrArg (· + 1) (createScope_metadata _ _ _ _ _ _ _ _ _ scopeOk).1

theorem retire_invocation_counter (heap after : Heap) (value : Located)
    (accepted : retireObject heap value = some after) : after.nextInvocation = heap.nextInvocation := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨_, _, middle, consumed, rfl⟩ := accepted
  simp [consumeValue, Option.bind_eq_some_iff] at consumed
  obtain ⟨_, _, rfl⟩ := consumed
  rfl

theorem applyClosure_invocation_counter (machine : State) (context : Context) (closure : Located)
    (arguments : List Located) (after : Transition)
    (accepted : applyClosure machine context closure arguments = .ok after) :
    after.state.heap.nextInvocation = machine.heap.nextInvocation + 1 := by
  simp only [applyClosure, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
  cases stored <;> try contradiction
  obtain ⟨⟨schema, token, reference⟩, _⟩ := CellStability.lookupObject_reference _ _ _ _ looked
  rw [reference] at accepted
  cases token with
  | none =>
    simp only [pure, Except.pure, Except.bind] at accepted
    exact invokeFunction_invocation_counter _ _ _ _ _ _ accepted
  | some token =>
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨store, retired, accepted⟩ := accepted
    exact (invokeFunction_invocation_counter _ _ _ _ _ _ accepted).trans
      (congrArg (· + 1) (retire_invocation_counter _ _ _ retired))

theorem leaveLexical_valid (machine : State) (after : Transition) (bounded : ValidAt limit machine)
    (accepted : leaveLexical machine = .ok after) : ValidAt limit after.state := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i scope tail stacked
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, record, recordAt, parent, parentAt, returned, leftScope, accepted⟩ := accepted
  have recordBound := bounded.heap.scopes record (List.mem_of_getElem? recordAt)
  have returnedBounded := leaveScope_valid _ _ _ _ _ _ bounded (recordBound.2.2 parent parentAt)
    bounded.invocation (fun frame member => bounded.frames frame (by simp [stacked, member])) leftScope
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨parentRecord, parentFound, heap, moved, rfl⟩ := accepted
  have parentBounded := returnedBounded.heap.scopes parentRecord (List.mem_of_getElem? parentFound)
  have movedBounded := move_valid returnedBounded moved
  refine ⟨⟨movedBounded.heap.objects, ?_, movedBounded.heap.invocations,
    movedBounded.heap.obligations, movedBounded.heap.loans⟩, movedBounded.frames,
    trivial, movedBounded.scope, movedBounded.invocation⟩
  intro record member
  rcases List.mem_or_eq_of_mem_set member with old | changed
  · exact movedBounded.heap.scopes record old
  · cases changed
    exact parentBounded

theorem releaseScope_valid (machine : State) (after : Transition) (bounded : ValidAt limit machine)
    (accepted : releaseScope machine = .ok after) : ValidAt limit after.state := by
  unfold releaseScope at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact ⟨bounded.heap, bounded.frames, trivial, bounded.scope, bounded.invocation⟩

theorem resumeRelease_valid (machine : State) (released : AfterRelease) (bounded : ValidAt limit machine) :
    ValidAt limit (resumeRelease machine released).state := by
  refine ⟨bounded.heap, bounded.frames, ?_, bounded.scope, bounded.invocation⟩
  cases released <;> trivial

end IdentitySupport
end BoundaryV2.Profile.Source.Machine
