import BoundaryV2.SourceScopeTreeEffects

namespace BoundaryV2.Profile.Source.Machine
namespace ScopeTree

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

theorem tickRunning_formed (machine : State) (context : Context) (after : Transition)
    (formed : Formed machine.heap) (bounded : IdentitySupport.Valid machine) (indexed : machine.heap.Indexed)
    (accepted : tickRunning machine context = .ok after) : Formed after.state.heap := by
  cases executing : machine.control <;> simp only [tickRunning, executing] at accepted
  case term => exact enterTerm_formed _ _ _ formed accepted
  case expression => exact enterExpression_formed _ _ _ formed accepted
  case invoke => exact enterInvocation_formed _ _ _ formed accepted
  case release => exact releaseScope_formed _ _ formed accepted
  case discard => exact discardValues_formed _ _ _ formed accepted
  case unwind => exact unwindStep_formed _ _ _ formed accepted
  case execute intent bindings operands =>
    cases intent with
    | primitive => exact executePrimitive_formed _ _ _ formed accepted
    | term term =>
      cases term <;> first
        | exact executeEffectTerm_formed _ _ _ formed indexed accepted
        | exact executeCleanupTerm_formed _ _ _ formed accepted
        | exact executeControlTerm_formed _ _ _ formed bounded accepted
  case delivered value =>
    cases stacked : machine.stack with
    | nil =>
      simp only [stacked, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
      exact formed
    | cons saved tail =>
      cases saved <;> simp only [stacked] at accepted
      all_goals first
        | exact enterBinding_formed _ _ _ formed bounded accepted
        | exact deliverOperand_formed _ _ formed accepted
        | exact leaveInvocation_formed _ _ formed accepted
        | exact leaveLexical_formed _ _ formed accepted
        | exact restoreResumeCaller_formed _ _ formed accepted
        | exact completeHandler_formed _ _ _ formed accepted
        | exact finishCleanup_formed _ _ _ formed accepted
        | exact beginCleanup_formed _ _ _ _ _ _ _ formed accepted
        | (cases accepted; exact formed)
        | contradiction

theorem tick_formed (machine : State) (context : Context) (after : Transition)
    (formed : Formed machine.heap) (bounded : IdentitySupport.Valid machine) (indexed : machine.heap.Indexed)
    (accepted : tick machine context = .ok after) : Formed after.state.heap := by
  cases phase : machine.status <;> simp only [tick, phase] at accepted
  · exact tickRunning_formed _ _ _ formed bounded indexed accepted
  all_goals cases accepted; exact formed

theorem external_formed (machine : State) (context : Context) (action : External) (after : Transition)
    (formed : Formed machine.heap)
    (accepted : external machine context action = .ok after) : Formed after.state.heap := by
  have scopedBound (value : SemanticValue) (result : Transition)
      (resumed : scopedValue {machine with status := .running} value = .ok result) : Formed result.state.heap :=
    scopedValue_formed _ _ _ (by exact formed) resumed
  cases action <;> cases phase : machine.status <;>
    simp only [external, phase, bind, pure, Except.pure, Except.bind] at accepted <;> try contradiction
  all_goals grind (gen := 32) only [except_bind_ok]

theorem step_formed (step : Step context before events after) (formed : Formed before.heap)
    (bounded : IdentitySupport.Valid before) (indexed : before.heap.Indexed) : Formed after.heap := by
  cases step with
  | internal accepted => exact tick_formed _ _ _ formed bounded indexed accepted
  | external accepted => exact external_formed _ _ _ _ formed accepted

theorem steps_formed (steps : Steps context before events after) (formed : Formed before.heap)
    (bounded : IdentitySupport.Valid before) (indexed : before.heap.Indexed) : Formed after.heap := by
  induction steps with
  | refl => exact formed
  | cons step _ induction => exact induction (step_formed step formed bounded indexed) (IdentitySupport.step_valid step bounded) (step_indexed step indexed)


theorem initial_formed (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) : Formed machine.heap := by
  have bounds := bounds_of_identity (IdentitySupport.initial_valid _ _ _ accepted)
  refine ⟨bounds, ?_⟩
  simp only [initial, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ := accepted
  exact ⟨fun _ => 0, by simp [Ranked]⟩

/-- Every initialized source trajectory retains a ranked lexical parent forest.
The proof includes actual scope reuse, copied dormant scopes, cancellation,
resource disposal, and cleanup that suspends or fails. -/
theorem initialized_execution_preserves_scope_ancestry (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : Formed after.heap :=
  steps_formed steps (initial_formed _ _ _ initialized) (IdentitySupport.initial_valid _ _ _ initialized)
    (initial_indexed _ _ _ initialized)

/-- One actual lexical-parent link, read from the indexed scope record. -/
def Parent (heap : Heap) (child parent : LexicalScopeId) : Prop :=
  ∃ record, heap.scopes[child.value]? = some record ∧ record.parent = some parent

inductive Ancestor (heap : Heap) : LexicalScopeId → LexicalScopeId → Prop where
  | direct : Parent heap child parent → Ancestor heap child parent
  | next : Parent heap child parent → Ancestor heap parent ancestor → Ancestor heap child ancestor

theorem parent_rank (heap : Heap) (rank : LexicalScopeId → Nat) (ranked : Ranked rank heap.scopes)
    (indexed : heap.Indexed) (linked : Parent heap child parent) : rank parent < rank child := by
  obtain ⟨record, found, parentAt⟩ := linked
  have same : record.id = child := by
    have identity := indexed.scope_identity found
    have ref_eq {left right : LexicalScopeId} (equal : left.value = right.value) : left = right := by
      cases left; cases right; simpa using equal
    exact ref_eq identity
  simpa only [same] using ranked record (List.mem_of_getElem? found) parent parentAt

theorem ancestor_rank (heap : Heap) (rank : LexicalScopeId → Nat) (ranked : Ranked rank heap.scopes)
    (indexed : heap.Indexed) (path : Ancestor heap child ancestor) : rank ancestor < rank child := by
  induction path with
  | direct edge => exact parent_rank _ _ ranked indexed edge
  | next edge _ induction => exact Nat.lt_trans induction (parent_rank _ _ ranked indexed edge)

theorem ancestor_irreflexive (heap : Heap) (formed : Formed heap) (indexed : heap.Indexed)
    (identity : LexicalScopeId) : ¬Ancestor heap identity identity := by
  obtain ⟨rank, ranked⟩ := formed.2
  intro cycle
  have impossible := ancestor_rank heap rank ranked indexed cycle
  omega

theorem reachable_scope_parent_chains_cannot_cycle (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) (identity : LexicalScopeId) : ¬Ancestor after.heap identity identity :=
  ancestor_irreflexive _ (initialized_execution_preserves_scope_ancestry _ _ _ _ _ initialized steps)
    (source_trajectory_indices _ _ _ _ initialized steps) identity

inductive RootPath (heap : Heap) : LexicalScopeId → LexicalScopeId → Prop where
  | root : (∃ record, heap.scopes[identity.value]? = some record ∧ record.parent = none) → RootPath heap identity identity
  | parent : Parent heap child parent → RootPath heap parent root → RootPath heap child root

/-- Every allocated scope reaches an actual parentless record. The rank proves
termination independently of the physical order chosen when scopes are cloned. -/
theorem scope_reaches_root (heap : Heap) (formed : Formed heap) (indexed : heap.Indexed)
    (identity : LexicalScopeId) (inside : identity.value < heap.nextScope) : ∃ root, RootPath heap identity root := by
  obtain ⟨rank, ranked⟩ := formed.2
  have descend : ∀ depth identity, rank identity = depth → identity.value < heap.nextScope →
      ∃ root, RootPath heap identity root := by
    intro depth
    induction depth using Nat.strongRecOn with
    | ind depth induction =>
      intro identity rankAt bounded
      obtain ⟨record, found, _⟩ := IdentitySupport.scope_record_exists indexed identity bounded
      cases parentAt : record.parent with
      | none => exact ⟨identity, .root ⟨record, found, parentAt⟩⟩
      | some parent =>
        have edge : Parent heap identity parent := ⟨record, found, parentAt⟩
        have below := parent_rank heap rank ranked indexed edge
        have parentBound := (formed.1 record (List.mem_of_getElem? found)).2 parent parentAt
        obtain ⟨root, path⟩ := induction (rank parent) (by omega) parent rfl parentBound
        exact ⟨root, .parent edge path⟩
  exact descend (rank identity) identity rfl inside

theorem reachable_scope_reaches_root (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : ∃ root, RootPath after.heap after.scope root :=
  scope_reaches_root _ (initialized_execution_preserves_scope_ancestry _ _ _ _ _ initialized steps)
    (source_trajectory_indices _ _ _ _ initialized steps)
    after.scope (IdentitySupport.initialized_execution_preserves_identity_bounds _ _ _ _ _ initialized steps).scope

end ScopeTree
end BoundaryV2.Profile.Source.Machine
