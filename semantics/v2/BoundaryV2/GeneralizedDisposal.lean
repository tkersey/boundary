import BoundaryV2.GeneralizedRegionRetirement
import BoundaryV2.GeneralizedOwnedOperandLowering
import BoundaryV2.GeneralizedNestedCleanup

namespace BoundaryV2.Generalized

namespace UseScope

def disposeOwned (view : ControlView) (store : ControlStore Future) : Option (Acquisition Future) :=
  (release .explicit view store).bind beginDisposal

theorem dispose_owned_preserves_ownership (valid : ControlStore.Valid store)
    (accepted : disposeOwned view store = some result) : ControlStore.Valid result.store := by
  obtain ⟨released, releaseStep, beginStep⟩ := Option.bind_eq_some_iff.mp accepted
  exact begin_disposal_preserves_ownership (release_preserves_ownership valid releaseStep) beginStep

theorem dispose_owned_corresponds (related : SourceFuture → TargetFuture → Prop)
    (stores : ControlStore.Related related source target) (view : ControlView) :
    Option.Rel (Acquisition.Related related) (disposeOwned view source) (disposeOwned view target) := by
  have released := release_corresponds related stores .explicit view
  unfold disposeOwned
  generalize sourceAt : release .explicit view source = sourceReleased at released ⊢
  generalize targetAt : release .explicit view target = targetReleased at released ⊢
  cases released with
  | none => exact .none
  | some matching => exact begin_disposal_corresponds related matching

end UseScope

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

namespace Source

/-- Operand evaluation and authority consumption precede the handoff. The caller
is retained independently of the abandoned future's input and answer types. -/
structure DisposalStart (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  store : ControlHeap signature algebra program
  cells : Cells signature algebra (Computation signature algebra program)
  regions : List (Id .region)
  future : Sigma (ControlPayload signature algebra program)
  outside : Context signature algebra program .unit result

inductive DisposeEntry [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
    (table : Definitions signature algebra program) : State signature algebra program result →
    DisposalStart signature algebra program result → Prop where
  | enter {use : UseScope.OneShotUse}
      {expression : Expression signature algebra program context (.continuation mode use.type effect input answer)}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program .unit result}
      {cells : Cells signature algebra (Computation signature algebra program)} :
      ExpressionEvaluation bindings cells.reservations.custody store expression
        (.ok (.continuation view.identity (some (view.authority, view.owner)))) evaluated →
      UseScope.disposeOwned view evaluated = some started →
      DisposeEntry table ⟨⟨store, outside.plug (.evaluate (.dispose expression) bindings)⟩, cells, regions⟩
        ⟨started.store, cells, regions, started.future, outside⟩

end Source

namespace Target

structure DisposalStart (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  store : ControlHeap signature algebra program
  cells : Cells signature algebra (fun context result => Code signature algebra program context [] result)
  regions : List (Id .region)
  future : Sigma (ControlPayload signature algebra program)
  outside : Stack signature algebra program .unit result

inductive DisposeEntry (table : Definitions signature algebra program) : State signature algebra program result →
    DisposalStart signature algebra program result → Prop where
  | enter {use : UseScope.OneShotUse}
      {next : Code signature algebra program context (.unit :: operands) answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {values : RuntimeEnvironment signature algebra program operands}
      {outside : Stack signature algebra program answer result}
      {cells : Cells signature algebra (fun context result => Code signature algebra program context [] result)} :
      UseScope.disposeOwned view store = some started →
      DisposeEntry table ⟨⟨store, .code (.dispose (use := use.type) (mode := mode) (effect := effect) (input := input) next)
        bindings (.cons (.continuation view.identity (some (view.authority, view.owner))) values) outside⟩, cells, regions⟩
        ⟨started.store, cells, regions, started.future, .push (.returnTo next bindings values) outside⟩

/-- Only the inner unwind owns the current resources. The caller is first-order
continuation data, not an executable host callback or a duplicate runtime. -/
structure Disposal (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  answer : TypeOf signature
  progress : ExitComposition.UnwindProgress signature algebra program answer
  outside : Stack signature algebra program .unit result

def DisposalStart.begin (start : DisposalStart signature algebra program result) : Disposal signature algebra program result :=
  ⟨start.future.fst.answer, .seeking
    ⟨⟨0⟩, .finished .abandoned, start.store, start.cells, start.regions, ⟨.abandoned, [], none⟩⟩
    start.future.snd.future, start.outside⟩

def Disposal.finish (disposal : Disposal signature algebra program result) :
    Option (ExitComposition.Resolution signature algebra program result) :=
  match disposal.progress with
  | .complete runtime => match runtime.exit.primary with
    | .abandoned => some (.reenter ⟨⟨runtime.store, .returned (.datum .unit) disposal.outside⟩,
        runtime.cells, runtime.liveRegions⟩ { runtime.exit with primary := .normal })
    | .failure fault => some (.reenter ⟨⟨runtime.store, .failed fault disposal.outside⟩,
        runtime.cells, runtime.liveRegions⟩ runtime.exit)
    | .cancelled => some (.unwind runtime disposal.outside)
    | .normal => none
  | _ => none

inductive DisposalStep [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
    (table : Definitions signature algebra program) : Disposal signature algebra program result →
    List (Id .obligation) → Disposal signature algebra program result → Prop where
  | unwind {answer : TypeOf signature}
      {before after : ExitComposition.UnwindProgress signature algebra program answer}
      {outside : Stack signature algebra program .unit result} : ExitComposition.UnwindStep table before selected after →
      DisposalStep table ⟨answer, before, outside⟩ selected ⟨answer, after, outside⟩

inductive DisposalSteps [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
    (table : Definitions signature algebra program) : Disposal signature algebra program result →
    List (Id .obligation) → Disposal signature algebra program result → Prop where
  | refl : DisposalSteps table state [] state
  | cons : DisposalStep table before selected middle → DisposalSteps table middle rest after →
      DisposalSteps table before (selected ++ rest) after

theorem DisposalSteps.of_unwind [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
    {table : Definitions signature algebra program}
    {before after : ExitComposition.UnwindProgress signature algebra program answer}
    (outside : Stack signature algebra program .unit result)
    (steps : ExitComposition.UnwindSteps table before selected after) :
    DisposalSteps table ⟨answer, before, outside⟩ selected ⟨answer, after, outside⟩ := by
  induction steps with
  | refl => exact .refl
  | cons step rest induction => exact .cons (.unwind step) induction

theorem unfinished_disposal_cannot_return
    (outside : Stack signature algebra program .unit result)
    (runtime : ExitComposition.Runtime signature algebra program)
    (future : Stack signature algebra program input answer) :
    Disposal.finish ⟨answer, .seeking runtime future, outside⟩ = none := rfl

theorem cleanup_in_progress_cannot_return
    (outside : Stack signature algebra program .unit result)
    (scope : ExitComposition.ScopeExit signature algebra program answer) :
    Disposal.finish ⟨answer, .cleaning scope, outside⟩ = none := rfl

theorem completed_disposal_failure_keeps_history
    (outside : Stack signature algebra program .unit result)
    (runtime : ExitComposition.Runtime signature algebra program)
    (failed : runtime.exit.primary = .failure fault) :
    Disposal.finish ⟨answer, .complete runtime, outside⟩ =
      some (.reenter ⟨⟨runtime.store, .failed fault outside⟩, runtime.cells, runtime.liveRegions⟩ runtime.exit) := by
  simp only [Disposal.finish, failed]

end Target
end BoundaryV2.Generalized
