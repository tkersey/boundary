import InvocationWitness
open Lean BoundaryV2 BoundaryV2.Profile BoundaryV2.Profile.Target
open BoundaryV2.Tooling.InvocationWitness

def main (args : List String) : IO UInt32 := do
  let [manifest, output] := args | throw (IO.userError "expected capacity capture manifest and output manifest")
  let captured ← orError (Json.parse (← IO.FS.readFile manifest))
  let normal ← field captured "normalExecution"
  let image ← string normal "image"
  let entry ← loadProgram image
  let mut clock : Boundary.Clock := ⟨0, none⟩
  let mut transitions : List Json := []
  let records ← orError (← field normal "records").getArr?
  unless !records.isEmpty do throw (IO.userError "empty capacity normal execution")
  for record in records do
    let inputPath ← string record "input"
    let outputPath ← string record "output"
    let inputBytes := (← IO.FS.readBinFile inputPath).toList
    let outputBytes := (← IO.FS.readBinFile outputPath).toList
    let (witness, checked) ← deriveInvocation entry ⟨inputBytes, outputBytes⟩ clock
    clock := checked.clock
    transitions := transitions ++ [Json.mkObj [("input", toJson inputPath), ("output", toJson outputPath), ("steps", toJson witness.internalSteps)]]
    IO.eprintln s!"capacity invocation {transitions.length}: {witness.internalSteps} formal steps, full output matched"
  IO.FS.writeFile output (toJson [Json.mkObj [("name", toJson "capacity"), ("image", toJson image), ("transitions", toJson transitions)]]).compress
  return 0
