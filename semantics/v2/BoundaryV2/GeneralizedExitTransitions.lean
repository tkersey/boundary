import BoundaryV2.GeneralizedExitWork

namespace BoundaryV2.Generalized.ExitComposition

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

/- Cleanup, owned values, and region retirement recursively invoke each other.
These are the existing operation rules with their shared finite composition. -/
mutual
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
          (.control (ControlProgress.seeking
            ⟨runtime.id, .finished .abandoned, acquired.store, runtime.cells, runtime.liveRegions, runtime.exit⟩
            acquired.future.snd.future) rest) retained
    | control : ControlProgressStep table before after
          (rest.flatMap (fun value => Target.valueReferences value.snd) ++ retained) →
        ValueDisposalStep table (.control before rest) (.control after rest) retained
    | finishControl : ValueDisposalStep table (.control (.complete runtime) rest) (.ready runtime rest) retained

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

  /-- Boundary transitions preserve complete exit records; ordinary target work
  continues in the actual context. Control disposal reuses its existing driver. -/
  inductive CleanupFrameStep (table : Target.Definitions signature algebra program) :
      CleanupFrameProgress signature algebra program result → CleanupFrameProgress signature algebra program result → (retained : List Reference := []) → Prop where
    | execute : Target.ExecutionStep table before after retained →
        CleanupFrameStep table (.running (.reenter before diagnostics)) (.running (.reenter after diagnostics)) retained
    | begin : beginAbruptCleanup before = some after → CleanupFrameStep table (.running before) (.running after) retained
    | advance : advanceFailedResolution before = some after → CleanupFrameStep table (.running before) (.running after) retained
    | unwind : advanceUnwindResolution before = some after → CleanupFrameStep table (.running before) (.running after) retained
    | finish : finishCleanupFrame before = some after → CleanupFrameStep table (.running before) after.progress retained
    | cancel : before.cancelRunning reason = some after → CleanupFrameStep table (.running before) (.running after) retained
    | enterRegion : RegionDisposal.begin before = some after →
        CleanupFrameStep table (.running before) (.region after) retained
    | region : RegionDisposalStep table before after retained →
        CleanupFrameStep table (.region before) (.region after) retained
    | finishRegion : RegionDisposal.finish (retained ++ external) before = some after →
        CleanupFrameStep table (.region before) (.running after) retained
    | enterValues : work.runtime.phase = .finished completion →
        CleanupFrameStep table (.disposing work)
          (.values work.runtime.id completion work.outside (ValueDisposal.start work.runtime work.value)) retained
    | values : ValueDisposalStep table before after (outside.installationReferences ++ retained) →
        CleanupFrameStep table (.values frame completion outside before) (.values frame completion outside after) retained
    | finishValues : machine.finished = some runtime →
        CleanupFrameStep table (.values frame completion outside machine)
          (reenterCleanupResult frame completion runtime.store runtime.cells runtime.liveRegions outside (.exiting runtime.exit)).progress retained

    | parkYield {future : Target.Configuration signature algebra program result} :
        CleanupFrameStep table
          (.running (.reenter ⟨⟨store, .yielded future⟩, cells, regions⟩ diagnostics))
          (.parked (.reenter ⟨⟨store, .yielded future⟩, cells, regions⟩ diagnostics)) retained
    | continueYield {future : Target.Configuration signature algebra program result} :
        CleanupFrameStep table
          (.parked (.reenter ⟨⟨store, .yielded future⟩, cells, regions⟩ diagnostics))
          (.running (.reenter ⟨⟨store, future⟩, cells, regions⟩ diagnostics)) retained
    | cancelParked : before.cancelRunning reason = some after →
        CleanupFrameStep table (.parked before) (.parked after) retained
    | captureYield {future : Target.Configuration signature algebra program result} :
        CleanupFrameStep table
          (.running (.reenter ⟨⟨store, .yielded future⟩, cells, regions⟩ diagnostics))
          (.captured identity (.reenter ⟨⟨store, .yielded future⟩, cells, regions⟩ diagnostics)) retained
    | reattach : CleanupFrameStep table (.captured identity resolution) (.running resolution) retained
    | cancelCaptured : before.cancelRunning reason = some after →
        CleanupFrameStep table (.captured identity before) (.captured identity after) retained

  inductive CleanupFrameSteps (table : Target.Definitions signature algebra program) :
      CleanupFrameProgress signature algebra program result → Nat → CleanupFrameProgress signature algebra program result → (retained : List Reference := []) → Prop where
    | refl : CleanupFrameSteps table state 0 state retained
    | cons : CleanupFrameStep table before middle retained → CleanupFrameSteps table middle count after retained → CleanupFrameSteps table before (count + 1) after retained
  inductive ControlProgressStep (table : Target.Definitions signature algebra program) :
      ControlProgress signature algebra program answer → ControlProgress signature algebra program answer → (retained : List Reference := []) → Prop where
    | frames : CleanupFrameStep table before after retained →
        ControlProgressStep table (.frames identity before) (.frames identity after) retained
    | finishFrames : before.finishFrames = some after → ControlProgressStep table before after retained
    | returnedValue : ValueDisposalStep table before after retained →
        ControlProgressStep table (.returnedValue before) (.returnedValue after) retained
    | finishAnswer : work.finished = some runtime → ControlProgressStep table (.returnedValue work) (.complete runtime) retained

  inductive ControlProgressSteps (table : Target.Definitions signature algebra program) :
      ControlProgress signature algebra program answer → Nat → ControlProgress signature algebra program answer → (retained : List Reference := []) → Prop where
    | refl : ControlProgressSteps table state 0 state retained
    | cons : ControlProgressStep table before middle retained → ControlProgressSteps table middle count after retained →
        ControlProgressSteps table before (count + 1) after retained

end

end BoundaryV2.Generalized.ExitComposition
