import BoundaryV2.GeneralizedCleanupCompletion

namespace BoundaryV2.Generalized.Target

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

/-- The abandoned future executes through the common handler-aware frame
rules. Only its caller is kept outside that execution. -/
structure Disposal (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  answer : TypeOf signature
  progress : ExitComposition.ControlProgress signature algebra program answer
  outside : Stack signature algebra program .unit result

def DisposalStart.begin (start : DisposalStart signature algebra program result) : Disposal signature algebra program result :=
  ⟨start.future.fst.answer, ExitComposition.ControlProgress.seeking
    ⟨⟨0⟩, .finished .abandoned, start.store, start.cells, start.regions, ⟨.abandoned, [], none⟩⟩
    start.future.snd.future, start.outside⟩

def Disposal.finish (disposal : Disposal signature algebra program result) :
    Option (ExitComposition.Resolution signature algebra program result) :=
  match disposal.progress with
  | .complete runtime => match runtime.exit.primary with
    | .normal | .abandoned => some (.reenter ⟨⟨runtime.store, .returned (.datum .unit) disposal.outside⟩,
        runtime.cells, runtime.liveRegions⟩ { runtime.exit with primary := .normal })
    | .failure fault => some (.reenter ⟨⟨runtime.store, .failed fault disposal.outside⟩,
        runtime.cells, runtime.liveRegions⟩ runtime.exit)
    | .cancelled => some (.unwind runtime disposal.outside)
  | _ => none

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
  | dispose {before after : ExitComposition.ControlProgress signature algebra program answer}
      {outside : Stack signature algebra program .unit result} :
      ExitComposition.ControlProgressStep table before after outside.installationReferences →
      DisposalRunStep table (.disposing ⟨answer, before, outside⟩) (.disposing ⟨answer, after, outside⟩)
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
  induction count generalizing before after with
  | zero => cases steps; exact .cons (.enter entered) .refl
  | succ count induction =>
    cases steps with
    | cons step rest => exact .cons (.evaluate step) (induction rest entered)

theorem DisposalRun.control_steps [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
    {table : Definitions signature algebra program}
    {before after : ExitComposition.ControlProgress signature algebra program answer}
    (outside : Stack signature algebra program .unit result)
    (steps : ExitComposition.ControlProgressSteps table before count after outside.installationReferences) :
    DisposalRun table (.disposing ⟨answer, before, outside⟩) count (.disposing ⟨answer, after, outside⟩) := by
  induction count generalizing before with
  | zero => cases steps; exact .refl
  | succ count induction =>
    cases steps with
    | cons step tail => exact .cons (.dispose step) (induction tail)

theorem DisposalRun.frame_steps [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
    {table : Definitions signature algebra program}
    {before after : ExitComposition.CleanupFrameProgress signature algebra program answer}
    (identity : Id .obligation) (outside : Stack signature algebra program .unit result)
    (steps : ExitComposition.CleanupFrameSteps table before count after outside.installationReferences) :
    DisposalRun table (.disposing ⟨answer, .frames identity before, outside⟩) count
      (.disposing ⟨answer, .frames identity after, outside⟩) := by
  induction count generalizing before with
  | zero => cases steps; exact .refl
  | succ count induction =>
    cases steps with
    | cons step tail => exact .cons (.dispose (.frames step)) (induction tail)

theorem DisposalRun.operand_failure [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
    {table : Definitions signature algebra program} {before : State signature algebra program result}
    {store : ControlHeap signature algebra program} {future : Stack signature algebra program input result}
    {cells : Cells signature algebra (fun context result => Code signature algebra program context [] result)}
    (steps : ExecutionSteps table before count ⟨⟨store, .failed fault future⟩, cells, regions⟩) :
    DisposalRun table (.evaluating before) (count + 1)
      (.resolved (.reenter ⟨⟨store, .failed fault future⟩, cells, regions⟩ ⟨.failure fault, [], none⟩)) := by
  have lift {length : Nat} {first last : State signature algebra program result} (executed : ExecutionSteps table first length last) :
      DisposalRun table (.evaluating first) length (.evaluating last) := by
    induction length generalizing first last with
    | zero => cases executed; exact .refl
    | succ length induction =>
      cases executed with
      | cons step tail => exact .cons (.evaluate step) (induction tail)
  exact (lift steps).trans (.cons .operandFault .refl)

theorem resolved_disposal_has_no_second_transition [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]
    (table : Definitions signature algebra program)
    {result : ExitComposition.Resolution signature algebra program resultType}
    {after : DisposalProgress signature algebra program resultType} :
    ¬ DisposalRunStep table (.resolved result) after := by intro step; cases step

end BoundaryV2.Generalized.Target

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

structure DisposalStartRelated (source : Source.DisposalStart signature algebra program result)
    (target : Target.DisposalStart signature algebra program result) : Prop where
  stores : ControlHeapRelated source.store target.store
  cells : target.cells = Defunctionalization.cells source.cells
  regions : target.regions = source.regions
  future : UseScope.PackedControlRelated controlPayloadRelated source.future target.future
  outside : ContextRelated signature algebra program source.outside target.outside

/-- Both sides evaluate the owned operand before releasing its actual authority.
The target's finite operand drain leads to disposal, not an early unit return. -/
theorem compiled_disposal_entry
    (table : Source.Definitions signature algebra program) (use : UseScope.OneShotUse)
    (expression : Source.Expression signature algebra program context (.continuation mode use.type effect input answer))
    (bindings : Source.RuntimeEnvironment signature algebra program context) (view : UseScope.ControlView)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore evaluated : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (operands : Source.ExpressionEvaluation bindings sourceCells.reservations.custody sourceStore expression
      (.ok (.continuation view.identity (some (view.authority, view.owner)))) evaluated)
    (stores : ControlHeapRelated sourceStore targetStore)
    (started : UseScope.Acquisition (Sigma (Source.ControlPayload signature algebra program)))
    (released : UseScope.disposeOwned view evaluated = some started)
    {sourceOutside : Source.Context signature algebra program .unit result}
    {targetOutside : Target.Stack signature algebra program .unit result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    Source.DisposeEntry table
      ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.dispose expression) bindings)⟩, sourceCells, regions⟩
      ⟨started.store, sourceCells, regions, started.future, sourceOutside⟩ ∧
    ∃ targetStart count, 0 < count ∧ DisposalStartRelated
      ⟨started.store, sourceCells, regions, started.future, sourceOutside⟩ targetStart ∧
      Target.DisposalRun (definitions table)
        (.evaluating ⟨⟨targetStore, .code (computation (.dispose expression)) (environment bindings) .nil targetOutside⟩,
          cells sourceCells, regions⟩) count (.disposing targetStart.begin) := by
  obtain ⟨count, targetEvaluated, _, steps, related⟩ := owned_expression_drains
    (UseScope.PackedControlRelated controlPayloadRelated) bindings sourceCells.reservations.custody
    expression (.continuation view.identity (some (view.authority, view.owner))) operands (.dispose .ret) .nil stores
  have reservations : (cells sourceCells).reservations = sourceCells.reservations := Cells.reservations_mapBodies _ sourceCells
  rw [← reservations] at steps
  have matching := UseScope.dispose_owned_corresponds (UseScope.PackedControlRelated controlPayloadRelated) related view
  obtain ⟨targetStarted, targetAccepted, joined⟩ := corresponding_acceptance matching released
  refine ⟨.enter operands released,
    ⟨targetStarted.store, cells sourceCells, regions, targetStarted.future,
      .push (.returnTo .ret (environment bindings) .nil) targetOutside⟩, count + 1, by omega,
    ⟨joined.store, rfl, rfl, joined.future, .passthrough bindings outside⟩, ?_⟩
  apply Target.DisposalRun.enter_after_operands (steps.in_execution (definitions table) targetOutside (cells sourceCells) regions)
  exact Target.DisposeEntry.enter (use := use) (next := .ret) (bindings := environment bindings)
    (values := .nil) (outside := targetOutside) (cells := cells sourceCells) targetAccepted

end BoundaryV2.Generalized.Defunctionalization
