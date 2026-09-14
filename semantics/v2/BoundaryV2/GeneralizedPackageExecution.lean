import BoundaryV2.GeneralizedStateExecution
import BoundaryV2.GeneralizedOwnedOperandLowering

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

variable {retained : List Reference}

theorem compiled_package
    (table : Source.Definitions signature algebra program)
    (expression : Source.Expression signature algebra program context content)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (inner : Source.RuntimeValue signature algebra program content) (owner : Owner)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore sourceEvaluated : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (evaluated : Source.ExpressionEvaluation bindings (sourceCells.reservations.withSupport retained).custody sourceStore expression (.ok inner) sourceEvaluated)
    (moved : UseScope.State) (handoff : ValueHandoff inner sourceEvaluated.fields moved)
    (stores : ControlHeapRelated sourceStore targetStore)
    {sourceOutside : Source.Context signature algebra program (.package content) result}
    {targetOutside : Target.Stack signature algebra program (.package content) result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    let created := createPackage inner owner sourceEvaluated moved handoff (sourceCells.reservations.withSupport retained).custody
    Source.ExecutionStep (retained := retained) table
      ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.package expression) bindings)⟩, sourceCells, regions⟩
      ⟨⟨created.store, sourceOutside.plug (.returned created.value)⟩, sourceCells, regions⟩ ∧
    ∃ count targetAfter, 0 < count ∧ Target.ExecutionSteps (retained := retained) (definitions table)
      ⟨⟨targetStore, .code (computation (.package expression)) (environment bindings) .nil targetOutside⟩,
        cells sourceCells, regions⟩ count targetAfter ∧
      CellStateRelated ⟨⟨created.store, sourceOutside.plug (.returned created.value)⟩, sourceCells, regions⟩ targetAfter := by
  dsimp only
  obtain ⟨count, targetEvaluated, _, operands, related⟩ := owned_expression_drains
    (UseScope.PackedControlRelated controlPayloadRelated) bindings (sourceCells.reservations.withSupport retained).custody
    expression inner evaluated (.package .ret) .nil stores
  have reservations : ((cells sourceCells).reservations.withSupport retained) = (sourceCells.reservations.withSupport retained) := Cells.reservations_with_support_mapBodies _ sourceCells retained
  rw [← reservations] at operands
  have targetHandoff : ValueHandoff (value inner) targetEvaluated.fields moved := by
    rw [← related.fields]
    exact handoff.map (fun _ _ body => computation body)
  let sourceCreated := createPackage inner owner sourceEvaluated moved handoff (sourceCells.reservations.withSupport retained).custody
  let targetCreated := createPackage (value inner) owner targetEvaluated moved targetHandoff (sourceCells.reservations.withSupport retained).custody
  have created := package_creation_corresponds (UseScope.PackedControlRelated controlPayloadRelated)
    (fun _ _ body => computation body) inner owner (sourceCells.reservations.withSupport retained).custody related handoff targetHandoff
  have packageStep : Target.ExecutionStep (retained := retained) (definitions table)
      ⟨⟨targetEvaluated, .code (.package .ret) (environment bindings) (.cons (value inner) .nil) targetOutside⟩, cells sourceCells, regions⟩
      ⟨⟨targetCreated.store, .code .ret (environment bindings) (.cons targetCreated.value .nil) targetOutside⟩, cells sourceCells, regions⟩ := by
    simpa only [targetCreated, reservations, UseScope.ReservedNames.withSupport_nil] using
      Target.ExecutionStep.packageOperand (retained := retained) (table := definitions table) (next := .ret)
        (bindings := environment bindings) (values := .nil) (outside := targetOutside) (cells := cells sourceCells) owner targetHandoff
  refine ⟨.packageOperand (retained := retained) owner handoff evaluated, count + 2,
    ⟨⟨targetCreated.store, .returned targetCreated.value targetOutside⟩, cells sourceCells, regions⟩, by omega, ?_, ?_⟩
  · exact (operands.in_execution (retained := retained) (definitions table) targetOutside (cells sourceCells) regions).trans
      (.cons packageStep (.single (.cell (.ordinary .returned))))
  · refine ⟨⟨created.2.2, ?_⟩, rfl, rfl⟩
    have values : targetCreated.value = value sourceCreated.value := created.2.1
    rw [values]
    exact .returned sourceCreated.value outside

theorem compiled_unpackage
    (table : Source.Definitions signature algebra program)
    (expression : Source.Expression signature algebra program context (.package content))
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (inner : Source.RuntimeValue signature algebra program content) (token : Id .custody) (owner : Owner)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore sourceEvaluated : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (evaluated : Source.ExpressionEvaluation bindings (sourceCells.reservations.withSupport retained).custody sourceStore expression (.ok (.package token owner inner)) sourceEvaluated)
    (handoff : PackageHandoff inner token owner sourceEvaluated.fields fields)
    (stores : ControlHeapRelated sourceStore targetStore)
    {sourceOutside : Source.Context signature algebra program content result}
    {targetOutside : Target.Stack signature algebra program content result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    Source.ExecutionStep (retained := retained) table
      ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.unpackage expression) bindings)⟩, sourceCells, regions⟩
      ⟨⟨{ sourceEvaluated with fields := fields }, sourceOutside.plug (.returned inner)⟩, sourceCells, regions⟩ ∧
    ∃ count targetAfter, 0 < count ∧ Target.ExecutionSteps (retained := retained) (definitions table)
      ⟨⟨targetStore, .code (computation (.unpackage expression)) (environment bindings) .nil targetOutside⟩,
        cells sourceCells, regions⟩ count targetAfter ∧
      CellStateRelated ⟨⟨{ sourceEvaluated with fields := fields }, sourceOutside.plug (.returned inner)⟩, sourceCells, regions⟩ targetAfter := by
  obtain ⟨count, targetEvaluated, _, operands, related⟩ := owned_expression_drains
    (UseScope.PackedControlRelated controlPayloadRelated) bindings (sourceCells.reservations.withSupport retained).custody
    expression (.package token owner inner) evaluated (.unpackage .ret) .nil stores
  have reservations : ((cells sourceCells).reservations.withSupport retained) = (sourceCells.reservations.withSupport retained) := Cells.reservations_with_support_mapBodies _ sourceCells retained
  rw [← reservations] at operands
  have targetHandoff : PackageHandoff (value inner) token owner targetEvaluated.fields fields := by
    rw [← related.fields]
    exact handoff.map (fun _ _ body => computation body)
  refine ⟨.unpackageOperand evaluated handoff, count + 2,
    ⟨⟨{ targetEvaluated with fields := fields }, .returned (value inner) targetOutside⟩, cells sourceCells, regions⟩, by omega, ?_, ?_⟩
  · exact (operands.in_execution (retained := retained) (definitions table) targetOutside (cells sourceCells) regions).trans
      (.cons (.unpackageOperand targetHandoff) (.single (.cell (.ordinary .returned))))
  · exact ⟨⟨⟨rfl, related.controls, related.disposing⟩, .returned inner outside⟩, rfl, rfl⟩

end BoundaryV2.Generalized.Defunctionalization
