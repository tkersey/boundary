import BoundaryV2.GeneralizedCellExecution
import BoundaryV2.GeneralizedCellReservations

namespace BoundaryV2.Generalized

namespace Source

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)} [DecidableEq (ControlShape signature)]

inductive OwnedStep.NonAllocating (table : Definitions signature algebra program) :
    {before after : ControlState signature algebra program result} → OwnedStep table before after → Prop where
  | ordinary : NonAllocating table (.ordinary step neutral)
  | application {context parameters capturedTypes : List (TypeOf signature)} {use : Use} {answer result : TypeOf signature}
      {function : Expression signature algebra program context (.computation use parameters answer)}
      {arguments : Arguments signature algebra program context parameters}
      {body : Computation signature algebra program (parameters ++ capturedTypes) answer}
      {captured : RuntimeEnvironment signature algebra program capturedTypes}
      {values : RuntimeEnvironment signature algebra program parameters} {authority : Option (Id .custody × Owner)}
      {bindings : RuntimeEnvironment signature algebra program context} {outside : Context signature algebra program answer result}
      {store : ControlHeap signature algebra program} {fields : UseScope.State}
      (functionAt : function.evaluate bindings = .ok (.closure body captured authority))
      (argumentsAt : arguments.evaluate bindings = .ok values)
      (handoff : ComputationHandoff captured use authority store.fields fields) :
      NonAllocating table (.application (outside := outside) functionAt argumentsAt handoff)
  | resume : NonAllocating table (.resume continuation response accepted)
  | successor : NonAllocating table (.successor continuation response accepted)
  | injection : NonAllocating table (.injection continuation body handoff accepted)

variable [DecidableEq (TypeOf signature)]

/-- Control use retains the complete cell state. Capture is separate because
its fresh names must also account for values held by cells. -/
inductive ExecutionStep (table : Definitions signature algebra program) : State signature algebra program result → State signature algebra program result → Prop where
  | cell : CellStep table before after → ExecutionStep table before after
  | control (step : OwnedStep table before after) : step.NonAllocating table →
      ExecutionStep table ⟨before, cells, regions⟩ ⟨after, cells, regions⟩
  | handled {effect : signature.Effect} {operation : signature.operation effect}
      [DecidableEq (signature.operation effect)]
      {mode : Mode} {context : List (TypeOf signature)} {body answer result : TypeOf signature}
      {returned : Computation signature algebra program (body :: context) answer}
      {clauses : Clauses signature algebra program effect mode context body answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {payload : RuntimeValue signature algebra program (signature.payload operation)}
      {bodies : RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type)}
      {inside : Context signature algebra program (signature.result operation) body}
      {outside : Context signature algebra program answer result}
      {store : ControlHeap signature algebra program} {before captured after : List UseScope.Field}
      {partition : store.fields.active = before ++ captured ++ after} {clause : OwnedClause signature algebra program result}
      {cells : Cells signature algebra (Computation signature algebra program)} :
      select attachment inside = none →
      dispatchOwnedClause operation attachment returned clauses bindings inside payload bodies outside
        owner before captured after store partition cells.reservations = some clause →
      ExecutionStep table ⟨⟨store, outside.plug (.handler effect mode attachment returned clauses bindings
        (.request operation attachment payload bodies inside))⟩, cells, regions⟩ ⟨clause.state, cells, regions⟩

end Source

namespace Target

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)} [DecidableEq (ControlShape signature)]

inductive OwnedStep.NonAllocating (table : Definitions signature algebra program) :
    {before after : ControlState signature algebra program result} → OwnedStep table before after → Prop where
  | ordinary : NonAllocating table (.ordinary step neutral)
  | application {context parameters capturedTypes operands : List (TypeOf signature)} {use : Use} {answer rest result : TypeOf signature}
      {body : Code signature algebra program (parameters ++ capturedTypes) [] answer}
      {captured : RuntimeEnvironment signature algebra program capturedTypes}
      {arguments : RuntimeEnvironment signature algebra program parameters} {authority : Option (Id .custody × Owner)}
      {next : Code signature algebra program context (answer :: operands) rest}
      {bindings : RuntimeEnvironment signature algebra program context} {values : RuntimeEnvironment signature algebra program operands}
      {outside : Stack signature algebra program rest result} {store : ControlHeap signature algebra program} {fields : UseScope.State}
      (handoff : ComputationHandoff captured use authority store.fields fields) :
      NonAllocating table (.application (body := body) (arguments := arguments) (next := next)
        (bindings := bindings) (values := values) (outside := outside) handoff)
  | resume : NonAllocating table (.resume accepted)
  | successor : NonAllocating table (.successor accepted)
  | injection {use : UseScope.OneShotUse} {bodyUse : Use}
      {context operands capturedTypes : List (TypeOf signature)} {mode : Mode} {effect : signature.Effect}
      {input answer rest result : TypeOf signature}
      {next : Code signature algebra program context (answer :: operands) rest}
      {body : Code signature algebra program capturedTypes [] input}
      {captured : RuntimeEnvironment signature algebra program capturedTypes}
      {bindings : RuntimeEnvironment signature algebra program context}
      {values : RuntimeEnvironment signature algebra program operands}
      {outside : Stack signature algebra program rest result}
      {authority : Option (Id .custody × Owner)} {store : ControlHeap signature algebra program} {fields : UseScope.State}
      {view : UseScope.ControlView} {after : ControlState signature algebra program result}
      {handoff : ComputationHandoff captured bodyUse authority store.fields fields}
      {accepted : injectControl ⟨mode, effect, input, answer⟩ view { store with fields := fields }
        ⟨capturedTypes, body, captured⟩ (.push (.returnTo next bindings values) outside) = some after} :
      NonAllocating table (.injection (use := use) (bodyUse := bodyUse) handoff accepted)

variable [DecidableEq (TypeOf signature)]

inductive ExecutionStep (table : Definitions signature algebra program) : State signature algebra program result → State signature algebra program result → Prop where
  | cell : CellStep table before after → ExecutionStep table before after
  | control (step : OwnedStep table before after) : step.NonAllocating table →
      ExecutionStep table ⟨before, cells, regions⟩ ⟨after, cells, regions⟩
  | handled {effect : signature.Effect} {operation : signature.operation effect}
      [DecidableEq (signature.operation effect)]
      {mode : Mode} {context : List (TypeOf signature)} {body answer result : TypeOf signature}
      {returned : Code signature algebra program (body :: context) [] answer}
      {clauses : Clauses signature algebra program effect mode context body answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {payload : RuntimeValue signature algebra program (signature.payload operation)}
      {bodies : RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type)}
      {inside : Stack signature algebra program (signature.result operation) body}
      {outside : Stack signature algebra program answer result}
      {store : ControlHeap signature algebra program} {before captured after : List UseScope.Field}
      {partition : store.fields.active = before ++ captured ++ after} {clause : OwnedClause signature algebra program result}
      {cells : Cells signature algebra (fun context result => Code signature algebra program context [] result)} :
      select attachment inside = none →
      dispatchOwnedClause operation attachment returned clauses bindings inside payload bodies outside
        owner before captured after store partition cells.reservations = some clause →
      ExecutionStep table ⟨⟨store, .requested operation attachment payload bodies
        (inside.append (.push (.handler effect mode attachment returned clauses bindings) outside))⟩, cells, regions⟩
        ⟨clause.state, cells, regions⟩

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
  have selections := selection_corresponds attachment inside
  rw [nearest] at selections
  have nearestTarget : Target.select attachment targetInside = none := by
    cases found : Target.select attachment targetInside with
    | none => rfl
    | some selected => rw [found] at selections; cases selections
  have matched := owned_clause_dispatch_corresponds operation attachment returned clauses bindings inside payload bodies outside
    owner before captured after stores sourcePartition targetPartition sourceCells.reservations
  rw [accepted] at matched
  generalize targetAt : Target.dispatchOwnedClause operation attachment (computation returned) (Defunctionalization.clauses clauses)
    (environment bindings) targetInside (value payload) (environment bodies) targetOutside owner before captured after targetStore
    targetPartition sourceCells.reservations = targetResult at matched
  cases matched with
  | @some _ targetAfter related =>
    have reserved : (cells sourceCells).reservations = sourceCells.reservations := Cells.reservations_mapBodies _ sourceCells
    refine ⟨targetAfter, ⟨⟨related.store, related.entry⟩, rfl, rfl⟩, .handled nearest accepted, ?_⟩
    apply Target.ExecutionSteps.single
    apply Target.ExecutionStep.handled nearestTarget
    simpa only [reserved] using targetAt

end Defunctionalization
end BoundaryV2.Generalized
