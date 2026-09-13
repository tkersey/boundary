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
    (continuationAt : continuation.evaluate bindings = .ok (.continuation view.identity (some (view.authority, view.owner))))
    (bodyAt : injected.evaluate bindings = .ok (.closure body captured authority))
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (handoff : ComputationHandoff captured bodyUse authority sourceStore.fields fields)
    {sourceOutside : Source.Context signature algebra program answer result}
    {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    (accepted : Source.injectControl ⟨mode, effect, input, answer⟩ view { sourceStore with fields := fields }
      body captured sourceOutside = some sourceAfter) :
    ∃ targetAfter count, 0 < count ∧
      CellStateRelated ⟨sourceAfter, sourceCells, regions⟩ ⟨targetAfter, cells sourceCells, regions⟩ ∧
      Source.ExecutionStep table
        ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.inject continuation injected) bindings)⟩, sourceCells, regions⟩
        ⟨sourceAfter, sourceCells, regions⟩ ∧
      Target.ExecutionSteps (definitions table)
        ⟨⟨targetStore, .code (computation (.inject continuation injected)) (environment bindings) .nil targetOutside⟩, cells sourceCells, regions⟩
        count ⟨targetAfter, cells sourceCells, regions⟩ := by
  have updatedStores : ControlHeapRelated { sourceStore with fields := fields } { targetStore with fields := fields } :=
    ⟨rfl, stores.controls, stores.disposing⟩
  have targetHandoff : ComputationHandoff (environment captured) bodyUse authority targetStore.fields fields := by
    simpa only [environment, ← stores.fields] using handoff.map (fun _ _ body => computation body)
  obtain ⟨targetAfter, targetAccepted, matched⟩ := corresponding_acceptance
    (inject_control_corresponds updatedStores ⟨mode, effect, input, answer⟩ view body captured (.passthrough bindings outside)) accepted
  obtain ⟨firstCount, firstSteps⟩ := expression_drains continuation bindings (expression injected (.inject .ret)) .nil _ continuationAt
  obtain ⟨secondCount, secondSteps⟩ := expression_drains injected bindings (.inject .ret)
    (.cons (.continuation view.identity (some (view.authority, view.owner))) .nil) _ bodyAt
  refine ⟨targetAfter, firstCount + secondCount + 1, by omega, ⟨matched, rfl, rfl⟩,
    .control (.injection continuationAt bodyAt handoff accepted)
      (.injection (continuation := continuationAt) (body := bodyAt) (handoff := handoff) (accepted := accepted)), ?_⟩
  have prefixSteps := (firstSteps.trans secondSteps).with_cells (definitions table) targetOutside
    targetStore (cells sourceCells) regions
  exact prefixSteps.in_execution.trans (.single (.control (.injection targetHandoff targetAccepted)
    (.injection (handoff := targetHandoff) (accepted := targetAccepted))))

end BoundaryV2.Generalized.Defunctionalization
