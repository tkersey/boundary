import BoundaryV2.SourceMachine
import BoundaryV2.SourceStorageLaws
import BoundaryV2.SourceCloneLaws

namespace BoundaryV2.Profile.Source.Machine
namespace CellStability

/-- Mutation changes cell contents, while its location, identity, declared
schema, region and content schema remain stable. -/
structure Signature where
  identity : CellId
  schema : SchemaId .source
  region : RegionInstanceId
  contentSchema : SchemaId .source
  deriving DecidableEq

def signature : Object → Option Signature
  | .cell identity schema region content => some ⟨identity, schema, region, content.value.schema⟩
  | _ => none

def view (objects : List (Option Object)) (node : NodeId) : Option Signature :=
  (objects[node.value]?.bind id).bind signature

def Preserves (before after : List (Option Object)) : Prop :=
  ∀ node shape, view before node = some shape → view after node = some shape

theorem Preserves.refl (objects : List (Option Object)) : Preserves objects objects := fun _ _ found => found

theorem Preserves.trans (first : Preserves before middle) (second : Preserves middle after) : Preserves before after :=
  fun node shape found => second node shape (first node shape found)

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

theorem append_preserves (before more : List (Option Object)) : Preserves before (before ++ more) := by
  intro node shape found
  have bounded : node.value < before.length := by
    by_cases bounded : node.value < before.length
    · exact bounded
    · simp [view, List.getElem?_eq_none (Nat.le_of_not_gt bounded)] at found
  simpa only [view, List.getElem?_append_left bounded] using found

theorem move_preserves (before after : Heap) (values : List Located) (receiver : Nat → Custody.Owner)
    (accepted : moveValues before values receiver = some after) : Preserves before.objects after.objects := by
  simp [moveValues, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  exact .refl _

theorem allocate_preserves (before after : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject before schema stored owner exclusive = some (after, value)) :
    Preserves before.objects after.objects := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, _⟩ := accepted; exact append_preserves _ _
  · obtain ⟨_, _, rfl, _⟩ := accepted; exact append_preserves _ _

theorem replace_preserves (before after : Heap) (node : NodeId) (old stored : Object)
    (looked : before.lookup node = some old) (same : signature stored = signature old)
    (accepted : replaceObject before node stored = some after) : Preserves before.objects after.objects := by
  have changed := replace_object_updates_only_selected_node before after node stored accepted
  intro other shape found
  change (after.lookup other).bind signature = some shape
  change (before.lookup other).bind signature = some shape at found
  by_cases equal : other = node
  · subst other
    rw [changed.1, Option.bind_some, same]
    simpa only [looked, Option.bind_some] using found
  · rw [changed.2 other equal]
    exact found

theorem lookupObject_reference (machine : State) (value : Located) (node : NodeId) (stored : Object)
    (accepted : lookupObject machine value = .ok (node, stored)) :
    (∃ schema token, value.value = .reference schema node token) ∧ machine.heap.lookup node = some stored := by
  simp only [lookupObject, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  rename_i schema foundNode token reference
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨foundObject, found, equal⟩ := accepted
  cases equal
  exact ⟨⟨schema, token, reference⟩, found⟩

theorem retire_noncell_preserves (machine : State) (value : Located) (node : NodeId) (stored : Object) (after : Heap)
    (looked : lookupObject machine value = .ok (node, stored)) (noncell : signature stored = none)
    (accepted : retireObject machine.heap value = some after) : Preserves machine.heap.objects after.objects := by
  obtain ⟨⟨schema, token, reference⟩, atNode⟩ := lookupObject_reference _ _ _ _ looked
  unfold retireObject at accepted
  rw [reference] at accepted
  cases token <;> try contradiction
  simp only [bind, Option.bind_eq_some_iff, consumeValue, pure, Option.some.injEq] at accepted
  obtain ⟨_, _, _, ⟨_, _, rfl⟩, rfl⟩ := accepted
  intro other shape found
  by_cases equal : node.value = other.value
  · have nodes : other = node := by cases other; cases node; simp_all
    subst other
    change (machine.heap.lookup node).bind signature = some shape at found
    simp only [atNode, Option.bind_some, noncell] at found
    cases found
  · simpa only [view, List.getElem?_set_ne equal] using found

theorem temporary_preserves (before after : State) (owner : Custody.Owner)
    (accepted : temporary before = .ok (after, owner)) : Preserves before.heap.objects after.heap.objects := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted; exact .refl _

theorem finishTemporary_preserves (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) : Preserves machine.heap.objects after.state.heap.objects := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  cases accepted; exact .refl _

theorem scopedValue_preserves (machine : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue machine value = .ok after) : Preserves machine.heap.objects after.state.heap.objects := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, finished⟩ := accepted
  exact (temporary_preserves _ _ _ temporaryOk).trans (finishTemporary_preserves _ _ _ finished)

theorem commitPure_preserves (machine : State) (opcode : Opcode) (operands : List Located) (value : SemanticValue)
    (after : Transition) (accepted : commitPure machine opcode operands value = .ok after) :
    Preserves machine.heap.objects after.state.heap.objects := by
  simp only [commitPure, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, accepted⟩ := accepted
  have first := temporary_preserves _ _ _ temporaryOk
  split at accepted <;> simp only [except_bind_ok, fromOption_ok] at accepted
  · obtain ⟨_, _, _, _, finished⟩ := accepted
    exact first.trans (finishTemporary_preserves _ _ _ finished)
  · obtain ⟨store, moved, _, _, _, _, finished⟩ := accepted
    have second := move_preserves _ _ _ _ moved
    have third := finishTemporary_preserves _ _ _ finished
    exact first.trans (second.trans third)

theorem makeClosureWithValues_preserves (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues machine context schema function values = .ok after) :
    Preserves machine.heap.objects after.state.heap.objects := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, ⟨middle, owner⟩, temporaryOk, moved, movedOk, ⟨store, result⟩, allocated, finished⟩ := accepted
  have first := temporary_preserves _ _ _ temporaryOk
  have second := move_preserves _ _ _ _ movedOk
  have third := allocate_preserves _ _ _ _ _ _ _ allocated
  have fourth := finishTemporary_preserves _ _ _ finished
  exact first.trans (second.trans (third.trans fourth))

theorem makeClosure_preserves (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (bindings : Environment) (after : Transition)
    (accepted : makeClosure machine context schema function bindings = .ok after) :
    Preserves machine.heap.objects after.state.heap.objects := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  exact makeClosureWithValues_preserves _ _ _ _ _ _ accepted

theorem enterExpression_preserves (machine : State) (context : Context) (after : Transition)
    (accepted : enterExpression machine context = .ok after) : Preserves machine.heap.objects after.state.heap.objects := by
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
    exact scopedValue_preserves _ _ _ accepted
  | lambda => exact makeClosure_preserves _ _ _ _ _ _ accepted
  | primitive _ operands => cases operands <;> cases accepted <;> exact .refl _

theorem authoredFailure_preserves (machine : State) (context : Context) (failures : List (InstructionFailure .source))
    (fault : Fault) (after : Transition) (accepted : authoredFailure machine context failures fault = .ok after) :
    Preserves machine.heap.objects after.state.heap.objects := by
  simp only [authoredFailure, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  exact .refl _

theorem heapPrimitive_preserves (machine : State) (context : Context) (operation : Primitives.GraphOperation)
    (schema : SchemaId .source) (immediate : Nat) (operands : List Located) (after : Transition)
    (accepted : heapPrimitive machine context operation schema immediate operands = .ok after) :
    Preserves machine.heap.objects after.state.heap.objects := by
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
    have first := temporary_preserves _ _ _ temporaryOk
    have second := move_preserves _ _ _ _ moveOk
    have third := allocate_preserves _ _ _ _ _ _ _ allocated
    have fourth := finishTemporary_preserves _ _ _ finished
    exact first.trans (second.trans (third.trans fourth))
  case cellGet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact scopedValue_preserves _ _ _ accepted
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
    have atNode := (lookupObject_reference _ _ _ _ looked).2
    have first := replace_preserves _ _ _ _ _ atNode (by simp [signature, retainAt, same]) replaced
    exact first.trans (scopedValue_preserves _ _ _ accepted)
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
    have first := temporary_preserves _ _ _ temporaryOk
    have second := move_preserves _ _ _ _ moveOk
    have third := allocate_preserves _ _ _ _ _ _ _ allocated
    have fourth := finishTemporary_preserves _ _ _ finished
    exact first.trans (second.trans (third.trans fourth))
  case unpack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, store, retired, accepted⟩ := accepted
    have first := retire_noncell_preserves _ _ _ _ _ looked rfl retired
    exact first.trans (commitPure_preserves _ _ _ _ _ accepted)
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
    have first := retire_noncell_preserves _ _ _ _ _ looked rfl retireOk
    have second := temporary_preserves _ _ _ temporaryOk
    have third := allocate_preserves _ _ _ _ _ _ _ allocated
    have fourth := finishTemporary_preserves _ _ _ finished
    exact first.trans (second.trans (third.trans fourth))
  case resourcePack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, ⟨middle, owner⟩, temporaryOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have first := temporary_preserves _ _ _ temporaryOk
    have second := allocate_preserves _ _ _ _ _ _ _ allocated
    have third := finishTemporary_preserves _ _ _ finished
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
      have first := retire_noncell_preserves _ _ _ _ _ looked rfl retired
      exact first.trans (scopedValue_preserves _ _ _ accepted)
    case borrow =>
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      exact scopedValue_preserves _ _ _ accepted

theorem executePrimitive_preserves (machine : State) (context : Context) (after : Transition)
    (accepted : executePrimitive machine context = .ok after) : Preserves machine.heap.objects after.state.heap.objects := by
  unfold executePrimitive at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · contradiction
  · exact authoredFailure_preserves _ _ _ _ _ accepted
  · exact commitPure_preserves _ _ _ _ _ accepted
  · exact heapPrimitive_preserves _ _ _ _ _ _ _ accepted


end CellStability
end BoundaryV2.Profile.Source.Machine
