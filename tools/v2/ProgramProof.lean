import ExecutionProof
import BoundaryV2.BorrowEvaluation
import BoundaryV2.BorrowReachability
import BoundaryV2.CanonicalEvaluation

open Lean BoundaryV2 BoundaryV2.Profile BoundaryV2.Profile.Target
open BoundaryV2.Tooling.InvocationWitness BoundaryV2.Tooling.ExecutionProof

namespace BoundaryV2.Tooling.ProgramProof

/-- Generated files carry ordinary declarations. Their dependency inventory is
returned to the driver so every file is compiled, audited and replayed. -/
structure Artifact where
  module : String
  path : System.FilePath

structure Package where
  module : String
  artifacts : List Artifact

private def header (imports : List String) (scope : String) : String :=
  String.intercalate "\n" (imports.map (fun name => "import " ++ name)) ++
    s!"\nset_option Elab.async false\nset_option cbv.warning false\nset_option cbv.maxSteps 5000000\nset_option maxRecDepth 65536\nset_option maxHeartbeats 0\nnamespace {scope}\nopen BoundaryV2 BoundaryV2.Profile BoundaryV2.Profile.Target\n"

private def writeModule (output : System.FilePath) (name scope : String) (imports : List String)
    (body : String) : IO Artifact := do
  let path := output / (name ++ ".lean")
  IO.FS.writeFile path (header imports scope ++ body ++ s!"\nend {scope}\n")
  return ⟨name, path⟩

private def allProof (names : List String) : String :=
  names.foldr (fun name tail => s!"Borrow.all_cons_checked _ _ _ {name} ({tail})") "rfl"

private def names (stem : String) (count : Nat) : List String :=
  (List.range count).map (fun index => s!"{stem}{index}")

private def checkedNames (stem : String) (count : Nat) : List String :=
  (names stem count).map (· ++ "Checked")

private def chunks (size : Nat) (items : List α) : List (List α) :=
  (List.range ((items.length + size - 1) / size)).map (fun index => (items.drop (index * size)).take size)

private def appendFacts (output : System.FilePath) (scope stem : String) (previous : Artifact)
    (commands : List String) : IO (List Artifact) := do
  let mut result := []
  let mut parent := previous.module
  for (chunk, index) in chunks 64 commands |>.zipIdx do
    let item ← writeModule output s!"{scope}{stem}{index}" scope [parent] (String.intercalate "\n" chunk)
    result := result ++ [item]
    parent := item.module
  return result

private def emitBorrow (output : System.FilePath) (scope : String) (data : Artifact)
    (program : Program) (witness : Borrow.Witness) : IO (List Artifact) := do
  let mut artifacts := [data]
  let mut queryCommands := []
  for (row, index) in witness.queries.zipIdx do
    -- Nested opcode/path matches can defeat Lean's equation-lemma generator.
    -- Kernel decision checks the same closed proposition without those lemmas.
    queryCommands := queryCommands ++ [s!"def query{index} : Borrow.QueryRow := {literal row}\ntheorem query{index}Checked : Borrow.queryRowValid program programWitness.borrows query{index} = true := by first | decide_cbv | decide +kernel"]
  artifacts := artifacts ++ (← appendFacts output scope "Query" (artifacts.getLastD data) queryCommands)
  let uniformEmpty := program.blocks.length > 128 && witness.requirements.all (fun row => row.constraints.isEmpty)
  let mut requirementProof := ""
  if uniformEmpty then
    let commands := (List.range program.blocks.length).map fun index =>
      s!"theorem block{index}Empty (start : BlockId) : Borrow.blockRequirements program programWitness.borrows start ⟨{index}⟩ = some [] := by decide_cbv"
    artifacts := artifacts ++ (← appendFacts output scope "Empty" (artifacts.getLastD data) commands)
    let proof := (List.range program.blocks.length).foldr (fun index tail =>
      s!"Borrow.forall_mem_cons_checked _ _ _ block{index}Empty ({tail})") "(by simp)"
    requirementProof := s!"theorem everyBlockEmpty : ∀ block ∈ Borrow.blockIds program, ∀ start, Borrow.blockRequirements program programWitness.borrows start block = some [] := by\n  have same : Borrow.blockIds program = {literal (Borrow.blockIds program)} := rfl\n  rw [same]\n  exact {proof}\ntheorem allRequirementsChecked : programWitness.borrows.requirements.all (Borrow.requirementsRowValid program programWitness.borrows) = true := Borrow.requirements_all_empty _ _ everyBlockEmpty (by decide_cbv)\n"
  else
    let mut commands := []
    for (row, index) in witness.requirements.zipIdx do
      commands := commands ++ [s!"def requirement{index} : Borrow.RequirementsRow := {literal row}\ntheorem requirement{index}Checked : Borrow.requirementsRowValid program programWitness.borrows requirement{index} = true := by decide_cbv"]
    artifacts := artifacts ++ (← appendFacts output scope "Requirement" (artifacts.getLastD data) commands)
    let rows := String.intercalate "," (names "requirement" witness.requirements.length)
    requirementProof := s!"theorem allRequirementsChecked : programWitness.borrows.requirements.all (Borrow.requirementsRowValid program programWitness.borrows) = true := Borrow.all_of_exact_list _ _ [{rows}] rfl ({allProof (checkedNames "requirement" witness.requirements.length)})\n"
  let mut scopedCommands := []
  for (block, index) in program.blocks.zipIdx do
    scopedCommands := scopedCommands ++ [s!"def scopedRow{index} : Block × Nat := ({literal block}, {index})\ntheorem scoped{index}Checked : (Borrow.scopedBindings program ⟨{index}⟩ scopedRow{index}.1.terminator).any (fun bindings => bindings.all (Borrow.scopedResultValid program programWitness.borrows)) = true := by decide_cbv"]
  artifacts := artifacts ++ (← appendFacts output scope "Scoped" (artifacts.getLastD data) scopedCommands)
  let ids := witness.requirements.map Borrow.RequirementsRow.start
  let mut uniqueCode := s!"def starts{ids.length} : List BlockId := []\ntheorem unique{ids.length} : starts{ids.length}.Nodup := List.nodup_nil\n"
  for index in (List.range ids.length).reverse do
    let some block := ids[index]? | throw (IO.userError "invalid requirement index")
    uniqueCode := uniqueCode ++ s!"def starts{index} : List BlockId := {literal block} :: starts{index+1}\ntheorem notIn{index} : ({literal block} : BlockId) ∉ starts{index+1} := by decide +kernel\ntheorem unique{index} : starts{index}.Nodup := List.nodup_cons.mpr ⟨notIn{index}, unique{index+1}⟩\n"
  uniqueCode := uniqueCode ++ "theorem requirementsUnique : decide (programWitness.borrows.requirements.map Borrow.RequirementsRow.start).Nodup = true := by\n  apply decide_eq_true_iff.mpr\n  have same : programWitness.borrows.requirements.map Borrow.RequirementsRow.start = starts0 := rfl\n  rw [same]\n  exact unique0\n"
  let unique ← writeModule output (scope ++ "Unique") scope [(artifacts.getLastD data).module] uniqueCode
  artifacts := artifacts ++ [unique]
  let queries := String.intercalate "," (names "query" witness.queries.length)
  let scopedRows := String.intercalate "," (names "scopedRow" program.blocks.length)
  let assembly := requirementProof ++ s!"theorem borrowAccepted : Borrow.check program programWitness.borrows = true := by
  apply Borrow.check_of_parts
  · decide +kernel
  · exact requirementsUnique
  · decide_cbv
  · exact Borrow.all_of_exact_list _ _ [{queries}] rfl ({allProof (checkedNames "query" witness.queries.length)})
  · exact allRequirementsChecked
  · exact Borrow.scoped_of_exact_rows _ _ [{scopedRows}] rfl ({allProof (checkedNames "scoped" program.blocks.length)})\n"
  let item ← writeModule output (scope ++ "Borrow") scope [unique.module] assembly
  return artifacts ++ [item]

private def emitCanonical (output : System.FilePath) (scope : String) (data : Artifact)
    (program : Program) : IO (List Artifact) := do
  let mut state := Canonical.EvaluationState.pending (Canonical.catalogReferences program)
    (Canonical.rootReferences program.roots) []
  let mut count := 0
  let mut commands := [s!"def canon0 : Canonical.EvaluationState := {literal state}"]
  while (match state with | .pending .. => true | .finished _ => false) do
    state := Canonical.advanceN program 8 state
    commands := commands ++ [s!"def canon{count+1} : Canonical.EvaluationState := {literal state}\ntheorem canon{count}Checked : Canonical.advanceN program 8 canon{count} = canon{count+1} := by first | decide +kernel | decide_cbv"]
    count := count + 1
  let .finished (some order) := state | throw (IO.userError "canonical traversal rejected")
  let proof := (List.range count).foldr (fun index tail =>
    s!"Canonical.evaluation_of_chunk _ _ _ _ _ canon{index}Checked ({tail})") "rfl"
  commands := commands ++ [s!"def canonicalOrder : List Canonical.Reference := {literal order}\ntheorem canonicalDiscovered : Canonical.discover program = some canonicalOrder := Canonical.discover_of_evaluation _ _ _ (by decide +kernel) ({proof})\ntheorem canonicalChecked : Canonical.check program = true := by\n  simp only [Canonical.check, canonicalDiscovered, Option.any_some]\n  decide +kernel"]
  let mut artifacts := []
  let mut parent := data.module
  for (chunk, index) in chunks 32 commands |>.zipIdx do
    let item ← writeModule output s!"{scope}Canonical{index}" scope [parent] (String.intercalate "\n" chunk)
    artifacts := artifacts ++ [item]
    parent := item.module
  return artifacts

/-- Byte identity chooses a shared file family, while every public claim still
contains the complete bytes. Witness candidates receive no semantic authority. -/
def emit (output : System.FilePath) (scope : String) (entry : ProgramCache)
    (dataCode : String) : IO Package := do
  let data ← writeModule output (scope ++ "Data") scope
    ["BoundaryV2.ExecutionCertificate", "BoundaryV2.SHA256Certificate", "BoundaryV2.BorrowEvaluation",
      "BoundaryV2.BorrowReachability", "BoundaryV2.CanonicalEvaluation", "Lean.Elab.Tactic.Cbv"]
    ("attribute [cbv_opaque] BoundaryV2.Profile.SHA256.hashNumerals BoundaryV2.Profile.SHA256.hash BoundaryV2.Profile.Target.Borrow.reachable\nattribute [cbv_eval] BoundaryV2.Profile.SHA256.hash_as_numerals BoundaryV2.Profile.Target.Borrow.reachable_forward\n" ++ dataCode)
  let borrowed ← emitBorrow output scope data entry.image.context.program entry.witness.borrows
  let canonical ← emitCanonical output scope data entry.image.context.program
  let finalCode := "theorem programAccepted : CertifiedImage.CanonicalProgram program programWitness := by\n  refine ⟨?_, ?_, (Admission.check_exact _ _).mp ?_, (Canonical.check_exact _).mp canonicalChecked⟩\n  · unfold Images.WireAdmitted; decide_cbv\n  · decide_cbv\n  · unfold Admission.check\n    simp only [Bool.and_eq_true, and_assoc]\n    refine ⟨?_, ?_, ?_, ?_, borrowAccepted⟩\n    all_goals decide_cbv\ndef image : Machine.ImageContext imageBytes programWitness := { context := { program := program, constants := storedConstants, inventory := by decide +kernel }, admitted := programAccepted, encoded := by decide_cbv }\n"
  let finalArtifact ← writeModule output scope scope [(borrowed.getLastD data).module, (canonical.getLastD data).module] finalCode
  return ⟨scope, borrowed ++ canonical ++ [finalArtifact]⟩

end BoundaryV2.Tooling.ProgramProof
