import BoundaryV2.ProgramCanonical
import BoundaryV2.BorrowRequirements
import BoundaryV2.UseAdmission
import BoundaryV2.Images

namespace BoundaryV2.Profile.Target.Admission

structure Witness where
  constants : List (Profile.Value .target)
  borrows : Borrow.Witness

/-- All declaration checks precede any possible pruning. Borrow tables contain
finite data and are verified against this same program, including trace closure
and inherited requirements. They carry neither execution results nor axioms. -/
def check (program : Program) (witness : Witness) : Bool :=
  declarationsValid program witness.constants &&
  program.blocks.all (blockInstructionsValid program) && regionsValid program &&
  (let facts := effectFacts program
   program.blocks.all (fun block => terminatorValid program facts block && blockUsesValid program facts block)) &&
  Borrow.check program witness.borrows

/-- Static admission is not historical reachability or machine preservation.
Those statements additionally need the operational state invariants. -/
def Admitted (program : Program) (witness : Witness) : Prop :=
  declarationsValid program witness.constants = true ∧
  (∀ block ∈ program.blocks, blockInstructionsValid program block = true) ∧
  regionsValid program = true ∧
  (∀ block ∈ program.blocks, terminatorValid program (effectFacts program) block = true ∧
    blockUsesValid program (effectFacts program) block = true) ∧
  Borrow.check program witness.borrows = true

theorem check_exact (program : Program) (witness : Witness) :
    check program witness = true ↔ Admitted program witness := by
  simp only [check, Admitted, Bool.and_eq_true, List.all_eq_true, and_assoc]

theorem admitted_constants_exact (program : Program) (witness : Witness)
    (accepted : Admitted program witness) :
    ∀ (index : Nat) (literal : Literal .target) (meaning : Profile.Value .target),
      program.constants[index]? = some literal → witness.constants[index]? = some meaning →
      meaning.schema = literal.schema ∧ Profile.Value.externalValid program.schemas meaning = true ∧
        Profile.Value.encode program.schemas meaning = literal.bytes := by
  have declarations := accepted.1
  simp only [declarationsValid, Bool.and_eq_true] at declarations
  exact (constants_exact program witness.constants declarations.1.1.1.1.1.1.1.2).2

end BoundaryV2.Profile.Target.Admission

namespace BoundaryV2.Profile.Images

theorem decodeImage_capacity (input : Bytes) (program : Target.Program)
    (accepted : decodeImage input = some program) : (encodeBody program).length < wordLimit := by
  unfold decodeImage at accepted
  cases header : (frameBytes .bpi).decode input with
  | none => simp [header] at accepted
  | some body =>
    have bodyRead : decodeBody body = some program := by simpa [header] using accepted
    have exactBody := (decodeBody_sound body program bodyRead).2
    have capacity := ((frameBytes .bpi).decode_exact input body header).1
    simpa only [frameBytes_valid, decide_eq_true_eq, ← exactBody] using capacity

end BoundaryV2.Profile.Images

namespace BoundaryV2.Profile.Target.CertifiedImage

/-- Complete static admission and canonical numbering of this decoded program,
with the wire bounds needed for an exact BPI2 encoder round trip. This is not a
source-to-target translation certificate. -/
def CanonicalProgram (program : Program) (witness : Admission.Witness) : Prop :=
  Images.WireAdmitted program ∧ (Images.encodeBody program).length < wordLimit ∧
  Admission.Admitted program witness ∧ Canonical.Numbered program

def decode (input : Bytes) (witness : Admission.Witness) : Option Program := do
  let program ← Images.decodeImage input
  if Admission.check program witness && Canonical.check program then some program else none

theorem decode_bpi2_sound (input : Bytes) (witness : Admission.Witness) (program : Program)
    (accepted : decode input witness = some program) :
    CanonicalProgram program witness ∧ Images.encodeImage program = input := by
  unfold decode at accepted
  cases parsed : Images.decodeImage input with
  | none => simp [parsed] at accepted
  | some original =>
    simp [parsed, Bool.and_eq_true] at accepted
    obtain ⟨checked, rfl⟩ := accepted
    have exactBytes := Images.decodeImage_sound input original parsed
    exact ⟨⟨exactBytes.1, Images.decodeImage_capacity input original parsed,
      (Admission.check_exact original witness).mp checked.1,
      (Canonical.check_exact original).mp checked.2⟩, exactBytes.2⟩

theorem canonical_encode_decode (program : Program) (witness : Admission.Witness)
    (accepted : CanonicalProgram program witness) :
    decode (Images.encodeImage program) witness = some program := by
  have parsed := Images.decodeImage_complete program accepted.1 accepted.2.1
  have admitted := (Admission.check_exact program witness).mpr accepted.2.2.1
  have numbered := (Canonical.check_exact program).mpr accepted.2.2.2
  simp [decode, parsed, admitted, numbered]

theorem accepted_bytes_reencode_exactly (input : Bytes) (witness : Admission.Witness) (program : Program)
    (accepted : decode input witness = some program) : Images.encodeImage program = input :=
  (decode_bpi2_sound input witness program accepted).2

theorem decode_complete_for_witness (input : Bytes) (witness : Admission.Witness) (program : Program)
    (canonical : CanonicalProgram program witness) (exactBytes : Images.encodeImage program = input) :
    decode input witness = some program := by
  rw [← exactBytes]
  exact canonical_encode_decode program witness canonical

end BoundaryV2.Profile.Target.CertifiedImage
