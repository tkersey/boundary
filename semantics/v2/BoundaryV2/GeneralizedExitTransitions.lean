import BoundaryV2.GeneralizedExitWork

namespace BoundaryV2.Generalized.ExitComposition

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

/- Cleanup, owned values, and region retirement recursively invoke each other.
These are the existing operation rules with their shared finite composition. -/
mutual
  inductive NestedProgressStep (table : Target.Definitions signature algebra program) :
      NestedProgress signature algebra program → NestedProgress signature algebra program → (retained : List Reference := []) → Prop where
    | nested : NestedStep table before initiations after → NestedProgressStep table (.active before) (.active after) retained
    | enterRegion : before.enterRegion = some after → NestedProgressStep table before after retained
    | region : RegionDisposalStep table before after (parents.flatMap CleanupParent.references ++ retained) →
        NestedProgressStep table (.region current parents before) (.region current parents after) retained
    | finishRegion : before.finishRegion (retained ++ external) = some after → NestedProgressStep table before after retained
    | cancel : NestedProgressStep table before (before.cancel reason) retained

  inductive NestedProgressSteps (table : Target.Definitions signature algebra program) :
      NestedProgress signature algebra program → Nat → NestedProgress signature algebra program → (retained : List Reference := []) → Prop where
    | refl : NestedProgressSteps table state 0 state retained
    | cons : NestedProgressStep table before middle retained → NestedProgressSteps table middle count after retained →
        NestedProgressSteps table before (count + 1) after retained

  inductive ValueDisposalStep (table : Target.Definitions signature algebra program) :
      ValueDisposal signature algebra program → ValueDisposal signature algebra program → (retained : List Reference := []) → Prop where
    | stale : value.hasActiveRoot runtime.store.fields = false →
        ValueDisposalStep table (.ready runtime (⟨type, value⟩ :: rest)) (.ready runtime rest) retained
    | pair : ValueDisposalStep table (.ready runtime (⟨_, .pair first second⟩ :: rest))
        (.ready runtime (⟨_, first⟩ :: ⟨_, second⟩ :: rest)) retained
    | left : ValueDisposalStep table (.ready runtime (⟨_, .left value⟩ :: rest)) (.ready runtime (⟨_, value⟩ :: rest)) retained
    | right : ValueDisposalStep table (.ready runtime (⟨_, .right value⟩ :: rest)) (.ready runtime (⟨_, value⟩ :: rest)) retained
    | datumPair : ValueDisposalStep table (.ready runtime (⟨_, .datum (.pair first second)⟩ :: rest))
        (.ready runtime (⟨_, .datum first⟩ :: ⟨_, .datum second⟩ :: rest)) retained
    | datumLeft : ValueDisposalStep table (.ready runtime (⟨_, .datum (.left value)⟩ :: rest))
        (.ready runtime (⟨_, .datum value⟩ :: rest)) retained
    | datumRight : ValueDisposalStep table (.ready runtime (⟨_, .datum (.right value)⟩ :: rest))
        (.ready runtime (⟨_, .datum value⟩ :: rest)) retained
    | package : PackageHandoff value token owner runtime.store.fields fields →
        ValueDisposalStep table (.ready runtime (⟨_, .package token owner value⟩ :: rest))
          (.ready { runtime with store := { runtime.store with fields := fields } } (⟨_, value⟩ :: rest)) retained
    | closure {body : Target.Code signature algebra program (parameters ++ capturedTypes) [] result} :
        ComputationHandoff captured use authority runtime.store.fields fields →
        ValueDisposalStep table (.ready runtime (⟨_, .closure (use := use) body captured authority⟩ :: rest))
          (.ready { runtime with store := { runtime.store with fields := fields } } (captured.disposalValues ++ rest)) retained
    | resource : UseScope.takeGrant token owner (UseScope.activeFields runtime.store.fields.active) = some active →
        ValueDisposalStep table (.ready runtime (⟨_, .datum (.resource identity token owner)⟩ :: rest))
          (.ready { runtime with store := { runtime.store with
            fields := ⟨active, runtime.store.fields.retained, token :: runtime.store.fields.spent⟩ } } rest) retained
    | enterControl : UseScope.disposeOwned ⟨identity, authority, owner⟩ runtime.store = some acquired →
        ValueDisposalStep table (.ready runtime (⟨_, .continuation identity (some (authority, owner))⟩ :: rest))
          (.control ⟨acquired.future.fst.answer, .seeking
            ⟨runtime.id, .finished .abandoned, acquired.store, runtime.cells, runtime.liveRegions, runtime.exit⟩
            acquired.future.snd.future, .done⟩ rest) retained
    | control : Target.DisposalStep table before selected after →
        ValueDisposalStep table (.control before rest) (.control after rest) retained
    | enterNested (scope : ScopeExit signature algebra program answer) :
        ValueDisposalStep table (.control ⟨answer, .cleaning scope, .done⟩ rest)
          (.nested (.active (NestedCleanup.start scope.cleanup)) scope.resume rest) retained
    | nested : NestedProgressStep table before after
          (resume.references ++ rest.flatMap (fun value => Target.valueReferences value.snd) ++ retained) →
        ValueDisposalStep table (.nested before resume rest) (.nested after resume rest) retained
    | leaveNested {resume : ResumePoint signature algebra program answer} : machine.finished = some runtime →
        ValueDisposalStep table (.nested machine resume rest)
          (.control ⟨answer, .cleaning ⟨runtime, resume⟩, .done⟩ rest) retained
    | finishControl : ValueDisposalStep table (.control ⟨answer, .complete runtime, .done⟩ rest) (.ready runtime rest) retained

  inductive ValueDisposalSteps (table : Target.Definitions signature algebra program) :
      ValueDisposal signature algebra program → Nat → ValueDisposal signature algebra program → (retained : List Reference := []) → Prop where
    | refl : ValueDisposalSteps table state 0 state retained
    | cons : ValueDisposalStep table before middle retained → ValueDisposalSteps table middle count after retained → ValueDisposalSteps table before (count + 1) after retained

  inductive RegionDisposalStep (table : Target.Definitions signature algebra program) :
      RegionDisposal signature algebra program result → RegionDisposal signature algebra program result → (retained : List Reference := []) → Prop where
    | offer : before.offer = some after → RegionDisposalStep table before after retained
    | values : ValueDisposalStep table before after (outside.installationReferences ++ retained) →
        RegionDisposalStep table (.disposing identity outside kept before) (.disposing identity outside kept after) retained
    | returnValue : before.returnValue = some after → RegionDisposalStep table before after retained

  inductive RegionDisposalSteps (table : Target.Definitions signature algebra program) :
      RegionDisposal signature algebra program result → Nat → RegionDisposal signature algebra program result → (retained : List Reference := []) → Prop where
    | refl : RegionDisposalSteps table state 0 state retained
    | cons : RegionDisposalStep table before middle retained → RegionDisposalSteps table middle count after retained → RegionDisposalSteps table before (count + 1) after retained

end

theorem NestedProgressSteps.trans {table : Target.Definitions signature algebra program}
    {before middle after : NestedProgress signature algebra program}
    (first : NestedProgressSteps table before count middle retained) (second : NestedProgressSteps table middle rest after retained) :
    NestedProgressSteps table before (count + rest) after retained := by
  induction count generalizing before with
  | zero => cases first; simpa using second
  | succ count induction =>
    cases first with
    | cons step tail => simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using NestedProgressSteps.cons step (induction tail)

theorem NestedProgressSteps.of_nested {table : Target.Definitions signature algebra program}
    {before after : NestedCleanup signature algebra program} (steps : NestedSteps table before initiations after) :
    ∃ count, NestedProgressSteps table (.active before) count (.active after) retained := by
  induction steps with
  | refl => exact ⟨0, .refl⟩
  | cons step tail induction =>
    obtain ⟨count, rest⟩ := induction
    exact ⟨count + 1, .cons (.nested step) rest⟩

theorem NestedProgressSteps.of_region {table : Target.Definitions signature algebra program}
    {before after : RegionDisposal signature algebra program .unit}
    (current : CleanupInfo algebra.Fault algebra.Reason) (parents : List (CleanupParent signature algebra program))
    (steps : RegionDisposalSteps table before count after (parents.flatMap CleanupParent.references ++ retained)) :
    NestedProgressSteps table (.region current parents before) count (.region current parents after) retained := by
  induction count generalizing before with
  | zero => cases steps; exact .refl
  | succ count induction =>
    cases steps with
    | cons step tail => exact .cons (.region step) (induction tail)

theorem nested_region_value_work_cannot_be_skipped {table : Target.Definitions signature algebra program}
    (current : CleanupInfo algebra.Fault algebra.Reason) (parents : List (CleanupParent signature algebra program))
    (identity : Id .region) (outside : Target.Stack signature algebra program input .unit)
    (kept : List (Id .cell)) (values : ValueDisposal signature algebra program)
    (after : NestedCleanup signature algebra program) :
    ¬ NestedProgressStep table (.region current parents (.disposing identity outside kept values)) (.active after) retained := by
  intro step
  cases step with
  | enterRegion accepted => cases accepted
  | finishRegion accepted => cases accepted

/-- Returning from the region detour must use the retained roots supplied by
the enclosing operation. Extra external roots may be added, never substituted. -/
theorem nested_region_step_uses_retained_roots {table : Target.Definitions signature algebra program}
    {current : CleanupInfo algebra.Fault algebra.Reason} {parents : List (CleanupParent signature algebra program)}
    {work : RegionDisposal signature algebra program .unit} {after : NestedCleanup signature algebra program}
    (step : NestedProgressStep table (.region current parents work) (.active after) retained) :
    ∃ external, NestedProgress.finishRegion (retained ++ external) (.region current parents work) = some (.active after) := by
  cases step with
  | enterRegion accepted => cases accepted
  | finishRegion accepted =>
    rename_i external
    exact ⟨external, accepted⟩

theorem nested_region_finite_handoff {table : Target.Definitions signature algebra program}
    {before after : NestedProgress signature algebra program}
    {current : CleanupInfo algebra.Fault algebra.Reason} {parents : List (CleanupParent signature algebra program)}
    {first last : RegionDisposal signature algebra program .unit}
    (entered : before.enterRegion = some (.region current parents first))
    (steps : RegionDisposalSteps table first count last (parents.flatMap CleanupParent.references ++ retained))
    (finished : NestedProgress.finishRegion (retained ++ external) (.region current parents last) = some after) :
    NestedProgressSteps table before (count + 2) after retained := by
  have middle := NestedProgressSteps.of_region current parents steps
  simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using
    ((NestedProgressSteps.cons (.enterRegion entered) .refl).trans middle).trans (.cons (.finishRegion finished) .refl)

end BoundaryV2.Generalized.ExitComposition
