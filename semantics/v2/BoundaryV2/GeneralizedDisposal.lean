import BoundaryV2.GeneralizedRegionRetirement
import BoundaryV2.GeneralizedOwnedOperandLowering

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

inductive DisposalProgress (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  | evaluating : State signature algebra program result → DisposalProgress signature algebra program result
  | disposing : Disposal signature algebra program result → DisposalProgress signature algebra program result
  | resolved : ExitComposition.Resolution signature algebra program result → DisposalProgress signature algebra program result

inductive DisposalRunStep [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
    (table : Definitions signature algebra program) : DisposalProgress signature algebra program result →
    DisposalProgress signature algebra program result → Prop where
  | evaluate : ExecutionStep table before after → DisposalRunStep table (.evaluating before) (.evaluating after)
  | enter : DisposeEntry table before start → DisposalRunStep table (.evaluating before) (.disposing start.begin)
  | operandFault {store : ControlHeap signature algebra program}
      {future : Stack signature algebra program input result}
      {cells : Cells signature algebra (fun context result => Code signature algebra program context [] result)} :
      DisposalRunStep table (.evaluating ⟨⟨store, .failed fault future⟩, cells, regions⟩)
        (.resolved (.reenter ⟨⟨store, .failed fault future⟩, cells, regions⟩ ⟨.failure fault, [], none⟩))
  | unwind : DisposalStep table before selected after → DisposalRunStep table (.disposing before) (.disposing after)
  | finish : disposal.finish = some result → DisposalRunStep table (.disposing disposal) (.resolved result)

inductive DisposalRun [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
    (table : Definitions signature algebra program) : DisposalProgress signature algebra program result →
    Nat → DisposalProgress signature algebra program result → Prop where
  | refl : DisposalRun table state 0 state
  | cons : DisposalRunStep table before middle → DisposalRun table middle count after → DisposalRun table before (count + 1) after

theorem DisposalRun.trans [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
    {table : Definitions signature algebra program}
    {before middle after : DisposalProgress signature algebra program result}
    (first : DisposalRun table before count middle) (second : DisposalRun table middle rest after) :
    DisposalRun table before (count + rest) after := by
  induction first with
  | refl => simpa using second
  | cons step tail induction =>
    simpa only [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using DisposalRun.cons step (induction second)

theorem DisposalRun.enter_after_operands [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
    {table : Definitions signature algebra program}
    {before after : State signature algebra program result} {start : DisposalStart signature algebra program result}
    (steps : ExecutionSteps table before count after) (entered : DisposeEntry table after start) :
    DisposalRun table (.evaluating before) (count + 1) (.disposing start.begin) := by
  induction steps with
  | refl => exact .cons (.enter entered) .refl
  | cons step rest induction => exact .cons (.evaluate step) (induction entered)

theorem DisposalRun.finish_after_unwind [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
    {table : Definitions signature algebra program}
    {before after : Disposal signature algebra program resultType}
    (steps : DisposalSteps table before selected after) (finished : after.finish = some result) :
    ∃ count, DisposalRun table (.disposing before) count (.resolved result) := by
  induction steps with
  | refl => exact ⟨1, .cons (.finish finished) .refl⟩
  | cons step rest induction =>
    obtain ⟨count, tail⟩ := induction finished
    exact ⟨count + 1, .cons (.unwind step) tail⟩

theorem DisposalRun.operand_failure [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
    {table : Definitions signature algebra program} {before : State signature algebra program result}
    {store : ControlHeap signature algebra program} {future : Stack signature algebra program input result}
    {cells : Cells signature algebra (fun context result => Code signature algebra program context [] result)}
    (steps : ExecutionSteps table before count ⟨⟨store, .failed fault future⟩, cells, regions⟩) :
    DisposalRun table (.evaluating before) (count + 1)
      (.resolved (.reenter ⟨⟨store, .failed fault future⟩, cells, regions⟩ ⟨.failure fault, [], none⟩)) := by
  have lift {length : Nat} {first last : State signature algebra program result} (executed : ExecutionSteps table first length last) :
      DisposalRun table (.evaluating first) length (.evaluating last) := by
    induction executed with
    | refl => exact .refl
    | cons step tail induction => exact .cons (.evaluate step) induction
  exact (lift steps).trans (.cons .operandFault .refl)

theorem resolved_disposal_has_no_second_transition [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
    (table : Definitions signature algebra program)
    {result : ExitComposition.Resolution signature algebra program resultType}
    {after : DisposalProgress signature algebra program resultType} :
    ¬ DisposalRunStep table (.resolved result) after := by intro step; cases step

end Target
end BoundaryV2.Generalized
