import BoundaryV2.SourceEnvironmentTypes
import BoundaryV2.SourceExpressionTypes

namespace BoundaryV2.Profile.Source.Machine

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

namespace ValueInventory

theorem createScope_environment_preserves_all (machine : State) (context : Context)
    (invocation : InvocationId) (parent : Option LexicalScopeId) (vars : List VariableId)
    (values : List Located) (bindings : Environment) (after : State) (entered : Environment)
    (accepted : createScope machine context invocation parent vars values bindings = .ok (after, entered))
    (property : SemanticValue → Prop) (inputs : ∀ value ∈ values, property value.value)
    (outer : ∀ binding ∈ bindings, property binding.located.value) :
    ∀ binding ∈ entered, property binding.located.value := by
  simp only [createScope, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · cases accepted
    intro binding member
    simp only [List.mem_append, List.mem_map, List.mem_filter] at member
    rcases member with ⟨⟨binder, value⟩, member, rfl⟩ | ⟨member, _⟩
    · exact inputs value ((List.of_mem_zip member).2)
    · exact outer binding member
  · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, equal⟩ := accepted
    cases equal
    intro binding member
    simp only [List.mem_append, List.mem_map, List.mem_filter] at member
    rcases member with ⟨⟨binder, value⟩, member, rfl⟩ | ⟨member, _⟩
    · have valueMember := (List.of_mem_zip member).2
      simp only [List.mapIdx_eq_zipIdx_map, List.mem_map] at valueMember
      obtain ⟨⟨original, index⟩, originalMember, rfl⟩ := valueMember
      exact inputs original (List.fst_mem_of_mem_zipIdx originalMember)
    · exact outer binding member

theorem createScope_preserves_control_stack (machine : State) (context : Context)
    (invocation : InvocationId) (parent : Option LexicalScopeId) (vars : List VariableId)
    (values : List Located) (bindings : Environment) (after : State) (entered : Environment)
    (accepted : createScope machine context invocation parent vars values bindings = .ok (after, entered)) :
    after.control = machine.control ∧ after.stack = machine.stack := by
  simp only [createScope, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · cases accepted; exact ⟨rfl, rfl⟩
  · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, equal⟩ := accepted
    cases equal
    exact ⟨rfl, rfl⟩

theorem invokeFunction_preserves_all (machine : State) (context : Context)
    (function : FunctionId .source) (bindings : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction machine context function bindings arguments = .ok after)
    (property : SemanticValue → Prop) (holds : All property machine)
    (outer : ∀ binding ∈ bindings, property binding.located.value)
    (inputs : ∀ value ∈ arguments, property value.value) : All property after.state := by
  simp only [invokeFunction, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨definition, _, body, _, captured, capturedOk, _, _, _, _, ⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have capturedHolds := captured_values_preserve_all bindings _ captured capturedOk property outer
  have valuesHold : ∀ value ∈ captured ++ arguments, property value.value := by
    intro value member
    rcases List.mem_append.mp member with member | member
    · exact capturedHolds value member
    · exact inputs value member
  have middleHolds := createScope_preserves_all _ _ _ _ _ _ _ _ _ scopeOk property holds valuesHold
  have enteredHolds := createScope_environment_preserves_all _ _ _ _ _ _ _ _ _ scopeOk property valuesHold (by simp)
  have sameStack := (createScope_preserves_control_stack _ _ _ _ _ _ _ _ _ scopeOk).2
  simp only [All, state, control, environment, heap, List.flatMap_cons, frame,
    List.nil_append, List.mem_append, List.mem_map, sameStack] at middleHolds ⊢
  grind only []

theorem enterInvocation_preserves_all (machine : State) (context : Context) (after : Transition)
    (accepted : enterInvocation machine context = .ok after) (property : SemanticValue → Prop)
    (holds : All property machine) : All property after.state := by
  unfold enterInvocation at accepted
  split at accepted <;> try contradiction
  rename_i function bindings arguments entered
  apply invokeFunction_preserves_all machine context function bindings arguments after accepted property holds
  all_goals simp only [All, state, entered, control, environment, List.mem_append, List.mem_map] at holds
  all_goals grind only []

theorem enterBinding_preserves_all (machine : State) (context : Context) (after : Transition)
    (accepted : enterBinding machine context = .ok after) (property : SemanticValue → Prop)
    (holds : All property machine) : All property after.state := by
  unfold enterBinding at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i value delivered frames binder body bindings parent tail stacked
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have valueHolds : property value.value := by
    apply holds
    simp [state, delivered, control]
  have outer : ∀ binding ∈ bindings, property binding.located.value := by
    intro binding member
    apply holds
    simp only [state, stacked, List.flatMap_cons, frame, environment, List.mem_append, List.mem_map]
    grind only []
  have inputs : ∀ child ∈ [value], property child.value := by simpa using valueHolds
  have middleHolds := createScope_preserves_all _ _ _ _ _ _ _ _ _ scopeOk property holds inputs
  have enteredHolds := createScope_environment_preserves_all _ _ _ _ _ _ _ _ _ scopeOk property inputs outer
  have sameStack := (createScope_preserves_control_stack _ _ _ _ _ _ _ _ _ scopeOk).2
  split
  all_goals simp only [All, state, control, environment, sameStack, stacked,
    List.flatMap_cons, frame, List.nil_append, List.mem_append, List.mem_map] at middleHolds ⊢
  all_goals grind only []

theorem enterPattern_preserves_all (machine : State) (context : Context) (vars : List VariableId)
    (parts : List SemanticValue) (owner : Custody.Owner) (body : TermId) (bindings : Environment) (after : Transition)
    (accepted : enterPattern machine context vars parts owner body bindings = .ok after)
    (property : SemanticValue → Prop) (holds : All property machine)
    (outer : ∀ binding ∈ bindings, property binding.located.value)
    (inputs : ∀ value ∈ parts, property value) : All property after.state := by
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have valuesHold : ∀ value ∈ parts.map (fun value => Located.mk value owner), property value.value := by
    intro value member
    obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
    exact inputs original originalMember
  have middleHolds := createScope_preserves_all _ _ _ _ _ _ _ _ _ scopeOk property holds valuesHold
  have enteredHolds := createScope_environment_preserves_all _ _ _ _ _ _ _ _ _ scopeOk property valuesHold outer
  have sameStack := (createScope_preserves_control_stack _ _ _ _ _ _ _ _ _ scopeOk).2
  split
  all_goals simp only [All, state, control, environment, sameStack,
    List.flatMap_cons, frame, List.nil_append, List.mem_append, List.mem_map] at middleHolds ⊢
  all_goals grind only []


theorem lookupObject_preserves_all (machine : State) (located : Located) (node : NodeId) (stored : Object)
    (accepted : lookupObject machine located = .ok (node, stored))
    (property : SemanticValue → Prop) (holds : All property machine) :
    ∀ value ∈ object stored, property value := by
  simp only [lookupObject, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨found, lookup, equal⟩ := accepted
  cases equal
  simp only [Heap.lookup, Option.bind_eq_some_iff] at lookup
  obtain ⟨entry, atNode, present⟩ := lookup
  have nodeMember := List.mem_of_getElem? atNode
  cases entry <;> simp [id] at present
  cases present
  intro value member
  apply holds
  simp only [state, heap, List.mem_append, List.mem_flatMap]
  grind only [Option.toList_some, List.mem_singleton]

theorem retireObject_preserves_all (machine : State) (located : Located) (store : Heap)
    (accepted : retireObject machine.heap located = some store)
    (property : SemanticValue → Prop) (holds : All property machine) :
    All property { machine with heap := store } := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, Option.bind_eq_some_iff, consumeValue, pure, Option.some.injEq] at accepted
  obtain ⟨_, _, _, ⟨_, _, rfl⟩, rfl⟩ := accepted
  simp only [All, state, heap, List.mem_append, List.mem_flatMap, List.mem_map] at holds ⊢
  grind only [→ List.mem_or_eq_of_mem_set, Option.toList_none, List.not_mem_nil]

theorem applyClosure_preserves_all (machine : State) (context : Context) (closure : Located)
    (arguments : List Located) (after : Transition)
    (accepted : applyClosure machine context closure arguments = .ok after)
    (property : SemanticValue → Prop) (holds : All property machine)
    (inputs : ∀ value ∈ arguments, property value.value) : All property after.state := by
  simp only [applyClosure, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, lookup, accepted⟩ := accepted
  cases stored <;> try contradiction
  rename_i schema function bindings
  simp only at accepted
  have storedHolds := lookupObject_preserves_all machine closure node (.closure schema function bindings) lookup property holds
  have outer : ∀ binding ∈ bindings, property binding.located.value := by
    intro binding member
    exact storedHolds _ (List.mem_map.mpr ⟨binding, member, rfl⟩)
  split at accepted <;> try contradiction
  · simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨store, storeOk, invoked⟩ := accepted
    exact invokeFunction_preserves_all _ _ _ _ _ _ invoked property
      (retireObject_preserves_all machine closure store storeOk property holds) outer inputs
  · simp only [pure, Except.pure, Except.bind] at accepted
    exact invokeFunction_preserves_all _ _ _ _ _ _ accepted property holds outer inputs


theorem leaveScope_preserves_all (machine : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition)
    (accepted : leaveScope machine parent invocation tail value = .ok after)
    (property : SemanticValue → Prop) (holds : All property machine)
    (tailHolds : ∀ child ∈ tail.flatMap frame, property child) (valueHolds : property value.value) :
    All property after.state := by
  have startHolds : All property { machine with scope := parent, invocation := invocation, stack := tail } := by
    simp only [All, state, List.mem_append] at holds ⊢
    grind only []
  simp only [leaveScope, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, store, moveOk, delivered, deliveredOk, rfl⟩ := accepted
  have middleHolds := temporary_preserves_all _ _ _ temporaryOk property startHolds
  have storeHolds := moveValues_preserves_all _ _ _ _ moveOk property middleHolds
  have deliveredHolds := finishTemporary_preserves_all _ _ _ deliveredOk property storeHolds valueHolds
  simp only [All, state, control, afterRelease, retainAt, List.mem_append, List.mem_singleton] at deliveredHolds ⊢
  grind only []

theorem leaveInvocation_preserves_all (machine : State) (after : Transition)
    (accepted : leaveInvocation machine = .ok after) (property : SemanticValue → Prop)
    (holds : All property machine) : All property after.state := by
  unfold leaveInvocation at accepted
  split at accepted <;> try contradiction
  rename_i value delivered
  split at accepted <;> try contradiction
  rename_i caller parent tail stacked
  apply leaveScope_preserves_all machine parent caller tail value after accepted property holds
  all_goals simp only [All, state, delivered, stacked, control, List.flatMap_cons, frame,
    List.nil_append, List.mem_append, List.mem_singleton] at holds
  all_goals grind only []


theorem scope_holdings_preserve_all (machine : State) (identity : LexicalScopeId) (record : Scope)
    (found : machine.heap.scopes[identity.value]? = some record)
    (property : SemanticValue → Prop) (holds : All property machine) :
    ∀ value ∈ record.holdings, property value.value := by
  have recordMember := List.mem_of_getElem? found
  intro value member
  apply holds
  simp only [state, heap, List.mem_append, List.mem_flatMap, List.mem_map]
  grind only []


theorem resumeRelease_preserves_all (machine : State) (after : AfterRelease)
    (property : SemanticValue → Prop) (holds : All property machine)
    (valuesHold : ∀ value ∈ afterRelease after, property value) : All property (resumeRelease machine after).state := by
  cases after <;> simp only [resumeRelease, All, state, control, afterRelease, List.mem_append] at holds valuesHold ⊢
  all_goals grind only []

end ValueInventory

/-- Calls, conditional control, authored failure, and aggregate elimination
preserve finite value typing through the actual source control dispatcher. -/
theorem executeControlTerm_preserves_value_shapes (machine : State) (context : Context) (after : Transition)
    (accepted : executeControlTerm machine context = .ok after)
    (typed : ValueInventory.All (ValueShape context.source.schemas) machine) :
    ValueInventory.All (ValueShape context.source.schemas) after.state := by
  unfold executeControlTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  have outer : ∀ binding ∈ bindings, ValueShape context.source.schemas binding.located.value := by
    intro binding member
    apply typed
    simp only [ValueInventory.state, executing, ValueInventory.control, ValueInventory.environment,
      List.mem_append, List.mem_map]
    grind only []
  have inputs : ∀ value ∈ operands, ValueShape context.source.schemas value.value := by
    intro value member
    apply typed
    simp only [ValueInventory.state, executing, ValueInventory.control, List.mem_append, List.mem_map]
    grind only []
  cases term <;> simp only at accepted <;> try contradiction
  case conditional condition yes no =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.environment,
      List.mem_append, List.mem_map] at typed ⊢
    grind only []
  case call function arguments =>
    cases accepted
    simpa only [ValueInventory.All, ValueInventory.state, executing, ValueInventory.control] using typed
  case apply function arguments =>
    split at accepted <;> try contradiction
    rename_i closure args operandsEqual
    exact ValueInventory.applyClosure_preserves_all machine context closure args after accepted _ typed
      (fun value member => inputs value (by simp [member]))
  case fail failure =>
    split at accepted <;> try contradiction
    rename_i value operandsEqual
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, rfl⟩ := accepted
    have failed := inputs value (by simp)
    simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, exitValues,
      List.append_nil, List.mem_append, List.mem_singleton] at typed ⊢
    grind only []
  case matchSum value cases =>
    split at accepted <;> try contradiction
    rename_i schema tag payload owner operandsEqual
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨⟨binder, body⟩, _, accepted⟩ := accepted
    have whole := inputs ⟨.variant schema tag payload, owner⟩ (by simp)
    have payloadTyped : ValueShape context.source.schemas payload := by cases whole; assumption
    exact ValueInventory.enterPattern_preserves_all machine context [binder] [payload] owner body bindings after
      accepted _ typed outer (by simpa using payloadTyped)
  case unpackProduct value vars body =>
    split at accepted <;> try contradiction
    rename_i schema fields owner operandsEqual
    have whole := inputs ⟨.product schema fields, owner⟩ (by simp)
    have fieldsTyped : ∀ child ∈ fields, ValueShape context.source.schemas child := by cases whole; assumption
    exact ValueInventory.enterPattern_preserves_all machine context vars fields owner body bindings after
      accepted _ typed outer fieldsTyped


end BoundaryV2.Profile.Source.Machine
