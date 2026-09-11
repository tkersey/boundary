import Std

/- Complete logical source and BPI2 record shapes. References remain untrusted
until admission establishes their bounds and contracts. Phantom indices prevent
catalogs and runtime identities from being interchanged by numeric coincidence. -/
namespace BoundaryV2.Profile
abbrev Bytes := List UInt8
def wordLimit : Nat := 2 ^ 64

inductive Space where
  | source | target | runtime
  deriving DecidableEq, Repr
inductive Domain where
  | schema | constant | effect | function | block | handler | capture | resource
  | regionBinder | constructor | variable | value | term | node | blob
  | attachment | regionInstance | cell | custody | templateBinder
  | invocation | lexicalScope | obligation | requestOccurrence | transfer
  deriving DecidableEq, Repr
structure Ref (space : Space) (domain : Domain) where
  value : Nat
  deriving DecidableEq, Repr
instance : OfNat (Ref space domain) n := ⟨⟨n⟩⟩
def Ref.inBounds (reference : Ref space domain) (length : Nat) : Prop := reference.value < length
abbrev SchemaId (space) := Ref space .schema
abbrev ConstantId (space) := Ref space .constant
abbrev EffectId (space) := Ref space .effect
abbrev FunctionId (space) := Ref space .function
abbrev BlockId := Ref .target .block
abbrev HandlerId (space) := Ref space .handler
abbrev CaptureId := Ref .target .capture
abbrev ResourceId (space) := Ref space .resource
abbrev RegionId (space) := Ref space .regionBinder
abbrev ConstructorId := Ref .target .constructor
abbrev VariableId := Ref .source .variable
abbrev SourceValueId := Ref .source .value
abbrev TermId := Ref .source .term
abbrev NodeId := Ref .runtime .node
abbrev BlobId := Ref .runtime .blob
abbrev AttachmentId := Ref .runtime .attachment
abbrev RegionInstanceId := Ref .runtime .regionInstance
abbrev CellId := Ref .runtime .cell
abbrev CustodyToken := Ref .runtime .custody
abbrev TemplateBinderId := Ref .runtime .templateBinder
abbrev InvocationId := Ref .runtime .invocation
abbrev LexicalScopeId := Ref .runtime .lexicalScope
abbrev ObligationId := Ref .runtime .obligation
abbrev RequestOccurrence := Ref .runtime .requestOccurrence
abbrev TransferId := Ref .runtime .transfer

inductive Use where
  | reusable | affine | linear | multi
  deriving DecidableEq, Repr
inductive Mode where
  | deep | shallow
  deriving DecidableEq, Repr
structure ComputationType (space : Space) where
  parameters : List (SchemaId space)
  result : SchemaId space
  effects : List (EffectId space) := []
  captureBound : List (SchemaId space) := []
  use : Use := .reusable
  regions : List (RegionId space) := []
  deriving DecidableEq, Repr
structure ResumptionType (space : Space) where
  effect : EffectId space
  input : SchemaId space
  answer : SchemaId space
  effects : List (EffectId space) := []
  captureBound : List (SchemaId space) := []
  handled : List (EffectId space)
  escaping : List (EffectId space) := []
  mode : Mode
  use : Use
  ownedRegions : List (RegionId space) := []
  obligations : Bool := false
  deriving DecidableEq, Repr
inductive Internal (space : Space) where
  | computation : ComputationType space → Internal space
  | capability : EffectId space → Internal space
  | cell : SchemaId space → RegionId space → Internal space
  | region : RegionId space → Internal space
  | resumption : ResumptionType space → Internal space
  | suspensionPackage : SchemaId space → Internal space
  | abstractResource : ResourceId space → Internal space
  | borrowed : SchemaId space → RegionId space → Internal space
  deriving DecidableEq, Repr
inductive Schema (space : Space) where
  | unit | boolean | i8 | i16 | i32 | i64 | u8 | u16 | u32 | u64 | bytes | text
  | product : List (SchemaId space) → Schema space
  | sum : List (SchemaId space) → Schema space
  | seq : SchemaId space → Schema space
  | vector : SchemaId space → Nat → Schema space
  | internal : Internal space → Schema space
  | array : SchemaId space → Nat → Schema space
  | boundedBytes : Nat → Schema space
  | boundedText : Nat → Schema space
  | enumeration : List Nat → Schema space
  deriving DecidableEq, Repr
structure Literal (space : Space) where
  schema : SchemaId space
  bytes : Bytes
  deriving DecidableEq, Repr
structure Effect (space : Space) where
  identity : Bytes
  payload : SchemaId space
  result : SchemaId space
  useSiteEffects : List (EffectId space) := []
  bodies : List (SchemaId space) := []
  controlUse : Use := .linear
  external : Bool := true
  deriving DecidableEq, Repr
inductive Opcode where
  | constant | move | integerAdd | integerSub | integerMul | integerDiv | equal | less
  | booleanNot | product | field | variant | variantTag | variantPayload
  | sequence | sequenceLength | sequenceGet | sequenceAppend | sequenceConcat | sequencePop
  | computation | cellNew | cellGet | cellSet | cloneResumption | package | unpack
  | resourcePack | resourceUnpack | integerRem | integerBitNot | integerBitAnd | integerBitOr
  | integerBitXor | integerConvert | enumTag | blobLength | blobConcat | blobSlice
  | blobCompare | blobByte | textScalar | textInteger | sequenceSet | sequenceTake
  | blobFromByte | sequencePopLast | select
  deriving DecidableEq, Repr
inductive Fault where
  | arithmeticOverflow | divisionByZero | capacityExceeded | invalidUtf8 | invalidIndex | invalidVariant
  deriving DecidableEq, Repr
structure InstructionFailure (space : Space) where
  kind : Fault
  value : ConstantId space
  deriving DecidableEq, Repr
structure Clause (space : Space) where
  effect : EffectId space
  function : FunctionId space
  resumption : SchemaId space
  direct : Bool := false
  deriving DecidableEq, Repr
structure Handler (space : Space) where
  mode : Mode
  input : SchemaId space
  answer : SchemaId space
  returnFunction : FunctionId space
  clauses : List (Clause space)
  forwardFunction : Option (FunctionId space) := none
  state : List (SchemaId space) := []
  effects : List (EffectId space) := []
  deriving DecidableEq, Repr
structure Resource (space : Space) where
  representation : SchemaId space
  introducers : List (FunctionId space)
  eliminators : List (FunctionId space)
  deriving DecidableEq, Repr

namespace Source
inductive Expression where
  | variable : VariableId → Expression
  | literal : ConstantId .source → Expression
  | primitive : Opcode → List SourceValueId → Nat → List (InstructionFailure .source) → Expression
  | lambda : FunctionId .source → Expression
  deriving DecidableEq, Repr
structure Value where
  schema : SchemaId .source
  expression : Expression
  deriving DecidableEq, Repr
structure Operation where
  effect : EffectId .source
  capability : Option SourceValueId := none
  payload : SourceValueId
  bodies : List SourceValueId := []
  useSiteCapabilities : List SourceValueId := []
  deriving DecidableEq, Repr
inductive Term where
  | value : SourceValueId → Term
  | bind : VariableId → TermId → TermId → Term
  | conditional : SourceValueId → TermId → TermId → Term
  | call : FunctionId .source → List SourceValueId → Term
  | apply : SourceValueId → List SourceValueId → Term
  | perform : Operation → Term
  | handle : HandlerId .source → SourceValueId → List SourceValueId → List SourceValueId → Term
  | resumeValue : SourceValueId → SourceValueId → Term
  | resumeWith : SourceValueId → SourceValueId → HandlerId .source → List SourceValueId → Term
  | resumeComputation : SourceValueId → SourceValueId → Term
  | protect : SourceValueId → SourceValueId → List SourceValueId → Option SourceValueId → Option (RegionId .source) → Term
  | withRegion : RegionId .source → SourceValueId → List SourceValueId → Term
  | dispose : SourceValueId → Term
  | fail : SourceValueId → Term
  | yieldThen : TermId → Term
  | matchSum : SourceValueId → List (VariableId × TermId) → Term
  | unpackProduct : SourceValueId → List VariableId → TermId → Term
  deriving DecidableEq, Repr
structure Function where
  parameters : List VariableId
  result : SchemaId .source
  effects : List (EffectId .source) := []
  regions : List (RegionId .source) := []
  body : Option TermId := none
  deriving DecidableEq, Repr
structure Module where
  entry : FunctionId .source
  failure : SchemaId .source
  schemas : List (Schema .source)
  constants : List (Literal .source)
  effects : List (Effect .source)
  handlers : List (Handler .source)
  regionCount : Nat
  resources : List (Resource .source) := []
  variables : List (SchemaId .source)
  values : List Value
  terms : List Term
  functions : List Function
  deriving DecidableEq, Repr
end Source

namespace Target
/-- Slot numbers are block-local, not catalog references. -/
structure Slot where
  value : Nat
  deriving DecidableEq, Repr
instance : OfNat Slot n := ⟨⟨n⟩⟩
inductive Argument where
  | slot : Slot → Argument
  | returned : Argument
  deriving DecidableEq, Repr
structure Edge where
  block : BlockId
  arguments : List Argument
  deriving DecidableEq, Repr
structure Instruction where
  opcode : Opcode
  resultType : SchemaId .target
  operands : List Slot := []
  immediate : Nat := 0
  failures : List (InstructionFailure .target) := []
  deriving DecidableEq, Repr
structure Perform where
  effect : EffectId .target
  capability : Option Slot := none
  payload : Slot
  bodies : List Slot := []
  useSiteCapabilities : List Slot := []
  next : Edge
  deriving DecidableEq, Repr
inductive Terminator where
  | returnValue : Slot → Terminator
  | jump : Edge → Terminator
  | branch : Slot → Edge → Edge → Terminator
  | switchVariant : Slot → List Edge → Terminator
  | unpackProduct : Slot → BlockId → List Slot → Terminator
  | call : FunctionId .target → List Slot → Edge → Terminator
  | perform : Perform → Terminator
  | yieldValue : Edge → Terminator
  | fail : Slot → Terminator
  | apply : Slot → List Slot → Edge → Terminator
  | handle : HandlerId .target → Slot → List Slot → List Slot → Edge → Terminator
  | resumeValue : Slot → Slot → Edge → Terminator
  | resumeWith : Slot → Slot → HandlerId .target → List Slot → Edge → Terminator
  | resumeComputation : Slot → Slot → Edge → Terminator
  | forward : Perform → Terminator
  | dispose : Slot → Edge → Terminator
  | protect : Slot → Slot → List Slot → Option Slot → Option (RegionId .target) → Edge → Terminator
  | withRegion : RegionId .target → Slot → List Slot → Edge → Terminator
  deriving DecidableEq, Repr
structure Block where
  function : FunctionId .target
  parameters : List (SchemaId .target)
  instructions : List Instruction
  terminator : Terminator
  deriving DecidableEq, Repr
structure Function where
  entry : BlockId
  parameters : List (SchemaId .target)
  result : SchemaId .target
  effects : List (EffectId .target) := []
  regions : List (RegionId .target) := []
  deriving DecidableEq, Repr
structure Capture where
  fields : List (SchemaId .target)
  ownedRegions : List (RegionId .target) := []
  borrowedRegions : List (RegionId .target) := []
  use : Use := .linear
  deriving DecidableEq, Repr
structure Constructor where
  function : FunctionId .target
  capture : CaptureId
  schema : SchemaId .target
  deriving DecidableEq, Repr
structure ScopeCatalog where
  captures : List Capture := []
  regionCount : Nat := 0
  resources : List (Resource .target) := []
  deriving DecidableEq, Repr
structure Roots where
  profile : Nat := 1
  entry : FunctionId .target
  result : SchemaId .target
  failure : SchemaId .target
  deriving DecidableEq, Repr
structure Program where
  roots : Roots
  schemas : List (Schema .target)
  constants : List (Literal .target)
  effects : List (Effect .target)
  functions : List Function
  blocks : List Block
  handlers : List (Handler .target) := []
  scopes : ScopeCatalog := {}
  constructors : List Constructor := []
  deriving DecidableEq, Repr
end Target

abbrev Digest := Vector UInt8 32

namespace Protocol
inductive Reason where
  | text : Bytes → Reason
  | bytes : Bytes → Reason
  deriving DecidableEq, Repr
inductive Mode where
  | advance | run
  deriving DecidableEq, Repr
inductive Instance where
  | initialArgs : Bytes → Instance
  | state : Bytes → Instance
  deriving DecidableEq, Repr
inductive Control where
  | continueValue : Option Bytes → Control
  | cancel : Reason → Control
  deriving DecidableEq, Repr
structure Input where
  mode : Mode
  image : Bytes
  instanceData : Instance
  control : Control
  deriving DecidableEq, Repr
inductive Provenance where
  | notObserved | exact | lowerBound
  deriving DecidableEq, Repr
structure Bound where
  amount : Nat := 0
  provenance : Provenance := .notObserved
  deriving DecidableEq, Repr
inductive Arena where
  | input | working | output | memory
  deriving DecidableEq, Repr
structure Capacity where
  arena : Arena
  input : Bound := {}
  working : Bound := {}
  output : Bound := {}
  memoryPages : Bound := {}
  deriving DecidableEq, Repr
inductive Outcome where
  | progressed : Bytes → Outcome
  | requested : Bytes → Bytes → Outcome
  | yielded : Bytes → Outcome
  | completed : Bytes → Outcome
  | failed : Bytes → Bytes → Option Reason → Outcome
  | cancelled : Reason → Bytes → Outcome
  | needsCapacity : Capacity → Outcome
  deriving DecidableEq, Repr
structure Request where
  programIdentity : Digest
  pendingStateDigest : Digest
  residualContractDigest : Digest
  continuationBindingDigest : Digest
  semanticIdentity : Bytes
  payloadSchema : Bytes
  resumeSchema : Bytes
  payload : Bytes
  requestIdentity : Digest
  deriving DecidableEq, Repr
structure Result where
  requestIdentity : Digest
  resumeSchemaDigest : Digest
  value : Bytes
  deriving DecidableEq, Repr
end Protocol

namespace Graph
structure OwnedRef where
  node : NodeId
  deriving DecidableEq, Repr
inductive ValueBody where
  | scalar : Vector UInt8 8 → ValueBody
  | blob : BlobId → ValueBody
  | reference : NodeId → ValueBody
  | owned : OwnedRef → ValueBody
  deriving DecidableEq, Repr
structure Value where
  schema : SchemaId .target
  body : ValueBody
  deriving DecidableEq, Repr
structure Blob where
  schema : SchemaId .target
  bytes : Bytes
  deriving DecidableEq, Repr
structure Control where
  block : BlockId
  arguments : List Value
  parent : Option NodeId := none
  evidence : Option NodeId := none
  region : Option NodeId := none
  deriving DecidableEq, Repr
structure Continuation where
  sourceBlock : BlockId
  arguments : List (Option Value)
  parent : Option NodeId := none
  evidence : Option NodeId := none
  region : Option NodeId := none
  deriving DecidableEq, Repr
inductive ExitReason where
  | normal : Value → ExitReason
  | failure : Value → ExitReason
  | cancellation | abandoned
  deriving DecidableEq, Repr
structure Exit where
  reason : ExitReason
  cleanupFailures : List Value := []
  cancellation : Option Protocol.Reason := none
  stop : Option NodeId := none
  outer : Option NodeId := none
  discarded : List Value := []
  deriving DecidableEq, Repr
structure Capture where
  schema : SchemaId .target
  capture : Option NodeId
  delimiter : NodeId
  evidence : Option NodeId
  useSiteCapabilities : List Value := []
  deriving DecidableEq, Repr
inductive AttachmentPhase where
  | active | suspended
  deriving DecidableEq, Repr
inductive ObligationStatus where
  | pending
  | running : NodeId → ObligationStatus
  | completed
  | failed : Value → ObligationStatus
  deriving DecidableEq, Repr
inductive Node where
  | control : Control → Node
  | continuation : Continuation → Node
  | handler : HandlerId .target → List Value → Option NodeId → Option NodeId → Node
  | attachment : NodeId → Option NodeId → Option NodeId → AttachmentPhase → Option NodeId → Node
  | environment : List Value → Option NodeId → Node
  | aggregate : SchemaId .target → Nat → List Value → Node
  | region : RegionId .target → Option NodeId → List OwnedRef → Node
  | regionScope : BlockId → NodeId → Option NodeId → Node
  | injection : NodeId → Node
  | protection : BlockId → OwnedRef → Option NodeId → Option NodeId → Option NodeId → Option NodeId → Node
  | cleanupReturn : OwnedRef → Option NodeId → NodeId → Node
  | disposalReturn : SchemaId .target → Option NodeId → List Value → Node
  | unwind : Option NodeId → List Value → Node
  | cell : SchemaId .target → NodeId → Option Value → Node
  | oneShot : Capture → Node
  | multiTemplate : Capture → Node
  | branch : NodeId → NodeId → List (NodeId × NodeId) → Node
  | package : SchemaId .target → Value → Node
  | computation : ConstructorId → NodeId → Node
  | resource : SchemaId .target → Value → Node
  | borrow : SchemaId .target → NodeId → NodeId → Node
  | obligation : BlockId → Option Value → Option Value → ObligationStatus → Node
  | pending : EffectId .target → Value → NodeId → BlockId → Node
  | exit : Exit → Node
  deriving DecidableEq, Repr
structure Roots where
  current : Option NodeId := none
  evidence : Option NodeId := none
  detached : List OwnedRef := []
  exit : Option NodeId := none
  pending : Option NodeId := none
  deriving DecidableEq, Repr
inductive Status where
  | active | yielded | parked | unwinding
  deriving DecidableEq, Repr
structure State where
  programIdentity : Digest
  status : Status
  roots : Roots
  nodes : List Node
  blobs : List Blob := []
  deriving DecidableEq, Repr
end Graph

end BoundaryV2.Profile
