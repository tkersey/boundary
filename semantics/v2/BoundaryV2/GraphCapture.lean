import BoundaryV2.GraphRecordTypes

namespace BoundaryV2.Profile.Graph.Admission

def capturedFrameValid (_program : Target.Program) (state : State) (signature : ResumptionType .target)
    (reference : NodeId) : Bool := ((do
  let record ← node state reference
  let values ← match record with
    | .continuation saved => some (saved.arguments.filterMap id)
    | .attachment activation _ _ _ _ => do
      let .handler _ values _ _ ← node state activation | none
      pure values
    | .disposalReturn _ _ values => some values
    | _ => some []
  let region ← match record with
    | .regionScope _ region _ => do
      let .region descriptor _ _ ← node state region | none
      pure (some descriptor)
    | .protection _ _ _ _ _ (some loan) => do
      let .region descriptor _ _ ← node state loan | none
      pure (some descriptor)
    | _ => some none
  let obligation := match record with | .protection .. | .cleanupReturn .. => true | _ => false
  pure (values.all (fun value => signature.captureBound.contains value.schema) &&
    region.all signature.ownedRegions.contains &&
    (!obligation || (signature.obligations && signature.use != .multi)))) : Option Bool).getD false

/-- Capture follows the same physical frame parents as execution. It retains
the selected suspended delimiter and checks every inside frame before stopping
there; borrowed outside state is excluded from the captured-value bound. -/
def captureValid (program : Target.Program) (state : State) (capture : Capture) : Bool :=
  (chain state frameParent isFrame (inventory state) capture.capture).any fun path =>
  path.contains capture.delimiter && ((do
  let signature ← Target.Admission.resumption program capture.schema
  let first ← capture.capture
  let .continuation saved ← node state first | none
  let .attachment activation _ _ .suspended _ ← node state capture.delimiter | none
  let source ← block program saved.sourceBlock
  let .perform operation := source.terminator | none
  let definition ← handler program state activation
  let effect ← program.effects[signature.effect.value]?
  pure (normalReturning state first && operation.effect == signature.effect && operation.capability.isSome &&
    definition.clauses.any (fun clause => clause.effect == signature.effect &&
      (clause.resumption == capture.schema || Target.Admission.cloneCompatible program clause.resumption capture.schema)) &&
    capture.evidence == saved.evidence && capture.useSiteCapabilities.length == effect.useSiteEffects.length &&
    (capture.useSiteCapabilities.zip effect.useSiteEffects).all (fun (value, effect) =>
      valueValid program state value value.schema && Target.Admission.capability program value.schema effect) &&
    (path.takeWhile (· != capture.delimiter)).all (capturedFrameValid program state signature))) : Option Bool).getD false

def captureRecordsValid (program : Target.Program) (state : State) : Bool := state.nodes.all fun record =>
  match record with | .oneShot capture | .multiTemplate capture => captureValid program state capture | _ => true

theorem captured_frame_checks_all_retained_values (program : Target.Program) (state : State)
    (signature : ResumptionType .target) (reference : NodeId) (saved : Continuation)
    (actual : node state reference = some (.continuation saved))
    (accepted : capturedFrameValid program state signature reference = true) :
    ∀ value ∈ saved.arguments.filterMap id, value.schema ∈ signature.captureBound := by
  have checked : (saved.arguments.filterMap id).all (fun value => signature.captureBound.contains value.schema) = true := by
    simpa only [capturedFrameValid, actual, bind, Option.bind, pure, Pure.pure, Option.getD_some,
      Bool.not_false, Bool.true_or, Bool.and_true, Option.all_none] using accepted
  intro value member
  exact List.contains_iff_mem.mp (List.all_eq_true.mp checked value member)

theorem multi_capture_cannot_retain_protection (program : Target.Program) (state : State)
    (signature : ResumptionType .target) (reference : NodeId) (source : BlockId) (obligation : OwnedRef)
    (parent evidence region loan : Option NodeId)
    (actual : node state reference = some (.protection source obligation parent evidence region loan))
    (multi : signature.use = .multi) : capturedFrameValid program state signature reference = false := by
  unfold capturedFrameValid
  simp only [actual, bind, Option.bind, multi]
  cases loan with
  | none => simp
  | some loan =>
    cases atLoan : node state loan with
    | none => simp [atLoan]
    | some loanRecord => cases loanRecord <;> simp [atLoan]

theorem capture_requires_selected_delimiter (program : Target.Program) (state : State) (capture : Capture)
    (accepted : captureValid program state capture = true) :
    ∃ path, chain state frameParent isFrame (inventory state) capture.capture = some path ∧ capture.delimiter ∈ path := by
  obtain ⟨path, found, checked⟩ := (Option.any_eq_true _ _).mp accepted
  simp only [Bool.and_eq_true] at checked
  exact ⟨path, found, List.contains_iff_mem.mp checked.1⟩

end BoundaryV2.Profile.Graph.Admission
