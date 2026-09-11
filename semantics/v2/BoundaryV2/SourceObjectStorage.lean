import BoundaryV2.SourceObjectSchemas

namespace BoundaryV2.Profile.Source.Machine
namespace ObjectSchemas
namespace Preservation

variable {source : Module}

def StoredValid (source : Module) (objects : List (Option Object)) : Prop :=
  ObjectSchemas.Valid source objects ∧ FrozenContracts.HeapValid { objects := objects }

def Preserves {source : Module} (before after : List (Option Object)) : Prop :=
  StoredValid source before → StoredValid source after

theorem Preserves.refl (objects : List (Option Object)) : Preserves (source := source) objects objects := fun valid => valid

theorem Preserves.trans (first : Preserves (source := source) before middle)
    (second : Preserves (source := source) middle after) : Preserves (source := source) before after :=
  fun valid => second (first valid)

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

private theorem require_ok (condition : Bool) (reason : Invalid) (result : Unit)
    (accepted : require condition reason = .ok result) : condition = true := by
  unfold require at accepted
  split at accepted <;> first | assumption | contradiction

theorem move_preserves (before after : Heap) (values : List Located) (receiver : Nat → Custody.Owner)
    (accepted : moveValues before values receiver = some after) : Preserves (source := source) before.objects after.objects := by
  simp [moveValues, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  exact .refl _

theorem allocate_preserves (before after : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject before schema stored owner exclusive = some (after, value))
    (storedValid : ObjectSchemas.ObjectValid source stored ∧ FrozenContracts.ObjectValid before stored) :
    Preserves (source := source) before.objects after.objects := by
  intro valid
  exact ⟨ObjectSchemas.allocate_valid source before after schema stored owner exclusive value accepted valid.1 storedValid.1,
    FrozenContracts.Preservation.allocate_preserves _ _ _ _ _ _ _ accepted storedValid.2 valid.2⟩

theorem replace_preserves (before after : Heap) (node : NodeId) (old stored : Object)
    (looked : before.lookup node = some old) (same : CellStability.signature stored = CellStability.signature old)
    (accepted : replaceObject before node stored = some after)
    (storedValid : ObjectSchemas.ObjectValid source stored ∧ FrozenContracts.ObjectValid before stored) :
    Preserves (source := source) before.objects after.objects := by
  intro valid
  exact ⟨ObjectSchemas.replace_valid source before after node stored accepted valid.1 storedValid.1,
    FrozenContracts.Preservation.replace_preserves _ _ _ _ _ looked same accepted storedValid.2 valid.2⟩

theorem retire_noncell_preserves (machine : State) (value : Located) (node : NodeId) (stored : Object) (after : Heap)
    (looked : lookupObject machine value = .ok (node, stored)) (noncell : CellStability.signature stored = none)
    (accepted : retireObject machine.heap value = some after) : Preserves (source := source) machine.heap.objects after.objects := by
  intro valid
  exact ⟨ObjectSchemas.retire_valid source machine.heap after value accepted valid.1,
    FrozenContracts.Preservation.retire_noncell_preserves _ _ _ _ _ looked noncell accepted valid.2⟩

theorem temporary_preserves (before after : State) (owner : Custody.Owner)
    (accepted : temporary before = .ok (after, owner)) : Preserves (source := source) before.heap.objects after.heap.objects := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted; exact .refl _

theorem finishTemporary_preserves (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) : Preserves (source := source) machine.heap.objects after.state.heap.objects := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  cases accepted; exact .refl _

theorem scopedValue_preserves (machine : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue machine value = .ok after) : Preserves (source := source) machine.heap.objects after.state.heap.objects := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, finished⟩ := accepted
  exact (temporary_preserves (source := source) _ _ _ temporaryOk).trans (finishTemporary_preserves (source := source) _ _ _ finished)

theorem commitPure_preserves (machine : State) (opcode : Opcode) (operands : List Located) (value : SemanticValue)
    (after : Transition) (accepted : commitPure machine opcode operands value = .ok after) :
    Preserves (source := source) machine.heap.objects after.state.heap.objects := by
  simp only [commitPure, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, accepted⟩ := accepted
  have first := temporary_preserves (source := source) _ _ _ temporaryOk
  split at accepted <;> simp only [except_bind_ok, fromOption_ok] at accepted
  · obtain ⟨_, _, _, _, finished⟩ := accepted
    exact first.trans (finishTemporary_preserves (source := source) _ _ _ finished)
  · obtain ⟨store, moved, _, _, _, _, finished⟩ := accepted
    have second := move_preserves (source := source) _ _ _ _ moved
    have third := finishTemporary_preserves (source := source) _ _ _ finished
    exact first.trans (second.trans third)

theorem makeClosureWithValues_preserves (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues machine context schema function values = .ok after) :
    Preserves (source := context.source) machine.heap.objects after.state.heap.objects := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, ⟨middle, owner⟩, temporaryOk, moved, movedOk, ⟨store, result⟩, allocated, finished⟩ := accepted
  have first := temporary_preserves (source := context.source) _ _ _ temporaryOk
  have second := move_preserves (source := context.source) _ _ _ _ movedOk
  have third := allocate_preserves (source := context.source) _ _ _ _ _ _ _ allocated (by simp only [ObjectSchemas.ObjectValid, FrozenContracts.ObjectValid]; grind only [→ require_ok, retainAt])
  have fourth := finishTemporary_preserves (source := context.source) _ _ _ finished
  exact first.trans (second.trans (third.trans fourth))

theorem makeClosure_preserves (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (bindings : Environment) (after : Transition)
    (accepted : makeClosure machine context schema function bindings = .ok after) :
    Preserves (source := context.source) machine.heap.objects after.state.heap.objects := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  exact makeClosureWithValues_preserves _ _ _ _ _ _ accepted

theorem enterExpression_preserves (machine : State) (context : Context) (after : Transition)
    (accepted : enterExpression machine context = .ok after) : Preserves (source := context.source) machine.heap.objects after.state.heap.objects := by
  unfold enterExpression at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨schema, expression⟩, _, accepted⟩ := accepted
  cases expression with
  | «variable» =>
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
    exact .refl _
  | literal =>
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, accepted⟩ := accepted
    exact scopedValue_preserves (source := context.source) _ _ _ accepted
  | lambda => exact makeClosure_preserves _ _ _ _ _ _ accepted
  | primitive _ operands => cases operands <;> cases accepted <;> exact .refl _

theorem authoredFailure_preserves (machine : State) (context : Context) (failures : List (InstructionFailure .source))
    (fault : Fault) (after : Transition) (accepted : authoredFailure machine context failures fault = .ok after) :
    Preserves (source := context.source) machine.heap.objects after.state.heap.objects := by
  simp only [authoredFailure, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  exact .refl _

theorem heapPrimitive_preserves (machine : State) (context : Context) (operation : Primitives.GraphOperation)
    (schema : SchemaId .source) (immediate : Nat) (operands : List Located) (after : Transition)
    (accepted : heapPrimitive machine context operation schema immediate operands = .ok after) :
    Preserves (source := context.source) machine.heap.objects after.state.heap.objects := by
  cases operation <;> simp only [heapPrimitive, bind, except_bind_ok, fromOption_ok] at accepted
  case computation =>
    obtain ⟨_, _, _, _, accepted⟩ := accepted
    exact makeClosureWithValues_preserves _ _ _ _ _ _ accepted
  case cellNew =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, ⟨middle, owner⟩, temporaryOk, moved, moveOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have first := temporary_preserves (source := context.source) _ _ _ temporaryOk
    have second := move_preserves (source := context.source) _ _ _ _ moveOk
    have third := allocate_preserves (source := context.source) _ _ _ _ _ _ _ allocated (by simp only [ObjectSchemas.ObjectValid, FrozenContracts.ObjectValid]; grind only [→ require_ok, retainAt])
    have fourth := finishTemporary_preserves (source := context.source) _ _ _ finished
    exact first.trans (second.trans (third.trans fourth))
  case cellGet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact scopedValue_preserves (source := context.source) _ _ _ accepted
  case cellSet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    rename_i identity cellSchema region content
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, checked, _, _, _, _, store, replaced, accepted⟩ := accepted
    have same := (Bool.and_eq_true_iff.mp (require_ok _ _ _ checked)).1
    simp only [beq_iff_eq] at same
    have atNode := (CellStability.lookupObject_reference _ _ _ _ looked).2
    intro valid
    have storedValid := ObjectSchemas.heap_lookup context.source machine.heap node _ atNode valid.1
    have first := replace_preserves (source := context.source) _ _ _ _ _ atNode (by simp [CellStability.signature, retainAt, same]) replaced (by simp only [ObjectSchemas.ObjectValid, FrozenContracts.ObjectValid]; grind only [ObjectSchemas.ObjectValid, retainAt])
    exact scopedValue_preserves (source := context.source) _ _ _ accepted (first valid)
  case package =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, ⟨middle, owner⟩, temporaryOk, moved, moveOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have first := temporary_preserves (source := context.source) _ _ _ temporaryOk
    have second := move_preserves (source := context.source) _ _ _ _ moveOk
    have third := allocate_preserves (source := context.source) _ _ _ _ _ _ _ allocated (by simp only [ObjectSchemas.ObjectValid, FrozenContracts.ObjectValid]; grind only [→ require_ok, retainAt])
    have fourth := finishTemporary_preserves (source := context.source) _ _ _ finished
    exact first.trans (second.trans (third.trans fourth))
  case unpack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, store, retired, accepted⟩ := accepted
    have first := retire_noncell_preserves (source := context.source) _ _ _ _ _ looked rfl retired
    exact first.trans (commitPure_preserves (source := context.source) _ _ _ _ _ accepted)
  case cloneResumption =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, retired, retireOk, ⟨middle, owner⟩, temporaryOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have first := retire_noncell_preserves (source := context.source) _ _ _ _ _ looked rfl retireOk
    have second := temporary_preserves (source := context.source) _ _ _ temporaryOk
    intro heapValid
    have originalValid := FrozenContracts.heap_lookup _ _ _ (CellStability.lookupObject_reference _ _ _ _ looked).2 heapValid.2
    have stable := (CellStability.retire_noncell_preserves _ _ _ _ _ looked rfl retireOk).trans
      (CellStability.temporary_preserves _ _ _ temporaryOk)
    have third := allocate_preserves (source := context.source) _ _ _ _ _ _ _ allocated
      (by refine ⟨?_, FrozenContracts.object_stability_preserves _ _ _ stable originalValid⟩; simp only [ObjectSchemas.ObjectValid]; grind only [→ require_ok])
    have fourth := finishTemporary_preserves (source := context.source) _ _ _ finished
    exact fourth (third (second (first heapValid)))
  case resourcePack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, ⟨middle, owner⟩, temporaryOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have first := temporary_preserves (source := context.source) _ _ _ temporaryOk
    have second := allocate_preserves (source := context.source) _ _ _ _ _ _ _ allocated (by simp only [ObjectSchemas.ObjectValid, FrozenContracts.ObjectValid]; grind only [→ require_ok, retainAt])
    have third := finishTemporary_preserves (source := context.source) _ _ _ finished
    exact first.trans (second.trans third)
  case resourceUnpack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, ⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    case resource =>
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, store, retired, accepted⟩ := accepted
      have first := retire_noncell_preserves (source := context.source) _ _ _ _ _ looked rfl retired
      exact first.trans (scopedValue_preserves (source := context.source) _ _ _ accepted)
    case borrow =>
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      exact scopedValue_preserves (source := context.source) _ _ _ accepted

theorem executePrimitive_preserves (machine : State) (context : Context) (after : Transition)
    (accepted : executePrimitive machine context = .ok after) : Preserves (source := context.source) machine.heap.objects after.state.heap.objects := by
  unfold executePrimitive at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · contradiction
  · exact authoredFailure_preserves _ _ _ _ _ accepted
  · exact commitPure_preserves (source := context.source) _ _ _ _ _ accepted
  · exact heapPrimitive_preserves _ _ _ _ _ _ _ accepted


end Preservation
end ObjectSchemas
end BoundaryV2.Profile.Source.Machine
