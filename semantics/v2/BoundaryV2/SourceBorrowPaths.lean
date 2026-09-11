import BoundaryV2.BorrowLifetime
import BoundaryV2.SourceBorrowGraph
import BoundaryV2.SourceDeclarations

namespace BoundaryV2.Profile.Source.Borrow

abbrev Ambient := BorrowLifetime.Ambient

inductive Projection where
  | field : Nat → Projection
  | element : Projection
  | environment : FunctionId .source → VariableId → Projection
  | handlerState : HandlerId .source → Nat → Projection
  | handlerCapture : HandlerId .source → VariableId → Projection
  | useSite : Nat → SchemaId .source → Projection
  | cellContent | packageToken
  | outer : Option Ambient → Projection
  | resumed : Option Ambient → Projection
  | bodyResult : SchemaId .source → Projection
  deriving DecidableEq, Repr

abbrev Path := List Projection

inductive Origin where
  | parameter : Nat → Path → Origin
  | captured : VariableId → Path → Origin
  | ambient : Ambient → Origin
  deriving DecidableEq, Repr

inductive Trace where
  | value : ValueRef → Path → Trace
  | ambient : Ambient → Trace
  | bodyResult : ValueRef → Path → Trace
  deriving DecidableEq, Repr

abbrev Bound := BorrowLifetime.Bound

structure Constraint where
  value : Origin
  owner : Origin
  bound : Bound
  deriving DecidableEq, Repr

structure Context where
  source : Module
  graph : Array Function
  current : FunctionId .source

structure Binding where
  node : ValueRef
  function : FunctionId .source
  environment : Environment := []
  arguments : List ValueRef := []
  computation : Option ValueRef := none
  supplied : Nat := 0
  fresh : Option Ambient := none
  handler : Option (HandlerId .source) := none
  state : List ValueRef := []
  operation : Option Invocation := none
  resumed : Option ValueRef := none
  deriving DecidableEq, Repr

structure Mapped where
  fresh : Option Ambient := none
  traces : List Trace := []
  deriving DecidableEq, Repr

def Mapped.one (trace : Trace) : Mapped := ⟨none, [trace]⟩
def Mapped.ambient : Option Ambient → Mapped
  | some component => .one (.ambient component)
  | none => ⟨none, [.ambient .evidence, .ambient .region]⟩

def prepend (step : Projection) (path : Path) : Path :=
  match step, path with
  | .outer component, .outer next :: _ => if component == next then path else step :: path
  | _, _ => step :: path

def selectedSchema (source : Module) (schema : SchemaId .source) (step : Projection) :
    Option (SchemaId .source) := do
  let type ← source.schemas[schema.value]?
  match step with
  | .field field => match type with
    | .product fields | .sum fields => fields[field]?
    | _ => none
  | .element => match type with | .seq item | .vector item _ | .array item _ => some item | _ => none
  | .environment function var =>
    if !(Analysis.constructors source).contains (function, schema) then none
    else source.variables[var.value]?
  | .handlerState handler field =>
    let .internal (.capability _) := type | none
    let handler ← source.handlers[handler.value]?
    handler.state[field]?
  | .handlerCapture handler var =>
    let .internal (.capability _) := type | none
    let _ ← source.handlers[handler.value]?
    source.variables[var.value]?
  | .cellContent => match type with | .internal (.cell item _) => some item | _ => none
  | .packageToken => match type with | .internal (.suspensionPackage item) => some item | _ => none
  | .useSite index schema =>
    let .internal (.resumption signature) := type | none
    let effect ← source.effects[signature.effect.value]?
    let selected ← effect.useSiteEffects[index]?
    if Admission.capability source schema selected then some schema else none
  | .outer _ => match type with | .internal (.capability _) => some schema | _ => none
  | .resumed _ => match type with
    | .internal (.capability _) | .internal (.resumption _) => some schema
    | _ => none
  | .bodyResult result => match type with
    | .internal (.capability _) => some result
    | .internal (.resumption signature) =>
      if signature.mode == .shallow && signature.answer == result then some result else none
    | _ => none

def outerProjection : Projection → Bool
  | .outer _ => true
  | _ => false

def normalizeAt (source : Module) (schema : SchemaId .source) (seen : List (SchemaId .source)) :
    Path → Option Path
  | [] => some []
  | step :: rest =>
    if !outerProjection step && seen.contains schema then some [] else do
      let next ← selectedSchema source schema step
      let tail ← normalizeAt source next (if outerProjection step then seen else schema :: seen) rest
      return step :: tail

def normalizePath (source : Module) (schema : SchemaId .source) (path : Path) : Path :=
  (normalizeAt source schema [] path).getD path

def selectPath (source : Module) : SchemaId .source → Path → Option (SchemaId .source)
  | schema, [] => some schema
  | schema, step :: rest => do
    let next ← selectedSchema source schema step
    selectPath source next rest

def nodeAt (context : Context) (reference : ValueRef) : Option Node := do
  let function ← context.graph[context.current.value]?
  function.nodes[reference]?

def valueType (context : Context) (reference : ValueRef) : Option (SchemaId .source) :=
  (nodeAt context reference).map Node.schema

def push (context : Context) (reference : ValueRef) (path : Path) : Option (List Trace) := do
  let schema ← valueType context reference
  let path := normalizePath context.source schema path
  match selectPath context.source schema path with
  | none => return []
  | some selected =>
    if Traits.check context.source.schemas .external selected then return []
    else return [.value reference path]

def pushTrace (context : Context) : Trace → Option (List Trace)
  | .value reference path => push context reference path
  | trace => some [trace]

def pushes (context : Context) (traces : List Trace) : Option (List Trace) := do
  return (← traces.mapM (pushTrace context)).flatten

def pushValues (context : Context) (references : List ValueRef) (path : Path) : Option (List Trace) :=
  pushes context (references.map (fun reference => .value reference path))

def childPath (path : Path) (step : Projection) : Option Path :=
  match path with
  | [] => some []
  | selected :: rest => if selected == step then some rest else none

def pathComponent : Path → Option Ambient
  | [] => none
  | .outer component :: _ | .resumed component :: _ => component
  | _ :: rest => pathComponent rest

def selectedComponent : Trace → Option Ambient
  | .ambient component => some component
  | .bodyResult _ path | .value _ path => pathComponent path

/-- A fresh dependency cannot escape into an owner of the same ancestry. -/
def mappedConstraintValid (values owners : Mapped) : Bool :=
  BorrowLifetime.compatible values.fresh owners.traces selectedComponent

theorem fresh_constraint_rejects_same_component (values owners : Mapped) (component : Ambient) (owner : Trace)
    (fresh : values.fresh = some component) (included : owner ∈ owners.traces)
    (selected : selectedComponent owner = some component) : mappedConstraintValid values owners = false :=
  BorrowLifetime.rejects_same_component values.fresh owners.traces selectedComponent component owner fresh included selected

end BoundaryV2.Profile.Source.Borrow
