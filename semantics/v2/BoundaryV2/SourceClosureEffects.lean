import BoundaryV2.SourceClosureContracts

namespace BoundaryV2.Profile.Source.Machine
namespace ClosureContracts

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem authoredFailure_valid (machine : State) (context : Context) (failures : List (InstructionFailure .source))
    (fault : Fault) (after : Transition) (accepted : authoredFailure machine context failures fault = .ok after)
    (typed : Valid context machine.heap.objects) : Valid context after.state.heap.objects := by
  simp only [authoredFailure, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  exact typed

theorem executePrimitive_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executePrimitive machine context = .ok after) (typed : Valid context machine.heap.objects)
    (contextTyped : context.typingValid = true) : Valid context after.state.heap.objects := by
  unfold executePrimitive at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · contradiction
  · exact authoredFailure_valid _ _ _ _ _ accepted typed
  · exact commitPure_valid _ _ _ _ _ _ accepted typed
  · exact heapPrimitive_valid _ _ _ _ _ _ _ accepted typed contextTyped

theorem createScope_valid (machine : State) (context : Context) (invocation : InvocationId)
    (parent : Option LexicalScopeId) (vars : List VariableId) (values : List Located) (bindings : Environment)
    (after : State) (entered : Environment)
    (accepted : createScope machine context invocation parent vars values bindings = .ok (after, entered))
    (typed : Valid context machine.heap.objects) : Valid context after.heap.objects := by
  simp only [createScope, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · cases accepted; exact typed
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, moved, movedOk, equal⟩ := accepted
    have movedTyped := move_valid _ _ _ _ _ movedOk typed
    cases equal; exact movedTyped

theorem invokeFunction_valid (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction machine context function bindings arguments = .ok after)
    (typed : Valid context machine.heap.objects) : Valid context after.state.heap.objects := by
  simp only [invokeFunction, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, ⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have result := createScope_valid _ _ _ _ _ _ _ _ _ scopeOk typed
  exact result

theorem applyClosure_valid (machine : State) (context : Context) (closure : Located)
    (arguments : List Located) (after : Transition)
    (accepted : applyClosure machine context closure arguments = .ok after)
    (typed : Valid context machine.heap.objects) : Valid context after.state.heap.objects := by
  simp only [applyClosure, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  · simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨store, retired, accepted⟩ := accepted
    exact invokeFunction_valid _ _ _ _ _ _ accepted (retire_valid _ _ _ _ retired typed)
  · simp only [pure, Except.pure, Except.bind] at accepted
    exact invokeFunction_valid _ _ _ _ _ _ accepted typed

theorem enterInvocation_valid (machine : State) (context : Context) (after : Transition)
    (accepted : enterInvocation machine context = .ok after) (typed : Valid context machine.heap.objects) :
    Valid context after.state.heap.objects := by
  unfold enterInvocation at accepted
  split at accepted <;> try contradiction
  exact invokeFunction_valid _ _ _ _ _ _ accepted typed

theorem enterBinding_valid (machine : State) (context : Context) (after : Transition)
    (accepted : enterBinding machine context = .ok after) (typed : Valid context machine.heap.objects) :
    Valid context after.state.heap.objects := by
  unfold enterBinding at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have result := createScope_valid _ _ _ _ _ _ _ _ _ scopeOk typed
  split <;> exact result

theorem enterPattern_valid (machine : State) (context : Context) (vars : List VariableId)
    (parts : List SemanticValue) (owner : Custody.Owner) (body : TermId) (bindings : Environment) (after : Transition)
    (accepted : enterPattern machine context vars parts owner body bindings = .ok after)
    (typed : Valid context machine.heap.objects) : Valid context after.state.heap.objects := by
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have result := createScope_valid _ _ _ _ _ _ _ _ _ scopeOk typed
  split <;> exact result

private theorem mapM_preserves (function : α → Except Invalid β) (property : β → Prop)
    (preserves : ∀ input output, function input = .ok output → property output)
    (inputs : List α) (outputs : List β) (accepted : inputs.mapM function = .ok outputs) :
    ∀ output ∈ outputs, property output := by
  induction inputs generalizing outputs with
  | nil => cases accepted; simp
  | cons head tail induction =>
    simp only [List.mapM_cons, bind, except_bind_ok] at accepted
    obtain ⟨first, firstAt, rest, restAt, accepted⟩ := accepted
    cases accepted
    exact fun value member => (List.mem_cons.mp member).elim
      (fun equal => equal ▸ preserves head first firstAt) (induction rest restAt value)

theorem instantiateCapture_valid (machine : State) (context : Context) (saved : Capture) (after : State × Capture)
    (accepted : instantiateCapture machine context saved = .ok after) (typed : Valid context machine.heap.objects) :
    Valid context after.1.heap.objects := by
  unfold instantiateCapture at accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨objects, objectsAt, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  cases accepted
  have objectsTyped : ∀ entry ∈ objects, ∀ stored ∈ entry, ObjectValid context stored := by
    refine mapM_preserves _ (fun entry : Option Object => ∀ stored ∈ entry, ObjectValid context stored) ?_ _ _ objectsAt
    intro input output checked
    simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at checked
    obtain ⟨stored, looked, rfl⟩ := checked
    have storedTyped := heap_lookup _ _ _ _ looked typed
    intro renamed present
    cases present
    apply rename_object
    cases stored <;> first | exact storedTyped | trivial
  intro entry member value present
  rcases List.mem_append.mp member with old | copied
  · exact typed _ old _ present
  · exact objectsTyped _ copied _ present

theorem takeCapture_valid (machine : State) (context : Context) (token : Located) (after : State × Capture)
    (accepted : takeCapture machine context token = .ok after) (typed : Valid context machine.heap.objects) :
    Valid context after.1.heap.objects := by
  simp only [takeCapture, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨store, retired, rfl⟩ := accepted
    exact retire_valid _ _ _ _ retired typed
  · exact instantiateCapture_valid _ _ _ _ accepted typed

theorem activateCapture_valid (machine : State) (context : Context) (saved : Capture)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : State)
    (accepted : activateCapture machine context saved successor = .ok after) (typed : Valid context machine.heap.objects) :
    Valid context after.heap.objects := by
  simp only [activateCapture, bind, except_bind_ok, pure, Except.pure] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  cases successor with
  | none => cases accepted; exact typed
  | some successor =>
    rcases successor with ⟨handler, stored, bindings⟩
    simp only [except_bind_ok, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, _, rfl, rfl⟩ := accepted
    exact typed

theorem resumeValue_valid (machine : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (accepted : resumeValue machine context token argument successor = .ok after) (typed : Valid context machine.heap.objects) :
    Valid context after.state.heap.objects := by
  simp only [resumeValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, _, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, active, activated, ⟨middle, owner⟩, temporaryOk, store, moved, finished⟩ := accepted
  have first := takeCapture_valid _ _ _ _ captured typed
  have second := activateCapture_valid _ _ _ _ _ activated first
  have third := temporary_valid _ _ _ _ temporaryOk second
  have fourth := move_valid _ _ _ _ _ moved third
  exact finishTemporary_valid _ _ _ _ finished fourth

theorem resumeComputation_valid (machine : State) (context : Context) (token computation : Located) (after : Transition)
    (accepted : resumeComputation machine context token computation = .ok after) (typed : Valid context machine.heap.objects) :
    Valid context after.state.heap.objects := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, active, activated, applied⟩ := accepted
  have first := takeCapture_valid _ _ _ _ captured typed
  have second := activateCapture_valid _ _ _ _ _ activated first
  exact applyClosure_valid _ _ _ _ _ applied second

private theorem foldlM_preserves (items : List β) (step : α → β → Except Invalid α)
    (property : α → Prop) (preserved : ∀ before item after, step before item = .ok after → property before → property after)
    (before after : α) (accepted : items.foldlM step before = .ok after) (holds : property before) : property after := by
  induction items generalizing before with
  | nil => cases accepted; exact holds
  | cons first rest induction =>
    simp only [List.foldlM_cons, bind, except_bind_ok] at accepted
    obtain ⟨middle, stepped, accepted⟩ := accepted
    exact induction middle accepted (preserved before first middle stepped holds)

theorem installHandler_valid (machine : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (bindings : Environment) (after : Transition)
    (accepted : installHandler machine context handler body arguments stored bindings = .ok after)
    (typed : Valid context machine.heap.objects) : Valid context after.state.heap.objects := by
  simp only [installHandler, bind, except_bind_ok] at accepted
  obtain ⟨definition, _, _, _, _, _, _, _, signature, _, _, _, ⟨store, capabilities⟩, allocated, applied⟩ := accepted
  let property (pair : Heap × List Located) : Prop := Valid context pair.1.objects
  have seedTyped : property ({ machine.heap with nextAttachment := machine.heap.nextAttachment + 1 }, []) := typed
  have allTyped := foldlM_preserves _ _ property (by
    intro before item after stepOk beforeTyped
    rcases before with ⟨heap, capabilities⟩
    rcases item with ⟨clause, schema⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at stepOk
    obtain ⟨_, _, ⟨next, value⟩, allocated, rfl⟩ := stepOk
    exact allocate_valid _ _ _ _ _ _ _ _ allocated beforeTyped trivial) _ _ allocated seedTyped
  exact applyClosure_valid _ _ _ _ _ applied allTyped

theorem enterRegion_valid (machine : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition)
    (accepted : enterRegion machine context descriptor body arguments = .ok after)
    (typed : Valid context machine.heap.objects) : Valid context after.state.heap.objects := by
  simp only [enterRegion, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, ⟨store, value⟩, allocated, applied⟩ := accepted
  have allocatedTyped := allocate_valid _ _ _ _ _ _ _ _ allocated typed trivial
  exact applyClosure_valid _ _ _ _ _ applied allocatedTyped

theorem openRequest_valid (machine : State) (context : Context) (operation : Operation)
    (operands : List Located) (after : Transition) (accepted : openRequest machine context operation operands = .ok after)
    (typed : Valid context machine.heap.objects) : Valid context after.state.heap.objects := by
  simp only [openRequest, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, accepted⟩ := accepted
  split at accepted
  · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    exact typed
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, accepted⟩ := accepted
    split at accepted
    · simp only [except_bind_ok] at accepted
      obtain ⟨_, _, _, _, _, _, invoked⟩ := accepted
      exact invokeFunction_valid _ _ _ _ _ _ invoked typed
    · simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      obtain ⟨store, moved, accepted⟩ := (except_bind_ok _ _ _).mp accepted
      have movedTyped := move_valid context _ store _ _ ((fromOption_ok _ _ _).mp moved) typed
      split at accepted
      all_goals
        simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        try
          obtain ⟨gate, guard, rest⟩ := accepted
          have _ : Unit := gate
          clear guard
          have accepted := rest
        obtain ⟨⟨outside, owner⟩, temporaryOk, ⟨allocatedHeap, token⟩, allocated, staged, stagedOk, rfl⟩ := accepted
        have first := temporary_valid _ _ _ _ temporaryOk movedTyped
        have second := allocate_valid _ _ _ _ _ _ _ _ allocated first (by trivial)
        have third := finishTemporary_valid _ _ _ _ stagedOk second
        exact third

theorem installProtection_valid (machine : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (accepted : installProtection machine context body cleanup arguments resource loan = .ok after)
    (typed : Valid context machine.heap.objects) : Valid context after.state.heap.objects := by
  simp only [installProtection, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, store, moved, accepted⟩ := accepted
  have movedTyped := move_valid context _ _ _ _ moved typed
  cases resource <;> cases loan <;> try contradiction
  · simp only [pure, Except.pure, Except.bind] at accepted
    exact applyClosure_valid _ _ _ _ _ accepted movedTyped
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, ⟨allocatedHeap, value⟩, allocated, _, rfl, applied⟩ := accepted
    have allocatedTyped := allocate_valid _ _ _ _ _ _ _ _ allocated movedTyped trivial
    exact applyClosure_valid _ _ _ _ _ applied allocatedTyped

theorem beginCleanup_valid (machine : State) (context : Context) (identity : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (accepted : beginCleanup machine context identity exit normal tail = .ok after)
    (typed : Valid context machine.heap.objects) : Valid context after.state.heap.objects := by
  simp only [beginCleanup, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, applied, rfl⟩ := accepted
  have result := applyClosure_valid _ _ _ _ _ applied typed
  exact result

theorem resumeRelease_valid (context : Context) (machine : State) (after : AfterRelease)
    (typed : Valid context machine.heap.objects) : Valid context (resumeRelease machine after).state.heap.objects := by
  cases after <;> exact typed

theorem finishCleanup_valid (machine : State) (context : Context) (after : Transition)
    (accepted : finishCleanup machine context = .ok after) (typed : Valid context machine.heap.objects) :
    Valid context after.state.heap.objects := by
  unfold finishCleanup at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, rfl⟩ := accepted
  exact resumeRelease_valid _ _ _ typed

theorem discardValues_valid (machine : State) (context : Context) (after : Transition)
    (accepted : discardValues machine context = .ok after) (typed : Valid context machine.heap.objects) :
    Valid context after.state.heap.objects := by
  unfold discardValues at accepted
  split at accepted <;> try contradiction
  split at accepted
  · cases accepted; exact resumeRelease_valid _ _ _ typed
  · split at accepted
    · cases accepted; exact typed
    · simp only [bind, except_bind_ok] at accepted
      obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
      cases stored <;> try contradiction
      all_goals simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
      all_goals obtain ⟨store, retired, rfl⟩ := accepted
      all_goals exact retire_valid _ _ _ _ retired typed

theorem leaveScope_valid (context : Context) (machine : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition)
    (accepted : leaveScope machine parent invocation tail value = .ok after) (typed : Valid context machine.heap.objects) :
    Valid context after.state.heap.objects := by
  simp only [leaveScope, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, store, moved, finished, finishedOk, rfl⟩ := accepted
  have first := temporary_valid _ _ _ _ temporaryOk typed
  have second := move_valid _ _ _ _ _ moved first
  have third := finishTemporary_valid _ _ _ _ finishedOk second
  exact third

theorem restoreResumeCaller_valid (context : Context) (machine : State) (after : Transition)
    (accepted : restoreResumeCaller machine = .ok after) (typed : Valid context machine.heap.objects) :
    Valid context after.state.heap.objects := by
  unfold restoreResumeCaller at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, store, moved, finished⟩ := accepted
  have first := temporary_valid _ _ _ _ temporaryOk typed
  have second := move_valid _ _ _ _ _ moved first
  exact finishTemporary_valid _ _ _ _ finished second
end ClosureContracts
end BoundaryV2.Profile.Source.Machine
