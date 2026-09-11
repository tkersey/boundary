import BoundaryV2.SourceBorrowRequirements
import Lean

open BoundaryV2 BoundaryV2.Profile
open BoundaryV2.Profile.Source.Borrow

namespace BoundaryV2.Tooling.SourceBorrowWitness

private def appendNew [DecidableEq α] (left right : List α) : List α :=
  right.foldl (fun result entry => if result.contains entry then result else result ++ [entry]) left

private def evaluate (label : String) (action : Evaluation α) : IO (α × List Request) :=
  match action.run [] with
  | .ok result => pure result
  | .error _ => throw (IO.userError s!"borrow dependency rejected: {label}")

private def addRequests (candidate : Witness) (requests : List Request) : Witness :=
  requests.foldl (fun candidate request => match request with
    | .query query =>
      if requestPresent candidate request then candidate else
        { candidate with queries := candidate.queries ++ [⟨query, [], []⟩] }
    | .requirements function =>
      if requestPresent candidate request then candidate else
        { candidate with requirements := candidate.requirements ++ [⟨function, []⟩] }) candidate

private def expandQuery (context : Context) (candidate : Witness) (row : QueryRow) : IO (QueryRow × List Request) := do
  let (seeds, requested) ← evaluate s!"seeds {repr row.query}" (querySeeds context candidate row.query.kind)
  let mut support := appendNew row.support seeds
  let mut origins := row.origins
  let mut requests := requested
  let mut cursor := 0
  while cursor < support.length do
    if support.length > 100000 then throw (IO.userError "inconclusive: source borrow trace search limit")
    let some trace := support[cursor]? | throw (IO.userError "trace cursor invariant")
    let (expansion, requested) ← evaluate s!"trace {repr row.query} / {repr trace}" (traceStep context candidate trace)
    support := appendNew support expansion.traces
    origins := appendNew origins expansion.origins
    requests := appendNew requests requested
    cursor := cursor + 1
  return ({ row with origins := origins, support := support }, requests)

/-- Untrusted finite candidate search. Only the ordinary source checker can
accept the result; a search limit or unsupported dependency is inconclusive. -/
def build (source : Source.Module) (facts : Source.Analysis.Facts) : IO Witness := do
  if !Source.Analysis.check source facts then throw (IO.userError "invalid source capture evidence")
  let graph ← match Source.Borrow.build source facts with
    | .ok graph => pure graph
    | .error _ => throw (IO.userError "source dependency graph rejected")
  let mut candidate : Witness := ⟨[], (List.range source.functions.length).map (fun index => ⟨⟨index⟩, []⟩)⟩
  for iteration in [:10000] do
    if candidate.queries.length > 100000 then throw (IO.userError "inconclusive: source borrow query search limit")
    let previous := candidate
    let mut requests := []
    let mut queries := []
    for row in candidate.queries do
      let (row, requested) ← expandQuery ⟨source, graph, row.query.function⟩ candidate row
      queries := queries ++ [row]
      requests := appendNew requests requested
    let mut requirements := []
    for row in candidate.requirements do
      let (constraints, requested) ← evaluate s!"requirements {row.function.value}, iteration {iteration}"
        (requirementsStep ⟨source, graph, row.function⟩ candidate)
      requirements := requirements ++ [{ row with constraints := appendNew row.constraints constraints }]
      requests := appendNew requests requested
    for index in [:source.functions.length] do
      let (accepted, requested) ← evaluate s!"scoped results {index}" (scopedResults ⟨source, graph, ⟨index⟩⟩ candidate)
      if !accepted then throw (IO.userError s!"borrow scoped result rejected in function {index}")
      requests := appendNew requests requested
    candidate := addRequests ⟨queries, requirements⟩ requests
    if candidate == previous then
      if !checkGraph source graph candidate || !Source.Borrow.check source facts candidate then
        throw (IO.userError "inconclusive: source borrow candidate is not closed")
      return candidate
  throw (IO.userError "inconclusive: source borrow summary search limit")

end BoundaryV2.Tooling.SourceBorrowWitness
