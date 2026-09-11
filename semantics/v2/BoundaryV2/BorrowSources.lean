import BoundaryV2.BorrowGraph

namespace BoundaryV2.Profile.Target.Borrow

inductive QueryKind where
  | returned : Path → QueryKind
  | origin : Trace → QueryKind
  | writes : SchemaId .target → Path → QueryKind
  deriving DecidableEq, Repr

structure Query where
  start : BlockId
  kind : QueryKind
  deriving DecidableEq, Repr

structure QueryRow where
  query : Query
  sources : List Source
  support : List Trace
  deriving DecidableEq, Repr

structure RequirementsRow where
  start : BlockId
  constraints : List Constraint
  deriving DecidableEq, Repr

structure Witness where
  queries : List QueryRow
  requirements : List RequirementsRow
  deriving DecidableEq, Repr

def normalizedQuery (program : Program) (query : Query) : Option Query := do
  let code ← program.blocks[query.start.value]?
  let function ← program.functions[code.function.value]?
  match query.kind with
  | .returned path => return { query with kind := .returned (normalizePath program function.result path) }
  | .origin _ | .writes _ _ => return query

def sourcesAt (program : Program) (witness : Witness) (query : Query) : Option (List Source) := do
  let query ← normalizedQuery program query
  let row ← witness.queries.find? (fun row => row.query == query)
  return row.sources

def requirementsAt (witness : Witness) (start : BlockId) : Option (List Constraint) :=
  (witness.requirements.find? (fun row => row.start == start)).map RequirementsRow.constraints

def functionEntry (program : Program) (function : FunctionId .target) : Option BlockId :=
  (program.functions[function.value]?).map Function.entry

def transferSources (program : Program) (binding : Binding) (sources : List Source) : Option (List Trace) := do
  let mapped ← sources.mapM (mapInput program binding)
  if mapped.any (fun item => item.fresh.isSome) then none
  else pushes program (mapped.flatMap Mapped.traces)

def callSources (program : Program) (witness : Witness) (binding : Binding) (kind : QueryKind) :
    Option (List Trace) := do
  let start ← functionEntry program binding.function
  let sources ← sourcesAt program witness ⟨start, kind⟩
  transferSources program binding sources

def bodyBindings (program : Program) (block : BlockId) (closure : Slot) (arguments : List Slot) (supplied : Nat) :
    Option (List Binding) := do
  let schema ← slotType program block closure
  let constructors := program.constructors.zipIdx.filter (fun (constructor, _) => constructor.schema == schema)
  constructors.mapM (fun (_, index) => bodyBinding program block closure arguments supplied ⟨index⟩)

def bodySources (program : Program) (witness : Witness) (block : BlockId) (closure : Slot)
    (arguments : List Slot) (supplied : Nat) (kind : QueryKind) : Option (List Trace) := do
  let bindings ← bodyBindings program block closure arguments supplied
  let parts ← bindings.mapM (fun binding => callSources program witness binding kind)
  return parts.flatten

def returnInput (program : Program) (witness : Witness) (block : BlockId) (source : Source) :
    Option (List Trace) := do
  let code ← program.blocks[block.value]?
  let state ← match code.terminator with
    | .handle _ _ _ state _ | .resumeWith _ _ _ state _ => some state
    | _ => none
  match source with
  | .ambient component => pushTrace program (.ambient block component)
  | .parameter parameter path =>
    if parameter < state.length then
      let slot ← state[parameter]?
      push program block slot path
    else match code.terminator with
      | .handle handler body arguments _ _ =>
        let handler ← program.handlers[handler.value]?
        bodySources program witness block body arguments handler.clauses.length (.returned path)
      | .resumeWith token _ handler _ _ =>
        let handler ← program.handlers[handler.value]?
        push program block token (prepend (.bodyResult handler.input) path)
      | _ => none

def returnSources (program : Program) (witness : Witness) (block : BlockId)
    (handler : Handler .target) (kind : QueryKind) : Option (List Trace) := do
  let start ← functionEntry program handler.returnFunction
  let sources ← sourcesAt program witness ⟨start, kind⟩
  let parts ← sources.mapM (returnInput program witness block)
  return parts.flatten

def clauseOutput (program : Program) (witness : Witness) (block : BlockId) (body : Slot)
    (arguments state : List Slot) (clause : Clause .target) (path : Path) : Option (List Trace) := do
  if clause.direct then return []
  let function ← program.functions[clause.function.value]?
  let sources ← sourcesAt program witness ⟨function.entry, .returned path⟩
  let parts ← sources.mapM fun source => match source with
    | .ambient component => pushTrace program (.ambient block component)
    | .parameter parameter path => do
      if parameter < state.length then
        let slot ← state[parameter]?
        push program block slot path
      else
        let inputs ← pushSlots program block (body :: arguments) []
        return inputs ++ (if parameter == function.parameters.length - 1
          then [.ambient block .evidence, .ambient block .region] else [])
  return parts.flatten

def operationBindings (program : Program) (block : BlockId) (operation : Perform) : List Binding :=
  program.handlers.zipIdx.flatMap (fun (handler, handlerId) => handler.clauses.filterMap (fun clause =>
    if clause.effect == operation.effect then some {
      block := block, function := clause.function, handler := some ⟨handlerId⟩, operation := some operation }
    else none))

def calledWrites (program : Program) (witness : Witness) (block : BlockId) (schema : SchemaId .target)
    (path : Path) : Option (List Trace) := do
  let code ← program.blocks[block.value]?
  let kind := QueryKind.writes schema path
  match code.terminator with
  | .call function arguments _ => callSources program witness { block := block, function := function, arguments := arguments } kind
  | .apply closure arguments _ => bodySources program witness block closure arguments 0 kind
  | .withRegion _ body arguments _ => bodySources program witness block body arguments 1 kind
  | .protect body cleanup arguments resource _ _ =>
    let body ← bodySources program witness block body arguments resource.toList.length kind
    let cleanup ← bodySources program witness block cleanup [] (1 + resource.toList.length) kind
    return body ++ cleanup
  | .handle handler body arguments _ _ =>
    let handler ← program.handlers[handler.value]?
    let body ← bodySources program witness block body arguments handler.clauses.length kind
    let returns ← returnSources program witness block handler kind
    return body ++ returns
  | .perform operation | .forward operation =>
    if operation.capability.isNone then return []
    let parts ← (operationBindings program block operation).mapM (fun binding => callSources program witness binding kind)
    return parts.flatten
  | .resumeValue token argument _ | .resumeComputation token argument _ => pushSlots program block [token, argument] []
  | .resumeWith token argument _ state _ => pushSlots program block ([token, argument] ++ state) []
  | .returnValue _ | .jump _ | .branch .. | .switchVariant .. | .unpackProduct ..
  | .yieldValue _ | .fail _ | .dispose .. => return []

def outputSources (program : Program) (witness : Witness) (block : BlockId) (path : Path) : Option (List Trace) := do
  let code ← program.blocks[block.value]?
  let kind := QueryKind.returned path
  match code.terminator with
  | .call function arguments _ => callSources program witness { block := block, function := function, arguments := arguments } kind
  | .apply closure arguments _ => bodySources program witness block closure arguments 0 kind
  | .withRegion _ body arguments _ => bodySources program witness block body arguments 1 kind
  | .protect body _ arguments resource _ _ => bodySources program witness block body arguments resource.toList.length kind
  | .handle handler body arguments state _ =>
    let handler ← program.handlers[handler.value]?
    let returns ← returnSources program witness block handler kind
    let clauses ← handler.clauses.mapM (fun clause => clauseOutput program witness block body arguments state clause path)
    return returns ++ clauses.flatten
  | .resumeValue token argument _ | .resumeComputation token argument _ => pushSlots program block [token, argument] []
  | .resumeWith token argument _ state _ => pushSlots program block ([token, argument] ++ state) []
  | .perform operation | .forward operation =>
    let capability := operation.capability.toList.map (fun slot => .slot block slot (prepend (.outer none) []))
    let operands := ([operation.payload] ++ operation.bodies ++ operation.useSiteCapabilities).map
      (fun slot => .slot block slot [])
    pushes program (capability ++ operands)
  | .returnValue _ | .jump _ | .branch .. | .switchVariant .. | .unpackProduct ..
  | .yieldValue _ | .fail _ | .dispose .. => return []

theorem sourcesAt_exact_subject (program : Program) (witness : Witness) (query : Query) (sources : List Source)
    (found : sourcesAt program witness query = some sources) :
    ∃ normalized row, normalizedQuery program query = some normalized ∧ row ∈ witness.queries ∧
      row.query = normalized ∧ row.sources = sources := by
  unfold sourcesAt at found
  cases normalized : normalizedQuery program query with
  | none => simp [normalized] at found
  | some exactQuery =>
    cases row : witness.queries.find? (fun row => row.query == exactQuery) with
    | none => simp [normalized, row] at found
    | some selected =>
      have member := List.mem_of_find?_eq_some row
      have key : selected.query = exactQuery := by simpa using List.find?_some row
      have values : selected.sources = sources := by simpa [normalized, row] using found
      exact ⟨exactQuery, selected, rfl, member, key, values⟩

end BoundaryV2.Profile.Target.Borrow
