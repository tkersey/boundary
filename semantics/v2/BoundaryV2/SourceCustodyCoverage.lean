import BoundaryV2.SourceOwningQueues

namespace BoundaryV2.Profile.Source.Machine
namespace CustodyCoverage

/-- Every book entry has a concrete token occurrence at its named owner.
Temporary proof inventories may add in-transit values during one atomic rule. -/
def Covered (book : Custody.Book) (values : List Located) : Prop :=
  ∀ entry ∈ book.entries, ∃ value ∈ values,
    value.owner = entry.owner ∧ entry.token ∈ ownedTokens value.value

def fields (machine : State) : List Located := OwningFields.heap machine.heap ++ QueueCustody.fields machine

def Valid (machine : State) : Prop := Covered machine.heap.custody (fields machine)

theorem Covered.mono (book : Custody.Book) (before after : List Located)
    (valid : Covered book before) (included : before ⊆ after) : Covered book after := by
  intro entry member
  obtain ⟨value, valueAt, ownerAt, tokenAt⟩ := valid entry member
  exact ⟨value, included valueAt, ownerAt, tokenAt⟩

theorem Covered.subbook (before after : Custody.Book) (values : List Located)
    (valid : Covered before values) (included : after.entries ⊆ before.entries) : Covered after values :=
  fun entry member => valid entry (included member)

theorem consume_covered (before after : Custody.Book) (removed : List CustodyToken) (owner : Custody.Owner)
    (values : List Located) (accepted : Custody.consume before removed owner = some after)
    (valid : Covered before values) : Covered after values := by
  unfold Custody.consume at accepted
  split at accepted <;> try contradiction
  cases accepted
  exact Covered.subbook _ _ _ valid (fun _ member => (List.mem_filter.mp member).1)

theorem commit_covered (before after : Custody.Book) (moves : List Custody.Move) (values added : List Located)
    (accepted : Custody.commit before moves = some after) (valid : Covered before values)
    (destinations : ∀ move ∈ moves, ∃ value ∈ added,
      value.owner = move.target ∧ move.token ∈ ownedTokens value.value) : Covered after (values ++ added) := by
  unfold Custody.commit at accepted
  split at accepted <;> try contradiction
  cases accepted
  intro entry member
  obtain ⟨original, originalAt, rfl⟩ := List.mem_map.mp member
  cases selected : moves.find? (fun move => move.token == original.token) with
  | none =>
    obtain ⟨value, valueAt, ownerAt, tokenAt⟩ := valid original originalAt
    exact ⟨value, List.mem_append_left _ valueAt, by simpa [Custody.destination, selected] using ownerAt,
      by simpa [Custody.destination, selected] using tokenAt⟩
  | some move =>
    have moveAt := List.mem_of_find?_eq_some selected
    have tokenAt : move.token = original.token := by simpa using List.find?_some selected
    obtain ⟨value, valueAt, ownerAt, owned⟩ := destinations move moveAt
    exact ⟨value, List.mem_append_right _ valueAt, by simpa [Custody.destination, selected] using ownerAt,
      by simpa only [Custody.destination_token, ← tokenAt] using owned⟩

theorem moveValues_covered (before after : Heap) (values moving : List Located) (receiver : Nat → Custody.Owner)
    (accepted : moveValues before moving receiver = some after) (valid : Covered before.custody values) :
    Covered after.custody (values ++ moving.mapIdx (fun index value => retainAt value (receiver index))) := by
  simp only [moveValues, bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨book, committed, rfl⟩ := accepted
  apply commit_covered _ _ _ _ _ committed valid
  intro move member
  obtain ⟨list, listAt, moveAt⟩ := List.mem_flatten.mp member
  obtain ⟨index, bounded, rfl⟩ := List.mem_mapIdx.mp listAt
  obtain ⟨token, tokenAt, rfl⟩ := List.mem_map.mp moveAt
  refine ⟨retainAt moving[index] (receiver index), ?_, rfl, tokenAt⟩
  exact List.mem_mapIdx.mpr ⟨index, bounded, rfl⟩

private theorem filter_congr (values : List α) (first second : α → Bool)
    (same : ∀ value ∈ values, first value = second value) : values.filter first = values.filter second := by
  induction values with
  | nil => rfl
  | cons value values induction =>
    simp only [List.filter_cons, same value (by simp), induction (fun child member => same child (List.mem_cons_of_mem _ member))]

theorem queue_fields_equal (machine : State) (owners : OwnerLocations.Valid machine) (leaves : DisposalShape.Valid machine) :
    OwningFields.queueFields machine = QueueCustody.fields machine := by
  rw [OwningFields.queue_fields_exact]
  apply filter_congr
  intro value member
  by_cases closed : QueueCustody.closureOwner value.owner = true
  · obtain ⟨node, index, ownerAt, _, absent⟩ := QueueCustody.fields_retired machine owners leaves value
      (List.mem_filter.mpr ⟨member, closed⟩)
    simp [OwningFields.detached, ownerAt, absent, QueueCustody.closureOwner]
  · cases ownerAt : value.owner <;> simp_all [OwningFields.detached, QueueCustody.closureOwner]

theorem fields_equal (machine : State) (owners : OwnerLocations.Valid machine) (leaves : DisposalShape.Valid machine) :
    fields machine = OwningFields.state machine := by
  rw [fields, ← queue_fields_equal machine owners leaves]
  simp only [OwningFields.state, OwningFields.queueFields, List.append_assoc]

theorem entries_cover_book (book : Custody.Book) (values : List Located) (valid : Covered book values)
    (aligned : ∀ entry ∈ values.flatMap (OwningFields.live book), entry ∈ book.entries) :
    book.entries ⊆ values.flatMap (OwningFields.live book) := by
  intro entry entryAt
  obtain ⟨value, valueAt, ownerAt, tokenAt⟩ := valid entry entryAt
  rw [← ownedReferences_tokens value.value] at tokenAt
  obtain ⟨pair, pairAt, sameToken⟩ := List.mem_map.mp tokenAt
  have held : Custody.has book pair.1 value.owner = true := by
    apply List.any_eq_true.mpr
    exact ⟨entry, entryAt, by simp [sameToken, ownerAt]⟩
  let candidate : Custody.Entry := ⟨pair.1, pair.2, value.owner⟩
  have live : candidate ∈ OwningFields.live book value :=
    List.mem_map.mpr ⟨pair, List.mem_filter.mpr ⟨pairAt, held⟩, rfl⟩
  have listed : candidate ∈ values.flatMap (OwningFields.live book) := List.mem_flatMap.mpr ⟨value, valueAt, live⟩
  have same := Custody.token_identifies_entry book candidate entry (aligned candidate listed) entryAt sameToken
  exact same ▸ listed

theorem reachable_entries_cover_book_of_coverage (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) (covered : Valid after) :
    after.heap.custody.entries ⊆ OwningFields.entries after := by
  have owners := OwnerLocations.initialized_execution_preserves_owner_locations _ _ _ _ _ initialized steps
  have leaves := DisposalShape.initialized_execution_preserves_disposal_leaves _ _ _ _ _ initialized steps
  have covered : Covered after.heap.custody (OwningFields.state after) :=
    (fields_equal after owners leaves) ▸ covered
  exact entries_cover_book _ _ covered
    (OwningFields.reachable_entries_in_book _ _ _ _ _ initialized steps)

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

theorem initial_valid (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) : Valid machine := by
  simp only [initial, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ := accepted
  simp [Valid, Covered, Custody.empty]

private theorem flatMap_set_same (values : List α) (index : Nat) (replacement original : α)
    (f : α → List β) (found : values[index]? = some original) (same : f replacement = f original) :
    (values.set index replacement).flatMap f = values.flatMap f := by
  induction values generalizing index with
  | nil => simp at found
  | cons value values induction =>
    cases index with
    | zero => cases found; simp [same]
    | succ index => simpa only [List.set_cons_succ, List.flatMap_cons] using congrArg (f value ++ ·) (induction index found)

theorem temporary_fields (machine after : State) (owner : Custody.Owner)
    (accepted : temporary machine = .ok (after, owner)) :
    fields after = fields machine ∧ after.heap.custody = machine.heap.custody := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  rename_i scope scopeAt
  split at accepted <;> try contradiction
  cases accepted
  constructor
  · have same := flatMap_set_same machine.heap.scopes machine.scope.value
      {scope with nextOwner := scope.nextOwner + 1} scope Scope.holdings scopeAt rfl
    simp only [fields, OwningFields.heap, same, QueueCustody.fields_components, QueueCustody.heapFields]
  · rfl

theorem temporary_covered (machine after : State) (owner : Custody.Owner) (extra : List Located)
    (accepted : temporary machine = .ok (after, owner))
    (valid : Covered machine.heap.custody (fields machine ++ extra)) :
    Covered after.heap.custody (fields after ++ extra) := by
  obtain ⟨same, book⟩ := temporary_fields _ _ _ accepted
  simpa only [same, book] using valid

private theorem flatMap_set_mono (values : List α) (index : Nat) (replacement original : α)
    (f : α → List β) (found : values[index]? = some original) (included : f original ⊆ f replacement) :
    values.flatMap f ⊆ (values.set index replacement).flatMap f := by
  induction values generalizing index with
  | nil => simp at found
  | cons value values induction =>
    cases index with
    | zero =>
      cases found
      intro child member
      rcases List.mem_append.mp member with originalAt | tailAt
      · exact List.mem_append_left _ (included originalAt)
      · exact List.mem_append_right _ tailAt
    | succ index =>
      intro child member
      rcases List.mem_append.mp member with first | rest
      · exact List.mem_append_left _ first
      · exact List.mem_append_right _ (induction index found rest)

theorem finishTemporary_fields (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) (empty : QueueCustody.controlFields machine.control = []) :
    after.state.heap.custody = machine.heap.custody ∧ fields machine ⊆ fields after.state ∧ value ∈ fields after.state := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  rename_i scope scopeAt
  cases accepted
  let updated := {scope with holdings := scope.holdings ++ [value]}
  have holdingSubset := flatMap_set_mono machine.heap.scopes machine.scope.value updated scope Scope.holdings scopeAt
    (fun _ member => List.mem_append_left _ member)
  have bounded := (List.getElem?_eq_some_iff.mp scopeAt).1
  have updatedAt : updated ∈ machine.heap.scopes.set machine.scope.value updated :=
    List.mem_of_getElem? (List.getElem?_set_self bounded)
  refine ⟨rfl, ?_, ?_⟩
  · intro field member
    simp only [fields, OwningFields.heap, List.mem_append] at member ⊢
    rcases member with ((object | protection) | holding) | queued
    · exact Or.inl (Or.inl (Or.inl object))
    · exact Or.inl (Or.inl (Or.inr protection))
    · exact Or.inl (Or.inr (holdingSubset holding))
    · right
      rw [QueueCustody.fields_components, empty, List.nil_append] at queued
      simpa only [QueueCustody.fields_components, QueueCustody.heapFields, finishValue,
        QueueCustody.controlFields, DisposalShape.control, List.filter_nil, List.nil_append] using queued
  · apply List.mem_append_left
    apply List.mem_append_right
    exact List.mem_flatMap.mpr ⟨updated, updatedAt, List.mem_append_right _ (by simp)⟩

theorem finishTemporary_covered (machine : State) (value : Located) (extra : List Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) (empty : QueueCustody.controlFields machine.control = [])
    (valid : Covered machine.heap.custody (fields machine ++ value :: extra)) :
    Covered after.state.heap.custody (fields after.state ++ extra) := by
  obtain ⟨book, prior, held⟩ := finishTemporary_fields _ _ _ accepted empty
  rw [book]
  apply Covered.mono _ _ _ valid
  intro field member
  rcases List.mem_append.mp member with old | added
  · exact List.mem_append_left _ (prior old)
  · rcases List.mem_cons.mp added with rfl | rest
    · exact List.mem_append_left _ held
    · exact List.mem_append_right _ rest

theorem commit_transit_covered (before after : Custody.Book) (moves : List Custody.Move)
    (values transit added : List Located) (accepted : Custody.commit before moves = some after)
    (valid : Covered before (values ++ transit))
    (destinations : ∀ move ∈ moves, ∃ value ∈ added,
      value.owner = move.target ∧ move.token ∈ ownedTokens value.value)
    (transferred : ∀ value ∈ transit, ∀ token ∈ ownedTokens value.value, ∃ move ∈ moves, move.token = token) :
    Covered after (values ++ added) := by
  unfold Custody.commit at accepted
  split at accepted <;> try contradiction
  cases accepted
  intro entry member
  obtain ⟨original, originalAt, rfl⟩ := List.mem_map.mp member
  cases selected : moves.find? (fun move => move.token == original.token) with
  | none =>
    obtain ⟨value, valueAt, ownerAt, tokenAt⟩ := valid original originalAt
    rcases List.mem_append.mp valueAt with old | moving
    · exact ⟨value, List.mem_append_left _ old, by simpa [Custody.destination, selected] using ownerAt,
        by simpa [Custody.destination, selected] using tokenAt⟩
    · obtain ⟨move, moveAt, same⟩ := transferred value moving original.token tokenAt
      have absent := List.find?_eq_none.mp selected move moveAt
      simp [same] at absent
  | some move =>
    have moveAt := List.mem_of_find?_eq_some selected
    have tokenAt : move.token = original.token := by simpa using List.find?_some selected
    obtain ⟨value, valueAt, ownerAt, owned⟩ := destinations move moveAt
    exact ⟨value, List.mem_append_right _ valueAt, by simpa [Custody.destination, selected] using ownerAt,
      by simpa only [Custody.destination_token, ← tokenAt] using owned⟩

theorem moveValues_transit_covered (before after : Heap) (values moving : List Located) (receiver : Nat → Custody.Owner)
    (accepted : moveValues before moving receiver = some after) (valid : Covered before.custody (values ++ moving)) :
    Covered after.custody (values ++ moving.mapIdx (fun index value => retainAt value (receiver index))) := by
  simp only [moveValues, bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨book, committed, rfl⟩ := accepted
  apply commit_transit_covered _ _ _ _ _ _ committed valid
  · intro move member
    obtain ⟨list, listAt, moveAt⟩ := List.mem_flatten.mp member
    obtain ⟨index, bounded, rfl⟩ := List.mem_mapIdx.mp listAt
    obtain ⟨token, tokenAt, rfl⟩ := List.mem_map.mp moveAt
    refine ⟨retainAt moving[index] (receiver index), ?_, rfl, tokenAt⟩
    exact List.mem_mapIdx.mpr ⟨index, bounded, rfl⟩
  · intro value member token tokenAt
    obtain ⟨index, bounded, rfl⟩ := List.mem_iff_getElem.mp member
    refine ⟨⟨token, moving[index].owner, receiver index⟩, ?_, rfl⟩
    apply List.mem_flatten.mpr
    refine ⟨_, List.mem_mapIdx.mpr ⟨index, bounded, rfl⟩, ?_⟩
    exact List.mem_map.mpr ⟨token, tokenAt, rfl⟩

theorem Covered.drop_free (book : Custody.Book) (values free : List Located)
    (valid : Covered book (values ++ free)) (empty : ∀ value ∈ free, ownedTokens value.value = []) : Covered book values := by
  intro entry member
  obtain ⟨value, valueAt, ownerAt, tokenAt⟩ := valid entry member
  rcases List.mem_append.mp valueAt with prior | added
  · exact ⟨value, prior, ownerAt, tokenAt⟩
  · simp [empty value added] at tokenAt

theorem move_fields (machine : State) (heap : Heap) (values : List Located) (receiver : Nat → Custody.Owner)
    (accepted : moveValues machine.heap values receiver = some heap) : fields {machine with heap := heap} = fields machine := by
  simp only [moveValues, bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  rfl

theorem append_scope_fields (machine : State) (scope : Scope) :
    fields machine ⊆ fields {machine with heap := {machine.heap with scopes := machine.heap.scopes ++ [scope]}} ∧
    scope.holdings ⊆ fields {machine with heap := {machine.heap with scopes := machine.heap.scopes ++ [scope]}} := by
  constructor
  · intro value member
    simp only [fields, OwningFields.heap, QueueCustody.fields_components, QueueCustody.heapFields,
      List.flatMap_append, List.flatMap_cons, List.flatMap_nil, List.append_nil, List.mem_append] at member ⊢
    grind only []
  · intro value member
    apply List.mem_append_left
    apply List.mem_append_right
    exact List.mem_flatMap.mpr ⟨scope, by simp, member⟩

theorem append_scope_covered (machine : State) (scope : Scope) (extra : List Located)
    (valid : Covered machine.heap.custody (fields machine ++ scope.holdings ++ extra)) :
    Covered machine.heap.custody
      (fields {machine with heap := {machine.heap with scopes := machine.heap.scopes ++ [scope]}} ++ extra) := by
  apply Covered.mono _ _ _ valid
  intro value member
  rcases List.mem_append.mp member with prior | rest
  · apply List.mem_append_left
    rcases List.mem_append.mp prior with old | added
    · exact (append_scope_fields machine scope).1 old
    · exact (append_scope_fields machine scope).2 added
  · exact List.mem_append_right _ rest

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem createScope_valid (machine : State) (context : Context) (invocation : InvocationId)
    (parent : Option LexicalScopeId) (vars : List VariableId) (values : List Located)
    (bindings : Environment) (after : State × Environment)
    (accepted : createScope machine context invocation parent vars values bindings = .ok after)
    (valid : Covered machine.heap.custody (fields machine ++ values)) : Valid after.1 := by
  simp only [createScope, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · rename_i reused
    have free := (Bool.and_eq_true_iff.mp reused).2
    cases accepted
    exact Covered.drop_free _ _ _ valid (fun value member => List.nil_of_isEmpty (List.all_eq_true.mp free value member))
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, heap, moved, rfl⟩ := accepted
    have movedCover := moveValues_transit_covered _ _ _ _ _ moved valid
    rw [← move_fields _ _ _ _ moved] at movedCover
    let identity : LexicalScopeId := ⟨machine.heap.nextScope⟩
    let relocated := values.mapIdx (fun index value => retainAt value (.lexical identity index))
    let scope : Scope := ⟨identity, invocation, parent, vars.length, relocated⟩
    have next := append_scope_covered {machine with heap := heap} scope [] (by simpa using movedCover)
    simpa only [Valid, List.append_nil, fields, OwningFields.heap, QueueCustody.fields_components, QueueCustody.heapFields, scope, relocated, identity] using next

theorem allocateObject_covered (before after : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (value : Located) (values : List Located)
    (accepted : allocateObject before schema stored owner exclusive = some (after, value))
    (valid : Covered before.custody values) : Covered after.custody (values ++ [value]) := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, rfl⟩ := accepted
    exact Covered.mono _ _ _ valid (fun _ member => List.mem_append_left _ member)
  · obtain ⟨book, allocated, rfl, rfl⟩ := accepted
    have entries := (Custody.allocation_is_fresh _ _ _ _ _ allocated).2.2
    intro entry member
    rw [entries] at member
    rcases List.mem_cons.mp member with rfl | prior
    · refine ⟨⟨.reference schema ⟨before.objects.length⟩ (some ⟨before.nextCustody⟩), owner⟩,
        List.mem_append_right _ (by simp), rfl, ?_⟩
      simp [ownedTokens]
    · obtain ⟨field, fieldAt, ownerAt, tokenAt⟩ := valid entry prior
      exact ⟨field, List.mem_append_left _ fieldAt, ownerAt, tokenAt⟩

theorem temporary_control (machine after : State) (owner : Custody.Owner)
    (accepted : temporary machine = .ok (after, owner)) : after.control = machine.control := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  rfl

theorem scopedValue_valid (machine : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue machine value = .ok after) (valid : Valid machine)
    (empty : QueueCustody.controlFields machine.control = []) : Valid after.state := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, reserved, finished⟩ := accepted
  have next := temporary_covered machine middle owner [] reserved (by simpa [Valid] using valid)
  have incoming : Covered middle.heap.custody (fields middle ++ [Located.mk value owner]) :=
    Covered.mono _ _ _ (by simpa using next) (fun _ member => List.mem_append_left _ member)
  have done := finishTemporary_covered middle ⟨value, owner⟩ [] after finished
    (by simpa only [temporary_control _ _ _ reserved] using empty) incoming
  simpa only [Valid, List.append_nil] using done

theorem createScope_control_stack (machine : State) (context : Context) (invocation : InvocationId)
    (parent : Option LexicalScopeId) (vars : List VariableId) (values : List Located)
    (bindings : Environment) (after : State × Environment)
    (accepted : createScope machine context invocation parent vars values bindings = .ok after) :
    after.1.control = machine.control ∧ after.1.stack = machine.stack := by
  simp only [createScope, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · cases accepted; exact ⟨rfl, rfl⟩
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    exact ⟨rfl, rfl⟩

theorem invokeFunction_covered (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments captured : List Located) (after : Transition)
    (capturedAt : (Analysis.captures context.captures function).mapM
      (fun binder => fromOption (lookupVariable bindings binder) .reference) = .ok captured)
    (accepted : invokeFunction machine context function bindings arguments = .ok after)
    (covered : Covered machine.heap.custody (fields machine ++ (captured ++ arguments)))
    (empty : QueueCustody.controlFields machine.control = []) : Valid after.state := by
  simp only [invokeFunction, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨definition, _, body, _, actualCaptured, actualAt, _, _, _, _, ⟨middle, entered⟩, created, rfl⟩ := accepted
  rw [capturedAt] at actualAt
  cases actualAt
  have next := createScope_valid _ _ _ _ _ _ _ _ created covered
  have same := createScope_control_stack _ _ _ _ _ _ _ _ created
  have controlSame : middle.control = machine.control := same.1
  have controlEmpty : QueueCustody.controlFields middle.control = [] := by rw [controlSame]; exact empty
  have stackSame : middle.stack = machine.stack := same.2
  simp only [Valid, fields, OwningFields.heap, QueueCustody.fields_components, QueueCustody.heapFields,
    controlEmpty, List.nil_append, stackSame] at next
  simpa only [Valid, fields, OwningFields.heap, QueueCustody.fields_components, QueueCustody.heapFields,
    QueueCustody.controlFields, QueueCustody.frameFields, DisposalShape.control, DisposalShape.frame,
    List.filter_nil, List.flatMap_cons, List.nil_append] using next

theorem invokeFunction_valid (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction machine context function bindings arguments = .ok after) (valid : Valid machine)
    (empty : QueueCustody.controlFields machine.control = []) : Valid after.state := by
  have acceptedCopy := accepted
  simp only [invokeFunction, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at acceptedCopy
  obtain ⟨_, _, _, _, captured, capturedAt, _⟩ := acceptedCopy
  apply invokeFunction_covered _ _ _ _ _ captured _ capturedAt accepted ?_ empty
  exact Covered.mono _ _ _ valid (fun _ member => List.mem_append_left _ member)

end CustodyCoverage
end BoundaryV2.Profile.Source.Machine
