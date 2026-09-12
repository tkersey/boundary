import BoundaryV2.SourceOperandEffects

namespace BoundaryV2.Profile.Source.Machine
namespace OperandStructure

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem enterTerm_valid (machine : State) (source : Module) (after : Transition)
    (accepted : enterTerm machine source = .ok after) (typed : Plain machine) : Valid after.state := by
  unfold enterTerm at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  repeat' split at accepted
  all_goals cases accepted
  all_goals refine ⟨?_, typed.2⟩
  all_goals first
    | exact typed.1
    | exact Layout.plain typed.1
    | exact Layout.term typed.1
    | exact (noOperands_cons _ _).mpr ⟨by simp, typed.1⟩

theorem enterExpression_valid (machine : State) (context : Context) (after : Transition)
    (accepted : enterExpression machine context = .ok after) (typed : Valid machine) : Valid after.state := by
  unfold enterExpression at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨schema, expression⟩, _, accepted⟩ := accepted
  cases expression with
  | «variable» binder =>
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨value, _, _, _, _, _, rfl⟩ := accepted
    exact ⟨typed.layout, typed.2⟩
  | literal constant =>
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨value, _, _, _, accepted⟩ := accepted
    exact delivered_valid _ _ typed.layout (scopedValue_valid _ _ _ accepted typed.2)
  | lambda function =>
    exact delivered_valid _ _ typed.layout (makeClosure_shape _ _ _ _ _ _ accepted typed.2)
  | primitive opcode operands immediate failures =>
    cases operands with
    | nil => cases accepted; exact ⟨typed.layout, typed.2⟩
    | cons => cases accepted; exact ⟨Layout.primitive typed.layout, typed.2⟩

theorem deliverOperand_valid (machine : State) (after : Transition)
    (accepted : deliverOperand machine = .ok after) (typed : Valid machine) : Valid after.state := by
  unfold deliverOperand at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i intent bindings remaining evaluated tail stacked
  have layout : Layout (.operands intent bindings remaining evaluated :: tail) := by
    simpa only [stacked] using typed.layout
  split at accepted
  · cases accepted
    refine ⟨?_, typed.2⟩
    cases intent
    · exact layout.term_tail
    · exact layout.primitive_tail
  · cases accepted
    exact ⟨layout.replace_operands _ _ _, typed.2⟩

theorem executePrimitive_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executePrimitive machine context = .ok after) (typed : Valid machine) : Valid after.state := by
  unfold executePrimitive at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · contradiction
  · have shape := authoredFailure_shape _ _ _ _ _ accepted
    obtain ⟨exit, unwinding⟩ := shape.1
    exact ⟨by simpa only [Fits, unwinding, shape.2.1] using typed.layout, typed.2.of_objects shape.2.2⟩
  · exact delivered_valid _ _ typed.layout (commitPure_valid _ _ _ _ _ accepted typed.2)
  · exact delivered_valid _ _ typed.layout (heapPrimitive_shape _ _ _ _ _ _ _ accepted typed.2)

theorem enterInvocation_plain (machine : State) (context : Context) (after : Transition)
    (accepted : enterInvocation machine context = .ok after) (typed : Plain machine) : Plain after.state := by
  unfold enterInvocation at accepted
  split at accepted <;> try contradiction
  exact invokeFunction_plain _ _ _ _ _ _ accepted typed

theorem enterBinding_plain (machine : State) (context : Context) (after : Transition)
    (accepted : enterBinding machine context = .ok after) (typed : Plain machine) : Plain after.state := by
  unfold enterBinding at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i binder body bindings parent tail stacked
  have tailTyped : NoOperands tail := (noOperands_cons _ _).mp (by simpa only [stacked] using typed.1) |>.2
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have shape := createScope_shape _ _ _ _ _ _ _ _ _ scopeOk
  refine ⟨?_, typed.2.of_objects shape.2.2⟩
  split
  · exact tailTyped
  · exact (noOperands_cons _ _).mpr ⟨by simp, tailTyped⟩

theorem enterPattern_plain (machine : State) (context : Context) (vars : List VariableId)
    (parts : List SemanticValue) (owner : Custody.Owner) (body : TermId) (bindings : Environment) (after : Transition)
    (accepted : enterPattern machine context vars parts owner body bindings = .ok after)
    (typed : Plain machine) : Plain after.state := by
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have shape := createScope_shape _ _ _ _ _ _ _ _ _ scopeOk
  refine ⟨?_, typed.2.of_objects shape.2.2⟩
  split
  · exact typed.1
  · exact (noOperands_cons _ _).mpr ⟨by simp, typed.1⟩

theorem executeControlTerm_plain (machine : State) (context : Context) (after : Transition)
    (accepted : executeControlTerm machine context = .ok after) (typed : Plain machine) : Plain after.state := by
  unfold executeControlTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  cases term <;> simp only at accepted <;> try contradiction
  case conditional =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    exact typed
  case call => cases accepted; exact typed
  case apply =>
    split at accepted <;> try contradiction
    exact applyClosure_plain _ _ _ _ _ accepted typed
  case fail =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, rfl⟩ := accepted
    exact typed
  case matchSum =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact enterPattern_plain _ _ _ _ _ _ _ _ accepted typed
  case unpackProduct =>
    split at accepted <;> try contradiction
    exact enterPattern_plain _ _ _ _ _ _ _ _ accepted typed


theorem leaveScope_plain (machine : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition)
    (accepted : leaveScope machine parent invocation tail value = .ok after)
    (typed : HeapValid machine.heap) (tailTyped : NoOperands tail) : Plain after.state := by
  simp only [leaveScope, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, store, moved, finished, finishOk, rfl⟩ := accepted
  have middleTyped := temporary_plain _ _ _ temporaryOk (show Plain
    { machine with scope := parent, invocation := invocation, stack := tail } from ⟨tailTyped, typed⟩)
  have movedTyped : Plain { middle with heap := store } := ⟨middleTyped.1, moveValues_valid _ _ _ _ moved middleTyped.2⟩
  have finishedTyped := finishTemporary_plain _ _ _ finishOk movedTyped
  exact finishedTyped

theorem leaveInvocation_plain (machine : State) (after : Transition)
    (accepted : leaveInvocation machine = .ok after) (typed : Plain machine) : Plain after.state := by
  unfold leaveInvocation at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i invocation parent tail stacked
  exact leaveScope_plain _ _ _ _ _ _ accepted typed.2
    ((noOperands_cons _ _).mp (by simpa only [stacked] using typed.1)).2

theorem leaveLexical_plain (machine : State) (after : Transition)
    (accepted : leaveLexical machine = .ok after) (typed : Plain machine) : Plain after.state := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i scope tail stacked
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, record, _, parent, _, result, leaving, accepted⟩ := accepted
  have leavingTyped := leaveScope_plain _ _ _ _ _ _ leaving typed.2
    ((noOperands_cons _ _).mp (by simpa only [stacked] using typed.1)).2
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, store, moved, rfl⟩ := accepted
  have movedTyped := moveValues_valid _ _ _ _ moved leavingTyped.2
  exact ⟨leavingTyped.1, movedTyped⟩

theorem restoreResumeCaller_plain (machine : State) (after : Transition)
    (accepted : restoreResumeCaller machine = .ok after) (typed : Plain machine) : Plain after.state := by
  unfold restoreResumeCaller at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i invocation scope tail stacked
  have tailTyped := ((noOperands_cons _ _).mp (by simpa only [stacked] using typed.1)).2
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, store, moved, finished⟩ := accepted
  have middleTyped := temporary_plain _ _ _ temporaryOk (show Plain
    { machine with scope := scope, invocation := invocation, stack := tail } from ⟨tailTyped, typed.2⟩)
  have movedTyped : Plain { middle with heap := store } := ⟨middleTyped.1, moveValues_valid _ _ _ _ moved middleTyped.2⟩
  exact finishTemporary_plain _ _ _ finished movedTyped

theorem completeHandler_plain (machine : State) (context : Context) (after : Transition)
    (accepted : completeHandler machine context = .ok after) (typed : Plain machine) : Plain after.state := by
  unfold completeHandler at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i active tail stacked
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact ⟨((noOperands_cons _ _).mp (by simpa only [stacked] using typed.1)).2, typed.2⟩

theorem unwindStep_valid (machine : State) (context : Context) (after : Transition)
    (accepted : unwindStep machine context = .ok after) (typed : Valid machine) : Valid after.state := by
  unfold unwindStep at accepted
  split at accepted <;> try contradiction
  rename_i original unwinding
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  cases stacked : machine.stack with
  | nil =>
    have plain : Plain machine := ⟨by simp [NoOperands, stacked], typed.2⟩
    simp only [stacked] at accepted
    split at accepted
    · cases accepted
      apply Plain.valid
      simpa only [Plain, stacked] using plain
    · split at accepted <;> try contradiction
      all_goals cases accepted
      all_goals apply Plain.valid
      all_goals simpa only [Plain, stacked] using plain
  | cons saved tail =>
    have layout : Layout (saved :: tail) := by simpa only [stacked] using typed.layout
    cases saved <;> simp only [stacked] at accepted
    case operands =>
      cases accepted
      exact ⟨by simpa only [Fits, unwinding] using layout.tail, typed.2⟩
    all_goals
      have plain := typed.nonoperand stacked (by simp)
      have tailTyped := ((noOperands_cons _ _).mp (by simpa only [stacked] using plain.1)).2
      have tailPlain : Plain { machine with stack := tail } := ⟨tailTyped, typed.2⟩
    case invocation =>
      split at accepted
      · cases accepted; apply Plain.valid; simpa only [Plain, stacked] using plain
      · cases accepted; apply Plain.valid; exact tailPlain
    case lexical =>
      split at accepted
      · cases accepted; apply Plain.valid; simpa only [Plain, stacked] using plain
      · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨_, _, _, _, rfl⟩ := accepted
        apply Plain.valid; exact tailPlain
    case protection => exact (beginCleanup_plain _ _ _ _ _ _ _ accepted typed.2 tailTyped).valid
    case cleanupReturn => exact (finishCleanupUnwind_plain _ _ _ _ _ _ _ _ accepted typed.2 tailTyped).valid
    case releaseReturn => cases accepted; apply Plain.valid; exact tailPlain
    case disposalReturn =>
      repeat' split at accepted
      all_goals simp only [pure, Except.pure, Except.bind, Except.ok.injEq] at accepted
      all_goals cases accepted
      all_goals apply Plain.valid
      all_goals first | exact tailPlain | simpa only [Plain, stacked] using plain
    all_goals cases accepted; apply Plain.valid; exact tailPlain

theorem cancel_fits (before : Control) (reason : Protocol.Reason) (frames : List Frame) (typed : Fits before frames) :
    Fits (cancelControl before reason) frames := by
  cases before <;> simp only [cancelControl]
  all_goals repeat' split
  all_goals first | exact typed | exact typed.layout

theorem external_valid (machine : State) (context : Context) (action : External) (after : Transition)
    (accepted : external machine context action = .ok after) (typed : Valid machine) : Valid after.state := by
  have running : Valid { machine with status := .running } := typed
  have cancelled (reason : Protocol.Reason) : Valid
      { machine with status := .running, control := cancelControl machine.control reason, cancellation := some reason } :=
    ⟨cancel_fits _ _ _ typed.1, typed.2⟩
  have cancellationOnly (reason : Protocol.Reason) : Valid { machine with cancellation := some reason } := typed
  have scopedResult (value : SemanticValue) (transition : Transition)
      (checked : scopedValue { machine with status := .running } value = .ok transition) : Valid transition.state :=
    delivered_valid _ _ running.layout (scopedValue_valid _ _ _ checked running.2)
  cases phase : machine.status <;> cases action <;>
    simp only [external, phase, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw,
      Except.bind] at accepted <;> try contradiction
  all_goals grind (gen := 32) only []

theorem tickRunning_valid (machine : State) (context : Context) (after : Transition)
    (accepted : tickRunning machine context = .ok after) (typed : Valid machine) : Valid after.state := by
  cases executing : machine.control <;> simp only [tickRunning, executing] at accepted
  case expression => exact enterExpression_valid _ _ _ accepted typed
  case unwind => exact unwindStep_valid _ _ _ accepted typed
  case execute intent bindings operands =>
    cases intent with
    | primitive => exact executePrimitive_valid _ _ _ accepted typed
    | term term =>
      have plain : Plain machine := ⟨by simpa only [Fits, executing] using typed.1, typed.2⟩
      cases term <;> first
        | exact (executeEffectTerm_plain _ _ _ accepted plain).valid
        | exact (executeCleanupTerm_plain _ _ _ accepted plain).valid
        | exact (executeControlTerm_plain _ _ _ accepted plain).valid
  case delivered value =>
    cases stacked : machine.stack with
    | nil =>
      simp only [stacked, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
      exact ⟨.plain noOperands_nil, typed.2⟩
    | cons saved tail =>
      cases saved <;> simp only [stacked] at accepted
      case operands => exact deliverOperand_valid _ _ accepted typed
      all_goals
        have plain := typed.nonoperand stacked (by simp)
        have tailTyped := ((noOperands_cons _ _).mp (by simpa only [stacked] using plain.1)).2
        have tailPlain : Plain { machine with stack := tail } := ⟨tailTyped, typed.2⟩
      all_goals first
        | exact (enterBinding_plain _ _ _ accepted plain).valid
        | exact (leaveInvocation_plain _ _ accepted plain).valid
        | exact (leaveLexical_plain _ _ accepted plain).valid
        | exact (restoreResumeCaller_plain _ _ accepted plain).valid
        | exact (completeHandler_plain _ _ _ accepted plain).valid
        | exact (beginCleanup_plain _ _ _ _ _ _ _ accepted typed.2 tailTyped).valid
        | exact (finishCleanup_plain _ _ _ accepted plain).valid
        | exact (finishDisposal_plain _ _ accepted plain).valid
        | (cases accepted; apply Plain.valid; exact tailPlain)
        | contradiction
  all_goals
    have plain : Plain machine := ⟨by simpa only [Fits, executing] using typed.1, typed.2⟩
  all_goals first
    | exact enterTerm_valid _ _ _ accepted plain
    | exact (enterInvocation_plain _ _ _ accepted plain).valid
    | exact (releaseScope_plain _ _ accepted plain).valid
    | exact (discardValues_plain _ _ _ accepted plain).valid

theorem tick_valid (machine : State) (context : Context) (after : Transition)
    (accepted : tick machine context = .ok after) (typed : Valid machine) : Valid after.state := by
  cases phase : machine.status <;> simp only [tick, phase] at accepted
  · exact tickRunning_valid _ _ _ accepted typed
  all_goals cases accepted; exact typed

theorem step_valid (context : Context) (before after : State) (events : List Event)
    (step : Step context before events after) (typed : Valid before) : Valid after := by
  cases step with
  | internal accepted => exact tick_valid _ _ _ accepted typed
  | external accepted => exact external_valid _ _ _ _ accepted typed

theorem steps_valid (context : Context) (before after : State) (events : List Event)
    (steps : Steps context before events after) (typed : Valid before) : Valid after := by
  induction steps with
  | refl => exact typed
  | cons step _ induction => exact induction (step_valid _ _ _ _ step typed)

theorem initial_valid (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) : Valid machine := by
  simp only [initial, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ := accepted
  apply Plain.valid
  simp [Plain, NoOperands, HeapValid]

theorem initialized_execution_preserves_operand_structure (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : Valid after :=
  steps_valid _ _ _ _ steps (initial_valid _ _ _ initialized)

end OperandStructure
end BoundaryV2.Profile.Source.Machine
