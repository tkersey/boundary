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
  | ordinary : Step table before after → CellStep table ⟨⟨store, before⟩, cells, regions⟩ ⟨⟨store, after⟩, cells, regions⟩
  | allocate
      {regionExpr : Expression signature algebra program context .region}
      {valueExpr : Expression signature algebra program context type}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program (.cell type) result}
      {store : ControlHeap signature algebra program}
      {cells : Cells signature algebra (Computation signature algebra program)}
      {value : RuntimeValue signature algebra program type} :
      regionExpr.evaluate bindings = .ok (.datum (.region region)) → valueExpr.evaluate bindings = .ok value →
      region ∈ regions → CellHandoff value store.fields fields →
      CellStep table ⟨⟨store, outside.plug (.evaluate (.cellNew regionExpr valueExpr) bindings)⟩, cells, regions⟩
        ⟨⟨{ store with fields := fields }, outside.plug (.returned (.cell (Cells.allocate region value cells reserved).identity region))⟩,
          (Cells.allocate region value cells reserved).cells, regions⟩
  | read
      {reference : Expression signature algebra program context (.cell type)}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program type result} :
      reference.evaluate bindings = .ok (.cell identity region) → region ∈ regions →
      Cells.readCopy identity region type cells = some value →
      CellStep table ⟨⟨store, outside.plug (.evaluate (.cellRead reference) bindings)⟩, cells, regions⟩
        ⟨⟨store, outside.plug (.returned value)⟩, cells, regions⟩
  | write
      {reference : Expression signature algebra program context (.cell type)}
      {replacement : Expression signature algebra program context type}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program .unit result} :
      reference.evaluate bindings = .ok (.cell identity region) → replacement.evaluate bindings = .ok value →
      region ∈ regions → Cells.writeCopy identity region value cells = some after →
      CellStep table ⟨⟨store, outside.plug (.evaluate (.cellWrite reference replacement) bindings)⟩, cells, regions⟩
        ⟨⟨store, outside.plug (.returned (.datum .unit))⟩, after, regions⟩

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
  | ordinary : CallStep table before after → CellStep table ⟨⟨store, before⟩, cells, regions⟩ ⟨⟨store, after⟩, cells, regions⟩
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

theorem CallSteps.with_cells (steps : CallSteps (table : Definitions signature algebra program) before count after)
    (store : ControlHeap signature algebra program)
    (cells : Cells signature algebra (fun context result => Code signature algebra program context [] result)) (regions : List (Id .region)) :
    CellSteps table ⟨⟨store, before⟩, cells, regions⟩ count ⟨⟨store, after⟩, cells, regions⟩ := by
  induction steps with
  | refl => exact .refl
  | cons step tail induction => exact .cons (.ordinary step) induction

def State.physicalInventory (state : State signature algebra program result) : List (Id .custody) :=
  UseScope.inventory state.control.store.fields ++ UseScope.tokens (Cells.fields state.cells)

theorem CellStep.conserves_physical_owners {before after : State signature algebra program result}
    (step : CellStep table before after) : before.physicalInventory.Perm after.physicalInventory := by
  cases step with
  | ordinary step | read live found => exact .refl _
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

theorem compiled_cell_read
    (table : Source.Definitions signature algebra program)
    (reference : Source.Expression signature algebra program context (.cell type))
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (identity : Id .cell) (region : Id .region) (value : Source.RuntimeValue signature algebra program type)
    (evaluated : reference.evaluate bindings = .ok (.cell identity region))
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program))
    (regions : List (Id .region)) (live : region ∈ regions)
    (read : Cells.readCopy identity region type sourceCells = some value)
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    {sourceOutside : Source.Context signature algebra program type result}
    {targetOutside : Target.Stack signature algebra program type result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    ∃ count, 0 < count ∧
      Source.CellStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.cellRead reference) bindings)⟩, sourceCells, regions⟩
        ⟨⟨sourceStore, sourceOutside.plug (.returned value)⟩, sourceCells, regions⟩ ∧
      Target.CellSteps (definitions table)
        ⟨⟨targetStore, .code (computation (.cellRead reference)) (environment bindings) .nil targetOutside⟩, cells sourceCells, regions⟩ count
        ⟨⟨targetStore, .returned (Defunctionalization.value value) targetOutside⟩, cells sourceCells, regions⟩ ∧
      CellStateRelated ⟨⟨sourceStore, sourceOutside.plug (.returned value)⟩, sourceCells, regions⟩
        ⟨⟨targetStore, .returned (Defunctionalization.value value) targetOutside⟩, cells sourceCells, regions⟩ := by
  have targetRead : Cells.readCopy identity region type (cells sourceCells) = some (Defunctionalization.value value) := by
    unfold cells
    rw [Cells.readCopy_mapBodies, read]
    rfl
  obtain ⟨count, operands⟩ := expression_drains reference bindings (.cellRead .ret) .nil _ evaluated
  refine ⟨count + 2, by omega, .read evaluated live read, ?_, ⟨⟨stores, .returned value outside⟩, rfl, rfl⟩⟩
  exact ((operands.in_context (definitions table) targetOutside).with_cells targetStore (cells sourceCells) regions).trans
    (.cons (.read live targetRead) (.cons (.ordinary .returned) .refl))

theorem compiled_cell_write
    (table : Source.Definitions signature algebra program)
    (reference : Source.Expression signature algebra program context (.cell type))
    (replacement : Source.Expression signature algebra program context type)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (identity : Id .cell) (region : Id .region) (value : Source.RuntimeValue signature algebra program type)
    (referenceEvaluated : reference.evaluate bindings = .ok (.cell identity region))
    (replacementEvaluated : replacement.evaluate bindings = .ok value)
    (sourceCells afterCells : Cells signature algebra (Source.Computation signature algebra program))
    (regions : List (Id .region)) (live : region ∈ regions)
    (written : Cells.writeCopy identity region value sourceCells = some afterCells)
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    {sourceOutside : Source.Context signature algebra program .unit result}
    {targetOutside : Target.Stack signature algebra program .unit result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    ∃ count, 0 < count ∧
      Source.CellStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.cellWrite reference replacement) bindings)⟩, sourceCells, regions⟩
        ⟨⟨sourceStore, sourceOutside.plug (.returned (.datum .unit))⟩, afterCells, regions⟩ ∧
      Target.CellSteps (definitions table)
        ⟨⟨targetStore, .code (computation (.cellWrite reference replacement)) (environment bindings) .nil targetOutside⟩, cells sourceCells, regions⟩ count
        ⟨⟨targetStore, .returned (.datum .unit) targetOutside⟩, cells afterCells, regions⟩ ∧
      CellStateRelated ⟨⟨sourceStore, sourceOutside.plug (.returned (.datum .unit))⟩, afterCells, regions⟩
        ⟨⟨targetStore, .returned (.datum .unit) targetOutside⟩, cells afterCells, regions⟩ := by
  have targetWritten : Cells.writeCopy identity region (Defunctionalization.value value) (cells sourceCells) = some (cells afterCells) := by
    unfold cells Defunctionalization.value
    rw [Cells.writeCopy_mapBodies, written]
    rfl
  obtain ⟨referenceCount, referenceSteps⟩ := expression_drains reference bindings (expression replacement (.cellWrite .ret)) .nil _ referenceEvaluated
  obtain ⟨replacementCount, replacementSteps⟩ := expression_drains replacement bindings (.cellWrite .ret)
    (.cons (.cell identity region) .nil) _ replacementEvaluated
  refine ⟨referenceCount + replacementCount + 2, by omega, .write referenceEvaluated replacementEvaluated live written,
    ?_, ⟨⟨stores, .returned (.datum .unit) outside⟩, rfl, rfl⟩⟩
  exact (((referenceSteps.trans replacementSteps).in_context (definitions table) targetOutside).with_cells
    targetStore (cells sourceCells) regions).trans (.cons (.write live targetWritten) (.cons (.ordinary .returned) .refl))

theorem compiled_cell_allocation
    (table : Source.Definitions signature algebra program)
    (regionExpr : Source.Expression signature algebra program context .region)
    (valueExpr : Source.Expression signature algebra program context type)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (region : Id .region) (value : Source.RuntimeValue signature algebra program type)
    (regionEvaluated : regionExpr.evaluate bindings = .ok (.datum (.region region)))
    (valueEvaluated : valueExpr.evaluate bindings = .ok value)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (reserved : List (Id .cell))
    (regions : List (Id .region)) (live : region ∈ regions)
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore) (fields : UseScope.State)
    (handoff : CellHandoff value sourceStore.fields fields)
    {sourceOutside : Source.Context signature algebra program (.cell type) result}
    {targetOutside : Target.Stack signature algebra program (.cell type) result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    let allocated := Cells.allocate region value sourceCells reserved
    ∃ count, 0 < count ∧
      Source.CellStep table ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.cellNew regionExpr valueExpr) bindings)⟩, sourceCells, regions⟩
        ⟨⟨{ sourceStore with fields := fields }, sourceOutside.plug (.returned (.cell allocated.identity region))⟩, allocated.cells, regions⟩ ∧
      Target.CellSteps (definitions table)
        ⟨⟨targetStore, .code (computation (.cellNew regionExpr valueExpr)) (environment bindings) .nil targetOutside⟩, cells sourceCells, regions⟩ count
        ⟨⟨{ targetStore with fields := fields }, .returned (.cell allocated.identity region) targetOutside⟩, cells allocated.cells, regions⟩ ∧
      CellStateRelated
        ⟨⟨{ sourceStore with fields := fields }, sourceOutside.plug (.returned (.cell allocated.identity region))⟩, allocated.cells, regions⟩
        ⟨⟨{ targetStore with fields := fields }, .returned (.cell allocated.identity region) targetOutside⟩, cells allocated.cells, regions⟩ := by
  dsimp only
  have allocation := Cells.allocate_mapBodies (fun _ _ body => computation body) region value sourceCells reserved
  have targetHandoff := cell_handoff_corresponds value handoff
  rw [stores.fields] at targetHandoff
  obtain ⟨regionCount, regionSteps⟩ := expression_drains regionExpr bindings (expression valueExpr (.cellNew .ret)) .nil _ regionEvaluated
  obtain ⟨valueCount, valueSteps⟩ := expression_drains valueExpr bindings (.cellNew .ret)
    (.cons (.datum (.region region)) .nil) _ valueEvaluated
  refine ⟨regionCount + valueCount + 2, by omega, .allocate regionEvaluated valueEvaluated live handoff, ?_,
    ⟨⟨⟨rfl, stores.controls, stores.disposing⟩, .returned (.cell _ region) outside⟩, rfl, rfl⟩⟩
  apply (((regionSteps.trans valueSteps).in_context (definitions table) targetOutside).with_cells
    targetStore (cells sourceCells) regions).trans
  have entered := Target.CellSteps.cons (Target.CellStep.allocate (table := definitions table) (reserved := reserved)
    (next := .ret) (bindings := environment bindings) (values := .nil) (outside := targetOutside) (cells := cells sourceCells) live targetHandoff)
    (Target.CellSteps.cons (.ordinary .returned) .refl)
  simpa only [Defunctionalization.value, cells, allocation.1, allocation.2] using entered

end Defunctionalization
end BoundaryV2.Generalized
