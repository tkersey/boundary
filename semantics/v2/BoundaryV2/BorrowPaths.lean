import BoundaryV2.UseAdmission

namespace BoundaryV2.Profile.Target.Borrow

inductive Ambient where
  | evidence | region
  deriving DecidableEq, Repr

inductive Projection where
  | field : Nat → Projection
  | element : Projection
  | environment : ConstructorId → Nat → Projection
  | handlerState : HandlerId .target → Nat → Projection
  | useSite : Nat → SchemaId .target → Projection
  | cellContent | packageToken
  | outer : Option Ambient → Projection
  | resumed : Option Ambient → Projection
  | bodyResult : SchemaId .target → Projection
  deriving DecidableEq, Repr

abbrev Path := List Projection

inductive Source where
  | parameter : Nat → Path → Source
  | ambient : Ambient → Source
  deriving DecidableEq, Repr

inductive Trace where
  | slot : BlockId → Slot → Path → Trace
  | ambient : BlockId → Ambient → Trace
  | bodyResult : BlockId → Path → Trace
  deriving DecidableEq, Repr

def Trace.block : Trace → BlockId
  | .slot block _ _ | .ambient block _ | .bodyResult block _ => block

inductive Bound where
  | region | clause | capture
  deriving DecidableEq, Repr

structure Constraint where
  value : Source
  owner : Source
  bound : Bound
  deriving DecidableEq, Repr

structure Binding where
  block : BlockId
  function : FunctionId .target
  arguments : List Slot := []
  constructor : Option ConstructorId := none
  computationSlot : Option Slot := none
  supplied : Nat := 0
  fresh : Option Ambient := none
  handler : Option (HandlerId .target) := none
  state : List Slot := []
  operation : Option Perform := none
  resumed : Option Slot := none
  deriving DecidableEq, Repr

structure Mapped where
  fresh : Option Ambient := none
  traces : List Trace := []
  deriving DecidableEq, Repr

def Mapped.one (trace : Trace) : Mapped := ⟨none, [trace]⟩

def Mapped.ambient (block : BlockId) : Option Ambient → Mapped
  | some component => .one (.ambient block component)
  | none => ⟨none, [.ambient block .evidence, .ambient block .region]⟩

def prepend (step : Projection) (path : Path) : Path :=
  match step, path with
  | .outer component, .outer next :: _ => if component == next then path else step :: path
  | _, _ => step :: path

def selectedSchema (program : Program) (id : SchemaId .target) (step : Projection) :
    Option (SchemaId .target) := do
  let type ← Admission.shape program id
  match step with
  | .field field => match type with
    | .product fields | .sum fields => fields[field]?
    | _ => none
  | .element => Admission.element type
  | .environment constructor field =>
    let constructor ← program.constructors[constructor.value]?
    if constructor.schema != id then none else do
      let capture ← program.scopes.captures[constructor.capture.value]?
      capture.fields[field]?
  | .handlerState handler field =>
    let .internal (.capability _) := type | none
    let handler ← program.handlers[handler.value]?
    handler.state[field]?
  | .cellContent => match type with | .internal (.cell item _) => some item | _ => none
  | .packageToken => match type with | .internal (.suspensionPackage item) => some item | _ => none
  | .useSite index schema =>
    let .internal (.resumption signature) := type | none
    let effect ← program.effects[signature.effect.value]?
    let selected ← effect.useSiteEffects[index]?
    if Admission.capability program schema selected then some schema else none
  | .outer _ => match type with | .internal (.capability _) => some id | _ => none
  | .resumed _ => match type with
    | .internal (.capability _) | .internal (.resumption _) => some id
    | _ => none
  | .bodyResult result => match type with
    | .internal (.capability _) => some result
    | .internal (.resumption signature) =>
      if signature.mode == .shallow && signature.answer == result then some result else none
    | _ => none

def outerProjection : Projection → Bool
  | .outer _ => true
  | _ => false

/-- Revisiting a recursive schema broadens the selector to the whole subtree.
It preserves every field selection before the cycle. Invalid selections are
kept for the subsequent selector check, which finds no such component. -/
def normalizeAt (program : Program) (schema : SchemaId .target) (seen : List (SchemaId .target)) :
    Path → Option Path
  | [] => some []
  | step :: rest =>
    if !outerProjection step && seen.contains schema then some [] else do
      let next ← selectedSchema program schema step
      let tail ← normalizeAt program next (if outerProjection step then seen else schema :: seen) rest
      return step :: tail

def normalizePath (program : Program) (schema : SchemaId .target) (path : Path) : Path :=
  (normalizeAt program schema [] path).getD path

def selectPath (program : Program) : SchemaId .target → Path → Option (SchemaId .target)
  | schema, [] => some schema
  | schema, step :: rest => do
    let next ← selectedSchema program schema step
    selectPath program next rest

def slotType (program : Program) (block : BlockId) (slot : Slot) : Option (SchemaId .target) := do
  let block ← program.blocks[block.value]?
  (Admission.blockSlots block)[slot.value]?

/-- External data has no borrowed owner. An impossible projection denotes no
component; a malformed block or slot remains an admission error. -/
def push (program : Program) (block : BlockId) (slot : Slot) (path : Path) : Option (List Trace) := do
  let type ← slotType program block slot
  let path := normalizePath program type path
  match selectPath program type path with
  | none => return []
  | some selected =>
    if Traits.check program.schemas .external selected then return []
    else return [.slot block slot path]

def pushTrace (program : Program) : Trace → Option (List Trace)
  | .slot block slot path => push program block slot path
  | trace => some [trace]

def childPath (path : Path) (step : Projection) : Option Path :=
  match path with
  | [] => some []
  | selected :: rest => if selected == step then some rest else none

def pathComponent : Path → Option Ambient
  | [] => none
  | .outer component :: _ | .resumed component :: _ => component
  | _ :: rest => pathComponent rest

def selectedComponent : Trace → Option Ambient
  | .ambient _ component => some component
  | .bodyResult _ path | .slot _ _ path => pathComponent path

def isOuter (path : Path) : Bool := path.any outerProjection

theorem normalizeAt_prefix (program : Program) (schema : SchemaId .target)
    (seen : List (SchemaId .target)) (path normalized : Path)
    (accepted : normalizeAt program schema seen path = some normalized) : normalized <+: path := by
  induction path generalizing schema seen normalized with
  | nil =>
    simp [normalizeAt] at accepted
    subst normalized
    exact List.prefix_refl []
  | cons step rest ih =>
    unfold normalizeAt at accepted
    split at accepted
    · cases accepted
      exact List.nil_prefix
    · cases selected : selectedSchema program schema step with
      | none => simp [selected] at accepted
      | some next =>
        cases tail : normalizeAt program next (if outerProjection step then seen else schema :: seen) rest with
        | none => simp [selected, tail] at accepted
        | some tailPath =>
          have initialSegment := ih next _ tailPath tail
          simp [selected, tail] at accepted
          subst normalized
          simpa using initialSegment

theorem normalizePath_prefix (program : Program) (schema : SchemaId .target) (path : Path) :
    normalizePath program schema path <+: path := by
  cases normalized : normalizeAt program schema [] path with
  | none => simp [normalizePath, normalized]
  | some result => simpa [normalizePath, normalized] using normalizeAt_prefix program schema [] path result normalized

theorem normalizePath_length (program : Program) (schema : SchemaId .target) (path : Path) :
    (normalizePath program schema path).length ≤ path.length :=
  (normalizePath_prefix program schema path).length_le

theorem adjacent_outer_alias (component : Option Ambient) (path : Path) :
    prepend (.outer component) (.outer component :: path) = .outer component :: path := by simp [prepend]

end BoundaryV2.Profile.Target.Borrow
