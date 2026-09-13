import BoundaryV2.GeneralizedStateExecution

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

/-- Closure application evaluates both operands before the handoff. Its owned
captures move into the active fields and the caller remains a separate frame. -/
theorem compiled_computation_application
    (table : Source.Definitions signature algebra program)
    (function : Source.Expression signature algebra program context (.computation use parameters answer))
    (arguments : Source.Arguments signature algebra program context parameters)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (body : Source.Computation signature algebra program (parameters ++ capturedTypes) answer)
    (captured : Source.RuntimeEnvironment signature algebra program capturedTypes)
    (actual : Source.RuntimeEnvironment signature algebra program parameters)
    (authority : Option (Id .custody × Owner))
    (functionAt : function.evaluate bindings = .ok (.closure body captured authority))
    (argumentsAt : arguments.evaluate bindings = .ok actual)
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (handoff : ComputationHandoff captured use authority sourceStore.fields fields)
    {sourceOutside : Source.Context signature algebra program answer result}
    {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region)) :
    Source.ExecutionStep table
      ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.apply function arguments) bindings)⟩, sourceCells, regions⟩
      ⟨⟨{ sourceStore with fields := fields }, sourceOutside.plug (Source.enterClosure body actual captured)⟩, sourceCells, regions⟩ ∧
    ∃ count, 0 < count ∧ Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (computation (.apply function arguments)) (environment bindings) .nil targetOutside⟩, cells sourceCells, regions⟩ count
      ⟨⟨{ targetStore with fields := fields }, .code (computation body) (environment (actual.append captured)) .nil
        (.push (.returnTo .ret (environment bindings) .nil) targetOutside)⟩, cells sourceCells, regions⟩ ∧
      CellStateRelated
        ⟨⟨{ sourceStore with fields := fields }, sourceOutside.plug (Source.enterClosure body actual captured)⟩, sourceCells, regions⟩
        ⟨⟨{ targetStore with fields := fields }, .code (computation body) (environment (actual.append captured)) .nil
          (.push (.returnTo .ret (environment bindings) .nil) targetOutside)⟩, cells sourceCells, regions⟩ := by
  have targetHandoff : ComputationHandoff (environment captured) use authority targetStore.fields fields := by
    simpa only [environment, ← stores.fields] using handoff.map (fun _ _ body => computation body)
  obtain ⟨functionCount, functionSteps⟩ := expression_drains function bindings (Defunctionalization.arguments arguments (.callClosure .ret)) .nil _ functionAt
  obtain ⟨argumentCount, argumentSteps⟩ := arguments_drains arguments bindings (.callClosure .ret)
    (.cons (value (.closure body captured authority)) .nil) actual argumentsAt
  refine ⟨.control (.application functionAt argumentsAt handoff)
    (.application functionAt argumentsAt handoff),
    functionCount + argumentCount + 1, by omega, ?_, ⟨⟨⟨rfl, stores.controls, stores.disposing⟩,
      .evaluate body (actual.append captured) (.passthrough bindings outside)⟩, rfl, rfl⟩⟩
  have prefixSteps := (functionSteps.trans argumentSteps).with_cells (definitions table) targetOutside targetStore (cells sourceCells) regions
  apply prefixSteps.in_execution.trans
  have entered := Target.ExecutionSteps.single (Target.ExecutionStep.control (table := definitions table)
    (cells := cells sourceCells) (regions := regions)
    (Target.OwnedStep.application (body := computation body) (arguments := environment actual) (next := .ret) (bindings := environment bindings)
      (values := .nil) (outside := targetOutside) targetHandoff)
    (Target.OwnedStep.NonAllocating.application (body := computation body) (arguments := environment actual)
      (next := .ret) (bindings := environment bindings) (values := .nil) (outside := targetOutside) targetHandoff))
  simpa only [Source.enterClosure, value, Value.map, environment, Environment.map_append] using entered

end BoundaryV2.Generalized.Defunctionalization
