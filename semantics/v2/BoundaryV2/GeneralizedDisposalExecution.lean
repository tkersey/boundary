import BoundaryV2.GeneralizedDisposal

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
