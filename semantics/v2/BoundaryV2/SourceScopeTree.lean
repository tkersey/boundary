import BoundaryV2.SourceIdentityExecution
import BoundaryV2.SourceInitialLaws

namespace BoundaryV2.Profile.Source.Machine
namespace ScopeTree

/-- A lexical parent is strictly lower in a mathematical rank. Allocation
indices need not follow parent order after capture cloning. -/
def Ranked (rank : LexicalScopeId → Nat) (scopes : List Scope) : Prop :=
  ∀ scope ∈ scopes, ∀ parent ∈ scope.parent, rank parent < rank scope.id

def Valid (heap : Heap) : Prop := ∃ rank, Ranked rank heap.scopes

def Bounds (heap : Heap) : Prop := ∀ scope ∈ heap.scopes,
  scope.id.value < heap.nextScope ∧ ∀ parent ∈ scope.parent, parent.value < heap.nextScope

def Formed (heap : Heap) : Prop := Bounds heap ∧ Valid heap

theorem bounds_of_identity (bounded : IdentitySupport.Valid machine) : Bounds machine.heap :=
  fun scope member => ⟨(bounded.heap.scopes scope member).1, (bounded.heap.scopes scope member).2.2⟩

theorem ranked_set (rank : LexicalScopeId → Nat) (scopes : List Scope) (index : Nat)
    (old fresh : Scope) (found : scopes[index]? = some old)
    (sameId : fresh.id = old.id) (sameParent : fresh.parent = old.parent)
    (ranked : Ranked rank scopes) : Ranked rank (scopes.set index fresh) := by
  intro scope member parent parentAt
  rcases List.mem_or_eq_of_mem_set member with member | equal
  · exact ranked scope member parent parentAt
  · subst scope
    rw [sameId]
    exact ranked old (List.mem_of_getElem? found) parent (sameParent ▸ parentAt)

theorem set_valid (before : Heap) (index : Nat) (old fresh : Scope)
    (found : before.scopes[index]? = some old)
    (sameId : fresh.id = old.id) (sameParent : fresh.parent = old.parent)
    (valid : Valid before) : Valid { before with scopes := before.scopes.set index fresh } := by
  obtain ⟨rank, ranked⟩ := valid
  exact ⟨rank, ranked_set _ _ _ _ _ found sameId sameParent ranked⟩

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

private theorem ref_eq {left right : Ref space domain} (same : left.value = right.value) : left = right := by
  cases left; cases right
  simpa only [Ref.mk.injEq] using same

private theorem dedup_length_le [BEq α] [LawfulBEq α] (values : List α) : values.eraseDups.length ≤ values.length := by
  cases values with
  | nil => simp
  | cons head tail =>
    rw [List.eraseDups_cons]
    have smaller := dedup_length_le (tail.filter (fun value => !value == head))
    have filtered := List.length_filter_le (fun value => !value == head) tail
    simp only [List.length_cons]
    omega
termination_by values.length
decreasing_by
  have bound := List.length_filter_le (fun value => !value == head) tail
  simp_wf
  omega

/-- A fresh scope extends the ranking even when its parent is not the most
recent allocation. Existing scope records retain their ranks. -/
theorem append_fresh (heap : Heap) (record : Scope)
    (fresh : record.id.value = heap.nextScope)
    (oldIds : ∀ scope ∈ heap.scopes, scope.id.value < heap.nextScope)
    (oldParents : ∀ scope ∈ heap.scopes, ∀ parent ∈ scope.parent, parent.value < heap.nextScope)
    (parentOld : ∀ parent ∈ record.parent, parent.value < heap.nextScope)
    (valid : Valid heap) : Valid { heap with scopes := heap.scopes ++ [record] } := by
  obtain ⟨rank, ranked⟩ := valid
  let level := (record.parent.map rank).getD 0 + 1
  let nextRank := fun identity => if identity = record.id then level else rank identity
  have unchanged (identity : LexicalScopeId) (bounded : identity.value < heap.nextScope) :
      nextRank identity = rank identity := by
    have different : identity ≠ record.id := by intro equal; rw [equal, fresh] at bounded; omega
    simp [nextRank, different]
  refine ⟨nextRank, ?_⟩
  intro scope member parent parentAt
  rcases List.mem_append.mp member with old | new
  · rw [unchanged scope.id (oldIds scope old), unchanged parent (oldParents scope old parent parentAt)]
    exact ranked scope old parent parentAt
  · cases List.mem_singleton.mp new
    rw [unchanged parent (parentOld parent parentAt)]
    have atParent : record.parent = some parent := by simpa using parentAt
    simp [nextRank, level, atParent]

/-- Extend a rank through the actual finite fresh map by looking up its inverse.
Only freshly mapped identities change; outside identities keep their ranks. -/
def clonedRank (start : Nat) (identities : List LexicalScopeId) (rank : LexicalScopeId → Nat)
    (identity : LexicalScopeId) : Nat :=
  rank (((freshMap .runtime .lexicalScope start identities).find? (fun pair => pair.2 == identity)).map Prod.fst |>.getD identity)

theorem clonedRank_old (start : Nat) (identities : List LexicalScopeId) (rank : LexicalScopeId → Nat)
    (identity : LexicalScopeId) (old : identity.value < start) : clonedRank start identities rank identity = rank identity := by
  have absent : (freshMap .runtime .lexicalScope start identities).find? (fun pair => pair.2 == identity) = none := by
    apply List.find?_eq_none.mpr
    intro pair member
    have lower := (fresh_map_member _ _ _ _ _ _ member).2.1
    have different : pair.2 ≠ identity := by intro equal; rw [equal] at lower; omega
    simpa using different
  simp [clonedRank, absent]

theorem clonedRank_renamed (start : Nat) (identities : List LexicalScopeId) (rank : LexicalScopeId → Nat)
    (identity : LexicalScopeId) (old : identity.value < start) :
    clonedRank start identities rank (renamed (freshMap .runtime .lexicalScope start identities) identity) = rank identity := by
  by_cases member : identity ∈ identities
  · have mapped := renamed_inside_fresh_map .runtime .lexicalScope start identities identity member
    cases found : (freshMap .runtime .lexicalScope start identities).find?
        (fun pair => pair.2 == renamed (freshMap .runtime .lexicalScope start identities) identity) with
    | none =>
      have absent := List.find?_eq_none.mp found _ mapped
      simp at absent
    | some pair =>
      have equal : pair.2 = renamed (freshMap .runtime .lexicalScope start identities) identity := by
        simpa using List.find?_some found
      have belongs := List.mem_of_find?_eq_some found
      have same := fresh_map_targets_identify_sources .runtime .lexicalScope start identities
        pair.1 identity pair.2 belongs (equal ▸ mapped)
      simp [clonedRank, found, same]
  · rw [renamed_outside_fresh_map _ _ _ _ _ member]
    exact clonedRank_old _ _ _ _ old

theorem createScope_valid (machine : State) (context : Context) (invocation : InvocationId)
    (parent : Option LexicalScopeId) (vars : List VariableId) (values : List Located)
    (bindings : Environment) (after : State × Environment)
    (valid : Valid machine.heap) (bounded : Bounds machine.heap)
    (parentOld : ∀ identity ∈ parent, identity.value < machine.heap.nextScope)
    (accepted : createScope machine context invocation parent vars values bindings = .ok after) :
    Valid after.1.heap := by
  simp only [createScope, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · cases accepted; exact valid
  · simp only [except_bind_ok, fromOption_ok,
      pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, heap, moved, rfl⟩ := accepted
    simp [moveValues, Option.bind_eq_some_iff] at moved
    obtain ⟨custody, _, rfl⟩ := moved
    apply append_fresh _ _ rfl
    · exact fun scope member => (bounded scope member).1
    · exact fun scope member => (bounded scope member).2
    · exact parentOld
    · exact valid

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

/-- Actual capture instantiation preserves lexical ancestry, including every
dormant template whose scopes are copied by the same fresh map. -/
theorem instantiateCapture_valid (machine : State) (context : Context) (saved : Capture) (after : State × Capture)
    (valid : Valid machine.heap) (bounded : Bounds machine.heap) (indexed : machine.heap.Indexed)
    (accepted : instantiateCapture machine context saved = .ok after) : Valid after.1.heap := by
  let dormant := (cloneSupport machine.heap saved).filterMap (fun node => match machine.heap.lookup node with
    | some (.multiTemplate inner) => some inner | _ => none)
  let localScopes := (captureScopes saved ++ dormant.flatMap captureScopes).eraseDups
  obtain ⟨rank, ranked⟩ := valid
  let nextRank := clonedRank machine.heap.nextScope localScopes rank
  have rankOld (identity : LexicalScopeId) (old : identity.value < machine.heap.nextScope) :
      nextRank identity = rank identity := clonedRank_old _ _ _ _ old
  have rankMapped (identity : LexicalScopeId) (old : identity.value < machine.heap.nextScope) :
      nextRank (renamed (freshMap .runtime .lexicalScope machine.heap.nextScope localScopes) identity) = rank identity :=
    clonedRank_renamed _ _ _ _ old
  unfold instantiateCapture at accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨scopeRows, scopeRowsAt, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  cases accepted
  refine ⟨nextRank, ?_⟩
  change Ranked nextRank (machine.heap.scopes ++ scopeRows)
  intro scope member parent parentAt
  rcases List.mem_append.mp member with old | copied
  · have bounds := bounded scope old
    rw [rankOld scope.id bounds.1, rankOld parent (bounds.2 parent parentAt)]
    exact ranked scope old parent parentAt
  · obtain ⟨originalId, _, checked⟩ := mapM_output _ _ _ scopeRowsAt scope copied
    simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at checked
    obtain ⟨original, originalAt, rfl⟩ := checked
    have originalMember := List.mem_of_getElem? originalAt
    have originalBounds := bounded original originalMember
    have originalIdentity : original.id = originalId := by
      have identity := indexed.scope_identity originalAt
      exact ref_eq identity
    obtain ⟨originalParent, parentFound, rfl⟩ := Option.map_eq_some_iff.mp (show
      original.parent.map (renamed (freshMap .runtime .lexicalScope machine.heap.nextScope localScopes)) = some parent from parentAt)
    change nextRank (renamed (freshMap .runtime .lexicalScope machine.heap.nextScope localScopes) originalParent) <
      nextRank (renamed (freshMap .runtime .lexicalScope machine.heap.nextScope localScopes) originalId)
    rw [rankMapped originalParent (originalBounds.2 originalParent parentFound),
      rankMapped originalId (originalIdentity ▸ originalBounds.1), ← originalIdentity]
    exact ranked original originalMember originalParent parentFound

theorem set_formed (before : Heap) (index : Nat) (old fresh : Scope)
    (found : before.scopes[index]? = some old)
    (sameId : fresh.id = old.id) (sameParent : fresh.parent = old.parent)
    (formed : Formed before) : Formed { before with scopes := before.scopes.set index fresh } := by
  refine ⟨?_, set_valid _ _ _ _ found sameId sameParent formed.2⟩
  intro scope member
  rcases List.mem_or_eq_of_mem_set member with member | equal
  · exact formed.1 scope member
  · subst scope
    simpa only [sameId, sameParent] using formed.1 old (List.mem_of_getElem? found)

theorem move_formed {before after : Heap} {values : List Located} {receiver : Nat → Custody.Owner}
    (formed : Formed before) (accepted : moveValues before values receiver = some after) : Formed after := by
  simp [moveValues, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  exact formed

theorem consume_formed {before after : Heap} {value : Located}
    (formed : Formed before) (accepted : consumeValue before value = some after) : Formed after := by
  simp [consumeValue, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  exact formed

theorem allocate_formed (before after : Heap) (schema : SchemaId .source) (object : Object)
    (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject before schema object owner exclusive = some (after, value))
    (formed : Formed before) : Formed after := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, _⟩ := accepted; exact formed
  · obtain ⟨_, _, rfl, _⟩ := accepted; exact formed

theorem replace_formed {before after : Heap} {node : NodeId} {object : Object}
    (formed : Formed before) (accepted : replaceObject before node object = some after) : Formed after := by
  unfold replaceObject at accepted
  split at accepted <;> try contradiction
  cases accepted
  exact formed

theorem retire_formed {before after : Heap} {value : Located}
    (formed : Formed before) (accepted : retireObject before value = some after) : Formed after := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, Option.bind_eq_some_iff, pure, Option.some.injEq] at accepted
  obtain ⟨_, _, middle, consumed, rfl⟩ := accepted
  have next := consume_formed formed consumed
  exact next

theorem temporary_formed {machine after : State} {owner : Custody.Owner}
    (formed : Formed machine.heap) (accepted : temporary machine = .ok (after, owner)) : Formed after.heap := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  rename_i record found
  split at accepted <;> try contradiction
  cases accepted
  exact set_formed _ _ _ _ found rfl rfl formed

theorem finishTemporary_formed {machine : State} {value : Located} {after : Transition}
    (formed : Formed machine.heap) (accepted : finishTemporary machine value = .ok after) : Formed after.state.heap := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  rename_i record found
  cases accepted
  exact set_formed _ _ _ _ found rfl rfl formed

theorem scopedValue_formed (machine : State) (value : SemanticValue) (after : Transition)
    (formed : Formed machine.heap) (accepted : scopedValue machine value = .ok after) : Formed after.state.heap := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, first, last⟩ := accepted
  exact finishTemporary_formed (temporary_formed formed first) last

theorem createScope_formed (machine : State) (context : Context) (invocation : InvocationId)
    (parent : Option LexicalScopeId) (vars : List VariableId) (values : List Located)
    (bindings : Environment) (after : State × Environment)
    (formed : Formed machine.heap) (parentOld : ∀ identity ∈ parent, identity.value < machine.heap.nextScope)
    (accepted : createScope machine context invocation parent vars values bindings = .ok after) :
    Formed after.1.heap := by
  have ranked := createScope_valid _ _ _ _ _ _ _ _ formed.2 formed.1 parentOld accepted
  refine ⟨?_, ranked⟩
  simp only [createScope, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · cases accepted; exact formed.1
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, heap, moved, rfl⟩ := accepted
    simp [moveValues, Option.bind_eq_some_iff] at moved
    obtain ⟨custody, _, rfl⟩ := moved
    intro scope member
    rcases List.mem_append.mp member with old | new
    · have before := formed.1 scope old
      exact ⟨by dsimp; omega, fun identity member => by have bound := before.2 identity member; dsimp; omega⟩
    · cases List.mem_singleton.mp new
      exact ⟨Nat.lt_succ_self _, fun identity member => Nat.lt_succ_of_lt (parentOld identity member)⟩

theorem instantiateCapture_formed (machine : State) (context : Context) (saved : Capture) (after : State × Capture)
    (formed : Formed machine.heap) (indexed : machine.heap.Indexed)
    (accepted : instantiateCapture machine context saved = .ok after) : Formed after.1.heap := by
  have ranked := instantiateCapture_valid _ _ _ _ formed.2 formed.1 indexed accepted
  refine ⟨?_, ranked⟩
  let dormant := (cloneSupport machine.heap saved).filterMap (fun node => match machine.heap.lookup node with
    | some (.multiTemplate inner) => some inner | _ => none)
  let localScopes := (captureScopes saved ++ dormant.flatMap captureScopes).eraseDups
  have mappedBound (identity : LexicalScopeId) (old : identity.value < machine.heap.nextScope) :
      (renamed (freshMap .runtime .lexicalScope machine.heap.nextScope localScopes) identity).value <
        machine.heap.nextScope + localScopes.length := by
    by_cases member : identity ∈ localScopes
    · have bound := (source_activation_interval .runtime .lexicalScope machine.heap.nextScope localScopes identity member).2
      have size := dedup_length_le localScopes
      omega
    · rw [renamed_outside_fresh_map _ _ _ _ _ member]
      omega
  unfold instantiateCapture at accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨scopeRows, scopeRowsAt, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  cases accepted
  change ∀ scope ∈ machine.heap.scopes ++ scopeRows,
    scope.id.value < machine.heap.nextScope + localScopes.length ∧
      ∀ parent ∈ scope.parent, parent.value < machine.heap.nextScope + localScopes.length
  intro scope member
  rcases List.mem_append.mp member with old | copied
  · have bounds := formed.1 scope old
    exact ⟨by omega, fun parent member => by have bound := bounds.2 parent member; omega⟩
  · obtain ⟨originalId, _, checked⟩ := mapM_output _ _ _ scopeRowsAt scope copied
    simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at checked
    obtain ⟨original, originalAt, rfl⟩ := checked
    have originalBounds := formed.1 original (List.mem_of_getElem? originalAt)
    have originalIdentity : original.id = originalId := ref_eq (indexed.scope_identity originalAt)
    refine ⟨mappedBound originalId (originalIdentity ▸ originalBounds.1), ?_⟩
    intro parent found
    obtain ⟨originalParent, parentAt, rfl⟩ := Option.map_eq_some_iff.mp found
    exact mappedBound originalParent (originalBounds.2 originalParent parentAt)

end ScopeTree
end BoundaryV2.Profile.Source.Machine
