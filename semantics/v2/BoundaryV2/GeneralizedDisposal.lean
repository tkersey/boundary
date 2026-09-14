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

end Target
end BoundaryV2.Generalized
