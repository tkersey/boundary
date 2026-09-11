import BoundaryV2.SourceBorrowDependencies

namespace BoundaryV2.Profile.Source.Borrow

def mapAmbient (binding : Binding) (component : Ambient) : Option Mapped :=
  match binding.resumed with
  | some token => some (.one (.value token (prepend (.resumed (some component)) [])))
  | none => match binding.operation with
    | some (.perform _ capability ..) => do
      let capability ← capability
      return .one (.value capability (prepend (.outer (some component)) []))
    | some _ => none
    | none =>
      if binding.fresh == some component then some ⟨some component, []⟩
      else some (.one (.ambient component))

def mapOperation (context : Context) (binding : Binding) (operation : Invocation)
    (parameter : Nat) (path : Path) : Option Mapped := do
  let .perform _ capability payload bodies sites := operation | none
  let capability ← capability
  let handlerId ← binding.handler
  let handler ← context.source.handlers[handlerId.value]?
  if parameter < handler.state.length then
    return .one (.value capability (prepend (.handlerState handlerId parameter) path))
  let argument := parameter - handler.state.length
  if argument == 0 then return .one (.value payload path)
  if argument ≤ bodies.length then
    let body ← bodies[argument - 1]?
    return .one (.value body path)
  match path with
  | .bodyResult _ :: _ | .resumed _ :: _ => return .one (.value capability path)
  | .useSite index _ :: rest =>
    let site ← sites[index]?
    return .one (.value site rest)
  | _ => return .one (.value capability (prepend (.outer none) []))

def mapSupplied (context : Context) (binding : Binding) (path : Path) : Option Mapped := do
  match path with
  | .outer component :: _ => return .ambient component
  | .resumed component :: _ =>
    if binding.fresh == some .evidence then
      match component with
      | some .region => return .ambient (some .region)
      | none => return ⟨some .evidence, [.ambient .region]⟩
      | some .evidence => pure ()
    return ⟨some (← binding.fresh), []⟩
  | .handlerState handler field :: rest =>
    if binding.handler != some handler then return ⟨none, []⟩
    let reference ← binding.state[field]?
    return .one (.value reference rest)
  | .handlerCapture handler var :: rest =>
    if binding.handler != some handler then return ⟨none, []⟩
    let reference ← (binding.environment.find? (fun entry => entry.1 == var)).map Prod.snd
    return .one (.value reference rest)
  | .bodyResult result :: rest =>
    if binding.fresh == some .evidence then
      let handlerId ← binding.handler
      let handler ← context.source.handlers[handlerId.value]?
      if handler.input != result then return ⟨none, []⟩
      return .one (.bodyResult binding.node rest)
    return ⟨some (← binding.fresh), []⟩
  | _ => return ⟨some (← binding.fresh), []⟩

def mapParameter (context : Context) (binding : Binding) (parameter : Nat) (path : Path) : Option Mapped := do
  let function ← context.source.functions[binding.function.value]?
  if parameter ≥ function.parameters.length then none else do
    match binding.operation with
    | some operation => mapOperation context binding operation parameter path
    | none => match binding.resumed with
      | some token =>
        let var ← function.parameters[parameter]?
        let schema ← context.source.variables[var.value]?
        return .one (.value token (prepend (.useSite parameter schema) path))
      | none =>
        if parameter < binding.supplied then mapSupplied context binding path
        else
          let reference ← binding.arguments[parameter - binding.supplied]?
          return .one (.value reference path)

def mapCaptured (binding : Binding) (var : VariableId) (path : Path) : Option Mapped := do
  match binding.computation with
  | some closure => return .one (.value closure (prepend (.environment binding.function var) path))
  | none => match binding.operation with
    | some (.perform _ capability ..) =>
      let capability ← capability
      let handler ← binding.handler
      return .one (.value capability (prepend (.handlerCapture handler var) path))
    | some _ => none
    | none =>
      let reference ← (binding.environment.find? (fun entry => entry.1 == var)).map Prod.snd
      return .one (.value reference path)

def mapInput (context : Context) (binding : Binding) : Origin → Option Mapped
  | .ambient component => mapAmbient binding component
  | .parameter parameter path => mapParameter context binding parameter path
  | .captured var path => mapCaptured binding var path

def mapOwner (context : Context) (binding : Binding) (origin : Origin) (bound : Bound) : Option Mapped := do
  let mapped ← mapInput context binding origin
  if bound == .clause && mapped.fresh == some .evidence &&
    (match origin with | .parameter _ [] => true | _ => false)
  then return .ambient none
  else return mapped

def bodyBinding (context : Context) (node closure : ValueRef) (arguments : List ValueRef)
    (supplied : Nat) (function : FunctionId .source) : Option Binding := do
  let code ← nodeAt context node
  let .invocation invocation := code.expression | none
  return {
    node := node, function := function, arguments := arguments
    computation := some closure, supplied := supplied
    resumed := match invocation with | .resumeComputation token _ => some token | _ => none
    fresh := match invocation with
      | .handle .. => some .evidence
      | .withRegion .. => some .region
      | .protect body _ _ _ region => if body == closure && region.isSome then some .region else none
      | _ => none
    handler := match invocation with | .handle handler .. => some handler | _ => none
    state := match invocation with | .handle _ _ _ _ state => state | _ => []
    environment := match invocation with | .handle _ environment .. => environment | _ => [] }

def bodyBindings (context : Context) (node closure : ValueRef) (arguments : List ValueRef) (supplied : Nat) :
    Option (List Binding) := do
  let schema ← valueType context closure
  let constructors := (Analysis.constructors context.source).filter (fun constructor => constructor.2 == schema)
  constructors.mapM (fun constructor => bodyBinding context node closure arguments supplied constructor.1)

theorem captured_closure_exact (binding : Binding) (closure : ValueRef) (var : VariableId) (path : Path)
    (found : binding.computation = some closure) :
    mapCaptured binding var path = some (.one (.value closure (.environment binding.function var :: path))) := by
  simp [mapCaptured, found, prepend]

theorem clause_owner_is_outside (context : Context) (binding : Binding) (parameter : Nat) (mapped : Mapped)
    (mapping : mapInput context binding (.parameter parameter []) = some mapped)
    (fresh : mapped.fresh = some .evidence) :
    mapOwner context binding (.parameter parameter []) .clause = some (.ambient none) := by
  simp [mapOwner, mapping, fresh]

end BoundaryV2.Profile.Source.Borrow
