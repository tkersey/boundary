import BoundaryV2.TargetExecution
import BoundaryV2.SnapshotCanonical

namespace BoundaryV2.Profile.Target.Boundary
open Machine (require fromOption)

theorem terminal_has_no_saved_state (program : Program) (result : Machine.Result)
    (outcome : Protocol.Outcome) (accepted : terminal program result = .ok outcome) :
    nextInstance outcome = none := by
  cases result <;> simp only [terminal, bind, Except.bind] at accepted
  all_goals repeat' first | split at accepted | contradiction
  all_goals cases accepted; rfl

theorem finish_saved_state (image : Machine.ImageContext imageBytes programWitness)
    (state : Machine.State image.context.program) (witness : Graph.Admission.Witness)
    (outcome : Protocol.Outcome) (bytes : Bytes)
    (accepted : finish image state witness = .ok outcome)
    (saved : nextInstance outcome = some (.state bytes)) :
    ∃ normalized, Graph.Snapshot.canonicalize state.raw = some normalized ∧
      Images.rawState.valid normalized = true ∧
      Graph.Admission.check image.context.program programWitness.borrows normalized witness = true ∧
      Images.rawState.encode normalized = bytes := by
  unfold finish at accepted
  simp only [require, bind, Except.bind] at accepted
  split at accepted
  · cases accepted
  · split at accepted
    · cases accepted
    · cases atResult : state.result with
      | some result =>
        simp only [atResult] at accepted
        rw [terminal_has_no_saved_state _ _ _ accepted] at saved
        cases saved
      | none =>
        simp only [atResult] at accepted
        cases normalizedAt : Graph.Snapshot.canonicalize state.raw with
        | none => simp [fromOption, normalizedAt] at accepted
        | some normalized =>
          simp only [fromOption, normalizedAt] at accepted
          cases valid : Images.rawState.valid normalized with
          | false => simp [valid] at accepted
          | true =>
            simp only [valid, ↓reduceIte] at accepted
            cases admitted : Graph.Admission.check image.context.program programWitness.borrows normalized witness with
            | false => simp [admitted] at accepted
            | true =>
              simp only [admitted, ↓reduceIte] at accepted
              refine ⟨normalized, rfl, valid, admitted, ?_⟩
              cases atStatus : state.status with
              | active | unwinding | yielded =>
                simp only [atStatus] at accepted
                cases accepted
                simpa only [nextInstance, Option.some.injEq, Protocol.Instance.state.injEq] using saved
              | parked =>
                simp only [atStatus] at accepted
                cases requested : request image.context.program normalized (Images.rawState.encode normalized) with
                | error error => simp only [requested] at accepted; cases accepted
                | ok pending =>
                  simp only [requested] at accepted
                  cases header : Images.rawRequest.valid pending && Protocol.requestHeaderValid pending with
                  | false => simp [header] at accepted
                  | true =>
                    simp only [header, ↓reduceIte] at accepted
                    cases accepted
                    simpa only [nextInstance, Option.some.injEq, Protocol.Instance.state.injEq] using saved

theorem emitted_snapshot_is_admitted (image : Machine.ImageContext imageBytes programWitness)
    (state : Machine.State image.context.program) (witness : Graph.Admission.Witness)
    (outcome : Protocol.Outcome) (bytes : Bytes)
    (accepted : finish image state witness = .ok outcome)
    (saved : nextInstance outcome = some (.state bytes)) :
    ∃ normalized, Graph.Snapshot.canonicalize state.raw = some normalized ∧
      CertifiedState.decode image bytes witness = some normalized := by
  obtain ⟨normalized, canonical, valid, admitted, encoded⟩ := finish_saved_state _ _ _ _ _ accepted saved
  refine ⟨normalized, canonical, CertifiedState.decode_complete _ _ _ _ ?_
    ((Graph.Admission.check_exact _ _ _ _).mp admitted)⟩
  rw [← encoded]
  exact Graph.Snapshot.decode_encode_canonical _ _ canonical valid

theorem observed_outcome_finishes (image : Machine.ImageContext imageBytes programWitness)
    (input : Protocol.Input) (witness : InvocationWitness)
    (observation : Observation image.context.program)
    (accepted : observe image input witness = .ok observation) :
    finish image observation.state witness.outgoing = .ok observation.outcome := by
  cases mode : input.mode with
  | advance =>
    have accepted : advance image input witness.incoming witness.outgoing = .ok observation := by
      simpa only [observe, mode] using accepted
    obtain ⟨_, _, _, _, atState, _, finished⟩ := advance_uses_one_target_quantum _ _ _ _ _ accepted
    simpa only [atState] using finished
  | run =>
    have accepted : run image input witness.incoming witness.outgoing witness.internalSteps = .ok observation := by
      simpa only [observe, mode] using accepted
    obtain ⟨_, _, _, _, _, atState, _, finished⟩ := run_has_complete_internal_derivation _ _ _ _ _ _ accepted
    simpa only [atState] using finished

/-- Every saved state in an accepted public invocation can be admitted again
against the same image. This derives admission from the boundary operation;
it does not assert preservation of unobserved internal states. -/
theorem checked_invocation_emits_admitted_state (image : Machine.ImageContext imageBytes programWitness)
    (record : PublicInvocation) (before : Clock) (witness : InvocationWitness)
    (result : InvocationResult) (bytes : Bytes)
    (accepted : checkInvocation image record before witness = some result)
    (saved : result.next = some (.state bytes)) :
    ∃ (outgoing : Graph.Admission.Witness) (normalized : Graph.State),
      CertifiedState.decode image bytes outgoing = some normalized := by
  obtain ⟨input, invocation, observation, _, _, _, _, observed, _, _, atNext, _, _, _⟩ :=
    (checkInvocation_sound _ _ _ _ _ accepted).realized
  have saved : nextInstance observation.outcome = some (.state bytes) := atNext ▸ saved
  obtain ⟨normalized, _, admitted⟩ := emitted_snapshot_is_admitted _ _ _ _ _
    (observed_outcome_finishes _ _ _ _ observed) saved
  exact ⟨invocation.outgoing, normalized, admitted⟩

end BoundaryV2.Profile.Target.Boundary
