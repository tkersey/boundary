import BoundaryV2.TargetMachine
import BoundaryV2.ProgramAdmission
import BoundaryV2.ProtocolIdentity

namespace BoundaryV2.Profile.Target.Machine

theorem Store.admitBlobs_complete (schemas : List (Schema .target)) (raws : List Graph.Blob)
    (meanings : List SemanticValue) (length : raws.length = meanings.length)
    (checked : (raws.zip meanings).all (fun (raw, meaning) =>
      Profile.Value.checkExternal schemas raw.schema raw.bytes meaning) = true) :
    ∃ blobs, Store.admitBlobs schemas raws meanings = some blobs := by
  induction raws generalizing meanings with
  | nil =>
    have empty : meanings = [] := by simpa using length.symm
    subst meanings
    exact ⟨[], rfl⟩
  | cons raw raws ih =>
    cases meanings with
    | nil => simp at length
    | cons meaning meanings =>
      simp only [List.length_cons, Nat.add_right_cancel_iff] at length
      simp only [List.zip_cons_cons, List.all_cons, Bool.and_eq_true] at checked
      obtain ⟨rest, tail⟩ := ih meanings length checked.2
      let first : StoredBlob schemas := ⟨raw, meaning, checked.1⟩
      have admitted : StoredBlob.admit schemas raw meaning = some first := by simp [StoredBlob.admit, checked.1, first]
      exact ⟨first :: rest, by simp [Store.admitBlobs, admitted, tail]⟩

theorem Context.ofWitness_program (program : Program) (meanings : List SemanticValue)
    (context : Context) (accepted : Context.ofWitness program meanings = some context) :
    context.program = program := by
  unfold Context.ofWitness at accepted
  split at accepted
  · cases accepted
  · cases accepted; rfl

theorem Context.ofWitness_complete (program : Program) (meanings : List SemanticValue)
    (checked : Admission.constantsValid program meanings = true) : (Context.ofWitness program meanings).isSome = true := by
  simp only [Admission.constantsValid, Bool.and_eq_true, beq_iff_eq] at checked
  let raws : List Graph.Blob := program.constants.map (fun literal => ⟨literal.schema, literal.bytes⟩)
  have length : raws.length = meanings.length := by simpa [raws] using checked.1
  have values : (raws.zip meanings).all (fun (raw, meaning) =>
      Profile.Value.checkExternal program.schemas raw.schema raw.bytes meaning) = true := by
    simpa [raws, List.zip_map_left, List.all_map] using checked.2
  obtain ⟨blobs, admitted⟩ := Store.admitBlobs_complete program.schemas raws meanings length values
  unfold Context.ofWitness
  split
  · rename_i rejected
    have same : Store.admitBlobs program.schemas raws meanings = none := rejected
    simp [same] at admitted
  · rfl

/-- The image bytes and the complete static witness are checked before this
context can be constructed. The stored constants retain their exact byte
interpretations. This does not assert operational preservation or compilation
equivalence. -/
structure ImageContext (bytes : Bytes) (witness : Admission.Witness) where
  context : Context
  admitted : CertifiedImage.CanonicalProgram context.program witness
  encoded : Images.encodeImage context.program = bytes

def ImageContext.decode (bytes : Bytes) (witness : Admission.Witness) :
    Option (ImageContext bytes witness) :=
  match decoded : CertifiedImage.decode bytes witness with
  | none => none
  | some program =>
    match constructed : Context.ofWitness program witness.constants with
    | none => none
    | some context =>
      let same := Context.ofWitness_program program witness.constants context constructed
      let sound := CertifiedImage.decode_bpi2_sound bytes witness program decoded
      some ⟨context, same ▸ sound.1, same ▸ sound.2⟩

theorem ImageContext.decode_complete (bytes : Bytes) (witness : Admission.Witness) (program : Program)
    (accepted : CertifiedImage.decode bytes witness = some program) :
    (ImageContext.decode bytes witness).isSome = true := by
  have declarations := (CertifiedImage.decode_bpi2_sound bytes witness program accepted).1.2.2.1.1
  simp only [Admission.declarationsValid, Bool.and_eq_true] at declarations
  have constants := Context.ofWitness_complete program witness.constants declarations.1.1.1.1.1.1.1.2
  unfold decode
  split
  · rename_i rejected; simp [rejected] at accepted
  · rename_i decoded found
    have same : decoded = program := Option.some.inj (found.symm.trans accepted)
    subst decoded
    split
    · rename_i rejected; simp [rejected] at constants
    · rfl

def ImageContext.identity (image : ImageContext bytes witness) : Digest :=
  Protocol.programIdentity image.context.program

/-- Image-backed initialization derives the program identity from the exact
decoded records. No producer-supplied digest can change the initial binding. -/
def ImageContext.initial (image : ImageContext bytes witness) (arguments : List SemanticValue) :
    Except Invalid (State image.context.program) :=
  Machine.initial image.context image.identity arguments

theorem initial_exact_identity (context : Context) (identity : Digest)
    (arguments : List SemanticValue) (state : State context.program)
    (accepted : initial context identity arguments = .ok state) : state.identity = identity := by
  unfold initial at accepted
  simp only [bind, Except.bind] at accepted
  split at accepted
  · cases accepted
  · split at accepted
    · cases accepted
    · split at accepted
      · cases accepted
      · cases accepted; rfl

theorem ImageContext.initial_binds_exact_image (image : ImageContext bytes witness)
    (arguments : List SemanticValue) (state : State image.context.program)
    (accepted : image.initial arguments = .ok state) :
    Images.encodeImage image.context.program = bytes ∧
      state.raw.programIdentity = Protocol.programIdentity image.context.program ∧
      CertifiedImage.CanonicalProgram image.context.program witness := by
  exact ⟨image.encoded, initial_exact_identity _ _ _ _ accepted, image.admitted⟩

theorem ImageContext.decode_rejects_unadmitted (bytes : Bytes) (witness : Admission.Witness)
    (rejected : CertifiedImage.decode bytes witness = none) :
    ImageContext.decode bytes witness = none := by
  unfold decode
  split
  · rfl
  · simp_all

end BoundaryV2.Profile.Target.Machine
