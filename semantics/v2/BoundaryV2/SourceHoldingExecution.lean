import BoundaryV2.SourceHoldingEffects

namespace BoundaryV2.Profile.Source.Machine
namespace HoldingOwners

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem tickRunning_valid (machine : State) (context : Context) (after : Transition)
    (formed : Valid machine.heap) (indexed : machine.heap.Indexed)
    (accepted : tickRunning machine context = .ok after) : Valid after.state.heap := by
  cases executing : machine.control <;> simp only [tickRunning, executing] at accepted
  case term => exact enterTerm_valid _ _ _ formed accepted
  case expression => exact enterExpression_valid _ _ _ formed accepted
  case invoke => exact enterInvocation_valid _ _ _ formed accepted
  case release => exact releaseScope_valid _ _ formed accepted
  case discard => exact discardValues_valid _ _ _ formed accepted
  case unwind => exact unwindStep_valid _ _ _ formed accepted
  case execute intent bindings operands =>
    cases intent with
    | primitive => exact executePrimitive_valid _ _ _ formed accepted
    | term term =>
      cases term <;> first
        | exact executeEffectTerm_valid _ _ _ formed accepted
        | exact executeCleanupTerm_valid _ _ _ formed accepted
        | exact executeControlTerm_valid _ _ _ formed accepted
  case delivered value =>
    cases stacked : machine.stack with
    | nil =>
      simp only [stacked, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
      exact formed
    | cons saved tail =>
      cases saved <;> simp only [stacked] at accepted
      all_goals first
        | exact enterBinding_valid _ _ _ formed accepted
        | exact deliverOperand_valid _ _ formed accepted
        | exact leaveInvocation_valid _ _ formed accepted
        | exact leaveLexical_valid _ _ formed indexed accepted
        | exact restoreResumeCaller_valid _ _ formed accepted
        | exact completeHandler_valid _ _ _ formed accepted
        | exact finishCleanup_valid _ _ _ formed accepted
        | exact finishDisposal_valid _ _ formed accepted
        | exact beginCleanup_valid _ _ _ _ _ _ _ formed accepted
        | (cases accepted; exact formed)
        | contradiction

theorem tick_valid (machine : State) (context : Context) (after : Transition)
    (formed : Valid machine.heap) (indexed : machine.heap.Indexed)
    (accepted : tick machine context = .ok after) : Valid after.state.heap := by
  cases phase : machine.status <;> simp only [tick, phase] at accepted
  · exact tickRunning_valid _ _ _ formed indexed accepted
  all_goals cases accepted; exact formed

theorem external_valid (machine : State) (context : Context) (action : External) (after : Transition)
    (formed : Valid machine.heap)
    (accepted : external machine context action = .ok after) : Valid after.state.heap := by
  have scopedBound (value : SemanticValue) (result : Transition)
      (resumed : scopedValue {machine with status := .running} value = .ok result) : Valid result.state.heap :=
    scopedValue_valid _ _ _ resumed (by exact formed)
  cases action <;> cases phase : machine.status <;>
    simp only [external, phase, bind, pure, Except.pure, Except.bind] at accepted <;> try contradiction
  all_goals grind (gen := 32) only [except_bind_ok]

theorem step_valid (step : Step context before events after) (formed : Valid before.heap)
    (indexed : before.heap.Indexed) : Valid after.heap := by
  cases step with
  | internal accepted => exact tick_valid _ _ _ formed indexed accepted
  | external accepted => exact external_valid _ _ _ _ formed accepted

theorem steps_valid (steps : Steps context before events after) (formed : Valid before.heap)
    (indexed : before.heap.Indexed) : Valid after.heap := by
  induction steps with
  | refl => exact formed
  | cons step _ induction => exact induction (step_valid step formed indexed) (step_indexed step indexed)


theorem initial_valid (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) : Valid machine.heap := by
  simp only [initial, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ := accepted
  simp [Valid, ValidScope]

/-- Every actual initialized source trajectory retains distinct owning slots
in each scope. Each stored owner is lexical or temporary, names its actual
scope, and lies below that scope's allocation counter. -/
theorem initialized_execution_preserves_holding_owners (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : Valid after.heap :=
  steps_valid steps (initial_valid _ _ _ initialized) (initial_indexed _ _ _ initialized)


private theorem allocated_scope_eq (first second : Scope) (owner : Custody.Owner)
    (firstAt : Allocated first owner) (secondAt : Allocated second owner) : first.id = second.id := by
  obtain ⟨firstIndex, _, firstOwner⟩ := firstAt
  obtain ⟨secondIndex, _, secondOwner⟩ := secondAt
  rcases firstOwner with firstOwner | firstOwner <;> rcases secondOwner with secondOwner | secondOwner
  all_goals have same := firstOwner.symm.trans secondOwner
  all_goals first | exact (Custody.Owner.lexical.inj same).1 | exact (Custody.Owner.temporary.inj same).1 | contradiction

/-- Slot owners are unique across all scope holdings, including retained stale
values. Scope identity separates slots from different allocations. -/
theorem all_scope_owners_unique (heap : Heap) (formed : Valid heap) (indexed : heap.Indexed) :
    (heap.scopes.flatMap fun scope => scope.holdings.map Located.owner).Nodup := by
  apply List.pairwise_flatMap.mpr
  refine ⟨fun scope member => (formed scope member).1, ?_⟩
  have identities : (heap.scopes.map fun scope => scope.id.value).Nodup := by
    rw [indexed.scopes]
    exact List.nodup_range
  apply (List.pairwise_map.mp identities).imp_of_mem
  intro first second firstAt secondAt distinct firstOwner firstMember secondOwner secondMember equal
  obtain ⟨firstValue, firstValueAt, firstValueOwner⟩ := List.mem_map.mp firstMember
  obtain ⟨secondValue, secondValueAt, secondValueOwner⟩ := List.mem_map.mp secondMember
  have firstAllocated : Allocated first firstOwner := firstValueOwner ▸ (formed first firstAt).2 firstValue firstValueAt
  have secondAllocated : Allocated second firstOwner := (secondValueOwner.trans equal.symm) ▸ (formed second secondAt).2 secondValue secondValueAt
  exact distinct (congrArg Ref.value (allocated_scope_eq first second firstOwner firstAllocated secondAllocated))

theorem reachable_scope_owners_are_unique (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) :
    (after.heap.scopes.flatMap fun scope => scope.holdings.map Located.owner).Nodup :=
  all_scope_owners_unique after.heap
    (initialized_execution_preserves_holding_owners _ _ _ _ _ initialized steps)
    (source_trajectory_indices _ _ _ _ initialized steps)

end HoldingOwners
end BoundaryV2.Profile.Source.Machine
