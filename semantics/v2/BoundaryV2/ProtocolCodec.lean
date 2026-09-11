import BoundaryV2.ProtocolIdentity
import BoundaryV2.Values

namespace BoundaryV2.Profile.Protocol

def reasonValid : Reason → Bool
  | .text bytes => UTF8.valid bytes
  | .bytes _ => true

def inputValid (input : Input) : Bool :=
  match input.instanceData, input.control with
  | .initialArgs _, .continueValue none => true
  | .initialArgs _, _ => false
  | .state _, .continueValue _ => true
  | .state _, .cancel reason => reasonValid reason

def cleanupFailuresValid (input : Bytes) : Bool := (Wire.NonemptyCodec.blob.list.toCodec.decode input).isSome

def outcomeValid : Outcome → Bool
  | .failed _ failures cancellation =>
    (cancellation.map reasonValid).getD true && cleanupFailuresValid failures
  | .cancelled reason failures => reasonValid reason && cleanupFailuresValid failures
  | _ => true

/-- Admission here is exactly the pure record codec's promise. For instance,
an `image` or `state` byte field is opaque to PKI2 record admission; the runtime
subsequently applies image/state admission against its own program. -/
def inputCodec : Wire.Codec Input := Images.rawInput.checked inputValid
def outcomeCodec : Wire.Codec Outcome := Images.rawOutcome.checked outcomeValid

theorem decode_input_exact (bytes : Bytes) (input : Input)
    (accepted : inputCodec.decode bytes = some input) :
    Images.rawInput.valid input = true ∧ inputValid input = true ∧ inputCodec.encode input = bytes := by
  have result := inputCodec.decode_exact bytes input accepted
  have both : Images.rawInput.valid input = true ∧ inputValid input = true := by
    simpa [inputCodec, Wire.Codec.checked] using result.1
  exact ⟨both.1, both.2, result.2⟩

theorem decode_outcome_exact (bytes : Bytes) (outcome : Outcome)
    (accepted : outcomeCodec.decode bytes = some outcome) :
    Images.rawOutcome.valid outcome = true ∧ outcomeValid outcome = true ∧
      outcomeCodec.encode outcome = bytes := by
  have result := outcomeCodec.decode_exact bytes outcome accepted
  have both : Images.rawOutcome.valid outcome = true ∧ outcomeValid outcome = true := by
    simpa [outcomeCodec, Wire.Codec.checked] using result.1
  exact ⟨both.1, both.2, result.2⟩

theorem cleanup_failures_exhausted (bytes : Bytes) (valid : cleanupFailuresValid bytes = true) :
    ∃ failures, (Wire.NonemptyCodec.blob.list.toCodec).valid failures = true ∧
      (Wire.NonemptyCodec.blob.list.toCodec).encode failures = bytes := by
  unfold cleanupFailuresValid at valid
  cases decoded : Wire.NonemptyCodec.blob.list.toCodec.decode bytes with
  | none => simp [decoded] at valid
  | some failures => exact ⟨failures, (Wire.NonemptyCodec.blob.list.toCodec.decode_exact bytes failures decoded)⟩

theorem initial_result_rejected (mode : Mode) (image arguments result : Bytes) :
    inputValid ⟨mode, image, .initialArgs arguments, .continueValue (some result)⟩ = false := rfl

theorem initial_cancel_rejected (mode : Mode) (image arguments : Bytes) (reason : Reason) :
    inputValid ⟨mode, image, .initialArgs arguments, .cancel reason⟩ = false := rfl

theorem malformed_cleanup_failures_rejected :
    cleanupFailuresValid [] = false ∧ cleanupFailuresValid [0, 0] = false ∧
      cleanupFailuresValid [1] = false ∧ cleanupFailuresValid [1, 2, 0] = false ∧
      cleanupFailuresValid [128, 0] = false := by decide +kernel

theorem opaque_cleanup_failure_values_preserved :
    cleanupFailuresValid [2, 0, 1, 255] = true := by decide +kernel

end BoundaryV2.Profile.Protocol
