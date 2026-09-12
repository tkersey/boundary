import BoundaryV2.SourceAllocationLaws

namespace BoundaryV2.Profile.Source.Machine

/-- Every previously allocated obligation remains at the same index and can
only follow the independently defined cleanup lifecycle. -/
def CleanupProgress (before after : List (Cleanup.Obligation .source)) : Prop :=
  ∀ (index : Nat) (obligation : Cleanup.Obligation .source), before[index]? = some obligation →
    ∃ advanced events, after[index]? = some advanced ∧ Cleanup.Path obligation events advanced

theorem CleanupProgress.refl (obligations : List (Cleanup.Obligation .source)) :
    CleanupProgress obligations obligations := by
  intro index obligation found
  exact ⟨obligation, [], found, .nil⟩

private theorem cleanupPath_trans (first : Cleanup.Path before left middle)
    (second : Cleanup.Path middle right after) : Cleanup.Path before (left ++ right) after := by
  induction first with
  | nil => exact second
  | cons step _ induction => simpa [List.append_assoc] using Cleanup.Path.cons step (induction second)

theorem CleanupProgress.trans (first : CleanupProgress before middle)
    (second : CleanupProgress middle after) : CleanupProgress before after := by
  intro index obligation found
  obtain ⟨mid, left, atMid, first⟩ := first index obligation found
  obtain ⟨last, right, atLast, second⟩ := second index mid atMid
  exact ⟨last, left ++ right, atLast, cleanupPath_trans first second⟩

theorem CleanupProgress.append (before added : List (Cleanup.Obligation .source)) :
    CleanupProgress before (before ++ added) := by
  intro index obligation found
  exact ⟨obligation, [], by simpa [List.getElem?_append_left (List.getElem?_eq_some_iff.mp found).1], .nil⟩

theorem CleanupProgress.update (before : List (Cleanup.Obligation .source)) (index : Nat)
    (obligation advanced : Cleanup.Obligation .source) (events : List Cleanup.Event)
    (found : before[index]? = some obligation) (step : Cleanup.Step obligation events advanced) :
    CleanupProgress before (before.set index advanced) := by
  intro other original atOther
  by_cases same : other = index
  · subst other
    have equal : original = obligation := by simpa [found] using atOther.symm
    subst original
    exact ⟨advanced, events, by simp [List.getElem?_eq_some_iff.mp found |>.1],
      by simpa using Cleanup.Path.cons step Cleanup.Path.nil⟩
  · exact ⟨original, [], by simpa [List.getElem?_set, same, Ne.symm same] using atOther, .nil⟩

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β)
    (result : β) : value.bind next = .ok result ↔
      ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem moveValues_cleanup (before after : Heap) (values : List Located)
    (receiver : Nat → Custody.Owner) (accepted : moveValues before values receiver = some after) :
    CleanupProgress before.obligations after.obligations := by
  simp [moveValues, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  exact .refl _

theorem consumeValue_cleanup (before after : Heap) (value : Located)
    (accepted : consumeValue before value = some after) :
    CleanupProgress before.obligations after.obligations := by
  simp [consumeValue, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  exact .refl _

theorem allocateObject_cleanup (before after : Heap) (schema : SchemaId .source)
    (object : Object) (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject before schema object owner exclusive = some (after, value)) :
    CleanupProgress before.obligations after.obligations := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, _⟩ := accepted; exact .refl _
  · obtain ⟨_, _, rfl, _⟩ := accepted; exact .refl _

theorem replaceObject_cleanup (before after : Heap) (node : NodeId) (object : Object)
    (accepted : replaceObject before node object = some after) :
    CleanupProgress before.obligations after.obligations := by
  unfold replaceObject at accepted
  split at accepted
  · cases accepted; exact .refl _
  · contradiction

theorem retireObject_cleanup (before after : Heap) (value : Located)
    (accepted : retireObject before value = some after) :
    CleanupProgress before.obligations after.obligations := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, Option.bind_eq_some_iff, pure, Option.some.injEq] at accepted
  obtain ⟨_, _, middle, consumed, rfl⟩ := accepted
  exact consumeValue_cleanup before middle value consumed



theorem CleanupProgress.append_trans (progress : CleanupProgress (before ++ added) after) :
    CleanupProgress before after := (CleanupProgress.append before added).trans progress

theorem CleanupProgress.begin (before : List (Cleanup.Obligation .source)) (index : Nat)
    (obligation advanced : Cleanup.Obligation .source) (invocation : InvocationId)
    (events : List Cleanup.Event) (found : before[index]? = some obligation)
    (accepted : Cleanup.begin obligation invocation = some (advanced, events)) :
    CleanupProgress before (before.set index advanced) :=
  .update before index obligation advanced events found (.start accepted)

theorem CleanupProgress.complete (before : List (Cleanup.Obligation .source)) (index : Nat)
    (obligation advanced : Cleanup.Obligation .source) (invocation : InvocationId)
    (result : Except SemanticValue Unit) (events : List Cleanup.Event)
    (found : before[index]? = some obligation)
    (accepted : Cleanup.complete obligation invocation result = some (advanced, events)) :
    CleanupProgress before (before.set index advanced) :=
  .update before index obligation advanced events found (.finish accepted)

private theorem foldlM_cleanup (items : List β)
    (step : Heap × α → β → Except Invalid (Heap × α))
    (progress : ∀ before item after, step before item = .ok after →
      CleanupProgress before.1.obligations after.1.obligations)
    (before after : Heap × α) (accepted : items.foldlM step before = .ok after) :
    CleanupProgress before.1.obligations after.1.obligations := by
  induction items generalizing before with
  | nil => cases accepted; exact .refl _
  | cons item tail induction =>
    rw [List.foldlM_cons] at accepted
    obtain ⟨middle, first, last⟩ := (except_bind_ok _ _ _).mp accepted
    exact (progress before item middle first).trans (induction middle last)

theorem temporary_cleanup (state after : State) (owner : Custody.Owner)
    (accepted : temporary state = .ok (after, owner)) : CleanupProgress state.heap.obligations after.heap.obligations := by
  simp only [temporary, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem finishTemporary_cleanup (state : State) (value : Located) (after : Transition)
    (accepted : finishTemporary state value = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [finishTemporary, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, finishValue] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem scopedValue_cleanup (state : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue state value = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → temporary_cleanup, → finishTemporary_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem makeClosureWithValues_cleanup (state : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues state context schema function values = .ok after) :
    CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → temporary_cleanup, → moveValues_cleanup, → allocateObject_cleanup, → finishTemporary_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem makeClosure_cleanup (state : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (environment : Environment) (after : Transition)
    (accepted : makeClosure state context schema function environment = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → makeClosureWithValues_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem enterTerm_cleanup (state : State) (source : Module) (after : Transition)
    (accepted : enterTerm state source = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [enterTerm, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem deliverOperand_cleanup (state : State) (after : Transition)
    (accepted : deliverOperand state = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [deliverOperand, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem authoredFailure_cleanup (state : State) (context : Context) (failures : List (InstructionFailure .source)) (fault : Fault) (after : Transition)
    (accepted : authoredFailure state context failures fault = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [authoredFailure, bind, except_bind_ok, fromOption_ok, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem enterExpression_cleanup (state : State) (context : Context) (after : Transition)
    (accepted : enterExpression state context = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [enterExpression, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, finishValue] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → scopedValue_cleanup, → makeClosure_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem commitPure_cleanup (state : State) (opcode : Opcode) (operands : List Located) (result : SemanticValue) (after : Transition)
    (accepted : commitPure state opcode operands result = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [commitPure, bind, except_bind_ok] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → temporary_cleanup, → moveValues_cleanup, → finishTemporary_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem heapPrimitive_cleanup (state : State) (context : Context) (operation : Primitives.GraphOperation)
    (schema : SchemaId .source) (immediate : Nat) (operands : List Located) (after : Transition)
    (accepted : heapPrimitive state context operation schema immediate operands = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [heapPrimitive, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → makeClosureWithValues_cleanup, → temporary_cleanup, → moveValues_cleanup, → allocateObject_cleanup, → finishTemporary_cleanup, → scopedValue_cleanup, → replaceObject_cleanup, → retireObject_cleanup, → commitPure_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem executePrimitive_cleanup (state : State) (context : Context) (after : Transition)
    (accepted : executePrimitive state context = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [executePrimitive, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → authoredFailure_cleanup, → commitPure_cleanup, → heapPrimitive_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem createScope_cleanup (state : State) (context : Context) (invocation : InvocationId) (parent : Option LexicalScopeId)
    (vars : List VariableId) (values : List Located) (environment : Environment) (after : State × Environment)
    (accepted : createScope state context invocation parent vars values environment = .ok after) : CleanupProgress state.heap.obligations after.1.heap.obligations := by
  simp only [createScope, bind, except_bind_ok, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → moveValues_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem invokeFunction_cleanup (state : State) (context : Context) (function : FunctionId .source)
    (environment : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction state context function environment arguments = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [invokeFunction, bind, except_bind_ok, fromOption_ok, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → createScope_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem applyClosure_cleanup (state : State) (context : Context) (closure : Located) (arguments : List Located) (after : Transition)
    (accepted : applyClosure state context closure arguments = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [applyClosure, bind, except_bind_ok, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → retireObject_cleanup, → invokeFunction_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem enterInvocation_cleanup (state : State) (context : Context) (after : Transition)
    (accepted : enterInvocation state context = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [enterInvocation, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → invokeFunction_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem enterBinding_cleanup (state : State) (context : Context) (after : Transition)
    (accepted : enterBinding state context = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [enterBinding, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → createScope_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem enterPattern_cleanup (state : State) (context : Context) (vars : List VariableId) (parts : List SemanticValue)
    (owner : Custody.Owner) (body : TermId) (environment : Environment) (after : Transition)
    (accepted : enterPattern state context vars parts owner body environment = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → createScope_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem executeControlTerm_cleanup (state : State) (context : Context) (after : Transition)
    (accepted : executeControlTerm state context = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [executeControlTerm, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → applyClosure_cleanup, → enterPattern_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem leaveScope_cleanup (state : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition)
    (accepted : leaveScope state parent invocation tail value = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [leaveScope, bind, except_bind_ok, fromOption_ok, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → temporary_cleanup, → moveValues_cleanup, → finishTemporary_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem leaveInvocation_cleanup (state : State) (after : Transition)
    (accepted : leaveInvocation state = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [leaveInvocation, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → leaveScope_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem leaveLexical_cleanup (state : State) (after : Transition)
    (accepted : leaveLexical state = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, record, _, parent, _, result, departed, remaining⟩ := accepted
  split at remaining <;> try contradiction
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at remaining
  obtain ⟨parentRecord, _, heap, moved, equal⟩ := remaining
  cases equal
  have h1 := leaveScope_cleanup _ _ _ _ _ _ departed
  have h2 := moveValues_cleanup _ _ _ _ moved
  exact h1.trans h2

theorem finishEmptyRelease_cleanup (state : State) (after : Transition)
    (accepted : finishEmptyRelease state = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [finishEmptyRelease, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, resumeRelease] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem instantiateCapture_cleanup (state : State) (context : Context) (capture : Capture) (after : State × Capture)
    (accepted : instantiateCapture state context capture = .ok after) : CleanupProgress state.heap.obligations after.1.heap.obligations := by
  unfold instantiateCapture at accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  cases accepted
  exact .refl _

theorem installHandler_cleanup (state : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (environment : Environment) (after : Transition)
    (accepted : installHandler state context handler body arguments stored environment = .ok after) :
    CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [installHandler, bind, except_bind_ok] at accepted
  obtain ⟨definition, _, _, _, _, _, _, _, signature, _, _, _, ⟨heap, capabilities⟩, folded, last⟩ := accepted
  have hfold := foldlM_cleanup _ _ (by
    intro before item after checked
    rcases before with ⟨heap, capabilities⟩
    rcases item with ⟨clause, schema⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at checked
    obtain ⟨_, _, ⟨allocated, value⟩, alloc, equal⟩ := checked
    cases equal
    exact allocateObject_cleanup _ _ _ _ _ _ _ alloc) _ _ folded
  have hlast := applyClosure_cleanup _ _ _ _ _ last
  exact hfold.trans hlast

theorem completeHandler_cleanup (state : State) (context : Context) (after : Transition)
    (accepted : completeHandler state context = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [completeHandler, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem openRequest_cleanup (state : State) (context : Context) (operation : Operation) (operands : List Located) (after : Transition)
    (accepted : openRequest state context operation operands = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [openRequest, bind, except_bind_ok, fromOption_ok, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → invokeFunction_cleanup, → moveValues_cleanup, → temporary_cleanup, → allocateObject_cleanup, → finishTemporary_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem takeCapture_cleanup (state : State) (context : Context) (token : Located) (after : State × Capture)
    (accepted : takeCapture state context token = .ok after) : CleanupProgress state.heap.obligations after.1.heap.obligations := by
  simp only [takeCapture, bind, except_bind_ok, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → retireObject_cleanup, → instantiateCapture_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem activateCapture_cleanup (state : State) (context : Context) (capture : Capture)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : State)
    (accepted : activateCapture state context capture successor = .ok after) : CleanupProgress state.heap.obligations after.heap.obligations := by
  simp only [activateCapture, bind, except_bind_ok, fromOption_ok, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem resumeValue_cleanup (state : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (accepted : resumeValue state context token argument successor = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [resumeValue, bind, except_bind_ok, fromOption_ok, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → takeCapture_cleanup, → activateCapture_cleanup, → temporary_cleanup, → moveValues_cleanup, → finishTemporary_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem resumeComputation_cleanup (state : State) (context : Context) (token computation : Located) (after : Transition)
    (accepted : resumeComputation state context token computation = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → takeCapture_cleanup, → activateCapture_cleanup, → applyClosure_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem restoreResumeCaller_cleanup (state : State) (after : Transition)
    (accepted : restoreResumeCaller state = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [restoreResumeCaller, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → temporary_cleanup, → moveValues_cleanup, → finishTemporary_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem enterRegion_cleanup (state : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition)
    (accepted : enterRegion state context descriptor body arguments = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [enterRegion, bind, except_bind_ok, fromOption_ok] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → allocateObject_cleanup, → applyClosure_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem executeEffectTerm_cleanup (state : State) (context : Context) (after : Transition)
    (accepted : executeEffectTerm state context = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [executeEffectTerm, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → openRequest_cleanup, → installHandler_cleanup, → resumeValue_cleanup, → resumeComputation_cleanup, → enterRegion_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem installProtection_cleanup (state : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (accepted : installProtection state context body cleanup arguments resource loan = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [installProtection, bind, except_bind_ok, fromOption_ok, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → moveValues_cleanup, → allocateObject_cleanup, → applyClosure_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem beginCleanup_cleanup (state : State) (context : Context) (identity : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (accepted : beginCleanup state context identity exit normal tail = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [beginCleanup, bind, except_bind_ok, fromOption_ok, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → applyClosure_cleanup, → CleanupProgress.begin,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem finishCleanup_cleanup (state : State) (context : Context) (after : Transition)
    (accepted : finishCleanup state context = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [finishCleanup, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, resumeRelease] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → CleanupProgress.complete,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem cleanupFailed_cleanup (state : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : cleanupFailed state identity invocation outer normal tail inner = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [cleanupFailed, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → CleanupProgress.complete,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem cleanupAbandoned_cleanup (state : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : cleanupAbandoned state identity invocation outer normal tail inner = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [cleanupAbandoned, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, before, found, ⟨record, events⟩, completed, rfl⟩ := accepted
  exact CleanupProgress.complete _ _ _ _ _ _ _ found completed


theorem finishCleanupUnwind_cleanup (state : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : finishCleanupUnwind state identity invocation outer normal tail inner = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  unfold finishCleanupUnwind at accepted
  split at accepted <;> first
    | exact cleanupFailed_cleanup _ _ _ _ _ _ _ _ accepted
    | exact cleanupAbandoned_cleanup _ _ _ _ _ _ _ _ accepted
    | contradiction

theorem finishDisposal_cleanup (state : State) (after : Transition)
    (accepted : finishDisposal state = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  unfold finishDisposal at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  exact .refl _

theorem releaseScope_cleanup (state : State) (after : Transition)
    (accepted : releaseScope state = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [releaseScope, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem discardValues_cleanup (state : State) (context : Context) (after : Transition)
    (accepted : discardValues state context = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [discardValues, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, resumeRelease] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → retireObject_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem unwindStep_cleanup (state : State) (context : Context) (after : Transition)
    (accepted : unwindStep state context = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [unwindStep, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → beginCleanup_cleanup, → finishCleanupUnwind_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem executeCleanupTerm_cleanup (state : State) (context : Context) (after : Transition)
    (accepted : executeCleanupTerm state context = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [executeCleanupTerm, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → installProtection_cleanup, → temporary_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem tickRunning_cleanup (state : State) (context : Context) (after : Transition)
    (accepted : tickRunning state context = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [tickRunning, bind, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → enterTerm_cleanup, → enterExpression_cleanup, → enterInvocation_cleanup, → releaseScope_cleanup, → discardValues_cleanup, → unwindStep_cleanup, → executePrimitive_cleanup, → executeEffectTerm_cleanup, → executeCleanupTerm_cleanup, → executeControlTerm_cleanup, → enterBinding_cleanup, → deliverOperand_cleanup, → leaveInvocation_cleanup, → leaveLexical_cleanup, → restoreResumeCaller_cleanup, → completeHandler_cleanup, → beginCleanup_cleanup, → finishCleanup_cleanup, → finishDisposal_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem tick_cleanup (state : State) (context : Context) (after : Transition)
    (accepted : tick state context = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [tick] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → tickRunning_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem external_cleanup (state : State) (context : Context) (action : External) (after : Transition)
    (accepted : external state context action = .ok after) : CleanupProgress state.heap.obligations after.state.heap.obligations := by
  simp only [external, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → scopedValue_cleanup,
    ← CleanupProgress.refl, ← CleanupProgress.append,
    → CleanupProgress.append_trans, → CleanupProgress.trans]

theorem step_cleanup (step : Step context before events after) :
    CleanupProgress before.heap.obligations after.heap.obligations := by
  cases step with
  | internal checked => exact tick_cleanup _ _ _ checked
  | external checked => exact external_cleanup _ _ _ _ checked

theorem steps_cleanup (steps : Steps context before events after) :
    CleanupProgress before.heap.obligations after.heap.obligations := by
  induction steps with
  | refl => exact .refl _
  | cons first _ induction => exact (step_cleanup first).trans induction



private theorem cleanupStep_record (step : Cleanup.Step before events after) :
    after.id = before.id ∧ after.scope = before.scope ∧ after.creation = before.creation ∧
      after.cleanup = before.cleanup ∧ after.resource = before.resource := by
  cases step with
  | start accepted =>
    unfold Cleanup.begin at accepted
    split at accepted <;> try contradiction
    cases accepted
    exact ⟨rfl, rfl, rfl, rfl, rfl⟩
  | finish accepted =>
    unfold Cleanup.complete at accepted
    split at accepted <;> try contradiction
    split at accepted <;> try contradiction
    split at accepted
    all_goals cases accepted; exact ⟨rfl, rfl, rfl, rfl, rfl⟩
  | suspended => exact ⟨rfl, rfl, rfl, rfl, rfl⟩

private theorem cleanupPath_record (path : Cleanup.Path before events after) :
    after.id = before.id ∧ after.scope = before.scope ∧ after.creation = before.creation ∧
      after.cleanup = before.cleanup ∧ after.resource = before.resource := by
  induction path with
  | nil => exact ⟨rfl, rfl, rfl, rfl, rfl⟩
  | cons step _ induction =>
    obtain ⟨a, b, c, d, e⟩ := cleanupStep_record step
    obtain ⟨f, g, h, i, j⟩ := induction
    exact ⟨f.trans a, g.trans b, h.trans c, i.trans d, j.trans e⟩

/-- Existing obligations cannot disappear, change identity, change lexical
owner/order, or replace their cleanup and protected resource during a run. -/
theorem steps_retain_obligation_record (steps : Steps context before events after)
    (index : Nat) (obligation : Cleanup.Obligation .source)
    (found : before.heap.obligations[index]? = some obligation) :
    ∃ advanced, after.heap.obligations[index]? = some advanced ∧
      advanced.id = obligation.id ∧ advanced.scope = obligation.scope ∧
      advanced.creation = obligation.creation ∧ advanced.cleanup = obligation.cleanup ∧
      advanced.resource = obligation.resource := by
  obtain ⟨advanced, _, atAfter, path⟩ := steps_cleanup steps index obligation found
  exact ⟨advanced, atAfter, cleanupPath_record path⟩

/-- This is a trajectory of the full source machine, including arbitrary
external responses and cancellation, rather than a standalone cleanup path. -/
theorem source_trajectory_cannot_restart_cleanup (steps : Steps context before events after)
    (index : Nat) (obligation : Cleanup.Obligation .source)
    (found : before.heap.obligations[index]? = some obligation)
    (started : 0 < obligation.phase.rank) (invocation : InvocationId) :
    ∃ advanced, after.heap.obligations[index]? = some advanced ∧ Cleanup.begin advanced invocation = none := by
  obtain ⟨advanced, _, atAfter, path⟩ := steps_cleanup steps index obligation found
  have rank := Cleanup.path_rank_monotone path
  exact ⟨advanced, atAfter, Cleanup.start_requires_zero_rank _ _ (by omega)⟩

theorem source_trajectory_cannot_complete_cleanup_twice (steps : Steps context before events after)
    (index : Nat) (obligation : Cleanup.Obligation .source)
    (found : before.heap.obligations[index]? = some obligation)
    (terminal : obligation.phase.rank = 2) (invocation : InvocationId)
    (result : Except SemanticValue Unit) :
    ∃ advanced, after.heap.obligations[index]? = some advanced ∧ Cleanup.complete advanced invocation result = none := by
  obtain ⟨advanced, _, atAfter, path⟩ := steps_cleanup steps index obligation found
  have rank := Cleanup.path_rank_monotone path
  have upper : advanced.phase.rank ≤ 2 := by cases advanced.phase <;> simp [Cleanup.Phase.rank]
  exact ⟨advanced, atAfter, Cleanup.terminal_cleanup_cannot_complete_again _ _ _ (by omega)⟩

end BoundaryV2.Profile.Source.Machine
