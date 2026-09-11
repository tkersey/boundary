import BoundaryV2.TargetMachine

namespace BoundaryV2.Profile.Target.Machine

private theorem bind_success (value : Except Invalid α) (next : α → Except Invalid β)
    (result : β) (accepted : value.bind next = .ok result) :
    ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value with
  | error error => cases accepted
  | ok input => exact ⟨input, rfl, accepted⟩

theorem continuation_preserves_request_clock (state : State program) (control : Graph.Control)
    (values : List Graph.Value) (after : State program) (saved : NodeId)
    (accepted : continuation state control values = .ok (after, saved)) :
    after.nextOccurrence = state.nextOccurrence ∧ after.pendingOccurrence = state.pendingOccurrence := by
  unfold continuation at accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  cases accepted
  exact ⟨rfl, rfl⟩

/-- Every genuine external perform allocates the current occurrence and advances
its unbounded logical supply. Equal effect and payload values remain distinct
when performed again; the identity does not depend on either value. -/
theorem external_perform_opens_fresh_request (context : Context)
    (state : State context.program) (control : Graph.Control) (operation : Perform)
    (values : List Graph.Value) (transition : Transition context.program)
    (externalCapability : operation.capability = none)
    (accepted : perform context state control operation values = .ok transition) :
    ∃ payload,
      transition.events = [.requestOpened ⟨state.nextOccurrence⟩ operation.effect payload] ∧
      transition.state.nextOccurrence = state.nextOccurrence + 1 ∧
      transition.state.pendingOccurrence = some ⟨state.nextOccurrence⟩ ∧
      transition.state.status = .parked := by
  unfold perform at accepted
  simp only [externalCapability, Option.isSome_none, Bool.false_eq_true, ↓reduceIte] at accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨payload, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨⟨after, saved⟩, continued, accepted⟩ := bind_success _ _ _ accepted
  have clock := continuation_preserves_request_clock _ _ _ _ _ continued
  cases accepted
  exact ⟨payload, by simp only [clock.1], by simp only [clock.1], by simp only [clock.1], rfl⟩

private theorem materialize_preserves_clock (state : State program) (value : SemanticValue)
    (after : State program) (stored : Graph.Value)
    (accepted : materialize state value = .ok (after, stored)) :
    after.nextOccurrence = state.nextOccurrence := by
  unfold materialize at accepted
  obtain ⟨⟨_, _⟩, _, accepted⟩ := bind_success _ _ _ accepted
  cases accepted
  rfl

private theorem resumeContinuation_preserves_clock (state : State program) (saved : NodeId)
    (value : Graph.Value) (after : State program)
    (accepted : resumeContinuation state saved value = .ok after) :
    after.nextOccurrence = state.nextOccurrence := by
  unfold resumeContinuation at accepted
  obtain ⟨record, _, accepted⟩ := bind_success _ _ _ accepted
  cases record <;> try contradiction
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  cases accepted
  rfl

theorem accepted_response_preserves_request_supply (context : Context)
    (state : State context.program) (occurrence : RequestOccurrence) (value : SemanticValue)
    (transition : Transition context.program)
    (accepted : external context state (.response occurrence value) = .ok transition) :
    transition.state.nextOccurrence = state.nextOccurrence ∧
    transition.state.pendingOccurrence = none ∧
    transition.events = [.responseAccepted occurrence value] := by
  unfold external at accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨record, _, accepted⟩ := bind_success _ _ _ accepted
  cases record <;> try contradiction
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨⟨materialized, stored⟩, storedAt, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨after, resumed, accepted⟩ := bind_success _ _ _ accepted
  cases accepted
  have same := resumeContinuation_preserves_clock _ _ _ _ resumed
  have storedClock := materialize_preserves_clock _ _ _ _ storedAt
  refine ⟨same.trans storedClock, ?_, rfl⟩
  unfold resumeContinuation at resumed
  obtain ⟨record, _, resumed⟩ := bind_success _ _ _ resumed
  cases record <;> try contradiction
  obtain ⟨_, _, resumed⟩ := bind_success _ _ _ resumed
  obtain ⟨_, _, resumed⟩ := bind_success _ _ _ resumed
  obtain ⟨_, _, resumed⟩ := bind_success _ _ _ resumed
  cases resumed
  rfl

/-- A request, its accepted response, and a subsequent perform expose two
separate occurrences even when both operations have equal labels and payloads. -/
theorem request_response_request_keeps_both_occurrences (context : Context)
    (state : State context.program) (firstControl secondControl : Graph.Control)
    (firstOperation secondOperation : Perform) (firstValues secondValues : List Graph.Value)
    (first response second : Transition context.program) (value : SemanticValue)
    (firstExternal : firstOperation.capability = none)
    (secondExternal : secondOperation.capability = none)
    (firstAt : perform context state firstControl firstOperation firstValues = .ok first)
    (responseAt : external context first.state (.response ⟨state.nextOccurrence⟩ value) = .ok response)
    (secondAt : perform context response.state secondControl secondOperation secondValues = .ok second) :
    ∃ firstPayload secondPayload,
      first.events = [.requestOpened ⟨state.nextOccurrence⟩ firstOperation.effect firstPayload] ∧
      response.events = [.responseAccepted ⟨state.nextOccurrence⟩ value] ∧
      second.events = [.requestOpened ⟨state.nextOccurrence + 1⟩ secondOperation.effect secondPayload] := by
  obtain ⟨firstPayload, firstEvent, firstClock, _, _⟩ :=
    external_perform_opens_fresh_request _ _ _ _ _ _ firstExternal firstAt
  obtain ⟨responseClock, _, responseEvent⟩ := accepted_response_preserves_request_supply _ _ _ _ _ responseAt
  obtain ⟨secondPayload, secondEvent, _, _, _⟩ :=
    external_perform_opens_fresh_request _ _ _ _ _ _ secondExternal secondAt
  exact ⟨firstPayload, secondPayload, firstEvent, responseEvent, by
    simpa only [responseClock, firstClock] using secondEvent⟩

theorem successive_request_occurrences_differ (before after : State program)
    (advanced : after.nextOccurrence = before.nextOccurrence + 1) :
    (⟨before.nextOccurrence⟩ : RequestOccurrence) ≠ ⟨after.nextOccurrence⟩ := by
  intro same
  have same := congrArg Ref.value same
  change before.nextOccurrence = after.nextOccurrence at same
  omega

end BoundaryV2.Profile.Target.Machine
