import BoundaryV2.SourceEnvironmentTypes
import BoundaryV2.SourceOperandOutcomes
import BoundaryV2.SourcePrimitiveResults
import BoundaryV2.SourceReferenceContracts

namespace BoundaryV2.Profile.Source.Machine
namespace InternalProgress

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

private theorem changed_control (before after : State) (different : after.control ≠ before.control) : after ≠ before := by
  intro same
  exact different (congrArg State.control same)

private theorem changed_stack (before after : State) (different : after.stack.length ≠ before.stack.length) : after ≠ before := by
  intro same
  exact different (congrArg (fun state : State => state.stack.length) same)

private theorem changed_status (before after : State) (different : after.status ≠ before.status) : after ≠ before := by
  intro same
  exact different (congrArg State.status same)

theorem enterTerm_changes (machine : State) (source : Module) (after : Transition)
    (running : machine.status = .running) (accepted : enterTerm machine source = .ok after) : after.state ≠ machine := by
  unfold enterTerm at accepted
  split at accepted <;> try contradiction
  rename_i reference bindings executing
  split at accepted <;> try contradiction
  split at accepted
  case h_1 =>
    cases accepted
    apply changed_stack
    simp
  case h_2 =>
    cases accepted
    apply changed_status
    simp [running]
  all_goals repeat' split at accepted
  all_goals cases accepted
  all_goals apply changed_control
  all_goals simp [executing]

theorem makeClosureWithValues_delivers (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues machine context schema function values = .ok after) :
    ∃ value, after.state.control = .delivered value := by
  simp only [makeClosureWithValues, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, finished⟩ := accepted
  exact ⟨_, finishTemporary_delivers _ _ _ finished⟩

theorem makeClosure_delivers (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (bindings : Environment) (after : Transition)
    (accepted : makeClosure machine context schema function bindings = .ok after) :
    ∃ value, after.state.control = .delivered value := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  obtain ⟨_, _, constructed⟩ := accepted
  exact makeClosureWithValues_delivers _ _ _ _ _ _ constructed

theorem enterExpression_changes (machine : State) (context : Context) (after : Transition)
    (accepted : enterExpression machine context = .ok after) : after.state ≠ machine := by
  unfold enterExpression at accepted
  split at accepted <;> try contradiction
  rename_i reference bindings executing
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨schema, expression⟩, _, accepted⟩ := accepted
  cases expression with
  | «variable» var =>
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
    apply changed_control
    simp [finishValue, executing]
  | literal constant =>
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, _, _, finished⟩ := accepted
    obtain ⟨value, delivered, _⟩ := scopedValue_delivers _ _ _ finished
    apply changed_control
    simp [delivered, executing]
  | lambda function =>
    obtain ⟨value, delivered⟩ := makeClosure_delivers _ _ _ _ _ _ accepted
    apply changed_control
    simp [delivered, executing]
  | primitive opcode operands immediate failures =>
    cases operands <;> cases accepted
    · apply changed_control; simp [executing]
    · apply changed_stack; simp

theorem deliverOperand_changes (machine : State) (after : Transition)
    (accepted : deliverOperand machine = .ok after) : after.state ≠ machine := by
  unfold deliverOperand at accepted
  split at accepted <;> try contradiction
  rename_i value executing
  split at accepted <;> try contradiction
  split at accepted <;> cases accepted
  all_goals apply changed_control
  all_goals simp [executing]

theorem releaseScope_changes (machine : State) (after : Transition)
    (accepted : releaseScope machine = .ok after) : after.state ≠ machine := by
  unfold releaseScope at accepted
  split at accepted <;> try contradiction
  rename_i scope released executing
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  apply changed_control
  simp [executing]

set_option maxRecDepth 4096 in
set_option maxHeartbeats 1600000 in
theorem heapPrimitive_delivers (machine : State) (context : Context)
    (operation : Primitives.GraphOperation) (schema : SchemaId .source) (immediate : Nat)
    (operands : List Located) (after : Transition)
    (accepted : heapPrimitive machine context operation schema immediate operands = .ok after) :
    ∃ value, after.state.control = .delivered value := by
  cases control : after.state.control
  case delivered value => exact ⟨value, rfl⟩
  all_goals cases operation <;> simp only [heapPrimitive, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  all_goals try split at accepted
  all_goals grind (gen := 32) only [except_bind_ok, fromOption_ok,
    → finishTemporary_delivers, → scopedValue_delivers, → commitPure_delivers,
    → makeClosureWithValues_delivers]

theorem executePrimitive_changes (machine : State) (context : Context) (after : Transition)
    (accepted : executePrimitive machine context = .ok after) : after.state ≠ machine := by
  unfold executePrimitive at accepted
  split at accepted <;> try contradiction
  rename_i schema opcode immediate failures bindings operands executing
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · contradiction
  · simp only [authoredFailure, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
    apply changed_control; simp [executing]
  · obtain ⟨value, delivered, _⟩ := commitPure_delivers _ _ _ _ _ accepted
    apply changed_control; simp [executing, delivered]
  · obtain ⟨value, delivered⟩ := heapPrimitive_delivers _ _ _ _ _ _ _ accepted
    apply changed_control; simp [executing, delivered]

theorem invokeFunction_enters (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction machine context function bindings arguments = .ok after) :
    ∃ body environment, after.state.control = .term body environment := by
  obtain ⟨body, environment, control, _⟩ := invokeFunction_enters_typed_environment _ _ _ _ _ _ accepted
  exact ⟨body, environment, control⟩

theorem applyClosure_enters (machine : State) (context : Context) (closure : Located)
    (arguments : List Located) (after : Transition)
    (accepted : applyClosure machine context closure arguments = .ok after) :
    ∃ body environment, after.state.control = .term body environment := by
  simp only [applyClosure, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, _, invoked⟩ := accepted
    exact invokeFunction_enters _ _ _ _ _ _ invoked
  · simp only [pure, Except.pure, Except.bind] at accepted
    exact invokeFunction_enters _ _ _ _ _ _ accepted

theorem enterInvocation_changes (machine : State) (context : Context) (after : Transition)
    (accepted : enterInvocation machine context = .ok after) : after.state ≠ machine := by
  unfold enterInvocation at accepted
  split at accepted <;> try contradiction
  rename_i function bindings arguments executing
  obtain ⟨body, environment, entered⟩ := invokeFunction_enters _ _ _ _ _ _ accepted
  apply changed_control; simp [executing, entered]

theorem enterBinding_changes (machine : State) (context : Context) (after : Transition)
    (accepted : enterBinding machine context = .ok after) : after.state ≠ machine := by
  unfold enterBinding at accepted
  split at accepted <;> try contradiction
  rename_i value executing
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  apply changed_control; simp [executing]

theorem executeControlTerm_changes (machine : State) (context : Context) (after : Transition)
    (accepted : executeControlTerm machine context = .ok after) : after.state ≠ machine := by
  have afterNot := OperandSchemas.executeControlTerm_nonexecuting _ _ _ accepted
  unfold executeControlTerm at accepted
  split at accepted <;> try contradiction
  rename_i authored bindings operands executing
  apply changed_control
  intro same
  simp only [same, executing, OperandSchemas.NonExecuting] at afterNot

theorem executeCleanupTerm_changes (machine : State) (context : Context) (after : Transition)
    (accepted : executeCleanupTerm machine context = .ok after) : after.state ≠ machine := by
  have afterNot := OperandSchemas.executeCleanupTerm_nonexecuting _ _ _ accepted
  unfold executeCleanupTerm at accepted
  split at accepted <;> try contradiction
  rename_i authored bindings operands executing
  apply changed_control
  intro same
  simp only [same, executing, OperandSchemas.NonExecuting] at afterNot

theorem retire_changes (before after : Heap) (value : Located)
    (accepted : retireObject before value = some after) : after ≠ before := by
  obtain ⟨schema, node, token, shape, absent, _⟩ := ReferenceContracts.retire_lookup _ _ _ accepted
  unfold retireObject at accepted
  simp only [shape, bind, Option.bind_eq_some_iff] at accepted
  obtain ⟨stored, found, _⟩ := accepted
  intro same
  rw [same, found] at absent
  contradiction

theorem discardValues_changes (machine : State) (context : Context) (after : Transition)
    (accepted : discardValues machine context = .ok after) : after.state ≠ machine := by
  unfold discardValues at accepted
  split at accepted <;> try contradiction
  rename_i values released executing
  split at accepted
  · cases accepted
    cases released <;> apply changed_control <;> simp [resumeRelease, executing]
  · rename_i value rest
    split at accepted
    · cases accepted
      apply changed_control
      intro same
      simp only [executing, Control.discard.injEq] at same
      have length := congrArg List.length same.1
      simp at length
    · simp only [bind, except_bind_ok] at accepted
      obtain ⟨⟨node, object⟩, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      all_goals
        simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨heap, retired, rfl⟩ := accepted
        intro same
        exact retire_changes _ _ _ retired (congrArg State.heap same)

theorem openRequest_shape (machine : State) (context : Context) (operation : Operation)
    (operands : List Located) (after : Transition)
    (accepted : openRequest machine context operation operands = .ok after) :
    OperandSchemas.NonExecuting after.state.control ∨ after.state.status ≠ .running := by
  cases control : after.state.control <;> try exact Or.inl trivial
  right
  intro running
  simp only [openRequest, bind, except_bind_ok, fromOption_ok, pure, Except.pure,
    throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → invokeFunction_enters]

theorem executeEffectTerm_changes (machine : State) (context : Context) (after : Transition)
    (running : machine.status = .running) (accepted : executeEffectTerm machine context = .ok after) :
    after.state ≠ machine := by
  intro same
  unfold executeEffectTerm at accepted
  split at accepted <;> try contradiction
  rename_i term environment operands executing
  have executed : ¬ OperandSchemas.NonExecuting after.state.control := by simp [same, executing, OperandSchemas.NonExecuting]
  have remains : after.state.status = .running := by simp [same, running]
  simp only [bind, except_bind_ok, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, → openRequest_shape,
    → OperandSchemas.installHandler_nonexecuting, → OperandSchemas.resumeValue_nonexecuting,
    → OperandSchemas.resumeComputation_nonexecuting, → OperandSchemas.enterRegion_nonexecuting]

theorem temporary_stack (before after : State) (owner : Custody.Owner)
    (accepted : temporary before = .ok (after, owner)) : after.stack = before.stack := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  rfl

theorem finishTemporary_stack (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) : after.state.stack = machine.stack := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  cases accepted
  rfl

theorem leaveScope_stack (machine : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition)
    (accepted : leaveScope machine parent invocation tail value = .ok after) : after.state.stack = tail := by
  simp only [leaveScope, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, _, _, finished, finishedOk, rfl⟩ := accepted
  exact (finishTemporary_stack _ _ _ finishedOk).trans (temporary_stack _ _ _ temporaryOk)

theorem leaveInvocation_changes (machine : State) (after : Transition)
    (accepted : leaveInvocation machine = .ok after) : after.state ≠ machine := by
  unfold leaveInvocation at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i caller parent tail stacked
  have popped := leaveScope_stack _ _ _ _ _ _ accepted
  apply changed_stack
  simp [popped, stacked]

theorem leaveLexical_changes (machine : State) (after : Transition)
    (accepted : leaveLexical machine = .ok after) : after.state ≠ machine := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i scope tail stacked
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, result, left, accepted⟩ := accepted
  have popped := leaveScope_stack _ _ _ _ _ _ left
  split at accepted <;> try contradiction
  simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  apply changed_stack
  simp [popped, stacked]

theorem restoreResumeCaller_changes (machine : State) (after : Transition)
    (accepted : restoreResumeCaller machine = .ok after) : after.state ≠ machine := by
  unfold restoreResumeCaller at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i invocation scope tail stacked
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, _, _, finished⟩ := accepted
  have temporaryStack := temporary_stack _ _ _ temporaryOk
  have finalStack := finishTemporary_stack _ _ _ finished
  have popped := finalStack.trans temporaryStack
  apply changed_stack
  simp [popped, stacked]

theorem completeHandler_changes (machine : State) (context : Context) (after : Transition)
    (accepted : completeHandler machine context = .ok after) : after.state ≠ machine := by
  unfold completeHandler at accepted
  split at accepted <;> try contradiction
  rename_i value executing
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  apply changed_control
  simp [executing]

theorem beginCleanup_enters (machine : State) (context : Context) (identity : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (accepted : beginCleanup machine context identity exit normal tail = .ok after) :
    ∃ body environment, after.state.control = .term body environment := by
  simp only [beginCleanup, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, applied, rfl⟩ := accepted
  have entered := applyClosure_enters _ _ _ _ _ applied
  exact entered

theorem finishCleanup_changes (machine : State) (context : Context) (after : Transition)
    (accepted : finishCleanup machine context = .ok after) : after.state ≠ machine := by
  unfold finishCleanup at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i identity invocation exit normal tail stacked
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, released, _, rfl⟩ := accepted
  apply changed_stack
  cases released <;> simp [resumeRelease, stacked]

theorem finishDisposal_changes (machine : State) (after : Transition)
    (accepted : finishDisposal machine = .ok after) : after.state ≠ machine := by
  unfold finishDisposal at accepted
  split at accepted <;> try contradiction
  rename_i value executing
  split at accepted <;> try contradiction
  cases accepted
  apply changed_control
  simp [executing]

theorem finishCleanupUnwind_discards (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : finishCleanupUnwind machine identity invocation outer normal tail inner = .ok after) :
    ∃ values released, after.state.control = .discard values released := by
  cases primary : inner.primary <;>
    simp only [finishCleanupUnwind, primary, cleanupFailed, cleanupAbandoned, bind,
      except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  case normal => contradiction
  case failure =>
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    exact ⟨_, _, rfl⟩
  all_goals
    obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
    exact ⟨_, _, rfl⟩

theorem unwindStep_changes (machine : State) (context : Context) (after : Transition)
    (running : machine.status = .running) (accepted : unwindStep machine context = .ok after) :
    after.state ≠ machine := by
  unfold unwindStep at accepted
  split at accepted <;> try contradiction
  rename_i original executing
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨scope, _, accepted⟩ := accepted
  cases stacked : machine.stack with
  | nil =>
    simp only [stacked] at accepted
    split at accepted
    · cases accepted
      apply changed_control; simp [executing]
    · split at accepted <;> try contradiction
      all_goals cases accepted
      all_goals apply changed_status
      all_goals simp [running]
  | cons saved tail =>
    cases saved <;> simp only [stacked] at accepted
    case invocation =>
      split at accepted <;> cases accepted
      · apply changed_control; simp [executing]
      · apply changed_stack; simp [stacked]
    case lexical =>
      split at accepted
      · cases accepted
        apply changed_control; simp [executing]
      · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨_, _, _, _, rfl⟩ := accepted
        apply changed_stack; simp [stacked]
    case protection =>
      obtain ⟨body, bindings, entered⟩ := beginCleanup_enters _ _ _ _ _ _ _ accepted
      apply changed_control; simp [executing, entered]
    case cleanupReturn =>
      obtain ⟨values, released, discarded⟩ := finishCleanupUnwind_discards _ _ _ _ _ _ _ _ accepted
      apply changed_control; simp [executing, discarded]
    case disposalReturn =>
      simp only [Bool.false_and, Bool.false_eq_true, ↓reduceIte] at accepted
      repeat' split at accepted
      all_goals simp only [pure, Except.pure, Except.bind, Except.ok.injEq] at accepted
      all_goals cases accepted
      all_goals apply changed_stack
      all_goals simp [stacked]
    all_goals cases accepted
    all_goals apply changed_stack
    all_goals simp [stacked]

theorem tickRunning_changes (machine : State) (context : Context) (after : Transition)
    (running : machine.status = .running) (accepted : tickRunning machine context = .ok after) :
    after.state ≠ machine := by
  unfold tickRunning at accepted
  split at accepted
  · exact enterTerm_changes _ _ _ running accepted
  · exact enterExpression_changes _ _ _ accepted
  · exact enterInvocation_changes _ _ _ accepted
  · exact releaseScope_changes _ _ accepted
  · exact discardValues_changes _ _ _ accepted
  · exact unwindStep_changes _ _ _ running accepted
  · split at accepted
    · exact executePrimitive_changes _ _ _ accepted
    · split at accepted <;> first
      | exact executeEffectTerm_changes _ _ _ running accepted
      | exact executeCleanupTerm_changes _ _ _ accepted
      | exact executeControlTerm_changes _ _ _ accepted
  · rename_i value executing
    split at accepted
    · simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
      apply changed_status; simp [running]
    · exact enterBinding_changes _ _ _ accepted
    · exact deliverOperand_changes _ _ accepted
    · exact leaveInvocation_changes _ _ accepted
    · exact leaveLexical_changes _ _ accepted
    · exact restoreResumeCaller_changes _ _ accepted
    · exact completeHandler_changes _ _ _ accepted
    · rename_i region tail stacked
      cases accepted
      apply changed_stack; simp [stacked]
    · obtain ⟨body, bindings, entered⟩ := beginCleanup_enters _ _ _ _ _ _ _ accepted
      apply changed_control; simp [executing, entered]
    · exact finishCleanup_changes _ _ _ accepted
    · rename_i injection tail stacked
      cases accepted
      apply changed_stack; simp [stacked]
    · cases accepted
      apply changed_control; simp [executing]
    · exact finishDisposal_changes _ _ accepted

/-- Every successful internal step of a running source machine advances its
actual state. Inactive polling remains an explicit identity transition. -/
theorem running_tick_changes (machine : State) (context : Context) (after : Transition)
    (running : machine.status = .running) (accepted : tick machine context = .ok after) :
    after.state ≠ machine := by
  simp only [tick, running] at accepted
  exact tickRunning_changes _ _ _ running accepted

end InternalProgress
end BoundaryV2.Profile.Source.Machine
