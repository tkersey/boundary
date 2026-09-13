import BoundaryV2.GeneralizedStateExecution

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

/-- Both operands finish before either authority is used. The closure handoff
and continuation acquisition form one accepted state transition; cells and the
clause caller survive while the body runs in the restored use-site context. -/
theorem compiled_computation_injection
    (table : Source.Definitions signature algebra program) (use : UseScope.OneShotUse)
    (continuation : Source.Expression signature algebra program context (.continuation mode use.type effect input answer))
    (injected : Source.Expression signature algebra program context (.computation bodyUse [] input))
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (body : Source.Computation signature algebra program capturedTypes input)
    (captured : Source.RuntimeEnvironment signature algebra program capturedTypes)
    (authority : Option (Id .custody × Owner)) (view : UseScope.ControlView)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore sourceEvaluated : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (evaluated : Source.ArgumentsEvaluation bindings sourceCells.reservations.custody sourceStore (.cons continuation (.cons injected .nil))
      (.ok (.cons (.continuation view.identity (some (view.authority, view.owner))) (.cons (.closure body captured authority) .nil))) sourceEvaluated)
    (stores : ControlHeapRelated sourceStore targetStore)
    (handoff : ComputationHandoff captured bodyUse authority sourceEvaluated.fields fields)
    {sourceOutside : Source.Context signature algebra program answer result}
    {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (accepted : Source.injectControl ⟨mode, effect, input, answer⟩ view { sourceEvaluated with fields := fields }
      body captured sourceOutside = some sourceAfter) :
    ∃ targetAfter count, 0 < count ∧
      CellStateRelated ⟨sourceAfter, sourceCells, regions⟩ ⟨targetAfter, cells sourceCells, regions⟩ ∧
      Source.ExecutionStep table
        ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.inject continuation injected) bindings)⟩, sourceCells, regions⟩
        ⟨sourceAfter, sourceCells, regions⟩ ∧
      Target.ExecutionSteps (definitions table)
        ⟨⟨targetStore, .code (computation (.inject continuation injected)) (environment bindings) .nil targetOutside⟩, cells sourceCells, regions⟩
        count ⟨targetAfter, cells sourceCells, regions⟩ := by
  obtain ⟨count, targetEvaluated, operands, evaluatedRelated⟩ := owned_two_operands_drains
    (UseScope.PackedControlRelated controlPayloadRelated) bindings sourceCells.reservations.custody continuation injected
    (.continuation view.identity (some (view.authority, view.owner))) (.closure body captured authority) evaluated (.inject .ret) stores
  have updatedStores : ControlHeapRelated { sourceEvaluated with fields := fields } { targetEvaluated with fields := fields } :=
    ⟨rfl, evaluatedRelated.controls, evaluatedRelated.disposing⟩
  have targetHandoff : ComputationHandoff (environment captured) bodyUse authority targetEvaluated.fields fields := by
    simpa only [environment, ← evaluatedRelated.fields] using handoff.map (fun _ _ body => computation body)
  obtain ⟨targetAfter, targetAccepted, matched⟩ := corresponding_acceptance
    (inject_control_corresponds updatedStores ⟨mode, effect, input, answer⟩ view body captured (.passthrough bindings outside)) accepted
  refine ⟨targetAfter, count + 1, by omega, ⟨matched, rfl, rfl⟩,
    .control (.injection evaluated handoff accepted), ?_⟩
  have reservations : (cells sourceCells).reservations = sourceCells.reservations := Cells.reservations_mapBodies _ sourceCells
  rw [← reservations] at operands
  exact (operands.in_execution (definitions table) targetOutside (cells sourceCells) regions).trans
    (.single (.control (.injection targetHandoff targetAccepted)))

end BoundaryV2.Generalized.Defunctionalization
