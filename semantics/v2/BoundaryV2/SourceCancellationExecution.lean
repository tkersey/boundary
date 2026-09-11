import BoundaryV2.SourceCancellation
import BoundaryV2.ProfileCodec

namespace BoundaryV2.Profile.Source.Machine
namespace Cancellation

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

def ValidReason : Protocol.Reason → Prop
  | .text data => UTF8.valid data = true
  | .bytes _ => True

private theorem require_ok (condition : Bool) (reason : Invalid) (result : Unit)
    (accepted : require condition reason = .ok result) : condition = true := by
  unfold require at accepted
  split at accepted <;> first | assumption | contradiction

theorem external_cancellation_origin (machine : State) (context : Context) (action : External) (after : Transition)
    (accepted : external machine context action = .ok after) :
    after.state.cancellation = machine.cancellation ∨ ∃ reason, action = .cancel reason ∧
      machine.cancellation = none ∧ after.state.cancellation = some reason ∧ ValidReason reason := by
  have scopedSame (value : SemanticValue) (transition : Transition)
      (checked : scopedValue { machine with status := .running } value = .ok transition) :
      transition.state.cancellation = machine.cancellation := by
    have result := scopedValue_cancellation _ _ _ checked
    exact result
  have absent (value : Option Protocol.Reason) (empty : value.isSome ≠ true) : value = none := by
    cases value <;> simp_all
  cases action with
  | continueYield =>
    cases phase : machine.status <;> simp only [external, phase, bind, Except.bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
    all_goals try contradiction
    cases accepted; exact Or.inl rfl
  | response occurrence value =>
    cases phase : machine.status <;> simp only [external, phase, bind, Except.bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
    all_goals try contradiction
    grind (gen := 32) only []
  | cancel reason =>
    cases reason <;> cases phase : machine.status <;>
      simp only [external, phase, bind, Except.bind, pure, Except.pure, ValidReason] at accepted ⊢ <;> try contradiction
    all_goals grind (gen := 32) only [except_bind_ok, → require_ok, ValidReason]

theorem external_keeps_first_cancellation (machine : State) (context : Context) (action : External) (after : Transition)
    (accepted : external machine context action = .ok after) (reason : Protocol.Reason)
    (existing : machine.cancellation = some reason) : after.state.cancellation = some reason := by
  rcases external_cancellation_origin _ _ _ _ accepted with same | ⟨_, _, absent, _, _⟩
  · exact same.trans existing
  · rw [existing] at absent; cases absent

theorem step_keeps_first_cancellation (context : Context) (before after : State) (events : List Event)
    (step : Step context before events after) (reason : Protocol.Reason) (existing : before.cancellation = some reason) :
    after.cancellation = some reason := by
  cases step with
  | internal accepted => exact (tick_cancellation _ _ _ accepted).trans existing
  | external accepted => exact external_keeps_first_cancellation _ _ _ _ accepted _ existing

theorem steps_keep_first_cancellation (context : Context) (before after : State) (events : List Event)
    (steps : Steps context before events after) (reason : Protocol.Reason) (existing : before.cancellation = some reason) :
    after.cancellation = some reason := by
  induction steps with
  | refl => exact existing
  | cons step _ induction => exact induction (step_keeps_first_cancellation _ _ _ _ step reason existing)

def Typed (machine : State) : Prop := ∀ reason, machine.cancellation = some reason → ValidReason reason

theorem initial_typed (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) : Typed machine := by
  simp only [initial, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ := accepted
  simp [Typed]

theorem step_typed (context : Context) (before after : State) (events : List Event)
    (step : Step context before events after) (typed : Typed before) : Typed after := by
  intro reason found
  cases step with
  | internal accepted => exact typed reason ((tick_cancellation _ _ _ accepted).symm.trans found)
  | external accepted =>
    rcases external_cancellation_origin _ _ _ _ accepted with same | ⟨newReason, _, _, same, valid⟩
    · exact typed reason (same.symm.trans found)
    · have equal := Option.some.inj (same.symm.trans found)
      exact equal ▸ valid

theorem steps_typed (context : Context) (before after : State) (events : List Event)
    (steps : Steps context before events after) (typed : Typed before) : Typed after := by
  induction steps with
  | refl => exact typed
  | cons step _ induction => exact induction (step_typed _ _ _ _ step typed)

theorem initialized_cancellation_is_valid (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : Typed after :=
  steps_typed _ _ _ _ steps (initial_typed _ _ _ initialized)

open Wire

def Bounded (reason : Protocol.Reason) : Prop :=
  match reason with | .text data | .bytes data => data.length < wordLimit


theorem codec_reason_bounded (reason : Protocol.Reason)
    (accepted : Codecs.reason.valid reason = true) :
    Bounded reason := by
  cases reason with
  | text data | bytes data =>
    change (decide (data.length < wordLimit) && true) = true at accepted
    simpa [Bounded] using accepted


theorem decoded_reason_bounded (input rest : Bytes) (reason : Protocol.Reason)
    (decoded : Codecs.reason.read input = some (reason, rest)) :
    Bounded reason :=
  codec_reason_bounded reason (Codecs.reason.readValid _ _ _ decoded)


def PayloadBounded (machine : State) : Prop := ∀ reason, machine.cancellation = some reason → Bounded reason

theorem initial_payload_bounded (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) : PayloadBounded machine := by
  simp only [initial, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ := accepted
  simp [PayloadBounded]

theorem tick_preserves_payload_bound (machine : State) (context : Context) (after : Transition)
    (accepted : tick machine context = .ok after) (bounded : PayloadBounded machine) : PayloadBounded after.state := by
  intro reason found
  exact bounded reason ((tick_cancellation _ _ _ accepted).symm.trans found)

theorem external_preserves_payload_bound (machine : State) (context : Context) (action : External) (after : Transition)
    (accepted : external machine context action = .ok after) (bounded : PayloadBounded machine)
    (inputBounded : ∀ reason, action = .cancel reason → Bounded reason) : PayloadBounded after.state := by
  intro reason found
  rcases external_cancellation_origin _ _ _ _ accepted with same | ⟨newReason, input, _, same, _⟩
  · exact bounded reason (same.symm.trans found)
  · have equal := Option.some.inj (same.symm.trans found)
    exact equal ▸ inputBounded newReason input

theorem decoded_cancellation_preserves_payload_bound (machine : State) (context : Context) (reason : Protocol.Reason)
    (input rest : Bytes) (decoded : Codecs.reason.read input = some (reason, rest)) (after : Transition)
    (accepted : external machine context (.cancel reason) = .ok after) (bounded : PayloadBounded machine) :
    PayloadBounded after.state := by
  apply external_preserves_payload_bound _ _ _ _ accepted bounded
  intro other equal
  cases equal
  exact decoded_reason_bounded _ _ _ decoded

end Cancellation
end BoundaryV2.Profile.Source.Machine
