import BoundaryV2.GeneralizedValueDisposal

namespace BoundaryV2.Generalized.ExitComposition

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

/-- Only the active phase owns the runtime. A value disposal keeps the region
identity, outside continuation, and offered-cell names, not a heap snapshot. -/
inductive RegionDisposal (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  | offering {input : TypeOf signature} : RegionHandoff signature algebra program input result → RegionDisposal signature algebra program result
  | disposing {input : TypeOf signature} : Id .region → Target.Stack signature algebra program input result →
      List (Id .cell) → ValueDisposal signature algebra program → RegionDisposal signature algebra program result

def RegionDisposal.begin (resolution : Resolution signature algebra program result) :
    Option (RegionDisposal signature algebra program result) :=
  match resolution with
  | .unwind runtime future => match Target.unwindBoundary future with
    | .region identity outside => some (.offering (beginRegionHandoff identity runtime outside))
    | _ => none
  | _ => none

def RegionDisposal.offer : RegionDisposal signature algebra program result → Option (RegionDisposal signature algebra program result)
  | .offering handoff => handoff.offerNext.map fun (value, after) =>
      .disposing after.identity after.outside after.kept (ValueDisposal.start after.runtime value.snd)
  | _ => none

def RegionDisposal.returnValue : RegionDisposal signature algebra program result → Option (RegionDisposal signature algebra program result)
  | .disposing identity outside kept work => work.finished.map fun runtime => .offering ⟨identity, runtime, outside, kept⟩
  | _ => none

/-- An exhausted offer loop does not itself authorize retirement. The existing
retirement operation checks completion, physical fields, and all surviving roots. -/
def RegionDisposal.finish (external : List Reference) :
    RegionDisposal signature algebra program result → Option (Resolution signature algebra program result)
  | .offering handoff =>
    if handoff.offerNext.isNone then (Resolution.unwind handoff.runtime handoff.outside).retireRegions [handoff.identity] external
    else none
  | _ => none

variable [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

inductive RegionDisposalStep (table : Target.Definitions signature algebra program) :
    RegionDisposal signature algebra program result → RegionDisposal signature algebra program result → Prop where
  | offer : before.offer = some after → RegionDisposalStep table before after
  | values : ValueDisposalStep table before after →
      RegionDisposalStep table (.disposing identity outside kept before) (.disposing identity outside kept after)
  | returnValue : before.returnValue = some after → RegionDisposalStep table before after

inductive RegionDisposalSteps (table : Target.Definitions signature algebra program) :
    RegionDisposal signature algebra program result → Nat → RegionDisposal signature algebra program result → Prop where
  | refl : RegionDisposalSteps table state 0 state
  | cons : RegionDisposalStep table before middle → RegionDisposalSteps table middle count after → RegionDisposalSteps table before (count + 1) after

theorem RegionDisposalSteps.of_values {table : Target.Definitions signature algebra program}
    (steps : ValueDisposalSteps table before count after) (identity : Id .region)
    (outside : Target.Stack signature algebra program input result) (kept : List (Id .cell)) :
    RegionDisposalSteps table (.disposing identity outside kept before) count (.disposing identity outside kept after) := by
  induction steps with
  | refl => exact .refl
  | cons step tail induction => exact .cons (.values step) induction

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
