import BoundaryV2.SourceObligationLaws
import BoundaryV2.SourcePrimitiveLinearity

namespace BoundaryV2.Profile.Source.Machine
namespace ProtectionLinearity

def Linear (record : Cleanup.Obligation .source) : Prop :=
  (ownedTokens record.cleanup ++ record.resource.toList.flatMap ownedTokens).Nodup

def All (records : List (Cleanup.Obligation .source)) : Prop := ∀ record ∈ records, Linear record

def Preserves (before after : List (Cleanup.Obligation .source)) : Prop := All before → All after

theorem Preserves.refl (records : List (Cleanup.Obligation .source)) : Preserves records records := fun formed => formed

theorem Preserves.trans (first : Preserves before middle) (second : Preserves middle after) : Preserves before after :=
  fun formed => second (first formed)

theorem Preserves.append (before added : List (Cleanup.Obligation .source)) (linear : All added) :
    Preserves before (before ++ added) := by
  intro formed record member
  rcases List.mem_append.mp member with old | new
  · exact formed record old
  · exact linear record new

private theorem cleanup_step_linear (step : Cleanup.Step before events after) (formed : Linear before) : Linear after := by
  cases step with
  | start accepted =>
    unfold Cleanup.begin at accepted
    split at accepted <;> try contradiction
    cases accepted
    exact formed
  | finish accepted =>
    unfold Cleanup.complete at accepted
    split at accepted <;> try contradiction
    split at accepted <;> try contradiction
    split at accepted
    all_goals cases accepted; exact formed
  | suspended => exact formed

theorem Preserves.update (before : List (Cleanup.Obligation .source)) (index : Nat)
    (obligation advanced : Cleanup.Obligation .source) (events : List Cleanup.Event)
    (found : before[index]? = some obligation) (step : Cleanup.Step obligation events advanced) :
    Preserves before (before.set index advanced) := by
  intro formed record member
  rcases List.mem_or_eq_of_mem_set member with old | rfl
  · exact formed record old
  · exact cleanup_step_linear step (formed obligation (List.mem_of_getElem? found))

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem moveValues_cleanup (before after : Heap) (values : List Located)
    (receiver : Nat → Custody.Owner) (accepted : moveValues before values receiver = some after) :
    Preserves before.obligations after.obligations := by
  simp [moveValues, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  exact .refl _

theorem consumeValue_cleanup (before after : Heap) (value : Located)
    (accepted : consumeValue before value = some after) :
    Preserves before.obligations after.obligations := by
  simp [consumeValue, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  exact .refl _

theorem allocateObject_cleanup (before after : Heap) (schema : SchemaId .source)
    (object : Object) (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject before schema object owner exclusive = some (after, value)) :
    Preserves before.obligations after.obligations := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, _⟩ := accepted; exact .refl _
  · obtain ⟨_, _, rfl, _⟩ := accepted; exact .refl _

theorem replaceObject_cleanup (before after : Heap) (node : NodeId) (object : Object)
    (accepted : replaceObject before node object = some after) :
    Preserves before.obligations after.obligations := by
  unfold replaceObject at accepted
  split at accepted
  · cases accepted; exact .refl _
  · contradiction

theorem retireObject_cleanup (before after : Heap) (value : Located)
    (accepted : retireObject before value = some after) :
    Preserves before.obligations after.obligations := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, Option.bind_eq_some_iff, pure, Option.some.injEq] at accepted
  obtain ⟨_, _, middle, consumed, rfl⟩ := accepted
  exact consumeValue_cleanup before middle value consumed



theorem Preserves.begin (before : List (Cleanup.Obligation .source)) (index : Nat)
    (obligation advanced : Cleanup.Obligation .source) (invocation : InvocationId)
    (events : List Cleanup.Event) (found : before[index]? = some obligation)
    (accepted : Cleanup.begin obligation invocation = some (advanced, events)) :
    Preserves before (before.set index advanced) :=
  .update before index obligation advanced events found (.start accepted)

theorem Preserves.complete (before : List (Cleanup.Obligation .source)) (index : Nat)
    (obligation advanced : Cleanup.Obligation .source) (invocation : InvocationId)
    (result : Except SemanticValue Unit) (events : List Cleanup.Event)
    (found : before[index]? = some obligation)
    (accepted : Cleanup.complete obligation invocation result = some (advanced, events)) :
    Preserves before (before.set index advanced) :=
  .update before index obligation advanced events found (.finish accepted)

private theorem foldlM_cleanup (items : List β)
    (step : Heap × α → β → Except Invalid (Heap × α))
    (progress : ∀ before item after, step before item = .ok after →
      Preserves before.1.obligations after.1.obligations)
    (before after : Heap × α) (accepted : items.foldlM step before = .ok after) :
    Preserves before.1.obligations after.1.obligations := by
  induction items generalizing before with
  | nil => cases accepted; exact .refl _
  | cons item tail induction =>
    rw [List.foldlM_cons] at accepted
    obtain ⟨middle, first, last⟩ := (except_bind_ok _ _ _).mp accepted
    exact (progress before item middle first).trans (induction middle last)

theorem temporary_cleanup (state after : State) (owner : Custody.Owner)
    (accepted : temporary state = .ok (after, owner)) : Preserves state.heap.obligations after.heap.obligations := by
  simp only [temporary, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    ← Preserves.refl,
    → Preserves.trans]

theorem finishTemporary_cleanup (state : State) (value : Located) (after : Transition)
    (accepted : finishTemporary state value = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [finishTemporary, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, finishValue] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    ← Preserves.refl,
    → Preserves.trans]

theorem scopedValue_cleanup (state : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue state value = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → temporary_cleanup, → finishTemporary_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem makeClosureWithValues_cleanup (state : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues state context schema function values = .ok after) :
    Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → temporary_cleanup, → moveValues_cleanup, → allocateObject_cleanup, → finishTemporary_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem makeClosure_cleanup (state : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (environment : Environment) (after : Transition)
    (accepted : makeClosure state context schema function environment = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → makeClosureWithValues_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem enterTerm_cleanup (state : State) (source : Module) (after : Transition)
    (accepted : enterTerm state source = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [enterTerm, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    ← Preserves.refl,
    → Preserves.trans]

theorem deliverOperand_cleanup (state : State) (after : Transition)
    (accepted : deliverOperand state = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [deliverOperand, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    ← Preserves.refl,
    → Preserves.trans]

theorem authoredFailure_cleanup (state : State) (context : Context) (failures : List (InstructionFailure .source)) (fault : Fault) (after : Transition)
    (accepted : authoredFailure state context failures fault = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [authoredFailure, bind, except_bind_ok, fromOption_ok, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    ← Preserves.refl,
    → Preserves.trans]

theorem enterExpression_cleanup (state : State) (context : Context) (after : Transition)
    (accepted : enterExpression state context = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [enterExpression, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, finishValue] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → scopedValue_cleanup, → makeClosure_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem commitPure_cleanup (state : State) (opcode : Opcode) (operands : List Located) (result : SemanticValue) (after : Transition)
    (accepted : commitPure state opcode operands result = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [commitPure, bind, except_bind_ok] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → temporary_cleanup, → moveValues_cleanup, → finishTemporary_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem heapPrimitive_cleanup (state : State) (context : Context) (operation : Primitives.GraphOperation)
    (schema : SchemaId .source) (immediate : Nat) (operands : List Located) (after : Transition)
    (accepted : heapPrimitive state context operation schema immediate operands = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [heapPrimitive, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → makeClosureWithValues_cleanup, → temporary_cleanup, → moveValues_cleanup, → allocateObject_cleanup, → finishTemporary_cleanup, → scopedValue_cleanup, → replaceObject_cleanup, → retireObject_cleanup, → commitPure_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem executePrimitive_cleanup (state : State) (context : Context) (after : Transition)
    (accepted : executePrimitive state context = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [executePrimitive, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → authoredFailure_cleanup, → commitPure_cleanup, → heapPrimitive_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem createScope_cleanup (state : State) (context : Context) (invocation : InvocationId) (parent : Option LexicalScopeId)
    (vars : List VariableId) (values : List Located) (environment : Environment) (after : State × Environment)
    (accepted : createScope state context invocation parent vars values environment = .ok after) : Preserves state.heap.obligations after.1.heap.obligations := by
  simp only [createScope, bind, except_bind_ok, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → moveValues_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem invokeFunction_cleanup (state : State) (context : Context) (function : FunctionId .source)
    (environment : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction state context function environment arguments = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [invokeFunction, bind, except_bind_ok, fromOption_ok, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → createScope_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem applyClosure_cleanup (state : State) (context : Context) (closure : Located) (arguments : List Located) (after : Transition)
    (accepted : applyClosure state context closure arguments = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [applyClosure, bind, except_bind_ok, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → retireObject_cleanup, → invokeFunction_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem enterInvocation_cleanup (state : State) (context : Context) (after : Transition)
    (accepted : enterInvocation state context = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [enterInvocation, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → invokeFunction_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem enterBinding_cleanup (state : State) (context : Context) (after : Transition)
    (accepted : enterBinding state context = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [enterBinding, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → createScope_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem enterPattern_cleanup (state : State) (context : Context) (vars : List VariableId) (parts : List SemanticValue)
    (owner : Custody.Owner) (body : TermId) (environment : Environment) (after : Transition)
    (accepted : enterPattern state context vars parts owner body environment = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → createScope_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem executeControlTerm_cleanup (state : State) (context : Context) (after : Transition)
    (accepted : executeControlTerm state context = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [executeControlTerm, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → applyClosure_cleanup, → enterPattern_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem leaveScope_cleanup (state : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition)
    (accepted : leaveScope state parent invocation tail value = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [leaveScope, bind, except_bind_ok, fromOption_ok, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → temporary_cleanup, → moveValues_cleanup, → finishTemporary_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem leaveInvocation_cleanup (state : State) (after : Transition)
    (accepted : leaveInvocation state = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [leaveInvocation, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → leaveScope_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem leaveLexical_cleanup (state : State) (after : Transition)
    (accepted : leaveLexical state = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
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
    (accepted : finishEmptyRelease state = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [finishEmptyRelease, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, resumeRelease] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    ← Preserves.refl,
    → Preserves.trans]

theorem instantiateCapture_cleanup (state : State) (context : Context) (capture : Capture) (after : State × Capture)
    (accepted : instantiateCapture state context capture = .ok after) : Preserves state.heap.obligations after.1.heap.obligations := by
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
    Preserves state.heap.obligations after.state.heap.obligations := by
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
    (accepted : completeHandler state context = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [completeHandler, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    ← Preserves.refl,
    → Preserves.trans]

theorem openRequest_cleanup (state : State) (context : Context) (operation : Operation) (operands : List Located) (after : Transition)
    (accepted : openRequest state context operation operands = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [openRequest, bind, except_bind_ok, fromOption_ok, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → invokeFunction_cleanup, → moveValues_cleanup, → temporary_cleanup, → allocateObject_cleanup, → finishTemporary_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem takeCapture_cleanup (state : State) (context : Context) (token : Located) (after : State × Capture)
    (accepted : takeCapture state context token = .ok after) : Preserves state.heap.obligations after.1.heap.obligations := by
  simp only [takeCapture, bind, except_bind_ok, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → retireObject_cleanup, → instantiateCapture_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem activateCapture_cleanup (state : State) (context : Context) (capture : Capture)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : State)
    (accepted : activateCapture state context capture successor = .ok after) : Preserves state.heap.obligations after.heap.obligations := by
  simp only [activateCapture, bind, except_bind_ok, fromOption_ok, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    ← Preserves.refl,
    → Preserves.trans]

theorem resumeValue_cleanup (state : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (accepted : resumeValue state context token argument successor = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [resumeValue, bind, except_bind_ok, fromOption_ok, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → takeCapture_cleanup, → activateCapture_cleanup, → temporary_cleanup, → moveValues_cleanup, → finishTemporary_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem resumeComputation_cleanup (state : State) (context : Context) (token computation : Located) (after : Transition)
    (accepted : resumeComputation state context token computation = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → takeCapture_cleanup, → activateCapture_cleanup, → applyClosure_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem restoreResumeCaller_cleanup (state : State) (after : Transition)
    (accepted : restoreResumeCaller state = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [restoreResumeCaller, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → temporary_cleanup, → moveValues_cleanup, → finishTemporary_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem enterRegion_cleanup (state : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition)
    (accepted : enterRegion state context descriptor body arguments = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [enterRegion, bind, except_bind_ok, fromOption_ok] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → allocateObject_cleanup, → applyClosure_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem executeEffectTerm_cleanup (state : State) (context : Context) (after : Transition)
    (accepted : executeEffectTerm state context = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [executeEffectTerm, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → openRequest_cleanup, → installHandler_cleanup, → resumeValue_cleanup, → resumeComputation_cleanup, → enterRegion_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

end ProtectionLinearity
end BoundaryV2.Profile.Source.Machine
