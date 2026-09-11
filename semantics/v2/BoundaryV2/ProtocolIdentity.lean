import BoundaryV2.SHA256
import BoundaryV2.Images

namespace BoundaryV2.Profile.Protocol

/-- Every field, including a digest, is preceded by its minimal u64 varint
byte length. Domain prefixes themselves have no length prefix. -/
def hashField (bytes : Bytes) : Bytes := Wire.natural bytes.length ++ bytes

def hashFields (domain : Bytes) (fields : List Bytes) : Digest :=
  SHA256.hash (domain ++ fields.flatMap hashField)

def requestFields (request : Request) : List Bytes := [
  request.programIdentity.toList, request.pendingStateDigest.toList,
  request.residualContractDigest.toList, request.continuationBindingDigest.toList,
  request.semanticIdentity, request.payloadSchema, request.resumeSchema, request.payload]

def requestIdentity (request : Request) : Digest :=
  hashFields "boundary.effect-request/v2".toUTF8.data.toList (requestFields request)

def contractIdentity (name payloadSchema resumeSchema : Bytes) : Digest :=
  hashFields "boundary.residual-contract/v2".toUTF8.data.toList [name, payloadSchema, resumeSchema]

def continuationIdentity (program state : Digest) (sourceBlock : BlockId) (resumeSchema : Digest) : Digest :=
  hashFields "boundary.continuation-binding/v2".toUTF8.data.toList
    [program.toList, state.toList, Wire.natural sourceBlock.value, resumeSchema.toList]

def programPreimage (program : Target.Program) : Bytes :=
  "boundary.program-image/v2".toUTF8.data.toList ++
    (Wire.natural program.roots.profile ::
      ((Images.sections program).zipIdx 1).flatMap (fun (bytes, index) => [Wire.natural index, bytes])).flatMap hashField

def programIdentity (program : Target.Program) : Digest := SHA256.hash (programPreimage program)

/-- Program-relative request generation supplies these two independently
computed digests. The wire record does not assert its own source of truth. -/
def bindRequest (request : Request) : Request :=
  let contracted := { request with
    residualContractDigest := contractIdentity request.semanticIdentity request.payloadSchema request.resumeSchema }
  { contracted with requestIdentity := requestIdentity contracted }

def requestBindingValid (request : Request) : Bool :=
  request.residualContractDigest ==
      contractIdentity request.semanticIdentity request.payloadSchema request.resumeSchema &&
    request.requestIdentity == requestIdentity request

def resultBindingValid (request : Request) (result : Result) : Bool :=
  result.requestIdentity == request.requestIdentity &&
    result.resumeSchemaDigest == SHA256.hash request.resumeSchema

theorem request_identity_ignores_only_its_own_field (request : Request) (digest : Digest) :
    requestIdentity { request with requestIdentity := digest } = requestIdentity request := rfl

theorem bound_request_valid (request : Request) : requestBindingValid (bindRequest request) = true := by
  simp [requestBindingValid, bindRequest, requestIdentity, requestFields]

theorem bound_request_idempotent (request : Request) :
    bindRequest (bindRequest request) = bindRequest request := by
  simp only [bindRequest, requestIdentity, requestFields]

theorem request_binding_exact (request : Request) :
    requestBindingValid request = true ↔
      request.residualContractDigest =
        contractIdentity request.semanticIdentity request.payloadSchema request.resumeSchema ∧
      request.requestIdentity = requestIdentity request := by
  simp [requestBindingValid]

theorem result_binding_exact (request : Request) (result : Result) :
    resultBindingValid request result = true ↔
      result.requestIdentity = request.requestIdentity ∧
      result.resumeSchemaDigest = SHA256.hash request.resumeSchema := by
  simp [resultBindingValid]

/-- These are exact SHA-256 equalities, not collision-freedom assumptions.
Snapshot and program correspondence must additionally bind their full bytes. -/
theorem result_rejects_different_request (request : Request) (result : Result)
    (different : result.requestIdentity ≠ request.requestIdentity) :
    resultBindingValid request result = false := by simp [resultBindingValid, different]

theorem result_rejects_different_schema (request : Request) (result : Result)
    (different : result.resumeSchemaDigest ≠ SHA256.hash request.resumeSchema) :
    resultBindingValid request result = false := by simp [resultBindingValid, different]

end BoundaryV2.Profile.Protocol
