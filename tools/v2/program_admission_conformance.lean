import BoundaryV2.Images
import BoundaryV2.UseAdmission

open BoundaryV2 BoundaryV2.Profile
open BoundaryV2.Profile.Target

private def constants (program : Program) : IO (List (Profile.Value .target)) :=
  program.constants.mapM fun literal =>
    match Profile.Value.decodeAt program.schemas ((literal.bytes.length + 1) * (program.schemas.length + 1))
        literal.schema literal.bytes with
    | some value => pure value
    | none => throw <| IO.userError "constant witness search was inconclusive"

/-- This is the currently implemented static subset. Borrow closure is checked
separately; this test does not publish a full-program certificate. -/
private def admitted (program : Program) (constants : List (Profile.Value .target)) : Bool :=
  Admission.declarationsValid program constants && program.blocks.all (Admission.blockInstructionsValid program) &&
  Admission.regionsValid program &&
  (let facts := Admission.effectFacts program
   program.blocks.all (fun block => Admission.terminatorValid program facts block && Admission.blockUsesValid program facts block))

private def emit (directory : System.FilePath) (name : String) (program : Program) (valid : Bool) : IO Unit := do
  if !Codecs.rawProgram.valid program then throw <| IO.userError s!"invalid raw fixture {name}"
  let raw := Codecs.rawProgram.encode program
  if Codecs.rawProgram.toCodec.decode raw != some program then throw <| IO.userError s!"raw roundtrip {name}"
  IO.FS.writeBinFile (directory / s!"{name}.program") raw.toByteArray
  IO.println s!"case\t{name}\t{if valid then "ok" else "reject"}"

def main (args : List String) : IO UInt32 := do
  let directory :: paths := args | throw <| IO.userError "expected output directory and image paths"
  if paths.isEmpty then throw <| IO.userError "empty program inventory"
  let directory : System.FilePath := directory
  let mut seen : List Opcode := []
  let mut terms : List Codecs.TerminatorTag := []
  for (path, index) in paths.zipIdx do
    let some program := Images.decodeImage (← IO.FS.readBinFile path).toList
      | throw <| IO.userError s!"invalid image {path}"
    let values ← constants program
    if !admitted program values then throw <| IO.userError s!"static admission rejected {path}"
    emit directory s!"base-{index}" program true
    let badRoot := { program with roots := { program.roots with entry := ⟨program.functions.length⟩ } }
    if admitted badRoot values then throw <| IO.userError "out-of-bounds entry admitted"
    emit directory s!"entry-{index}" badRoot false
    for (block, blockIndex) in program.blocks.zipIdx do
      let tag := (Codecs.terminatorView block.terminator).1
      if !terms.contains tag then
        terms := tag :: terms
        IO.println s!"terminator\t{Codecs.terminatorTagName tag}"
      for (instruction, instructionIndex) in block.instructions.zipIdx do
        if !seen.contains instruction.opcode then
          seen := instruction.opcode :: seen
          let name := Codecs.opcodeName instruction.opcode
          IO.println s!"opcode\t{name}"
          for (suffix, changed) in [
              ("operand", { instruction with operands := instruction.operands ++ [⟨block.parameters.length + instructionIndex⟩] }),
              ("immediate", { instruction with immediate := wordLimit - 1 })] do
            let changedBlock := { block with instructions := block.instructions.set instructionIndex changed }
            let mutated := { program with blocks := program.blocks.set blockIndex changedBlock }
            if admitted mutated values then throw <| IO.userError s!"ineffective {name}-{suffix} mutation"
            emit directory s!"{name}-{suffix}" mutated false
  return 0
