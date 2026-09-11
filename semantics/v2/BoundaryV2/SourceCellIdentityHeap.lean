import BoundaryV2.SourceCellIdentityClone
import BoundaryV2.SourcePrimitiveCustody

namespace BoundaryV2.Profile.Source.Machine
namespace CellIdentities

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem commitPure_unique (machine : State) (opcode : Opcode) (operands : List Located)
    (value : SemanticValue) (after : Transition) (formed : Unique machine.heap)
    (accepted : commitPure machine opcode operands value = .ok after) : Unique after.state.heap := by
  have same := (commitPure_retains_storage_and_supply _ _ _ _ _ accepted).1
  simpa only [Unique, atNode, Heap.lookup, same] using formed

theorem authoredFailure_unique (machine : State) (context : Context)
    (failures : List (InstructionFailure .source)) (fault : Fault) (after : Transition)
    (formed : Unique machine.heap)
    (accepted : authoredFailure machine context failures fault = .ok after) : Unique after.state.heap := by
  simp only [authoredFailure, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  exact formed

theorem heapPrimitive_unique (machine : State) (context : Context) (operation : Primitives.GraphOperation)
    (schema : SchemaId .source) (immediate : Nat) (operands : List Located) (after : Transition)
    (formed : Unique machine.heap) (bounded : IdentitySupport.Valid machine)
    (accepted : heapPrimitive machine context operation schema immediate operands = .ok after) : Unique after.state.heap := by
  cases operation <;> simp only [heapPrimitive, bind, except_bind_ok, fromOption_ok] at accepted
  case computation =>
    obtain ⟨_, _, _, _, accepted⟩ := accepted
    exact makeClosureWithValues_unique _ _ _ _ _ _ formed accepted
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
    have unchanged : middle.heap.objects = machine.heap.objects ∧ middle.heap.nextCell = machine.heap.nextCell := by
      unfold temporary at temporaryOk
      split at temporaryOk <;> try contradiction
      split at temporaryOk <;> try contradiction
      cases temporaryOk; exact ⟨rfl, rfl⟩
    have movedObjects : moved.objects = machine.heap.objects := by
      simp [moveValues, Option.bind_eq_some_iff] at moveOk
      obtain ⟨_, _, rfl⟩ := moveOk
      exact unchanged.1
    have fresh : ∀ cell ∈ some (⟨middle.heap.nextCell⟩ : CellId),
        ∀ node, atNode {moved with nextCell := moved.nextCell + 1} node ≠ some cell := by
      intro cell found node collision
      cases found
      have old : atNode machine.heap node = some (⟨middle.heap.nextCell⟩ : CellId) := by
        simpa only [atNode, Heap.lookup, movedObjects] using collision
      have below := identity_bounded bounded.heap old
      simp only [unchanged.2] at below
      omega
    have movedUnique := move_unique (temporary_unique formed temporaryOk) moveOk
    have next := allocate_unique _ _ _ _ _ _ _ allocated movedUnique fresh
    exact finishTemporary_unique next finished
  case cellGet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact scopedValue_unique formed accepted
  case cellSet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, store, replaced, accepted⟩ := accepted
    have next := replace_unique _ _ _ _ _ (CellStability.lookupObject_reference _ _ _ _ looked).2 (by rfl) replaced formed
    exact scopedValue_unique next accepted
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
    exact finishTemporary_unique (allocate_noncell_unique _ _ _ _ _ _ _ allocated rfl
      (move_unique (temporary_unique formed temporaryOk) moveOk)) finished
  case unpack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, store, retired, accepted⟩ := accepted
    exact commitPure_unique _ _ _ _ _ (retire_unique _ _ _ retired formed) accepted
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
    exact finishTemporary_unique (allocate_noncell_unique _ _ _ _ _ _ _ allocated rfl
      (temporary_unique (retire_unique _ _ _ retireOk formed) temporaryOk)) finished
  case resourcePack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, ⟨middle, owner⟩, temporaryOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    exact finishTemporary_unique (allocate_noncell_unique _ _ _ _ _ _ _ allocated rfl
      (temporary_unique formed temporaryOk)) finished
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
      exact scopedValue_unique (retire_unique _ _ _ retired formed) accepted
    case borrow =>
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      exact scopedValue_unique formed accepted

theorem executePrimitive_unique (machine : State) (context : Context) (after : Transition)
    (formed : Unique machine.heap) (bounded : IdentitySupport.Valid machine)
    (accepted : executePrimitive machine context = .ok after) : Unique after.state.heap := by
  unfold executePrimitive at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · exact authoredFailure_unique _ _ _ _ _ formed accepted
  · exact commitPure_unique _ _ _ _ _ formed accepted
  · exact heapPrimitive_unique _ _ _ _ _ _ _ formed bounded accepted

end CellIdentities
end BoundaryV2.Profile.Source.Machine
