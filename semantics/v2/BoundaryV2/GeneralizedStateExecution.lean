import BoundaryV2.GeneralizedCellExecution
import BoundaryV2.GeneralizedCellReservations
import BoundaryV2.GeneralizedOwnedOperands

namespace BoundaryV2.Generalized

namespace Source

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)} [DecidableEq (ControlShape signature)]

variable [DecidableEq (TypeOf signature)]

/-- Control steps preserve cell contents and use the live cell reservations
when creating closure or continuation authority. -/
inductive ExecutionStep (table : Definitions signature algebra program) : State signature algebra program result → State signature algebra program result → Prop where
  | cell : CellStep table before after → ExecutionStep table before after
  | control {cells : Cells signature algebra (Computation signature algebra program)} :
      OwnedStep table cells.reservations before after →
      ExecutionStep table ⟨before, cells, regions⟩ ⟨after, cells, regions⟩
  | returnOperand
      {expression : Expression signature algebra program context answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program answer result}
      {cells : Cells signature algebra (Computation signature algebra program)} :
      ExpressionEvaluation bindings cells.reservations.custody before expression (.ok value) after →
      ExecutionStep table ⟨⟨before, outside.plug (.evaluate (.returnValue expression) bindings)⟩, cells, regions⟩
        ⟨⟨after, outside.plug (.returned value)⟩, cells, regions⟩
  | operandFault
      {body : Computation signature algebra program context answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program answer result}
      {cells : Cells signature algebra (Computation signature algebra program)} :
      ArgumentsEvaluation bindings cells.reservations.custody before body.operandPrefix.arguments (.error fault) after →
      ExecutionStep table ⟨⟨before, outside.plug (.evaluate body bindings)⟩, cells, regions⟩
        ⟨⟨after, outside.plug (.failed fault)⟩, cells, regions⟩
  | applicationOperands
      {function : Expression signature algebra program context (.computation use parameters answer)}
      {arguments : Arguments signature algebra program context parameters}
      {body : Computation signature algebra program (parameters ++ capturedTypes) answer}
      {captured : RuntimeEnvironment signature algebra program capturedTypes}
      {actual : RuntimeEnvironment signature algebra program parameters}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program answer result}
      {cells : Cells signature algebra (Computation signature algebra program)} :
      ArgumentsEvaluation bindings cells.reservations.custody before (.cons function arguments)
        (.ok (.cons (.closure body captured authority) actual)) evaluated →
      ComputationHandoff captured use authority evaluated.fields fields →
      ExecutionStep table ⟨⟨before, outside.plug (.evaluate (.apply function arguments) bindings)⟩, cells, regions⟩
        ⟨⟨{ evaluated with fields := fields }, outside.plug (enterClosure body actual captured)⟩, cells, regions⟩

end Source

namespace Target

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)} [DecidableEq (ControlShape signature)]

variable [DecidableEq (TypeOf signature)]

inductive ExecutionStep (table : Definitions signature algebra program) : State signature algebra program result → State signature algebra program result → Prop where
  | cell : CellStep table before after → ExecutionStep table before after
  | control {cells : Cells signature algebra (fun context result => Code signature algebra program context [] result)} :
      OwnedStep table cells.reservations before after →
      ExecutionStep table ⟨before, cells, regions⟩ ⟨after, cells, regions⟩

inductive ExecutionSteps (table : Definitions signature algebra program) :
    State signature algebra program result → Nat → State signature algebra program result → Prop where
  | refl : ExecutionSteps table state 0 state
  | cons : ExecutionStep table before middle → ExecutionSteps table middle count after → ExecutionSteps table before (count + 1) after

theorem ExecutionSteps.single {before after : State signature algebra program result}
    (step : ExecutionStep table before after) : ExecutionSteps table before 1 after := .cons step .refl

theorem ExecutionSteps.trans {before middle after : State signature algebra program result}
    (first : ExecutionSteps table before count middle) (second : ExecutionSteps table middle rest after) :
    ExecutionSteps table before (count + rest) after := by
  induction first with
  | refl => simpa using second
  | cons step tail induction => simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using ExecutionSteps.cons step (induction second)

theorem CellSteps.in_execution {before after : State signature algebra program result}
    (steps : CellSteps table before count after) : ExecutionSteps table before count after := by
  induction steps with
  | refl => exact .refl
  | cons step tail induction => exact .cons (.cell step) induction

theorem OwnedSteps.in_execution
    {before after : ControlState signature algebra program result}
    (cells : Cells signature algebra (fun context result => Code signature algebra program context [] result))
    (regions : List (Id .region))
    (steps : OwnedSteps table cells.reservations before count after) :
    ExecutionSteps table ⟨before, cells, regions⟩ count ⟨after, cells, regions⟩ := by
  induction steps with
  | refl => exact .refl
  | cons step tail induction => exact .cons (.control step) induction

theorem OwnedOperandSteps.in_execution
    {bindings : RuntimeEnvironment signature algebra program context}
    {before after : Operands signature algebra program context answer}
    {beforeStore afterStore : ControlHeap signature algebra program}
    (table : Definitions signature algebra program) (outside : Stack signature algebra program answer result)
    (cells : Cells signature algebra (fun context result => Code signature algebra program context [] result))
    (regions : List (Id .region))
    (steps : OwnedOperandSteps bindings cells.reservations.custody beforeStore before count afterStore after) :
    ExecutionSteps table ⟨⟨beforeStore, .code before.code bindings before.values outside⟩, cells, regions⟩ count
      ⟨⟨afterStore, .code after.code bindings after.values outside⟩, cells, regions⟩ := by
  induction steps with
  | refl => exact .refl
  | cons step tail induction => exact .cons (.control (.operand step)) (induction outside)

omit [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)] in
theorem OwnedOperandSteps.preserves_cell_inventory
    {bindings : RuntimeEnvironment signature algebra program context}
    {before after : Operands signature algebra program context answer}
    {beforeStore afterStore : ControlHeap signature algebra program}
    (cells : Cells signature algebra (fun context result => Code signature algebra program context [] result))
    (steps : OwnedOperandSteps bindings cells.reservations.custody beforeStore before count afterStore after)
    (unique : (UseScope.inventory beforeStore.fields ++ UseScope.tokens cells.fields).Nodup) :
    (UseScope.inventory afterStore.fields ++ UseScope.tokens cells.fields).Nodup :=
  steps.preserves_external_inventory _ unique (fun _ member => cells.owning_tokens_reserved member)

end Target

namespace Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

theorem handled_operation_with_cells_corresponds
    (table : Source.Definitions signature algebra program)
    (operation : signature.operation effect) [DecidableEq (signature.operation effect)]
    (attachment : Id .attachment)
    (returned : Source.Computation signature algebra program (body :: context) answer)
    (clauses : Source.Clauses signature algebra program effect mode context body answer)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    {sourceInside : Source.Context signature algebra program (signature.result operation) body}
    {targetInside : Target.Stack signature algebra program (signature.result operation) body}
    (inside : ContextRelated signature algebra program sourceInside targetInside)
    (payload : Source.RuntimeValue signature algebra program (signature.payload operation))
    (bodies : Source.RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type))
    {sourceOutside : Source.Context signature algebra program answer result}
    {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (owner : Owner) (before captured after : List UseScope.Field)
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    (sourcePartition : sourceStore.fields.active = before ++ captured ++ after)
    (targetPartition : targetStore.fields.active = before ++ captured ++ after)
    (nearest : Source.select attachment sourceInside = none)
    (accepted : Source.dispatchOwnedClause operation attachment returned clauses bindings sourceInside payload bodies sourceOutside
      owner before captured after sourceStore sourcePartition sourceCells.reservations = some sourceAfter) :
    ∃ targetAfter : Target.OwnedClause signature algebra program result,
      CellStateRelated ⟨sourceAfter.state, sourceCells, regions⟩ ⟨targetAfter.state, cells sourceCells, regions⟩ ∧
      Source.ExecutionStep table
        ⟨⟨sourceStore, sourceOutside.plug (.handler effect mode attachment returned clauses bindings
          (.request operation attachment payload bodies sourceInside))⟩, sourceCells, regions⟩
        ⟨sourceAfter.state, sourceCells, regions⟩ ∧
      Target.ExecutionSteps (definitions table)
        ⟨⟨targetStore, .requested operation attachment (value payload) (environment bodies)
          (targetInside.append (.push (.handler effect mode attachment (computation returned)
            (Defunctionalization.clauses clauses) (environment bindings)) targetOutside))⟩, cells sourceCells, regions⟩ 1
        ⟨targetAfter.state, cells sourceCells, regions⟩ := by
  obtain ⟨targetAfter, matched, sourceStep, targetSteps⟩ := handled_operation_corresponds table sourceCells.reservations
    operation attachment returned clauses bindings inside payload bodies outside owner before captured after stores
    sourcePartition targetPartition nearest accepted
  have reservations : (cells sourceCells).reservations = sourceCells.reservations := Cells.reservations_mapBodies _ sourceCells
  rw [← reservations] at targetSteps
  exact ⟨targetAfter, ⟨matched, rfl, rfl⟩, .control sourceStep, targetSteps.in_execution (cells sourceCells) regions⟩

end Defunctionalization
end BoundaryV2.Generalized
