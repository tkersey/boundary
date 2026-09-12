import BoundaryV2.SourceCustodyCleanup

namespace BoundaryV2.Profile.Source.Machine
namespace CustodyCoverage

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

/-- A response replaces only the suspended request's ordinary control. -/
def ParkedEmpty (machine : State) : Prop :=
  ∀ request, machine.status = .parked request → QueueCustody.controlFields machine.control = []

theorem invokeFunction_empty (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction machine context function bindings arguments = .ok after) :
    QueueCustody.controlFields after.state.control = [] := by
  obtain ⟨body, entered, control, _⟩ := invokeFunction_enters_typed_environment _ _ _ _ _ _ accepted
  rw [control]
  rfl

theorem applyClosure_empty (machine : State) (context : Context) (closure : Located)
    (arguments : List Located) (after : Transition)
    (accepted : applyClosure machine context closure arguments = .ok after) :
    QueueCustody.controlFields after.state.control = [] := by
  simp only [applyClosure, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  · obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
    exact invokeFunction_empty _ _ _ _ _ _ accepted
  · simp only [pure, Except.pure, Except.bind] at accepted
    exact invokeFunction_empty _ _ _ _ _ _ accepted

theorem finishTemporary_empty (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) : QueueCustody.controlFields after.state.control = [] := by
  rw [finishTemporary_control _ _ _ accepted]
  rfl

theorem enterInvocation_empty (machine : State) (context : Context) (after : Transition)
    (accepted : enterInvocation machine context = .ok after) : QueueCustody.controlFields after.state.control = [] := by
  unfold enterInvocation at accepted
  split at accepted <;> try contradiction
  exact invokeFunction_empty _ _ _ _ _ _ accepted

theorem enterBinding_empty (machine : State) (context : Context) (after : Transition)
    (accepted : enterBinding machine context = .ok after) : QueueCustody.controlFields after.state.control = [] := by
  unfold enterBinding at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  rfl

theorem enterPattern_empty (machine : State) (context : Context) (vars : List VariableId)
    (parts : List SemanticValue) (owner : Custody.Owner) (body : TermId) (bindings : Environment) (after : Transition)
    (accepted : enterPattern machine context vars parts owner body bindings = .ok after) :
    QueueCustody.controlFields after.state.control = [] := by
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  rfl

theorem executeControlTerm_empty (machine : State) (context : Context) (after : Transition)
    (accepted : executeControlTerm machine context = .ok after) : QueueCustody.controlFields after.state.control = [] := by
  unfold executeControlTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    rfl
  · cases accepted; rfl
  · split at accepted <;> try contradiction
    exact applyClosure_empty _ _ _ _ _ accepted
  · split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, rfl⟩ := accepted
    rfl
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact enterPattern_empty _ _ _ _ _ _ _ _ accepted
  · split at accepted <;> try contradiction
    exact enterPattern_empty _ _ _ _ _ _ _ _ accepted

theorem installHandler_empty (machine : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (bindings : Environment) (after : Transition)
    (accepted : installHandler machine context handler body arguments stored bindings = .ok after) :
    QueueCustody.controlFields after.state.control = [] := by
  simp only [installHandler, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, applied⟩ := accepted
  exact applyClosure_empty _ _ _ _ _ applied

theorem resumeValue_empty (machine : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (accepted : resumeValue machine context token argument successor = .ok after) :
    QueueCustody.controlFields after.state.control = [] := by
  simp only [resumeValue, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, finished⟩ := accepted
  exact finishTemporary_empty _ _ _ finished

theorem resumeComputation_empty (machine : State) (context : Context) (token computation : Located) (after : Transition)
    (accepted : resumeComputation machine context token computation = .ok after) :
    QueueCustody.controlFields after.state.control = [] := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, applied⟩ := accepted
  exact applyClosure_empty _ _ _ _ _ applied

theorem enterRegion_empty (machine : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition)
    (accepted : enterRegion machine context descriptor body arguments = .ok after) :
    QueueCustody.controlFields after.state.control = [] := by
  simp only [enterRegion, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, applied⟩ := accepted
  exact applyClosure_empty _ _ _ _ _ applied

theorem openRequest_empty (machine : State) (context : Context) (operation : Operation)
    (operands : List Located) (after : Transition)
    (accepted : openRequest machine context operation operands = .ok after)
    (empty : QueueCustody.controlFields machine.control = []) : QueueCustody.controlFields after.state.control = [] := by
  simp only [openRequest, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, accepted⟩ := accepted
  split at accepted
  · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    exact empty
  · simp only [except_bind_ok] at accepted
    obtain ⟨⟨_, stored⟩, _, accepted⟩ := accepted
    cases stored <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, accepted⟩ := accepted
    split at accepted
    · simp only [except_bind_ok] at accepted
      obtain ⟨_, _, _, _, _, _, invoked⟩ := accepted
      exact invokeFunction_empty _ _ _ _ _ _ invoked
    · obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
      split at accepted <;> try contradiction
      obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
      split at accepted
      all_goals
        simp only [except_bind_ok] at accepted
        try
          obtain ⟨gate, _, rest⟩ := accepted
          have _ : Unit := gate
          have accepted := rest
        obtain ⟨_, _, _, _, _, _, invoked⟩ := accepted
        exact invokeFunction_empty _ _ _ _ _ _ invoked

theorem executeEffectTerm_empty (machine : State) (context : Context) (after : Transition)
    (accepted : executeEffectTerm machine context = .ok after) : QueueCustody.controlFields after.state.control = [] := by
  unfold executeEffectTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  have empty : QueueCustody.controlFields machine.control = [] := by rw [executing]; rfl
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · exact openRequest_empty _ _ _ _ _ accepted empty
  · split at accepted <;> try contradiction
    exact installHandler_empty _ _ _ _ _ _ _ _ accepted
  · split at accepted <;> try contradiction
    exact resumeValue_empty _ _ _ _ _ _ accepted
  · split at accepted <;> try contradiction
    exact resumeValue_empty _ _ _ _ _ _ accepted
  · split at accepted <;> try contradiction
    exact resumeComputation_empty _ _ _ _ _ accepted
  · split at accepted <;> try contradiction
    exact enterRegion_empty _ _ _ _ _ _ accepted

theorem installProtection_empty (machine : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (accepted : installProtection machine context body cleanup arguments resource loan = .ok after) :
    QueueCustody.controlFields after.state.control = [] := by
  simp only [installProtection, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, accepted⟩ := accepted
  cases resource <;> cases loan <;> try contradiction
  · simp only [pure, Except.pure, Except.bind] at accepted
    exact applyClosure_empty _ _ _ _ _ accepted
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, _, rfl, applied⟩ := accepted
    exact applyClosure_empty _ _ _ _ _ applied

theorem beginCleanup_empty (machine : State) (context : Context) (id : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (accepted : beginCleanup machine context id exit normal tail = .ok after) : QueueCustody.controlFields after.state.control = [] := by
  simp only [beginCleanup, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, applied, rfl⟩ := accepted
  have empty := applyClosure_empty _ _ _ _ _ applied
  exact empty

theorem finishCleanup_empty (machine : State) (context : Context) (after : Transition)
    (accepted : finishCleanup machine context = .ok after) : QueueCustody.controlFields after.state.control = [] := by
  unfold finishCleanup at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, released, _, rfl⟩ := accepted
  cases released <;> rfl

theorem executeCleanupTerm_parked (machine : State) (context : Context) (after : Transition)
    (accepted : executeCleanupTerm machine context = .ok after) (running : machine.status = .running) : ParkedEmpty after.state := by
  unfold executeCleanupTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact fun _ _ => installProtection_empty _ _ _ _ _ _ _ _ accepted
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, ⟨middle, owner⟩, reserved, rfl⟩ := accepted
    intro request parked
    have status : middle.status = machine.status := OperandSchemas.temporary_status _ _ _ reserved
    simp only [status, running] at parked
    cases parked

theorem parked_empty_of_running (machine : State) (running : machine.status = .running) : ParkedEmpty machine := by
  intro request parked
  rw [running] at parked
  cases parked

theorem leaveScope_empty (machine : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition)
    (accepted : leaveScope machine parent invocation tail value = .ok after) : QueueCustody.controlFields after.state.control = [] := by
  simp only [leaveScope, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  rfl

theorem leaveInvocation_empty (machine : State) (after : Transition)
    (accepted : leaveInvocation machine = .ok after) : QueueCustody.controlFields after.state.control = [] := by
  unfold leaveInvocation at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  exact leaveScope_empty _ _ _ _ _ _ accepted

theorem leaveLexical_empty (machine : State) (after : Transition)
    (accepted : leaveLexical machine = .ok after) : QueueCustody.controlFields after.state.control = [] := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  rfl

theorem restoreResumeCaller_empty (machine : State) (after : Transition)
    (accepted : restoreResumeCaller machine = .ok after) : QueueCustody.controlFields after.state.control = [] := by
  unfold restoreResumeCaller at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, finished⟩ := accepted
  exact finishTemporary_empty _ _ _ finished

theorem completeHandler_empty (machine : State) (context : Context) (after : Transition)
    (accepted : completeHandler machine context = .ok after) : QueueCustody.controlFields after.state.control = [] := by
  unfold completeHandler at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  rfl

theorem cleanupFailed_status (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : cleanupFailed machine identity invocation outer normal tail inner = .ok after) :
    after.state.status = machine.status := by
  unfold cleanupFailed at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  rfl

theorem cleanupAbandoned_status (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : cleanupAbandoned machine identity invocation outer normal tail inner = .ok after) :
    after.state.status = machine.status := by
  simp only [cleanupAbandoned, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  rfl

theorem finishCleanupUnwind_status (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : finishCleanupUnwind machine identity invocation outer normal tail inner = .ok after) :
    after.state.status = machine.status := by
  unfold finishCleanupUnwind at accepted
  split at accepted <;> first
    | exact cleanupFailed_status _ _ _ _ _ _ _ _ accepted
    | exact cleanupAbandoned_status _ _ _ _ _ _ _ _ accepted
    | contradiction

theorem releaseScope_status (machine : State) (after : Transition)
    (accepted : releaseScope machine = .ok after) : after.state.status = machine.status := by
  unfold releaseScope at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  rfl

theorem discardValues_status (machine : State) (context : Context) (after : Transition)
    (accepted : discardValues machine context = .ok after) : after.state.status = machine.status := by
  unfold discardValues at accepted
  split at accepted <;> try contradiction
  split at accepted
  · cases accepted; rfl
  · split at accepted
    · cases accepted; rfl
    · simp only [bind, except_bind_ok] at accepted
      obtain ⟨⟨node, stored⟩, _, accepted⟩ := accepted
      cases stored <;> try contradiction
      all_goals simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      all_goals obtain ⟨_, _, rfl⟩ := accepted
      all_goals rfl

theorem unwindStep_parked (machine : State) (context : Context) (after : Transition)
    (accepted : unwindStep machine context = .ok after) (running : machine.status = .running) : ParkedEmpty after.state := by
  unfold unwindStep at accepted
  split at accepted <;> try contradiction
  rename_i original unwinding
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  cases stacked : machine.stack with
  | nil =>
    simp only [stacked] at accepted
    split at accepted
    · cases accepted; exact parked_empty_of_running _ running
    · split at accepted <;> try contradiction
      all_goals cases accepted
      all_goals intro request parked; cases parked
  | cons saved tail =>
    cases saved <;> simp only [stacked] at accepted
    all_goals first
      | (exact fun _ _ => beginCleanup_empty _ _ _ _ _ _ _ accepted)
      | (exact parked_empty_of_running _ ((finishCleanupUnwind_status _ _ _ _ _ _ _ _ accepted).trans running))
      | (cases accepted; exact parked_empty_of_running _ running)
      | skip
    case invocation =>
      split at accepted <;> cases accepted <;> exact parked_empty_of_running _ running
    case lexical =>
      split at accepted
      · cases accepted; exact parked_empty_of_running _ running
      · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨_, _, _, _, rfl⟩ := accepted
        exact parked_empty_of_running _ running
    case disposalReturn remaining afterRelease invocation scope =>
      cases primaryIs : (observedExit machine original).primary <;> simp only [primaryIs] at accepted
      all_goals cases afterRelease <;> simp only [pure, Except.pure, Except.bind] at accepted
      all_goals cases accepted
      all_goals exact parked_empty_of_running _ running

theorem tickRunning_parked (machine : State) (context : Context) (after : Transition)
    (accepted : tickRunning machine context = .ok after) (running : machine.status = .running) : ParkedEmpty after.state := by
  cases executing : machine.control <;> simp only [tickRunning, executing] at accepted
  case term =>
    unfold enterTerm at accepted
    split at accepted <;> try contradiction
    split at accepted <;> try contradiction
    repeat' split at accepted
    all_goals cases accepted
    all_goals intro request parked
    all_goals simp only [running] at parked
    all_goals cases parked
  case expression => exact parked_empty_of_running _ ((OperandSchemas.enterExpression_status _ _ _ accepted).trans running)
  case invoke => exact fun _ _ => enterInvocation_empty _ _ _ accepted
  case release => exact parked_empty_of_running _ ((releaseScope_status _ _ accepted).trans running)
  case discard => exact parked_empty_of_running _ ((discardValues_status _ _ _ accepted).trans running)
  case unwind => exact unwindStep_parked _ _ _ accepted running
  case execute intent bindings operands =>
    cases intent with
    | primitive => exact parked_empty_of_running _ ((OperandSchemas.executePrimitive_status _ _ _ accepted).trans running)
    | term term =>
      cases term <;> first
        | exact (fun _ _ => executeEffectTerm_empty _ _ _ accepted)
        | exact executeCleanupTerm_parked _ _ _ accepted running
        | exact (fun _ _ => executeControlTerm_empty _ _ _ accepted)
  case delivered value =>
    cases stacked : machine.stack with
    | nil =>
      simp only [stacked, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
      intro request parked
      cases parked
    | cons saved tail =>
      cases saved <;> simp only [stacked] at accepted
      all_goals first
        | exact (fun _ _ => enterBinding_empty _ _ _ accepted)
        | exact parked_empty_of_running _ ((OperandSchemas.deliverOperand_status _ _ accepted).trans running)
        | exact (fun _ _ => leaveInvocation_empty _ _ accepted)
        | exact (fun _ _ => leaveLexical_empty _ _ accepted)
        | exact (fun _ _ => restoreResumeCaller_empty _ _ accepted)
        | exact (fun _ _ => completeHandler_empty _ _ _ accepted)
        | exact (fun _ _ => beginCleanup_empty _ _ _ _ _ _ _ accepted)
        | exact (fun _ _ => finishCleanup_empty _ _ _ accepted)
        | (cases accepted; exact parked_empty_of_running _ running)
        | skip
      case disposalReturn =>
        unfold finishDisposal at accepted
        split at accepted <;> try contradiction
        split at accepted <;> try contradiction
        cases accepted
        exact parked_empty_of_running _ running

theorem tick_parked (machine : State) (context : Context) (after : Transition)
    (accepted : tick machine context = .ok after) (valid : ParkedEmpty machine) : ParkedEmpty after.state := by
  cases phase : machine.status <;> simp only [tick, phase] at accepted
  · exact tickRunning_parked _ _ _ accepted phase
  all_goals cases accepted; exact valid

end CustodyCoverage
end BoundaryV2.Profile.Source.Machine
