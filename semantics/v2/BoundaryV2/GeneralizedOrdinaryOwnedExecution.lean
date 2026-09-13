import BoundaryV2.GeneralizedStatefulOperandExecution
import BoundaryV2.GeneralizedBranching

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

theorem compiled_owned_named_call
    (table : Source.Definitions signature algebra program) (reference : Variable program body)
    (arguments : Source.Arguments signature algebra program context body.parameters)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (actual : Source.RuntimeEnvironment signature algebra program body.parameters)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore sourceAfter : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (evaluated : Source.ArgumentsEvaluation bindings sourceCells.reservations.custody sourceStore arguments (.ok actual) sourceAfter)
    (stores : ControlHeapRelated sourceStore targetStore)
    {sourceOutside : Source.Context signature algebra program body.result result}
    {targetOutside : Target.Stack signature algebra program body.result result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    Source.ExecutionStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.call reference arguments) bindings)⟩, sourceCells, regions⟩
      ⟨⟨sourceAfter, sourceOutside.plug (Source.unfoldCall table reference actual)⟩, sourceCells, regions⟩ ∧
    ∃ count targetAfter, 0 < count ∧ Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (computation (.call reference arguments)) (environment bindings) .nil targetOutside⟩, cells sourceCells, regions⟩ count
      ⟨⟨targetAfter, .code (computation (reference.lookup table)) (environment actual) .nil
        (.push (.returnTo .ret (environment bindings) .nil) targetOutside)⟩, cells sourceCells, regions⟩ ∧
      CellStateRelated ⟨⟨sourceAfter, sourceOutside.plug (Source.unfoldCall table reference actual)⟩, sourceCells, regions⟩
        ⟨⟨targetAfter, .code (computation (reference.lookup table)) (environment actual) .nil
          (.push (.returnTo .ret (environment bindings) .nil) targetOutside)⟩, cells sourceCells, regions⟩ := by
  obtain ⟨count, targetAfter, operands, related⟩ := owned_arguments_drains
    (UseScope.PackedControlRelated controlPayloadRelated) bindings sourceCells.reservations.custody arguments actual evaluated
    (.callNamed reference .ret) .nil stores
  have reservations : (cells sourceCells).reservations = sourceCells.reservations := Cells.reservations_mapBodies _ sourceCells
  rw [← reservations] at operands
  refine ⟨.namedOperands evaluated, count + 1, targetAfter, by omega, ?_,
    ⟨⟨related, .evaluate _ actual (.passthrough bindings outside)⟩, rfl, rfl⟩⟩
  exact (operands.in_execution (definitions table) targetOutside (cells sourceCells) regions).trans
    (.single (.cell (.ordinary (named_call_enters_corresponding_body table reference actual bindings .ret .nil targetOutside))))

theorem compiled_owned_primitive
    (table : Source.Definitions signature algebra program)
    (operation : algebra.operation parameters answer)
    (inputs : Source.Arguments signature algebra program context (parameters.map Ty.leaf))
    (bindings : Source.RuntimeEnvironment signature algebra program context) (returned : algebra.Value answer)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore sourceAfter : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (evaluated : Source.ExpressionEvaluation bindings sourceCells.reservations.custody sourceStore (.primitive operation inputs)
      (.ok (.datum (.leaf returned))) sourceAfter)
    (stores : ControlHeapRelated sourceStore targetStore)
    {sourceOutside : Source.Context signature algebra program (.leaf answer) result}
    {targetOutside : Target.Stack signature algebra program (.leaf answer) result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    Source.ExecutionStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.primitive operation inputs) bindings)⟩, sourceCells, regions⟩
      ⟨⟨sourceAfter, sourceOutside.plug (.returned (.datum (.leaf returned)))⟩, sourceCells, regions⟩ ∧
    ∃ count targetAfter, 0 < count ∧ Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (computation (.primitive operation inputs)) (environment bindings) .nil targetOutside⟩, cells sourceCells, regions⟩ count
      ⟨⟨targetAfter, .returned (.datum (.leaf returned)) targetOutside⟩, cells sourceCells, regions⟩ ∧
      CellStateRelated ⟨⟨sourceAfter, sourceOutside.plug (.returned (.datum (.leaf returned)))⟩, sourceCells, regions⟩
        ⟨⟨targetAfter, .returned (.datum (.leaf returned)) targetOutside⟩, cells sourceCells, regions⟩ := by
  exact ⟨.primitiveOperands evaluated,
    (compiled_owned_operand_return table (.primitive operation inputs) bindings (.datum (.leaf returned))
      sourceCells regions evaluated stores outside).2⟩

theorem compiled_owned_match_left
    (table : Source.Definitions signature algebra program)
    (test : Source.Expression signature algebra program context (.sum leftType rightType))
    (left : Source.Computation signature algebra program (leftType :: context) answer)
    (right : Source.Computation signature algebra program (rightType :: context) answer)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (sum : Source.RuntimeValue signature algebra program (.sum leftType rightType))
    (payload : Source.RuntimeValue signature algebra program leftType)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore sourceAfter : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (evaluated : Source.ExpressionEvaluation bindings sourceCells.reservations.custody sourceStore test (.ok sum) sourceAfter)
    (selected : sum.asSum = .inl payload) (stores : ControlHeapRelated sourceStore targetStore)
    {sourceOutside : Source.Context signature algebra program answer result}
    {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    Source.ExecutionStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.matchSum test left right) bindings)⟩, sourceCells, regions⟩
      ⟨⟨sourceAfter, sourceOutside.plug (.evaluate left (.cons payload bindings))⟩, sourceCells, regions⟩ ∧
    ∃ count targetAfter, 0 < count ∧ Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (computation (.matchSum test left right)) (environment bindings) .nil targetOutside⟩, cells sourceCells, regions⟩ count
      ⟨⟨targetAfter, .code (computation left) (environment (.cons payload bindings)) .nil targetOutside⟩, cells sourceCells, regions⟩ ∧
      CellStateRelated ⟨⟨sourceAfter, sourceOutside.plug (.evaluate left (.cons payload bindings))⟩, sourceCells, regions⟩
        ⟨⟨targetAfter, .code (computation left) (environment (.cons payload bindings)) .nil targetOutside⟩, cells sourceCells, regions⟩ := by
  obtain ⟨count, targetAfter, _, operands, related⟩ := owned_expression_drains
    (UseScope.PackedControlRelated controlPayloadRelated) bindings sourceCells.reservations.custody test sum evaluated
    (.branch (computation left) (computation right)) .nil stores
  have reservations : (cells sourceCells).reservations = sourceCells.reservations := Cells.reservations_mapBodies _ sourceCells
  rw [← reservations] at operands
  refine ⟨.branchLeftOperands evaluated selected, count + 1, targetAfter, by omega, ?_,
    ⟨⟨related, .evaluate left (.cons payload bindings) outside⟩, rfl, rfl⟩⟩
  exact (operands.in_execution (definitions table) targetOutside (cells sourceCells) regions).trans
    (.single (.cell (.ordinary (.branchLeft ((sum_left_is_preserved_and_reflected sum (value payload)).mpr ⟨payload, selected, rfl⟩)))))

theorem compiled_owned_match_right
    (table : Source.Definitions signature algebra program)
    (test : Source.Expression signature algebra program context (.sum leftType rightType))
    (left : Source.Computation signature algebra program (leftType :: context) answer)
    (right : Source.Computation signature algebra program (rightType :: context) answer)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (sum : Source.RuntimeValue signature algebra program (.sum leftType rightType))
    (payload : Source.RuntimeValue signature algebra program rightType)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore sourceAfter : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (evaluated : Source.ExpressionEvaluation bindings sourceCells.reservations.custody sourceStore test (.ok sum) sourceAfter)
    (selected : sum.asSum = .inr payload) (stores : ControlHeapRelated sourceStore targetStore)
    {sourceOutside : Source.Context signature algebra program answer result}
    {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    Source.ExecutionStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.matchSum test left right) bindings)⟩, sourceCells, regions⟩
      ⟨⟨sourceAfter, sourceOutside.plug (.evaluate right (.cons payload bindings))⟩, sourceCells, regions⟩ ∧
    ∃ count targetAfter, 0 < count ∧ Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (computation (.matchSum test left right)) (environment bindings) .nil targetOutside⟩, cells sourceCells, regions⟩ count
      ⟨⟨targetAfter, .code (computation right) (environment (.cons payload bindings)) .nil targetOutside⟩, cells sourceCells, regions⟩ ∧
      CellStateRelated ⟨⟨sourceAfter, sourceOutside.plug (.evaluate right (.cons payload bindings))⟩, sourceCells, regions⟩
        ⟨⟨targetAfter, .code (computation right) (environment (.cons payload bindings)) .nil targetOutside⟩, cells sourceCells, regions⟩ := by
  obtain ⟨count, targetAfter, _, operands, related⟩ := owned_expression_drains
    (UseScope.PackedControlRelated controlPayloadRelated) bindings sourceCells.reservations.custody test sum evaluated
    (.branch (computation left) (computation right)) .nil stores
  have reservations : (cells sourceCells).reservations = sourceCells.reservations := Cells.reservations_mapBodies _ sourceCells
  rw [← reservations] at operands
  refine ⟨.branchRightOperands evaluated selected, count + 1, targetAfter, by omega, ?_,
    ⟨⟨related, .evaluate right (.cons payload bindings) outside⟩, rfl, rfl⟩⟩
  exact (operands.in_execution (definitions table) targetOutside (cells sourceCells) regions).trans
    (.single (.cell (.ordinary (.branchRight ((sum_right_is_preserved_and_reflected sum (value payload)).mpr ⟨payload, selected, rfl⟩)))))

/-- Dispatch preserves computation-bearing arguments and their owning fields.
The pending request retains its typed continuation, including the caller frame. -/
theorem compiled_owned_operation
    (table : Source.Definitions signature algebra program)
    (operation : signature.operation effect)
    (capability : Source.Expression signature algebra program context (.capability effect))
    (payload : Source.Expression signature algebra program context (signature.payload operation))
    (bodies : Source.Arguments signature algebra program context ((signature.bodies operation).map BodyType.type))
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (attachment : Id .attachment)
    (payloadValue : Source.RuntimeValue signature algebra program (signature.payload operation))
    (bodyValues : Source.RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type))
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceStore sourceAfter : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (evaluated : Source.ArgumentsEvaluation bindings sourceCells.reservations.custody sourceStore (.cons capability (.cons payload bodies))
      (.ok (.cons (.datum (.capability attachment)) (.cons payloadValue bodyValues))) sourceAfter)
    (stores : ControlHeapRelated sourceStore targetStore)
    {sourceOutside : Source.Context signature algebra program (signature.result operation) result}
    {targetOutside : Target.Stack signature algebra program (signature.result operation) result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    Source.ExecutionStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.perform operation capability payload bodies) bindings)⟩, sourceCells, regions⟩
      ⟨⟨sourceAfter, sourceOutside.plug (.request operation attachment payloadValue bodyValues .done)⟩, sourceCells, regions⟩ ∧
    ∃ count targetAfter, 0 < count ∧ Target.ExecutionSteps (definitions table)
      ⟨⟨targetStore, .code (computation (.perform operation capability payload bodies)) (environment bindings) .nil targetOutside⟩, cells sourceCells, regions⟩ count
      ⟨⟨targetAfter, .requested operation attachment (value payloadValue) (environment bodyValues)
        (.push (.returnTo .ret (environment bindings) .nil) targetOutside)⟩, cells sourceCells, regions⟩ ∧
      CellStateRelated
        ⟨⟨sourceAfter, sourceOutside.plug (.request operation attachment payloadValue bodyValues .done)⟩, sourceCells, regions⟩
        ⟨⟨targetAfter, .requested operation attachment (value payloadValue) (environment bodyValues)
          (.push (.returnTo .ret (environment bindings) .nil) targetOutside)⟩, cells sourceCells, regions⟩ := by
  refine ⟨.performOperands evaluated, ?_⟩
  cases evaluated with
  | cons capabilityStep tail =>
    cases tail with
    | cons payloadStep bodiesStep =>
      obtain ⟨capabilityCount, capabilityStore, _, capabilitySteps, capabilityRelated⟩ := owned_expression_drains
        (UseScope.PackedControlRelated controlPayloadRelated) bindings sourceCells.reservations.custody capability
        (.datum (.capability attachment)) capabilityStep
        (expression payload (arguments bodies (.dispatch operation .ret))) .nil stores
      obtain ⟨payloadCount, payloadStore, _, payloadSteps, payloadRelated⟩ := owned_expression_drains
        (UseScope.PackedControlRelated controlPayloadRelated) bindings sourceCells.reservations.custody payload payloadValue payloadStep
        (arguments bodies (.dispatch operation .ret)) (.cons (.datum (.capability attachment)) .nil) capabilityRelated
      obtain ⟨bodyCount, targetAfter, bodySteps, related⟩ := owned_arguments_drains
        (UseScope.PackedControlRelated controlPayloadRelated) bindings sourceCells.reservations.custody bodies bodyValues bodiesStep
        (.dispatch operation .ret) (.cons (value payloadValue) (.cons (.datum (.capability attachment)) .nil)) payloadRelated
      have operands := (capabilitySteps.trans payloadSteps).trans bodySteps
      have reservations : (cells sourceCells).reservations = sourceCells.reservations := Cells.reservations_mapBodies _ sourceCells
      rw [← reservations] at operands
      refine ⟨capabilityCount + payloadCount + bodyCount + 1, targetAfter, by omega, ?_,
        ⟨⟨related, .requested operation attachment payloadValue bodyValues (.passthrough bindings outside)⟩, rfl, rfl⟩⟩
      exact (operands.in_execution (definitions table) targetOutside (cells sourceCells) regions).trans
        (.single (.cell (.ordinary .dispatch)))

end BoundaryV2.Generalized.Defunctionalization
