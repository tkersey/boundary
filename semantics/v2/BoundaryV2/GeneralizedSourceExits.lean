import BoundaryV2.GeneralizedCleanupCompletion
import BoundaryV2.GeneralizedStateObservations

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

/-- Local source exit steps coexist with ordinary source execution. Their
boundaries are actual source program constructors, not target observations. -/
inductive CleanupProgress (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  | running : ExitResolution signature algebra program result → CleanupProgress signature algebra program result
  | disposing : CleanupDisposal signature algebra program result → CleanupProgress signature algebra program result

def CompletedCleanup.progress : CompletedCleanup signature algebra program result → CleanupProgress signature algebra program result
  | .resolved resolution => .running resolution
  | .disposing work => .disposing work

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

end BoundaryV2.Generalized.Source
