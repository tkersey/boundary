import BoundaryV2.SourceCellIdentityCleanup

namespace BoundaryV2.Profile.Source.Machine
namespace CellIdentities

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

theorem tickRunning_unique (machine : State) (context : Context) (after : Transition)
    (formed : Unique machine.heap) (bounded : IdentitySupport.Valid machine)
    (accepted : tickRunning machine context = .ok after) : Unique after.state.heap := by
  cases executing : machine.control <;> simp only [tickRunning, executing] at accepted
  case term => exact enterTerm_unique _ _ _ formed accepted
  case expression => exact enterExpression_unique _ _ _ formed accepted
  case invoke => exact enterInvocation_unique _ _ _ formed accepted
  case release => exact releaseScope_unique _ _ formed accepted
  case discard => exact discardValues_unique _ _ _ formed accepted
  case unwind => exact unwindStep_unique _ _ _ formed accepted
  case execute intent bindings operands =>
    cases intent with
    | primitive => exact executePrimitive_unique _ _ _ formed bounded accepted
    | term term =>
      cases term <;> first
        | exact executeEffectTerm_unique _ _ _ formed bounded accepted
        | exact executeCleanupTerm_unique _ _ _ formed accepted
        | exact executeControlTerm_unique _ _ _ formed accepted
  case delivered value =>
    cases stacked : machine.stack with
    | nil =>
      simp only [stacked, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
      exact formed
    | cons saved tail =>
      cases saved <;> simp only [stacked] at accepted
      all_goals first
        | exact enterBinding_unique _ _ _ formed accepted
        | exact deliverOperand_unique _ _ formed accepted
        | exact leaveInvocation_unique _ _ formed accepted
        | exact leaveLexical_unique _ _ formed accepted
        | exact restoreResumeCaller_unique _ _ formed accepted
        | exact completeHandler_unique _ _ _ formed accepted
        | exact finishCleanup_unique _ _ _ formed accepted
        | exact beginCleanup_unique _ _ _ _ _ _ _ formed accepted
        | (cases accepted; exact formed)
        | contradiction

theorem tick_unique (machine : State) (context : Context) (after : Transition)
    (formed : Unique machine.heap) (bounded : IdentitySupport.Valid machine)
    (accepted : tick machine context = .ok after) : Unique after.state.heap := by
  cases phase : machine.status <;> simp only [tick, phase] at accepted
  · exact tickRunning_unique _ _ _ formed bounded accepted
  all_goals cases accepted; exact formed

theorem external_unique (machine : State) (context : Context) (action : External) (after : Transition)
    (formed : Unique machine.heap)
    (accepted : external machine context action = .ok after) : Unique after.state.heap := by
  have scopedBound (value : SemanticValue) (result : Transition)
      (resumed : scopedValue {machine with status := .running} value = .ok result) : Unique result.state.heap :=
    scopedValue_unique (by exact formed) resumed
  cases action <;> cases phase : machine.status <;>
    simp only [external, phase, bind, pure, Except.pure, Except.bind] at accepted <;> try contradiction
  all_goals grind (gen := 32) only [except_bind_ok]

theorem step_unique (step : Step context before events after) (formed : Unique before.heap)
    (bounded : IdentitySupport.Valid before) : Unique after.heap := by
  cases step with
  | internal accepted => exact tick_unique _ _ _ formed bounded accepted
  | external accepted => exact external_unique _ _ _ _ formed accepted

theorem steps_unique (steps : Steps context before events after) (formed : Unique before.heap)
    (bounded : IdentitySupport.Valid before) : Unique after.heap := by
  induction steps with
  | refl => exact formed
  | cons step _ induction => exact induction (step_unique step formed bounded) (IdentitySupport.step_valid step bounded)

/-- Arbitrarily long initialized source executions preserve the correspondence
between a mutable cell's logical identity and its physical heap node. The
cloning case uses the actual copied-node order and fresh cell-identity map. -/
theorem initialized_execution_preserves_cell_identity (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : Unique after.heap :=
  steps_unique steps (initial_unique _ _ _ initialized) (IdentitySupport.initial_valid _ _ _ initialized)

theorem initialized_cells_with_equal_identity_are_same_node (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) (left right : NodeId) (cell : CellId)
    (leftSchema rightSchema : SchemaId .source) (leftRegion rightRegion : RegionInstanceId)
    (leftContent rightContent : Located)
    (leftAt : after.heap.lookup left = some (.cell cell leftSchema leftRegion leftContent))
    (rightAt : after.heap.lookup right = some (.cell cell rightSchema rightRegion rightContent)) : left = right :=
  initialized_execution_preserves_cell_identity _ _ _ _ _ initialized steps left right cell
    (by simp [atNode, leftAt, identity]) (by simp [atNode, rightAt, identity])

end CellIdentities
end BoundaryV2.Profile.Source.Machine
