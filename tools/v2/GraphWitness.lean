import BorrowWitness
import BoundaryV2.GraphAdmission
import Lean

open Lean BoundaryV2 BoundaryV2.Profile
open BoundaryV2.Profile.Graph.Admission

namespace BoundaryV2.Tooling.GraphWitness

private def object (name : String) (value : Json) : Json := Json.mkObj [(name, value)]
private def ambient : Option Target.Borrow.Ambient → Json
  | none => Json.null | some .evidence => toJson "evidence" | some .region => toJson "region"

private def stepJson : Target.Borrow.Projection → Json
  | .field index => object "field" (toJson index)
  | .element => object "element" (Json.mkObj [])
  | .environment constructor field => object "environment" (Json.mkObj [("constructor", toJson constructor.value), ("field", toJson field)])
  | .handlerState handler field => object "handler_state" (Json.mkObj [("handler", toJson handler.value), ("field", toJson field)])
  | .useSite index schema => object "use_site" (Json.mkObj [("index", toJson index), ("schema", toJson schema.value)])
  | .cellContent => object "cell_content" (Json.mkObj [])
  | .packageToken => object "package_token" (Json.mkObj [])
  | .outer component => object "outer" (ambient component)
  | .resumed component => object "resumed" (ambient component)
  | .bodyResult schema => object "body_result" (toJson schema.value)

private def queryJson (query : Target.Borrow.Query) : IO Json := do
  let .returned path := query.kind | throw (IO.userError "expected returned-value query")
  pure (Json.mkObj [("start", toJson query.start.value), ("path", toJson (path.map stepJson))])

/-- This native process produces candidate data only. Its complete program
subject, all summary rows and transitive supports are rechecked independently. -/
def refresh (probe stem : String) (program : Target.Program) (requested : List Target.Borrow.Query) :
    IO Target.Borrow.Witness := do
  let raw := stem ++ ".graph.program"
  let queries := stem ++ ".graph.queries.json"
  let report := stem ++ ".graph.borrow.json"
  IO.FS.writeBinFile raw (Codecs.rawProgram.encode program).toByteArray
  IO.FS.writeFile queries (toJson (← requested.mapM queryJson)).compress
  let result ← IO.Process.output { cmd := probe, args := #["graph-borrow", raw, queries] }
  if result.exitCode != 0 || !result.stderr.isEmpty then
    throw (IO.userError s!"native borrow witness generation failed: {result.stderr}")
  IO.FS.writeFile report result.stdout
  let json ← match Json.parse result.stdout with
    | .ok json => pure json | .error error => throw (IO.userError error)
  let (actual, witness) ← BorrowWitness.read json
  if actual != program then throw (IO.userError "native borrow witness changed its complete program subject")
  if !Target.Borrow.check program witness then throw (IO.userError "extended borrow summary rejected")
  pure witness

private def neededQuery (program : Target.Program) (state : Graph.State) (borrows : Target.Borrow.Witness)
    (task : ProjectionTask) : Option Target.Borrow.Query := do
  let .delivered frame path := task | none
  let child ← frameChild state frame
  let record ← node state child
  let some start ← returnedStart program state record | none
  let query ← Target.Borrow.normalizedQuery program ⟨start, .returned path⟩
  if (Target.Borrow.sourcesAt program borrows query).isNone then some query else none

def row (program : Target.Program) (state : Graph.State) (borrows : Target.Borrow.Witness)
    (root : ProjectionTask) : IO (Except Target.Borrow.Query ProjectionRow) := do
  let mut support := [root]
  let mut outputs := []
  let mut cursor := 0
  while cursor < support.length do
    if support.length > 100000 then throw (IO.userError "inconclusive: graph projection witness search limit")
    let some task := support[cursor]? | throw (IO.userError "projection cursor invariant")
    if let some query := neededQuery program state borrows task then return .error query
    let some expansion := projectionStep program state borrows task
      | throw (IO.userError s!"graph projection rejected: {repr task}")
    for next in expansion.next do
      if !support.contains next then support := support ++ [next]
    for output in expansion.outputs do
      if !outputs.contains output then outputs := outputs ++ [output]
    cursor := cursor + 1
  let result : ProjectionRow := ⟨root, support, outputs⟩
  if !projectionRowValid program state borrows result then throw (IO.userError "generated graph projection row rejected")
  pure (.ok result)

def rows (program : Target.Program) (state : Graph.State) (borrows : Target.Borrow.Witness) :
    IO (Except Target.Borrow.Query (List ProjectionRow)) := do
  let some obligations := futureObligations program state borrows
    | throw (IO.userError "future-use obligation derivation rejected")
  let roots := (obligations.flatMap fun obligation => match obligation with
    | .constraint owner value _ => [owner, value] | .outside value _ => [value]).eraseDups
  let mut result := []
  for root in roots do
    match ← row program state borrows root with
    | .error query => return .error query
    | .ok row => result := result ++ [row]
  pure (.ok result)

end BoundaryV2.Tooling.GraphWitness
