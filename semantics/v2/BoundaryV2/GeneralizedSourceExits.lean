import BoundaryV2.GeneralizedCleanupCompletion
import BoundaryV2.GeneralizedStateObservations
import BoundaryV2.GeneralizedSourceCancellation

namespace BoundaryV2.Generalized.Source

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

/-- Unwinding carries a completed local exit. Ongoing source cleanup remains
an ordinary higher-order program under its actual context. -/
structure ExitRuntime (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) where
  id : Id .obligation
  completion : ExitComposition.Completion algebra.Fault
  store : ControlHeap signature algebra program
  cells : Cells signature algebra (Computation signature algebra program)
  regions : List (Id .region)
  exit : ExitInfo algebra.Fault algebra.Reason

inductive ExitResolution (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  | reenter : State signature algebra program result → ExitInfo algebra.Fault algebra.Reason → ExitResolution signature algebra program result
  | unwind {input : TypeOf signature} : ExitRuntime signature algebra program →
      Context signature algebra program input result → ExitResolution signature algebra program result

def ExitResolution.cancelRunning (reason : algebra.Reason) :
    ExitResolution signature algebra program result → Option (ExitResolution signature algebra program result)
  | .reenter state diagnostics => (state.control.computation.cancelRunning reason).map fun computation =>
      .reenter { state with control := { state.control with computation := computation } } diagnostics
  | .unwind runtime outside => (outside.cancelRunning reason).map (.unwind runtime)

theorem ExitResolution.repeated_cancellation_keeps_running_work
    (first later : algebra.Reason) (before after : ExitResolution signature algebra program result)
    (accepted : before.cancelRunning first = some after) : after.cancelRunning later = some after := by
  cases before with
  | reenter state diagnostics =>
    obtain ⟨updated, found, same⟩ := Option.map_eq_some_iff.mp accepted
    cases same
    simp only [ExitResolution.cancelRunning,
      (Program.running_cancellation_stable first later state.control.computation).2 updated found, Option.map_some]
  | unwind runtime outside =>
    obtain ⟨updated, found, same⟩ := Option.map_eq_some_iff.mp accepted
    cases same
    simp only [ExitResolution.cancelRunning,
      (Context.running_cancellation_stable first later outside).2 updated found, Option.map_some]

structure CleanupDisposal (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  type : TypeOf signature
  value : RuntimeValue signature algebra program type
  runtime : ExitRuntime signature algebra program
  outside : Context signature algebra program type result

inductive CompletedCleanup (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  | resolved : ExitResolution signature algebra program result → CompletedCleanup signature algebra program result
  | disposing : CleanupDisposal signature algebra program result → CompletedCleanup signature algebra program result

/-- Source completion plugs the original source context. It never executes
or stores target code, and an owned saved result remains explicit work. -/
def reenterCleanupResult (identity : Id .obligation) (completion : ExitComposition.Completion algebra.Fault)
    (store : ControlHeap signature algebra program)
    (cells : Cells signature algebra (Computation signature algebra program)) (regions : List (Id .region))
    (outside : Context signature algebra program input result) :
    ExitComposition.CleanupResult signature algebra (Computation signature algebra program) input →
    CompletedCleanup signature algebra program result
  | .returned value exit => .resolved (.reenter ⟨⟨store, outside.plug (.returned value)⟩, cells, regions⟩ exit)
  | .exiting exit => match exit.primary with
    | .failure fault => .resolved (.reenter ⟨⟨store, outside.plug (.failed fault)⟩, cells, regions⟩ exit)
    | _ => .resolved (.unwind ⟨identity, completion, store, cells, regions, exit⟩ outside)
  | .disposing value exit => .disposing ⟨_, value, ⟨identity, completion, store, cells, regions, exit⟩, outside⟩

/-- The source begins cleanup beneath its own higher-order continuation and
preserves the authored exit independently of the cleanup body's diagnostics. -/
def beginExitCleanup (identity : Id .obligation)
    (cleanup : Computation signature algebra program (.exit :: context) .unit)
    (bindings : RuntimeEnvironment signature algebra program context)
    (store : ControlHeap signature algebra program)
    (cells : Cells signature algebra (Computation signature algebra program)) (regions : List (Id .region))
    (exit : ExitInfo algebra.Fault algebra.Reason) (outside : Context signature algebra program input result) :
    ExitResolution signature algebra program result :=
  .reenter ⟨⟨store, outside.plug (.cleaning identity none exit
    (.evaluate cleanup (.cons (.exit exit) bindings)))⟩, cells, regions⟩ ⟨.normal, [], none⟩

abbrev DisposalValues (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) := List (Sigma (RuntimeValue signature algebra program))

/-- Source region work keeps current storage with its actual higher-order
outside context. Previously offered nonowning cells remain readable. -/
structure RegionHandoff (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (input result : TypeOf signature) where
  identity : Id .region
  runtime : ExitRuntime signature algebra program
  outside : Context signature algebra program input result
  kept : List (Id .cell)

def RegionHandoff.offerNext (handoff : RegionHandoff signature algebra program input result) :
    Option ((Sigma (RuntimeValue signature algebra program)) × RegionHandoff signature algebra program input result) :=
  (Cells.takeOldest handoff.identity handoff.runtime.cells handoff.kept).map fun (cell, remaining) =>
    if cell.value.owningField.tokens.isEmpty then
      (⟨cell.type, cell.value⟩, { handoff with kept := cell.identity :: handoff.kept })
    else
      let fields := { handoff.runtime.store.fields with active := handoff.runtime.store.fields.active ++ [cell.value.owningField] }
      let runtime := { handoff.runtime with cells := remaining, store := { handoff.runtime.store with fields := fields } }
      (⟨cell.type, cell.value⟩, { handoff with runtime := runtime })

def retireUnwoundRegion (identity : Id .region) (runtime : ExitRuntime signature algebra program)
    (outside : Context signature algebra program input result) (external : List Reference) :
    Option (ExitResolution signature algebra program result) :=
  let remaining := runtime.cells.outsideRegions [identity]
  let support := storeReferences runtime.store ++ cellsReferences remaining ++ outside.referenceSupport ++ external
  if canRetireStorage [identity] runtime.regions runtime.cells support then
    some (.unwind { runtime with
      cells := remaining
      regions := runtime.regions.filter fun region => !([identity].contains region) } outside)
  else none

/- Source work retains source computations and higher-order contexts. The
mutual states expose ongoing control disposal and its remaining owned values. -/
mutual
  inductive CleanupProgress (signature : Signature) (algebra : LeafAlgebra signature.Data)
      (program : List (BodyType signature.Data signature.Effect)) : TypeOf signature → Type where
    | running : ExitResolution signature algebra program result → CleanupProgress signature algebra program result
    | parked : ExitResolution signature algebra program result → CleanupProgress signature algebra program result
    | captured : Id .control → ExitResolution signature algebra program result → CleanupProgress signature algebra program result
    | region : RegionDisposal signature algebra program result → CleanupProgress signature algebra program result
    | disposing : CleanupDisposal signature algebra program result → CleanupProgress signature algebra program result
    | values {input : TypeOf signature} : Id .obligation → ExitComposition.Completion algebra.Fault →
        Context signature algebra program input result → ValueDisposal signature algebra program → CleanupProgress signature algebra program result

  inductive ValueDisposal (signature : Signature) (algebra : LeafAlgebra signature.Data)
      (program : List (BodyType signature.Data signature.Effect)) where
    | ready : ExitRuntime signature algebra program → DisposalValues signature algebra program → ValueDisposal signature algebra program
    | control {answer : TypeOf signature} : ControlProgress signature algebra program answer →
        DisposalValues signature algebra program → ValueDisposal signature algebra program

  inductive ControlProgress (signature : Signature) (algebra : LeafAlgebra signature.Data)
      (program : List (BodyType signature.Data signature.Effect)) : TypeOf signature → Type where
    | frames : Id .obligation → CleanupProgress signature algebra program answer → ControlProgress signature algebra program answer
    | returnedValue : ValueDisposal signature algebra program → ControlProgress signature algebra program answer
    | complete : ExitRuntime signature algebra program → ControlProgress signature algebra program answer

  inductive RegionDisposal (signature : Signature) (algebra : LeafAlgebra signature.Data)
      (program : List (BodyType signature.Data signature.Effect)) : TypeOf signature → Type where
    | offering {input : TypeOf signature} : RegionHandoff signature algebra program input result → RegionDisposal signature algebra program result
    | disposing {input : TypeOf signature} : Id .region → Context signature algebra program input result →
        List (Id .cell) → ValueDisposal signature algebra program → RegionDisposal signature algebra program result
end

def ValueDisposal.start (runtime : ExitRuntime signature algebra program) (value : RuntimeValue signature algebra program type) :
    ValueDisposal signature algebra program := .ready runtime [⟨type, value⟩]

def ValueDisposal.finished : ValueDisposal signature algebra program → Option (ExitRuntime signature algebra program)
  | .ready runtime [] => some runtime
  | _ => none

def RegionDisposal.begin : ExitResolution signature algebra program result → Option (RegionDisposal signature algebra program result)
  | .unwind runtime future => match unwindBoundary future with
    | .region identity outside => some (.offering ⟨identity, runtime, outside, []⟩)
    | _ => none
  | _ => none

def RegionDisposal.offer : RegionDisposal signature algebra program result → Option (RegionDisposal signature algebra program result)
  | .offering handoff => handoff.offerNext.map fun (value, after) =>
      .disposing after.identity after.outside after.kept (ValueDisposal.start after.runtime value.snd)
  | _ => none

def RegionDisposal.returnValue : RegionDisposal signature algebra program result → Option (RegionDisposal signature algebra program result)
  | .disposing identity outside kept work => work.finished.map fun runtime => .offering ⟨identity, runtime, outside, kept⟩
  | _ => none

def RegionDisposal.finish (external : List Reference) :
    RegionDisposal signature algebra program result → Option (ExitResolution signature algebra program result)
  | .offering handoff => if handoff.offerNext.isNone then
      retireUnwoundRegion handoff.identity handoff.runtime handoff.outside external else none
  | _ => none

def ControlProgress.seeking (runtime : ExitRuntime signature algebra program)
    (outside : Context signature algebra program input answer) : ControlProgress signature algebra program answer :=
  .frames runtime.id (.running (.unwind runtime outside))

def CompletedCleanup.progress : CompletedCleanup signature algebra program result → CleanupProgress signature algebra program result
  | .resolved resolution => .running resolution
  | .disposing work => .disposing work

mutual
  inductive CleanupStep [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
      (table : Definitions signature algebra program) : CleanupProgress signature algebra program result →
      CleanupProgress signature algebra program result → (retained : List Reference := []) → Prop where
    | execute : ExecutionStep table before after retained →
        CleanupStep table (.running (.reenter before diagnostics)) (.running (.reenter after diagnostics)) retained
    | beginFailure {outside : Context signature algebra program input result} :
        CleanupStep table (.running (.reenter
          ⟨⟨store, outside.plug (.protection identity cleanup bindings (.failed fault))⟩, cells, regions⟩ diagnostics))
          (.running (beginExitCleanup identity cleanup bindings store cells regions
            ⟨.failure fault, diagnostics.failures, diagnostics.cancellation⟩ outside)) retained
    | beginUnwind {outside : Context signature algebra program input result} :
        CleanupStep table (.running (.unwind runtime (.push (.protection identity cleanup bindings) outside)))
          (.running (beginExitCleanup identity cleanup bindings runtime.store runtime.cells runtime.regions runtime.exit outside)) retained
    | unwindBind : CleanupStep table (.running (.unwind runtime (.push (.bind next description) outside)))
        (.running (.unwind runtime outside)) retained
    | unwindHandler : CleanupStep table (.running (.unwind runtime
        (.push (.handler effect mode identity returned clauses bindings) outside)))
        (.running (.unwind runtime outside)) retained
    | returned {outside : Context signature algebra program input result} :
        ExitComposition.finalizeCleanup original exit = some outcome →
        CleanupStep table (.running (.reenter
          ⟨⟨store, outside.plug (.cleaning identity original exit (.returned cleaned))⟩, cells, regions⟩ diagnostics))
          (reenterCleanupResult identity .returned store cells regions outside outcome).progress retained
    | failed {outside : Context signature algebra program input result} :
        ExitComposition.finalizeCleanup original (exit.nestedFailure fault diagnostics.failures diagnostics.cancellation) = some outcome →
        CleanupStep table (.running (.reenter
          ⟨⟨store, outside.plug (.cleaning identity original exit (.failed fault))⟩, cells, regions⟩ diagnostics))
          (reenterCleanupResult identity (.failed fault) store cells regions outside outcome).progress retained
    | unwound {outside : Context signature algebra program input result} :
        ExitComposition.finalizeCleanup original
          (match runtime.exit.primary with
            | .failure fault => exit.nestedFailure fault runtime.exit.failures runtime.exit.cancellation
            | _ => exit.nestedAbandon runtime.exit) = some outcome →
        CleanupStep table (.running (.unwind runtime (.push (.cleanupReturn identity original exit) outside)))
          (reenterCleanupResult identity .abandoned runtime.store runtime.cells runtime.regions outside outcome).progress retained
    | enterValues : CleanupStep table (.disposing work)
        (.values work.runtime.id work.runtime.completion work.outside (ValueDisposal.start work.runtime work.value)) retained
    | values : ValueDisposalStep table before after (outside.referenceSupport ++ retained) →
        CleanupStep table (.values identity completion outside before) (.values identity completion outside after) retained
    | finishValues : work.finished = some runtime →
        CleanupStep table (.values identity completion outside work)
          (reenterCleanupResult identity completion runtime.store runtime.cells runtime.regions outside (.exiting runtime.exit)).progress retained

    | cancel : before.cancelRunning reason = some after →
        CleanupStep table (.running before) (.running after) retained
    | parkYield {future : Program signature algebra program result} :
        CleanupStep table (.running (.reenter ⟨⟨store, .yielded future⟩, cells, regions⟩ diagnostics))
          (.parked (.reenter ⟨⟨store, .yielded future⟩, cells, regions⟩ diagnostics)) retained
    | continueYield {future : Program signature algebra program result} :
        CleanupStep table (.parked (.reenter ⟨⟨store, .yielded future⟩, cells, regions⟩ diagnostics))
          (.running (.reenter ⟨⟨store, future⟩, cells, regions⟩ diagnostics)) retained
    | cancelParked : before.cancelRunning reason = some after →
        CleanupStep table (.parked before) (.parked after) retained
    | captureYield {future : Program signature algebra program result} :
        CleanupStep table (.running (.reenter ⟨⟨store, .yielded future⟩, cells, regions⟩ diagnostics))
          (.captured identity (.reenter ⟨⟨store, .yielded future⟩, cells, regions⟩ diagnostics)) retained
    | reattach : CleanupStep table (.captured identity resolution) (.running resolution) retained
    | cancelCaptured : before.cancelRunning reason = some after →
        CleanupStep table (.captured identity before) (.captured identity after) retained
    | enterRegion : RegionDisposal.begin before = some after →
        CleanupStep table (.running before) (.region after) retained
    | region : RegionDisposalStep table before after retained →
        CleanupStep table (.region before) (.region after) retained
    | finishRegion : before.finish (retained ++ external) = some after →
        CleanupStep table (.region before) (.running after) retained


  inductive ValueDisposalStep [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
      (table : Definitions signature algebra program) :
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
      | closure {body : Computation signature algebra program (parameters ++ capturedTypes) result} :
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
              ⟨runtime.id, .abandoned, acquired.store, runtime.cells, runtime.regions, runtime.exit⟩
              acquired.future.snd.future) rest) retained
      | control : ControlProgressStep table before after
            (rest.flatMap (fun value => Source.valueReferences value.snd) ++ retained) →
          ValueDisposalStep table (.control before rest) (.control after rest) retained
      | finishControl : ValueDisposalStep table (.control (.complete runtime) rest) (.ready runtime rest) retained

  inductive ControlProgressStep [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
      (table : Definitions signature algebra program) :
      ControlProgress signature algebra program answer → ControlProgress signature algebra program answer → (retained : List Reference := []) → Prop where
    | frames : CleanupStep table before after retained →
        ControlProgressStep table (.frames identity before) (.frames identity after) retained
    | unwindDone : ControlProgressStep table (.frames identity (.running (.unwind runtime .done))) (.complete runtime) retained
    | returned {value : RuntimeValue signature algebra program answer} :
        ControlProgressStep table (.frames identity (.running (.reenter ⟨⟨store, .returned value⟩, cells, regions⟩ diagnostics)))
          (.returnedValue (ValueDisposal.start ⟨identity, .returned, store, cells, regions, diagnostics⟩ value)) retained
    | failed : ControlProgressStep table (.frames identity (.running (.reenter ⟨⟨store, .failed fault⟩, cells, regions⟩ diagnostics)))
        (.complete ⟨identity, .failed fault, store, cells, regions, { diagnostics with primary := .failure fault }⟩) retained
    | answerStep : ValueDisposalStep table before after retained →
        ControlProgressStep table (.returnedValue before) (.returnedValue after) retained
    | finishAnswer : work.finished = some runtime → ControlProgressStep table (.returnedValue work) (.complete runtime) retained

  inductive RegionDisposalStep [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
      (table : Definitions signature algebra program) :
      RegionDisposal signature algebra program result → RegionDisposal signature algebra program result → (retained : List Reference := []) → Prop where
    | offer : before.offer = some after → RegionDisposalStep table before after retained
    | values : ValueDisposalStep table before after (outside.referenceSupport ++ retained) →
        RegionDisposalStep table (.disposing identity outside kept before) (.disposing identity outside kept after) retained
    | returnValue : before.returnValue = some after → RegionDisposalStep table before after retained

end

inductive CleanupSteps [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
    (table : Definitions signature algebra program) : CleanupProgress signature algebra program result →
    Nat → CleanupProgress signature algebra program result → (retained : List Reference := []) → Prop where
  | refl : CleanupSteps table state 0 state retained
  | cons : CleanupStep table before middle retained → CleanupSteps table middle count after retained →
      CleanupSteps table before (count + 1) after retained

theorem CleanupSteps.of_execution [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
    {table : Definitions signature algebra program}
    (steps : ExecutionSteps table before count after retained) (diagnostics : ExitInfo algebra.Fault algebra.Reason) :
    CleanupSteps table (.running (.reenter before diagnostics)) count (.running (.reenter after diagnostics)) retained := by
  induction steps with
  | refl => exact .refl
  | cons step tail induction => exact .cons (.execute step) induction

inductive ValueDisposalSteps [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
    (table : Definitions signature algebra program) : ValueDisposal signature algebra program →
    Nat → ValueDisposal signature algebra program → (retained : List Reference := []) → Prop where
  | refl : ValueDisposalSteps table state 0 state retained
  | cons : ValueDisposalStep table before middle retained → ValueDisposalSteps table middle count after retained →
      ValueDisposalSteps table before (count + 1) after retained

inductive ControlProgressSteps [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
    (table : Definitions signature algebra program) : ControlProgress signature algebra program answer →
    Nat → ControlProgress signature algebra program answer → (retained : List Reference := []) → Prop where
  | refl : ControlProgressSteps table state 0 state retained
  | cons : ControlProgressStep table before middle retained → ControlProgressSteps table middle count after retained →
      ControlProgressSteps table before (count + 1) after retained

inductive RegionDisposalSteps [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
    (table : Definitions signature algebra program) : RegionDisposal signature algebra program result →
    Nat → RegionDisposal signature algebra program result → (retained : List Reference := []) → Prop where
  | refl : RegionDisposalSteps table state 0 state retained
  | cons : RegionDisposalStep table before middle retained → RegionDisposalSteps table middle count after retained →
      RegionDisposalSteps table before (count + 1) after retained

theorem CleanupSteps.trans [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
    {table : Definitions signature algebra program}
    (first : CleanupSteps table before count middle retained) (second : CleanupSteps table middle rest after retained) :
    CleanupSteps table before (count + rest) after retained := by
  induction first with
  | refl => simpa using second
  | cons step tail induction =>
    simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using CleanupSteps.cons step (induction second)

theorem CleanupSteps.of_region [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
    {table : Definitions signature algebra program}
    (steps : RegionDisposalSteps table before count after retained) :
    CleanupSteps table (.region before) count (.region after) retained := by
  induction steps with
  | refl => exact .refl
  | cons step tail induction => exact .cons (.region step) induction

end BoundaryV2.Generalized.Source
