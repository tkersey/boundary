import BoundaryV2.TargetExecution

namespace BoundaryV2.Profile.Target.Boundary

/-- A refusal is independent of the producer's witness choices, including
static borrow summaries. A bad witness cannot make a valid action refused. -/
def Refused (imageBytes inputBytes : Bytes) : Prop :=
  ∀ (programWitness : Admission.Witness) (image : Machine.ImageContext imageBytes programWitness)
    (outputBytes : Bytes) (before : Clock) (witness : InvocationWitness),
    checkInvocation image ⟨inputBytes, outputBytes⟩ before witness = none

theorem malformed_input_refused (imageBytes inputBytes : Bytes)
    (malformed : Protocol.inputCodec.decode inputBytes = none) : Refused imageBytes inputBytes := by
  intro programWitness image output before witness
  simp [checkInvocation, malformed, bind, Option.bind]

theorem different_image_refused (imageBytes inputBytes : Bytes) (input : Protocol.Input)
    (parsed : Protocol.inputCodec.decode inputBytes = some input)
    (different : input.image ≠ imageBytes) : Refused imageBytes inputBytes := by
  intro programWitness image output before witness
  cases checked : checkInvocation image ⟨inputBytes, output⟩ before witness with
  | none => rfl
  | some result =>
    obtain ⟨decoded, _, _, atInput, _, bound, _⟩ :=
      (checkInvocation_sound image ⟨inputBytes, output⟩ before witness result checked).realized
    have same : decoded = input := Option.some.inj (atInput.symm.trans parsed)
    exact False.elim (different (same ▸ bound))

private theorem image_program_unique (left : Machine.ImageContext bytes leftWitness)
    (right : Machine.ImageContext bytes rightWitness) : left.context.program = right.context.program := by
  have first := Images.decodeImage_complete left.context.program left.admitted.1 left.admitted.2.1
  have second := Images.decodeImage_complete right.context.program right.admitted.1 right.admitted.2.1
  rw [left.encoded] at first
  rw [right.encoded] at second
  exact Option.some.inj (first.symm.trans second)

private theorem observed_preparation (image : Machine.ImageContext imageBytes programWitness)
    (input : Protocol.Input) (witness : InvocationWitness) (observation : Observation image.context.program)
    (accepted : observe image input witness = .ok observation) :
    ∃ prepared, prepare image input witness.incoming = .ok prepared := by
  cases mode : input.mode with
  | advance =>
    obtain ⟨prepared, _, found, _⟩ := advance_uses_one_target_quantum image input witness.incoming witness.outgoing
      observation (by simpa [observe, mode] using accepted)
    exact ⟨prepared, found⟩
  | run =>
    obtain ⟨prepared, _, found, _⟩ := run_has_complete_internal_derivation image input witness.incoming witness.outgoing
      witness.internalSteps observation (by simpa [observe, mode] using accepted)
    exact ⟨prepared, found⟩

private theorem refuse_unpreparable (imageBytes inputBytes : Bytes) (input : Protocol.Input)
    (parsed : Protocol.inputCodec.decode inputBytes = some input)
    (prevented : ∀ (programWitness : Admission.Witness) (image : Machine.ImageContext imageBytes programWitness)
      (witness : InputWitness) (prepared : Prepared image.context.program),
      prepare image input witness ≠ .ok prepared) : Refused imageBytes inputBytes := by
  intro programWitness image output before witness
  cases checked : checkInvocation image ⟨inputBytes, output⟩ before witness with
  | none => rfl
  | some result =>
    obtain ⟨decoded, used, observation, atInput, _, _, _, observed, _⟩ :=
      (checkInvocation_sound image ⟨inputBytes, output⟩ before witness result checked).realized
    have same : decoded = input := Option.some.inj (atInput.symm.trans parsed)
    subst decoded
    obtain ⟨prepared, ready⟩ := observed_preparation image input used observation observed
    exact False.elim (prevented programWitness image used.incoming prepared ready)

private theorem saved_decode_required (image : Machine.ImageContext imageBytes programWitness)
    (input : Protocol.Input) (witness : InputWitness) (prepared : Prepared image.context.program)
    (instanceAt : input.instanceData = .state snapshot)
    (accepted : prepare image input witness = .ok prepared) :
    ∃ graph, CertifiedState.decode image snapshot witness.graph = some graph := by
  cases decoded : CertifiedState.decode image snapshot witness.graph with
  | some graph => exact ⟨graph, rfl⟩
  | none =>
    simp [prepare, instanceAt, decoded, Machine.require, Machine.fromOption, bind, Except.bind] at accepted
    by_cases allowed : input.image = imageBytes ∧ Protocol.inputValid input = true <;>
      by_cases arguments : witness.arguments = [] <;> simp [allowed, arguments] at accepted

private theorem saved_decode_parsed (image : Machine.ImageContext imageBytes programWitness)
    (snapshot : Bytes) (witness : Graph.Admission.Witness) (graph : Graph.State)
    (accepted : CertifiedState.decode image snapshot witness = some graph) :
    Graph.Snapshot.decode snapshot = some graph := by
  unfold CertifiedState.decode at accepted
  cases parsed : Graph.Snapshot.decode snapshot with
  | none => simp [parsed] at accepted
  | some actual =>
    simp [parsed] at accepted
    obtain ⟨_, rfl⟩ := accepted
    rfl

theorem malformed_state_refused (imageBytes inputBytes : Bytes) (input : Protocol.Input)
    (parsed : Protocol.inputCodec.decode inputBytes = some input)
    (instanceAt : input.instanceData = .state snapshot)
    (malformed : Graph.Snapshot.decode snapshot = none) : Refused imageBytes inputBytes := by
  apply refuse_unpreparable imageBytes inputBytes input parsed
  intro programWitness image witness prepared accepted
  obtain ⟨graph, decoded⟩ := saved_decode_required image input witness prepared instanceAt accepted
  have exact := saved_decode_parsed image snapshot witness.graph graph decoded
  simp [malformed] at exact

theorem different_state_identity_refused (reference : Machine.ImageContext imageBytes referenceWitness)
    (inputBytes : Bytes) (input : Protocol.Input) (graph : Graph.State)
    (parsed : Protocol.inputCodec.decode inputBytes = some input)
    (instanceAt : input.instanceData = .state snapshot)
    (snapshotAt : Graph.Snapshot.decode snapshot = some graph)
    (different : graph.programIdentity ≠ reference.identity) : Refused imageBytes inputBytes := by
  apply refuse_unpreparable imageBytes inputBytes input parsed
  intro programWitness image witness prepared accepted
  obtain ⟨actual, decoded⟩ := saved_decode_required image input witness prepared instanceAt accepted
  have same : actual = graph := Option.some.inj ((saved_decode_parsed image snapshot witness.graph actual decoded).symm.trans snapshotAt)
  subst actual
  have bound := (CertifiedState.decode_sound image snapshot witness.graph graph decoded).2.2.2.2.1
  have program := image_program_unique image reference
  exact different (by simpa [Machine.ImageContext.identity, program] using bound)

def responseHeader (program : Program) (graph : Graph.State) (snapshot bytes : Bytes) : Bool :=
  ((request program graph snapshot).toOption).any (fun request =>
    (Images.rawResult.decode bytes).any (Protocol.resultBindingValid request))

private theorem accepted_response_header (image : Machine.ImageContext imageBytes programWitness)
    (graph : Graph.State) (snapshot bytes : Bytes) (state : Machine.State image.context.program)
    (witness : ResponseWitness) (transition : Machine.Transition image.context.program)
    (accepted : acceptResponse image graph snapshot bytes state witness = .ok transition) :
    responseHeader image.context.program graph snapshot bytes = true := by
  cases requested : request image.context.program graph snapshot with
  | error error => simp [acceptResponse, requested, bind, Except.bind] at accepted
  | ok request =>
    cases parsed : Images.rawResult.decode bytes with
    | none => simp [acceptResponse, requested, parsed, Machine.fromOption, bind, Except.bind] at accepted
    | some result =>
      have checked : Protocol.checkResult request result witness.descriptorPayload witness.descriptorResponse = true := by
        by_cases checked : Protocol.checkResult request result witness.descriptorPayload witness.descriptorResponse = true
        · exact checked
        · simp [acceptResponse, requested, parsed, checked, Machine.fromOption, Machine.require, bind, Except.bind] at accepted
      have meaning := Protocol.checkResult_sound request result witness.descriptorPayload witness.descriptorResponse checked
      have binding := (Protocol.result_binding_exact request result).mpr ⟨meaning.identity, meaning.schemaDigest⟩
      simp [responseHeader, requested, parsed, binding, Except.toOption]

private theorem prepared_response_header (image : Machine.ImageContext imageBytes programWitness)
    (input : Protocol.Input) (witness : InputWitness) (prepared : Prepared image.context.program)
    (graph : Graph.State) (instanceAt : input.instanceData = .state snapshot)
    (controlAt : input.control = .continueValue (some bytes))
    (snapshotAt : Graph.Snapshot.decode snapshot = some graph)
    (accepted : prepare image input witness = .ok prepared) :
    responseHeader image.context.program graph snapshot bytes = true := by
  have bound := prepare_binds_complete_image image input witness prepared accepted
  have valid : Protocol.inputValid input = true := by simp [Protocol.inputValid, instanceAt, controlAt]
  have guard : (input.image == imageBytes && Protocol.inputValid input) = true := by simp [bound, valid]
  obtain ⟨actual, saved⟩ := saved_decode_required image input witness prepared instanceAt accepted
  have same : actual = graph := Option.some.inj ((saved_decode_parsed image snapshot witness.graph actual saved).symm.trans snapshotAt)
  subst actual
  by_cases arguments : witness.arguments = []
  · simp [prepare, instanceAt, controlAt, guard, arguments, saved, Machine.require, Machine.fromOption,
      bind, Except.bind] at accepted
    cases restored : restore image graph witness.graph witness.clock with
    | error error => simp [restored] at accepted
    | ok state =>
      simp only [restored] at accepted
      cases responseAt : witness.response with
      | none => simp [responseAt] at accepted
      | some response =>
        simp only [responseAt] at accepted
        cases responded : acceptResponse image graph snapshot bytes state response with
        | error error => simp [responded] at accepted
        | ok transition => exact accepted_response_header image graph snapshot bytes state response transition responded
  · simp [prepare, instanceAt, guard, arguments, Machine.require, bind, Except.bind] at accepted

theorem response_header_refused (reference : Machine.ImageContext imageBytes referenceWitness)
    (inputBytes : Bytes) (input : Protocol.Input) (graph : Graph.State)
    (parsed : Protocol.inputCodec.decode inputBytes = some input)
    (instanceAt : input.instanceData = .state snapshot)
    (controlAt : input.control = .continueValue (some bytes))
    (snapshotAt : Graph.Snapshot.decode snapshot = some graph)
    (refused : responseHeader reference.context.program graph snapshot bytes = false) : Refused imageBytes inputBytes := by
  apply refuse_unpreparable imageBytes inputBytes input parsed
  intro programWitness image witness prepared accepted
  have checked := prepared_response_header image input witness prepared graph instanceAt controlAt snapshotAt accepted
  have same := image_program_unique image reference
  simp [same, refused] at checked

inductive Backend where
  | native | wasm
  deriving DecidableEq, Repr

/-- These are complete physical observations. Diagnostic bytes are retained
without claiming that an embedding's wording is a machine event. -/
structure RefusalRecord where
  backend : Backend
  input : Bytes
  output : Bytes
  diagnostic : Bytes
  inputAfter : Bytes
  status : Nat
  deriving DecidableEq, Repr

def refusalSurfaceValid (record : RefusalRecord) : Bool :=
  record.output.isEmpty && !record.diagnostic.isEmpty && record.inputAfter == record.input &&
    match record.backend with
    | .native => 0 < record.status && record.status < 256
    | .wasm => record.status == 2

/-- Refusal recognizes malformed records and mismatched complete image/state
bindings. Other refusal causes require their own uniform proof. -/
def checkRefusal (image : Machine.ImageContext imageBytes programWitness) (record : RefusalRecord) : Bool :=
  refusalSurfaceValid record &&
    match Protocol.inputCodec.decode record.input with
    | none => true
    | some input =>
      if input.image != imageBytes then true else
        match input.instanceData with
        | .initialArgs _ => false
        | .state snapshot =>
          match Graph.Snapshot.decode snapshot with
          | none => true
          | some graph => graph.programIdentity != image.identity ||
              match input.control with
              | .continueValue (some bytes) => !responseHeader image.context.program graph snapshot bytes
              | _ => false

theorem checkRefusal_sound (image : Machine.ImageContext imageBytes programWitness) (record : RefusalRecord)
    (accepted : checkRefusal image record = true) :
    refusalSurfaceValid record = true ∧ Refused imageBytes record.input := by
  simp only [checkRefusal, Bool.and_eq_true] at accepted
  refine ⟨accepted.1, ?_⟩
  cases parsed : Protocol.inputCodec.decode record.input with
  | none => exact malformed_input_refused imageBytes record.input parsed
  | some input =>
    by_cases different : input.image ≠ imageBytes
    · exact different_image_refused imageBytes record.input input parsed different
    · have checked := accepted.2
      simp only [parsed, bne_iff_ne, different, ↓reduceIte] at checked
      cases instanceAt : input.instanceData with
      | initialArgs bytes => simp [instanceAt] at checked
      | state snapshot =>
        cases snapshotAt : Graph.Snapshot.decode snapshot with
        | none => exact malformed_state_refused imageBytes record.input input parsed instanceAt snapshotAt
        | some graph =>
          by_cases different : graph.programIdentity ≠ image.identity
          · exact different_state_identity_refused image record.input input graph parsed instanceAt snapshotAt different
          · have same : graph.programIdentity = image.identity := Classical.byContradiction different
            simp [instanceAt, snapshotAt, same] at checked
            cases controlAt : input.control with
            | cancel reason => simp [controlAt] at checked
            | continueValue response =>
              cases response with
              | none => simp [controlAt] at checked
              | some bytes =>
                exact response_header_refused image record.input input graph parsed instanceAt controlAt snapshotAt
                  (by simpa [controlAt] using checked)

/-- Image admission supplies a nonempty semantic subject. The refusal itself
quantifies over every admitted interpretation and every invocation witness. -/
structure CertifiedRefusal (imageBytes : Bytes) (record : RefusalRecord) : Prop where
  admittedImage : ∃ (programWitness : Admission.Witness), Nonempty (Machine.ImageContext imageBytes programWitness)
  surface : refusalSurfaceValid record = true
  refused : Refused imageBytes record.input

/-- Keep every captured byte and status in the certificate's type index.
The indexed construction preserves the original refusal obligations exactly. -/
theorem certified_refusal_iff (imageBytes : Bytes) (record : RefusalRecord) :
    CertifiedRefusal imageBytes record ↔
      (∃ (programWitness : Admission.Witness), Nonempty (Machine.ImageContext imageBytes programWitness)) ∧
        refusalSurfaceValid record = true ∧ Refused imageBytes record.input := by
  constructor
  · intro checked
    exact ⟨checked.admittedImage, checked.surface, checked.refused⟩
  · intro checked
    exact ⟨checked.1, checked.2.1, checked.2.2⟩

theorem certify_refusal (image : Machine.ImageContext imageBytes programWitness) (record : RefusalRecord)
    (accepted : checkRefusal image record = true) : CertifiedRefusal imageBytes record :=
  ⟨⟨programWitness, ⟨image⟩⟩, (checkRefusal_sound image record accepted).1,
    (checkRefusal_sound image record accepted).2⟩

theorem refused_record_has_no_commit (imageBytes : Bytes) (record : RefusalRecord)
    (accepted : CertifiedRefusal imageBytes record) :
    record.output = [] ∧ record.inputAfter = record.input := by
  have surface := accepted.surface
  simp only [refusalSurfaceValid, Bool.and_eq_true, beq_iff_eq] at surface
  exact ⟨by simpa using surface.1.1.1, surface.1.2⟩

end BoundaryV2.Profile.Target.Boundary
