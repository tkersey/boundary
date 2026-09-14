import BoundaryV2.GeneralizedCellExecution
import BoundaryV2.GeneralizedCellReservations
import BoundaryV2.GeneralizedOwnedOperands
import BoundaryV2.GeneralizedInstallationSupport
import BoundaryV2.GeneralizedPackages

namespace BoundaryV2.Generalized

namespace Source

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)} [DecidableEq (ControlShape signature)]

variable [DecidableEq (TypeOf signature)]

/-- Control steps preserve cell contents and use the live cell reservations
when creating closure or continuation authority. -/
inductive ExecutionStep (table : Definitions signature algebra program) : State signature algebra program result → State signature algebra program result → (retained : List Reference := []) → Prop where
  | cell : CellStep table before after retained → ExecutionStep table before after retained

  | control {cells : Cells signature algebra (Computation signature algebra program)} :
      OwnedStep table (cells.reservations.withSupport retained) before after →
      ExecutionStep table ⟨before, cells, regions⟩ ⟨after, cells, regions⟩ retained

  | installHandler
      {returned : Computation signature algebra program (bodyType :: context) answer}
      {clauses : Clauses signature algebra program effect mode context bodyType answer}
      {body : Computation signature algebra program (.capability effect :: context) bodyType}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program answer result}
      {cells : Cells signature algebra (Computation signature algebra program)}
      (extra : List Reference) :
      ContextSupported outside outsideSupport → StoreSupported store storedSupport →
      attachment = freshAttachment table (.handle effect mode returned clauses body) bindings outsideSupport storedSupport cells (retained ++ extra) →
      ExecutionStep table ⟨⟨store, outside.plug (.evaluate (.handle effect mode returned clauses body) bindings)⟩, cells, regions⟩
        ⟨⟨store, outside.plug (.handler effect mode attachment returned clauses bindings
          (.evaluate body (.cons (.datum (.capability attachment)) bindings)))⟩, cells, regions⟩ retained

  | enterProtection
      {cleanup : Computation signature algebra program (.exit :: context) .unit}
      {body : Computation signature algebra program context answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program answer result}
      {cells : Cells signature algebra (Computation signature algebra program)}
      (extra : List Reference) :
      ContextSupported outside outsideSupport → StoreSupported store storedSupport →
      identity = freshObligation table (.protect cleanup body) bindings outsideSupport storedSupport cells (retained ++ extra) →
      ExecutionStep table ⟨⟨store, outside.plug (.evaluate (.protect cleanup body) bindings)⟩, cells, regions⟩
        ⟨⟨store, outside.plug (.protection identity cleanup bindings (.evaluate body bindings))⟩, cells, regions⟩ retained

  | enterRegion
      {body : Computation signature algebra program (.region :: context) answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program answer result}
      {cells : Cells signature algebra (Computation signature algebra program)}
      (extra : List Reference) :
      ContextSupported outside outsideSupport → StoreSupported store storedSupport →
      identity = freshRegion table (.withRegion body) bindings outsideSupport storedSupport cells regions (retained ++ extra) →
      ExecutionStep table ⟨⟨store, outside.plug (.evaluate (.withRegion body) bindings)⟩, cells, regions⟩
        ⟨⟨store, outside.plug (.region identity (.evaluate body (.cons (.datum (.region identity)) bindings)))⟩,
          cells, identity :: regions⟩ retained

  | packageOperand
      {expression : Expression signature algebra program context content}
      {value : RuntimeValue signature algebra program content}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program (.package content) result}
      {store evaluated : ControlHeap signature algebra program} {moved : UseScope.State}
      {cells : Cells signature algebra (Computation signature algebra program)}
      (owner : Owner) (handoff : ValueHandoff value evaluated.fields moved) :
      ExpressionEvaluation bindings (cells.reservations.withSupport retained).custody store expression (.ok value) evaluated →
      ExecutionStep table ⟨⟨store, outside.plug (.evaluate (.package expression) bindings)⟩, cells, regions⟩
        ⟨⟨(createPackage value owner evaluated moved handoff (cells.reservations.withSupport retained).custody).store,
          outside.plug (.returned (createPackage value owner evaluated moved handoff (cells.reservations.withSupport retained).custody).value)⟩,
          cells, regions⟩ retained

  | unpackageOperand
      {expression : Expression signature algebra program context (.package content)}
      {value : RuntimeValue signature algebra program content}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program content result}
      {store evaluated : ControlHeap signature algebra program}
      {cells : Cells signature algebra (Computation signature algebra program)} :
      ExpressionEvaluation bindings (cells.reservations.withSupport retained).custody store expression (.ok (.package token owner value)) evaluated →
      PackageHandoff value token owner evaluated.fields fields →
      ExecutionStep table ⟨⟨store, outside.plug (.evaluate (.unpackage expression) bindings)⟩, cells, regions⟩
        ⟨⟨{ evaluated with fields := fields }, outside.plug (.returned value)⟩, cells, regions⟩ retained

  | returnOperand
      {expression : Expression signature algebra program context answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program answer result}
      {cells : Cells signature algebra (Computation signature algebra program)} :
      ExpressionEvaluation bindings (cells.reservations.withSupport retained).custody before expression (.ok value) after →
      ExecutionStep table ⟨⟨before, outside.plug (.evaluate (.returnValue expression) bindings)⟩, cells, regions⟩
        ⟨⟨after, outside.plug (.returned value)⟩, cells, regions⟩ retained

  | operandFault
      {body : Computation signature algebra program context answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program answer result}
      {cells : Cells signature algebra (Computation signature algebra program)} :
      ArgumentsEvaluation bindings (cells.reservations.withSupport retained).custody before body.operandPrefix.arguments (.error fault) after →
      ExecutionStep table ⟨⟨before, outside.plug (.evaluate body bindings)⟩, cells, regions⟩
        ⟨⟨after, outside.plug (.failed fault)⟩, cells, regions⟩ retained

  | applicationOperands
      {function : Expression signature algebra program context (.computation use parameters answer)}
      {arguments : Arguments signature algebra program context parameters}
      {body : Computation signature algebra program (parameters ++ capturedTypes) answer}
      {captured : RuntimeEnvironment signature algebra program capturedTypes}
      {actual : RuntimeEnvironment signature algebra program parameters}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program answer result}
      {cells : Cells signature algebra (Computation signature algebra program)} :
      ArgumentsEvaluation bindings (cells.reservations.withSupport retained).custody before (.cons function arguments)
        (.ok (.cons (.closure body captured authority) actual)) evaluated →
      ComputationHandoff captured use authority evaluated.fields fields →
      ExecutionStep table ⟨⟨before, outside.plug (.evaluate (.apply function arguments) bindings)⟩, cells, regions⟩
        ⟨⟨{ evaluated with fields := fields }, outside.plug (enterClosure body actual captured)⟩, cells, regions⟩ retained

  | namedOperands
      {reference : Variable program body}
      {arguments : Arguments signature algebra program context body.parameters}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program body.result result}
      {cells : Cells signature algebra (Computation signature algebra program)} :
      ArgumentsEvaluation bindings (cells.reservations.withSupport retained).custody before arguments (.ok actual) after →
      ExecutionStep table ⟨⟨before, outside.plug (.evaluate (.call reference arguments) bindings)⟩, cells, regions⟩
        ⟨⟨after, outside.plug (unfoldCall table reference actual)⟩, cells, regions⟩ retained

  | primitiveOperands {parameters : List signature.Data} {answer : signature.Data}
      {operation : algebra.operation parameters answer}
      {value : algebra.Value answer}
      {inputs : Arguments signature algebra program context (parameters.map Ty.leaf)}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program (.leaf answer) result}
      {cells : Cells signature algebra (Computation signature algebra program)} :
      ExpressionEvaluation bindings (cells.reservations.withSupport retained).custody before (.primitive operation inputs)
        (.ok (.datum (.leaf value))) after →
      ExecutionStep table ⟨⟨before, outside.plug (.evaluate (.primitive operation inputs) bindings)⟩, cells, regions⟩
        ⟨⟨after, outside.plug (.returned (.datum (.leaf value)))⟩, cells, regions⟩ retained

  | branchLeftOperands
      {test : Expression signature algebra program context (.sum leftType rightType)}
      {left : Computation signature algebra program (leftType :: context) answer}
      {right : Computation signature algebra program (rightType :: context) answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program answer result}
      {cells : Cells signature algebra (Computation signature algebra program)} :
      ExpressionEvaluation bindings (cells.reservations.withSupport retained).custody before test (.ok value) after →
      value.asSum = .inl payload →
      ExecutionStep table ⟨⟨before, outside.plug (.evaluate (.matchSum test left right) bindings)⟩, cells, regions⟩
        ⟨⟨after, outside.plug (.evaluate left (.cons payload bindings))⟩, cells, regions⟩ retained

  | branchRightOperands
      {test : Expression signature algebra program context (.sum leftType rightType)}
      {left : Computation signature algebra program (leftType :: context) answer}
      {right : Computation signature algebra program (rightType :: context) answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program answer result}
      {cells : Cells signature algebra (Computation signature algebra program)} :
      ExpressionEvaluation bindings (cells.reservations.withSupport retained).custody before test (.ok value) after →
      value.asSum = .inr payload →
      ExecutionStep table ⟨⟨before, outside.plug (.evaluate (.matchSum test left right) bindings)⟩, cells, regions⟩
        ⟨⟨after, outside.plug (.evaluate right (.cons payload bindings))⟩, cells, regions⟩ retained

  | performOperands
      {operation : signature.operation effect}
      {payloadValue : RuntimeValue signature algebra program (signature.payload operation)}
      {bodyValues : RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type)}
      {capability : Expression signature algebra program context (.capability effect)}
      {payload : Expression signature algebra program context (signature.payload operation)}
      {bodies : Arguments signature algebra program context ((signature.bodies operation).map BodyType.type)}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program (signature.result operation) result}
      {cells : Cells signature algebra (Computation signature algebra program)} :
      ArgumentsEvaluation bindings (cells.reservations.withSupport retained).custody before (.cons capability (.cons payload bodies))
        (.ok (.cons (.datum (.capability attachment)) (.cons payloadValue bodyValues))) after →
      ExecutionStep table ⟨⟨before, outside.plug (.evaluate (.perform operation capability payload bodies) bindings)⟩, cells, regions⟩
        ⟨⟨after, outside.plug (.request operation attachment payloadValue bodyValues .done)⟩, cells, regions⟩ retained

end Source

namespace Target

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)} [DecidableEq (ControlShape signature)]

variable [DecidableEq (TypeOf signature)]

inductive ExecutionStep (table : Definitions signature algebra program) : State signature algebra program result → State signature algebra program result → (retained : List Reference := []) → Prop where
  | cell : CellStep table before after retained → ExecutionStep table before after retained

  | control {cells : Cells signature algebra (fun context result => Code signature algebra program context [] result)} :
      OwnedStep table (cells.reservations.withSupport retained) before after →
      ExecutionStep table ⟨before, cells, regions⟩ ⟨after, cells, regions⟩ retained

  | installHandler
      {returned : Code signature algebra program (bodyType :: context) [] answer}
      {clauses : Clauses signature algebra program effect mode context bodyType answer}
      {body : Code signature algebra program (.capability effect :: context) [] bodyType}
      {next : Code signature algebra program context (answer :: operands) resultType}
      {bindings : RuntimeEnvironment signature algebra program context}
      {values : RuntimeEnvironment signature algebra program operands}
      {outside : Stack signature algebra program resultType result}
      {cells : Cells signature algebra (fun context result => Code signature algebra program context [] result)}
      (extra : List Reference) :
      attachment = freshAttachment table (.attach effect mode returned clauses body next) bindings values outside store cells (retained ++ extra) →
      ExecutionStep table ⟨⟨store, .code (.attach effect mode returned clauses body next) bindings values outside⟩, cells, regions⟩
        ⟨⟨store, .code body (.cons (.datum (.capability attachment)) bindings) .nil
          (.push (.handler effect mode attachment returned clauses bindings) (.push (.returnTo next bindings values) outside))⟩, cells, regions⟩ retained

  | enterProtection
      {cleanup : Code signature algebra program (.exit :: context) [] .unit}
      {body : Code signature algebra program context [] answer}
      {next : Code signature algebra program context (answer :: operands) resultType}
      {bindings : RuntimeEnvironment signature algebra program context}
      {values : RuntimeEnvironment signature algebra program operands}
      {outside : Stack signature algebra program resultType result}
      {cells : Cells signature algebra (fun context result => Code signature algebra program context [] result)}
      (extra : List Reference) :
      identity = freshObligation table (.protect cleanup body next) bindings values outside store cells (retained ++ extra) →
      ExecutionStep table ⟨⟨store, .code (.protect cleanup body next) bindings values outside⟩, cells, regions⟩
        ⟨⟨store, .code body bindings .nil
          (.push (.protection identity cleanup bindings) (.push (.returnTo next bindings values) outside))⟩, cells, regions⟩ retained

  | enterRegion
      {body : Code signature algebra program (.region :: context) [] answer}
      {next : Code signature algebra program context (answer :: operands) resultType}
      {bindings : RuntimeEnvironment signature algebra program context}
      {values : RuntimeEnvironment signature algebra program operands}
      {outside : Stack signature algebra program resultType result}
      {cells : Cells signature algebra (fun context result => Code signature algebra program context [] result)}
      (extra : List Reference) :
      identity = freshRegion table (.enterRegion body next) bindings values outside store cells regions (retained ++ extra) →
      ExecutionStep table ⟨⟨store, .code (.enterRegion body next) bindings values outside⟩, cells, regions⟩
        ⟨⟨store, .code body (.cons (.datum (.region identity)) bindings) .nil
          (.push (.region identity) (.push (.returnTo next bindings values) outside))⟩, cells, identity :: regions⟩ retained

  | packageOperand
      {value : RuntimeValue signature algebra program content}
      {next : Code signature algebra program context (.package content :: operands) answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {values : RuntimeEnvironment signature algebra program operands}
      {outside : Stack signature algebra program answer result}
      {store : ControlHeap signature algebra program} {moved : UseScope.State}
      {cells : Cells signature algebra (fun context result => Code signature algebra program context [] result)}
      (owner : Owner) (handoff : ValueHandoff value store.fields moved) :
      ExecutionStep table ⟨⟨store, .code (.package next) bindings (.cons value values) outside⟩, cells, regions⟩
        ⟨⟨(createPackage value owner store moved handoff (cells.reservations.withSupport retained).custody).store,
          .code next bindings (.cons (createPackage value owner store moved handoff (cells.reservations.withSupport retained).custody).value values) outside⟩,
          cells, regions⟩ retained

  | unpackageOperand
      {value : RuntimeValue signature algebra program content}
      {next : Code signature algebra program context (content :: operands) answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {values : RuntimeEnvironment signature algebra program operands}
      {outside : Stack signature algebra program answer result}
      {store : ControlHeap signature algebra program}
      {cells : Cells signature algebra (fun context result => Code signature algebra program context [] result)} :
      PackageHandoff value token owner store.fields fields →
      ExecutionStep table ⟨⟨store, .code (.unpackage next) bindings (.cons (.package token owner value) values) outside⟩, cells, regions⟩
        ⟨⟨{ store with fields := fields }, .code next bindings (.cons value values) outside⟩, cells, regions⟩ retained

inductive ExecutionSteps (table : Definitions signature algebra program) :
    State signature algebra program result → Nat → State signature algebra program result → (retained : List Reference := []) → Prop where
  | refl : ExecutionSteps (retained := retained) table state 0 state
  | cons : ExecutionStep table before middle retained → ExecutionSteps (retained := retained) table middle count after → ExecutionSteps (retained := retained) table before (count + 1) after

theorem ExecutionSteps.single {retained : List Reference} {before after : State signature algebra program result}
    (step : ExecutionStep table before after retained) : ExecutionSteps (retained := retained) table before 1 after := .cons step .refl

theorem ExecutionSteps.trans {retained : List Reference} {before middle after : State signature algebra program result}
    (first : ExecutionSteps (retained := retained) table before count middle) (second : ExecutionSteps (retained := retained) table middle rest after) :
    ExecutionSteps (retained := retained) table before (count + rest) after := by
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
