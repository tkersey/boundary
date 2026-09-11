import BoundaryV2.SourceIdentityCleanup

namespace BoundaryV2.Profile.Source.Machine
namespace IdentitySupport

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

set_option maxRecDepth 4096 in
set_option maxHeartbeats 1600000 in
theorem heapPrimitive_valid (machine : State) (context : Context)
    (operation : Primitives.GraphOperation) (schema : SchemaId .source) (immediate : Nat)
    (operands : List Located) (after : Transition) (bounded : ValidAt limit machine)
    (upper : Upper limit after.state.heap)
    (accepted : heapPrimitive machine context operation schema immediate operands = .ok after) : ValidAt limit after.state := by
  cases operation <;> simp only [heapPrimitive, bind, except_bind_ok, fromOption_ok] at accepted
  case computation =>
    obtain ⟨⟨function, expected⟩, _, _, _, accepted⟩ := accepted
    exact makeClosureWithValues_valid _ _ _ _ _ _ bounded accepted
  case cellNew =>
    split at accepted <;> try contradiction
    rename_i regionValue initial
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, object⟩, looked, accepted⟩ := accepted
    split at accepted <;> try contradiction
    rename_i storedNode region descriptor invocation outer matched
    cases matched
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨shape, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, ⟨middle, owner⟩, temporaryOk, moved, moveOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have middleBound := temporary_valid bounded temporaryOk
    have movedBound := move_valid middleBound moveOk
    have regionBound := (lookupObject_bound bounded looked).1
    have same : moved.nextCell = middle.heap.nextCell := by
      simp [moveValues, Option.bind_eq_some_iff] at moveOk
      obtain ⟨_, _, rfl⟩ := moveOk
      rfl
    have high := upper_before ((allocateObject_allocation _ _ _ _ _ _ _ allocated).trans
      (finishTemporary_allocation _ _ _ finished).heap) upper .cell
    have fresh : Bound limit (⟨middle.heap.nextCell⟩ : CellId) := by
      change moved.nextCell + 1 ≤ limit .cell at high
      simp only [same] at high
      exact Nat.lt_of_lt_of_le (Nat.lt_succ_self _) high
    have seed : ValidAt limit {middle with heap := {moved with nextCell := moved.nextCell + 1}} :=
      ⟨⟨movedBound.heap.objects, movedBound.heap.scopes, movedBound.heap.invocations,
        movedBound.heap.obligations, movedBound.heap.loans⟩,
        movedBound.frames, movedBound.control, movedBound.scope, movedBound.invocation⟩
    exact finishTemporary_valid (allocate_valid seed (by exact ⟨fresh, regionBound⟩) allocated) finished
  case cellGet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, object⟩, looked, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact scopedValue_valid bounded accepted
  case cellSet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, object⟩, looked, accepted⟩ := accepted
    split at accepted <;> try contradiction
    rename_i storedNode identity cellSchema region content matched
    cases matched
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, shape, found, _, checked, store, replaced, accepted⟩ := accepted
    have old := lookupObject_bound bounded looked
    have changed := replace_heap bounded.heap (by exact old) replaced
    have next : ValidAt limit {machine with heap := store} :=
      ⟨changed, bounded.frames, bounded.control, bounded.scope, bounded.invocation⟩
    exact scopedValue_valid next accepted
  case package =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, object⟩, looked, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨shape, found, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, ⟨middle, owner⟩, temporaryOk, moved, moveOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    exact finishTemporary_valid (allocate_valid (move_valid (temporary_valid bounded temporaryOk) moveOk)
      (by trivial) allocated) finished
  case unpack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, object⟩, looked, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, store, retired, accepted⟩ := accepted
    exact commitPure_valid _ _ _ _ _ (retire_valid bounded retired) accepted
  case cloneResumption =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, object⟩, looked, accepted⟩ := accepted
    split at accepted <;> try contradiction
    rename_i storedNode capture matched
    cases matched
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨sourceShape, sourceAt, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨resultShape, resultAt, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, retired, retireOk, ⟨middle, owner⟩, temporaryOk,
      ⟨store, result⟩, allocated, finished⟩ := accepted
    have captureBound := lookupObject_bound bounded looked
    exact finishTemporary_valid (allocate_valid (temporary_valid (retire_valid bounded retireOk) temporaryOk)
      (by exact captureBound) allocated) finished
  case resourcePack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨shape, found, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, ⟨middle, owner⟩, temporaryOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    exact finishTemporary_valid (allocate_valid (temporary_valid bounded temporaryOk) (by trivial) allocated) finished
  case resourceUnpack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨shape, _, resourceShape, resourceAt, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨resource, resourceAt, invocation, invocationAt, _, checked, ⟨node, object⟩, looked, accepted⟩ := accepted
    split at accepted
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, store, retired, accepted⟩ := accepted
      exact scopedValue_valid (retire_valid bounded retired) accepted
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨identity, _, obligation, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, stored, storedAt, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      exact scopedValue_valid bounded accepted
    · contradiction

theorem executePrimitive_valid (machine : State) (context : Context) (after : Transition)
    (bounded : ValidAt limit machine) (upper : Upper limit after.state.heap)
    (accepted : executePrimitive machine context = .ok after) : ValidAt limit after.state := by
  unfold executePrimitive at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · exact authoredFailure_valid _ _ _ _ _ bounded accepted
  · exact commitPure_valid _ _ _ _ _ bounded accepted
  · exact heapPrimitive_valid _ _ _ _ _ _ _ bounded upper accepted

end IdentitySupport
end BoundaryV2.Profile.Source.Machine
