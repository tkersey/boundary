import BoundaryV2.SourceIdentityExecution
import BoundaryV2.SourceInitialLaws

namespace BoundaryV2.Profile.Source.Machine
namespace CellIdentities

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

def identity : Object → Option CellId
  | .cell cell _ _ _ => some cell
  | _ => none

def atNode (heap : Heap) (node : NodeId) : Option CellId := (heap.lookup node).bind identity

/-- A logical mutable-cell identity names one physical source heap node. -/
def Unique (heap : Heap) : Prop := ∀ left right cell,
  atNode heap left = some cell → atNode heap right = some cell → left = right

private theorem ref_eq {left right : Ref space domain} (same : left.value = right.value) : left = right := by
  cases left; cases right
  simpa only [Ref.mk.injEq] using same

theorem unique_of_restriction (formed : Unique before)
    (retained : ∀ node cell, atNode after node = some cell → atNode before node = some cell) : Unique after :=
  fun left right cell first second => formed left right cell (retained _ _ first) (retained _ _ second)

theorem initial_unique (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) : Unique machine.heap := by
  have noObjects := (initialization_excludes_hidden_handles _ _ _ accepted).2.1
  intro left right cell found
  simp [atNode, Heap.lookup, noObjects] at found

private theorem append_lookup (heap : Heap) (stored : Object) (node : NodeId) (object : Object)
    (found : ({heap with objects := heap.objects ++ [some stored]} : Heap).lookup node = some object) :
    heap.lookup node = some object ∨ node.value = heap.objects.length ∧ object = stored := by
  by_cases old : node.value < heap.objects.length
  · exact Or.inl (by simpa only [Heap.lookup, List.getElem?_append_left old] using found)
  · have high : heap.objects.length ≤ node.value := Nat.le_of_not_gt old
    simp only [Heap.lookup, List.getElem?_append_right high] at found
    cases distance : node.value - heap.objects.length with
    | zero =>
      simp only [distance, List.getElem?_cons_zero, Option.bind_some, id_eq, Option.some.injEq] at found
      exact Or.inr ⟨by omega, found.symm⟩
    | succ n => simp [distance] at found

theorem append_unique (formed : Unique heap)
    (fresh : ∀ cell ∈ identity stored, ∀ node, atNode heap node ≠ some cell) :
    Unique {heap with objects := heap.objects ++ [some stored]} := by
  intro left right cell first second
  obtain ⟨firstObject, firstAt, firstCell⟩ := Option.bind_eq_some_iff.mp first
  obtain ⟨secondObject, secondAt, secondCell⟩ := Option.bind_eq_some_iff.mp second
  rcases append_lookup _ _ _ _ firstAt with firstOld | ⟨firstIndex, rfl⟩
  · rcases append_lookup _ _ _ _ secondAt with secondOld | ⟨secondIndex, rfl⟩
    · exact formed _ _ _ (Option.bind_eq_some_iff.mpr ⟨_, firstOld, firstCell⟩)
        (Option.bind_eq_some_iff.mpr ⟨_, secondOld, secondCell⟩)
    · exact False.elim (fresh cell secondCell left (Option.bind_eq_some_iff.mpr ⟨_, firstOld, firstCell⟩))
  · rcases append_lookup _ _ _ _ secondAt with secondOld | ⟨secondIndex, rfl⟩
    · exact False.elim (fresh cell firstCell right (Option.bind_eq_some_iff.mpr ⟨_, secondOld, secondCell⟩))
    · exact ref_eq (firstIndex.trans secondIndex.symm)

theorem identity_bounded (bounded : IdentitySupport.HeapValid (IdentitySupport.limits heap) heap)
    (found : atNode heap node = some cell) : cell.value < heap.nextCell := by
  obtain ⟨stored, storedAt, cellAt⟩ := Option.bind_eq_some_iff.mp found
  have storedBound := IdentitySupport.heap_lookup bounded storedAt
  cases stored <;> try contradiction
  cases cellAt
  exact storedBound.1

theorem allocate_unique (heap after : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (result : Located)
    (accepted : allocateObject heap schema stored owner exclusive = some (after, result))
    (formed : Unique heap) (fresh : ∀ cell ∈ identity stored, ∀ node, atNode heap node ≠ some cell) : Unique after := by
  have appended := append_unique formed fresh
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, _⟩ := accepted; exact appended
  · obtain ⟨_, _, rfl, _⟩ := accepted; exact appended

theorem move_unique (formed : Unique heap) (accepted : moveValues heap values receiver = some after) : Unique after := by
  simp [moveValues, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  exact formed

theorem consume_unique (formed : Unique heap) (accepted : consumeValue heap value = some after) : Unique after := by
  simp [consumeValue, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  exact formed

theorem replace_unique (heap after : Heap) (node : NodeId) (old stored : Object)
    (looked : heap.lookup node = some old) (same : identity stored = identity old)
    (replaced : replaceObject heap node stored = some after) (formed : Unique heap) : Unique after := by
  have changed := replace_object_updates_only_selected_node _ _ _ _ replaced
  apply unique_of_restriction formed
  intro selected cell found
  by_cases isSelected : selected = node
  · subst selected
    simpa only [atNode, changed.1, Option.bind_some, same, looked] using found
  · simpa only [atNode, changed.2 selected isSelected] using found

theorem retire_unique (heap after : Heap) (value : Located)
    (retired : retireObject heap value = some after) (formed : Unique heap) : Unique after := by
  unfold retireObject at retired
  split at retired <;> try contradiction
  rename_i schema node token shape
  simp only [bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at retired
  obtain ⟨_, _, middle, consumed, rfl⟩ := retired
  have middleUnique := consume_unique formed consumed
  apply unique_of_restriction middleUnique
  intro selected cell found
  by_cases selectedNode : node.value = selected.value
  · simp only [atNode, Heap.lookup, selectedNode, List.getElem?_set_self'] at found
    cases entry : middle.objects[selected.value]? <;> simp [entry] at found
  · simpa only [atNode, Heap.lookup, List.getElem?_set_ne selectedNode] using found

theorem temporary_unique (formed : Unique machine.heap)
    (accepted : temporary machine = .ok (after, owner)) : Unique after.heap := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  exact formed

theorem finishTemporary_unique (formed : Unique machine.heap)
    (accepted : finishTemporary machine value = .ok after) : Unique after.state.heap := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  cases accepted
  exact formed

theorem scopedValue_unique (formed : Unique machine.heap)
    (accepted : scopedValue machine value = .ok after) : Unique after.state.heap := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, finished⟩ := accepted
  exact finishTemporary_unique (temporary_unique formed temporaryOk) finished

end CellIdentities
end BoundaryV2.Profile.Source.Machine
