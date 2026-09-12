import BoundaryV2.SourceOwnerLocationCleanup

namespace BoundaryV2.Profile.Source.Machine
namespace OwnerLocations

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem tickRunning_valid (machine : State) (context : Context) (after : Transition)
    (accepted : tickRunning machine context = .ok after) (valid : Valid machine)
    (layouts : ObjectOwners.Valid machine.heap) : Valid after.state := by
  cases executing : machine.control <;> simp only [tickRunning, executing] at accepted
  case term => exact enterTerm_valid _ _ _ accepted valid
  case expression => exact enterExpression_valid _ _ _ accepted valid
  case invoke => exact enterInvocation_valid _ _ _ accepted valid
  case release => exact releaseScope_valid _ _ accepted valid
  case discard => exact discardValues_valid _ _ _ accepted valid layouts
  case unwind original => exact unwindStep_valid _ _ _ original executing accepted valid
  case execute intent bindings operands =>
    cases intent with
    | primitive => exact executePrimitive_valid _ _ _ valid accepted
    | term term =>
      cases term <;> first
        | exact executeEffectTerm_valid _ _ _ accepted valid
        | exact executeCleanupTerm_valid _ _ _ accepted valid
        | exact executeControlTerm_valid _ _ _ accepted valid
  case delivered value =>
    have ordinary := normal_delivered machine value valid.1 executing
    cases stacked : machine.stack with
    | nil =>
      simp only [stacked, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
      simpa only [Valid, Normal, Pending, ordinaryValues, queuedValues, executing, stacked] using
        with_status machine (.completed value.value) valid (by simp [statusValues])
    | cons saved tail =>
      have included : ∀ frame ∈ tail, frame ∈ machine.stack := by intro frame member; simp [stacked, member]
      have next := tail_valid machine tail valid included
      have frameNormal := normal_frame machine saved (by simp [stacked]) valid.1
      cases saved <;> simp only [stacked] at accepted
      all_goals first
        | exact enterBinding_valid _ _ _ accepted valid
        | exact deliverOperand_valid _ _ accepted valid
        | exact leaveInvocation_valid _ _ accepted valid
        | exact leaveLexical_valid _ _ accepted valid
        | exact restoreResumeCaller_valid _ _ accepted valid
        | exact completeHandler_valid _ _ _ accepted valid
        | exact finishCleanup_valid _ _ _ accepted valid
        | exact finishDisposal_valid _ _ accepted valid
        | (cases accepted; simpa only [Valid, Normal, Pending, ordinaryValues, queuedValues, executing] using next)
        | skip
      case protection identity =>
        exact beginCleanup_valid _ _ _ _ _ _ _ accepted valid (by simpa using ordinary) included
      case releaseReturn scope released =>
        cases accepted
        exact with_control _ (.release scope released) next frameNormal (by simp [DisposalShape.control])

theorem tick_valid (machine : State) (context : Context) (after : Transition)
    (accepted : tick machine context = .ok after) (valid : Valid machine)
    (layouts : ObjectOwners.Valid machine.heap) : Valid after.state := by
  cases phase : machine.status <;> simp only [tick, phase] at accepted
  · exact tickRunning_valid _ _ _ accepted valid layouts
  all_goals cases accepted; exact valid

theorem cancel_control_normal (control : Control) (reason : Protocol.Reason) :
    controlValues (cancelControl control reason) ⊆ controlValues control := by
  cases control with
  | discard values after | release scope after => cases after <;> simp [cancelControl, controlValues, afterValues]
  | _ => simp [cancelControl, controlValues]

theorem cancel_control_queued (control : Control) (reason : Protocol.Reason) :
    DisposalShape.control (cancelControl control reason) = DisposalShape.control control := by
  cases control with
  | discard values after | release scope after => cases after <;> rfl
  | _ => rfl

theorem external_valid (machine : State) (context : Context) (action : External) (after : Transition)
    (accepted : external machine context action = .ok after) (valid : Valid machine) : Valid after.state := by
  have running := with_status machine .running valid (by simp [statusValues])
  have resumed (value : SemanticValue) (result : Transition)
      (accepted : scopedValue {machine with status := .running} value = .ok result) : Valid result.state :=
    scopedValue_valid _ _ _ accepted running
  have cancelled (reason : Protocol.Reason) :
      Valid {machine with status := .running, control := cancelControl machine.control reason, cancellation := some reason} := by
    have next := with_control {machine with status := .running} (cancelControl machine.control reason) running
      (fun value member => normal_control machine valid.1 value (cancel_control_normal machine.control reason member))
      (by simpa only [cancel_control_queued] using pending_control machine valid.2)
    exact next
  have deferred (reason : Protocol.Reason) : Valid {machine with cancellation := some reason} := valid
  cases action <;> cases phase : machine.status <;>
    simp only [external, phase, bind, pure, Except.pure, Except.bind] at accepted <;> try contradiction
  all_goals grind (gen := 32) only [except_bind_ok]

theorem initial_valid (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) : Valid machine := by
  have external := initialization_checks_external_arguments _ _ _ accepted
  simp only [initial, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ := accepted
  constructor
  · intro value member
    simp only [ordinaryValues, controlValues, heapValues, statusValues, List.map_nil, List.nil_append,
      List.flatMap_nil, List.flatMap_cons, List.append_nil] at member
    obtain ⟨index, _, rfl⟩ := List.exists_of_mem_mapIdx member
    exact Or.inr (external_value_has_no_runtime_handles _ _ (external _ (List.getElem_mem _))).2
  · simp [Pending, queuedValues, DisposalShape.control]

theorem reachable_step_valid (context : Context) (arguments : List SemanticValue)
    (initialState before after : State) (prefixEvents events : List Event)
    (initialized : initial context arguments = .ok initialState)
    (prior : Steps context initialState prefixEvents before) (step : Step context before events after)
    (valid : Valid before) : Valid after := by
  cases step with
  | external accepted => exact external_valid _ _ _ _ accepted valid
  | internal accepted =>
    exact tick_valid _ _ _ accepted valid
      (ObjectOwners.initialized_execution_preserves_object_owners _ _ _ _ _ initialized prior)

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

/-- Ordinary active values remain scope views or token-free values. Every raw
disposal entry is such a view or names an already retired physical parent.
The object-layout premise used by disposal is derived from initialized steps. -/
theorem initialized_execution_preserves_owner_locations (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : Valid after :=
  reachable_steps_valid context arguments before before after [] events initialized .refl steps (initial_valid _ _ _ initialized)

end OwnerLocations
end BoundaryV2.Profile.Source.Machine
