import BoundaryV2.TargetBoundary

namespace BoundaryV2.Profile.Target.Boundary

open Machine (SemanticValue Invalid require fromOption)

structure ResponseWitness where
  value : SemanticValue
  descriptorPayload : SemanticValue
  descriptorResponse : SemanticValue

structure InputWitness where
  arguments : List SemanticValue
  graph : Graph.Admission.Witness
  clock : Clock
  response : Option ResponseWitness

structure Prepared (program : Program) where
  state : Machine.State program
  events : List Machine.Event
  parked : Bool

def argumentsValid (program : Program) (bytes : Bytes) (arguments : List SemanticValue) : Bool :=
  program.functions[program.roots.entry.value]?.any (fun entry => arguments.map Profile.Value.schema == entry.parameters) &&
  arguments.all (Profile.Value.externalValid program.schemas) && arguments.flatMap (Profile.Value.encode program.schemas) == bytes

/-- Decode the public response contract and the original program-relative
value independently against the exact same response byte field. -/
def acceptResponse (image : Machine.ImageContext imageBytes programWitness) (graph : Graph.State)
    (snapshot bytes : Bytes) (state : Machine.State image.context.program) (witness : ResponseWitness) :
    Except Invalid (Machine.Transition image.context.program) := do
  let request ← request image.context.program graph snapshot
  let result ← fromOption (Images.rawResult.decode bytes) .type
  require (Protocol.checkResult request result witness.descriptorPayload witness.descriptorResponse) .type
  let pending ← fromOption graph.roots.pending .inactive
  let .pending effect _ _ _ ← fromOption graph.nodes[pending.value]? .reference | throw .type
  let effect ← fromOption image.context.program.effects[effect.value]? .reference
  require (Profile.Value.checkExternal image.context.program.schemas effect.result result.value witness.value) .type
  let occurrence ← fromOption state.pendingOccurrence .inactive
  Machine.external image.context state (.response occurrence witness.value)

/-- Exactly the public invocation boundary before execution: initial arguments,
restoration, cancellation, parked polling, response acceptance, and saved-yield
continuation. No application block is executed by this preparation function. -/
def prepare (image : Machine.ImageContext imageBytes programWitness) (input : Protocol.Input)
    (witness : InputWitness) : Except Invalid (Prepared image.context.program) := do
  require (input.image == imageBytes && Protocol.inputValid input) .witness
  match input.instanceData with
  | .initialArgs bytes =>
    require (witness.clock == ⟨0, none⟩ && witness.response.isNone) .witness
    require (argumentsValid image.context.program bytes witness.arguments) .type
    let state ← image.initial witness.arguments
    require (Graph.Admission.check image.context.program programWitness.borrows state.raw witness.graph) .scope
    pure ⟨state, [], false⟩
  | .state snapshot =>
    require witness.arguments.isEmpty .witness
    let graph ← fromOption (CertifiedState.decode image snapshot witness.graph) .scope
    let state ← restore image graph witness.graph witness.clock
    match input.control with
    | .cancel reason =>
      require witness.response.isNone .witness
      let transition ← Machine.external image.context state (.cancel reason)
      pure ⟨transition.state, transition.events, transition.state.status == .parked⟩
    | .continueValue (some bytes) =>
      let response ← fromOption witness.response .witness
      let transition ← acceptResponse image graph snapshot bytes state response
      pure ⟨transition.state, transition.events, false⟩
    | .continueValue none =>
      require witness.response.isNone .witness
      match state.status with
      | .parked => pure ⟨state, [], true⟩
      | .yielded =>
        let transition ← Machine.external image.context state .continueYield
        pure ⟨transition.state, transition.events, false⟩
      | .active | .unwinding => pure ⟨state, [], false⟩

structure Observation (program : Program) where
  state : Machine.State program
  events : List Machine.Event
  outcome : Protocol.Outcome

def advanceQuantum (context : Machine.Context) (prepared : Prepared context.program) :
    Except Invalid (Machine.Transition context.program) :=
  if prepared.parked then .ok ⟨prepared.state, []⟩ else Machine.tick context prepared.state

/-- An advance invocation executes exactly one target block or unwind rule,
except a still-parked poll or cancellation that remains parked. -/
def advance (image : Machine.ImageContext imageBytes programWitness) (input : Protocol.Input)
    (incoming : InputWitness) (outgoing : Graph.Admission.Witness) :
    Except Invalid (Observation image.context.program) := do
  require (input.mode == .advance) .witness
  let prepared ← prepare image input incoming
  let transition ← advanceQuantum image.context prepared
  let outcome ← finish image transition.state outgoing
  require (Protocol.outcomeCodec.valid outcome) .type
  pure ⟨transition.state, prepared.events ++ transition.events, outcome⟩

theorem prepare_binds_complete_image (image : Machine.ImageContext imageBytes programWitness)
    (input : Protocol.Input) (witness : InputWitness) (prepared : Prepared image.context.program)
    (accepted : prepare image input witness = .ok prepared) : input.image = imageBytes := by
  by_cases same : input.image = imageBytes
  · exact same
  · simp [prepare, same, require, bind, Except.bind] at accepted

theorem advance_uses_one_target_quantum (image : Machine.ImageContext imageBytes programWitness)
    (input : Protocol.Input) (incoming : InputWitness) (outgoing : Graph.Admission.Witness)
    (observation : Observation image.context.program)
    (accepted : advance image input incoming outgoing = .ok observation) :
    ∃ prepared transition,
      prepare image input incoming = .ok prepared ∧
      (if prepared.parked then .ok ⟨prepared.state, []⟩ else Machine.tick image.context prepared.state) = .ok transition ∧
      observation.state = transition.state ∧ observation.events = prepared.events ++ transition.events ∧
      finish image transition.state outgoing = .ok observation.outcome := by
  unfold advance at accepted
  simp only [bind, Except.bind] at accepted
  split at accepted
  · cases accepted
  · cases preparedAt : prepare image input incoming with
    | error error => simp [preparedAt] at accepted
    | ok prepared =>
      simp only [preparedAt] at accepted
      cases transitionAt : advanceQuantum image.context prepared with
      | error error => simp [transitionAt] at accepted
      | ok transition =>
        simp only [transitionAt] at accepted
        cases outcomeAt : finish image transition.state outgoing with
        | error error => simp [outcomeAt] at accepted
        | ok outcome =>
          simp only [outcomeAt] at accepted
          split at accepted
          · cases accepted
          · cases accepted
            exact ⟨prepared, transition, rfl, transitionAt, rfl, rfl, outcomeAt⟩

end BoundaryV2.Profile.Target.Boundary
