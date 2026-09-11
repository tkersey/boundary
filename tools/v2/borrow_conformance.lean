import BorrowWitness
import BoundaryV2.TargetImage
import Lean

open Lean BoundaryV2 BoundaryV2.Profile
open BoundaryV2.Profile.Target.Borrow

private def verify (path : String) : IO Unit := do
  let json ← match Json.parse (← IO.FS.readFile path) with
    | .ok json => pure json | .error error => throw (IO.userError error)
  let (program, witness) ← BoundaryV2.Tooling.BorrowWitness.read json
  for row in witness.queries do
    if !queryRowValid program witness row then
      throw <| IO.userError s!"borrow query closure rejected: {repr row.query}"
  for row in witness.requirements do
    if !requirementsRowValid program witness row then
      throw <| IO.userError s!"{path}: borrow requirements rejected at block {row.start.value}"
  if !check program witness then throw <| IO.userError "borrow certificate rejected"
  let constants ← program.constants.mapM fun literal =>
    match Profile.Value.decodeAt program.schemas ((literal.bytes.length + 1) * (program.schemas.length + 1))
        literal.schema literal.bytes with
    | some meaning => pure meaning
    | none => throw <| IO.userError "inconclusive: constant value witness search"
  let admission : Target.Admission.Witness := ⟨constants, witness⟩
  if !Target.Admission.check program admission then throw <| IO.userError "combined static admission rejected"
  let image := Images.encodeImage program
  if Target.CertifiedImage.decode image admission != some program then
    throw <| IO.userError "canonical admitted image rejected"
  let some context := Target.Machine.ImageContext.decode image admission
    | throw <| IO.userError "image-backed machine context rejected"
  if context.context.program != program || context.identity != Protocol.programIdentity program then
    throw <| IO.userError "image-backed machine context changed the subject"
  if Target.CertifiedImage.decode (image ++ [0]) admission != none then
    throw <| IO.userError "admitted image ignored trailing bytes"
  let unnumbered := { program with schemas := program.schemas ++ [.unit] }
  if Target.CertifiedImage.decode (Images.encodeImage unnumbered) admission != none then
    throw <| IO.userError "admitted image ignored unreachable catalog entry"
  let firstFunction ← match program.functions.head? with
    | some function => pure function | none => throw <| IO.userError "missing function"
  let absentRequirement := { witness with requirements := witness.requirements.filter (fun row => row.start != firstFunction.entry) }
  if check program absentRequirement then throw <| IO.userError "missing function requirement admitted"
  let mut supportMutations := 0
  let mut subjectMutations := 0
  let mut sourceMutations := 0
  let mut constraintMutations := 0
  for (row, index) in witness.queries.zipIdx do
    if !row.support.isEmpty && supportMutations == 0 then
      let changed := { witness with queries := witness.queries.set index { row with support := [] } }
      if check program changed then throw <| IO.userError "missing trace support admitted"
      supportMutations := supportMutations + 1
    if subjectMutations == 0 then
      let changedRow := { row with query := { row.query with start := ⟨program.blocks.length⟩ } }
      let changed := { witness with queries := witness.queries.set index changedRow }
      if check program changed then throw <| IO.userError "changed query subject admitted"
      subjectMutations := subjectMutations + 1
    if !row.sources.isEmpty && sourceMutations == 0 then
      let changed := { witness with queries := witness.queries.set index { row with sources := [] } }
      if check program changed then throw <| IO.userError "missing source dependencies admitted"
      sourceMutations := sourceMutations + 1
  for (row, index) in witness.requirements.zipIdx do
    if !row.constraints.isEmpty && constraintMutations == 0 then
      let changed := { witness with requirements := witness.requirements.set index { row with constraints := [] } }
      if check program changed then throw <| IO.userError "missing ownership constraints admitted"
      constraintMutations := constraintMutations + 1
  IO.println s!"borrow\t{witness.queries.length}\t{witness.requirements.length}\t{(witness.queries.map (fun row => row.support.length)).sum}\t{supportMutations}\t{subjectMutations}\t{sourceMutations}\t{constraintMutations}"

def main (args : List String) : IO UInt32 := do
  if args.isEmpty then throw <| IO.userError "expected native witness files"
  for path in args do verify path
  return 0
