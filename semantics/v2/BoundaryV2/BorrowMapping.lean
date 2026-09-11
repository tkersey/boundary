import BoundaryV2.BorrowPaths

namespace BoundaryV2.Profile.Target.Borrow

def mapAmbient (binding : Binding) (component : Ambient) : Option Mapped :=
  match binding.resumed with
  | some token => some (.one (.slot binding.block token (prepend (.resumed (some component)) [])))
  | none => match binding.operation with
    | some operation => do
      let capability ← operation.capability
      return .one (.slot binding.block capability (prepend (.outer (some component)) []))
    | none =>
      if binding.fresh == some component then some ⟨some component, []⟩
      else some (.one (.ambient binding.block component))

def mapOperation (program : Program) (binding : Binding) (operation : Perform)
    (parameter : Nat) (path : Path) : Option Mapped := do
  let capability ← operation.capability
  let handlerId ← binding.handler
  let handler ← program.handlers[handlerId.value]?
  if parameter < handler.state.length then
    return .one (.slot binding.block capability (prepend (.handlerState handlerId parameter) path))
  let argument := parameter - handler.state.length
  if argument == 0 then return .one (.slot binding.block operation.payload path)
  if argument ≤ operation.bodies.length then
    let body ← operation.bodies[argument - 1]?
    return .one (.slot binding.block body path)
  match path with
  | .bodyResult _ :: _ | .resumed _ :: _ => return .one (.slot binding.block capability path)
  | .useSite index _ :: rest =>
    let site ← operation.useSiteCapabilities[index]?
    return .one (.slot binding.block site rest)
  | _ => return .one (.slot binding.block capability (prepend (.outer none) []))

def mapSupplied (program : Program) (binding : Binding) (path : Path) : Option Mapped := do
  match path with
  | .outer component :: _ => return .ambient binding.block component
  | .resumed component :: _ =>
    if binding.fresh == some .evidence then
      match component with
      | some .region => return .ambient binding.block (some .region)
      | none => return ⟨some .evidence, [.ambient binding.block .region]⟩
      | some .evidence => pure ()
    return ⟨some (← binding.fresh), []⟩
  | .handlerState handler field :: rest =>
    if binding.handler != some handler then return ⟨none, []⟩
    let slot ← binding.state[field]?
    return .one (.slot binding.block slot rest)
  | .bodyResult result :: rest =>
    if binding.fresh == some .evidence then
      let handlerId ← binding.handler
      let handler ← program.handlers[handlerId.value]?
      if handler.input != result then return ⟨none, []⟩
      return .one (.bodyResult binding.block rest)
    return ⟨some (← binding.fresh), []⟩
  | _ => return ⟨some (← binding.fresh), []⟩

def captureCount (program : Program) (binding : Binding) : Option Nat :=
  match binding.constructor with
  | none => some 0
  | some constructor => do
    let constructor ← program.constructors[constructor.value]?
    let capture ← program.scopes.captures[constructor.capture.value]?
    return capture.fields.length

def mapParameter (program : Program) (binding : Binding) (parameter : Nat) (path : Path) : Option Mapped := do
  let function ← program.functions[binding.function.value]?
  if parameter ≥ function.parameters.length then none else do
    match binding.operation with
    | some operation => mapOperation program binding operation parameter path
    | none =>
      let captures ← captureCount program binding
      if parameter < captures then
        let constructor ← binding.constructor
        let closure ← binding.computationSlot
        return .one (.slot binding.block closure (prepend (.environment constructor parameter) path))
      match binding.resumed with
      | some token =>
        let schema ← function.parameters[parameter]?
        return .one (.slot binding.block token (prepend (.useSite (parameter - captures) schema) path))
      | none =>
        if parameter < captures + binding.supplied then mapSupplied program binding path
        else
          let slot ← binding.arguments[parameter - captures - binding.supplied]?
          return .one (.slot binding.block slot path)

def mapInput (program : Program) (binding : Binding) : Source → Option Mapped
  | .ambient component => mapAmbient binding component
  | .parameter parameter path => mapParameter program binding parameter path

def mapOwner (program : Program) (binding : Binding) (source : Source) (bound : Bound) : Option Mapped := do
  let mapped ← mapInput program binding source
  if bound == .clause && mapped.fresh == some .evidence &&
    (match source with | .parameter _ [] => true | _ => false)
  then return .ambient binding.block none
  else return mapped

def bodyBinding (program : Program) (block : BlockId) (closure : Slot) (arguments : List Slot)
    (supplied : Nat) (constructorId : ConstructorId) : Option Binding := do
  let code ← program.blocks[block.value]?
  let constructor ← program.constructors[constructorId.value]?
  return {
    block := block, function := constructor.function, arguments := arguments
    constructor := some constructorId, computationSlot := some closure, supplied := supplied
    resumed := match code.terminator with | .resumeComputation token _ _ => some token | _ => none
    fresh := match code.terminator with
      | .handle .. => some .evidence
      | .withRegion .. => some .region
      | .protect body _ _ _ region _ => if body == closure && region.isSome then some .region else none
      | _ => none
    handler := match code.terminator with | .handle handler .. => some handler | _ => none
    state := match code.terminator with | .handle _ _ _ state _ => state | _ => [] }

/-- A fresh value may be constrained by the other ancestry component. Any
owner trace selecting its own component would retain it outside this binder. -/
def mappedConstraintValid (values owners : Mapped) : Bool :=
  BorrowLifetime.compatible values.fresh owners.traces selectedComponent

theorem resumed_ambient_exact (binding : Binding) (token : Slot) (component : Ambient)
    (resumed : binding.resumed = some token) :
    mapAmbient binding component = some (.one (.slot binding.block token [.resumed (some component)])) := by
  simp [mapAmbient, resumed, prepend]

theorem fresh_ambient_exact (binding : Binding) (component : Ambient)
    (notResumed : binding.resumed = none) (notOperation : binding.operation = none)
    (fresh : binding.fresh = some component) :
    mapAmbient binding component = some ⟨some component, []⟩ := by
  simp [mapAmbient, notResumed, notOperation, fresh]

theorem clause_owner_is_outside (program : Program) (binding : Binding) (parameter : Nat) (mapped : Mapped)
    (mapping : mapInput program binding (.parameter parameter []) = some mapped)
    (fresh : mapped.fresh = some .evidence) :
    mapOwner program binding (.parameter parameter []) .clause = some (.ambient binding.block none) := by
  simp [mapOwner, mapping, fresh]

theorem fresh_constraint_rejects_same_component (values owners : Mapped) (component : Ambient) (owner : Trace)
    (fresh : values.fresh = some component) (included : owner ∈ owners.traces)
    (selected : selectedComponent owner = some component) : mappedConstraintValid values owners = false :=
  BorrowLifetime.rejects_same_component values.fresh owners.traces selectedComponent component owner fresh included selected

end BoundaryV2.Profile.Target.Borrow
