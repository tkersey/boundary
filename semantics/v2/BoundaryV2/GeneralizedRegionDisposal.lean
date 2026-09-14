import BoundaryV2.GeneralizedValueDisposal

namespace BoundaryV2.Generalized.ExitComposition

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

variable [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

theorem RegionDisposalSteps.of_values {table : Target.Definitions signature algebra program}
    (identity : Id .region) (outside : Target.Stack signature algebra program input result) (kept : List (Id .cell))
    (steps : ValueDisposalSteps table before count after (outside.installationReferences ++ retained)) :
    RegionDisposalSteps table (.disposing identity outside kept before) count (.disposing identity outside kept after) retained := by
  induction count generalizing before with
  | zero => cases steps; exact .refl
  | succ count induction =>
    cases steps with
    | cons step tail => exact .cons (.values step) (induction tail)

omit [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)] in
theorem active_value_disposal_prevents_region_retirement
    (identity : Id .region) (outside : Target.Stack signature algebra program input result)
    (kept : List (Id .cell)) (work : ValueDisposal signature algebra program) :
    RegionDisposal.finish external (.disposing identity outside kept work) = none := rfl

omit [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)] in
theorem finished_region_passes_the_actual_retirement_gate
    (before : RegionDisposal signature algebra program result) (accepted : before.finish external = some after) :
    ∃ (input : TypeOf signature), ∃ (handoff : RegionHandoff signature algebra program input result),
      before = .offering handoff ∧ handoff.offerNext = none ∧
      (Resolution.unwind handoff.runtime handoff.outside).retireRegions [handoff.identity] external = some after := by
  cases before with
  | disposing => cases accepted
  | offering handoff =>
    change (if handoff.offerNext.isNone then
      (Resolution.unwind handoff.runtime handoff.outside).retireRegions [handoff.identity] external
      else none) = some after at accepted
    split at accepted
    · rename_i exhausted
      exact ⟨_, handoff, rfl, by simpa using exhausted, accepted⟩
    · cases accepted

omit [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)] in
theorem finished_region_preserves_owners_and_exit
    (handoff : RegionHandoff signature algebra program input result)
    (accepted : RegionDisposal.finish external (.offering handoff) = some after) :
    after.store = handoff.runtime.store ∧ after.exitInfo = handoff.runtime.exit ∧
      UseScope.tokens after.cells.fields = UseScope.tokens handoff.runtime.cells.fields := by
  change (if handoff.offerNext.isNone then
    (Resolution.unwind handoff.runtime handoff.outside).retireRegions [handoff.identity] external
    else none) = some after at accepted
  split at accepted
  · exact region_retirement_preserves_owners_and_exit accepted
  · cases accepted

end BoundaryV2.Generalized.ExitComposition
