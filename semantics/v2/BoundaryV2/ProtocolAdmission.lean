import BoundaryV2.ProtocolCodec
import BoundaryV2.SchemaClasses
import BoundaryV2.ValueCodec

namespace BoundaryV2.Profile.Protocol

def requestHeaderValid (request : Request) : Bool :=
  !request.semanticIdentity.isEmpty && UTF8.valid request.semanticIdentity && requestBindingValid request

def requestDescriptors (request : Request) : Option (SchemaDescriptor.Descriptor × SchemaDescriptor.Descriptor) := do
  if !requestHeaderValid request then none else do
    let payload ← SchemaDescriptor.decode request.payloadSchema
    let resume ← SchemaDescriptor.decode request.resumeSchema
    return (payload, resume)

/-- A finite value tree is untrusted certificate data. Its entire structure,
schema, external trait, and exact encoded payload are independently checked.
No parser depth or execution fuel occurs in the admission predicate. -/
def checkRequest (request : Request) (payload : Value .target) : Bool :=
  match requestDescriptors request with
  | none => false
  | some (descriptor, _) => Value.checkExternal descriptor.types descriptor.root request.payload payload

def checkResult (request : Request) (result : Result) (payload resumed : Value .target) : Bool :=
  checkRequest request payload && resultBindingValid request result &&
    match requestDescriptors request with
    | none => false
    | some (_, descriptor) => Value.checkExternal descriptor.types descriptor.root result.value resumed

structure RequestMeaning (request : Request) (payload : Value .target) : Prop where
  named : request.semanticIdentity.isEmpty = false
  utf8 : UTF8.valid request.semanticIdentity = true
  contract : request.residualContractDigest =
    contractIdentity request.semanticIdentity request.payloadSchema request.resumeSchema
  identity : request.requestIdentity = requestIdentity request
  descriptors : ∃ payloadType resumeType,
    SchemaDescriptor.decode request.payloadSchema = some payloadType ∧
    SchemaDescriptor.decode request.resumeSchema = some resumeType ∧
    payload.schema = payloadType.root ∧ Value.externalValid payloadType.types payload = true ∧
    Value.encode payloadType.types payload = request.payload

structure ResultMeaning (request : Request) (result : Result) (payload resumed : Value .target) : Prop where
  requestValid : RequestMeaning request payload
  identity : result.requestIdentity = request.requestIdentity
  schemaDigest : result.resumeSchemaDigest = SHA256.hash request.resumeSchema
  value : ∃ descriptor,
    SchemaDescriptor.decode request.resumeSchema = some descriptor ∧
    resumed.schema = descriptor.root ∧ Value.externalValid descriptor.types resumed = true ∧
    Value.encode descriptor.types resumed = result.value

theorem request_descriptors_exact (request : Request) (payload resume : SchemaDescriptor.Descriptor)
    (accepted : requestDescriptors request = some (payload, resume)) :
    requestHeaderValid request = true ∧ SchemaDescriptor.decode request.payloadSchema = some payload ∧
      SchemaDescriptor.decode request.resumeSchema = some resume := by
  unfold requestDescriptors at accepted
  split at accepted
  · cases accepted
  · rename_i valid
    have header : requestHeaderValid request = true := by simpa using valid
    simp only [Bind.bind, Option.bind_eq_some_iff, pure, Pure.pure, Option.some.injEq, Prod.mk.injEq] at accepted
    obtain ⟨payloadType, foundPayload, resumeType, foundResume, rfl, rfl⟩ := accepted
    exact ⟨header, foundPayload, foundResume⟩

theorem checkRequest_sound (request : Request) (payload : Value .target)
    (accepted : checkRequest request payload = true) : RequestMeaning request payload := by
  unfold checkRequest at accepted
  cases descriptors : requestDescriptors request with
  | none => simp [descriptors] at accepted
  | some pair =>
    rcases pair with ⟨payloadType, resumeType⟩
    have parsed := request_descriptors_exact request payloadType resumeType descriptors
    have header : request.semanticIdentity.isEmpty = false ∧ UTF8.valid request.semanticIdentity = true ∧
        requestBindingValid request = true := by
      simpa [requestHeaderValid, Bool.and_eq_true, and_assoc] using parsed.1
    have binding := (request_binding_exact request).mp header.2.2
    have value := Value.checkExternal_sound _ _ _ _ (by simpa [descriptors] using accepted)
    exact ⟨header.1, header.2.1, binding.1, binding.2,
      ⟨payloadType, resumeType, parsed.2.1, parsed.2.2, value⟩⟩

theorem checkResult_sound (request : Request) (result : Result) (payload resumed : Value .target)
    (accepted : checkResult request result payload resumed = true) :
    ResultMeaning request result payload resumed := by
  unfold checkResult at accepted
  simp only [Bool.and_eq_true] at accepted
  have binding := (result_binding_exact request result).mp accepted.1.2
  cases descriptors : requestDescriptors request with
  | none => simp [descriptors] at accepted
  | some pair =>
    rcases pair with ⟨payloadType, resumeType⟩
    have parsed := request_descriptors_exact request payloadType resumeType descriptors
    have value := Value.checkExternal_sound _ _ _ _ (by simpa [descriptors] using accepted.2)
    exact ⟨checkRequest_sound request payload accepted.1.1, binding.1, binding.2,
      ⟨resumeType, parsed.2.2, value⟩⟩

theorem checkRequest_complete (request : Request) (payload : Value .target)
    (meaning : RequestMeaning request payload) : checkRequest request payload = true := by
  obtain ⟨payloadType, resumeType, parsedPayload, parsedResume, schema, valid, encoded⟩ := meaning.descriptors
  have header : requestHeaderValid request = true := by
    simp [requestHeaderValid, meaning.named, meaning.utf8, request_binding_exact,
      meaning.contract, meaning.identity]
  simp [checkRequest, requestDescriptors, header, parsedPayload, parsedResume,
    Value.checkExternal, schema, valid, encoded]

theorem checkResult_complete (request : Request) (result : Result) (payload resumed : Value .target)
    (meaning : ResultMeaning request result payload resumed) :
    checkResult request result payload resumed = true := by
  have requestValid := checkRequest_complete request payload meaning.requestValid
  have bound : resultBindingValid request result = true :=
    (result_binding_exact request result).mpr ⟨meaning.identity, meaning.schemaDigest⟩
  obtain ⟨descriptor, decoded, schema, valid, encoded⟩ := meaning.value
  cases descriptors : requestDescriptors request with
  | none => simp [checkRequest, descriptors] at requestValid
  | some pair =>
    rcases pair with ⟨payloadType, resumeType⟩
    have parsed := request_descriptors_exact request payloadType resumeType descriptors
    have same : resumeType = descriptor := Option.some.inj (parsed.2.2.symm.trans decoded)
    subst resumeType
    simp [checkResult, requestValid, bound, descriptors, Value.checkExternal, schema, valid, encoded]

theorem checkRequest_exact (request : Request) (payload : Value .target) :
    checkRequest request payload = true ↔ RequestMeaning request payload :=
  ⟨checkRequest_sound request payload, checkRequest_complete request payload⟩

theorem checkResult_exact (request : Request) (result : Result) (payload resumed : Value .target) :
    checkResult request result payload resumed = true ↔ ResultMeaning request result payload resumed :=
  ⟨checkResult_sound request result payload resumed, checkResult_complete request result payload resumed⟩

def decodeRequest (input : Bytes) (payload : Value .target) : Option Request := do
  let request ← Images.rawRequest.decode input
  if checkRequest request payload then some request else none

def decodeResult (request : Request) (input : Bytes) (payload resumed : Value .target) : Option Result := do
  let result ← Images.rawResult.decode input
  if checkResult request result payload resumed then some result else none

theorem decodeRequest_exact (input : Bytes) (payload : Value .target) (request : Request)
    (accepted : decodeRequest input payload = some request) :
    Images.rawRequest.valid request = true ∧ Images.rawRequest.encode request = input ∧
      RequestMeaning request payload := by
  unfold decodeRequest at accepted
  cases raw : Images.rawRequest.decode input with
  | none => simp [raw] at accepted
  | some candidate =>
    simp [raw] at accepted
    obtain ⟨valid, rfl⟩ := accepted
    have exactBytes := Images.rawRequest.decode_exact input candidate raw
    exact ⟨exactBytes.1, exactBytes.2, checkRequest_sound candidate payload valid⟩

theorem decodeResult_exact (request : Request) (input : Bytes) (payload resumed : Value .target) (result : Result)
    (accepted : decodeResult request input payload resumed = some result) :
    Images.rawResult.valid result = true ∧ Images.rawResult.encode result = input ∧
      ResultMeaning request result payload resumed := by
  unfold decodeResult at accepted
  cases raw : Images.rawResult.decode input with
  | none => simp [raw] at accepted
  | some candidate =>
    simp [raw] at accepted
    obtain ⟨valid, rfl⟩ := accepted
    have exactBytes := Images.rawResult.decode_exact input candidate raw
    exact ⟨exactBytes.1, exactBytes.2, checkResult_sound request candidate payload resumed valid⟩

theorem decodeRequest_complete (request : Request) (payload : Value .target)
    (wire : Images.rawRequest.valid request = true) (meaning : RequestMeaning request payload) :
    decodeRequest (Images.rawRequest.encode request) payload = some request := by
  simp [decodeRequest, Images.rawRequest.decode_encode request wire, checkRequest_complete request payload meaning]

theorem decodeResult_complete (request : Request) (result : Result) (payload resumed : Value .target)
    (wire : Images.rawResult.valid result = true) (meaning : ResultMeaning request result payload resumed) :
    decodeResult request (Images.rawResult.encode result) payload resumed = some result := by
  simp [decodeResult, Images.rawResult.decode_encode result wire,
    checkResult_complete request result payload resumed meaning]

end BoundaryV2.Profile.Protocol
