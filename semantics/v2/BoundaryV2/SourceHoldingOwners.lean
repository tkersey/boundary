import BoundaryV2.SourceScopeTreeExecution

namespace BoundaryV2.Profile.Source.Machine
namespace HoldingOwners

def Allocated (scope : Scope) (owner : Custody.Owner) : Prop :=
  ∃ index, index < scope.nextOwner ∧
    (owner = .lexical scope.id index ∨ owner = .temporary scope.id index)

def ValidScope (scope : Scope) : Prop :=
  (scope.holdings.map Located.owner).Nodup ∧
    ∀ value ∈ scope.holdings, Allocated scope value.owner

def Valid (heap : Heap) : Prop := ∀ scope ∈ heap.scopes, ValidScope scope

theorem allocated_mono (before after : Scope) (same : after.id = before.id)
    (grows : before.nextOwner ≤ after.nextOwner) (owner : Custody.Owner)
    (allocated : Allocated before owner) : Allocated after owner := by
  obtain ⟨index, bounded, located⟩ := allocated
  exact ⟨index, Nat.lt_of_lt_of_le bounded grows, by simpa only [same] using located⟩

theorem fresh_temporary (scope : Scope) (formed : ValidScope scope) (index : Nat)
    (fresh : scope.nextOwner ≤ index) : .temporary scope.id index ∉ scope.holdings.map Located.owner := by
  intro member
  obtain ⟨value, valueAt, owner⟩ := List.mem_map.mp member
  obtain ⟨slot, bounded, located⟩ := formed.2 value valueAt
  rcases located with located | located <;> rw [owner] at located
  · cases located
  · have same : index = slot := by simpa using located
    omega

theorem set_valid (before : Heap) (index : Nat) (replacement : Scope)
    (formed : Valid before) (newScope : ValidScope replacement) :
    Valid { before with scopes := before.scopes.set index replacement } := by
  intro scope member
  rcases List.mem_or_eq_of_mem_set member with member | rfl
  · exact formed scope member
  · exact newScope

theorem advance_valid (scope : Scope) (formed : ValidScope scope) (amount : Nat) :
    ValidScope {scope with nextOwner := scope.nextOwner + amount} := by
  refine ⟨formed.1, ?_⟩
  intro value member
  exact allocated_mono scope {scope with nextOwner := scope.nextOwner + amount} rfl (Nat.le_add_right _ _) _ (formed.2 value member)

theorem append_value_valid (scope : Scope) (value : Located)
    (formed : ValidScope scope) (allocated : Allocated scope value.owner)
    (fresh : value.owner ∉ scope.holdings.map Located.owner) :
    ValidScope {scope with holdings := scope.holdings ++ [value]} := by
  refine ⟨?_, ?_⟩
  · simp only [List.map_append, List.map_singleton]
    apply List.nodup_append.mpr ⟨formed.1, by simp, ?_⟩
    intro first firstAt last lastAt same
    cases List.mem_singleton.mp lastAt
    exact fresh (same ▸ firstAt)
  · intro child member
    rcases List.mem_append.mp member with member | member
    · exact formed.2 child member
    · cases List.mem_singleton.mp member; exact allocated

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

/-- Reservation advances the actual counter and leaves a slot absent from
all holdings in the current scope. -/
theorem temporary_valid (machine after : State) (owner : Custody.Owner)
    (accepted : temporary machine = .ok (after, owner)) (formed : Valid machine.heap) :
    Valid after.heap ∧ ∃ scope, after.heap.scopes[after.scope.value]? = some scope ∧
      Allocated scope owner ∧ owner ∉ scope.holdings.map Located.owner := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  rename_i record found
  split at accepted <;> try contradiction
  rename_i same
  have sameId : record.id = machine.scope := by simpa using same
  cases accepted
  have old := formed record (List.mem_of_getElem? found)
  have next := advance_valid record old 1
  refine ⟨set_valid _ _ _ formed next, {record with nextOwner := record.nextOwner + 1}, ?_, ?_, ?_⟩
  · simp only [List.getElem?_set_self (List.getElem?_eq_some_iff.mp found).choose]
  · exact ⟨record.nextOwner, Nat.lt_succ_self _, Or.inr (by simp [sameId])⟩
  · simpa only [sameId] using fresh_temporary record old record.nextOwner (Nat.le_refl _)

theorem finishTemporary_valid (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) (formed : Valid machine.heap)
    (ready : ∀ scope, machine.heap.scopes[machine.scope.value]? = some scope →
      Allocated scope value.owner ∧ value.owner ∉ scope.holdings.map Located.owner) : Valid after.state.heap := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  rename_i record found
  cases accepted
  exact set_valid _ _ _ formed (append_value_valid record value
    (formed record (List.mem_of_getElem? found)) (ready record found).1 (ready record found).2)

theorem retagged_owners_unique (values : List Located) (owner : Nat → Custody.Owner)
    (injective : ∀ i j, owner i = owner j → i = j) :
    ((values.mapIdx fun index value => retainAt value (owner index)).map Located.owner).Nodup := by
  apply List.pairwise_iff_getElem.mpr
  intro i j hi hj earlier same
  have equal : owner i = owner j := by simpa [retainAt] using same
  exact (Nat.ne_of_lt earlier) (injective i j equal)

theorem lexical_scope_valid (identity : LexicalScopeId) (invocation : InvocationId)
    (parent : Option LexicalScopeId) (values : List Located) (count : Nat) (enough : values.length ≤ count) :
    ValidScope ⟨identity, invocation, parent, count,
      values.mapIdx (fun index value => retainAt value (.lexical identity index))⟩ := by
  refine ⟨retagged_owners_unique values _ (by intro i j same; simpa using same), ?_⟩
  intro value member
  obtain ⟨index, bounded, rfl⟩ := List.exists_of_mem_mapIdx member
  exact ⟨index, Nat.lt_of_lt_of_le bounded enough, Or.inl rfl⟩

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

private theorem require_ok (condition : Bool) (reason : Invalid) (result : Unit)
    (accepted : require condition reason = .ok result) : condition = true := by
  unfold require at accepted
  split at accepted <;> first | assumption | contradiction

theorem createScope_valid (machine : State) (context : Context) (invocation : InvocationId)
    (parent : Option LexicalScopeId) (vars : List VariableId) (values : List Located)
    (bindings : Environment) (after : State × Environment)
    (accepted : createScope machine context invocation parent vars values bindings = .ok after)
    (formed : Valid machine.heap) : Valid after.1.heap := by
  simp only [createScope, bind, except_bind_ok] at accepted
  obtain ⟨_, checked, accepted⟩ := accepted
  have sameLength : vars.length = values.length := by
    have checked := require_ok _ _ _ checked
    simp only [bindArguments, Bool.and_eq_true, beq_iff_eq] at checked
    exact checked.1.1
  split at accepted
  · cases accepted; exact formed
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, heap, moved, rfl⟩ := accepted
    simp [moveValues, Option.bind_eq_some_iff] at moved
    obtain ⟨custody, _, rfl⟩ := moved
    intro scope member
    rcases List.mem_append.mp member with member | member
    · exact formed scope member
    · cases List.mem_singleton.mp member
      exact lexical_scope_valid _ _ _ _ _ (Nat.le_of_eq sameLength.symm)

/-- A reserved owner is a concrete unused slot in the current scope. This is
a proof parameter for atomic helper composition, not additional runtime state. -/
def Ready (machine : State) (owner : Custody.Owner) : Prop :=
  ∃ scope, machine.heap.scopes[machine.scope.value]? = some scope ∧
    Allocated scope owner ∧ owner ∉ scope.holdings.map Located.owner

theorem finish_reserved (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) (formed : Valid machine.heap)
    (ready : Ready machine value.owner) : Valid after.state.heap := by
  obtain ⟨scope, found, allocated, fresh⟩ := ready
  apply finishTemporary_valid _ _ _ accepted formed
  intro actual actualAt
  have same : actual = scope := Option.some.inj (actualAt.symm.trans found)
  subst actual
  exact ⟨allocated, fresh⟩

theorem scopedValue_valid (machine : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue machine value = .ok after) (formed : Valid machine.heap) : Valid after.state.heap := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, reserved, finished⟩ := accepted
  have ready := temporary_valid _ _ _ reserved formed
  exact finish_reserved _ _ _ finished ready.1 ready.2

theorem move_scopes (before after : Heap) (values : List Located) (owner : Nat → Custody.Owner)
    (accepted : moveValues before values owner = some after) : after.scopes = before.scopes := by
  simp only [moveValues, bind, Option.bind_eq_some_iff, pure, Option.some.injEq] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  rfl

theorem consume_scopes (before after : Heap) (value : Located)
    (accepted : consumeValue before value = some after) : after.scopes = before.scopes := by
  simp only [consumeValue, bind, Option.bind_eq_some_iff, pure, Option.some.injEq] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  rfl

theorem allocation_scopes (before after : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject before schema stored owner exclusive = some (after, value)) :
    after.scopes = before.scopes ∧ value.owner = owner := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, rfl⟩ := accepted; exact ⟨rfl, rfl⟩
  · obtain ⟨_, _, rfl, rfl⟩ := accepted; exact ⟨rfl, rfl⟩

theorem retire_scopes (before after : Heap) (value : Located)
    (accepted : retireObject before value = some after) : after.scopes = before.scopes := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, Option.bind_eq_some_iff, pure, Option.some.injEq] at accepted
  obtain ⟨_, _, middle, consumed, rfl⟩ := accepted
  exact consume_scopes before middle value consumed

theorem replace_scopes (before after : Heap) (node : NodeId) (stored : Object)
    (accepted : replaceObject before node stored = some after) : after.scopes = before.scopes := by
  unfold replaceObject at accepted
  split at accepted <;> try contradiction
  cases accepted; rfl

theorem invokeFunction_valid (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction machine context function bindings arguments = .ok after)
    (formed : Valid machine.heap) : Valid after.state.heap := by
  simp only [invokeFunction, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, ⟨middle, environment⟩, created, rfl⟩ := accepted
  exact createScope_valid _ _ _ _ _ _ _ _ created formed

theorem applyClosure_valid (machine : State) (context : Context) (closure : Located)
    (arguments : List Located) (after : Transition)
    (accepted : applyClosure machine context closure arguments = .ok after) (formed : Valid machine.heap) :
    Valid after.state.heap := by
  simp only [applyClosure, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, object⟩, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  · simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨heap, retired, applied⟩ := accepted
    apply invokeFunction_valid _ _ _ _ _ _ applied
    simpa only [Valid, retire_scopes _ _ _ retired] using formed
  · exact invokeFunction_valid _ _ _ _ _ _ accepted formed

theorem makeClosureWithValues_valid (machine : State) (context : Context)
    (schema : SchemaId .source) (function : FunctionId .source) (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues machine context schema function values = .ok after)
    (formed : Valid machine.heap) : Valid after.state.heap := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, ⟨middle, owner⟩, reserved, moved, movedAt, ⟨heap, result⟩, allocated, finished⟩ := accepted
  have ready := temporary_valid _ _ _ reserved formed
  have movedScopes := move_scopes _ _ _ _ movedAt
  have allocatedFields := allocation_scopes _ _ _ _ _ _ _ allocated
  apply finish_reserved _ _ _ finished
  · simpa only [Valid, allocatedFields.1, movedScopes] using ready.1
  · simpa only [Ready, allocatedFields.1, allocatedFields.2, movedScopes] using ready.2

theorem commitPure_valid (machine : State) (opcode : Opcode) (operands : List Located)
    (result : SemanticValue) (after : Transition)
    (accepted : commitPure machine opcode operands result = .ok after) (formed : Valid machine.heap) :
    Valid after.state.heap := by
  simp only [commitPure, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, reserved, accepted⟩ := accepted
  have ready := temporary_valid _ _ _ reserved formed
  split at accepted
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, _, _, _, finished⟩ := accepted
    exact finish_reserved _ _ _ finished ready.1 ready.2
  · simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨heap, moved, _, _, custody, _, finished⟩ := accepted
    have same := move_scopes _ _ _ _ moved
    apply finish_reserved _ _ _ finished
    · simpa only [Valid, same] using ready.1
    · simpa only [Ready, same] using ready.2

private theorem mapM_output (function : α → Except Invalid β) (inputs : List α) (outputs : List β)
    (accepted : inputs.mapM function = .ok outputs) (output : β) (member : output ∈ outputs) :
    ∃ input ∈ inputs, function input = .ok output := by
  induction inputs generalizing outputs with
  | nil => cases accepted; simp at member
  | cons head tail induction =>
    simp only [List.mapM_cons, bind, except_bind_ok] at accepted
    obtain ⟨first, firstAt, rest, restAt, accepted⟩ := accepted
    cases accepted
    rcases List.mem_cons.mp member with equal | belongs
    · cases equal; exact ⟨head, by simp, firstAt⟩
    · obtain ⟨input, inputMember, checked⟩ := induction rest restAt belongs
      exact ⟨input, by simp [inputMember], checked⟩

theorem instantiateCapture_valid (machine : State) (context : Context) (saved : Capture) (after : State × Capture)
    (formed : Valid machine.heap) (accepted : instantiateCapture machine context saved = .ok after) :
    Valid after.1.heap := by
  unfold instantiateCapture at accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨scopeRows, scopeRowsAt, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  cases accepted
  intro scope member
  rcases List.mem_append.mp member with old | copied
  · exact formed scope old
  · obtain ⟨originalId, _, checked⟩ := mapM_output _ _ _ scopeRowsAt scope copied
    simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at checked
    obtain ⟨original, originalAt, rfl⟩ := checked
    simp [ValidScope]

theorem inherit_valid (scope : Scope) (values : List Located) (formed : ValidScope scope) :
    ValidScope {scope with
      nextOwner := scope.nextOwner + values.length
      holdings := (values.mapIdx fun index value => retainAt value (.temporary scope.id (scope.nextOwner + index))) ++ scope.holdings} := by
  refine ⟨?_, ?_⟩
  · simp only [List.map_append]
    apply List.nodup_append.mpr
    refine ⟨retagged_owners_unique values _ (by intro i j same; simp only [Custody.Owner.temporary.injEq] at same; omega), formed.1, ?_⟩
    intro first firstAt last lastAt equal
    obtain ⟨value, valueAt, owner⟩ := List.mem_map.mp firstAt
    obtain ⟨index, bounded, rfl⟩ := List.exists_of_mem_mapIdx valueAt
    have forbidden := fresh_temporary scope formed (scope.nextOwner + index) (Nat.le_add_right _ _)
    apply forbidden
    have same : last = .temporary scope.id (scope.nextOwner + index) := (owner.trans equal).symm
    exact same ▸ lastAt
  · intro value member
    rcases List.mem_append.mp member with inherited | old
    · obtain ⟨index, bounded, rfl⟩ := List.exists_of_mem_mapIdx inherited
      exact ⟨scope.nextOwner + index, Nat.add_lt_add_left bounded _, Or.inr rfl⟩
    · exact allocated_mono scope {scope with
        nextOwner := scope.nextOwner + values.length
        holdings := (values.mapIdx fun index value => retainAt value (.temporary scope.id (scope.nextOwner + index))) ++ scope.holdings}
        rfl (Nat.le_add_right _ _) value.owner (formed.2 value old)

theorem leaveScope_valid (machine : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition) (formed : Valid machine.heap)
    (accepted : leaveScope machine parent invocation tail value = .ok after) : Valid after.state.heap := by
  simp only [leaveScope, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, heap, moved, delivered, finished, rfl⟩ := accepted
  have ready := temporary_valid _ _ _ temporaryOk formed
  have same := move_scopes _ _ _ _ moved
  apply finish_reserved _ _ _ finished
  · simpa only [Valid, same] using ready.1
  · simpa only [Ready, same, retainAt] using ready.2

theorem leaveLexical_valid (machine : State) (after : Transition) (formed : Valid machine.heap)
    (indexed : machine.heap.Indexed) (accepted : leaveLexical machine = .ok after) : Valid after.state.heap := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, record, _, parent, _, result, left, accepted⟩ := accepted
  have next := leaveScope_valid _ _ _ _ _ _ formed left
  have nextIndexed := leaveScope_indexed _ _ _ _ _ _ left indexed
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨parentRecord, parentAt, heap, moved, rfl⟩ := accepted
  have sameScopes := move_scopes _ _ _ _ moved
  have parentId : parentRecord.id = parent := by
    have same := nextIndexed.scope_identity parentAt
    cases identity : parentRecord.id
    cases parent
    simpa [identity] using same
  apply set_valid heap parent.value _
  · simpa only [Valid, sameScopes] using next
  · simpa only [parentId] using inherit_valid parentRecord _ (next parentRecord (List.mem_of_getElem? parentAt))

end HoldingOwners
end BoundaryV2.Profile.Source.Machine
