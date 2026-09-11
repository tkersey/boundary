import BoundaryV2.SourceReader
import BoundaryV2.SourceAnalysis
import Lean

open BoundaryV2.Profile

private def decodeRows (json : Lean.Json) : Except String (List Source.Analysis.Row) := do
  let rows ← json.getArr?
  rows.toList.mapM fun row => do
    let entries ← row.getArr?
    entries.toList.mapM fun entry => do
      let pair ← entry.getArr?
      if pair.size != 2 then throw "expected variable/rank pair"
      return (⟨← pair[0]!.getNat?⟩, ← pair[1]!.getNat?)

def main (arguments : List String) : IO UInt32 := do
  match arguments with
  | [sourcePath, factsPath] =>
    let sourceBytes ← IO.FS.readBinFile sourcePath
    let some source := SourceReader.decode sourceBytes.toList | throw (IO.userError "source decode rejected")
    if !Source.Analysis.formation source then throw (IO.userError "source formation rejected")
    let text ← IO.FS.readFile factsPath
    let facts := do
      let json ← Lean.Json.parse text
      return { values := ← decodeRows (← json.getObjVal? "values")
               terms := ← decodeRows (← json.getObjVal? "terms")
               functions := ← decodeRows (← json.getObjVal? "functions") : Source.Analysis.Facts }
    let facts ← match facts with
      | .ok facts => pure facts
      | .error error => throw (IO.userError error)
    if !Source.Analysis.check source facts then throw (IO.userError "source capture witness rejected")
    IO.println s!"source analysis: {sourcePath} ({source.functions.length} functions)"
    return 0
  | _ => throw (IO.userError "expected SOURCE FACTS")
