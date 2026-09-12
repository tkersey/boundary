import BoundaryV2.SourceUnwindTypes

namespace BoundaryV2.Profile.Source.Machine
namespace Cancellation

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem temporary_cancellation (before after : State) (owner : Custody.Owner)
    (accepted : temporary before = .ok (after, owner)) : after.cancellation = before.cancellation := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  rfl

theorem finishTemporary_cancellation (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) : after.state.cancellation = machine.cancellation := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  cases accepted
  rfl

theorem scopedValue_cancellation (machine : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue machine value = .ok after) : after.state.cancellation = machine.cancellation := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, finished⟩ := accepted
  have middleStatus := temporary_cancellation _ _ _ temporaryOk
  have finalStatus := finishTemporary_cancellation _ _ _ finished
  exact finalStatus.trans middleStatus

theorem commitPure_cancellation (machine : State) (opcode : Opcode) (operands : List Located)
    (value : SemanticValue) (after : Transition) (accepted : commitPure machine opcode operands value = .ok after) :
    after.state.cancellation = machine.cancellation := by
  simp only [commitPure, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, accepted⟩ := accepted
  have middleStatus := temporary_cancellation _ _ _ temporaryOk
  split at accepted <;> simp only [except_bind_ok] at accepted
  · obtain ⟨_, _, _, _, finished⟩ := accepted
    exact (finishTemporary_cancellation _ _ _ finished).trans middleStatus
  · obtain ⟨_, _, _, _, _, _, finished⟩ := accepted
    exact (finishTemporary_cancellation _ _ _ finished).trans middleStatus

theorem makeClosureWithValues_cancellation (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues machine context schema function values = .ok after) : after.state.cancellation = machine.cancellation := by
  simp only [makeClosureWithValues, bind, except_bind_ok] at accepted
  obtain ⟨_, _, ⟨middle, owner⟩, temporaryOk, _, _, ⟨_, _⟩, _, finished⟩ := accepted
  have middleStatus := temporary_cancellation _ _ _ temporaryOk
  have finalStatus := finishTemporary_cancellation _ _ _ finished
  exact finalStatus.trans middleStatus

theorem makeClosure_cancellation (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (bindings : Environment) (after : Transition)
    (accepted : makeClosure machine context schema function bindings = .ok after) : after.state.cancellation = machine.cancellation := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  exact makeClosureWithValues_cancellation _ _ _ _ _ _ accepted

theorem enterExpression_cancellation (machine : State) (context : Context) (after : Transition)
    (accepted : enterExpression machine context = .ok after) : after.state.cancellation = machine.cancellation := by
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
    exact scopedValue_cancellation _ _ _ accepted
  | lambda => exact makeClosure_cancellation _ _ _ _ _ _ accepted
  | primitive opcode operands => cases operands <;> cases accepted <;> rfl

set_option maxRecDepth 4096 in
set_option maxHeartbeats 1600000 in
theorem heapPrimitive_cancellation (machine : State) (context : Context)
    (operation : Primitives.GraphOperation) (schema : SchemaId .source) (immediate : Nat)
    (operands : List Located) (after : Transition)
    (accepted : heapPrimitive machine context operation schema immediate operands = .ok after) :
    after.state.cancellation = machine.cancellation := by
  cases operation <;> simp only [heapPrimitive, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  all_goals try split at accepted
  all_goals grind (gen := 32) only [except_bind_ok, fromOption_ok,
    → temporary_cancellation, → finishTemporary_cancellation, → scopedValue_cancellation,
    → commitPure_cancellation, → makeClosureWithValues_cancellation]

theorem executePrimitive_cancellation (machine : State) (context : Context) (after : Transition)
    (accepted : executePrimitive machine context = .ok after) : after.state.cancellation = machine.cancellation := by
  unfold executePrimitive at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · contradiction
  · simp only [authoredFailure, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
    rfl
  · exact commitPure_cancellation _ _ _ _ _ accepted
  · exact heapPrimitive_cancellation _ _ _ _ _ _ _ accepted

theorem deliverOperand_cancellation (machine : State) (after : Transition)
    (accepted : deliverOperand machine = .ok after) : after.state.cancellation = machine.cancellation := by
  unfold deliverOperand at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  split at accepted <;> cases accepted <;> rfl


theorem createScope_cancellation (machine : State) (context : Context) (invocation : InvocationId)
    (parent : Option LexicalScopeId) (vars : List VariableId) (values : List Located) (bindings : Environment)
    (after : State) (entered : Environment)
    (accepted : createScope machine context invocation parent vars values bindings = .ok (after, entered)) :
    after.cancellation = machine.cancellation := by
  simp only [createScope, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · cases accepted; rfl
  · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, equal⟩ := accepted
    cases equal
    rfl

theorem invokeFunction_cancellation (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction machine context function bindings arguments = .ok after) :
    after.state.cancellation = machine.cancellation := by
  simp only [invokeFunction, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, ⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have result := createScope_cancellation _ _ _ _ _ _ _ _ _ scopeOk
  exact result

theorem applyClosure_cancellation (machine : State) (context : Context) (closure : Located)
    (arguments : List Located) (after : Transition)
    (accepted : applyClosure machine context closure arguments = .ok after) : after.state.cancellation = machine.cancellation := by
  simp only [applyClosure, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    have result := invokeFunction_cancellation _ _ _ _ _ _ accepted
    exact result
  · simp only [pure, Except.pure, Except.bind] at accepted
    have result := invokeFunction_cancellation _ _ _ _ _ _ accepted
    exact result

theorem enterInvocation_cancellation (machine : State) (context : Context) (after : Transition)
    (accepted : enterInvocation machine context = .ok after) : after.state.cancellation = machine.cancellation := by
  unfold enterInvocation at accepted
  split at accepted <;> try contradiction
  exact invokeFunction_cancellation _ _ _ _ _ _ accepted

theorem enterBinding_cancellation (machine : State) (context : Context) (after : Transition)
    (accepted : enterBinding machine context = .ok after) : after.state.cancellation = machine.cancellation := by
  unfold enterBinding at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have result := createScope_cancellation _ _ _ _ _ _ _ _ _ scopeOk
  split <;> exact result

theorem enterPattern_cancellation (machine : State) (context : Context) (vars : List VariableId)
    (parts : List SemanticValue) (owner : Custody.Owner) (body : TermId) (bindings : Environment) (after : Transition)
    (accepted : enterPattern machine context vars parts owner body bindings = .ok after) :
    after.state.cancellation = machine.cancellation := by
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have result := createScope_cancellation _ _ _ _ _ _ _ _ _ scopeOk
  split <;> exact result

theorem instantiateCapture_cancellation (machine : State) (context : Context) (saved : Capture) (after : State × Capture)
    (accepted : instantiateCapture machine context saved = .ok after) : after.1.cancellation = machine.cancellation := by
  simp only [instantiateCapture, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ := accepted
  rfl

theorem takeCapture_cancellation (machine : State) (context : Context) (token : Located) (after : State × Capture)
    (accepted : takeCapture machine context token = .ok after) : after.1.cancellation = machine.cancellation := by
  simp only [takeCapture, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, rfl⟩ := accepted
    rfl
  · exact instantiateCapture_cancellation _ _ _ _ accepted

theorem activateCapture_cancellation (machine : State) (context : Context) (saved : Capture)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : State)
    (accepted : activateCapture machine context saved successor = .ok after) : after.cancellation = machine.cancellation := by
  simp only [activateCapture, bind, except_bind_ok, pure, Except.pure] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  cases successor with
  | none => cases accepted; rfl
  | some successor =>
    rcases successor with ⟨handler, stored, bindings⟩
    simp only [except_bind_ok, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, _, rfl, rfl⟩ := accepted
    rfl

theorem resumeValue_cancellation (machine : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (accepted : resumeValue machine context token argument successor = .ok after) : after.state.cancellation = machine.cancellation := by
  simp only [resumeValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, _, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok] at accepted
  obtain ⟨_, _, active, activated, ⟨middle, owner⟩, temporaryOk, _, _, finished⟩ := accepted
  have first := takeCapture_cancellation _ _ _ _ captured
  have second := activateCapture_cancellation _ _ _ _ _ activated
  have third := temporary_cancellation _ _ _ temporaryOk
  have fourth := finishTemporary_cancellation _ _ _ finished
  exact fourth.trans (third.trans (second.trans first))

theorem resumeComputation_cancellation (machine : State) (context : Context) (token computation : Located)
    (after : Transition) (accepted : resumeComputation machine context token computation = .ok after) :
    after.state.cancellation = machine.cancellation := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, active, activated, applied⟩ := accepted
  have first := takeCapture_cancellation _ _ _ _ captured
  have second := activateCapture_cancellation _ _ _ _ _ activated
  have third := applyClosure_cancellation _ _ _ _ _ applied
  exact third.trans (second.trans first)


theorem executeControlTerm_cancellation (machine : State) (context : Context) (after : Transition)
    (accepted : executeControlTerm machine context = .ok after) : after.state.cancellation = machine.cancellation := by
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
    rfl
  case call => cases accepted; rfl
  case apply =>
    split at accepted <;> try contradiction
    have result := applyClosure_cancellation _ _ _ _ _ accepted
    exact result
  case fail =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, rfl⟩ := accepted
    rfl
  case matchSum =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact enterPattern_cancellation _ _ _ _ _ _ _ _ accepted
  case unpackProduct =>
    split at accepted <;> try contradiction
    exact enterPattern_cancellation _ _ _ _ _ _ _ _ accepted

theorem completeHandler_cancellation (machine : State) (context : Context) (after : Transition)
    (accepted : completeHandler machine context = .ok after) : after.state.cancellation = machine.cancellation := by
  unfold completeHandler at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  rfl

theorem installHandler_cancellation (machine : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (bindings : Environment) (after : Transition)
    (accepted : installHandler machine context handler body arguments stored bindings = .ok after) : after.state.cancellation = machine.cancellation := by
  simp only [installHandler, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, applied⟩ := accepted
  have result := applyClosure_cancellation _ _ _ _ _ applied
  exact result

theorem enterRegion_cancellation (machine : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition)
    (accepted : enterRegion machine context descriptor body arguments = .ok after) : after.state.cancellation = machine.cancellation := by
  simp only [enterRegion, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, applied⟩ := accepted
  have result := applyClosure_cancellation _ _ _ _ _ applied
  exact result

theorem resumeRelease_cancellation (machine : State) (after : AfterRelease) : (resumeRelease machine after).state.cancellation = machine.cancellation := by
  cases after <;> rfl

theorem installProtection_cancellation (machine : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (accepted : installProtection machine context body cleanup arguments resource loan = .ok after) : after.state.cancellation = machine.cancellation := by
  simp only [installProtection, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, accepted⟩ := accepted
  cases resource <;> cases loan <;> try contradiction
  · simp only [pure, Except.pure, Except.bind] at accepted
    have result := applyClosure_cancellation _ _ _ _ _ accepted
    exact result
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, _, rfl, applied⟩ := accepted
    have result := applyClosure_cancellation _ _ _ _ _ applied
    exact result

theorem beginCleanup_cancellation (machine : State) (context : Context) (identity : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (accepted : beginCleanup machine context identity exit normal tail = .ok after) : after.state.cancellation = machine.cancellation := by
  simp only [beginCleanup, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, applied, rfl⟩ := accepted
  have result := applyClosure_cancellation _ _ _ _ _ applied
  exact result

theorem finishCleanup_cancellation (machine : State) (context : Context) (after : Transition)
    (accepted : finishCleanup machine context = .ok after) : after.state.cancellation = machine.cancellation := by
  unfold finishCleanup at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, rfl⟩ := accepted
  exact resumeRelease_cancellation _ _

theorem cleanupFailed_cancellation (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : cleanupFailed machine identity invocation outer normal tail inner = .ok after) :
    after.state.cancellation = machine.cancellation := by
  unfold cleanupFailed at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  rfl

theorem cleanupAbandoned_cancellation (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : cleanupAbandoned machine identity invocation outer normal tail inner = .ok after) : after.state.cancellation = machine.cancellation := by
  simp only [cleanupAbandoned, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  rfl

theorem finishCleanupUnwind_cancellation (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : finishCleanupUnwind machine identity invocation outer normal tail inner = .ok after) : after.state.cancellation = machine.cancellation := by
  unfold finishCleanupUnwind at accepted
  split at accepted <;> first
    | exact cleanupFailed_cancellation _ _ _ _ _ _ _ _ accepted
    | exact cleanupAbandoned_cancellation _ _ _ _ _ _ _ _ accepted
    | contradiction

theorem finishDisposal_cancellation (machine : State) (after : Transition)
    (accepted : finishDisposal machine = .ok after) : after.state.cancellation = machine.cancellation := by
  unfold finishDisposal at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  rfl

theorem releaseScope_cancellation (machine : State) (after : Transition)
    (accepted : releaseScope machine = .ok after) : after.state.cancellation = machine.cancellation := by
  unfold releaseScope at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  rfl

theorem executeCleanupTerm_cancellation (machine : State) (context : Context) (after : Transition)
    (accepted : executeCleanupTerm machine context = .ok after) : after.state.cancellation = machine.cancellation := by
  unfold executeCleanupTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact installProtection_cancellation _ _ _ _ _ _ _ _ accepted
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, ⟨middle, owner⟩, temporaryOk, rfl⟩ := accepted
    have result := temporary_cancellation _ _ _ temporaryOk
    exact result

theorem discardValues_cancellation (machine : State) (context : Context) (after : Transition)
    (accepted : discardValues machine context = .ok after) : after.state.cancellation = machine.cancellation := by
  unfold discardValues at accepted
  split at accepted <;> try contradiction
  split at accepted
  · cases accepted; exact resumeRelease_cancellation _ _
  · split at accepted
    · cases accepted; rfl
    · simp only [bind, except_bind_ok] at accepted
      obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
      cases stored <;> try contradiction
      all_goals simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      all_goals obtain ⟨_, _, rfl⟩ := accepted
      all_goals rfl


theorem enterTerm_cancellation (machine : State) (source : Module) (after : Transition)
    (accepted : enterTerm machine source = .ok after) : after.state.cancellation = machine.cancellation := by
  unfold enterTerm at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  repeat' split at accepted
  all_goals cases accepted; rfl

theorem leaveScope_cancellation (machine : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition)
    (accepted : leaveScope machine parent invocation tail value = .ok after) : after.state.cancellation = machine.cancellation := by
  simp only [leaveScope, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, _, _, finished, finishedOk, rfl⟩ := accepted
  have first := temporary_cancellation _ _ _ temporaryOk
  have second := finishTemporary_cancellation _ _ _ finishedOk
  exact second.trans first

theorem leaveInvocation_cancellation (machine : State) (after : Transition)
    (accepted : leaveInvocation machine = .ok after) : after.state.cancellation = machine.cancellation := by
  unfold leaveInvocation at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  exact leaveScope_cancellation _ _ _ _ _ _ accepted

theorem leaveLexical_cancellation (machine : State) (after : Transition)
    (accepted : leaveLexical machine = .ok after) : after.state.cancellation = machine.cancellation := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, leaving, accepted⟩ := accepted
  have result := leaveScope_cancellation _ _ _ _ _ _ leaving
  split at accepted <;> try contradiction
  simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact result

theorem restoreResumeCaller_cancellation (machine : State) (after : Transition)
    (accepted : restoreResumeCaller machine = .ok after) : after.state.cancellation = machine.cancellation := by
  unfold restoreResumeCaller at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, _, _, finished⟩ := accepted
  have first := temporary_cancellation _ _ _ temporaryOk
  have second := finishTemporary_cancellation _ _ _ finished
  exact second.trans first

theorem openRequest_cancellation (machine : State) (context : Context) (operation : Operation)
    (operands : List Located) (after : Transition) (accepted : openRequest machine context operation operands = .ok after) :
    after.state.cancellation = machine.cancellation := by
  simp only [openRequest, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, accepted⟩ := accepted
  split at accepted
  · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    rfl
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, accepted⟩ := accepted
    split at accepted
    · simp only [except_bind_ok] at accepted
      obtain ⟨_, _, _, _, _, _, invoked⟩ := accepted
      have result := invokeFunction_cancellation _ _ _ _ _ _ invoked
      exact result
    · simp only [except_bind_ok] at accepted
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
        obtain ⟨⟨outside, owner⟩, temporaryOk, _, _, staged, stagedOk, invoked⟩ := accepted
        have first := temporary_cancellation _ _ _ temporaryOk
        have second := finishTemporary_cancellation _ _ _ stagedOk
        exact (invokeFunction_cancellation _ _ _ _ _ _ invoked).trans (second.trans first)

theorem executeEffectTerm_cancellation (machine : State) (context : Context) (after : Transition)
    (accepted : executeEffectTerm machine context = .ok after) : after.state.cancellation = machine.cancellation := by
  unfold executeEffectTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  cases term <;> simp only at accepted <;> try contradiction
  case perform operation => exact openRequest_cancellation _ _ _ _ _ accepted
  all_goals split at accepted <;> try contradiction
  all_goals first
    | exact installHandler_cancellation _ _ _ _ _ _ _ _ accepted
    | exact resumeValue_cancellation _ _ _ _ _ _ accepted
    | exact resumeComputation_cancellation _ _ _ _ _ accepted
    | exact enterRegion_cancellation _ _ _ _ _ _ accepted

theorem unwindStep_cancellation (machine : State) (context : Context) (after : Transition)
    (accepted : unwindStep machine context = .ok after) : after.state.cancellation = machine.cancellation := by
  unfold unwindStep at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  cases stacked : machine.stack with
  | nil =>
    simp only [stacked] at accepted
    split at accepted
    · cases accepted; rfl
    · split at accepted <;> try contradiction
      all_goals cases accepted; rfl
  | cons saved tail =>
    cases saved <;> simp only [stacked] at accepted
    case invocation => split at accepted <;> cases accepted <;> rfl
    case lexical =>
      split at accepted
      · cases accepted; rfl
      · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨_, _, _, _, rfl⟩ := accepted
        rfl
    case protection => exact beginCleanup_cancellation _ _ _ _ _ _ _ accepted
    case cleanupReturn => exact finishCleanupUnwind_cancellation _ _ _ _ _ _ _ _ accepted
    case disposalReturn =>
      repeat' split at accepted
      all_goals simp only [pure, Except.pure, Except.bind, Except.ok.injEq] at accepted
      all_goals cases accepted; rfl
    all_goals cases accepted; rfl

theorem tickRunning_cancellation (machine : State) (context : Context) (after : Transition)
    (accepted : tickRunning machine context = .ok after) : after.state.cancellation = machine.cancellation := by
  cases executing : machine.control <;> simp only [tickRunning, executing] at accepted
  case term => exact enterTerm_cancellation _ _ _ accepted
  case expression => exact enterExpression_cancellation _ _ _ accepted
  case invoke => exact enterInvocation_cancellation _ _ _ accepted
  case release => exact releaseScope_cancellation _ _ accepted
  case discard => exact discardValues_cancellation _ _ _ accepted
  case unwind => exact unwindStep_cancellation _ _ _ accepted
  case execute intent bindings operands =>
    cases intent with
    | primitive => exact executePrimitive_cancellation _ _ _ accepted
    | term term =>
      cases term <;> first
        | exact executeEffectTerm_cancellation _ _ _ accepted
        | exact executeCleanupTerm_cancellation _ _ _ accepted
        | exact executeControlTerm_cancellation _ _ _ accepted
  case delivered value =>
    cases stacked : machine.stack with
    | nil =>
      simp only [stacked, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
      rfl
    | cons saved tail =>
      cases saved <;> simp only [stacked] at accepted
      all_goals first
        | exact enterBinding_cancellation _ _ _ accepted
        | exact deliverOperand_cancellation _ _ accepted
        | exact leaveInvocation_cancellation _ _ accepted
        | exact leaveLexical_cancellation _ _ accepted
        | exact restoreResumeCaller_cancellation _ _ accepted
        | exact completeHandler_cancellation _ _ _ accepted
        | exact beginCleanup_cancellation _ _ _ _ _ _ _ accepted
        | exact finishCleanup_cancellation _ _ _ accepted
        | exact finishDisposal_cancellation _ _ accepted
        | (cases accepted; rfl)
        | contradiction

theorem tick_cancellation (machine : State) (context : Context) (after : Transition)
    (accepted : tick machine context = .ok after) : after.state.cancellation = machine.cancellation := by
  cases phase : machine.status <;> simp only [tick, phase] at accepted
  · exact tickRunning_cancellation _ _ _ accepted
  all_goals cases accepted; rfl

end Cancellation
end BoundaryV2.Profile.Source.Machine
