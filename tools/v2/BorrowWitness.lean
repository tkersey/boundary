import BoundaryV2.ProgramAdmission
import Lean

open Lean BoundaryV2 BoundaryV2.Profile
open BoundaryV2.Profile.Target.Borrow

namespace BoundaryV2.Tooling.BorrowWitness

private def field (json : Json) (name : String) : Except String Json := json.getObjVal? name
private def number (json : Json) (name : String) : Except String Nat := do (← field json name).getNat?
private def array (json : Json) (name : String) : Except String (List Json) := do return (← (← field json name).getArr?).toList
private def readOptional (read : Json → Except String α) (json : Json) : Except String (Option α) :=
  if json == Json.null then .ok none else some <$> read json

private def ambient (json : Json) : Except String Ambient := do
  match ← json.getStr? with
  | "evidence" => pure .evidence
  | "region" => pure .region
  | _ => throw "unknown ancestry component"

private def tagged (json : Json) : Except String (String × Json) := do
  let object ← json.getObj?
  let [(name, value)] := object.toList | throw "expected one union tag"
  return (name, value)

private def projection (json : Json) : Except String Projection := do
  let (tag, value) ← tagged json
  match tag with
  | "field" => return .field (← value.getNat?)
  | "element" => return .element
  | "environment" => return .environment ⟨← number value "constructor"⟩ (← number value "field")
  | "handler_state" => return .handlerState ⟨← number value "handler"⟩ (← number value "field")
  | "use_site" => return .useSite (← number value "index") ⟨← number value "schema"⟩
  | "cell_content" => return .cellContent
  | "package_token" => return .packageToken
  | "outer" => return .outer (← readOptional ambient value)
  | "resumed" => return .resumed (← readOptional ambient value)
  | "body_result" => return .bodyResult ⟨← value.getNat?⟩
  | _ => throw s!"unknown projection {tag}"

private def pathAt (paths : List Path) (index : Nat) : Except String Path :=
  if index == 0 then .ok [] else match paths[index - 1]? with
    | some path => .ok path
    | none => .error s!"invalid path reference {index}"

private def readPaths (json : List Json) : Except String (List Path) :=
  json.foldlM (fun paths item => do
    let tail ← pathAt paths (← number item "tail")
    let step ← projection (← field item "step")
    return paths ++ [step :: tail]) []

private def source (paths : List Path) (json : Json) : Except String Source := do
  let parameter ← number json "parameter"
  let path ← number json "path"
  match ← readOptional ambient (← field json "ambient") with
  | some component =>
    if parameter != 0 || path != 0 then throw "ambiguous ambient source"
    return .ambient component
  | none => return .parameter parameter (← pathAt paths path)

private def readTrace (paths : List Path) (json : Json) : Except String Trace := do
  let block : BlockId := ⟨← number json "block"⟩
  let slot ← number json "slot"
  let path ← number json "path"
  let body ← (← field json "body_result").getBool?
  match ← readOptional ambient (← field json "ambient") with
  | some component =>
    if body || slot != 0 || path != 0 then throw "ambiguous ambient trace"
    return .ambient block component
  | none =>
    if body then
      if slot != 0 then throw "ambiguous body-result trace"
      return .bodyResult block (← pathAt paths path)
    return .slot block ⟨slot⟩ (← pathAt paths path)

private def queryRow (paths : List Path) (json : Json) : Except String QueryRow := do
  let start : BlockId := ⟨← number json "start"⟩
  let path ← number json "path"
  let target ← readOptional (readTrace paths) (← field json "target")
  let writes ← readOptional Json.getNat? (← field json "writes")
  let kind : QueryKind ← match target, writes with
    | some target, none =>
      if path != 0 then throw "ambiguous origin query"
      pure (QueryKind.origin target)
    | none, some schema => do pure (QueryKind.writes ⟨schema⟩ (← pathAt paths path))
    | none, none => do pure (QueryKind.returned (← pathAt paths path))
    | some _, some _ => throw "ambiguous query kind"
  return ⟨⟨start, kind⟩, ← (← array json "sources").mapM (source paths), []⟩

private def constraint (paths : List Path) (json : Json) : Except String Constraint := do
  let bound ← match ← (← field json "bound").getStr? with
    | "region" => pure Bound.region
    | "clause" => pure Bound.clause
    | "capture" => pure Bound.capture
    | _ => throw "unknown ownership bound"
  return ⟨← source paths (← field json "value"), ← source paths (← field json "owner"), bound⟩

private def requirementsRow (paths : List Path) (json : Json) : Except String RequirementsRow := do
  return ⟨⟨← number json "start"⟩, ← (← array json "constraints").mapM (constraint paths)⟩

private def bytes (json : Json) : Except String Bytes := do
  (← json.getArr?).toList.mapM fun item => do
    let number ← item.getNat?
    if number < 256 then return UInt8.ofNat number else throw "invalid byte"

private def orError (result : Except String α) : IO α :=
  match result with | .ok value => pure value | .error reason => throw (IO.userError reason)

private def completeSupport (program : Target.Program) (witness : Witness) (row : QueryRow) : IO QueryRow := do
  let some seeds := querySeeds program witness row.query
    | throw <| IO.userError s!"query seed dependency missing: {repr row.query}"
  let live := reachable program row.query.start
  let mut pending := seeds.eraseDups
  let mut index := 0
  while index < pending.length do
    if pending.length > 100000 then throw <| IO.userError "inconclusive: trace witness search limit"
    let some currentTrace := pending[index]? | throw <| IO.userError "support cursor invariant"
    let some expanded := traceStep program witness row.query.start live currentTrace
      | throw <| IO.userError s!"trace dependency missing: {repr row.query}, {repr currentTrace}"
    for next in expanded.traces do
      if !pending.contains next then pending := pending ++ [next]
    index := index + 1
  return { row with support := pending }

def read (json : Json) : IO (Target.Program × Witness) := do
  let raw ← orError (bytes (← orError (field json "program_bytes")))
  let some program := Codecs.rawProgram.toCodec.decode raw | throw <| IO.userError "invalid exact program subject"
  let paths ← orError (readPaths (← orError (array json "paths")))
  let queries ← orError ((← orError (array json "queries")).mapM (queryRow paths))
  let requirements ← orError ((← orError (array json "requirements")).mapM (requirementsRow paths))
  let candidate : Witness := ⟨queries, requirements⟩
  let queries ← queries.mapM (completeSupport program candidate)
  let witness := { candidate with queries := queries }
  return (program, witness)

end BoundaryV2.Tooling.BorrowWitness
