import BoundaryV2.GraphAdmission
import BoundaryV2.ProtocolAdmission

namespace BoundaryV2.Profile.Target.Boundary

open Machine (SemanticValue Invalid require fromOption)

structure Clock where
  next : Nat
  pending : Option RequestOccurrence
  deriving DecidableEq, Repr

def Clock.valid (clock : Clock) (status : Graph.Status) : Bool :=
  clock.pending.isSome == (status == .parked) && clock.pending.all (fun occurrence => occurrence.value < clock.next)

def clock (state : Machine.State program) : Clock := ⟨state.nextOccurrence, state.pendingOccurrence⟩

/-- The logical request clock is certificate data, not a wire field. A segment
must carry it across its boundaries; repeated identical ERQ2 bytes do not reset
the occurrence counter or identify distinct operations with each other. -/
def restore (image : Machine.ImageContext imageBytes programWitness) (state : Graph.State)
    (witness : Graph.Admission.Witness) (clock : Clock) : Except Invalid (Machine.State image.context.program) := do
  require (Graph.Admission.check image.context.program programWitness.borrows state witness) .scope
  require (clock.valid state.status) .witness
  let store ← fromOption (Machine.Store.importGraph image.context.program.schemas state witness.blobs) .witness
  pure ⟨state.programIdentity, store, state.status, state.roots, none, clock.next, clock.pending⟩

theorem restoration_preserves_complete_graph (image : Machine.ImageContext imageBytes programWitness)
    (graph : Graph.State) (witness : Graph.Admission.Witness) (clock : Clock)
    (state : Machine.State image.context.program)
    (accepted : restore image graph witness clock = .ok state) : state.raw = graph := by
  unfold restore at accepted
  simp only [bind, Except.bind] at accepted
  split at accepted
  · cases accepted
  · split at accepted
    · cases accepted
    · cases imported : Machine.Store.importGraph image.context.program.schemas graph witness.blobs with
      | none => simp [fromOption, imported] at accepted
      | some store =>
        simp [fromOption, imported] at accepted
        cases accepted
        exact Machine.Store.import_preserves_exact_graph _ _ _ _ imported

def externalBytes (program : Program) (expected : SchemaId .target) (value : SemanticValue) : Except Invalid Bytes := do
  require (value.schema == expected && Profile.Value.externalValid program.schemas value) .type
  pure (Profile.Value.encode program.schemas value)

def graphBytes (program : Program) (state : Graph.State) (expected : SchemaId .target)
    (value : Graph.Value) : Except Invalid Bytes := do
  require (Graph.Admission.valueValid program state value expected) .type
  match value.body with
  | .scalar bytes =>
    let shape ← fromOption program.schemas[expected.value]? .type
    let width ← fromOption (Profile.Value.scalarWidth shape) .type
    pure (bytes.toList.take width)
  | .blob reference => pure (← fromOption state.blobs[reference.value]? .reference).bytes
  | .reference _ | .owned _ => throw .type

def descriptorBytes (program : Program) (schema : SchemaId .target) : Except Invalid Bytes :=
  fromOption (SchemaDescriptor.encode ⟨schema, program.schemas⟩) .type

def request (program : Program) (state : Graph.State) (snapshot : Bytes) : Except Invalid Protocol.Request := do
  let pending ← fromOption state.roots.pending .inactive
  let .pending effect payload _ source ← fromOption state.nodes[pending.value]? .reference | throw .type
  let effect ← fromOption program.effects[effect.value]? .reference
  let payloadSchema ← descriptorBytes program effect.payload
  let resumeSchema ← descriptorBytes program effect.result
  let payload ← graphBytes program state effect.payload payload
  let stateDigest := SHA256.hash snapshot
  let value : Protocol.Request := {
    programIdentity := state.programIdentity
    pendingStateDigest := stateDigest
    residualContractDigest := Protocol.contractIdentity effect.identity payloadSchema resumeSchema
    continuationBindingDigest := Protocol.continuationIdentity state.programIdentity stateDigest source (SHA256.hash resumeSchema)
    semanticIdentity := effect.identity
    payloadSchema := payloadSchema
    resumeSchema := resumeSchema
    payload := payload
    requestIdentity := Vector.replicate 32 0 }
  pure (Protocol.bindRequest value)

def terminal (program : Program) : Machine.Result → Except Invalid Protocol.Outcome
  | .completed value => return .completed (← externalBytes program program.roots.result value)
  | .failed value failures cancellation => do
    let value ← externalBytes program program.roots.failure value
    let failures ← failures.mapM (externalBytes program program.roots.failure)
    pure (.failed value (Wire.NonemptyCodec.blob.list.toCodec.encode failures) cancellation)
  | .cancelled reason failures => do
    let failures ← failures.mapM (externalBytes program program.roots.failure)
    pure (.cancelled reason (Wire.NonemptyCodec.blob.list.toCodec.encode failures))

/-- This is the public boundary operation: normalize complete graph records,
admit the resulting state, and derive every request field from that same state.
Logical transition and collection preservation are separate laws. -/
def finish (image : Machine.ImageContext imageBytes programWitness) (state : Machine.State image.context.program)
    (witness : Graph.Admission.Witness) : Except Invalid Protocol.Outcome := do
  require (state.identity == image.identity) .witness
  require ((clock state).valid state.status) .witness
  match state.result with
  | some result => terminal image.context.program result
  | none =>
    let normalized ← fromOption (Graph.Snapshot.canonicalize state.raw) .reference
    require (Images.rawState.valid normalized) .reference
    require (Graph.Admission.check image.context.program programWitness.borrows normalized witness) .scope
    let bytes := Images.rawState.encode normalized
    match state.status with
    | .active | .unwinding => pure (.progressed bytes)
    | .yielded => pure (.yielded bytes)
    | .parked =>
      let pending ← request image.context.program normalized bytes
      require (Images.rawRequest.valid pending && Protocol.requestHeaderValid pending) .type
      pure (.requested bytes (Images.rawRequest.encode pending))

theorem emitted_boundary_has_valid_clock (image : Machine.ImageContext imageBytes programWitness)
    (state : Machine.State image.context.program) (witness : Graph.Admission.Witness) (outcome : Protocol.Outcome)
    (accepted : finish image state witness = .ok outcome) : (clock state).valid state.status = true := by
  cases valid : (clock state).valid state.status with
  | true => rfl
  | false =>
    simp [finish, valid, require, bind, Except.bind] at accepted
    split at accepted <;> cases accepted

theorem request_identity_derived_from_complete_fields (program : Program) (state : Graph.State)
    (snapshot : Bytes) (output : Protocol.Request) (accepted : request program state snapshot = .ok output) :
    Protocol.requestBindingValid output = true := by
  unfold request at accepted
  simp only [bind, Except.bind] at accepted
  repeat' first
    | split at accepted
    | contradiction
  all_goals cases accepted; exact Protocol.bound_request_valid _

end BoundaryV2.Profile.Target.Boundary
