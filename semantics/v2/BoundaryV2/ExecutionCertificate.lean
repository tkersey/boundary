import BoundaryV2.TargetExecution
import BoundaryV2.WireEvaluation

/- Compositional evaluation laws for exact execution certificates. These retain
all checks in the original functions while allowing independently checked
intermediate computations to be reused in a larger proof. -/

namespace BoundaryV2.Profile.Protocol

theorem checkRequest_of_descriptors (request : Request) (payload : Value .target)
    (payloadType resumeType : SchemaDescriptor.Descriptor)
    (descriptors : requestDescriptors request = some (payloadType, resumeType))
    (value : Value.checkExternal payloadType.types payloadType.root request.payload payload = true) :
    checkRequest request payload = true := by
  unfold checkRequest
  rw [descriptors]
  exact value

theorem checkResult_of_parts (request : Request) (result : Result) (payload resumed : Value .target)
    (payloadType resumeType : SchemaDescriptor.Descriptor)
    (checkedRequest : checkRequest request payload = true)
    (bound : resultBindingValid request result = true)
    (descriptors : requestDescriptors request = some (payloadType, resumeType))
    (value : Value.checkExternal resumeType.types resumeType.root result.value resumed = true) :
    checkResult request result payload resumed = true := by
  simp only [checkResult, checkedRequest, bound, descriptors, Bool.true_and, value]

end BoundaryV2.Profile.Protocol

namespace BoundaryV2.Profile.Target.Boundary

theorem acceptResponse_of_parts
    (image : Machine.ImageContext imageBytes programWitness) (graph : Graph.State)
    (snapshot bytes : Bytes) (state : Machine.State image.context.program)
    (witness : ResponseWitness) (requestValue : Protocol.Request) (resultValue : Protocol.Result)
    (pending resume : NodeId) (effect : EffectId .target) (payload : Graph.Value) (source : BlockId)
    (contract : Effect .target) (occurrence : RequestOccurrence)
    (transition : Machine.Transition image.context.program)
    (foundRequest : request image.context.program graph snapshot = .ok requestValue)
    (foundResult : Images.rawResult.decode bytes = some resultValue)
    (checkedResult : Protocol.checkResult requestValue resultValue witness.descriptorPayload witness.descriptorResponse = true)
    (foundPending : graph.roots.pending = some pending)
    (foundNode : graph.nodes[pending.value]? = some (.pending effect payload resume source))
    (foundEffect : image.context.program.effects[effect.value]? = some contract)
    (checkedValue : Profile.Value.checkExternal image.context.program.schemas contract.result resultValue.value witness.value = true)
    (foundOccurrence : state.pendingOccurrence = some occurrence)
    (resumed : Machine.external image.context state (.response occurrence witness.value) = .ok transition) :
    acceptResponse image graph snapshot bytes state witness = .ok transition := by
  simp [acceptResponse, foundRequest, foundResult, checkedResult, foundPending, foundNode, foundEffect,
    checkedValue, foundOccurrence, resumed, Machine.fromOption, Machine.require, bind, Except.bind]

end BoundaryV2.Profile.Target.Boundary

namespace BoundaryV2.Profile.Target.Boundary

theorem prepare_state_response_of_parts
    (image : Machine.ImageContext imageBytes programWitness) (input : Protocol.Input) (witness : InputWitness)
    (snapshot bytes : Bytes) (graph : Graph.State) (state : Machine.State image.context.program)
    (response : ResponseWitness) (transition : Machine.Transition image.context.program)
    (header : (input.image == imageBytes && Protocol.inputValid input) = true)
    (instanceAt : input.instanceData = .state snapshot)
    (controlAt : input.control = .continueValue (some bytes))
    (emptyArguments : witness.arguments.isEmpty = true)
    (decoded : CertifiedState.decode image snapshot witness.graph = some graph)
    (restored : restore image graph witness.graph witness.clock = .ok state)
    (responseAt : witness.response = some response)
    (accepted : acceptResponse image graph snapshot bytes state response = .ok transition) :
    prepare image input witness = .ok ⟨transition.state, transition.events, false⟩ := by
  simp [prepare, header, instanceAt, controlAt, emptyArguments, decoded, restored, responseAt,
    accepted, Machine.fromOption, Machine.require, bind, Except.bind]
  rfl

end BoundaryV2.Profile.Target.Boundary
namespace BoundaryV2.Profile.Target.Boundary

theorem run_of_parts (image : Machine.ImageContext imageBytes programWitness) (input : Protocol.Input)
    (incoming : InputWitness) (outgoing : Graph.Admission.Witness) (count : Nat)
    (prepared : Prepared image.context.program) (transition : Machine.Transition image.context.program)
    (outcome : Protocol.Outcome)
    (mode : input.mode = .run)
    (preparedAt : prepare image input incoming = .ok prepared)
    (ran : completeInternal image.context count prepared.state = .ok transition)
    (finished : finish image transition.state outgoing = .ok outcome)
    (valid : Protocol.outcomeCodec.valid outcome = true) :
    run image input incoming outgoing count = .ok ⟨transition.state, prepared.events ++ transition.events, outcome⟩ := by
  simp [run, mode, preparedAt, ran, finished, valid, Machine.require, bind, Except.bind]
  rfl

theorem checkInvocation_of_parts (image : Machine.ImageContext imageBytes programWitness)
    (record : PublicInvocation) (before : Clock) (witness : InvocationWitness)
    (input : Protocol.Input) (observation : Observation image.context.program)
    (sameClock : witness.incoming.clock = before)
    (decoded : Protocol.inputCodec.decode record.input = some input)
    (observed : observe image input witness = .ok observation)
    (encoded : Protocol.outcomeCodec.encode observation.outcome = record.output) :
    checkInvocation image record before witness =
      some ⟨input.instanceData, nextInstance observation.outcome, clock observation.state,
        observation.events, terminalOutcome observation.outcome⟩ := by
  simp [checkInvocation, sameClock, decoded, observed, encoded, Except.toOption, Option.bind]

end BoundaryV2.Profile.Target.Boundary
