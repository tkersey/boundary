import BoundaryV2.SourceRequestLaws
import BoundaryV2.SourceActivationLaws

namespace BoundaryV2.Profile.Source.Machine

/-- Allocation records retain their actual array identity through execution.
This is one identity invariant; it does not assert complete machine typing,
reference validity, or unique custody of all graph edges. -/
structure Heap.Indexed (heap : Heap) : Prop where
  scopes : heap.scopes.map (fun scope => scope.id.value) = List.range heap.nextScope
  invocations : heap.invocations.map (fun invocation => invocation.id.value) = List.range heap.nextInvocation
  obligations : heap.obligations.map (fun obligation => obligation.id.value) = List.range heap.nextObligation

private theorem map_set_retains (project : α → β) (items : List α) (index : Nat) (old fresh : α)
    (found : items[index]? = some old) (same : project fresh = project old) :
    (items.set index fresh).map project = items.map project := by
  induction items generalizing index with
  | nil => simp at found
  | cons head tail induction =>
    cases index with
    | zero => cases found; simp [same]
    | succ index =>
      simp only [List.getElem?_cons_succ] at found
      simpa using congrArg (fun values => project head :: values) (induction index found)

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β)
    (result : β) : value.bind next = .ok result ↔
      ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem moveValues_indexed (before after : Heap) (values : List Located)
    (receiver : Nat → Custody.Owner) (accepted : moveValues before values receiver = some after)
    (indexed : before.Indexed) : after.Indexed := by
  simp [moveValues, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  exact ⟨indexed.scopes, indexed.invocations, indexed.obligations⟩

theorem consumeValue_indexed (before after : Heap) (value : Located)
    (accepted : consumeValue before value = some after) (indexed : before.Indexed) : after.Indexed := by
  simp [consumeValue, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  exact ⟨indexed.scopes, indexed.invocations, indexed.obligations⟩

theorem allocateObject_indexed (before after : Heap) (schema : SchemaId .source)
    (object : Object) (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject before schema object owner exclusive = some (after, value))
    (indexed : before.Indexed) : after.Indexed := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, _⟩ := accepted; exact ⟨indexed.scopes, indexed.invocations, indexed.obligations⟩
  · obtain ⟨_, _, rfl, _⟩ := accepted; exact ⟨indexed.scopes, indexed.invocations, indexed.obligations⟩

theorem replaceObject_indexed (before after : Heap) (node : NodeId) (object : Object)
    (accepted : replaceObject before node object = some after) (indexed : before.Indexed) : after.Indexed := by
  unfold replaceObject at accepted
  split at accepted
  · cases accepted; exact ⟨indexed.scopes, indexed.invocations, indexed.obligations⟩
  · contradiction

theorem retireObject_indexed (before after : Heap) (value : Located)
    (accepted : retireObject before value = some after) (indexed : before.Indexed) : after.Indexed := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, Option.bind_eq_some_iff, pure, Option.some.injEq] at accepted
  obtain ⟨_, _, middle, consumed, rfl⟩ := accepted
  have preserved := consumeValue_indexed _ _ _ consumed indexed
  exact ⟨preserved.scopes, preserved.invocations, preserved.obligations⟩

theorem temporary_indexed (state after : State) (owner : Custody.Owner)
    (accepted : temporary state = .ok (after, owner)) (indexed : state.heap.Indexed) : after.heap.Indexed := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  rename_i record found
  split at accepted <;> try contradiction
  cases accepted
  refine ⟨?_, indexed.invocations, indexed.obligations⟩
  exact (map_set_retains (fun row : Scope => row.id.value) _ _ record
    { record with nextOwner := record.nextOwner + 1 } found rfl).trans indexed.scopes

theorem finishTemporary_indexed (state : State) (value : Located) (after : Transition)
    (accepted : finishTemporary state value = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  rename_i record found
  cases accepted
  refine ⟨?_, indexed.invocations, indexed.obligations⟩
  exact (map_set_retains (fun row : Scope => row.id.value) _ _ record
    { record with holdings := record.holdings ++ [value] } found rfl).trans indexed.scopes

theorem scopedValue_indexed (state : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue state value = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, first, last⟩ := accepted
  exact finishTemporary_indexed _ _ _ last (temporary_indexed _ _ _ first indexed)

theorem makeClosureWithValues_indexed (state : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues state context schema function values = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → temporary_indexed, → moveValues_indexed, → allocateObject_indexed, → finishTemporary_indexed, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem makeClosure_indexed (state : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (environment : Environment) (after : Transition)
    (accepted : makeClosure state context schema function environment = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → makeClosureWithValues_indexed, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem enterTerm_indexed (state : State) (source : Module) (after : Transition)
    (accepted : enterTerm state source = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [enterTerm, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem deliverOperand_indexed (state : State) (after : Transition)
    (accepted : deliverOperand state = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [deliverOperand, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem authoredFailure_indexed (state : State) (context : Context) (failures : List (InstructionFailure .source)) (fault : Fault) (after : Transition)
    (accepted : authoredFailure state context failures fault = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [authoredFailure, bind, except_bind_ok, fromOption_ok, pure, Except.pure] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem enterExpression_indexed (state : State) (context : Context) (after : Transition)
    (accepted : enterExpression state context = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [enterExpression, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, finishValue] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → scopedValue_indexed, → makeClosure_indexed, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem commitPure_indexed (state : State) (opcode : Opcode) (operands : List Located) (result : SemanticValue) (after : Transition)
    (accepted : commitPure state opcode operands result = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [commitPure, bind, except_bind_ok] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → temporary_indexed, → moveValues_indexed, → finishTemporary_indexed, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem heapPrimitive_indexed (state : State) (context : Context) (operation : Primitives.GraphOperation)
    (schema : SchemaId .source) (immediate : Nat) (operands : List Located) (after : Transition)
    (accepted : heapPrimitive state context operation schema immediate operands = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [heapPrimitive, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → makeClosureWithValues_indexed, → temporary_indexed, → moveValues_indexed, → allocateObject_indexed, → finishTemporary_indexed, → scopedValue_indexed, → replaceObject_indexed, → retireObject_indexed, → commitPure_indexed, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem executePrimitive_indexed (state : State) (context : Context) (after : Transition)
    (accepted : executePrimitive state context = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [executePrimitive, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → authoredFailure_indexed, → commitPure_indexed, → heapPrimitive_indexed, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem createScope_indexed (state : State) (context : Context) (invocation : InvocationId) (parent : Option LexicalScopeId)
    (vars : List VariableId) (values : List Located) (environment : Environment) (after : State × Environment)
    (accepted : createScope state context invocation parent vars values environment = .ok after) (indexed : state.heap.Indexed) : after.1.heap.Indexed := by
  simp only [createScope, bind, except_bind_ok, moveValues, pure, Except.pure] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, Option.bind_eq_some_iff, List.map_append, List.map_cons, List.map_nil, List.range_succ, cases Heap.Indexed]

private theorem createScope_invocation_counter (state : State) (context : Context) (invocation : InvocationId) (parent : Option LexicalScopeId)
    (vars : List VariableId) (values : List Located) (environment : Environment) (after : State × Environment)
    (accepted : createScope state context invocation parent vars values environment = .ok after) : after.1.heap.nextInvocation = state.heap.nextInvocation := by
  simp only [createScope, bind, except_bind_ok, moveValues, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, Option.bind_eq_some_iff]

theorem invokeFunction_indexed (state : State) (context : Context) (function : FunctionId .source)
    (environment : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction state context function environment arguments = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [invokeFunction, bind, except_bind_ok, fromOption_ok, pure, Except.pure] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → createScope_indexed, → createScope_invocation_counter, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem applyClosure_indexed (state : State) (context : Context) (closure : Located) (arguments : List Located) (after : Transition)
    (accepted : applyClosure state context closure arguments = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [applyClosure, bind, except_bind_ok, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → retireObject_indexed, → invokeFunction_indexed, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem enterInvocation_indexed (state : State) (context : Context) (after : Transition)
    (accepted : enterInvocation state context = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [enterInvocation, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → invokeFunction_indexed, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem enterBinding_indexed (state : State) (context : Context) (after : Transition)
    (accepted : enterBinding state context = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [enterBinding, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → createScope_indexed, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem enterPattern_indexed (state : State) (context : Context) (vars : List VariableId) (parts : List SemanticValue)
    (owner : Custody.Owner) (body : TermId) (environment : Environment) (after : Transition)
    (accepted : enterPattern state context vars parts owner body environment = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → createScope_indexed, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem executeControlTerm_indexed (state : State) (context : Context) (after : Transition)
    (accepted : executeControlTerm state context = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [executeControlTerm, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → applyClosure_indexed, → enterPattern_indexed, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem leaveScope_indexed (state : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition)
    (accepted : leaveScope state parent invocation tail value = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [leaveScope, bind, except_bind_ok, fromOption_ok, pure, Except.pure] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → temporary_indexed, → moveValues_indexed, → finishTemporary_indexed, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem leaveInvocation_indexed (state : State) (after : Transition)
    (accepted : leaveInvocation state = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [leaveInvocation, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, → leaveScope_indexed, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem finishEmptyRelease_indexed (state : State) (after : Transition)
    (accepted : finishEmptyRelease state = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [finishEmptyRelease, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, resumeRelease] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, Option.bind_eq_some_iff, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

private theorem dedup_nodup [BEq α] [LawfulBEq α] (values : List α) : values.eraseDups.Nodup := by
  cases values with
  | nil => simp
  | cons head tail =>
    rw [List.eraseDups_cons, List.nodup_cons]
    constructor
    · simp [List.mem_eraseDups]
    · exact dedup_nodup _
termination_by values.length
decreasing_by have := List.length_filter_le (fun value => !value == head) tail; simp only [List.length_cons]; omega

private theorem dedup_of_nodup [BEq α] [LawfulBEq α] (values : List α) (unique : values.Nodup) :
    values.eraseDups = values := by
  induction values with
  | nil => rfl
  | cons head tail induction =>
    rw [List.nodup_cons] at unique
    have unchanged : tail.filter (fun value => !value == head) = tail := by
      apply List.filter_eq_self.mpr
      intro value member
      have different : value ≠ head := by intro same; exact unique.1 (same ▸ member)
      simpa using different
    rw [List.eraseDups_cons, unchanged, induction unique.2]

private theorem renamed_fresh_at (space : Space) (domain : Domain) (start : Nat)
    (identities : List (Ref space domain)) (unique : identities.Nodup)
    (index : Nat) (bound : index < identities.length) :
    (renamed (freshMap space domain start identities) identities[index]).value = start + index := by
  have selected := renamed_inside_fresh_map space domain start identities identities[index] (List.getElem_mem bound)
  obtain ⟨position, positionBound, atPosition⟩ := List.mem_mapIdx.mp selected
  have source := congrArg Prod.fst atPosition
  have target := congrArg (fun pair => pair.2.value) atPosition
  simp only [dedup_of_nodup identities unique] at source target positionBound
  have same : position = index := (List.getElem_inj unique).mp source
  simpa [same] using target.symm

private theorem fresh_map_indices (space : Space) (domain : Domain) (start : Nat)
    (identities : List (Ref space domain)) (unique : identities.Nodup) :
    identities.map (fun identity => (renamed (freshMap space domain start identities) identity).value) =
      List.range' start identities.length := by
  apply List.ext_getElem
  · simp
  · intro index leftBound rightBound
    simp only [List.length_map] at leftBound
    simpa using renamed_fresh_at space domain start identities unique index leftBound

private theorem mapM_projection (function : α → Except Invalid β) (project : β → γ) (expected : α → γ)
    (maps : ∀ input output, function input = .ok output → project output = expected input)
    (inputs : List α) (outputs : List β) (accepted : inputs.mapM function = .ok outputs) :
    outputs.map project = inputs.map expected := by
  induction inputs generalizing outputs with
  | nil => cases accepted; rfl
  | cons head tail induction =>
    simp only [List.mapM_cons, bind, except_bind_ok] at accepted
    obtain ⟨first, firstAt, rest, restAt, accepted⟩ := accepted
    cases accepted
    simp only [List.map_cons, maps _ _ firstAt, induction _ restAt]

theorem instantiateCapture_indexed (state : State) (context : Context) (capture : Capture) (after : State × Capture)
    (accepted : instantiateCapture state context capture = .ok after) (indexed : state.heap.Indexed) :
    after.1.heap.Indexed := by
  let dormant := (cloneSupport state.heap capture).filterMap (fun node => match state.heap.lookup node with
    | some (.multiTemplate inner) => some inner | _ => none)
  let localScopes := (captureScopes capture ++ dormant.flatMap captureScopes).eraseDups
  let localInvocations := (captureInvocations capture ++ dormant.flatMap captureInvocations).eraseDups
  unfold instantiateCapture at accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨scopeRows, scopeRowsAt, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨invocationRows, invocationRowsAt, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  cases accepted
  have scopeProjection : scopeRows.map (fun row : Scope => row.id.value) =
      localScopes.map (fun scope => (renamed (freshMap .runtime .lexicalScope state.heap.nextScope localScopes) scope).value) := by
    apply mapM_projection _ _ _ ?_ _ _ scopeRowsAt
    intro input output checked
    simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at checked
    obtain ⟨_, _, rfl⟩ := checked
    rfl
  have invocationProjection : invocationRows.map (fun row : Invocation => row.id.value) =
      localInvocations.map (fun invocation => (renamed (freshMap .runtime .invocation state.heap.nextInvocation localInvocations) invocation).value) := by
    apply mapM_projection _ _ _ ?_ _ _ invocationRowsAt
    intro input output checked
    simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at checked
    obtain ⟨_, _, rfl⟩ := checked
    rfl
  have scopeIds := scopeProjection.trans (fresh_map_indices _ _ _ _ (dedup_nodup _))
  have invocationIds := invocationProjection.trans (fresh_map_indices _ _ _ _ (dedup_nodup _))
  refine ⟨?_, ?_, indexed.obligations⟩
  · change (state.heap.scopes ++ scopeRows).map (fun row => row.id.value) =
      List.range (state.heap.nextScope + localScopes.length)
    rw [List.map_append, scopeIds, indexed.scopes, List.range_add, List.range'_eq_map_range]
  · change (state.heap.invocations ++ invocationRows).map (fun row => row.id.value) =
      List.range (state.heap.nextInvocation + localInvocations.length)
    rw [List.map_append, invocationIds, indexed.invocations, List.range_add, List.range'_eq_map_range]

theorem leaveLexical_indexed (state : State) (after : Transition)
    (accepted : leaveLexical state = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, record, _, parent, _, result, departed, remaining⟩ := accepted
  split at remaining <;> try contradiction
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at remaining
  obtain ⟨parentRecord, parentAt, heap, moved, equal⟩ := remaining
  cases equal
  simp only [moveValues, bind, Option.bind_eq_some_iff, pure, Option.some.injEq] at moved
  obtain ⟨_, _, rfl⟩ := moved
  have preserved := leaveScope_indexed _ _ _ _ _ _ departed indexed
  refine ⟨?_, preserved.invocations, preserved.obligations⟩
  apply Eq.trans (b := result.state.heap.scopes.map (fun row => row.id.value))
  · apply map_set_retains _ _ _ _ _ parentAt
    rfl
  · exact preserved.scopes

private theorem foldlM_indexed (items : List β)
    (step : Heap × α → β → Except Invalid (Heap × α))
    (preserves : ∀ before item after, step before item = .ok after → before.1.Indexed → after.1.Indexed)
    (before after : Heap × α) (accepted : items.foldlM step before = .ok after) (indexed : before.1.Indexed) :
    after.1.Indexed := by
  induction items generalizing before with
  | nil => cases accepted; exact indexed
  | cons item tail induction =>
    rw [List.foldlM_cons] at accepted
    obtain ⟨middle, first, last⟩ := (except_bind_ok _ _ _).mp accepted
    exact induction middle last (preserves before item middle first indexed)

theorem installHandler_indexed (state : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (environment : Environment) (after : Transition)
    (accepted : installHandler state context handler body arguments stored environment = .ok after)
    (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [installHandler, bind, except_bind_ok] at accepted
  obtain ⟨definition, _, _, _, _, _, _, _, signature, _, _, _, ⟨heap, capabilities⟩, folded, last⟩ := accepted
  have seed : ({ state.heap with nextAttachment := state.heap.nextAttachment + 1 } : Heap).Indexed :=
    ⟨indexed.scopes, indexed.invocations, indexed.obligations⟩
  have preserved := foldlM_indexed _ _ (by
    intro before item after checked current
    rcases before with ⟨heap, capabilities⟩
    rcases item with ⟨clause, schema⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at checked
    obtain ⟨_, _, ⟨allocated, value⟩, alloc, equal⟩ := checked
    cases equal
    exact allocateObject_indexed _ _ _ _ _ _ _ alloc current) _ _ folded seed
  exact applyClosure_indexed _ _ _ _ _ last preserved

private theorem obligation_set_indexed (heap : Heap) (index : Nat)
    (before after : Cleanup.Obligation .source) (found : heap.obligations[index]? = some before)
    (same : after.id = before.id) (indexed : heap.Indexed) :
    ({ heap with obligations := heap.obligations.set index after } : Heap).Indexed := by
  refine ⟨indexed.scopes, indexed.invocations, ?_⟩
  exact (map_set_retains (fun row : Cleanup.Obligation .source => row.id.value) _ _ _ _ found
    (congrArg Ref.value same)).trans indexed.obligations

theorem completeHandler_indexed (state : State) (context : Context) (after : Transition)
    (accepted : completeHandler state context = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [completeHandler, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, Option.bind_eq_some_iff, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem openRequest_indexed (state : State) (context : Context) (operation : Operation) (operands : List Located) (after : Transition)
    (accepted : openRequest state context operation operands = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [openRequest, bind, except_bind_ok, fromOption_ok, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, Option.bind_eq_some_iff, → invokeFunction_indexed, → moveValues_indexed, → temporary_indexed, → allocateObject_indexed, → finishTemporary_indexed, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem takeCapture_indexed (state : State) (context : Context) (token : Located) (after : State × Capture)
    (accepted : takeCapture state context token = .ok after) (indexed : state.heap.Indexed) : after.1.heap.Indexed := by
  simp only [takeCapture, bind, except_bind_ok, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, Option.bind_eq_some_iff, → retireObject_indexed, → instantiateCapture_indexed, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem activateCapture_indexed (state : State) (context : Context) (capture : Capture)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : State)
    (accepted : activateCapture state context capture successor = .ok after) (indexed : state.heap.Indexed) : after.heap.Indexed := by
  simp only [activateCapture, bind, except_bind_ok, fromOption_ok, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, Option.bind_eq_some_iff, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem resumeValue_indexed (state : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (accepted : resumeValue state context token argument successor = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [resumeValue, bind, except_bind_ok, fromOption_ok, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, Option.bind_eq_some_iff, → takeCapture_indexed, → activateCapture_indexed, → temporary_indexed, → moveValues_indexed, → finishTemporary_indexed, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem resumeComputation_indexed (state : State) (context : Context) (token computation : Located) (after : Transition)
    (accepted : resumeComputation state context token computation = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, Option.bind_eq_some_iff, → takeCapture_indexed, → activateCapture_indexed, → applyClosure_indexed, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem restoreResumeCaller_indexed (state : State) (after : Transition)
    (accepted : restoreResumeCaller state = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [restoreResumeCaller, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, Option.bind_eq_some_iff, → temporary_indexed, → moveValues_indexed, → finishTemporary_indexed, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem enterRegion_indexed (state : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition)
    (accepted : enterRegion state context descriptor body arguments = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [enterRegion, bind, except_bind_ok, fromOption_ok] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, Option.bind_eq_some_iff, → allocateObject_indexed, → applyClosure_indexed, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem executeEffectTerm_indexed (state : State) (context : Context) (after : Transition)
    (accepted : executeEffectTerm state context = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [executeEffectTerm, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, Option.bind_eq_some_iff, → openRequest_indexed, → installHandler_indexed, → resumeValue_indexed, → resumeComputation_indexed, → enterRegion_indexed, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem installProtection_indexed (state : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (accepted : installProtection state context body cleanup arguments resource loan = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [installProtection, moveValues, bind, except_bind_ok, fromOption_ok, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, Option.bind_eq_some_iff, → moveValues_indexed, → allocateObject_indexed, → applyClosure_indexed, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem beginCleanup_indexed (state : State) (context : Context) (identity : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (accepted : beginCleanup state context identity exit normal tail = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [beginCleanup, bind, except_bind_ok, fromOption_ok, pure, Except.pure] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, Option.bind_eq_some_iff, → applyClosure_indexed, → obligation_set_indexed, → Cleanup.begin_advances_once, → Cleanup.complete_advances_once, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem finishCleanup_indexed (state : State) (context : Context) (after : Transition)
    (accepted : finishCleanup state context = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [finishCleanup, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, resumeRelease] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, Option.bind_eq_some_iff, → obligation_set_indexed, → Cleanup.begin_advances_once, → Cleanup.complete_advances_once, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem cleanupFailed_indexed (state : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : cleanupFailed state identity invocation outer normal tail inner = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [cleanupFailed, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, Option.bind_eq_some_iff, → obligation_set_indexed, → Cleanup.begin_advances_once, → Cleanup.complete_advances_once, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem releaseScope_indexed (state : State) (after : Transition)
    (accepted : releaseScope state = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [releaseScope, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, Option.bind_eq_some_iff, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem discardValues_indexed (state : State) (context : Context) (after : Transition)
    (accepted : discardValues state context = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [discardValues, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, resumeRelease] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, Option.bind_eq_some_iff, → retireObject_indexed, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem unwindStep_indexed (state : State) (context : Context) (after : Transition)
    (accepted : unwindStep state context = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [unwindStep, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, Option.bind_eq_some_iff, → beginCleanup_indexed, → cleanupFailed_indexed, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem executeCleanupTerm_indexed (state : State) (context : Context) (after : Transition)
    (accepted : executeCleanupTerm state context = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [executeCleanupTerm, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, Option.bind_eq_some_iff, → installProtection_indexed, → temporary_indexed, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem tickRunning_indexed (state : State) (context : Context) (after : Transition)
    (accepted : tickRunning state context = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [tickRunning, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, Option.bind_eq_some_iff, → enterTerm_indexed, → enterExpression_indexed, → enterInvocation_indexed, → releaseScope_indexed, → discardValues_indexed, → unwindStep_indexed, → executePrimitive_indexed, → executeEffectTerm_indexed, → executeCleanupTerm_indexed, → executeControlTerm_indexed, → enterBinding_indexed, → deliverOperand_indexed, → leaveInvocation_indexed, → leaveLexical_indexed, → restoreResumeCaller_indexed, → completeHandler_indexed, → beginCleanup_indexed, → finishCleanup_indexed, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem tick_indexed (state : State) (context : Context) (after : Transition)
    (accepted : tick state context = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [tick] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, Option.bind_eq_some_iff, → tickRunning_indexed, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

theorem external_indexed (state : State) (context : Context) (action : External) (after : Transition)
    (accepted : external state context action = .ok after) (indexed : state.heap.Indexed) : after.state.heap.Indexed := by
  simp only [external, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  constructor <;> grind (gen := 32) only [except_bind_ok, fromOption_ok, Option.bind_eq_some_iff, → scopedValue_indexed, List.map_append, List.map_cons, List.map_nil, List.range_succ, ← Heap.Indexed.mk, cases Heap.Indexed]

/-- Every actual source transition preserves the allocation-record identity
invariant, including suspended cleanup and reusable capture instantiation. -/
theorem step_indexed (step : Step context before events after) (indexed : before.heap.Indexed) :
    after.heap.Indexed := by
  cases step with
  | internal checked => exact tick_indexed _ _ _ checked indexed
  | external checked => exact external_indexed _ _ _ _ checked indexed

theorem steps_indexed (steps : Steps context before events after) (indexed : before.heap.Indexed) :
    after.heap.Indexed := by
  induction steps with
  | refl => exact indexed
  | cons first _ induction => exact induction (step_indexed first indexed)

theorem initial_indexed (context : Context) (arguments : List SemanticValue) (state : State)
    (accepted : initial context arguments = .ok state) : state.heap.Indexed := by
  unfold initial at accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  cases accepted
  exact ⟨rfl, rfl, rfl⟩

theorem source_trajectory_indices (context : Context) (arguments : List SemanticValue) (before after : State)
    (initialized : initial context arguments = .ok before) (steps : Steps context before events after) :
    after.heap.Indexed := steps_indexed steps (initial_indexed _ _ _ initialized)

private theorem indexed_lookup (rows : List α) (project : α → Nat) (count : Nat)
    (indexed : rows.map project = List.range count) (index : Nat) (row : α)
    (found : rows[index]? = some row) : project row = index := by
  have size := congrArg List.length indexed
  simp only [List.length_map, List.length_range] at size
  have bound : index < count := by
    have bound := (List.getElem?_eq_some_iff.mp found).1
    omega
  have atIndex : (rows.map project)[index]? = some (project row) := by simp [found]
  rw [indexed, List.getElem?_range bound] at atIndex
  exact (Option.some.inj atIndex).symm

theorem Heap.Indexed.scope_identity {heap : Heap} {index : Nat} {scope : Scope} (indexed : heap.Indexed) (found : heap.scopes[index]? = some scope) :
    scope.id.value = index := indexed_lookup _ _ _ indexed.scopes _ _ found

theorem Heap.Indexed.invocation_identity {heap : Heap} {index : Nat} {invocation : Invocation} (indexed : heap.Indexed) (found : heap.invocations[index]? = some invocation) :
    invocation.id.value = index := indexed_lookup _ _ _ indexed.invocations _ _ found

theorem Heap.Indexed.obligation_identity {heap : Heap} {index : Nat} {obligation : Cleanup.Obligation .source} (indexed : heap.Indexed) (found : heap.obligations[index]? = some obligation) :
    obligation.id.value = index := indexed_lookup _ _ _ indexed.obligations _ _ found

theorem Heap.Indexed.supplies {heap : Heap} (indexed : heap.Indexed) :
    heap.nextScope = heap.scopes.length ∧ heap.nextInvocation = heap.invocations.length ∧
      heap.nextObligation = heap.obligations.length := by
  have scopes := congrArg List.length indexed.scopes
  have invocations := congrArg List.length indexed.invocations
  have obligations := congrArg List.length indexed.obligations
  simp only [List.length_map, List.length_range] at scopes invocations obligations
  exact ⟨scopes.symm, invocations.symm, obligations.symm⟩

theorem Heap.Indexed.unique_ids {heap : Heap} (indexed : heap.Indexed) :
    (heap.scopes.map (fun row => row.id.value)).Nodup ∧
      (heap.invocations.map (fun row => row.id.value)).Nodup ∧
      (heap.obligations.map (fun row => row.id.value)).Nodup := by
  rw [indexed.scopes, indexed.invocations, indexed.obligations]
  exact ⟨List.nodup_range, List.nodup_range, List.nodup_range⟩

end BoundaryV2.Profile.Source.Machine
