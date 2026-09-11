import BoundaryV2.SourceBorrowMapping

namespace BoundaryV2.Profile.Source.Borrow

inductive QueryKind where
  | returned : Path → QueryKind
  | origin : Trace → QueryKind
  | writes : SchemaId .source → Path → QueryKind
  deriving DecidableEq, Repr

structure Query where
  function : FunctionId .source
  kind : QueryKind
  deriving DecidableEq, Repr

structure QueryRow where
  query : Query
  origins : List Origin
  support : List Trace
  deriving DecidableEq, Repr

structure RequirementsRow where
  function : FunctionId .source
  constraints : List Constraint
  deriving DecidableEq, Repr

structure Witness where
  queries : List QueryRow
  requirements : List RequirementsRow
  deriving DecidableEq, Repr

inductive Request where
  | query : Query → Request
  | requirements : FunctionId .source → Request
  deriving DecidableEq, Repr

/-- Missing summaries produce empty candidates during witness search. Every
lookup is recorded, and acceptance requires every requested row to be present
and closed. Search completion therefore cannot become an admission shortcut. -/
abbrev Evaluation := StateT (List Request) (Except Unit)

def require (value : Option α) : Evaluation α :=
  match value with | some value => pure value | none => throw ()

def normalizedQuery (source : Module) (query : Query) : Option Query := do
  let function ← source.functions[query.function.value]?
  match query.kind with
  | .returned path => return { query with kind := .returned (normalizePath source function.result path) }
  | .origin _ | .writes _ _ => return query

def originsAt (source : Module) (witness : Witness) (query : Query) : Evaluation (List Origin) := do
  let query ← require (normalizedQuery source query)
  modify (fun requests => .query query :: requests)
  return ((witness.queries.find? (fun row => row.query == query)).map QueryRow.origins).getD []

def requirementsAt (witness : Witness) (function : FunctionId .source) : Evaluation (List Constraint) := do
  modify (fun requests => .requirements function :: requests)
  return ((witness.requirements.find? (fun row => row.function == function)).map RequirementsRow.constraints).getD []

def requestPresent (witness : Witness) : Request → Bool
  | .query query => witness.queries.any (fun row => row.query == query)
  | .requirements function => witness.requirements.any (fun row => row.function == function)

def transferOrigins (context : Context) (binding : Binding) (origins : List Origin) : Option (List Trace) := do
  let mapped ← origins.mapM (mapInput context binding)
  if mapped.any (fun item => item.fresh.isSome) then none
  else pushes context (mapped.flatMap Mapped.traces)

def callOrigins (context : Context) (witness : Witness) (binding : Binding) (kind : QueryKind) :
    Evaluation (List Trace) := do
  let origins ← originsAt context.source witness ⟨binding.function, kind⟩
  require (transferOrigins context binding origins)

def bodyOrigins (context : Context) (witness : Witness) (node closure : ValueRef)
    (arguments : List ValueRef) (supplied : Nat) (kind : QueryKind) : Evaluation (List Trace) := do
  let bindings ← require (bodyBindings context node closure arguments supplied)
  return (← bindings.mapM (fun binding => callOrigins context witness binding kind)).flatten

def returnInput (context : Context) (witness : Witness) (node : ValueRef) (origin : Origin) :
    Evaluation (List Trace) := do
  let code ← require (nodeAt context node)
  let .invocation invocation := code.expression | throw ()
  let (handlerId, environment, state) ← require (match invocation with
    | .handle handler environment _ _ state | .resumeWith _ _ handler environment state =>
      some (handler, environment, state)
    | _ => none)
  match origin with
  | .ambient component => return [.ambient component]
  | .captured var path =>
    let reference ← require ((environment.find? (fun entry => entry.1 == var)).map Prod.snd)
    require (push context reference path)
  | .parameter parameter path =>
    if parameter < state.length then
      let reference ← require state[parameter]?
      require (push context reference path)
    else
      let handler ← require context.source.handlers[handlerId.value]?
      if parameter != state.length then throw ()
      match invocation with
      | .handle _ _ body arguments _ =>
        bodyOrigins context witness node body arguments handler.clauses.length (.returned path)
      | .resumeWith token .. => require (push context token (prepend (.bodyResult handler.input) path))
      | _ => throw ()

def returnOrigins (context : Context) (witness : Witness) (node : ValueRef)
    (handler : Handler .source) (kind : QueryKind) : Evaluation (List Trace) := do
  let origins ← originsAt context.source witness ⟨handler.returnFunction, kind⟩
  return (← origins.mapM (returnInput context witness node)).flatten

def clauseOutput (context : Context) (witness : Witness) (body : ValueRef)
    (arguments state : List ValueRef) (environment : Environment) (clause : Clause .source)
    (path : Path) : Evaluation (List Trace) := do
  if clause.direct then return []
  let function ← require context.source.functions[clause.function.value]?
  let origins ← originsAt context.source witness ⟨clause.function, .returned path⟩
  let parts ← origins.mapM fun origin => match origin with
    | .ambient component => pure [.ambient component]
    | .captured var path => do
      let reference ← require ((environment.find? (fun entry => entry.1 == var)).map Prod.snd)
      require (push context reference path)
    | .parameter parameter path => do
      if parameter < state.length then
        let reference ← require state[parameter]?
        require (push context reference path)
      else
        let inputs ← require (pushValues context (body :: arguments) [])
        return inputs ++ (if parameter == function.parameters.length - 1
          then [.ambient .evidence, .ambient .region] else [])
  return parts.flatten

def operationBindings (context : Context) (node : ValueRef) (operation : Invocation) : List Binding :=
  match operation with
  | .perform effect .. => context.source.handlers.zipIdx.flatMap (fun (handler, handlerId) =>
      handler.clauses.filterMap (fun clause => if clause.effect == effect then some {
        node := node, function := clause.function, handler := some ⟨handlerId⟩, operation := some operation }
      else none))
  | _ => []

def calledWrites (context : Context) (witness : Witness) (node : ValueRef) (invocation : Invocation)
    (schema : SchemaId .source) (path : Path) : Evaluation (List Trace) := do
  let kind := QueryKind.writes schema path
  match invocation with
  | .call function environment arguments =>
    callOrigins context witness
      { node := node, function := function, environment := environment, arguments := arguments } kind
  | .apply closure arguments => bodyOrigins context witness node closure arguments 0 kind
  | .withRegion _ body arguments => bodyOrigins context witness node body arguments 1 kind
  | .protect body cleanup arguments resource _ =>
    let body ← bodyOrigins context witness node body arguments resource.toList.length kind
    let cleanup ← bodyOrigins context witness node cleanup [] (1 + resource.toList.length) kind
    return body ++ cleanup
  | .handle handler _ body arguments _ =>
    let handler ← require context.source.handlers[handler.value]?
    let body ← bodyOrigins context witness node body arguments handler.clauses.length kind
    let returns ← returnOrigins context witness node handler kind
    return body ++ returns
  | .perform _ capability .. =>
    if capability.isNone then return []
    return (← (operationBindings context node invocation).mapM
      (fun binding => callOrigins context witness binding kind)).flatten
  | .resumeValue token argument | .resumeComputation token argument => require (pushValues context [token, argument] [])
  | .resumeWith token argument _ _ state => require (pushValues context ([token, argument] ++ state) [])
  | .dispose _ => return []

def outputOrigins (context : Context) (witness : Witness) (node : ValueRef) (invocation : Invocation)
    (path : Path) : Evaluation (List Trace) := do
  let kind := QueryKind.returned path
  match invocation with
  | .call function environment arguments =>
    callOrigins context witness
      { node := node, function := function, environment := environment, arguments := arguments } kind
  | .apply closure arguments => bodyOrigins context witness node closure arguments 0 kind
  | .withRegion _ body arguments => bodyOrigins context witness node body arguments 1 kind
  | .protect body _ arguments resource _ => bodyOrigins context witness node body arguments resource.toList.length kind
  | .handle handler environment body arguments state =>
    let handler ← require context.source.handlers[handler.value]?
    let returns ← returnOrigins context witness node handler kind
    let clauses ← handler.clauses.mapM
      (fun clause => clauseOutput context witness body arguments state environment clause path)
    return returns ++ clauses.flatten
  | .resumeValue token argument | .resumeComputation token argument => require (pushValues context [token, argument] [])
  | .resumeWith token argument _ _ state => require (pushValues context ([token, argument] ++ state) [])
  | .perform _ capability payload bodies sites =>
    let capability := capability.toList.map (fun reference => .value reference (prepend (.outer none) []))
    let operands := (payload :: bodies ++ sites).map (fun reference => .value reference [])
    require (pushes context (capability ++ operands))
  | .dispose _ => return []

end BoundaryV2.Profile.Source.Borrow
