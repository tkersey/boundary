import BoundaryV2.SourceQueueCleanup

namespace BoundaryV2.Profile.Source.Machine
namespace QueueCustody

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

theorem tickRunning_valid (machine : State) (context : Context) (after : Transition)
    (accepted : tickRunning machine context = .ok after) (valid : Valid machine)
    (owners : OwnerLocations.Valid machine) (leaves : DisposalShape.Valid machine)
    (objects : ObjectOwners.Valid machine.heap)
    (shapes : ValueInventory.All (ValueShape context.source.schemas) machine)
    (linear : ValueInventory.All (fun value => (ownedTokens value).Nodup) machine) : Valid after.state := by
  have retired := fields_retired machine owners leaves
  cases executing : machine.control <;> simp only [tickRunning, executing] at accepted
  case term => exact enterTerm_valid _ _ _ accepted valid
  case expression => exact enterExpression_valid _ _ _ accepted valid owners
  case invoke => exact enterInvocation_valid _ _ _ accepted valid owners
  case release => exact releaseScope_valid _ _ accepted valid owners
  case discard => exact discardValues_valid _ _ _ accepted valid retired objects linear
  case unwind original => exact unwindStep_valid _ _ _ original executing accepted valid owners retired objects
  case execute intent bindings operands =>
    cases intent with
    | primitive => exact executePrimitive_valid _ _ _ valid owners leaves objects accepted
    | term term =>
      cases term <;> first
        | exact executeEffectTerm_valid _ _ _ accepted valid owners leaves objects
        | exact executeCleanupTerm_valid _ _ _ accepted valid owners leaves objects shapes
        | exact executeControlTerm_valid _ _ _ accepted valid owners leaves objects
  case delivered value =>
    cases stacked : machine.stack with
    | nil =>
      simp only [stacked, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
      simpa only [Valid, fields_components, executing, stacked] using valid
    | cons saved tail =>
      have included : tail.Sublist machine.stack := by rw [stacked]; exact List.sublist_cons_self _ _
      have next := substack_valid machine tail valid included
      cases saved <;> simp only [stacked] at accepted
      all_goals first
        | exact enterBinding_valid _ _ _ accepted valid owners
        | exact deliverOperand_valid _ _ accepted valid
        | exact leaveInvocation_valid _ _ accepted valid owners
        | exact leaveLexical_valid _ _ accepted valid owners
        | exact restoreResumeCaller_valid _ _ accepted valid owners
        | exact completeHandler_valid _ _ _ accepted valid
        | exact finishCleanup_valid _ _ _ accepted valid
        | exact finishDisposal_valid _ _ accepted valid owners
        | (cases accepted; simpa only [Valid, fields_components, controlFields, DisposalShape.control, executing] using next)
        | skip
      case protection identity =>
        exact beginCleanup_valid _ _ _ _ _ _ _ accepted valid included retired objects

theorem tick_valid (machine : State) (context : Context) (after : Transition)
    (accepted : tick machine context = .ok after) (valid : Valid machine)
    (owners : OwnerLocations.Valid machine) (leaves : DisposalShape.Valid machine)
    (objects : ObjectOwners.Valid machine.heap)
    (shapes : ValueInventory.All (ValueShape context.source.schemas) machine)
    (linear : ValueInventory.All (fun value => (ownedTokens value).Nodup) machine) : Valid after.state := by
  cases phase : machine.status <;> simp only [tick, phase] at accepted
  · exact tickRunning_valid _ _ _ accepted valid owners leaves objects shapes linear
  all_goals cases accepted; exact valid

theorem external_valid (machine : State) (context : Context) (action : External) (after : Transition)
    (accepted : external machine context action = .ok after) (valid : Valid machine) : Valid after.state := by
  have running : Valid {machine with status := .running} := valid
  have resumed (value : SemanticValue) (result : Transition)
      (accepted : scopedValue {machine with status := .running} value = .ok result) : Valid result.state :=
    scopedValue_valid _ _ _ accepted running
  have cancelled (reason : Protocol.Reason) :
      Valid {machine with status := .running, control := cancelControl machine.control reason, cancellation := some reason} := by
    simpa only [Valid, fields_components, controlFields, OwnerLocations.cancel_control_queued] using valid
  have deferred (reason : Protocol.Reason) : Valid {machine with cancellation := some reason} := valid
  cases action <;> cases phase : machine.status <;>
    simp only [external, phase, bind, pure, Except.pure, Except.bind] at accepted <;> try contradiction
  all_goals grind (gen := 32) only [except_bind_ok]

theorem initial_valid (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) : Valid machine := by
  simp only [initial, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ := accepted
  simp [Valid, fields, OwnerLocations.queuedValues, DisposalShape.control, Linear, tokens]

theorem reachable_step_valid (context : Context) (arguments : List SemanticValue)
    (initialState before after : State) (prefixEvents events : List Event)
    (initialized : initial context arguments = .ok initialState)
    (prior : Steps context initialState prefixEvents before) (step : Step context before events after)
    (valid : Valid before) : Valid after := by
  cases step with
  | external accepted => exact external_valid _ _ _ _ accepted valid
  | internal accepted =>
    exact tick_valid _ _ _ accepted valid
      (OwnerLocations.initialized_execution_preserves_owner_locations _ _ _ _ _ initialized prior)
      (DisposalShape.initialized_execution_preserves_disposal_leaves _ _ _ _ _ initialized prior)
      (ObjectOwners.initialized_execution_preserves_object_owners _ _ _ _ _ initialized prior)
      (initialized_execution_preserves_value_shapes _ _ _ _ _ initialized prior)
      (ValueLinearity.initialized_execution_preserves_linearity _ _ _ _ _ initialized prior)

theorem reachable_steps_valid (context : Context) (arguments : List SemanticValue)
    (initialState before after : State) (prefixEvents events : List Event)
    (initialized : initial context arguments = .ok initialState)
    (prior : Steps context initialState prefixEvents before) (steps : Steps context before events after)
    (valid : Valid before) : Valid after := by
  induction steps generalizing prefixEvents with
  | refl => exact valid
  | cons step _ induction =>
    apply induction _ (steps_trans prior (.cons step .refl))
    exact reachable_step_valid _ _ _ _ _ _ _ initialized prior step valid

/-- Raw closure-tagged disposal entries contain no repeated owning token, and
each remains current, throughout actual execution from successful initialization.
Capture transfers preserve list multiplicity across heap objects and frames. -/
theorem initialized_execution_preserves_queue_custody (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : Valid after :=
  reachable_steps_valid context arguments before before after [] events initialized .refl steps (initial_valid _ _ _ initialized)

end QueueCustody
end BoundaryV2.Profile.Source.Machine
