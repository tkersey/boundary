import BoundaryV2.SourceReader
import SourceBorrowWitness
import Lean

open Lean BoundaryV2 BoundaryV2.Profile
open BoundaryV2.Profile.Source.Borrow

private def orError (value : Except String α) : IO α :=
  match value with | .ok value => pure value | .error error => throw (IO.userError error)

private def rows (json : Json) : Except String (List Source.Analysis.Row) := do
  (← json.getArr?).toList.mapM fun row => do
    (← row.getArr?).toList.mapM fun entry => do
      let pair ← entry.getArr?
      if pair.size != 2 then throw "bad capture fact row"
      return (⟨← pair[0]!.getNat?⟩, ← pair[1]!.getNat?)

private def checkMutation (source : Source.Module) (facts : Source.Analysis.Facts)
    (witness : Witness) (name : String) : IO Unit := do
  if Source.Borrow.check source facts witness then throw (IO.userError s!"forged source borrow witness accepted: {name}")

private def mutations (source : Source.Module) (facts : Source.Analysis.Facts) (witness : Witness) : IO Nat := do
  let mut count := 0
  for (row, index) in witness.queries.zipIdx do
    if !row.origins.isEmpty then
      checkMutation source facts { witness with queries := witness.queries.set index { row with origins := [] } } "missing origins"
      count := count + 1
    if !row.support.isEmpty then
      checkMutation source facts { witness with queries := witness.queries.set index { row with support := [] } } "missing dependency support"
      count := count + 1
    checkMutation source facts { witness with queries := witness.queries ++ [row] } "duplicate query"
    count := count + 1
  for (row, index) in witness.requirements.zipIdx do
    checkMutation source facts { witness with requirements := witness.requirements.eraseIdx index } "missing function requirements"
    count := count + 1
    if !row.constraints.isEmpty then
      checkMutation source facts { witness with requirements := witness.requirements.set index { row with constraints := [] } } "missing lifetime constraints"
      count := count + 1
  return count

def main (arguments : List String) : IO UInt32 := do
  let [input] := arguments | throw (IO.userError "expected source borrow conformance input")
  let json ← orError (Json.parse (← IO.FS.readFile input))
  let mut accepted : List (String × Witness) := []
  let mut invalid := 0
  let mut checkedMutations := 0
  for group in (← orError json.getArr?).toList do
    let name ← orError ((← orError (group.getObjVal? "name")).getStr?)
    let path ← orError ((← orError (group.getObjVal? "path")).getStr?)
    let expected ← orError ((← orError (group.getObjVal? "expectedBorrow")).getBool?)
    let some source := SourceReader.decode (← IO.FS.readBinFile path).toList | throw (IO.userError "source reader rejected")
    let facts ← orError (group.getObjVal? "facts")
    let facts : Source.Analysis.Facts := {
      values := ← orError (rows (← orError (facts.getObjVal? "values")))
      terms := ← orError (rows (← orError (facts.getObjVal? "terms")))
      functions := ← orError (rows (← orError (facts.getObjVal? "functions"))) }
    if expected then
      let witness ← BoundaryV2.Tooling.SourceBorrowWitness.build source facts
      if !Source.Borrow.check source facts witness then throw (IO.userError s!"{name}: ordinary source checker rejected")
      checkedMutations := checkedMutations + (← mutations source facts witness)
      accepted := accepted ++ [(name, witness)]
    else
      let result ← try
        let _ ← BoundaryV2.Tooling.SourceBorrowWitness.build source facts
        pure (none : Option String)
      catch error => pure (some error.toString)
      let some reason := result | throw (IO.userError s!"{name}: unsafe younger borrow admitted")
      if !reason.startsWith "borrow dependency rejected:" then
        throw (IO.userError s!"{name}: failed outside the expected lifetime constraint: {reason}")
      let partner ← orError ((← orError (group.getObjVal? "borrowPartner")).getStr?)
      let some (_, witness) := accepted.find? (fun entry => entry.1 == partner)
        | throw (IO.userError s!"{name}: missing older-handler counterpart")
      checkMutation source facts witness s!"{name}: older-handler witness rebound to younger source"
      checkedMutations := checkedMutations + 1
      invalid := invalid + 1
  IO.println s!"source borrow admission: {accepted.length} accepted, {invalid} younger-handler rejections, {checkedMutations} altered or incomplete witnesses rejected"
  return 0
