import BoundaryV2.TargetRun

namespace BoundaryV2.Profile.Target.Boundary

structure PublicInvocation where
  input : Bytes
  output : Bytes
  deriving DecidableEq, Repr

structure InvocationWitness where
  incoming : InputWitness
  outgoing : Graph.Admission.Witness
  internalSteps : Nat

def observe (image : Machine.ImageContext imageBytes programWitness) (input : Protocol.Input)
    (witness : InvocationWitness) : Except Machine.Invalid (Observation image.context.program) :=
  match input.mode with
  | .advance => advance image input witness.incoming witness.outgoing
  | .run => run image input witness.incoming witness.outgoing witness.internalSteps

def nextInstance : Protocol.Outcome → Option Protocol.Instance
  | .progressed state | .requested state _ | .yielded state => some (.state state)
  | .completed _ | .failed .. | .cancelled .. | .needsCapacity _ => none

def terminalOutcome : Protocol.Outcome → Bool
  | .completed _ | .failed .. | .cancelled .. => true
  | _ => false

structure InvocationResult where
  instanceData : Protocol.Instance
  next : Option Protocol.Instance
  clock : Clock
  events : List Machine.Event
  terminal : Bool

/-- Check the complete captured invocation. The witness supplies finite data
and a path length; neither expected output bytes nor a producer's verdict can
change the reconstructed target transition. -/
def checkInvocation (image : Machine.ImageContext imageBytes programWitness) (record : PublicInvocation)
    (before : Clock) (witness : InvocationWitness) : Option InvocationResult := do
  if witness.incoming.clock != before then none else do
    let input ← Protocol.inputCodec.decode record.input
    let observation ← (observe image input witness).toOption
    if Protocol.outcomeCodec.encode observation.outcome != record.output then none else
      some ⟨input.instanceData, nextInstance observation.outcome, clock observation.state,
        observation.events, terminalOutcome observation.outcome⟩

/-- The logical subject includes every public input/output byte. Semantic
events and the request clock are the result of the checked machine execution;
they are not inferred by deduplicating public request records. -/
structure InvocationMeaning (image : Machine.ImageContext imageBytes programWitness)
    (record : PublicInvocation) (before : Clock) (result : InvocationResult) : Prop where
  realized : ∃ (input : Protocol.Input) (witness : InvocationWitness)
      (observation : Observation image.context.program),
    Protocol.inputCodec.decode record.input = some input ∧
    Protocol.inputCodec.encode input = record.input ∧
    input.image = imageBytes ∧ witness.incoming.clock = before ∧
    observe image input witness = .ok observation ∧
    Protocol.outcomeCodec.encode observation.outcome = record.output ∧
    result.instanceData = input.instanceData ∧ result.next = nextInstance observation.outcome ∧
    result.clock = clock observation.state ∧ result.events = observation.events ∧
    result.terminal = terminalOutcome observation.outcome

theorem observe_binds_image (image : Machine.ImageContext imageBytes programWitness)
    (input : Protocol.Input) (witness : InvocationWitness) (observation : Observation image.context.program)
    (accepted : observe image input witness = .ok observation) : input.image = imageBytes := by
  cases mode : input.mode with
  | advance =>
    have accepted : advance image input witness.incoming witness.outgoing = .ok observation := by
      simpa [observe, mode] using accepted
    obtain ⟨prepared, _, atPrepared, _⟩ := advance_uses_one_target_quantum _ _ _ _ _ accepted
    exact prepare_binds_complete_image _ _ _ prepared atPrepared
  | run =>
    have accepted : run image input witness.incoming witness.outgoing witness.internalSteps = .ok observation := by
      simpa [observe, mode] using accepted
    obtain ⟨prepared, _, atPrepared, _⟩ := run_has_complete_internal_derivation _ _ _ _ _ _ accepted
    exact prepare_binds_complete_image _ _ _ prepared atPrepared

theorem checkInvocation_sound (image : Machine.ImageContext imageBytes programWitness)
    (record : PublicInvocation) (before : Clock) (witness : InvocationWitness) (result : InvocationResult)
    (accepted : checkInvocation image record before witness = some result) :
    InvocationMeaning image record before result := by
  unfold checkInvocation at accepted
  split at accepted
  · cases accepted
  · rename_i atClock
    have atClock : witness.incoming.clock = before := by simpa using atClock
    cases atInput : Protocol.inputCodec.decode record.input with
    | none => simp [atInput] at accepted
    | some input =>
      simp only [atInput, bind, Option.bind] at accepted
      cases observed : observe image input witness with
      | error error => simp [observed, Except.toOption] at accepted
      | ok observation =>
        simp only [observed, Except.toOption] at accepted
        split at accepted
        · cases accepted
        · rename_i output
          have output : Protocol.outcomeCodec.encode observation.outcome = record.output := by simpa using output
          cases accepted
          exact ⟨⟨input, witness, observation, atInput, (Protocol.decode_input_exact _ _ atInput).2.2,
            observe_binds_image _ _ _ _ observed, atClock, observed, output, rfl, rfl, rfl, rfl, rfl⟩⟩

structure Continuation where
  instanceData : Option Protocol.Instance
  clock : Clock
  terminal : Bool
  deriving DecidableEq, Repr

def InvocationResult.continuation (result : InvocationResult) : Continuation :=
  ⟨result.next, result.clock, result.terminal⟩

structure SegmentResult where
  continuation : Continuation
  events : List Machine.Event

/-- Every successor consumes the exact state bytes emitted by its predecessor.
Finishing an execution leaves no resumable instance. An arbitrary starting
PST2 is admitted by the first invocation, without claiming historical origin. -/
def checkSegment (image : Machine.ImageContext imageBytes programWitness) :
    List PublicInvocation → List InvocationWitness → Continuation → Option SegmentResult
  | [], [], before => some ⟨before, []⟩
  | record :: records, witness :: witnesses, before => do
    let expected ← before.instanceData
    let result ← checkInvocation image record before.clock witness
    if result.instanceData != expected then none else do
      let rest ← checkSegment image records witnesses result.continuation
      some ⟨rest.continuation, result.events ++ rest.events⟩
  | _, _, _ => none

inductive SegmentMeaning (image : Machine.ImageContext imageBytes programWitness) :
    List PublicInvocation → Continuation → List Machine.Event → Continuation → Prop where
  | empty : SegmentMeaning image [] before [] before
  | invocation : before.instanceData = some result.instanceData →
      InvocationMeaning image record before.clock result →
      SegmentMeaning image records result.continuation later final →
      SegmentMeaning image (record :: records) before (result.events ++ later) final

theorem checkSegment_sound (image : Machine.ImageContext imageBytes programWitness)
    (records : List PublicInvocation) (witnesses : List InvocationWitness)
    (before : Continuation) (result : SegmentResult)
    (accepted : checkSegment image records witnesses before = some result) :
    SegmentMeaning image records before result.events result.continuation := by
  induction records generalizing witnesses before result with
  | nil =>
    cases witnesses with
    | nil => simp [checkSegment] at accepted; cases accepted; exact .empty
    | cons _ _ => simp [checkSegment] at accepted
  | cons record records ih =>
    cases witnesses with
    | nil => simp [checkSegment] at accepted
    | cons witness witnesses =>
      simp only [checkSegment, bind, Option.bind] at accepted
      cases instanceAt : before.instanceData with
      | none => simp [instanceAt] at accepted
      | some expected =>
        simp only [instanceAt] at accepted
        cases atRecord : checkInvocation image record before.clock witness with
        | none => simp [atRecord] at accepted
        | some current =>
          simp only [atRecord] at accepted
          split at accepted
          · cases accepted
          · rename_i same
            have same : current.instanceData = expected := by simpa using same
            cases atRest : checkSegment image records witnesses current.continuation with
            | none => simp [atRest] at accepted
            | some rest =>
              simp only [atRest] at accepted
              cases accepted
              exact .invocation (by simpa [same] using instanceAt)
                (checkInvocation_sound _ _ _ _ _ atRecord) (ih _ _ _ atRest)

theorem segment_composition (image : Machine.ImageContext imageBytes programWitness)
    (first : SegmentMeaning image early before events middle)
    (second : SegmentMeaning image later middle more final) :
    SegmentMeaning image (early ++ later) before (events ++ more) final := by
  induction first with
  | empty => simpa using second
  | invocation atInstance meaning _ ih =>
    simpa [List.append_assoc] using SegmentMeaning.invocation atInstance meaning (ih second)

inductive SegmentClaim where
  | completed | prefix
  deriving DecidableEq, Repr

def checkExecution (image : Machine.ImageContext imageBytes programWitness)
    (records : List PublicInvocation) (witnesses : List InvocationWitness)
    (before : Continuation) (claim : SegmentClaim) : Option SegmentResult := do
  if records.isEmpty then none else do
    let result ← checkSegment image records witnesses before
    if claim == .completed && !result.continuation.terminal then none else some result

theorem completed_execution_is_terminal (image : Machine.ImageContext imageBytes programWitness)
    (records : List PublicInvocation) (witnesses : List InvocationWitness)
    (before : Continuation) (result : SegmentResult)
    (accepted : checkExecution image records witnesses before .completed = some result) :
    records ≠ [] ∧ SegmentMeaning image records before result.events result.continuation ∧
      result.continuation.terminal = true := by
  unfold checkExecution at accepted
  split at accepted
  · cases accepted
  · rename_i nonempty
    cases checked : checkSegment image records witnesses before with
    | none => simp [checked] at accepted
    | some found =>
      simp only [checked, bind, Option.bind] at accepted
      split at accepted
      · cases accepted
      · rename_i terminal
        cases accepted
        exact ⟨by simpa using nonempty, checkSegment_sound _ _ _ _ _ checked, by simpa using terminal⟩

/-- A complete execution from an actual initial-argument invocation. Every
record is byte-bound, every intervening saved state is admitted, every internal
run ends at its stated boundary, and the last invocation is terminal. This
states target/runtime agreement; source compilation agreement is separate. -/
def CertifiedInitialExecution (imageBytes : Bytes) (records : List PublicInvocation) : Prop :=
  ∃ (programWitness : Admission.Witness) (image : Machine.ImageContext imageBytes programWitness)
    (arguments : Bytes) (result : SegmentResult),
    records ≠ [] ∧
    SegmentMeaning image records ⟨some (.initialArgs arguments), ⟨0, none⟩, false⟩ result.events result.continuation ∧
    result.continuation.terminal = true

theorem certify_initial_execution (image : Machine.ImageContext imageBytes programWitness)
    (records : List PublicInvocation) (witnesses : List InvocationWitness) (arguments : Bytes)
    (checked : (checkExecution image records witnesses ⟨some (.initialArgs arguments), ⟨0, none⟩, false⟩ .completed).isSome = true) :
    CertifiedInitialExecution imageBytes records := by
  cases accepted : checkExecution image records witnesses ⟨some (.initialArgs arguments), ⟨0, none⟩, false⟩ .completed with
  | none => simp [accepted] at checked
  | some result =>
    exact ⟨programWitness, image, arguments, result, completed_execution_is_terminal _ _ _ _ _ accepted⟩

end BoundaryV2.Profile.Target.Boundary
