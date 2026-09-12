import BoundaryV2.SourceOperandSchemas

namespace BoundaryV2.Profile.Source.Machine
namespace OperandSchemas

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem temporary_status (before after : State) (owner : Custody.Owner)
    (accepted : temporary before = .ok (after, owner)) : after.status = before.status := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  rfl

theorem finishTemporary_status (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) : after.state.status = machine.status := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  cases accepted
  rfl

theorem scopedValue_status (machine : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue machine value = .ok after) : after.state.status = machine.status := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, finished⟩ := accepted
  have middleStatus := temporary_status _ _ _ temporaryOk
  have finalStatus := finishTemporary_status _ _ _ finished
  exact finalStatus.trans middleStatus

theorem commitPure_status (machine : State) (opcode : Opcode) (operands : List Located)
    (value : SemanticValue) (after : Transition) (accepted : commitPure machine opcode operands value = .ok after) :
    after.state.status = machine.status := by
  simp only [commitPure, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, accepted⟩ := accepted
  have middleStatus := temporary_status _ _ _ temporaryOk
  split at accepted <;> simp only [except_bind_ok] at accepted
  · obtain ⟨_, _, _, _, finished⟩ := accepted
    exact (finishTemporary_status _ _ _ finished).trans middleStatus
  · obtain ⟨_, _, _, _, _, _, finished⟩ := accepted
    exact (finishTemporary_status _ _ _ finished).trans middleStatus

theorem makeClosureWithValues_status (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues machine context schema function values = .ok after) : after.state.status = machine.status := by
  simp only [makeClosureWithValues, bind, except_bind_ok] at accepted
  obtain ⟨_, _, ⟨middle, owner⟩, temporaryOk, _, _, ⟨_, _⟩, _, finished⟩ := accepted
  have middleStatus := temporary_status _ _ _ temporaryOk
  have finalStatus := finishTemporary_status _ _ _ finished
  exact finalStatus.trans middleStatus

theorem makeClosure_status (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (bindings : Environment) (after : Transition)
    (accepted : makeClosure machine context schema function bindings = .ok after) : after.state.status = machine.status := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  exact makeClosureWithValues_status _ _ _ _ _ _ accepted

theorem enterExpression_status (machine : State) (context : Context) (after : Transition)
    (accepted : enterExpression machine context = .ok after) : after.state.status = machine.status := by
  unfold enterExpression at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨⟨_, expression⟩, _, accepted⟩ := accepted
  cases expression with
  | «variable» =>
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
    rfl
  | literal =>
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, _, _, accepted⟩ := accepted
    exact scopedValue_status _ _ _ accepted
  | lambda => exact makeClosure_status _ _ _ _ _ _ accepted
  | primitive opcode operands => cases operands <;> cases accepted <;> rfl

set_option maxRecDepth 4096 in
set_option maxHeartbeats 1600000 in
theorem heapPrimitive_status (machine : State) (context : Context)
    (operation : Primitives.GraphOperation) (schema : SchemaId .source) (immediate : Nat)
    (operands : List Located) (after : Transition)
    (accepted : heapPrimitive machine context operation schema immediate operands = .ok after) :
    after.state.status = machine.status := by
  cases operation <;> simp only [heapPrimitive, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  all_goals try split at accepted
  all_goals grind (gen := 32) only [except_bind_ok, fromOption_ok,
    → temporary_status, → finishTemporary_status, → scopedValue_status,
    → commitPure_status, → makeClosureWithValues_status]

theorem executePrimitive_status (machine : State) (context : Context) (after : Transition)
    (accepted : executePrimitive machine context = .ok after) : after.state.status = machine.status := by
  unfold executePrimitive at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · contradiction
  · simp only [authoredFailure, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
    rfl
  · exact commitPure_status _ _ _ _ _ accepted
  · exact heapPrimitive_status _ _ _ _ _ _ _ accepted

theorem deliverOperand_status (machine : State) (after : Transition)
    (accepted : deliverOperand machine = .ok after) : after.state.status = machine.status := by
  unfold deliverOperand at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  split at accepted <;> cases accepted <;> rfl


def NonExecuting : Control → Prop
  | .execute .. => False
  | _ => True

theorem plain_types (source : Module) (machine : State) (plain : OperandStructure.Plain machine)
    (control : NonExecuting machine.control) : LocalTypes source machine := by
  cases executing : machine.control with
  | execute intent bindings values =>
    cases intent <;> simp only [NonExecuting, executing] at control ⊢
  | expression | delivered =>
    simpa only [LocalTypes, executing] using (Spine.plain (source := source) (input := _) plain.1)
  | term | invoke | release | discard | unwind => simp only [LocalTypes, executing]

theorem plain_typed (source : Module) (machine : State) (plain : OperandStructure.Plain machine)
    (control : NonExecuting machine.control) : Typed source machine :=
  ⟨plain.valid, plain_types _ _ plain control, fun _ _ => plain.1⟩

theorem running_typed (source : Module) (machine : State) (structural : OperandStructure.Valid machine)
    (localTypes : LocalTypes source machine) (running : machine.status = .running) : Typed source machine :=
  ⟨structural, localTypes, by intro request parked; rw [running] at parked; cases parked⟩

theorem invokeFunction_nonexecuting (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction machine context function bindings arguments = .ok after) : NonExecuting after.state.control := by
  obtain ⟨body, entered, control, _⟩ := invokeFunction_enters_typed_environment _ _ _ _ _ _ accepted
  simp only [NonExecuting, control]

theorem applyClosure_nonexecuting (machine : State) (context : Context) (closure : Located)
    (arguments : List Located) (after : Transition)
    (accepted : applyClosure machine context closure arguments = .ok after) : NonExecuting after.state.control := by
  simp only [applyClosure, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact invokeFunction_nonexecuting _ _ _ _ _ _ accepted
  · simp only [pure, Except.pure, Except.bind] at accepted
    exact invokeFunction_nonexecuting _ _ _ _ _ _ accepted

theorem enterInvocation_nonexecuting (machine : State) (context : Context) (after : Transition)
    (accepted : enterInvocation machine context = .ok after) : NonExecuting after.state.control := by
  unfold enterInvocation at accepted
  split at accepted <;> try contradiction
  exact invokeFunction_nonexecuting _ _ _ _ _ _ accepted

theorem enterBinding_nonexecuting (machine : State) (context : Context) (after : Transition)
    (accepted : enterBinding machine context = .ok after) : NonExecuting after.state.control := by
  unfold enterBinding at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  trivial

theorem enterPattern_nonexecuting (machine : State) (context : Context) (vars : List VariableId)
    (parts : List SemanticValue) (owner : Custody.Owner) (body : TermId) (bindings : Environment) (after : Transition)
    (accepted : enterPattern machine context vars parts owner body bindings = .ok after) : NonExecuting after.state.control := by
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  trivial

theorem executeControlTerm_nonexecuting (machine : State) (context : Context) (after : Transition)
    (accepted : executeControlTerm machine context = .ok after) : NonExecuting after.state.control := by
  unfold executeControlTerm at accepted
  split at accepted <;> try contradiction
  rename_i authored bindings values executing
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  cases authored <;> simp only at accepted <;> try contradiction
  case conditional =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    trivial
  case call => cases accepted; trivial
  case apply =>
    split at accepted <;> try contradiction
    exact applyClosure_nonexecuting _ _ _ _ _ accepted
  case fail =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, rfl⟩ := accepted
    trivial
  case matchSum =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact enterPattern_nonexecuting _ _ _ _ _ _ _ _ accepted
  case unpackProduct =>
    split at accepted <;> try contradiction
    exact enterPattern_nonexecuting _ _ _ _ _ _ _ _ accepted

theorem completeHandler_nonexecuting (machine : State) (context : Context) (after : Transition)
    (accepted : completeHandler machine context = .ok after) : NonExecuting after.state.control := by
  unfold completeHandler at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  trivial

theorem installHandler_nonexecuting (machine : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (bindings : Environment) (after : Transition)
    (accepted : installHandler machine context handler body arguments stored bindings = .ok after) : NonExecuting after.state.control := by
  simp only [installHandler, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, applied⟩ := accepted
  exact applyClosure_nonexecuting _ _ _ _ _ applied

theorem enterRegion_nonexecuting (machine : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition)
    (accepted : enterRegion machine context descriptor body arguments = .ok after) : NonExecuting after.state.control := by
  simp only [enterRegion, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, applied⟩ := accepted
  exact applyClosure_nonexecuting _ _ _ _ _ applied

theorem resumeValue_nonexecuting (machine : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (accepted : resumeValue machine context token argument successor = .ok after) : NonExecuting after.state.control := by
  simp only [resumeValue, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, finished⟩ := accepted
  simp only [NonExecuting, finishTemporary_delivers _ _ _ finished]

theorem resumeComputation_nonexecuting (machine : State) (context : Context) (token computation : Located) (after : Transition)
    (accepted : resumeComputation machine context token computation = .ok after) : NonExecuting after.state.control := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, applied⟩ := accepted
  exact applyClosure_nonexecuting _ _ _ _ _ applied

theorem openRequest_types (machine : State) (context : Context) (operation : Operation) (operands : List Located)
    (after : Transition) (accepted : openRequest machine context operation operands = .ok after)
    (typed : LocalTypes context.source machine) (plain : OperandStructure.Plain machine) : LocalTypes context.source after.state := by
  have plainAfter := OperandStructure.openRequest_plain _ _ _ _ _ accepted plain
  simp only [openRequest, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, accepted⟩ := accepted
  split at accepted
  · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    exact typed
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, accepted⟩ := accepted
    split at accepted
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, _, _, invoked⟩ := accepted
      exact plain_types _ _ (OperandStructure.invokeFunction_plain _ _ _ _ _ _ invoked plain)
        (invokeFunction_nonexecuting _ _ _ _ _ _ invoked)
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
      split at accepted
      all_goals
        simp only [except_bind_ok] at accepted
        try
          obtain ⟨gate, guard, rest⟩ := accepted
          have _ : Unit := gate
          clear guard
          have accepted := rest
        obtain ⟨_, _, _, _, _, _, invoked⟩ := accepted
        exact plain_types _ _ plainAfter (invokeFunction_nonexecuting _ _ _ _ _ _ invoked)

theorem executeEffectTerm_types (machine : State) (context : Context) (after : Transition)
    (accepted : executeEffectTerm machine context = .ok after) (typed : LocalTypes context.source machine)
    (plain : OperandStructure.Plain machine) : LocalTypes context.source after.state := by
  unfold executeEffectTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · exact openRequest_types _ _ _ _ _ accepted typed plain
  all_goals split at accepted <;> try contradiction
  all_goals first
    | exact plain_types _ _ (OperandStructure.installHandler_plain _ _ _ _ _ _ _ _ accepted plain) (installHandler_nonexecuting _ _ _ _ _ _ _ _ accepted)
    | exact plain_types _ _ (OperandStructure.resumeValue_plain _ _ _ _ _ _ accepted plain) (resumeValue_nonexecuting _ _ _ _ _ _ accepted)
    | exact plain_types _ _ (OperandStructure.resumeComputation_plain _ _ _ _ _ accepted plain) (resumeComputation_nonexecuting _ _ _ _ _ accepted)
    | exact plain_types _ _ (OperandStructure.enterRegion_plain _ _ _ _ _ _ accepted plain) (enterRegion_nonexecuting _ _ _ _ _ _ accepted)

theorem startTerm_types (source : Module) (machine : State) (authored : Term) (bindings : Environment)
    (references : List SourceValueId) (expected : Schemas) (after : Transition)
    (accepted : (match references with
      | [] => .ok ⟨{ machine with control := .execute (.term authored) bindings [] }, []⟩
      | first :: rest => .ok ⟨{ machine with
          control := .expression first bindings
          stack := .operands (.term authored) bindings rest [] :: machine.stack }, []⟩) = (Except.ok after : Except Invalid Transition))
    (typed : Admission.valueTypes source references = some expected)
    (signature : Signature source (.term authored) expected) (plain : OperandStructure.NoOperands machine.stack)
    : LocalTypes source after.state := by
  cases references with
  | nil =>
    cases accepted
    have empty : expected = [] := Option.some.inj typed.symm
    subst expected
    exact ⟨signature, plain⟩
  | cons first rest =>
    obtain ⟨schema, remainingTypes, firstAt, restAt, rfl⟩ := valueTypes_cons source first rest expected typed
    cases accepted
    simp only [LocalTypes, firstAt]
    exact .term signature restAt plain

theorem enterTerm_types (machine : State) (context : Context) (after : Transition)
    (accepted : enterTerm machine context.source = .ok after) (contextTyped : context.typingValid = true)
    (plain : OperandStructure.Plain machine) : LocalTypes context.source after.state := by
  unfold enterTerm at accepted
  split at accepted <;> try contradiction
  rename_i reference bindings executing
  split at accepted <;> try contradiction
  rename_i authored found
  obtain ⟨types, typesAt⟩ := checked_term_operand_types context reference.value authored contextTyped found
  have signature : Signature context.source (.term authored) types := .term (List.mem_of_getElem? found) typesAt
  cases authored <;> simp only at accepted
  case value => cases accepted; exact .plain plain.1
  case bind => cases accepted; trivial
  case yieldThen => cases accepted; trivial
  all_goals exact startTerm_types _ machine _ bindings _ _ _ accepted typesAt signature plain.1

theorem enterTerm_parked (machine : State) (source : Module) (after : Transition)
    (accepted : enterTerm machine source = .ok after) (running : machine.status = .running) : ParkedPlain after.state := by
  intro request parked
  unfold enterTerm at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  repeat' split at accepted
  all_goals cases accepted
  all_goals simp only [running] at parked
  all_goals cases parked

theorem resumeRelease_nonexecuting (machine : State) (after : AfterRelease) : NonExecuting (resumeRelease machine after).state.control := by
  cases after <;> trivial

theorem leaveScope_nonexecuting (machine : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition)
    (accepted : leaveScope machine parent invocation tail value = .ok after) : NonExecuting after.state.control := by
  simp only [leaveScope, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  trivial

theorem leaveInvocation_nonexecuting (machine : State) (after : Transition)
    (accepted : leaveInvocation machine = .ok after) : NonExecuting after.state.control := by
  unfold leaveInvocation at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  exact leaveScope_nonexecuting _ _ _ _ _ _ accepted

theorem leaveLexical_nonexecuting (machine : State) (after : Transition)
    (accepted : leaveLexical machine = .ok after) : NonExecuting after.state.control := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  trivial

theorem restoreResumeCaller_nonexecuting (machine : State) (after : Transition)
    (accepted : restoreResumeCaller machine = .ok after) : NonExecuting after.state.control := by
  unfold restoreResumeCaller at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, finished⟩ := accepted
  simp only [NonExecuting, finishTemporary_delivers _ _ _ finished]

theorem installProtection_nonexecuting (machine : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (accepted : installProtection machine context body cleanup arguments resource loan = .ok after) : NonExecuting after.state.control := by
  simp only [installProtection, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, accepted⟩ := accepted
  cases resource <;> cases loan <;> try contradiction
  · simp only [pure, Except.pure, Except.bind] at accepted
    exact applyClosure_nonexecuting _ _ _ _ _ accepted
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, _, rfl, applied⟩ := accepted
    exact applyClosure_nonexecuting _ _ _ _ _ applied

theorem beginCleanup_nonexecuting (machine : State) (context : Context) (identity : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (accepted : beginCleanup machine context identity exit normal tail = .ok after) : NonExecuting after.state.control := by
  simp only [beginCleanup, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, applied, rfl⟩ := accepted
  have result := applyClosure_nonexecuting _ _ _ _ _ applied
  exact result

theorem finishCleanup_nonexecuting (machine : State) (context : Context) (after : Transition)
    (accepted : finishCleanup machine context = .ok after) : NonExecuting after.state.control := by
  unfold finishCleanup at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, rfl⟩ := accepted
  exact resumeRelease_nonexecuting _ _

theorem cleanupFailed_nonexecuting (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : cleanupFailed machine identity invocation outer normal tail inner = .ok after) :
    NonExecuting after.state.control := by
  unfold cleanupFailed at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  trivial

theorem cleanupAbandoned_nonexecuting (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : cleanupAbandoned machine identity invocation outer normal tail inner = .ok after) :
    NonExecuting after.state.control := by
  simp only [cleanupAbandoned, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  trivial

theorem finishCleanupUnwind_nonexecuting (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : finishCleanupUnwind machine identity invocation outer normal tail inner = .ok after) :
    NonExecuting after.state.control := by
  unfold finishCleanupUnwind at accepted
  split at accepted <;> first
    | exact cleanupFailed_nonexecuting _ _ _ _ _ _ _ _ accepted
    | exact cleanupAbandoned_nonexecuting _ _ _ _ _ _ _ _ accepted
    | contradiction

theorem finishDisposal_nonexecuting (machine : State) (after : Transition)
    (accepted : finishDisposal machine = .ok after) : NonExecuting after.state.control := by
  unfold finishDisposal at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  trivial

theorem releaseScope_nonexecuting (machine : State) (after : Transition)
    (accepted : releaseScope machine = .ok after) : NonExecuting after.state.control := by
  unfold releaseScope at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  trivial

theorem executeCleanupTerm_nonexecuting (machine : State) (context : Context) (after : Transition)
    (accepted : executeCleanupTerm machine context = .ok after) : NonExecuting after.state.control := by
  unfold executeCleanupTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact installProtection_nonexecuting _ _ _ _ _ _ _ _ accepted
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
    trivial

theorem discardValues_nonexecuting (machine : State) (context : Context) (after : Transition)
    (accepted : discardValues machine context = .ok after) : NonExecuting after.state.control := by
  unfold discardValues at accepted
  split at accepted <;> try contradiction
  split at accepted
  · cases accepted; exact resumeRelease_nonexecuting _ _
  · split at accepted
    · cases accepted; trivial
    · simp only [bind, except_bind_ok] at accepted
      obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
      cases stored <;> try contradiction
      all_goals simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      all_goals obtain ⟨_, _, rfl⟩ := accepted
      all_goals trivial

end OperandSchemas
end BoundaryV2.Profile.Source.Machine
