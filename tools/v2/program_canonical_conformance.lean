import BoundaryV2.ProgramRemap
import BoundaryV2.Images

open BoundaryV2 BoundaryV2.Profile BoundaryV2.Profile.Target
open BoundaryV2.Profile.Target.Canonical

private def kindName : Kind → String
  | .schema => "schema" | .constant => "constant" | .effect => "effect" | .function => "function"
  | .block => "block" | .handler => "handler" | .capture => "capture" | .region => "region"
  | .resource => "resource" | .constructor => "constructor"

private def emit (directory : System.FilePath) (name : String) (program : Program) (accepted : Bool) : IO Unit := do
  if check program != accepted then throw <| IO.userError s!"canonical numbering disagrees: {name}"
  let some normalized := normalizeRecords program | throw <| IO.userError s!"normalization rejected: {name}"
  if !check normalized then throw <| IO.userError s!"normalization produced noncanonical result: {name}"
  if normalizeRecords normalized != some normalized then throw <| IO.userError s!"normalization not idempotent: {name}"
  IO.FS.writeBinFile (directory / s!"{name}.program") (Codecs.rawProgram.encode program).toByteArray
  IO.FS.writeBinFile (directory / s!"{name}.bpi2") (Images.encodeImage program).toByteArray
  IO.FS.writeBinFile (directory / s!"{name}.normalized") (Codecs.rawProgram.encode normalized).toByteArray
  IO.println s!"canonical\t{name}\t{if accepted then "ok" else "reject"}"

/-- Shift a nonempty catalog by one, retaining a now-unreachable duplicate at
zero. Every embedded catalog reference moves with it. This covers singleton
catalogs as well as catalogs where a nontrivial permutation is available. -/
private def shifted (program : Program) (kind : Kind) : Option Program := do
  let result ← materialize program (fun current => if current == kind then 0 :: List.range (count program current)
    else List.range (count program current))
    (fun current index => if current == kind then index + 1 else index)
  if kind != .function then return result
  -- A function's entry block names that same function. An unreachable padding
  -- function therefore needs its own valid entry, not an alias of function 1.
  let unit : SchemaId .target := ⟨result.schemas.length⟩
  return { result with
    schemas := result.schemas ++ [.unit]
    functions := result.functions.set 0 ⟨⟨result.blocks.length⟩, [unit], unit, [], []⟩
    blocks := result.blocks ++ [⟨0, [unit], [], .returnValue 0⟩] }

private def swap (index : Nat) : Nat := if index == 0 then 1 else if index == 1 then 0 else index

private def permuted (program : Program) (kind : Kind) : Option Program :=
  materialize program (fun current => (List.range (count program current)).map
    (fun index => if current == kind then swap index else index))
    (fun current index => if current == kind then swap index else index)

def main (args : List String) : IO UInt32 := do
  let directory :: paths := args | throw <| IO.userError "expected output directory and image paths"
  if paths.isEmpty then throw <| IO.userError "empty program inventory"
  let directory : System.FilePath := directory
  let mut shiftedKinds : List Kind := []
  let mut permutedKinds : List Kind := []
  let mut duplicates := 0
  let mut nominalTies := 0
  for (path, index) in paths.zipIdx do
    let some program := Images.decodeImage (← IO.FS.readBinFile path).toList
      | throw <| IO.userError s!"invalid image {path}"
    emit directory s!"canonical-base-{index}" program true
    emit directory s!"canonical-unreachable-{index}" { program with schemas := program.schemas ++ [.unit] } false
    for kind in kinds do
      if count program kind > 0 && !shiftedKinds.contains kind then
        let some shifted := shifted program kind | throw <| IO.userError "shift materialization rejected"
        emit directory s!"canonical-shift-{kindName kind}" shifted false
        shiftedKinds := shiftedKinds ++ [kind]
      if count program kind > 1 && !permutedKinds.contains kind then
        let some permuted := permuted program kind | throw <| IO.userError "permutation materialization rejected"
        emit directory s!"canonical-permute-{kindName kind}" permuted false
        permutedKinds := permutedKinds ++ [kind]
    if let some literal := program.constants.head? then
      let duplicate := { program with
        constants := program.constants ++ [literal]
        blocks := program.blocks.map fun block => { block with instructions := block.instructions.map fun instruction =>
          if instruction.opcode == .constant && instruction.immediate == 0 then
            { instruction with immediate := program.constants.length }
          else instruction } }
      emit directory s!"canonical-duplicate-{index}" duplicate false
      duplicates := duplicates + 1
    if nominalTies == 0 && program.effects.length > 1 then
      let some first := program.effects[0]? | throw <| IO.userError "missing first effect"
      let some second := program.effects[1]? | throw <| IO.userError "missing second effect"
      let tied := { program with effects := program.effects.set 1 { second with identity := first.identity } }
      let some normalized := normalizeRecords tied | throw <| IO.userError "nominal tie normalization rejected"
      if normalized.effects.length != program.effects.length then throw <| IO.userError "equal-name nominal declarations collapsed"
      emit directory "canonical-nominal-tie" normalized true
      nominalTies := nominalTies + 1
  for kind in shiftedKinds do IO.println s!"shift\t{kindName kind}"
  for kind in permutedKinds do IO.println s!"permutation\t{kindName kind}"
  IO.println s!"interning\t{duplicates}\t{nominalTies}"
  return 0
