import BoundaryV2.GeneralizedRegionDisposal

namespace BoundaryV2.Generalized.ExitComposition

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

def CompletedCleanup.store : CompletedCleanup signature algebra program result → Target.ControlHeap signature algebra program
  | .resolved resolution => resolution.store
  | .disposing work => work.runtime.store

def CompletedCleanup.cells : CompletedCleanup signature algebra program result →
    Cells signature algebra (fun context result => Target.Code signature algebra program context [] result)
  | .resolved resolution => resolution.cells
  | .disposing work => work.runtime.cells

def CompletedCleanup.regions : CompletedCleanup signature algebra program result → List (Id .region)
  | .resolved resolution => resolution.regions
  | .disposing work => work.runtime.liveRegions

omit [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)] in
theorem cleanup_result_reentry_uses_current_resources
    (identity : Id .obligation) (completion : Completion algebra.Fault)
    (store : Target.ControlHeap signature algebra program)
    (cells : Cells signature algebra (fun context result => Target.Code signature algebra program context [] result))
    (regions : List (Id .region)) (outside : Target.Stack signature algebra program input result)
    (outcome : CleanupResult signature algebra (fun context result => Target.Code signature algebra program context [] result) input) :
    let after := reenterCleanupResult identity completion store cells regions outside outcome
    after.store = store ∧ after.cells = cells ∧ after.regions = regions := by
  cases outcome with
  | returned | disposing => exact ⟨rfl, rfl, rfl⟩
  | exiting exit =>
    cases exit with
    | mk primary failures cancellation => cases primary <;> exact ⟨rfl, rfl, rfl⟩

omit [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)] in
theorem cleanup_frame_completion_uses_current_resources
    (before : Resolution signature algebra program result) (after : CompletedCleanup signature algebra program result)
    (accepted : finishCleanupFrame before = some after) :
    after.store = before.store ∧ after.cells = before.cells ∧ after.regions = before.regions := by
  fun_cases finishCleanupFrame before <;> simp_all only [finishCleanupFrame] <;>
    first
    | contradiction
    | (obtain ⟨outcome, _, same⟩ := Option.map_eq_some_iff.mp accepted
       cases same
       exact cleanup_result_reentry_uses_current_resources _ _ _ _ _ _ _)

theorem CleanupFrameSteps.of_execution {table : Target.Definitions signature algebra program}
    (steps : Target.ExecutionSteps table before count after retained)
    (diagnostics : ExitInfo algebra.Fault algebra.Reason) :
    CleanupFrameSteps table (.running (.reenter before diagnostics)) count (.running (.reenter after diagnostics)) retained := by
  induction count generalizing before with
  | zero => cases steps; exact .refl
  | succ count induction =>
    cases steps with
    | cons step tail => exact .cons (.execute step) (induction tail)

theorem CleanupFrameSteps.trans {table : Target.Definitions signature algebra program}
    {before middle after : CleanupFrameProgress signature algebra program result}
    (first : CleanupFrameSteps table before count middle retained)
    (second : CleanupFrameSteps table middle rest after retained) :
    CleanupFrameSteps table before (count + rest) after retained := by
  induction count generalizing before with
  | zero => cases first; simpa using second
  | succ count induction =>
    cases first with
    | cons step tail =>
      simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using CleanupFrameSteps.cons step (induction tail)

theorem CleanupFrameSteps.of_values {table : Target.Definitions signature algebra program}
    (frame : Id .obligation) (completion : Completion algebra.Fault)
    (outside : Target.Stack signature algebra program input result)
    (steps : ValueDisposalSteps table before count after (outside.installationReferences ++ retained)) :
    CleanupFrameSteps table (.values frame completion outside before) count (.values frame completion outside after) retained := by
  induction count generalizing before with
  | zero => cases steps; exact .refl
  | succ count induction =>
    cases steps with
    | cons step tail => exact .cons (.values step) (induction tail)

theorem CleanupFrameSteps.of_region {table : Target.Definitions signature algebra program}
    {before after : RegionDisposal signature algebra program result}
    (steps : RegionDisposalSteps table before count after retained) :
    CleanupFrameSteps table (.region before) count (.region after) retained := by
  induction count generalizing before with
  | zero => cases steps; exact .refl
  | succ count induction =>
    cases steps with
    | cons step tail => exact .cons (.region step) (induction tail)

theorem owned_cleanup_result_cannot_skip_disposal
    {table : Target.Definitions signature algebra program} {work : CleanupDisposal signature algebra program result}
    {resolution : Resolution signature algebra program result} :
    ¬ CleanupFrameStep table (.disposing work) (.running resolution) := by intro step; cases step

theorem frame_region_step_uses_retained_roots {table : Target.Definitions signature algebra program}
    {before : RegionDisposal signature algebra program result} {after : Resolution signature algebra program result}
    (step : CleanupFrameStep table (.region before) (.running after) retained) :
    ∃ external, before.finish (retained ++ external) = some after := by
  cases step with
  | finishRegion accepted =>
    rename_i external
    exact ⟨external, accepted⟩

theorem frame_region_finite_handoff {table : Target.Definitions signature algebra program}
    {before after : Resolution signature algebra program result}
    {first last : RegionDisposal signature algebra program result}
    (entered : RegionDisposal.begin before = some first)
    (steps : RegionDisposalSteps table first count last retained)
    (finished : last.finish (retained ++ external) = some after) :
    CleanupFrameSteps table (.running before) (count + 2) (.running after) retained := by
  have middle := CleanupFrameSteps.of_region steps
  simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
    ((CleanupFrameSteps.cons (.enterRegion entered) .refl).trans middle).trans (.cons (.finishRegion finished) .refl)

end BoundaryV2.Generalized.ExitComposition
