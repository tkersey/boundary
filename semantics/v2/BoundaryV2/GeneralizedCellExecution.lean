import BoundaryV2.GeneralizedCellLowering
import BoundaryV2.GeneralizedControlExecution

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {Body : List (TypeOf signature) → TypeOf signature → Type}

/-- Ownership moves only once the cell initializer is complete. Copyable/plain
values need no owning-field transfer; an owned value moves its actual field. -/
inductive CellHandoff (value : Value signature algebra Body type) : UseScope.State → UseScope.State → Prop where
  | unowned : value.owningField.tokens = [] → CellHandoff value fields fields
  | move : CellHandoff value
      ⟨before ++ value.owningField :: after, retained, spent⟩ ⟨before ++ after, retained, spent⟩

theorem CellHandoff.conserves_owners (handoff : CellHandoff value before after) :
    (UseScope.inventory before).Perm (value.owningField.tokens ++ UseScope.inventory after) ∧ after.spent = before.spent := by
  cases handoff with
  | unowned empty => exact ⟨by simp only [empty, List.nil_append]; exact .refl _, rfl⟩
  | move =>
    constructor
    · simp only [UseScope.inventory, UseScope.tokens_append, UseScope.tokens, List.append_assoc]
      simpa only [List.append_assoc] using
        (List.perm_append_comm (l₁ := UseScope.tokens _) (l₂ := value.owningField.tokens)).append_right _
    · rfl

namespace Source

structure State (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  control : ControlState signature algebra program result
  cells : Cells signature algebra (Computation signature algebra program)
  liveRegions : List (Id .region)

variable {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (TypeOf signature)]

/-- Cell transitions act on source expressions and their source values. Region
liveness is explicit; establishing and closing region scopes is a separate rule. -/
inductive CellStep (table : Definitions signature algebra program) : State signature algebra program result → State signature algebra program result → Prop where
  | ordinary (step : Step table before after) (neutral : before.needsOwnershipStep = false := by rfl) :
      CellStep table ⟨⟨store, before⟩, cells, regions⟩ ⟨⟨store, after⟩, cells, regions⟩
  | allocate
      {regionExpr : Expression signature algebra program context .region}
      {valueExpr : Expression signature algebra program context type}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program (.cell type) result}
      {store : ControlHeap signature algebra program}
      {cells : Cells signature algebra (Computation signature algebra program)}
      {value : RuntimeValue signature algebra program type} :
      ArgumentsEvaluation bindings cells.reservations.custody store (.cons regionExpr (.cons valueExpr .nil))
        (.ok (.cons (.datum (.region region)) (.cons value .nil))) evaluated →
      region ∈ regions → CellHandoff value evaluated.fields fields →
      CellStep table ⟨⟨store, outside.plug (.evaluate (.cellNew regionExpr valueExpr) bindings)⟩, cells, regions⟩
        ⟨⟨{ evaluated with fields := fields }, outside.plug (.returned (.cell (Cells.allocate region value cells reserved).identity region))⟩,
          (Cells.allocate region value cells reserved).cells, regions⟩
  | read
      {reference : Expression signature algebra program context (.cell type)}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program type result}
      {cells : Cells signature algebra (Computation signature algebra program)} :
      ExpressionEvaluation bindings cells.reservations.custody store reference (.ok (.cell identity region)) evaluated → region ∈ regions →
      Cells.readCopy identity region type cells = some value →
      CellStep table ⟨⟨store, outside.plug (.evaluate (.cellRead reference) bindings)⟩, cells, regions⟩
        ⟨⟨evaluated, outside.plug (.returned value)⟩, cells, regions⟩
  | write
      {reference : Expression signature algebra program context (.cell type)}
      {replacement : Expression signature algebra program context type}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program .unit result}
      {cells : Cells signature algebra (Computation signature algebra program)} :
      ArgumentsEvaluation bindings cells.reservations.custody store (.cons reference (.cons replacement .nil))
        (.ok (.cons (.cell identity region) (.cons value .nil))) evaluated →
      region ∈ regions → Cells.writeCopy identity region value cells = some after →
      CellStep table ⟨⟨store, outside.plug (.evaluate (.cellWrite reference replacement) bindings)⟩, cells, regions⟩
        ⟨⟨evaluated, outside.plug (.returned (.datum .unit))⟩, after, regions⟩

end Source

namespace Target

structure State (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  control : ControlState signature algebra program result
  cells : Cells signature algebra (fun context result => Code signature algebra program context [] result)
  liveRegions : List (Id .region)

variable {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (TypeOf signature)]

inductive CellStep (table : Definitions signature algebra program) : State signature algebra program result → State signature algebra program result → Prop where
  | ordinary (step : CallStep table before after) (neutral : before.needsOwnershipStep = false := by rfl) :
      CellStep table ⟨⟨store, before⟩, cells, regions⟩ ⟨⟨store, after⟩, cells, regions⟩
  | allocate
      {next : Code signature algebra program context (.cell type :: operands) answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {values : RuntimeEnvironment signature algebra program operands}
      {outside : Stack signature algebra program answer result}
      {store : ControlHeap signature algebra program}
      {cells : Cells signature algebra (fun context result => Code signature algebra program context [] result)}
      {value : RuntimeValue signature algebra program type} :
      region ∈ regions → CellHandoff value store.fields fields →
      CellStep table ⟨⟨store, .code (.cellNew next) bindings (.cons value (.cons (.datum (.region region)) values)) outside⟩, cells, regions⟩
        ⟨⟨{ store with fields := fields }, .code next bindings
          (.cons (.cell (Cells.allocate region value cells reserved).identity region) values) outside⟩,
          (Cells.allocate region value cells reserved).cells, regions⟩
  | read
      {next : Code signature algebra program context (type :: operands) answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {values : RuntimeEnvironment signature algebra program operands}
      {outside : Stack signature algebra program answer result} :
      region ∈ regions → Cells.readCopy identity region type cells = some value →
      CellStep table ⟨⟨store, .code (.cellRead next) bindings (.cons (.cell identity region) values) outside⟩, cells, regions⟩
        ⟨⟨store, .code next bindings (.cons value values) outside⟩, cells, regions⟩
  | write
      {next : Code signature algebra program context (.unit :: operands) answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {values : RuntimeEnvironment signature algebra program operands}
      {outside : Stack signature algebra program answer result} :
      region ∈ regions → Cells.writeCopy identity region value cells = some after →
      CellStep table ⟨⟨store, .code (.cellWrite next) bindings (.cons value (.cons (.cell identity region) values)) outside⟩, cells, regions⟩
        ⟨⟨store, .code next bindings (.cons (.datum .unit) values) outside⟩, after, regions⟩

inductive CellSteps (table : Definitions signature algebra program) :
    State signature algebra program result → Nat → State signature algebra program result → Prop where
  | refl : CellSteps table state 0 state
  | cons : CellStep table before middle → CellSteps table middle count after → CellSteps table before (count + 1) after

theorem CellSteps.single {before after : State signature algebra program result}
    (step : CellStep table before after) : CellSteps table before 1 after := .cons step .refl

theorem CellSteps.trans {before middle after : State signature algebra program result}
    (first : CellSteps table before count middle) (second : CellSteps table middle rest after) :
    CellSteps table before (count + rest) after := by
  induction first with
  | refl => simpa using second
  | cons step tail induction => simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using CellSteps.cons step (induction second)

def State.physicalInventory (state : State signature algebra program result) : List (Id .custody) :=
  UseScope.inventory state.control.store.fields ++ UseScope.tokens (Cells.fields state.cells)

theorem CellStep.conserves_physical_owners {before after : State signature algebra program result}
    (step : CellStep table before after) : before.physicalInventory.Perm after.physicalInventory := by
  cases step with
  | ordinary step neutral | read live found => exact .refl _
  | write live written => simp only [State.physicalInventory, Cells.write_copy_preserves_ownership_inventory written]; exact .refl _
  | allocate live handoff =>
    have moved := handoff.conserves_owners
    simpa only [State.physicalInventory, Cells.allocation_holds_value_fields, UseScope.tokens, List.append_assoc] using
      (moved.1.append_right _).trans
        ((List.perm_append_comm (l₁ := _ ) (l₂ := UseScope.inventory _)).append_right _)

theorem CellSteps.conserves_physical_owners {before after : State signature algebra program result}
    (steps : CellSteps table before count after) : before.physicalInventory.Perm after.physicalInventory := by
  induction steps with
  | refl => exact .refl _
  | cons step tail induction => exact step.conserves_physical_owners.trans induction

end Target

namespace Defunctionalization

variable {program : List (BodyType signature.Data signature.Effect)} [DecidableEq (TypeOf signature)]

def cells (source : Cells signature algebra (Source.Computation signature algebra program)) :
    Cells signature algebra (fun context result => Target.Code signature algebra program context [] result) :=
  source.mapBodies (fun _ _ body => computation body)

structure CellStateRelated (source : Source.State signature algebra program result)
    (target : Target.State signature algebra program result) : Prop where
  control : ControlStateRelated source.control target.control
  cells : target.cells = Defunctionalization.cells source.cells
  regions : source.liveRegions = target.liveRegions

omit [DecidableEq (TypeOf signature)] in
theorem cell_handoff_corresponds
    (value : Source.RuntimeValue signature algebra program type) (handoff : CellHandoff value before after) :
    CellHandoff (Defunctionalization.value value) before after := by
  cases handoff with
  | unowned empty => exact .unowned (by simpa only [Defunctionalization.value, Value.map_preserves_owning_fields] using empty)
  | move => simpa only [Defunctionalization.value, Value.map_preserves_owning_fields] using
      (CellHandoff.move (value := Defunctionalization.value value))

end Defunctionalization
end BoundaryV2.Generalized
