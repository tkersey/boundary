import BoundaryV2.SourceMachine

namespace BoundaryV2.Profile.Source.Machine

/-- Allocation supplies are monotone independently of source typing. Tombstone
replacement, custody transfer, and completed cleanup do not recycle identities. -/
structure Heap.AllocationLE (before after : Heap) : Prop where
  nodes : before.objects.length ≤ after.objects.length
  custody : before.nextCustody ≤ after.nextCustody
  attachments : before.nextAttachment ≤ after.nextAttachment
  regions : before.nextRegion ≤ after.nextRegion
  cells : before.nextCell ≤ after.nextCell
  invocations : before.nextInvocation ≤ after.nextInvocation
  scopes : before.nextScope ≤ after.nextScope
  obligations : before.nextObligation ≤ after.nextObligation
  invocationRows : before.invocations.length ≤ after.invocations.length
  scopeRows : before.scopes.length ≤ after.scopes.length
  obligationRows : before.obligations.length ≤ after.obligations.length

structure AllocationLE (before after : State) : Prop where
  heap : before.heap.AllocationLE after.heap
  occurrences : before.nextOccurrence ≤ after.nextOccurrence

theorem Heap.AllocationLE.refl (heap : Heap) : heap.AllocationLE heap := by
  constructor <;> exact Nat.le_refl _

theorem Heap.AllocationLE.trans {before middle after : Heap} (first : before.AllocationLE middle)
    (second : middle.AllocationLE after) : before.AllocationLE after := by
  cases first; cases second; constructor <;> omega

theorem AllocationLE.refl (state : State) : AllocationLE state state :=
  ⟨.refl _, Nat.le_refl _⟩

theorem AllocationLE.trans (first : AllocationLE before middle)
    (second : AllocationLE middle after) : AllocationLE before after :=
  ⟨first.heap.trans second.heap, Nat.le_trans first.occurrences second.occurrences⟩

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β)
    (result : β) : value.bind next = .ok result ↔
      ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem moveValues_allocation (before after : Heap) (values : List Located)
    (receiver : Nat → Custody.Owner) (accepted : moveValues before values receiver = some after) :
    before.AllocationLE after := by
  simp [moveValues, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  constructor <;> exact Nat.le_refl _

theorem consumeValue_allocation (before after : Heap) (value : Located)
    (accepted : consumeValue before value = some after) : before.AllocationLE after := by
  simp [consumeValue, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  constructor <;> exact Nat.le_refl _

theorem allocateObject_allocation (before after : Heap) (schema : SchemaId .source)
    (object : Object) (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject before schema object owner exclusive = some (after, value)) :
    before.AllocationLE after := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, _⟩ := accepted
    constructor <;> simp
  · obtain ⟨_, _, rfl, _⟩ := accepted
    constructor <;> simp

theorem replaceObject_allocation (before after : Heap) (node : NodeId) (object : Object)
    (accepted : replaceObject before node object = some after) : before.AllocationLE after := by
  unfold replaceObject at accepted
  split at accepted
  · cases accepted; constructor <;> simp
  · contradiction

theorem retireObject_allocation (before after : Heap) (value : Located)
    (accepted : retireObject before value = some after) : before.AllocationLE after := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, Option.bind_eq_some_iff, pure, Option.some.injEq] at accepted
  obtain ⟨_, _, middle, consumed, rfl⟩ := accepted
  have h := consumeValue_allocation _ _ _ consumed
  cases h; constructor <;> simp_all

theorem temporary_allocation (state after : State) (owner : Custody.Owner)
    (accepted : temporary state = .ok (after, owner)) : AllocationLE state after := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  constructor
  · constructor <;> simp
  · exact Nat.le_refl _

theorem finishTemporary_allocation (state : State) (value : Located) (after : Transition)
    (accepted : finishTemporary state value = .ok after) : AllocationLE state after.state := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  cases accepted
  constructor
  · constructor <;> simp [finishValue]
  · exact Nat.le_refl _

theorem scopedValue_allocation (state : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue state value = .ok after) : AllocationLE state after.state := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, first, last⟩ := accepted
  exact (temporary_allocation _ _ _ first).trans (finishTemporary_allocation _ _ _ last)

theorem makeClosureWithValues_allocation (state : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues state context schema function values = .ok after) :
    AllocationLE state after.state := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, ⟨middle, owner⟩, first, heap, moved, ⟨allocated, result⟩, alloc, last⟩ := accepted
  have h1 := temporary_allocation _ _ _ first
  have h2 := moveValues_allocation _ _ _ _ moved
  have h3 := allocateObject_allocation _ _ _ _ _ _ _ alloc
  have h4 := finishTemporary_allocation _ _ _ last
  constructor
  · constructor <;> grind (gen := 32) only [cases AllocationLE, cases Heap.AllocationLE]
  · grind (gen := 32) only [cases AllocationLE, cases Heap.AllocationLE]



theorem makeClosure_allocation (state : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (environment : Environment) (after : Transition)
    (accepted : makeClosure state context schema function environment = .ok after) : AllocationLE state after.state := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  constructor
  · constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → makeClosureWithValues_allocation, cases AllocationLE, cases Heap.AllocationLE]
  · grind (gen := 32) only [except_bind_ok, fromOption_ok, → makeClosureWithValues_allocation, cases AllocationLE, cases Heap.AllocationLE]

theorem enterTerm_allocation (state : State) (source : Module) (after : Transition)
    (accepted : enterTerm state source = .ok after) : AllocationLE state after.state := by
  simp only [enterTerm, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor
  · constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, cases AllocationLE, cases Heap.AllocationLE]
  · grind (gen := 32) only [except_bind_ok, fromOption_ok, cases AllocationLE, cases Heap.AllocationLE]

theorem deliverOperand_allocation (state : State) (after : Transition)
    (accepted : deliverOperand state = .ok after) : AllocationLE state after.state := by
  simp only [deliverOperand, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor
  · constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, cases AllocationLE, cases Heap.AllocationLE]
  · grind (gen := 32) only [except_bind_ok, fromOption_ok, cases AllocationLE, cases Heap.AllocationLE]

theorem authoredFailure_allocation (state : State) (context : Context) (failures : List (InstructionFailure .source)) (fault : Fault) (after : Transition)
    (accepted : authoredFailure state context failures fault = .ok after) : AllocationLE state after.state := by
  simp only [authoredFailure, bind, except_bind_ok, fromOption_ok, pure, Except.pure] at accepted
  constructor
  · constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, cases AllocationLE, cases Heap.AllocationLE]
  · grind (gen := 32) only [except_bind_ok, fromOption_ok, cases AllocationLE, cases Heap.AllocationLE]

theorem enterExpression_allocation (state : State) (context : Context) (after : Transition)
    (accepted : enterExpression state context = .ok after) : AllocationLE state after.state := by
  simp only [enterExpression, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, finishValue] at accepted
  constructor
  · constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → scopedValue_allocation, → makeClosure_allocation, cases AllocationLE, cases Heap.AllocationLE]
  · grind (gen := 32) only [except_bind_ok, fromOption_ok, → scopedValue_allocation, → makeClosure_allocation, cases AllocationLE, cases Heap.AllocationLE]

theorem commitPure_allocation (state : State) (opcode : Opcode) (operands : List Located) (result : SemanticValue) (after : Transition)
    (accepted : commitPure state opcode operands result = .ok after) : AllocationLE state after.state := by
  simp only [commitPure, bind, except_bind_ok] at accepted
  constructor
  · constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → temporary_allocation, → moveValues_allocation, → finishTemporary_allocation, cases AllocationLE, cases Heap.AllocationLE]
  · grind (gen := 32) only [except_bind_ok, fromOption_ok, → temporary_allocation, → moveValues_allocation, → finishTemporary_allocation, cases AllocationLE, cases Heap.AllocationLE]



theorem heapPrimitive_allocation (state : State) (context : Context) (operation : Primitives.GraphOperation)
    (schema : SchemaId .source) (immediate : Nat) (operands : List Located) (after : Transition)
    (accepted : heapPrimitive state context operation schema immediate operands = .ok after) : AllocationLE state after.state := by
  simp only [heapPrimitive, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor
  · constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → makeClosureWithValues_allocation, → temporary_allocation, → moveValues_allocation, → allocateObject_allocation, → finishTemporary_allocation, → scopedValue_allocation, → replaceObject_allocation, → retireObject_allocation, → commitPure_allocation,
      List.length_set, List.length_append, List.length_cons, List.length_nil,
      cases AllocationLE, cases Heap.AllocationLE]
  · grind (gen := 32) only [except_bind_ok, fromOption_ok, → makeClosureWithValues_allocation, → temporary_allocation, → moveValues_allocation, → allocateObject_allocation, → finishTemporary_allocation, → scopedValue_allocation, → replaceObject_allocation, → retireObject_allocation, → commitPure_allocation, cases AllocationLE, cases Heap.AllocationLE]

theorem executePrimitive_allocation (state : State) (context : Context) (after : Transition)
    (accepted : executePrimitive state context = .ok after) : AllocationLE state after.state := by
  simp only [executePrimitive, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor
  · constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → authoredFailure_allocation, → commitPure_allocation, → heapPrimitive_allocation,
      List.length_set, List.length_append, List.length_cons, List.length_nil,
      cases AllocationLE, cases Heap.AllocationLE]
  · grind (gen := 32) only [except_bind_ok, fromOption_ok, → authoredFailure_allocation, → commitPure_allocation, → heapPrimitive_allocation, cases AllocationLE, cases Heap.AllocationLE]

theorem createScope_allocation (state : State) (context : Context) (invocation : InvocationId) (parent : Option LexicalScopeId)
    (vars : List VariableId) (values : List Located) (environment : Environment) (after : State × Environment)
    (accepted : createScope state context invocation parent vars values environment = .ok after) : AllocationLE state after.1 := by
  simp only [createScope, bind, except_bind_ok, pure, Except.pure] at accepted
  constructor
  · constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → moveValues_allocation,
      List.length_set, List.length_append, List.length_cons, List.length_nil,
      cases AllocationLE, cases Heap.AllocationLE]
  · grind (gen := 32) only [except_bind_ok, fromOption_ok, → moveValues_allocation, cases AllocationLE, cases Heap.AllocationLE]

theorem invokeFunction_allocation (state : State) (context : Context) (function : FunctionId .source)
    (environment : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction state context function environment arguments = .ok after) : AllocationLE state after.state := by
  simp only [invokeFunction, bind, except_bind_ok, fromOption_ok, pure, Except.pure] at accepted
  constructor
  · constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → createScope_allocation,
      List.length_set, List.length_append, List.length_cons, List.length_nil,
      cases AllocationLE, cases Heap.AllocationLE]
  · grind (gen := 32) only [except_bind_ok, fromOption_ok, → createScope_allocation, cases AllocationLE, cases Heap.AllocationLE]

theorem applyClosure_allocation (state : State) (context : Context) (closure : Located) (arguments : List Located) (after : Transition)
    (accepted : applyClosure state context closure arguments = .ok after) : AllocationLE state after.state := by
  simp only [applyClosure, bind, except_bind_ok, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor
  · constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → retireObject_allocation, → invokeFunction_allocation,
      List.length_set, List.length_append, List.length_cons, List.length_nil,
      cases AllocationLE, cases Heap.AllocationLE]
  · grind (gen := 32) only [except_bind_ok, fromOption_ok, → retireObject_allocation, → invokeFunction_allocation, cases AllocationLE, cases Heap.AllocationLE]

theorem enterInvocation_allocation (state : State) (context : Context) (after : Transition)
    (accepted : enterInvocation state context = .ok after) : AllocationLE state after.state := by
  simp only [enterInvocation, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor
  · constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → invokeFunction_allocation,
      List.length_set, List.length_append, List.length_cons, List.length_nil,
      cases AllocationLE, cases Heap.AllocationLE]
  · grind (gen := 32) only [except_bind_ok, fromOption_ok, → invokeFunction_allocation, cases AllocationLE, cases Heap.AllocationLE]

theorem enterBinding_allocation (state : State) (context : Context) (after : Transition)
    (accepted : enterBinding state context = .ok after) : AllocationLE state after.state := by
  simp only [enterBinding, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor
  · constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → createScope_allocation,
      List.length_set, List.length_append, List.length_cons, List.length_nil,
      cases AllocationLE, cases Heap.AllocationLE]
  · grind (gen := 32) only [except_bind_ok, fromOption_ok, → createScope_allocation, cases AllocationLE, cases Heap.AllocationLE]

theorem enterPattern_allocation (state : State) (context : Context) (vars : List VariableId) (parts : List SemanticValue)
    (owner : Custody.Owner) (body : TermId) (environment : Environment) (after : Transition)
    (accepted : enterPattern state context vars parts owner body environment = .ok after) : AllocationLE state after.state := by
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure] at accepted
  constructor
  · constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → createScope_allocation,
      List.length_set, List.length_append, List.length_cons, List.length_nil,
      cases AllocationLE, cases Heap.AllocationLE]
  · grind (gen := 32) only [except_bind_ok, fromOption_ok, → createScope_allocation, cases AllocationLE, cases Heap.AllocationLE]

theorem executeControlTerm_allocation (state : State) (context : Context) (after : Transition)
    (accepted : executeControlTerm state context = .ok after) : AllocationLE state after.state := by
  simp only [executeControlTerm, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor
  · constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → applyClosure_allocation, → enterPattern_allocation,
      List.length_set, List.length_append, List.length_cons, List.length_nil,
      cases AllocationLE, cases Heap.AllocationLE]
  · grind (gen := 32) only [except_bind_ok, fromOption_ok, → applyClosure_allocation, → enterPattern_allocation, cases AllocationLE, cases Heap.AllocationLE]

theorem leaveScope_allocation (state : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition)
    (accepted : leaveScope state parent invocation tail value = .ok after) : AllocationLE state after.state := by
  simp only [leaveScope, bind, except_bind_ok, fromOption_ok, pure, Except.pure] at accepted
  constructor
  · constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → temporary_allocation, → moveValues_allocation, → finishTemporary_allocation,
      List.length_set, List.length_append, List.length_cons, List.length_nil,
      cases AllocationLE, cases Heap.AllocationLE]
  · grind (gen := 32) only [except_bind_ok, fromOption_ok, → temporary_allocation, → moveValues_allocation, → finishTemporary_allocation, cases AllocationLE, cases Heap.AllocationLE]

theorem leaveInvocation_allocation (state : State) (after : Transition)
    (accepted : leaveInvocation state = .ok after) : AllocationLE state after.state := by
  simp only [leaveInvocation, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor
  · constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → leaveScope_allocation,
      List.length_set, List.length_append, List.length_cons, List.length_nil,
      cases AllocationLE, cases Heap.AllocationLE]
  · grind (gen := 32) only [except_bind_ok, fromOption_ok, → leaveScope_allocation, cases AllocationLE, cases Heap.AllocationLE]

theorem leaveLexical_allocation (state : State) (after : Transition)
    (accepted : leaveLexical state = .ok after) : AllocationLE state after.state := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, record, _, parent, _, result, departed, remaining⟩ := accepted
  split at remaining <;> try contradiction
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at remaining
  obtain ⟨parentRecord, _, heap, moved, equal⟩ := remaining
  cases equal
  have h1 := leaveScope_allocation _ _ _ _ _ _ departed
  have h2 := moveValues_allocation _ _ _ _ moved
  constructor
  · constructor <;> simp only [List.length_set] <;>
      grind only [cases AllocationLE, cases Heap.AllocationLE]
  · exact h1.occurrences

theorem finishEmptyRelease_allocation (state : State) (after : Transition)
    (accepted : finishEmptyRelease state = .ok after) : AllocationLE state after.state := by
  simp only [finishEmptyRelease, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, resumeRelease] at accepted
  constructor
  · constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok,
      List.length_set, List.length_append, List.length_cons, List.length_nil,
      cases AllocationLE, cases Heap.AllocationLE]
  · grind (gen := 32) only [except_bind_ok, fromOption_ok, cases AllocationLE, cases Heap.AllocationLE]

theorem instantiateCapture_allocation (state : State) (context : Context) (capture : Capture) (after : State × Capture)
    (accepted : instantiateCapture state context capture = .ok after) : AllocationLE state after.1 := by
  unfold instantiateCapture at accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  cases accepted
  constructor
  · constructor <;> simp
  · exact Nat.le_refl _

private theorem foldlM_allocation (items : List β)
    (step : Heap × α → β → Except Invalid (Heap × α))
    (monotone : ∀ before item after, step before item = .ok after → before.1.AllocationLE after.1)
    (before after : Heap × α) (accepted : items.foldlM step before = .ok after) :
    before.1.AllocationLE after.1 := by
  induction items generalizing before with
  | nil => cases accepted; exact .refl _
  | cons item tail induction =>
    rw [List.foldlM_cons] at accepted
    obtain ⟨middle, first, last⟩ := (except_bind_ok _ _ _).mp accepted
    exact (monotone before item middle first).trans (induction middle last)



theorem installHandler_allocation (state : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (environment : Environment) (after : Transition)
    (accepted : installHandler state context handler body arguments stored environment = .ok after) :
    AllocationLE state after.state := by
  simp only [installHandler, bind, except_bind_ok] at accepted
  obtain ⟨definition, _, _, _, _, _, _, _, signature, _, _, _, ⟨heap, capabilities⟩, folded, last⟩ := accepted
  have hfold := foldlM_allocation _ _ (by
    intro before item after checked
    rcases before with ⟨heap, capabilities⟩
    rcases item with ⟨clause, schema⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at checked
    obtain ⟨_, _, ⟨allocated, value⟩, alloc, equal⟩ := checked
    cases equal
    exact allocateObject_allocation _ _ _ _ _ _ _ alloc) _ _ folded
  have hlast := applyClosure_allocation _ _ _ _ _ last
  constructor
  · constructor <;> grind (gen := 32) only [cases AllocationLE, cases Heap.AllocationLE]
  · exact hlast.occurrences



theorem completeHandler_allocation (state : State) (context : Context) (after : Transition)
    (accepted : completeHandler state context = .ok after) : AllocationLE state after.state := by
  simp only [completeHandler, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    List.length_set, List.length_append, List.length_cons, List.length_nil,
    ← AllocationLE.mk, ← Heap.AllocationLE.mk, cases AllocationLE, cases Heap.AllocationLE]

theorem openRequest_allocation (state : State) (context : Context) (operation : Operation) (operands : List Located) (after : Transition)
    (accepted : openRequest state context operation operands = .ok after) : AllocationLE state after.state := by
  simp only [openRequest, bind, except_bind_ok, fromOption_ok, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → invokeFunction_allocation, → moveValues_allocation, → temporary_allocation, → allocateObject_allocation, → finishTemporary_allocation,
    List.length_set, List.length_append, List.length_cons, List.length_nil,
    ← AllocationLE.mk, ← Heap.AllocationLE.mk, cases AllocationLE, cases Heap.AllocationLE]

theorem takeCapture_allocation (state : State) (context : Context) (token : Located) (after : State × Capture)
    (accepted : takeCapture state context token = .ok after) : AllocationLE state after.1 := by
  simp only [takeCapture, bind, except_bind_ok, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → retireObject_allocation, → instantiateCapture_allocation,
    List.length_set, List.length_append, List.length_cons, List.length_nil,
    ← AllocationLE.mk, ← Heap.AllocationLE.mk, cases AllocationLE, cases Heap.AllocationLE]

theorem activateCapture_allocation (state : State) (context : Context) (capture : Capture)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : State)
    (accepted : activateCapture state context capture successor = .ok after) : AllocationLE state after := by
  simp only [activateCapture, bind, except_bind_ok, fromOption_ok, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    List.length_set, List.length_append, List.length_cons, List.length_nil,
    ← AllocationLE.mk, ← Heap.AllocationLE.mk, cases AllocationLE, cases Heap.AllocationLE]

theorem resumeValue_allocation (state : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (accepted : resumeValue state context token argument successor = .ok after) : AllocationLE state after.state := by
  simp only [resumeValue, bind, except_bind_ok, fromOption_ok, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → takeCapture_allocation, → activateCapture_allocation, → temporary_allocation, → moveValues_allocation, → finishTemporary_allocation,
    List.length_set, List.length_append, List.length_cons, List.length_nil,
    ← AllocationLE.mk, ← Heap.AllocationLE.mk, cases AllocationLE, cases Heap.AllocationLE]

theorem resumeComputation_allocation (state : State) (context : Context) (token computation : Located) (after : Transition)
    (accepted : resumeComputation state context token computation = .ok after) : AllocationLE state after.state := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → takeCapture_allocation, → activateCapture_allocation, → applyClosure_allocation,
    List.length_set, List.length_append, List.length_cons, List.length_nil,
    ← AllocationLE.mk, ← Heap.AllocationLE.mk, cases AllocationLE, cases Heap.AllocationLE]

theorem restoreResumeCaller_allocation (state : State) (after : Transition)
    (accepted : restoreResumeCaller state = .ok after) : AllocationLE state after.state := by
  simp only [restoreResumeCaller, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → temporary_allocation, → moveValues_allocation, → finishTemporary_allocation,
    List.length_set, List.length_append, List.length_cons, List.length_nil,
    ← AllocationLE.mk, ← Heap.AllocationLE.mk, cases AllocationLE, cases Heap.AllocationLE]

theorem enterRegion_allocation (state : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition)
    (accepted : enterRegion state context descriptor body arguments = .ok after) : AllocationLE state after.state := by
  simp only [enterRegion, bind, except_bind_ok, fromOption_ok] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → allocateObject_allocation, → applyClosure_allocation,
    List.length_set, List.length_append, List.length_cons, List.length_nil,
    ← AllocationLE.mk, ← Heap.AllocationLE.mk, cases AllocationLE, cases Heap.AllocationLE]

theorem executeEffectTerm_allocation (state : State) (context : Context) (after : Transition)
    (accepted : executeEffectTerm state context = .ok after) : AllocationLE state after.state := by
  simp only [executeEffectTerm, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → openRequest_allocation, → installHandler_allocation, → resumeValue_allocation, → resumeComputation_allocation, → enterRegion_allocation,
    List.length_set, List.length_append, List.length_cons, List.length_nil,
    ← AllocationLE.mk, ← Heap.AllocationLE.mk, cases AllocationLE, cases Heap.AllocationLE]

theorem installProtection_allocation (state : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (accepted : installProtection state context body cleanup arguments resource loan = .ok after) : AllocationLE state after.state := by
  simp only [installProtection, bind, except_bind_ok, fromOption_ok, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → moveValues_allocation, → allocateObject_allocation, → applyClosure_allocation,
    List.length_set, List.length_append, List.length_cons, List.length_nil,
    ← AllocationLE.mk, ← Heap.AllocationLE.mk, cases AllocationLE, cases Heap.AllocationLE]

theorem beginCleanup_allocation (state : State) (context : Context) (identity : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (accepted : beginCleanup state context identity exit normal tail = .ok after) : AllocationLE state after.state := by
  simp only [beginCleanup, bind, except_bind_ok, fromOption_ok, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → applyClosure_allocation,
    List.length_set, List.length_append, List.length_cons, List.length_nil,
    ← AllocationLE.mk, ← Heap.AllocationLE.mk, cases AllocationLE, cases Heap.AllocationLE]

theorem finishCleanup_allocation (state : State) (context : Context) (after : Transition)
    (accepted : finishCleanup state context = .ok after) : AllocationLE state after.state := by
  simp only [finishCleanup, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, resumeRelease] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    List.length_set, List.length_append, List.length_cons, List.length_nil,
    ← AllocationLE.mk, ← Heap.AllocationLE.mk, cases AllocationLE, cases Heap.AllocationLE]

theorem cleanupFailed_allocation (state : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : cleanupFailed state identity invocation outer normal tail inner = .ok after) : AllocationLE state after.state := by
  simp only [cleanupFailed, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    List.length_set, List.length_append, List.length_cons, List.length_nil,
    ← AllocationLE.mk, ← Heap.AllocationLE.mk, cases AllocationLE, cases Heap.AllocationLE]

theorem releaseScope_allocation (state : State) (after : Transition)
    (accepted : releaseScope state = .ok after) : AllocationLE state after.state := by
  simp only [releaseScope, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    List.length_set, List.length_append, List.length_cons, List.length_nil,
    ← AllocationLE.mk, ← Heap.AllocationLE.mk, cases AllocationLE, cases Heap.AllocationLE]

theorem discardValues_allocation (state : State) (context : Context) (after : Transition)
    (accepted : discardValues state context = .ok after) : AllocationLE state after.state := by
  simp only [discardValues, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, resumeRelease] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → retireObject_allocation,
    List.length_set, List.length_append, List.length_cons, List.length_nil,
    ← AllocationLE.mk, ← Heap.AllocationLE.mk, cases AllocationLE, cases Heap.AllocationLE]

theorem unwindStep_allocation (state : State) (context : Context) (after : Transition)
    (accepted : unwindStep state context = .ok after) : AllocationLE state after.state := by
  simp only [unwindStep, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → beginCleanup_allocation, → cleanupFailed_allocation,
    List.length_set, List.length_append, List.length_cons, List.length_nil,
    ← AllocationLE.mk, ← Heap.AllocationLE.mk, cases AllocationLE, cases Heap.AllocationLE]

theorem executeCleanupTerm_allocation (state : State) (context : Context) (after : Transition)
    (accepted : executeCleanupTerm state context = .ok after) : AllocationLE state after.state := by
  simp only [executeCleanupTerm, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → installProtection_allocation, → temporary_allocation,
    List.length_set, List.length_append, List.length_cons, List.length_nil,
    ← AllocationLE.mk, ← Heap.AllocationLE.mk, cases AllocationLE, cases Heap.AllocationLE]

theorem tickRunning_allocation (state : State) (context : Context) (after : Transition)
    (accepted : tickRunning state context = .ok after) : AllocationLE state after.state := by
  simp only [tickRunning, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → enterTerm_allocation, → enterExpression_allocation, → enterInvocation_allocation, → releaseScope_allocation, → discardValues_allocation, → unwindStep_allocation, → executePrimitive_allocation, → executeEffectTerm_allocation, → executeCleanupTerm_allocation, → executeControlTerm_allocation, → enterBinding_allocation, → deliverOperand_allocation, → leaveInvocation_allocation, → leaveLexical_allocation, → restoreResumeCaller_allocation, → completeHandler_allocation, → beginCleanup_allocation, → finishCleanup_allocation,
    List.length_set, List.length_append, List.length_cons, List.length_nil,
    ← AllocationLE.mk, ← Heap.AllocationLE.mk, cases AllocationLE, cases Heap.AllocationLE]

theorem tick_allocation (state : State) (context : Context) (after : Transition)
    (accepted : tick state context = .ok after) : AllocationLE state after.state := by
  simp only [tick] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → tickRunning_allocation,
    List.length_set, List.length_append, List.length_cons, List.length_nil,
    ← AllocationLE.mk, ← Heap.AllocationLE.mk, cases AllocationLE, cases Heap.AllocationLE]

theorem external_allocation (state : State) (context : Context) (action : External) (after : Transition)
    (accepted : external state context action = .ok after) : AllocationLE state after.state := by
  simp only [external, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → scopedValue_allocation,
    List.length_set, List.length_append, List.length_cons, List.length_nil,
    ← AllocationLE.mk, ← Heap.AllocationLE.mk, cases AllocationLE, cases Heap.AllocationLE]

/-- Every actual transition preserves all allocation frontiers, including all
external inputs, suspended cleanup, dormant templates, and malformed inputs
that the transition function accepts. No execution horizon is a premise. -/
theorem step_allocation (step : Step context before events after) : AllocationLE before after := by
  cases step with
  | internal checked => exact tick_allocation _ _ _ checked
  | external checked => exact external_allocation _ _ _ _ checked

theorem steps_allocation (steps : Steps context before events after) : AllocationLE before after := by
  induction steps with
  | refl => exact .refl _
  | cons first _ induction => exact (step_allocation first).trans induction

end BoundaryV2.Profile.Source.Machine
