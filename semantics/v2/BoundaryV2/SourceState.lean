import BoundaryV2.SourceAnalysis
import BoundaryV2.Primitives
import BoundaryV2.Cleanup

namespace BoundaryV2.Profile.Source.Machine

abbrev SemanticValue := Profile.Value .source

structure Located where
  value : SemanticValue
  owner : Custody.Owner

structure Binding where
  var : VariableId
  located : Located

abbrev Environment := List Binding

def lookupVariable (environment : Environment) (var : VariableId) : Option Located :=
  ((environment.find? (fun binding => binding.var == var)).map Binding.located)

structure Activation where
  identity : AttachmentId
  definition : HandlerId .source
  environment : Environment
  state : List Located
  invocation : InvocationId
  scope : LexicalScopeId
  outer : Option AttachmentId

inductive Intent where
  | term : Source.Term → Intent
  | primitive : SchemaId .source → Opcode → Nat → List (InstructionFailure .source) → Intent

inductive AfterRelease where
  | deliver : Located → AfterRelease
  | unwind : Cleanup.Exit .source → AfterRelease

inductive Frame where
  | binding : VariableId → TermId → Environment → LexicalScopeId → Frame
  | operands : Intent → Environment → List SourceValueId → List Located → Frame
  | invocation : InvocationId → LexicalScopeId → Frame
  | restore : InvocationId → LexicalScopeId → Frame
  | lexical : LexicalScopeId → Frame
  | handler : Activation → Frame
  | region : RegionInstanceId → Frame
  | protection : ObligationId → Frame
  | cleanupReturn : ObligationId → InvocationId → Cleanup.Exit .source → Option Located → Frame
  | disposalReturn : List Located → AfterRelease → InvocationId → LexicalScopeId → Frame
  | injection : List Located → Frame
  | releaseReturn : LexicalScopeId → AfterRelease → Frame

structure FrozenCell where
  node : NodeId
  identity : CellId
  region : RegionInstanceId
  content : Located

structure Capture where
  schema : SchemaId .source
  frames : List Frame
  delimiter : Activation
  useSiteCapabilities : List Located
  localRegions : List RegionInstanceId
  frozenCells : List FrozenCell
  scope : LexicalScopeId
  invocation : InvocationId

inductive Object where
  | closure : SchemaId .source → FunctionId .source → Environment → Object
  | capability : AttachmentId → EffectId .source → Object
  | region : RegionInstanceId → RegionId .source → InvocationId → Option RegionInstanceId → Object
  | cell : CellId → SchemaId .source → RegionInstanceId → Located → Object
  | oneShot : Capture → Object
  | multiTemplate : Capture → Object
  | package : SchemaId .source → Located → Object
  | resource : SchemaId .source → Located → Object
  | borrow : SchemaId .source → NodeId → RegionInstanceId → InvocationId → Object

structure Scope where
  id : LexicalScopeId
  invocation : InvocationId
  parent : Option LexicalScopeId
  nextOwner : Nat
  holdings : List Located := []

structure Invocation where
  id : InvocationId
  function : FunctionId .source
  capabilityParents : List AttachmentId
  regionParents : List RegionInstanceId

structure Heap where
  /-- Retired objects leave tombstones. Serialized IDs are never recycled. -/
  objects : List (Option Object) := []
  obligations : List (Cleanup.Obligation .source) := []
  loans : List (RegionInstanceId × ObligationId) := []
  scopes : List Scope := []
  invocations : List Invocation := []
  custody : Custody.Book := Custody.empty
  nextCustody : Nat := 0
  nextAttachment : Nat := 0
  nextRegion : Nat := 0
  nextCell : Nat := 0
  nextInvocation : Nat := 0
  nextScope : Nat := 0
  nextObligation : Nat := 0

def Heap.lookup (heap : Heap) (reference : NodeId) : Option Object :=
  heap.objects[reference.value]?.bind id

def ownedTokens (value : SemanticValue) : List CustodyToken := match value with
  | .reference _ _ token => token.toList
  | .product _ fields | .sequence _ fields => fields.flatMap ownedTokens
  | .variant _ _ payload => ownedTokens payload
  | .scalar _ _ | .blob _ _ => []

def Located.moves (located : Located) (receiver : Custody.Owner) : List Custody.Move :=
  (ownedTokens located.value).map (fun token => ⟨token, located.owner, receiver⟩)

def moveValues (heap : Heap) (values : List Located) (receiver : Nat → Custody.Owner) : Option Heap := do
  let custody ← Custody.commit heap.custody ((values.mapIdx fun index value => value.moves (receiver index)).flatten)
  return { heap with custody := custody }

def consumeValue (heap : Heap) (located : Located) : Option Heap := do
  let custody ← Custody.consume heap.custody (ownedTokens located.value) located.owner
  return { heap with custody := custody }

def retainAt (located : Located) (owner : Custody.Owner) : Located := { located with owner := owner }

/-- Data allocation returns a mathematical fresh reference. Operational memory
capacity belongs to the certificate runner and never becomes an authored fault. -/
def allocateObject (heap : Heap) (schema : SchemaId .source) (object : Object)
    (owner : Custody.Owner) (exclusive : Bool) : Option (Heap × Located) := do
  let reference : NodeId := ⟨heap.objects.length⟩
  let token : CustodyToken := ⟨heap.nextCustody⟩
  let custody ← if exclusive then Custody.allocate heap.custody token reference owner else some heap.custody
  let after := { heap with
    objects := heap.objects ++ [some object]
    custody := custody
    nextCustody := if exclusive then heap.nextCustody + 1 else heap.nextCustody }
  return (after, ⟨.reference schema reference (if exclusive then some token else none), owner⟩)

def replaceObject (heap : Heap) (reference : NodeId) (object : Object) : Option Heap :=
  if reference.value < heap.objects.length then some { heap with objects := heap.objects.set reference.value (some object) }
  else none

def retireObject (heap : Heap) (located : Located) : Option Heap := do
  let .reference _ reference (some _) := located.value | none
  let _ ← heap.lookup reference
  let after ← consumeValue heap located
  return { after with objects := after.objects.set reference.value none }

inductive Control where
  | term : TermId → Environment → Control
  | expression : SourceValueId → Environment → Control
  | delivered : Located → Control
  | execute : Intent → Environment → List Located → Control
  | invoke : FunctionId .source → Environment → List Located → Control
  | unwind : Cleanup.Exit .source → Control
  | release : LexicalScopeId → AfterRelease → Control
  | discard : List Located → AfterRelease → Control

structure Request where
  occurrence : RequestOccurrence
  effect : EffectId .source
  payload : SemanticValue
  bodies : List Located
  useSiteCapabilities : List Located
  result : SchemaId .source

inductive Status where
  | running | yielded
  | parked : Request → Status
  | completed : SemanticValue → Status
  | failed : Cleanup.Exit .source → Status
  | cancelled : Cleanup.Exit .source → Status

structure State where
  control : Control
  stack : List Frame
  heap : Heap
  scope : LexicalScopeId
  invocation : InvocationId
  status : Status := .running
  nextOccurrence : Nat := 0
  cancellation : Option Protocol.Reason := none

/-- The machine owns the first cancellation. Local exit records retain their
primary and cleanup failures; their cancellation field is a derived view. -/
def observedExit (state : State) (exit : Cleanup.Exit .source) : Cleanup.Exit .source :=
  match state.cancellation with
  | none => exit
  | some reason => Cleanup.cancel { exit with cancellation := none } reason

inductive Event where
  | requestOpened : Request → Event
  | resultAccepted : RequestOccurrence → SemanticValue → Event
  | requestRebound : RequestOccurrence → Event
  | yielded
  | completed : SemanticValue → Event
  | failed : Cleanup.Exit .source → Event
  | cancelled : Cleanup.Exit .source → Event
  | cleanup : Cleanup.Event → Event
  | transferred : TransferId → Event

structure Transition where
  state : State
  events : List Event := []

inductive Invalid where
  | reference | type | operands | custody | scope | inactive
  deriving DecidableEq, Repr

/-- Administrative paths use these actual syntax/control changes. Source
execution is a transition relation, not a bounded recursive evaluator. -/
def enterTerm (state : State) (source : Module) : Except Invalid Transition := do
  let .term reference environment := state.control | throw .inactive
  let some term := source.terms[reference.value]? | throw .reference
  match term with
  | .bind var value next => return ⟨{ state with
      control := .term value environment
      stack := .binding var next environment state.scope :: state.stack }, []⟩
  | .yieldThen next => return ⟨{ state with control := .term next environment, status := .yielded }, [.yielded]⟩
  | .value value => return ⟨{ state with control := .expression value environment }, []⟩
  | .conditional .. | .call .. | .apply .. | .perform _ | .handle .. | .resumeValue ..
  | .resumeWith .. | .resumeComputation .. | .protect .. | .withRegion .. | .dispose _ | .fail _
  | .matchSum .. | .unpackProduct .. =>
    match Analysis.termValues term with
    | [] => return ⟨{ state with control := .execute (.term term) environment [] }, []⟩
    | first :: rest => return ⟨{ state with
        control := .expression first environment
        stack := .operands (.term term) environment rest [] :: state.stack }, []⟩

theorem entering_bind_retains_heap_and_custody (state : State) (source : Module)
    (reference : TermId) (environment : Environment) (var : VariableId) (value next : TermId)
    (control : state.control = .term reference environment)
    (code : source.terms[reference.value]? = some (.bind var value next)) :
    enterTerm state source = .ok ⟨{ state with
      control := .term value environment
      stack := .binding var next environment state.scope :: state.stack }, []⟩ := by
  simp [enterTerm, control, code]
  rfl

theorem heap_allocation_fresh (heap after : Heap) (schema : SchemaId .source) (object : Object)
    (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (allocated : allocateObject heap schema object owner exclusive = some (after, value)) :
    after.objects.length = heap.objects.length + 1 := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at allocated
  · rcases allocated with ⟨rfl, _⟩; simp
  · obtain ⟨_, _, rfl, _⟩ := allocated; simp

end BoundaryV2.Profile.Source.Machine
