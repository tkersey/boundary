import BoundaryV2.SourceMachine

namespace BoundaryV2.Profile.Source.Machine

private theorem bind_success (value : Except Invalid α) (next : α → Except Invalid β)
    (result : β) (accepted : value.bind next = .ok result) :
    ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value with
  | error error => cases accepted
  | ok input => exact ⟨input, rfl, accepted⟩

/-- An actual ambient operation allocates one new logical occurrence, even
when its contract and payload equal an earlier operation. Polling is separate. -/
theorem ambient_request_allocates_occurrence (state : State) (context : Context)
    (operation : Operation) (operands : List Located) (transition : Transition)
    (ambient : operation.capability = none)
    (accepted : openRequest state context operation operands = .ok transition) :
    ∃ request, request.occurrence = ⟨state.nextOccurrence⟩ ∧
      request.effect = operation.effect ∧
      transition.state = { state with status := .parked request, nextOccurrence := state.nextOccurrence + 1 } ∧
      transition.events = [.requestOpened request] := by
  simp only [openRequest, ambient] at accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  cases accepted
  exact ⟨_, rfl, rfl, rfl, rfl⟩

theorem terminal_poll_has_no_event (state : State) (context : Context)
    (terminal : (∃ value, state.status = .completed value) ∨
      (∃ exit, state.status = .failed exit) ∨ (∃ exit, state.status = .cancelled exit)) :
    tick state context = .ok ⟨state, []⟩ := by
  rcases terminal with ⟨value, status⟩ | ⟨exit, status⟩ | ⟨exit, status⟩ <;> simp [tick, status]

end BoundaryV2.Profile.Source.Machine
