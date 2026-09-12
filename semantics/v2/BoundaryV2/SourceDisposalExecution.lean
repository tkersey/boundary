import BoundaryV2.SourceDisposalCleanup

namespace BoundaryV2.Profile.Source.Machine
namespace DisposalShape
open DisposalProgress

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem enterTerm_valid (machine : State) (source : Module) (after : Transition)
    (accepted : enterTerm machine source = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold enterTerm at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  repeat' split at accepted
  all_goals cases accepted
  all_goals exact ⟨by simp [control], by simpa [frame] using valid.2.1, valid.2.2⟩

theorem delivered_valid (before : State) (after : Transition) (valid : Valid before)
    (shape : (∃ result, after.state.control = .delivered result) ∧ after.state.stack = before.stack ∧ HeapValid after.state.heap) :
    Valid after.state := by
  obtain ⟨⟨value, delivered⟩, stacked, stored⟩ := shape
  exact ⟨by simp [control, delivered], by simpa only [stacked] using valid.2.1, stored⟩

theorem enterExpression_valid (machine : State) (context : Context) (after : Transition)
    (accepted : enterExpression machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold enterExpression at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨schema, expression⟩, _, accepted⟩ := accepted
  cases expression with
  | «variable» binder =>
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨value, _, _, _, _, _, rfl⟩ := accepted
    exact ⟨by simp [control, finishValue], valid.2⟩
  | literal constant =>
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨value, _, _, _, accepted⟩ := accepted
    exact scopedValue_valid _ _ _ accepted valid
  | lambda function => exact delivered_valid _ _ valid (makeClosure_shape _ _ _ _ _ _ accepted valid.2.2)
  | primitive opcode operands immediate failures =>
    cases operands <;> cases accepted
    all_goals exact ⟨by simp [control], by simpa [frame] using valid.2.1, valid.2.2⟩

theorem deliverOperand_valid (machine : State) (after : Transition)
    (accepted : deliverOperand machine = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold deliverOperand at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i intent bindings remaining evaluated tail stacked
  have tailValid := valid.tail stacked
  split at accepted <;> cases accepted
  all_goals exact ⟨by simp [control], by simpa [frame] using tailValid, valid.2.2⟩

theorem executePrimitive_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executePrimitive machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold executePrimitive at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · contradiction
  · obtain ⟨⟨exit, unwinding⟩, stacked, objects⟩ := OperandStructure.authoredFailure_shape _ _ _ _ _ accepted
    exact ⟨by simp [control, unwinding], by simpa only [stacked] using valid.2.1, valid.2.2.of_objects objects⟩
  · exact commitPure_valid _ _ _ _ _ accepted valid
  · exact delivered_valid _ _ valid (heapPrimitive_shape _ _ _ _ _ _ _ accepted valid.2.2)

theorem enterInvocation_valid (machine : State) (context : Context) (after : Transition)
    (accepted : enterInvocation machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold enterInvocation at accepted
  split at accepted <;> try contradiction
  exact invokeFunction_valid _ _ _ _ _ _ accepted valid

theorem enterBinding_valid (machine : State) (context : Context) (after : Transition)
    (accepted : enterBinding machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold enterBinding at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i binder body bindings parent tail stacked
  have tailValid := valid.tail stacked
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have middleValid := createScope_valid _ _ _ _ _ _ _ _ _ scopeOk valid
  refine ⟨by simp [control], ?_, middleValid.2.2⟩
  split <;> simpa [frame] using tailValid

theorem enterPattern_valid (machine : State) (context : Context) (vars : List VariableId)
    (parts : List SemanticValue) (owner : Custody.Owner) (body : TermId) (bindings : Environment) (after : Transition)
    (accepted : enterPattern machine context vars parts owner body bindings = .ok after)
    (valid : Valid machine) : Valid after.state := by
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have middleValid := createScope_valid _ _ _ _ _ _ _ _ _ scopeOk valid
  refine ⟨by simp [control], ?_, middleValid.2.2⟩
  split <;> simpa [frame] using valid.2.1

theorem executeControlTerm_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executeControlTerm machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold executeControlTerm at accepted
  split at accepted <;> try contradiction
  rename_i authored bindings operands executing
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  cases authored <;> simp only at accepted <;> try contradiction
  case conditional =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    exact ⟨by simp [control], valid.2⟩
  case call => cases accepted; exact ⟨by simp [control], valid.2⟩
  case apply =>
    split at accepted <;> try contradiction
    exact applyClosure_valid _ _ _ _ _ accepted valid
  case fail =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, rfl⟩ := accepted
    exact ⟨by simp [control], valid.2⟩
  case matchSum =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact enterPattern_valid _ _ _ _ _ _ _ _ accepted valid
  case unpackProduct =>
    split at accepted <;> try contradiction
    exact enterPattern_valid _ _ _ _ _ _ _ _ accepted valid

theorem leaveScope_valid (machine : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition)
    (accepted : leaveScope machine parent invocation tail value = .ok after)
    (valid : Valid machine) (tailValid : ∀ value ∈ tail.flatMap frame, Leaf value) : Valid after.state := by
  simp only [leaveScope, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, store, moved, finished, finishOk, rfl⟩ := accepted
  have middleValid := temporary_valid _ _ _ temporaryOk (show Valid
    { machine with scope := parent, invocation := invocation, stack := tail } from ⟨valid.1, tailValid, valid.2.2⟩)
  have movedValid : Valid { middle with heap := store } := ⟨middleValid.1, middleValid.2.1, move_valid _ _ _ _ moved middleValid.2.2⟩
  have finishedValid := finishTemporary_valid _ _ _ finishOk movedValid
  exact ⟨by simp [control], finishedValid.2⟩

theorem leaveInvocation_valid (machine : State) (after : Transition)
    (accepted : leaveInvocation machine = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold leaveInvocation at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i invocation parent tail stacked
  exact leaveScope_valid _ _ _ _ _ _ accepted valid (valid.tail stacked)

theorem leaveLexical_valid (machine : State) (after : Transition)
    (accepted : leaveLexical machine = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i scope tail stacked
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, record, _, parent, _, result, leaving, accepted⟩ := accepted
  have leavingValid := leaveScope_valid _ _ _ _ _ _ leaving valid (valid.tail stacked)
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, store, moved, rfl⟩ := accepted
  have movedValid := move_valid _ _ _ _ moved leavingValid.2.2
  exact ⟨by simp [control], leavingValid.2.1, movedValid⟩

theorem restoreResumeCaller_valid (machine : State) (after : Transition)
    (accepted : restoreResumeCaller machine = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold restoreResumeCaller at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i invocation scope tail stacked
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, store, moved, finished⟩ := accepted
  have middleValid := temporary_valid _ _ _ temporaryOk (show Valid
    { machine with scope := scope, invocation := invocation, stack := tail } from ⟨valid.1, valid.tail stacked, valid.2.2⟩)
  exact finishTemporary_valid _ _ _ finished ⟨middleValid.1, middleValid.2.1, move_valid _ _ _ _ moved middleValid.2.2⟩

theorem completeHandler_valid (machine : State) (context : Context) (after : Transition)
    (accepted : completeHandler machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold completeHandler at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i active tail stacked
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact ⟨by simp [control], valid.tail stacked, valid.2.2⟩

theorem unwindStep_valid (machine : State) (context : Context) (after : Transition)
    (accepted : unwindStep machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold unwindStep at accepted
  split at accepted <;> try contradiction
  rename_i original unwinding
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨scope, _, accepted⟩ := accepted
  cases stacked : machine.stack with
  | nil =>
    simp only [stacked] at accepted
    split at accepted
    · cases accepted; exact ⟨liveOwned_list _ _, by simpa only [stacked] using valid.2.1, valid.2.2⟩
    · split at accepted <;> try contradiction
      all_goals cases accepted; simpa only [Valid, stacked] using valid
  | cons saved tail =>
    have tailValid := valid.tail stacked
    cases saved <;> simp only [stacked] at accepted
    case invocation =>
      split at accepted
      · cases accepted; exact ⟨liveOwned_list _ _, by simpa only [stacked] using valid.2.1, valid.2.2⟩
      · cases accepted; exact ⟨valid.1, tailValid, valid.2.2⟩
    case lexical =>
      split at accepted
      · cases accepted; exact ⟨liveOwned_list _ _, by simpa only [stacked] using valid.2.1, valid.2.2⟩
      · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨_, _, _, _, rfl⟩ := accepted
        exact ⟨valid.1, tailValid, valid.2.2⟩
    case protection => exact beginCleanup_valid _ _ _ _ _ _ _ accepted valid tailValid
    case cleanupReturn => exact finishCleanupUnwind_valid _ _ _ _ _ _ _ _ accepted valid.2.2 tailValid
    case releaseReturn => cases accepted; exact ⟨by simp [control], tailValid, valid.2.2⟩
    case disposalReturn remaining released invocation callerScope =>
      have remainingValid : ∀ value ∈ remaining, Leaf value := by
        intro value member
        apply valid.2.1
        simp [stacked, frame, member]
      simp only [Bool.false_and, Bool.false_eq_true, ↓reduceIte] at accepted
      repeat' split at accepted
      all_goals simp only [pure, Except.pure, Except.bind, Except.ok.injEq] at accepted
      all_goals cases accepted
      all_goals exact ⟨remainingValid, tailValid, valid.2.2⟩
    all_goals cases accepted; exact ⟨valid.1, tailValid, valid.2.2⟩

theorem cancel_control (before : Control) (reason : Protocol.Reason) :
    control (cancelControl before reason) = control before := by
  cases before <;> try rfl
  case release scope after => cases after <;> rfl
  case discard values after => cases after <;> rfl

theorem external_valid (machine : State) (context : Context) (action : External) (after : Transition)
    (accepted : external machine context action = .ok after) (valid : Valid machine) : Valid after.state := by
  have running : Valid { machine with status := .running } := valid
  have cancelled (reason : Protocol.Reason) : Valid
      { machine with status := .running, control := cancelControl machine.control reason, cancellation := some reason } :=
    ⟨by simpa only [cancel_control] using valid.1, valid.2⟩
  have cancellationOnly (reason : Protocol.Reason) : Valid { machine with cancellation := some reason } := valid
  have scopedResult (value : SemanticValue) (transition : Transition)
      (checked : scopedValue { machine with status := .running } value = .ok transition) : Valid transition.state :=
    scopedValue_valid _ _ _ checked running
  cases phase : machine.status <;> cases action <;>
    simp only [external, phase, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw,
      Except.bind] at accepted <;> try contradiction
  all_goals grind (gen := 32) only []

theorem tickRunning_valid (machine : State) (context : Context) (after : Transition)
    (accepted : tickRunning machine context = .ok after) (valid : Valid machine)
    (shapes : ValueInventory.All (ValueShape context.source.schemas) machine) : Valid after.state := by
  cases executing : machine.control <;> simp only [tickRunning, executing] at accepted
  case term => exact enterTerm_valid _ _ _ accepted valid
  case expression => exact enterExpression_valid _ _ _ accepted valid
  case invoke => exact enterInvocation_valid _ _ _ accepted valid
  case release => exact releaseScope_valid _ _ accepted valid
  case discard => exact discardValues_valid _ _ _ accepted valid
  case unwind => exact unwindStep_valid _ _ _ accepted valid
  case execute intent bindings operands =>
    cases intent with
    | primitive => exact executePrimitive_valid _ _ _ accepted valid
    | term authored =>
      cases authored <;> first
        | exact executeEffectTerm_valid _ _ _ accepted valid
        | exact executeCleanupTerm_valid _ _ _ accepted valid shapes
        | exact executeControlTerm_valid _ _ _ accepted valid
  case delivered value =>
    cases stacked : machine.stack with
    | nil =>
      simp only [stacked, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
      simpa only [Valid, stacked, executing] using valid
    | cons saved tail =>
      have tailValid := valid.tail stacked
      cases saved <;> simp only [stacked] at accepted
      all_goals first
        | exact deliverOperand_valid _ _ accepted valid
        | exact enterBinding_valid _ _ _ accepted valid
        | exact leaveInvocation_valid _ _ accepted valid
        | exact leaveLexical_valid _ _ accepted valid
        | exact restoreResumeCaller_valid _ _ accepted valid
        | exact completeHandler_valid _ _ _ accepted valid
        | exact beginCleanup_valid _ _ _ _ _ _ _ accepted valid tailValid
        | exact finishCleanup_valid _ _ _ accepted valid
        | exact finishDisposal_valid _ _ accepted valid
        | (cases accepted; exact ⟨valid.1, tailValid, valid.2.2⟩)
        | (cases accepted; exact ⟨by simp [control], tailValid, valid.2.2⟩)
        | contradiction

theorem tick_valid (machine : State) (context : Context) (after : Transition)
    (accepted : tick machine context = .ok after) (valid : Valid machine)
    (shapes : ValueInventory.All (ValueShape context.source.schemas) machine) : Valid after.state := by
  cases phase : machine.status <;> simp only [tick, phase] at accepted
  · exact tickRunning_valid _ _ _ accepted valid shapes
  all_goals cases accepted; exact valid

theorem step_valid (context : Context) (before after : State) (events : List Event)
    (step : Step context before events after) (valid : Valid before)
    (shapes : ValueInventory.All (ValueShape context.source.schemas) before) : Valid after := by
  cases step with
  | internal accepted => exact tick_valid _ _ _ accepted valid shapes
  | external accepted => exact external_valid _ _ _ _ accepted valid

theorem initial_valid (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) : Valid machine := by
  simp only [initial, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ := accepted
  simp [Valid, control, HeapValid]

/-- Every pending disposal occurrence is a reference leaf, both in active
control and saved disposal callers within current or dormant continuations. -/
theorem initialized_execution_preserves_disposal_leaves (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : Valid after := by
  have extend : ∀ machine emitted after, Steps context machine emitted after →
      ∀ prefixEvents, Steps context before prefixEvents machine → Valid machine → Valid after := by
    intro machine emitted after path
    induction path with
    | refl => intro _ _ valid; exact valid
    | @cons machine first middle rest after step suffix induction =>
      intro prefixEvents history valid
      exact induction (prefixEvents ++ first) (steps_trans history (by simpa using Steps.cons step Steps.refl))
        (step_valid _ _ _ _ step valid (initialized_execution_preserves_value_shapes _ _ _ _ _ initialized history))
  exact extend before events after steps [] .refl (initial_valid _ _ _ initialized)

/-- Actual initialized execution cannot get stuck in disposal. Reference
safety, object schemas, and the owning-leaf shape all follow from reachability. -/
theorem reachable_discard_progress (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (values : List Located) (released : AfterRelease)
    (executing : machine.control = .discard values released) (running : machine.status = .running) :
    ∃ after, tick machine context = .ok after ∧ after.state ≠ machine := by
  have leaves := (initialized_execution_preserves_disposal_leaves _ _ _ _ _ initialized steps).1
  simp only [control, executing] at leaves
  exact reachable_discard_leaves _ _ _ _ _ initialized steps _ _ executing leaves running

end DisposalShape
end BoundaryV2.Profile.Source.Machine
