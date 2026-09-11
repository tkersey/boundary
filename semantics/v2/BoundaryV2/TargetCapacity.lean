import BoundaryV2.TargetExecution

namespace BoundaryV2.Profile.Target.Boundary

structure CapacityFollowup where
  invocation : PublicInvocation
  inputAfter : Bytes
  prepareStatus : Nat
  executeStatus : Nat
  deriving DecidableEq, Repr

/-- Complete WASM capacity and retry observations. A failed input reservation
has no guest input buffer observation; the caller's bytes are still retained. -/
structure CapacityRecord where
  input : Bytes
  output : Bytes
  callerInputAfter : Bytes
  guestInputAfter : Option Bytes
  prepareStatus : Nat
  executeStatus : Option Nat
  retry : PublicInvocation
  retryInputAfter : Bytes
  retryPrepareStatus : Nat
  retryExecuteStatus : Nat
  followups : List CapacityFollowup := []
  deriving DecidableEq, Repr

def capacityFollowupsValid (record : CapacityRecord) : Bool :=
  record.followups.all (fun next => next.inputAfter == next.invocation.input &&
    next.prepareStatus == 0 && next.executeStatus == 0)

def capacitySurfaceValid (record : CapacityRecord) : Bool :=
  record.callerInputAfter == record.input && record.retry.input == record.input &&
  record.retryInputAfter == record.input && record.retryPrepareStatus == 0 &&
  record.retryExecuteStatus == 0 &&
    match record.guestInputAfter with
    | none => record.prepareStatus == 1 && record.executeStatus.isNone
    | some bytes => record.prepareStatus == 0 && record.executeStatus == some 0 && bytes == record.input

/-- The complete capacity record is decoded and retained. Its measured amounts
are not asserted to be an allocation theorem of the logical target machine. -/
def capacityEnvelopeValid (record : CapacityRecord) : Bool :=
  capacitySurfaceValid record && (Protocol.outcomeCodec.decode record.output).any (fun outcome =>
    match outcome with
    | .needsCapacity capacity => record.guestInputAfter.isSome || capacity.arena == .input
    | _ => false)

def checkCapacityRetry (image : Machine.ImageContext imageBytes programWitness)
    (record : CapacityRecord) (before : Clock) (witness : InvocationWitness) : Option InvocationResult :=
  if capacityEnvelopeValid record then checkInvocation image record.retry before witness else none

structure CapacityMeaning (image : Machine.ImageContext imageBytes programWitness)
    (record : CapacityRecord) (before : Clock) (result : InvocationResult) : Prop where
  envelope : capacityEnvelopeValid record = true
  retry : InvocationMeaning image record.retry before result

theorem checkCapacityRetry_sound (image : Machine.ImageContext imageBytes programWitness)
    (record : CapacityRecord) (before : Clock) (witness : InvocationWitness) (result : InvocationResult)
    (checked : checkCapacityRetry image record before witness = some result) :
    CapacityMeaning image record before result := by
  unfold checkCapacityRetry at checked
  split at checked
  · rename_i envelope
    exact ⟨envelope, checkInvocation_sound image record.retry before witness result checked⟩
  · cases checked

/-- A capacity certificate binds the complete measured envelope and the
successful retry. It makes no claim that capacity pressure performed a target
transition or that reported allocation quantities follow from target semantics. -/
def CertifiedCapacityRetry (imageBytes : Bytes) (record : CapacityRecord) (before : Clock) : Prop :=
  ∃ (programWitness : Admission.Witness) (image : Machine.ImageContext imageBytes programWitness)
    (result : InvocationResult), CapacityMeaning image record before result

/-- A completed capacity scenario retains all physical retry observations and
requires the same complete execution claim used for ordinary invocations. -/
structure CertifiedCapacityExecution (imageBytes : Bytes) (record : CapacityRecord) : Prop where
  envelope : capacityEnvelopeValid record = true
  followups : capacityFollowupsValid record = true
  execution : CertifiedInitialExecution imageBytes
    (record.retry :: record.followups.map CapacityFollowup.invocation)

def checkCapacityExecution (image : Machine.ImageContext imageBytes programWitness)
    (record : CapacityRecord) (witnesses : List InvocationWitness) (arguments : Bytes) :
    Option SegmentResult :=
  if capacityEnvelopeValid record && capacityFollowupsValid record then
    checkExecution image (record.retry :: record.followups.map CapacityFollowup.invocation) witnesses
      ⟨some (.initialArgs arguments), ⟨0, none⟩, false⟩ .completed
  else none

theorem checkCapacityExecution_sound (image : Machine.ImageContext imageBytes programWitness)
    (record : CapacityRecord) (witnesses : List InvocationWitness) (arguments : Bytes)
    (checked : (checkCapacityExecution image record witnesses arguments).isSome = true) :
    CertifiedCapacityExecution imageBytes record := by
  unfold checkCapacityExecution at checked
  split at checked
  · rename_i valid
    have valid : capacityEnvelopeValid record = true ∧ capacityFollowupsValid record = true := by
      simpa only [Bool.and_eq_true] using valid
    exact ⟨valid.1, valid.2, certify_initial_execution image _ witnesses arguments checked⟩
  · cases checked

theorem certify_capacity_execution (record : CapacityRecord)
    (execution : CertifiedInitialExecution imageBytes
      (record.retry :: record.followups.map CapacityFollowup.invocation))
    (envelope : capacityEnvelopeValid record = true)
    (followups : capacityFollowupsValid record = true) :
    CertifiedCapacityExecution imageBytes record := ⟨envelope, followups, execution⟩

theorem capacity_followups_preserve_input (accepted : CertifiedCapacityExecution imageBytes record)
    (next : CapacityFollowup) (member : next ∈ record.followups) :
    next.inputAfter = next.invocation.input ∧ next.prepareStatus = 0 ∧ next.executeStatus = 0 := by
  have checked := List.all_eq_true.mp accepted.followups next member
  simpa only [Bool.and_eq_true, beq_iff_eq, and_assoc] using checked

theorem certify_capacity_retry (image : Machine.ImageContext imageBytes programWitness)
    (record : CapacityRecord) (before : Clock) (witness : InvocationWitness)
    (checked : (checkCapacityRetry image record before witness).isSome = true) :
    CertifiedCapacityRetry imageBytes record before := by
  cases found : checkCapacityRetry image record before witness with
  | none => simp [found] at checked
  | some result => exact ⟨programWitness, image, result, checkCapacityRetry_sound image record before witness result found⟩

/-- Reuse a checked initial execution when its first public invocation is the
captured retry. Every capacity attempt retains its own exact envelope. -/
theorem capacity_of_initial_head (record : CapacityRecord) (rest : List PublicInvocation)
    (execution : CertifiedInitialExecution imageBytes (record.retry :: rest))
    (envelope : capacityEnvelopeValid record = true) :
    CertifiedCapacityRetry imageBytes record ⟨0, none⟩ := by
  obtain ⟨programWitness, image, arguments, result, _, meaning, _⟩ := execution
  rcases result with ⟨final, events⟩
  cases meaning with
  | invocation linked first later => exact ⟨programWitness, image, _, ⟨envelope, first⟩⟩

theorem capacity_preserves_input (record : CapacityRecord)
    (accepted : capacityEnvelopeValid record = true) :
    record.callerInputAfter = record.input ∧ record.retry.input = record.input ∧
    record.retryInputAfter = record.input ∧
    ∀ bytes, record.guestInputAfter = some bytes → bytes = record.input := by
  have surface : capacitySurfaceValid record = true := by
    simp only [capacityEnvelopeValid, Bool.and_eq_true] at accepted
    exact accepted.1
  simp only [capacitySurfaceValid, Bool.and_eq_true, beq_iff_eq] at surface
  refine ⟨surface.1.1.1.1.1, surface.1.1.1.1.2, surface.1.1.1.2, ?_⟩
  intro bytes installed
  have guest := surface.2
  simp only [installed, Bool.and_eq_true, beq_iff_eq] at guest
  exact guest.2

theorem capacity_has_no_committed_state (record : CapacityRecord)
    (accepted : capacityEnvelopeValid record = true) :
    ∃ capacity, Protocol.outcomeCodec.decode record.output = some (.needsCapacity capacity) ∧
      Protocol.outcomeCodec.encode (.needsCapacity capacity) = record.output ∧
      nextInstance (.needsCapacity capacity) = none ∧ terminalOutcome (.needsCapacity capacity) = false := by
  simp only [capacityEnvelopeValid, Bool.and_eq_true, Option.any_eq_true] at accepted
  obtain ⟨outcome, parsed, checked⟩ := accepted.2
  cases outcome <;> try contradiction
  rename_i capacity
  exact ⟨capacity, parsed, (Protocol.outcomeCodec.decode_exact _ _ parsed).2, rfl, rfl⟩

/-- Erasing the no-commit capacity observation leaves precisely the checked
retry invocation, with the same incoming clock and full original input bytes. -/
theorem capacity_retry_uses_original_input (image : Machine.ImageContext imageBytes programWitness)
    (record : CapacityRecord) (before : Clock) (result : InvocationResult)
    (meaning : CapacityMeaning image record before result) :
    InvocationMeaning image ⟨record.input, record.retry.output⟩ before result := by
  have unchanged := (capacity_preserves_input record meaning.envelope).2.1
  have same : record.retry = ⟨record.input, record.retry.output⟩ :=
    congrArg (fun input => PublicInvocation.mk input record.retry.output) unchanged
  exact same ▸ meaning.retry

end BoundaryV2.Profile.Target.Boundary
