import BoundaryV2.Images
import BoundaryV2.SourceReader
import BoundaryV2.SourceEncoder

open BoundaryV2.Profile

private def checkRecord (codec : Wire.Codec α) (path : System.FilePath) : IO Unit := do
  let input := (← IO.FS.readBinFile path).data.toList
  let some value := codec.decode input
    | throw <| IO.userError s!"wire.decode: {path}"
  if codec.encode value != input then
    throw <| IO.userError s!"wire.reencode: {path}"

/-- Operational cross-check of actual production bytes. This is not the program
or execution certification command and makes no semantic-admission claim. -/
def main (args : List String) : IO UInt32 := do
  let family :: files := args | throw <| IO.userError "usage: wire_conformance.lean <source|bpi|pst|pki|pko|erq|ers> <files...>"
  if files.isEmpty then throw <| IO.userError "wire.empty_input_inventory"
  if family == "source-normalize" then
    let [file] := files | throw <| IO.userError "source-normalize requires one input file"
    let some source := SourceReader.decode (← IO.FS.readBinFile file).data.toList
      | throw <| IO.userError s!"source.decode: {file}"
    (← IO.getStdout).write ⟨(SourceEncoder.encode source).toArray⟩
    return 0
  for file in files do
    match family with
    | "source" =>
      let input := (← IO.FS.readBinFile file).data.toList
      let some source := SourceReader.decode input
        | throw <| IO.userError s!"source.decode: {file}"
      if SourceEncoder.encode source != input then throw <| IO.userError s!"source.reencode: {file}"
    | "bpi" =>
      let input := (← IO.FS.readBinFile file).data.toList
      let some program := Images.decodeImage input
        | throw <| IO.userError s!"bpi.decode: {file}"
      if Images.encodeImage program != input then throw <| IO.userError s!"bpi.reencode: {file}"
    | "pst" => checkRecord Images.rawState file
    | "pki" => checkRecord Images.rawInput file
    | "pko" => checkRecord Images.rawOutcome file
    | "erq" => checkRecord Images.rawRequest file
    | "ers" => checkRecord Images.rawResult file
    | _ => throw <| IO.userError s!"wire.unknown_family: {family}"
  IO.println s!"wire conformance: {files.length} actual {family} records decoded and re-encoded exactly"
  return 0
