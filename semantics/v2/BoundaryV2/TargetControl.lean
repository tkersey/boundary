import BoundaryV2.TargetState

namespace BoundaryV2.Profile.Target.Machine

private def literalBlob (literal : Literal .target) : Graph.Blob := ⟨literal.schema, literal.bytes⟩

structure Context where
  program : Program
  constants : List (StoredBlob program.schemas)
  inventory : constants.map StoredBlob.raw = program.constants.map literalBlob

def Context.ofWitness (program : Program) (meanings : List SemanticValue) : Option Context :=
  match admitted : Store.admitBlobs program.schemas (program.constants.map literalBlob) meanings with
  | none => none
  | some constants => some ⟨program, constants,
      (Store.admitted_blob_inventory _ _ _ _ admitted).1⟩

inductive Result where
  | completed : SemanticValue → Result
  | failed : SemanticValue → List SemanticValue → Option Protocol.Reason → Result
  | cancelled : Protocol.Reason → List SemanticValue → Result

/-- One target state is rooted in BPI2 blocks and PST2 graph records. The source
AST, lexical-variable evaluator, and source continuation type are absent. -/
structure State (program : Program) where
  identity : Digest
  store : Store program.schemas
  status : Graph.Status := .active
  roots : Graph.Roots := {}
  result : Option Result := none
  nextOccurrence : Nat := 0
  pendingOccurrence : Option RequestOccurrence := none

def State.raw (state : State program) : Graph.State :=
  state.store.raw state.identity state.status state.roots

inductive Event where
  | requestOpened : RequestOccurrence → EffectId .target → SemanticValue → Event
  | responseAccepted : RequestOccurrence → SemanticValue → Event
  | requestRebound : RequestOccurrence → Event
  | yielded
  | completed : SemanticValue → Event
  | failed : SemanticValue → List SemanticValue → Option Protocol.Reason → Event
  | cancelled : Protocol.Reason → List SemanticValue → Event

structure Transition (program : Program) where
  state : State program
  events : List Event := []

def initial (context : Context) (identity : Digest) (arguments : List SemanticValue) : Except Invalid (State context.program) := do
  let entry ← fromOption context.program.functions[context.program.roots.entry.value]? .reference
  require (arguments.map Profile.Value.schema == entry.parameters) .type
  let (store, arguments) ← arguments.foldlM (fun (store, values) argument => do
    let (store, value) ← storeExternal store argument
    pure (store, values ++ [value])) (({} : Store context.program.schemas), ([] : List Graph.Value))
  let (store, current) := store.add (.control ⟨entry.entry, arguments, none, none, none⟩)
  return ⟨identity, store, .active, { current := some current }, none, 0, none⟩

def nextEdge : Terminator → Option Edge
  | .call _ _ next | .apply _ _ next | .handle _ _ _ _ next
  | .resumeValue _ _ next | .resumeWith _ _ _ _ next | .resumeComputation _ _ next
  | .dispose _ next | .protect _ _ _ _ _ next | .withRegion _ _ _ next => some next
  | .perform operation | .forward operation => some operation.next
  | _ => none

def slot (values : List Graph.Value) (slot : Slot) : Except Invalid Graph.Value :=
  fromOption values[slot.value]? .operands

def slots (values : List Graph.Value) (selected : List Slot) : Except Invalid (List Graph.Value) :=
  selected.mapM (slot values)

def edgeArguments (edge : Edge) (values : List Graph.Value) (returned : Option Graph.Value) : Except Invalid (List Graph.Value) :=
  edge.arguments.mapM fun argument => match argument with
    | .slot index => slot values index
    | .returned => fromOption returned .operands

def currentControl (state : State program) : Except Invalid Graph.Control := do
  let current ← fromOption state.roots.current .inactive
  let .control control ← fromOption (state.store.lookup current) .reference | throw .type
  return control

def installControl (state : State program) (control : Graph.Control) : State program :=
  let (store, current) := state.store.add (.control control)
  { state with store := store, roots := { state.roots with current := some current } }

def jump (state : State program) (control : Graph.Control) (edge : Edge)
    (values : List Graph.Value) (returned : Option Graph.Value := none) : Except Invalid (State program) := do
  let arguments ← edgeArguments edge values returned
  return installControl state { control with block := edge.block, arguments := arguments }

def continuation (state : State program) (control : Graph.Control) (values : List Graph.Value) :
    Except Invalid (State program × NodeId) := do
  let block ← fromOption program.blocks[control.block.value]? .reference
  let edge ← fromOption (nextEdge block.terminator) .type
  let arguments ← edge.arguments.mapM fun argument => match argument with
    | .slot index => return some (← slot values index)
    | .returned => pure none
  let saved : Graph.Continuation := ⟨control.block, arguments, control.parent, control.evidence, control.region⟩
  let (store, reference) := state.store.add (.continuation saved)
  return ({ state with store := store }, reference)

def resumeContinuation (state : State program) (reference : NodeId) (value : Graph.Value) :
    Except Invalid (State program) := do
  let .continuation saved ← fromOption (state.store.lookup reference) .reference | throw .type
  let block ← fromOption program.blocks[saved.sourceBlock.value]? .reference
  let edge ← fromOption (nextEdge block.terminator) .type
  require (saved.arguments.length == edge.arguments.length) .type
  let control : Graph.Control := ⟨edge.block, saved.arguments.map (·.getD value), saved.parent, saved.evidence, saved.region⟩
  return installControl { state with roots := { state.roots with evidence := saved.evidence } } control

def enter (state : State program) (function : FunctionId .target) (arguments : List Graph.Value)
    (parent evidence region : Option NodeId) : Except Invalid (State program) := do
  let definition ← fromOption program.functions[function.value]? .reference
  require (arguments.map Graph.Value.schema == definition.parameters) .type
  return installControl { state with roots := { state.roots with evidence := evidence } }
    ⟨definition.entry, arguments, parent, evidence, region⟩

def valueReference (value : Graph.Value) : Except Invalid NodeId := match value.body with
  | .reference reference => .ok reference
  | .owned reference => .ok reference.node
  | _ => .error .type

/-- Flatten a captured lexical environment by its explicit finite graph links.
Application recursion does not participate in this walk. -/
def environmentValues (store : Store schemas) : Nat → Option NodeId → Except Invalid (List Graph.Value)
  | _, none => .ok []
  | 0, some _ => .error .scope
  | count + 1, some reference => do
    let .environment values tail ← fromOption (store.lookup reference) .reference | throw .type
    return values ++ (← environmentValues store count tail)

def applyComputation (state : State program) (value : Graph.Value) (arguments : List Graph.Value)
    (parent evidence region : Option NodeId) : Except Invalid (State program) := do
  let .internal (.computation signature) ← fromOption program.schemas[value.schema.value]? .type | throw .type
  require (arguments.map Graph.Value.schema == signature.parameters) .type
  let reference ← valueReference value
  let .computation constructor environment ← fromOption (state.store.lookup reference) .reference | throw .type
  let definition ← fromOption program.constructors[constructor.value]? .reference
  require (definition.schema == value.schema) .type
  let captured ← environmentValues state.store (state.store.nodes.length + 1) (some environment)
  enter state definition.function (captured ++ arguments) parent evidence region

/-- Exact BPI2 return-edge test used only for an administrative frame omission. -/
def tailCall (program : Program) (next : Edge) : Bool :=
  match program.blocks[next.block.value]? with
  | some block => match block.terminator with
    | .returnValue result => block.instructions.isEmpty && next.arguments[result.value]? == some .returned
    | _ => false
  | none => false

def call (state : State program) (control : Graph.Control) (function : FunctionId .target)
    (selected : List Slot) (next : Edge) (values : List Graph.Value) : Except Invalid (State program) := do
  let arguments ← slots values selected
  let (state, parent) ← if tailCall program next then pure (state, control.parent) else do
    let (state, saved) ← continuation state control values
    pure (state, some saved)
  enter state function arguments parent control.evidence control.region

theorem installControl_preserves_outside (state : State program) (control : Graph.Control) :
    (installControl state control).roots.evidence = state.roots.evidence ∧
    (installControl state control).roots.detached = state.roots.detached ∧
    (installControl state control).roots.exit = state.roots.exit ∧
    (installControl state control).roots.pending = state.roots.pending := by
  exact ⟨rfl, rfl, rfl, rfl⟩

theorem saved_return_arguments (saved : Graph.Continuation) (value : Graph.Value) :
    (saved.arguments.map (·.getD value)).length = saved.arguments.length := by simp

end BoundaryV2.Profile.Target.Machine
