import BoundaryV2.SourceIdentitySupport

namespace BoundaryV2.Profile.Source.Machine
namespace IdentitySupport

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem heap_lookup (bounded : HeapValid limit heap) (found : heap.lookup node = some object) :
    ObjectValid limit object := by
  unfold Heap.lookup at found
  obtain ⟨entry, found, present⟩ := Option.bind_eq_some_iff.mp found
  exact bounded.objects entry (List.mem_of_getElem? found) object present

theorem heap_objects (bounded : HeapValid limit heap)
    (objects : ∀ entry ∈ fresh, ∀ object ∈ entry, ObjectValid limit object) :
    HeapValid limit { heap with objects := fresh } :=
  ⟨objects, bounded.scopes, bounded.invocations, bounded.obligations, bounded.loans⟩

theorem move_heap (bounded : HeapValid limit heap)
    (accepted : moveValues heap values receiver = some after) : HeapValid limit after := by
  simp [moveValues, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  exact ⟨bounded.objects, bounded.scopes, bounded.invocations, bounded.obligations, bounded.loans⟩

theorem consume_heap (bounded : HeapValid limit heap)
    (accepted : consumeValue heap value = some after) : HeapValid limit after := by
  simp [consumeValue, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  exact ⟨bounded.objects, bounded.scopes, bounded.invocations, bounded.obligations, bounded.loans⟩

theorem allocate_heap (bounded : HeapValid limit heap) (newBounded : ObjectValid limit object)
    (accepted : allocateObject heap schema object owner exclusive = some (after, result)) : HeapValid limit after := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, _⟩ := accepted
    refine ⟨?_, bounded.scopes, bounded.invocations, bounded.obligations, bounded.loans⟩
    intro entry member present found
    rcases List.mem_append.mp member with old | added
    · exact bounded.objects entry old present found
    · cases List.mem_singleton.mp added
      cases found
      exact newBounded
  · obtain ⟨_, _, rfl, _⟩ := accepted
    refine ⟨?_, bounded.scopes, bounded.invocations, bounded.obligations, bounded.loans⟩
    intro entry member present found
    rcases List.mem_append.mp member with old | added
    · exact bounded.objects entry old present found
    · cases List.mem_singleton.mp added
      cases found
      exact newBounded

theorem replace_heap (bounded : HeapValid limit heap) (newBounded : ObjectValid limit object)
    (accepted : replaceObject heap node object = some after) : HeapValid limit after := by
  unfold replaceObject at accepted
  split at accepted <;> try contradiction
  cases accepted
  apply heap_objects bounded
  intro entry member present found
  rcases Or.comm.mp (List.mem_or_eq_of_mem_set member) with fresh | old
  · cases fresh
    cases found
    exact newBounded
  · exact bounded.objects entry old present found

theorem retire_heap (bounded : HeapValid limit heap)
    (accepted : retireObject heap value = some after) : HeapValid limit after := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨_, _, middle, consumed, rfl⟩ := accepted
  apply heap_objects (consume_heap bounded consumed)
  intro entry member present found
  rcases Or.comm.mp (List.mem_or_eq_of_mem_set member) with fresh | old
  · cases fresh
    contradiction
  · exact (consume_heap bounded consumed).objects entry old present found

theorem temporary_heap (bounded : HeapValid limit machine.heap)
    (accepted : temporary machine = .ok (after, owner)) : HeapValid limit after.heap := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  rename_i record found
  split at accepted <;> try contradiction
  cases accepted
  refine ⟨bounded.objects, ?_, bounded.invocations, bounded.obligations, bounded.loans⟩
  intro scope member
  rcases Or.comm.mp (List.mem_or_eq_of_mem_set member) with fresh | old
  · cases fresh
    exact bounded.scopes record (List.mem_of_getElem? found)
  · exact bounded.scopes _ old

theorem finishTemporary_heap (bounded : HeapValid limit machine.heap)
    (accepted : finishTemporary machine value = .ok after) : HeapValid limit after.state.heap := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  rename_i record found
  cases accepted
  refine ⟨bounded.objects, ?_, bounded.invocations, bounded.obligations, bounded.loans⟩
  intro scope member
  rcases Or.comm.mp (List.mem_or_eq_of_mem_set member) with fresh | old
  · cases fresh
    exact bounded.scopes record (List.mem_of_getElem? found)
  · exact bounded.scopes _ old

theorem temporary_valid (bounded : ValidAt limit machine)
    (accepted : temporary machine = .ok (after, owner)) : ValidAt limit after := by
  have heap := temporary_heap bounded.heap accepted
  unfold temporary at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  exact ⟨heap, bounded.frames, bounded.control, bounded.scope, bounded.invocation⟩

theorem finishTemporary_valid (bounded : ValidAt limit machine)
    (accepted : finishTemporary machine value = .ok after) : ValidAt limit after.state := by
  have heap := finishTemporary_heap bounded.heap accepted
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  cases accepted
  exact ⟨heap, bounded.frames, trivial, bounded.scope, bounded.invocation⟩

theorem initial_valid (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) : Valid machine := by
  unfold initial at accepted
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ := accepted
  constructor
  · constructor
    all_goals simp [ScopeValid, InvocationValid, limits, Bound] <;> decide
  · simp
  · trivial
  · simp [Bound, limits] <;> decide
  · simp [Bound, limits] <;> decide

def Upper (limit : Limits) (heap : Heap) : Prop := ∀ domain, limits heap domain ≤ limit domain

theorem upper_before (growth : before.AllocationLE after) (upper : Upper limit after) : Upper limit before :=
  fun domain => Nat.le_trans (limits_monotone growth domain) (upper domain)

theorem scopedValue_valid (bounded : ValidAt limit machine)
    (accepted : scopedValue machine value = .ok after) : ValidAt limit after.state := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, first, last⟩ := accepted
  exact finishTemporary_valid (temporary_valid bounded first) last

theorem move_valid (bounded : ValidAt limit machine)
    (accepted : moveValues machine.heap values receiver = some heap) : ValidAt limit { machine with heap := heap } :=
  ⟨move_heap bounded.heap accepted, bounded.frames, bounded.control, bounded.scope, bounded.invocation⟩

theorem allocate_valid (bounded : ValidAt limit machine) (objectBounded : ObjectValid limit object)
    (accepted : allocateObject machine.heap schema object owner exclusive = some (heap, value)) :
    ValidAt limit { machine with heap := heap } :=
  ⟨allocate_heap bounded.heap objectBounded accepted, bounded.frames, bounded.control, bounded.scope, bounded.invocation⟩

theorem makeClosureWithValues_valid (machine : State) (context : Context)
    (schema : SchemaId .source) (function : FunctionId .source) (values : List Located) (after : Transition)
    (bounded : ValidAt limit machine)
    (accepted : makeClosureWithValues machine context schema function values = .ok after) : ValidAt limit after.state := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, ⟨temporary, owner⟩, temporaryOk, heap, moved, ⟨allocated, result⟩, allocatedOk, finished⟩ := accepted
  exact finishTemporary_valid (allocate_valid (move_valid (temporary_valid bounded temporaryOk) moved) (by trivial) allocatedOk) finished

theorem makeClosure_valid (machine : State) (context : Context)
    (schema : SchemaId .source) (function : FunctionId .source) (bindings : Environment) (after : Transition)
    (bounded : ValidAt limit machine)
    (accepted : makeClosure machine context schema function bindings = .ok after) : ValidAt limit after.state := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  obtain ⟨values, _, created⟩ := accepted
  exact makeClosureWithValues_valid _ _ _ _ _ _ bounded created

theorem createScope_valid (machine : State) (context : Context) (invocation : InvocationId)
    (parent : Option LexicalScopeId) (vars : List VariableId) (values : List Located) (bindings : Environment)
    (after : State) (entered : Environment) (bounded : ValidAt limit machine)
    (invocationBound : Bound limit invocation) (parentBound : ∀ scope ∈ parent, Bound limit scope)
    (upper : Upper limit after.heap)
    (accepted : createScope machine context invocation parent vars values bindings = .ok (after, entered)) : ValidAt limit after := by
  simp only [createScope, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · cases accepted
    exact bounded
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at accepted
    obtain ⟨_, _, heap, moved, rfl, rfl⟩ := accepted
    have storage := move_heap bounded.heap moved
    have supply : heap.nextScope = machine.heap.nextScope := by
      simp [moveValues, Option.bind_eq_some_iff] at moved
      obtain ⟨_, _, rfl⟩ := moved
      rfl
    have fresh : Bound limit (⟨machine.heap.nextScope⟩ : LexicalScopeId) := by
      have upper := upper .lexicalScope
      simp only [limits] at upper
      simp only [Bound]
      omega
    refine ⟨⟨storage.objects, ?_, storage.invocations, storage.obligations, storage.loans⟩,
      bounded.frames, bounded.control, fresh, bounded.invocation⟩
    intro scope member
    rcases List.mem_append.mp member with old | added
    · exact storage.scopes scope old
    · cases List.mem_singleton.mp added
      exact ⟨fresh, invocationBound, parentBound⟩

theorem active_attachments (bounded : ∀ frame ∈ frames, FrameValid limit frame)
    (member : identity ∈ activeAttachments frames) : Bound limit identity := by
  obtain ⟨frame, frameMember, found⟩ := List.mem_filterMap.mp member
  have formed := bounded frame frameMember
  cases frame <;> simp only [FrameValid] at formed <;> try contradiction
  case handler activation =>
    cases found
    exact formed.1

theorem active_regions (bounded : ∀ frame ∈ frames, FrameValid limit frame)
    (member : identity ∈ activeRegions frames) : Bound limit identity := by
  obtain ⟨frame, frameMember, found⟩ := List.mem_filterMap.mp member
  have formed := bounded frame frameMember
  cases frame <;> simp only [FrameValid] at formed <;> try contradiction
  case region identity =>
    cases found
    exact formed

theorem createScope_metadata (machine : State) (context : Context) (invocation : InvocationId)
    (parent : Option LexicalScopeId) (vars : List VariableId) (values : List Located) (bindings : Environment)
    (after : State) (entered : Environment)
    (accepted : createScope machine context invocation parent vars values bindings = .ok (after, entered)) :
    after.heap.nextInvocation = machine.heap.nextInvocation ∧ after.stack = machine.stack ∧
      after.control = machine.control := by
  simp only [createScope, bind, except_bind_ok, moveValues, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, Option.bind_eq_some_iff]

theorem invokeFunction_valid (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (bounded : ValidAt limit machine) (upper : Upper limit after.state.heap)
    (accepted : invokeFunction machine context function bindings arguments = .ok after) : ValidAt limit after.state := by
  simp only [invokeFunction, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨definition, _, body, _, captured, _, _, _, _, _, ⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have same := createScope_metadata _ _ _ _ _ _ _ _ _ scopeOk
  have middleUpper : Upper limit middle.heap := by
    intro domain
    have high := upper domain
    cases domain <;> simp only [limits] at high ⊢ <;> omega
  have fresh : Bound limit (⟨machine.heap.nextInvocation⟩ : InvocationId) := by
    have high := upper .invocation
    simp only [limits] at high
    simp only [Bound]
    omega
  have middleBounded := createScope_valid _ _ _ _ _ _ _ _ _ bounded fresh (by simp) middleUpper scopeOk
  refine ⟨⟨middleBounded.heap.objects, middleBounded.heap.scopes, ?_,
    middleBounded.heap.obligations, middleBounded.heap.loans⟩, ?_, trivial, middleBounded.scope, fresh⟩
  · intro invocation member
    rcases List.mem_append.mp member with old | added
    · exact middleBounded.heap.invocations invocation old
    · cases List.mem_singleton.mp added
      exact ⟨fresh, fun parent member => active_attachments bounded.frames member,
        fun parent member => active_regions bounded.frames member⟩
  · intro frame member
    rcases List.mem_cons.mp member with freshFrame | old
    · cases freshFrame
      exact ⟨bounded.invocation, bounded.scope⟩
    · exact bounded.frames frame old

end IdentitySupport
end BoundaryV2.Profile.Source.Machine
