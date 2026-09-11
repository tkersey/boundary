import BoundaryV2.SourceRequestLaws
import BoundaryV2.SourceCloneSafety

namespace BoundaryV2.Profile.Source.Machine

/-- Every live custody entry refers to an allocated token and physical object.
This does not assert that all value locators agree with the book. -/
structure CustodyBounds (book : Custody.Book) (nextCustody objectCount : Nat) : Prop where
  tokens : ∀ entry ∈ book.entries, entry.token.value < nextCustody
  objects : ∀ entry ∈ book.entries, entry.object.value < objectCount

abbrev Heap.CustodyBounded (heap : Heap) : Prop :=
  CustodyBounds heap.custody heap.nextCustody heap.objects.length

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β)
    (result : β) : value.bind next = .ok result ↔
      ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem Heap.CustodyBounded.mono (before after : Heap) (bounded : before.CustodyBounded)
    (same : after.custody = before.custody) (tokens : before.nextCustody ≤ after.nextCustody)
    (objects : before.objects.length ≤ after.objects.length) : after.CustodyBounded := by
  constructor
  · intro entry member
    exact Nat.lt_of_lt_of_le (bounded.tokens entry (same ▸ member)) tokens
  · intro entry member
    exact Nat.lt_of_lt_of_le (bounded.objects entry (same ▸ member)) objects

theorem commitBook_custody_bounded (before : Heap) (moves : List Custody.Move) (book : Custody.Book)
    (accepted : Custody.commit before.custody moves = some book) (bounded : before.CustodyBounded) :
    ({ before with custody := book } : Heap).CustodyBounded := by
  unfold Custody.commit at accepted
  split at accepted <;> try contradiction
  cases accepted
  constructor
  · intro entry member
    obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
    simpa [Custody.destination_token] using bounded.tokens original originalMember
  · intro entry member
    obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
    simpa [Custody.destination_object] using bounded.objects original originalMember

theorem consumeBook_custody_bounded (before : Heap) (tokens : List CustodyToken) (owner : Custody.Owner)
    (book : Custody.Book) (accepted : Custody.consume before.custody tokens owner = some book)
    (bounded : before.CustodyBounded) : ({ before with custody := book } : Heap).CustodyBounded := by
  unfold Custody.consume at accepted
  split at accepted <;> try contradiction
  cases accepted
  constructor
  · intro entry member
    exact bounded.tokens entry (List.mem_filter.mp member).1
  · intro entry member
    exact bounded.objects entry (List.mem_filter.mp member).1

theorem moveValues_custody_bounded (before after : Heap) (values : List Located)
    (receiver : Nat → Custody.Owner) (accepted : moveValues before values receiver = some after)
    (bounded : before.CustodyBounded) : after.CustodyBounded := by
  simp [moveValues, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, committed, rfl⟩ := accepted
  exact commitBook_custody_bounded _ _ _ committed bounded

theorem consumeValue_custody_bounded (before after : Heap) (value : Located)
    (accepted : consumeValue before value = some after) (bounded : before.CustodyBounded) :
    after.CustodyBounded := by
  simp [consumeValue, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, consumed, rfl⟩ := accepted
  exact consumeBook_custody_bounded _ _ _ _ consumed bounded

theorem allocateObject_custody_bounded (before after : Heap) (schema : SchemaId .source)
    (object : Object) (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject before schema object owner exclusive = some (after, value))
    (bounded : before.CustodyBounded) : after.CustodyBounded := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, _⟩ := accepted
    refine Heap.CustodyBounded.mono before _ bounded ?_ ?_ ?_ <;> simp
  · obtain ⟨book, allocated, rfl, _⟩ := accepted
    have entries := (Custody.allocation_is_fresh _ _ _ _ _ allocated).2.2
    constructor
    · intro entry member
      rw [entries] at member
      rcases List.mem_cons.mp member with rfl | member
      · exact Nat.lt_succ_self _
      · exact Nat.lt_succ_of_lt (bounded.tokens entry member)
    · intro entry member
      rw [entries] at member
      simp only [List.length_append, List.length_cons, List.length_nil, Nat.zero_add]
      rcases List.mem_cons.mp member with rfl | member
      · exact Nat.lt_succ_self _
      · exact Nat.lt_succ_of_lt (bounded.objects entry member)

theorem replaceObject_custody_bounded (before after : Heap) (node : NodeId) (object : Object)
    (accepted : replaceObject before node object = some after) (bounded : before.CustodyBounded) :
    after.CustodyBounded := by
  unfold replaceObject at accepted
  split at accepted <;> try contradiction
  cases accepted
  refine Heap.CustodyBounded.mono before _ bounded ?_ ?_ ?_ <;> simp

theorem retireObject_custody_bounded (before after : Heap) (value : Located)
    (accepted : retireObject before value = some after) (bounded : before.CustodyBounded) :
    after.CustodyBounded := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, Option.bind_eq_some_iff, pure, Option.some.injEq] at accepted
  obtain ⟨_, _, middle, consumed, rfl⟩ := accepted
  have preserved := consumeValue_custody_bounded _ _ _ consumed bounded
  refine Heap.CustodyBounded.mono middle _ preserved ?_ ?_ ?_ <;> simp

theorem temporary_custody_bounded (state after : State) (owner : Custody.Owner)
    (accepted : temporary state = .ok (after, owner)) (bounded : state.heap.CustodyBounded) : after.heap.CustodyBounded := by
  simp only [temporary, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem finishTemporary_custody_bounded (state : State) (value : Located) (after : Transition)
    (accepted : finishTemporary state value = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [finishTemporary, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, finishValue] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem scopedValue_custody_bounded (state : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue state value = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [scopedValue, bind] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → finishTemporary_custody_bounded, → temporary_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem makeClosureWithValues_custody_bounded (state : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues state context schema function values = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [makeClosureWithValues, bind] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → temporary_custody_bounded, → finishTemporary_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem makeClosure_custody_bounded (state : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (environment : Environment) (after : Transition)
    (accepted : makeClosure state context schema function environment = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [makeClosure, bind] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → makeClosureWithValues_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem enterTerm_custody_bounded (state : State) (source : Module) (after : Transition)
    (accepted : enterTerm state source = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [enterTerm, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem deliverOperand_custody_bounded (state : State) (after : Transition)
    (accepted : deliverOperand state = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [deliverOperand, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem authoredFailure_custody_bounded (state : State) (context : Context) (failures : List (InstructionFailure .source)) (fault : Fault) (after : Transition)
    (accepted : authoredFailure state context failures fault = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [authoredFailure, bind, pure, Except.pure] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem enterExpression_custody_bounded (state : State) (context : Context) (after : Transition)
    (accepted : enterExpression state context = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [enterExpression, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, finishValue] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → scopedValue_custody_bounded, → makeClosure_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem commitPure_custody_bounded (state : State) (opcode : Opcode) (operands : List Located) (result : SemanticValue) (after : Transition)
    (accepted : commitPure state opcode operands result = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [commitPure, bind] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → temporary_custody_bounded, → finishTemporary_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem heapPrimitive_custody_bounded (state : State) (context : Context) (operation : Primitives.GraphOperation)
    (schema : SchemaId .source) (immediate : Nat) (operands : List Located) (after : Transition)
    (accepted : heapPrimitive state context operation schema immediate operands = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [heapPrimitive, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → makeClosureWithValues_custody_bounded, → temporary_custody_bounded, → finishTemporary_custody_bounded, → scopedValue_custody_bounded, → commitPure_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem executePrimitive_custody_bounded (state : State) (context : Context) (after : Transition)
    (accepted : executePrimitive state context = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [executePrimitive, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → authoredFailure_custody_bounded, → commitPure_custody_bounded, → heapPrimitive_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem createScope_custody_bounded (state : State) (context : Context) (invocation : InvocationId) (parent : Option LexicalScopeId)
    (vars : List VariableId) (values : List Located) (environment : Environment) (after : State × Environment)
    (accepted : createScope state context invocation parent vars values environment = .ok after) (bounded : state.heap.CustodyBounded) : after.1.heap.CustodyBounded := by
  simp only [createScope, bind, pure, Except.pure] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem invokeFunction_custody_bounded (state : State) (context : Context) (function : FunctionId .source)
    (environment : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction state context function environment arguments = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [invokeFunction, bind, pure, Except.pure] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → createScope_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem applyClosure_custody_bounded (state : State) (context : Context) (closure : Located) (arguments : List Located) (after : Transition)
    (accepted : applyClosure state context closure arguments = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [applyClosure, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → invokeFunction_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem enterInvocation_custody_bounded (state : State) (context : Context) (after : Transition)
    (accepted : enterInvocation state context = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [enterInvocation, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → invokeFunction_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem enterBinding_custody_bounded (state : State) (context : Context) (after : Transition)
    (accepted : enterBinding state context = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [enterBinding, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → createScope_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem enterPattern_custody_bounded (state : State) (context : Context) (vars : List VariableId) (parts : List SemanticValue)
    (owner : Custody.Owner) (body : TermId) (environment : Environment) (after : Transition)
    (accepted : enterPattern state context vars parts owner body environment = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [enterPattern, bind, pure, Except.pure] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → createScope_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem executeControlTerm_custody_bounded (state : State) (context : Context) (after : Transition)
    (accepted : executeControlTerm state context = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [executeControlTerm, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → applyClosure_custody_bounded, → enterPattern_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem leaveScope_custody_bounded (state : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition)
    (accepted : leaveScope state parent invocation tail value = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [leaveScope, bind, pure, Except.pure] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → temporary_custody_bounded, → finishTemporary_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem leaveInvocation_custody_bounded (state : State) (after : Transition)
    (accepted : leaveInvocation state = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [leaveInvocation, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → leaveScope_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem finishEmptyRelease_custody_bounded (state : State) (after : Transition)
    (accepted : finishEmptyRelease state = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [finishEmptyRelease, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, resumeRelease] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem instantiateCapture_custody_bounded (state : State) (context : Context) (capture : Capture) (after : State × Capture)
    (accepted : instantiateCapture state context capture = .ok after) (bounded : state.heap.CustodyBounded) :
    after.1.heap.CustodyBounded := by
  have growth := instantiateCapture_allocation state context capture after accepted
  exact Heap.CustodyBounded.mono state.heap after.1.heap bounded
    (instantiate_preserves_custody state after.1 context capture after.2 accepted)
    growth.heap.custody growth.heap.nodes

theorem leaveLexical_custody_bounded (state : State) (after : Transition)
    (accepted : leaveLexical state = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, record, _, parent, _, result, departed, remaining⟩ := accepted
  split at remaining <;> try contradiction
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at remaining
  obtain ⟨parentRecord, _, heap, moved, equal⟩ := remaining
  cases equal
  have preserved := moveValues_custody_bounded _ _ _ _ moved (leaveScope_custody_bounded _ _ _ _ _ _ departed bounded)
  exact preserved

private theorem foldlM_custody_bounded (items : List β)
    (step : Heap × α → β → Except Invalid (Heap × α))
    (preserves : ∀ before item after, step before item = .ok after → before.1.CustodyBounded → after.1.CustodyBounded)
    (before after : Heap × α) (accepted : items.foldlM step before = .ok after) (bounded : before.1.CustodyBounded) :
    after.1.CustodyBounded := by
  induction items generalizing before with
  | nil => cases accepted; exact bounded
  | cons item tail induction =>
    rw [List.foldlM_cons] at accepted
    obtain ⟨middle, first, last⟩ := (except_bind_ok _ _ _).mp accepted
    exact induction middle last (preserves before item middle first bounded)

theorem installHandler_custody_bounded (state : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (environment : Environment) (after : Transition)
    (accepted : installHandler state context handler body arguments stored environment = .ok after)
    (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [installHandler, bind, except_bind_ok] at accepted
  obtain ⟨definition, _, _, _, _, _, _, _, signature, _, _, _, ⟨heap, capabilities⟩, folded, last⟩ := accepted
  have seed : ({ state.heap with nextAttachment := state.heap.nextAttachment + 1 } : Heap).CustodyBounded := bounded
  have preserved := foldlM_custody_bounded _ _ (by
    intro before item after checked current
    rcases before with ⟨heap, capabilities⟩
    rcases item with ⟨clause, schema⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at checked
    obtain ⟨_, _, ⟨allocated, value⟩, alloc, equal⟩ := checked
    cases equal
    exact allocateObject_custody_bounded _ _ _ _ _ _ _ alloc current) _ _ folded seed
  exact applyClosure_custody_bounded _ _ _ _ _ last preserved

theorem completeHandler_custody_bounded (state : State) (context : Context) (after : Transition)
    (accepted : completeHandler state context = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [completeHandler, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem openRequest_custody_bounded (state : State) (context : Context) (operation : Operation) (operands : List Located) (after : Transition)
    (accepted : openRequest state context operation operands = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [openRequest, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → invokeFunction_custody_bounded, → temporary_custody_bounded, → finishTemporary_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem takeCapture_custody_bounded (state : State) (context : Context) (token : Located) (after : State × Capture)
    (accepted : takeCapture state context token = .ok after) (bounded : state.heap.CustodyBounded) : after.1.heap.CustodyBounded := by
  simp only [takeCapture, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → instantiateCapture_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem activateCapture_custody_bounded (state : State) (context : Context) (capture : Capture)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : State)
    (accepted : activateCapture state context capture successor = .ok after) (bounded : state.heap.CustodyBounded) : after.heap.CustodyBounded := by
  simp only [activateCapture, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem resumeValue_custody_bounded (state : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (accepted : resumeValue state context token argument successor = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [resumeValue, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → takeCapture_custody_bounded, → activateCapture_custody_bounded, → temporary_custody_bounded, → finishTemporary_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem resumeComputation_custody_bounded (state : State) (context : Context) (token computation : Located) (after : Transition)
    (accepted : resumeComputation state context token computation = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [resumeComputation, bind] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → takeCapture_custody_bounded, → activateCapture_custody_bounded, → applyClosure_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem restoreResumeCaller_custody_bounded (state : State) (after : Transition)
    (accepted : restoreResumeCaller state = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [restoreResumeCaller, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → temporary_custody_bounded, → finishTemporary_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem enterRegion_custody_bounded (state : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition)
    (accepted : enterRegion state context descriptor body arguments = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [enterRegion, bind] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → applyClosure_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem executeEffectTerm_custody_bounded (state : State) (context : Context) (after : Transition)
    (accepted : executeEffectTerm state context = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [executeEffectTerm, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → openRequest_custody_bounded, → installHandler_custody_bounded, → resumeValue_custody_bounded, → resumeComputation_custody_bounded, → enterRegion_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem installProtection_custody_bounded (state : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (accepted : installProtection state context body cleanup arguments resource loan = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [installProtection, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → applyClosure_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem beginCleanup_custody_bounded (state : State) (context : Context) (identity : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (accepted : beginCleanup state context identity exit normal tail = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [beginCleanup, bind, pure, Except.pure] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → applyClosure_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem finishCleanup_custody_bounded (state : State) (context : Context) (after : Transition)
    (accepted : finishCleanup state context = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [finishCleanup, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, resumeRelease] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem cleanupFailed_custody_bounded (state : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : cleanupFailed state identity invocation outer normal tail inner = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [cleanupFailed, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem releaseScope_custody_bounded (state : State) (after : Transition)
    (accepted : releaseScope state = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [releaseScope, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem discardValues_custody_bounded (state : State) (context : Context) (after : Transition)
    (accepted : discardValues state context = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [discardValues, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, resumeRelease] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem unwindStep_custody_bounded (state : State) (context : Context) (after : Transition)
    (accepted : unwindStep state context = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [unwindStep, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → beginCleanup_custody_bounded, → cleanupFailed_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem executeCleanupTerm_custody_bounded (state : State) (context : Context) (after : Transition)
    (accepted : executeCleanupTerm state context = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [executeCleanupTerm, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → installProtection_custody_bounded, → temporary_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem tickRunning_custody_bounded (state : State) (context : Context) (after : Transition)
    (accepted : tickRunning state context = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [tickRunning, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → enterTerm_custody_bounded, → enterExpression_custody_bounded, → enterInvocation_custody_bounded, → releaseScope_custody_bounded, → discardValues_custody_bounded, → unwindStep_custody_bounded, → executePrimitive_custody_bounded, → executeEffectTerm_custody_bounded, → executeCleanupTerm_custody_bounded, → executeControlTerm_custody_bounded, → enterBinding_custody_bounded, → deliverOperand_custody_bounded, → leaveInvocation_custody_bounded, → leaveLexical_custody_bounded, → restoreResumeCaller_custody_bounded, → completeHandler_custody_bounded, → beginCleanup_custody_bounded, → finishCleanup_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem tick_custody_bounded (state : State) (context : Context) (after : Transition)
    (accepted : tick state context = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [tick] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → tickRunning_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem external_custody_bounded (state : State) (context : Context) (action : External) (after : Transition)
    (accepted : external state context action = .ok after) (bounded : state.heap.CustodyBounded) : after.state.heap.CustodyBounded := by
  simp only [external, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → commitBook_custody_bounded, → consumeBook_custody_bounded, → moveValues_custody_bounded, → consumeValue_custody_bounded, → allocateObject_custody_bounded, → replaceObject_custody_bounded, → retireObject_custody_bounded, → scopedValue_custody_bounded,
    ← CustodyBounds.mk, cases CustodyBounds, List.length_set, List.length_append,
    List.length_cons, List.length_nil]

theorem step_custody_bounded (step : Step context before events after)
    (bounded : before.heap.CustodyBounded) : after.heap.CustodyBounded := by
  cases step with
  | internal checked => exact tick_custody_bounded _ _ _ checked bounded
  | external checked => exact external_custody_bounded _ _ _ _ checked bounded

theorem steps_custody_bounded (steps : Steps context before events after)
    (bounded : before.heap.CustodyBounded) : after.heap.CustodyBounded := by
  induction steps with
  | refl => exact bounded
  | cons first _ induction => exact induction (step_custody_bounded first bounded)

theorem initial_custody_bounded (context : Context) (arguments : List SemanticValue) (state : State)
    (accepted : initial context arguments = .ok state) : state.heap.CustodyBounded := by
  unfold initial at accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  cases accepted
  constructor <;> simp [Custody.empty]

theorem source_trajectory_custody_bounds (context : Context) (arguments : List SemanticValue)
    (before after : State) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : after.heap.CustodyBounded :=
  steps_custody_bounded steps (initial_custody_bounded _ _ _ initialized)

/-- Fresh object allocation cannot collide with any live custody entry on an
initialized trajectory. This is a progress fact about the actual allocator. -/
theorem bounded_custody_allocation_succeeds (heap : Heap) (bounded : heap.CustodyBounded)
    (schema : SchemaId .source) (object : Object) (owner : Custody.Owner) (exclusive : Bool) :
    (allocateObject heap schema object owner exclusive).isSome = true := by
  have tokenFresh : (⟨heap.nextCustody⟩ : CustodyToken) ∉ heap.custody.entries.map Custody.Entry.token := by
    rintro member
    obtain ⟨entry, member, same⟩ := List.mem_map.mp member
    have smaller := bounded.tokens entry member
    have equal := congrArg Ref.value same
    simp only at equal
    omega
  have objectFresh : (⟨heap.objects.length⟩ : NodeId) ∉ heap.custody.entries.map Custody.Entry.object := by
    rintro member
    obtain ⟨entry, member, same⟩ := List.mem_map.mp member
    have smaller := bounded.objects entry member
    have equal := congrArg Ref.value same
    simp only at equal
    omega
  cases exclusive <;> simp [allocateObject, Custody.allocate, tokenFresh, objectFresh]

/-- A previously live token stays below every later allocation frontier, even
if it has since been consumed. Monotone supplies therefore prevent reuse. -/
theorem old_token_below_later_supply (steps : Steps context before events after)
    (bounded : before.heap.CustodyBounded) (entry : Custody.Entry)
    (member : entry ∈ before.heap.custody.entries) : entry.token.value < after.heap.nextCustody :=
  Nat.lt_of_lt_of_le (bounded.tokens entry member) (steps_allocation steps).heap.custody

theorem later_allocation_uses_distinct_token (steps : Steps context before events after)
    (bounded : before.heap.CustodyBounded) (entry : Custody.Entry)
    (member : entry ∈ before.heap.custody.entries) (schema : SchemaId .source)
    (object : Object) (owner : Custody.Owner) (heap : Heap) (value : Located)
    (allocated : allocateObject after.heap schema object owner true = some (heap, value)) :
    ∃ token, value.value = .reference schema ⟨after.heap.objects.length⟩ (some token) ∧ token ≠ entry.token := by
  simp [allocateObject, Option.bind_eq_some_iff] at allocated
  obtain ⟨_, _, _, equal⟩ := allocated
  have smaller := old_token_below_later_supply steps bounded entry member
  refine ⟨⟨after.heap.nextCustody⟩, ?_, ?_⟩
  · exact (congrArg Located.value equal).symm
  · intro same
    have sameValue := congrArg Ref.value same
    simp only at sameValue
    omega

end BoundaryV2.Profile.Source.Machine
