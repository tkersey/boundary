import BoundaryV2.SourceInformationTypes
import Lean.Elab.Tactic.Cbv

namespace BoundaryV2.Profile.Source.Machine
namespace InformationCapacity

/-- The profile's sequence-length ceiling is operational here. Cleanup does
not turn this rejection into an authored `capacityExceeded` failure. -/
theorem failure_payload_overflow_rejected (context : Context) (schema : SchemaId .source)
    (exit : Cleanup.Exit .source) (tooLarge : wordLimit ≤ exit.failures.length) :
    cleanupInformation context schema exit = .error .capacity := by
  have overflow : ¬exit.failures.length < wordLimit := by omega
  simp [cleanupInformation, require, overflow, bind, Except.bind]

theorem cancellation_payload_overflow_rejected (context : Context) (schema : SchemaId .source)
    (exit : Cleanup.Exit .source) (reason : Protocol.Reason) (found : exit.cancellation = some reason)
    (tooLarge : match reason with | .text bytes | .bytes bytes => wordLimit ≤ bytes.length) :
    cleanupInformation context schema exit = .error .capacity := by
  have rejected : Codecs.reason.valid reason = false := by
    cases reason with
    | text bytes | bytes bytes =>
      change (decide (bytes.length < wordLimit) && true) = false
      simp [Nat.not_lt.mpr tooLarge]
  simp [cleanupInformation, found, rejected, require, bind, Except.bind]

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

/-- Even though cleanup preparation computes a candidate obligation update,
an oversized information record cannot publish that update as a successor. -/
theorem oversized_cleanup_has_no_successor (machine : State) (context : Context)
    (identity : ObligationId) (exit : Cleanup.Exit .source) (normal : Option Located)
    (tail : List Frame) (after : Transition) (tooLarge : wordLimit ≤ exit.failures.length) :
    beginCleanup machine context identity exit normal tail ≠ .ok after := by
  intro accepted
  have failures : (observedExit machine exit).failures = exit.failures := by
    unfold observedExit
    cases machine.cancellation <;> rfl
  simp only [beginCleanup, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, information, informationAt, _⟩ := accepted
  rw [failure_payload_overflow_rejected _ _ _ (by simpa only [failures] using tooLarge)] at informationAt
  contradiction

private def context : Context := {
  source := {
    entry := 0, failure := 0
    schemas := [.unit, .text, .bytes, .sum [1, 2], .sum [0, 0, 3, 0],
      .sum [0, 3], .seq 0, .product [4, 5, 6]]
    constants := [⟨0, []⟩], effects := [], handlers := [], regionCount := 0
    variables := [], values := [⟨0, .literal 0⟩], terms := [.value 0]
    functions := [{ parameters := [], result := 0, body := some 0 }] }
  captures := ⟨[[]], [[]], [[]]⟩
  constants := [.scalar 0 0]
  borrows := ⟨[], [⟨0, []⟩]⟩ }

private def information (failures : List SemanticValue) : SemanticValue :=
  .product 7 [.variant 4 0 (.scalar 0 0), .variant 5 0 (.scalar 0 0), .sequence 6 failures]

theorem information_layout_admitted :
    ControlAdmission.cleanupInfoValid (Admission.controlContext context.source) 7 = true := by
  decide_cbv

theorem representable_failures_keep_exact_information (failures : List SemanticValue)
    (bounded : failures.length < wordLimit) :
    cleanupInformation context 7 ⟨.normal (.scalar 0 0), failures, none⟩ = .ok (information failures) := by
  simp only [cleanupInformation, Option.all_none, Bool.and_true]
  rw [show require (decide (failures.length < wordLimit)) .capacity = .ok () by simp [require, bounded]]
  rfl

theorem last_representable_sequence_is_admitted :
    cleanupInformation context 7 ⟨.normal (.scalar 0 0), List.replicate (wordLimit - 1) (.scalar 0 0), none⟩ =
      .ok (information (List.replicate (wordLimit - 1) (.scalar 0 0))) := by
  apply representable_failures_keep_exact_information
  simp only [List.length_replicate]
  have positive : 0 < wordLimit := by decide
  omega

theorem first_unrepresentable_sequence_is_rejected :
    cleanupInformation context 7 ⟨.normal (.scalar 0 0), List.replicate wordLimit (.scalar 0 0), none⟩ =
      .error .capacity := by
  apply failure_payload_overflow_rejected
  simp

theorem oversized_byte_reason_is_rejected :
    cleanupInformation context 7 ⟨.cancellation, [], some (.bytes (List.replicate wordLimit 0))⟩ =
      .error .capacity := by
  apply cancellation_payload_overflow_rejected _ _ _ (.bytes (List.replicate wordLimit 0)) rfl
  simp

theorem malformed_text_reason_is_rejected :
    cleanupInformation context 7 ⟨.cancellation, [], some (.text [0xff])⟩ = .error .type := by
  cbv

end InformationCapacity
end BoundaryV2.Profile.Source.Machine
