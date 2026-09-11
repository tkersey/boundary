import BoundaryV2.GraphFutureUses
import BoundaryV2.GraphEffects
import BoundaryV2.TargetImage
import BoundaryV2.Snapshot

namespace BoundaryV2.Profile.Graph.Admission

structure Witness where
  blobs : List (Profile.Value .target)
  projections : List ProjectionRow

def checkWithFacts (program : Target.Program) (identity : Digest) (effects : Target.Admission.EffectFacts)
    (borrows : Target.Borrow.Witness) (state : State) (witness : Witness) : Bool :=
  positionValidWithIdentity program identity state && recordsValid program state &&
  captureRecordsValid program state && effectsValidWith program state effects &&
  blobsValid program state witness.blobs &&
  (directUses state).any (usesValid state) && futureScopesValid program state borrows witness.projections

/-- The program's interprocedural borrow witness is shared with image admission.
State witnesses supply only exact blob meanings and complete local projections;
they cannot assert missing program summaries or omit future lifetime demands. -/
def check (program : Target.Program) (borrows : Target.Borrow.Witness) (state : State) (witness : Witness) : Bool :=
  checkWithFacts program (Protocol.programIdentity program) (Target.Admission.effectFacts program) borrows state witness

def Admitted (program : Target.Program) (borrows : Target.Borrow.Witness) (state : State) (witness : Witness) : Prop :=
  positionValid program state = true ∧ recordsValid program state = true ∧
  captureRecordsValid program state = true ∧ effectsValid program state = true ∧
  blobsValid program state witness.blobs = true ∧
  (∃ uses, directUses state = some uses ∧ usesValid state uses = true) ∧
  futureScopesValid program state borrows witness.projections = true

theorem check_exact (program : Target.Program) (borrows : Target.Borrow.Witness) (state : State) (witness : Witness) :
    check program borrows state witness = true ↔ Admitted program borrows state witness := by
  simp [check, checkWithFacts, Admitted, positionValid, effectsValid, Bool.and_eq_true, Option.any_eq_true, and_assoc]

theorem admitted_state_bound_to_program (program : Target.Program) (borrows : Target.Borrow.Witness)
    (state : State) (witness : Witness) (accepted : Admitted program borrows state witness) :
    state.programIdentity = Protocol.programIdentity program := position_exact_identity program state accepted.1

theorem admitted_value_lifetimes (program : Target.Program) (borrows : Target.Borrow.Witness)
    (state : State) (witness : Witness) (accepted : Admitted program borrows state witness) :
    ∃ uses, directUses state = some uses ∧ ∀ use ∈ uses, supportedUse state use = true := by
  obtain ⟨uses, derived, checked⟩ := accepted.2.2.2.2.2.1
  exact ⟨uses, derived, fun use member => every_use_checked state uses use checked member⟩

theorem shared_facts_preserve_every_check (program : Target.Program) (borrows : Target.Borrow.Witness)
    (state : State) (witness : Witness) :
    checkWithFacts program (Protocol.programIdentity program) (Target.Admission.effectFacts program) borrows state witness =
      check program borrows state witness := rfl

end BoundaryV2.Profile.Graph.Admission

namespace BoundaryV2.Profile.Target.CertifiedState

/-- Complete bytes, canonical graph numbering, and program-relative type,
custody, scope, capture, effect and obligation admission. Historical reachability
and preservation by runtime transitions are separate propositions. -/
def decode (image : Machine.ImageContext imageBytes programWitness) (input : Bytes)
    (witness : Graph.Admission.Witness) : Option Graph.State := do
  let state ← Graph.Snapshot.decode input
  if Graph.Admission.check image.context.program programWitness.borrows state witness then some state else none

theorem decode_sound (image : Machine.ImageContext imageBytes programWitness) (input : Bytes)
    (witness : Graph.Admission.Witness) (state : Graph.State)
    (accepted : decode image input witness = some state) :
    Images.rawState.valid state = true ∧ Images.rawState.encode state = input ∧
    Graph.Snapshot.canonicalize state = some state ∧
    Graph.Admission.Admitted image.context.program programWitness.borrows state witness ∧
    state.programIdentity = Protocol.programIdentity image.context.program ∧
    CertifiedImage.CanonicalProgram image.context.program programWitness ∧
    Images.encodeImage image.context.program = imageBytes := by
  unfold decode at accepted
  cases parsed : Graph.Snapshot.decode input with
  | none => simp [parsed] at accepted
  | some original =>
    simp [parsed] at accepted
    obtain ⟨checked, rfl⟩ := accepted
    have exactBytes := Graph.Snapshot.decode_exact input original parsed
    have admitted := (Graph.Admission.check_exact _ _ _ _).mp checked
    exact ⟨exactBytes.1, exactBytes.2.1, exactBytes.2.2, admitted,
      Graph.Admission.admitted_state_bound_to_program _ _ _ _ admitted, image.admitted, image.encoded⟩

theorem decode_complete (image : Machine.ImageContext imageBytes programWitness) (input : Bytes)
    (witness : Graph.Admission.Witness) (state : Graph.State)
    (parsed : Graph.Snapshot.decode input = some state)
    (admitted : Graph.Admission.Admitted image.context.program programWitness.borrows state witness) :
    decode image input witness = some state := by
  simp [decode, parsed, (Graph.Admission.check_exact _ _ _ _).mpr admitted]

end BoundaryV2.Profile.Target.CertifiedState
