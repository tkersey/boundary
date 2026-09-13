import BoundaryV2.GeneralizedStateExecution
import BoundaryV2.GeneralizedOwnedOperandLowering

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

theorem compiled_owned_operand_return
    (table : Source.Definitions signature algebra program)
    (expression : Source.Expression signature algebra program context answer)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (returned : Source.RuntimeValue signature algebra program answer)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore sourceAfter : Source.ControlHeap signature algebra program}
    {targetStore : Target.ControlHeap signature algebra program}
    (evaluated : Source.ExpressionEvaluation bindings sourceCells.reservations.custody sourceStore expression (.ok returned) sourceAfter)
    (stores : ControlHeapRelated sourceStore targetStore)
    {sourceOutside : Source.Context signature algebra program answer result}
    {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    Source.ExecutionStep table
      ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.returnValue expression) bindings)⟩, sourceCells, regions⟩
      ⟨⟨sourceAfter, sourceOutside.plug (.returned returned)⟩, sourceCells, regions⟩ ∧
    ∃ count targetAfter, 0 < count ∧ Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (computation (.returnValue expression)) (environment bindings) .nil targetOutside⟩, cells sourceCells, regions⟩ count
      ⟨⟨targetAfter, .returned (value returned) targetOutside⟩, cells sourceCells, regions⟩ ∧
      CellStateRelated ⟨⟨sourceAfter, sourceOutside.plug (.returned returned)⟩, sourceCells, regions⟩
        ⟨⟨targetAfter, .returned (value returned) targetOutside⟩, cells sourceCells, regions⟩ := by
  obtain ⟨count, targetAfter, _, operands, related⟩ := owned_expression_drains
    (UseScope.PackedControlRelated controlPayloadRelated) bindings sourceCells.reservations.custody
    expression returned evaluated .ret .nil stores
  have reservations : (cells sourceCells).reservations = sourceCells.reservations := Cells.reservations_mapBodies _ sourceCells
  rw [← reservations] at operands
  refine ⟨.returnOperand evaluated, count + 1, targetAfter, by omega, ?_, ⟨⟨related, .returned returned outside⟩, rfl, rfl⟩⟩
  exact (operands.in_execution (definitions table) targetOutside (cells sourceCells) regions).trans
    (.single (.cell (.ordinary .returned)))

/-- A failed operand prefix enters exit with the store it actually produced.
The enclosing scopes and their pending cleanup remain attached. -/
theorem compiled_owned_operand_failure
    (table : Source.Definitions signature algebra program)
    (body : Source.Computation signature algebra program context answer)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (fault : algebra.Fault)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore sourceAfter : Source.ControlHeap signature algebra program}
    {targetStore : Target.ControlHeap signature algebra program}
    (evaluated : Source.ArgumentsEvaluation bindings sourceCells.reservations.custody sourceStore body.operandPrefix.arguments (.error fault) sourceAfter)
    (stores : ControlHeapRelated sourceStore targetStore)
    {sourceOutside : Source.Context signature algebra program answer result}
    {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    Source.ExecutionStep table
      ⟨⟨sourceStore, sourceOutside.plug (.evaluate body bindings)⟩, sourceCells, regions⟩
      ⟨⟨sourceAfter, sourceOutside.plug (.failed fault)⟩, sourceCells, regions⟩ ∧
    ∃ count targetAfter, 0 < count ∧ Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (computation body) (environment bindings) .nil targetOutside⟩, cells sourceCells, regions⟩ count
      ⟨⟨targetAfter, .failed fault targetOutside⟩, cells sourceCells, regions⟩ ∧
      CellStateRelated ⟨⟨sourceAfter, sourceOutside.plug (.failed fault)⟩, sourceCells, regions⟩
        ⟨⟨targetAfter, .failed fault targetOutside⟩, cells sourceCells, regions⟩ := by
  obtain ⟨count, targetAfter, final, operands, faulted, related⟩ := owned_computation_operand_fault_drains
    (UseScope.PackedControlRelated controlPayloadRelated) bindings sourceCells.reservations.custody body fault evaluated stores
  have reservations : (cells sourceCells).reservations = sourceCells.reservations := Cells.reservations_mapBodies _ sourceCells
  rw [← reservations] at operands
  cases faulted
  refine ⟨.operandFault evaluated, count + 1, targetAfter, by omega, ?_, ⟨⟨related, .failed fault outside⟩, rfl, rfl⟩⟩
  exact (operands.in_execution (definitions table) targetOutside (cells sourceCells) regions).trans
    (.single (.cell (.ordinary .fault)))

/-- Operand allocation and the application handoff occur in one source
transition and a positive finite target run. Both use the live cell support. -/
theorem compiled_owned_operand_application
    (table : Source.Definitions signature algebra program)
    (function : Source.Expression signature algebra program context (.computation use parameters answer))
    (arguments : Source.Arguments signature algebra program context parameters)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (body : Source.Computation signature algebra program (parameters ++ capturedTypes) answer)
    (captured : Source.RuntimeEnvironment signature algebra program capturedTypes)
    (actual : Source.RuntimeEnvironment signature algebra program parameters)
    (authority : Option (Id .custody × Owner))
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore sourceEvaluated : Source.ControlHeap signature algebra program}
    {targetStore : Target.ControlHeap signature algebra program}
    (evaluated : Source.ArgumentsEvaluation bindings sourceCells.reservations.custody sourceStore (.cons function arguments)
      (.ok (.cons (.closure body captured authority) actual)) sourceEvaluated)
    (handoff : ComputationHandoff captured use authority sourceEvaluated.fields fields)
    (stores : ControlHeapRelated sourceStore targetStore)
    {sourceOutside : Source.Context signature algebra program answer result}
    {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    Source.ExecutionStep table
      ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.apply function arguments) bindings)⟩, sourceCells, regions⟩
      ⟨⟨{ sourceEvaluated with fields := fields }, sourceOutside.plug (Source.enterClosure body actual captured)⟩, sourceCells, regions⟩ ∧
    ∃ count, 0 < count ∧ Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (computation (.apply function arguments)) (environment bindings) .nil targetOutside⟩, cells sourceCells, regions⟩ count
      ⟨⟨{ targetStore with fields := fields }, .code (computation body) (environment (actual.append captured)) .nil
        (.push (.returnTo .ret (environment bindings) .nil) targetOutside)⟩, cells sourceCells, regions⟩ ∧
      CellStateRelated
        ⟨⟨{ sourceEvaluated with fields := fields }, sourceOutside.plug (Source.enterClosure body actual captured)⟩, sourceCells, regions⟩
        ⟨⟨{ targetStore with fields := fields }, .code (computation body) (environment (actual.append captured)) .nil
          (.push (.returnTo .ret (environment bindings) .nil) targetOutside)⟩, cells sourceCells, regions⟩ := by
  refine ⟨.applicationOperands evaluated handoff, ?_⟩
  cases evaluated with
  | cons functionStep argumentStep =>
    obtain ⟨functionCount, middleTarget, _, functionSteps, middleRelated⟩ := owned_expression_drains
      (UseScope.PackedControlRelated controlPayloadRelated) bindings sourceCells.reservations.custody function
      (.closure body captured authority) functionStep (Defunctionalization.arguments arguments (.callClosure .ret)) .nil stores
    obtain ⟨argumentCount, targetEvaluated, argumentSteps, evaluatedRelated⟩ := owned_arguments_drains
      (UseScope.PackedControlRelated controlPayloadRelated) bindings sourceCells.reservations.custody arguments actual
      argumentStep (.callClosure .ret) (.cons (value (.closure body captured authority)) .nil) middleRelated
    have targetHandoff : ComputationHandoff (environment captured) use authority targetEvaluated.fields fields := by
      simpa only [environment, ← evaluatedRelated.fields] using handoff.map (fun _ _ body => computation body)
    have operands := functionSteps.trans argumentSteps
    have reservations : (cells sourceCells).reservations = sourceCells.reservations := Cells.reservations_mapBodies _ sourceCells
    rw [← reservations] at operands
    have replaced : { targetEvaluated with fields := fields } = { targetStore with fields := fields } :=
      congrArg (fun store => { store with fields := fields }) operands.store_is_field_update
    refine ⟨functionCount + argumentCount + 1, by omega, ?_, ?_⟩
    · rw [← replaced]
      apply (operands.in_execution (definitions table) targetOutside (cells sourceCells) regions).trans
      have entered := Target.ExecutionSteps.single (Target.ExecutionStep.control (table := definitions table)
        (cells := cells sourceCells) (regions := regions)
        (Target.OwnedStep.application (body := computation body) (arguments := environment actual) (next := .ret)
          (bindings := environment bindings) (values := .nil) (outside := targetOutside) targetHandoff))
      simpa only [Source.enterClosure, value, Value.map, environment, Environment.map_append] using entered
    · rw [← replaced]
      exact ⟨⟨⟨rfl, evaluatedRelated.controls, evaluatedRelated.disposing⟩,
        .evaluate body (actual.append captured) (.passthrough bindings outside)⟩, rfl, rfl⟩

end BoundaryV2.Generalized.Defunctionalization
