import BoundaryV2.SourceObligationLaws

namespace BoundaryV2.Profile.Source.Machine

/-- Logical opening occurrences; parked observations and request rebinding
are different events and cannot allocate an additional opening here. -/
def requestOccurrences (events : List Event) : List Nat := events.filterMap fun event => match event with
  | .requestOpened request => some request.occurrence.value
  | _ => none

def EventClock (before after : State) (events : List Event) : Prop :=
  (after.nextOccurrence = before.nextOccurrence ∧ requestOccurrences events = []) ∨
    (after.nextOccurrence = before.nextOccurrence + 1 ∧ requestOccurrences events = [before.nextOccurrence])

theorem requestOccurrences_append (first second : List Event) :
    requestOccurrences (first ++ second) = requestOccurrences first ++ requestOccurrences second := by
  simp [requestOccurrences, List.filterMap_append]

theorem requestOccurrences_cleanup (events : List Cleanup.Event) :
    requestOccurrences (events.map Event.cleanup) = [] := by
  induction events with
  | nil => rfl
  | cons event rest induction => simp_all [requestOccurrences]

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β)
    (result : β) : value.bind next = .ok result ↔
      ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem temporary_event_clock (state after : State) (owner : Custody.Owner)
    (accepted : temporary state = .ok (after, owner)) : after.nextOccurrence = state.nextOccurrence := by
  simp only [temporary, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem finishTemporary_event_clock (state : State) (value : Located) (after : Transition)
    (accepted : finishTemporary state value = .ok after) : EventClock state after.state after.events := by
  simp only [finishTemporary, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, finishValue] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem finishTemporary_quiet (state : State) (value : Located) (after : Transition)
    (accepted : finishTemporary state value = .ok after) :
    after.state.nextOccurrence = state.nextOccurrence ∧ after.events = [] := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  cases accepted
  exact ⟨rfl, rfl⟩

theorem scopedValue_event_clock (state : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue state value = .ok after) : EventClock state after.state after.events := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → temporary_event_clock, → finishTemporary_event_clock, → finishTemporary_quiet,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem scopedValue_quiet (state : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue state value = .ok after) :
    after.state.nextOccurrence = state.nextOccurrence ∧ after.events = [] := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, first, last⟩ := accepted
  have a := temporary_event_clock _ _ _ first
  have b := finishTemporary_quiet _ _ _ last
  exact ⟨b.1.trans a, b.2⟩

theorem makeClosureWithValues_event_clock (state : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues state context schema function values = .ok after) :
    EventClock state after.state after.events := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → temporary_event_clock, → finishTemporary_event_clock, → finishTemporary_quiet,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem makeClosure_event_clock (state : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (environment : Environment) (after : Transition)
    (accepted : makeClosure state context schema function environment = .ok after) : EventClock state after.state after.events := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → makeClosureWithValues_event_clock,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem enterTerm_event_clock (state : State) (source : Module) (after : Transition)
    (accepted : enterTerm state source = .ok after) : EventClock state after.state after.events := by
  simp only [enterTerm, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem deliverOperand_event_clock (state : State) (after : Transition)
    (accepted : deliverOperand state = .ok after) : EventClock state after.state after.events := by
  simp only [deliverOperand, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem authoredFailure_event_clock (state : State) (context : Context) (failures : List (InstructionFailure .source)) (fault : Fault) (after : Transition)
    (accepted : authoredFailure state context failures fault = .ok after) : EventClock state after.state after.events := by
  simp only [authoredFailure, bind, except_bind_ok, fromOption_ok, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem enterExpression_event_clock (state : State) (context : Context) (after : Transition)
    (accepted : enterExpression state context = .ok after) : EventClock state after.state after.events := by
  simp only [enterExpression, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, finishValue] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → scopedValue_event_clock, → scopedValue_quiet, → makeClosure_event_clock,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem commitPure_event_clock (state : State) (opcode : Opcode) (operands : List Located) (result : SemanticValue) (after : Transition)
    (accepted : commitPure state opcode operands result = .ok after) : EventClock state after.state after.events := by
  simp only [commitPure, bind, except_bind_ok] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → temporary_event_clock, → finishTemporary_event_clock, → finishTemporary_quiet,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem heapPrimitive_event_clock (state : State) (context : Context) (operation : Primitives.GraphOperation)
    (schema : SchemaId .source) (immediate : Nat) (operands : List Located) (after : Transition)
    (accepted : heapPrimitive state context operation schema immediate operands = .ok after) : EventClock state after.state after.events := by
  simp only [heapPrimitive, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → makeClosureWithValues_event_clock, → temporary_event_clock, → finishTemporary_event_clock, → finishTemporary_quiet, → scopedValue_event_clock, → scopedValue_quiet, → commitPure_event_clock,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem executePrimitive_event_clock (state : State) (context : Context) (after : Transition)
    (accepted : executePrimitive state context = .ok after) : EventClock state after.state after.events := by
  simp only [executePrimitive, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → authoredFailure_event_clock, → commitPure_event_clock, → heapPrimitive_event_clock,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem createScope_event_clock (state : State) (context : Context) (invocation : InvocationId) (parent : Option LexicalScopeId)
    (vars : List VariableId) (values : List Located) (environment : Environment) (after : State × Environment)
    (accepted : createScope state context invocation parent vars values environment = .ok after) : after.1.nextOccurrence = state.nextOccurrence := by
  simp only [createScope, bind, except_bind_ok, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem invokeFunction_event_clock (state : State) (context : Context) (function : FunctionId .source)
    (environment : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction state context function environment arguments = .ok after) : EventClock state after.state after.events := by
  simp only [invokeFunction, bind, except_bind_ok, fromOption_ok, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → createScope_event_clock,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem applyClosure_event_clock (state : State) (context : Context) (closure : Located) (arguments : List Located) (after : Transition)
    (accepted : applyClosure state context closure arguments = .ok after) : EventClock state after.state after.events := by
  simp only [applyClosure, bind, except_bind_ok, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → invokeFunction_event_clock,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem enterInvocation_event_clock (state : State) (context : Context) (after : Transition)
    (accepted : enterInvocation state context = .ok after) : EventClock state after.state after.events := by
  simp only [enterInvocation, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → invokeFunction_event_clock,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem enterBinding_event_clock (state : State) (context : Context) (after : Transition)
    (accepted : enterBinding state context = .ok after) : EventClock state after.state after.events := by
  simp only [enterBinding, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → createScope_event_clock,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem enterPattern_event_clock (state : State) (context : Context) (vars : List VariableId) (parts : List SemanticValue)
    (owner : Custody.Owner) (body : TermId) (environment : Environment) (after : Transition)
    (accepted : enterPattern state context vars parts owner body environment = .ok after) : EventClock state after.state after.events := by
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → createScope_event_clock,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem executeControlTerm_event_clock (state : State) (context : Context) (after : Transition)
    (accepted : executeControlTerm state context = .ok after) : EventClock state after.state after.events := by
  simp only [executeControlTerm, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → applyClosure_event_clock, → enterPattern_event_clock,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem leaveScope_quiet (state : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition)
    (accepted : leaveScope state parent invocation tail value = .ok after) :
    after.state.nextOccurrence = state.nextOccurrence ∧ after.events = [] := by
  simp only [leaveScope, bind, except_bind_ok, pure, Except.pure] at accepted
  grind only [→ temporary_event_clock, → finishTemporary_quiet]

theorem leaveScope_event_clock (state : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition)
    (accepted : leaveScope state parent invocation tail value = .ok after) : EventClock state after.state after.events := by
  simp only [leaveScope, bind, except_bind_ok, fromOption_ok, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → temporary_event_clock, → finishTemporary_event_clock, → finishTemporary_quiet,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem leaveInvocation_event_clock (state : State) (after : Transition)
    (accepted : leaveInvocation state = .ok after) : EventClock state after.state after.events := by
  simp only [leaveInvocation, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → leaveScope_event_clock,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem leaveLexical_event_clock (state : State) (after : Transition)
    (accepted : leaveLexical state = .ok after) : EventClock state after.state after.events := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, record, _, parent, _, result, departed, remaining⟩ := accepted
  split at remaining <;> try contradiction
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at remaining
  obtain ⟨parentRecord, _, heap, moved, equal⟩ := remaining
  cases equal
  have h1 := leaveScope_quiet _ _ _ _ _ _ departed
  exact Or.inl ⟨h1.1, rfl⟩

theorem finishEmptyRelease_event_clock (state : State) (after : Transition)
    (accepted : finishEmptyRelease state = .ok after) : EventClock state after.state after.events := by
  simp only [finishEmptyRelease, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, resumeRelease] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem instantiateCapture_event_clock (state : State) (context : Context) (capture : Capture) (after : State × Capture)
    (accepted : instantiateCapture state context capture = .ok after) : after.1.nextOccurrence = state.nextOccurrence := by
  unfold instantiateCapture at accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  cases accepted
  rfl

theorem installHandler_event_clock (state : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (environment : Environment) (after : Transition)
    (accepted : installHandler state context handler body arguments stored environment = .ok after) :
    EventClock state after.state after.events := by
  simp only [installHandler, bind, except_bind_ok, fromOption_ok, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → applyClosure_event_clock,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem completeHandler_event_clock (state : State) (context : Context) (after : Transition)
    (accepted : completeHandler state context = .ok after) : EventClock state after.state after.events := by
  simp only [completeHandler, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem openRequest_event_clock (state : State) (context : Context) (operation : Operation) (operands : List Located) (after : Transition)
    (accepted : openRequest state context operation operands = .ok after) : EventClock state after.state after.events := by
  simp only [openRequest, bind, except_bind_ok, fromOption_ok, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → invokeFunction_event_clock, → temporary_event_clock, → finishTemporary_event_clock, → finishTemporary_quiet,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem takeCapture_event_clock (state : State) (context : Context) (token : Located) (after : State × Capture)
    (accepted : takeCapture state context token = .ok after) : after.1.nextOccurrence = state.nextOccurrence := by
  simp only [takeCapture, bind, except_bind_ok, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → instantiateCapture_event_clock,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem activateCapture_event_clock (state : State) (context : Context) (capture : Capture)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : State)
    (accepted : activateCapture state context capture successor = .ok after) : after.nextOccurrence = state.nextOccurrence := by
  simp only [activateCapture, bind, except_bind_ok, fromOption_ok, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem resumeValue_event_clock (state : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (accepted : resumeValue state context token argument successor = .ok after) : EventClock state after.state after.events := by
  simp only [resumeValue, bind, except_bind_ok, fromOption_ok, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → takeCapture_event_clock, → activateCapture_event_clock, → temporary_event_clock, → finishTemporary_event_clock, → finishTemporary_quiet,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem resumeComputation_event_clock (state : State) (context : Context) (token computation : Located) (after : Transition)
    (accepted : resumeComputation state context token computation = .ok after) : EventClock state after.state after.events := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → takeCapture_event_clock, → activateCapture_event_clock, → applyClosure_event_clock,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem restoreResumeCaller_event_clock (state : State) (after : Transition)
    (accepted : restoreResumeCaller state = .ok after) : EventClock state after.state after.events := by
  simp only [restoreResumeCaller, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → temporary_event_clock, → finishTemporary_event_clock, → finishTemporary_quiet,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem enterRegion_event_clock (state : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition)
    (accepted : enterRegion state context descriptor body arguments = .ok after) : EventClock state after.state after.events := by
  simp only [enterRegion, bind, except_bind_ok, fromOption_ok] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → applyClosure_event_clock,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem executeEffectTerm_event_clock (state : State) (context : Context) (after : Transition)
    (accepted : executeEffectTerm state context = .ok after) : EventClock state after.state after.events := by
  simp only [executeEffectTerm, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → openRequest_event_clock, → installHandler_event_clock, → resumeValue_event_clock, → resumeComputation_event_clock, → enterRegion_event_clock,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem installProtection_event_clock (state : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (accepted : installProtection state context body cleanup arguments resource loan = .ok after) : EventClock state after.state after.events := by
  simp only [installProtection, bind, except_bind_ok, fromOption_ok, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → applyClosure_event_clock,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem beginCleanup_event_clock (state : State) (context : Context) (identity : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (accepted : beginCleanup state context identity exit normal tail = .ok after) : EventClock state after.state after.events := by
  simp only [beginCleanup, bind, except_bind_ok, fromOption_ok, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → applyClosure_event_clock,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem finishCleanup_event_clock (state : State) (context : Context) (after : Transition)
    (accepted : finishCleanup state context = .ok after) : EventClock state after.state after.events := by
  simp only [finishCleanup, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, resumeRelease] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem cleanupFailed_event_clock (state : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : cleanupFailed state identity invocation outer normal tail inner = .ok after) : EventClock state after.state after.events := by
  simp only [cleanupFailed, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem releaseScope_event_clock (state : State) (after : Transition)
    (accepted : releaseScope state = .ok after) : EventClock state after.state after.events := by
  simp only [releaseScope, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem discardValues_event_clock (state : State) (context : Context) (after : Transition)
    (accepted : discardValues state context = .ok after) : EventClock state after.state after.events := by
  simp only [discardValues, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, resumeRelease] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem unwindStep_event_clock (state : State) (context : Context) (after : Transition)
    (accepted : unwindStep state context = .ok after) : EventClock state after.state after.events := by
  simp only [unwindStep, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → beginCleanup_event_clock, → cleanupFailed_event_clock,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem executeCleanupTerm_event_clock (state : State) (context : Context) (after : Transition)
    (accepted : executeCleanupTerm state context = .ok after) : EventClock state after.state after.events := by
  simp only [executeCleanupTerm, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → installProtection_event_clock, → temporary_event_clock,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem tickRunning_event_clock (state : State) (context : Context) (after : Transition)
    (accepted : tickRunning state context = .ok after) : EventClock state after.state after.events := by
  simp only [tickRunning, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → enterTerm_event_clock, → enterExpression_event_clock, → enterInvocation_event_clock, → releaseScope_event_clock, → discardValues_event_clock, → unwindStep_event_clock, → executePrimitive_event_clock, → executeEffectTerm_event_clock, → executeCleanupTerm_event_clock, → executeControlTerm_event_clock, → enterBinding_event_clock, → deliverOperand_event_clock, → leaveInvocation_event_clock, → leaveLexical_event_clock, → restoreResumeCaller_event_clock, → completeHandler_event_clock, → beginCleanup_event_clock, → finishCleanup_event_clock,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem tick_event_clock (state : State) (context : Context) (after : Transition)
    (accepted : tick state context = .ok after) : EventClock state after.state after.events := by
  simp only [tick] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → tickRunning_event_clock,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

theorem external_event_clock (state : State) (context : Context) (action : External) (after : Transition)
    (accepted : external state context action = .ok after) : EventClock state after.state after.events := by
  simp only [external, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → scopedValue_event_clock, → scopedValue_quiet,
    EventClock, requestOccurrences, requestOccurrences_append, requestOccurrences_cleanup,
    List.filterMap_cons, List.filterMap_nil, List.nil_append]

/-- One accepted source transition opens either no request or exactly the next
fresh occurrence, independent of the request's payload and nominal effect. -/
theorem step_event_clock (step : Step context before events after) : EventClock before after events := by
  cases step with
  | internal checked => exact tick_event_clock _ _ _ checked
  | external checked => exact external_event_clock _ _ _ _ checked

/-- A complete finite source trace contains exactly the consecutive allocated
opening identities. Equal payloads do not collapse, and repeated polls do not
invent earlier operations. -/
theorem source_trace_request_occurrences (steps : Steps context before events after) :
    before.nextOccurrence ≤ after.nextOccurrence ∧
      requestOccurrences events = List.range' before.nextOccurrence (after.nextOccurrence - before.nextOccurrence) := by
  induction steps with
  | refl => simp [requestOccurrences]
  | @cons before first middle rest after step _ induction =>
    obtain ⟨monotone, traced⟩ := induction
    rcases step_event_clock step with ⟨same, empty⟩ | ⟨next, opened⟩
    · constructor
      · omega
      · simpa [requestOccurrences_append, empty, same] using traced
    · constructor
      · omega
      · have length : after.nextOccurrence - before.nextOccurrence =
            (after.nextOccurrence - middle.nextOccurrence) + 1 := by omega
        simp only [requestOccurrences_append, opened, List.singleton_append, traced, length, List.range'_succ, next]

theorem source_trace_openings_unique (steps : Steps context before events after) :
    (requestOccurrences events).Nodup := by
  rw [(source_trace_request_occurrences steps).2]
  exact List.nodup_range' 1

end BoundaryV2.Profile.Source.Machine
