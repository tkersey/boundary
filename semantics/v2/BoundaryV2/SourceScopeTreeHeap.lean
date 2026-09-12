import BoundaryV2.SourceScopeTree

namespace BoundaryV2.Profile.Source.Machine
namespace ScopeTree

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem makeClosureWithValues_formed (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (values : List Located) (after : Transition)
    (formed : Formed machine.heap)
    (accepted : makeClosureWithValues machine context schema function values = .ok after) : Formed after.state.heap := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, ⟨middle, owner⟩, temporaryOk, heap, moved, ⟨store, result⟩, allocated, finished⟩ := accepted
  exact finishTemporary_formed (allocate_formed _ _ _ _ _ _ _ allocated
    (move_formed (temporary_formed formed temporaryOk) moved)) finished

theorem makeClosure_formed (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (bindings : Environment) (after : Transition)
    (formed : Formed machine.heap)
    (accepted : makeClosure machine context schema function bindings = .ok after) : Formed after.state.heap := by
  simp only [makeClosure, bind] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → makeClosureWithValues_formed]

theorem commitPure_formed (machine : State) (opcode : Opcode) (operands : List Located)
    (result : SemanticValue) (after : Transition) (formed : Formed machine.heap)
    (accepted : commitPure machine opcode operands result = .ok after) : Formed after.state.heap := by
  simp only [commitPure, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, accepted⟩ := accepted
  have next := temporary_formed formed temporaryOk
  split at accepted
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, _, _, _, finished⟩ := accepted
    exact finishTemporary_formed next finished
  · simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨heap, moved, _, _, custody, _, finished⟩ := accepted
    have movedFormed := move_formed next moved
    exact finishTemporary_formed movedFormed finished

theorem authoredFailure_formed (machine : State) (context : Context)
    (failures : List (InstructionFailure .source)) (fault : Fault) (after : Transition)
    (formed : Formed machine.heap)
    (accepted : authoredFailure machine context failures fault = .ok after) : Formed after.state.heap := by
  simp only [authoredFailure, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  exact formed

theorem heapPrimitive_formed (machine : State) (context : Context) (operation : Primitives.GraphOperation)
    (schema : SchemaId .source) (immediate : Nat) (operands : List Located) (after : Transition)
    (formed : Formed machine.heap)
    (accepted : heapPrimitive machine context operation schema immediate operands = .ok after) : Formed after.state.heap := by
  cases operation <;> simp only [heapPrimitive, bind, except_bind_ok, fromOption_ok] at accepted
  case computation =>
    obtain ⟨_, _, _, _, accepted⟩ := accepted
    exact makeClosureWithValues_formed _ _ _ _ _ _ formed accepted
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
    have movedFormed := move_formed (temporary_formed formed temporaryOk) moveOk
    have next := allocate_formed {moved with nextCell := moved.nextCell + 1} store _ _ _ _ _ allocated movedFormed
    exact finishTemporary_formed next finished
  case cellGet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact scopedValue_formed _ _ _ formed accepted
  case cellSet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, store, replaced, accepted⟩ := accepted
    have next := replace_formed formed replaced
    exact scopedValue_formed _ _ _ next accepted
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
    exact finishTemporary_formed (allocate_formed _ _ _ _ _ _ _ allocated
      (move_formed (temporary_formed formed temporaryOk) moveOk)) finished
  case unpack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, store, retired, accepted⟩ := accepted
    exact commitPure_formed _ _ _ _ _ (retire_formed formed retired) accepted
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
    exact finishTemporary_formed (allocate_formed _ _ _ _ _ _ _ allocated
      (temporary_formed (retire_formed formed retireOk) temporaryOk)) finished
  case resourcePack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, ⟨middle, owner⟩, temporaryOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    exact finishTemporary_formed (allocate_formed _ _ _ _ _ _ _ allocated
      (temporary_formed formed temporaryOk)) finished
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
      exact scopedValue_formed _ _ _ (retire_formed formed retired) accepted
    case borrow =>
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      exact scopedValue_formed _ _ _ formed accepted

theorem executePrimitive_formed (machine : State) (context : Context) (after : Transition)
    (formed : Formed machine.heap)
    (accepted : executePrimitive machine context = .ok after) : Formed after.state.heap := by
  unfold executePrimitive at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · exact authoredFailure_formed _ _ _ _ _ formed accepted
  · exact commitPure_formed _ _ _ _ _ formed accepted
  · exact heapPrimitive_formed _ _ _ _ _ _ _ formed accepted

theorem invokeFunction_formed (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (formed : Formed machine.heap)
    (accepted : invokeFunction machine context function bindings arguments = .ok after) : Formed after.state.heap := by
  simp only [invokeFunction, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, ⟨middle, entered⟩, created, rfl⟩ := accepted
  exact createScope_formed _ _ _ _ _ _ _ _ formed (by simp) created

theorem applyClosure_formed (machine : State) (context : Context) (closure : Located)
    (arguments : List Located) (after : Transition) (formed : Formed machine.heap)
    (accepted : applyClosure machine context closure arguments = .ok after) : Formed after.state.heap := by
  unfold applyClosure at accepted
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨⟨node, object⟩, _, accepted⟩ := accepted
  cases object <;> try contradiction
  simp only at accepted
  split at accepted <;> try contradiction
  · simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨heap, retired, invoked⟩ := accepted
    exact invokeFunction_formed _ _ _ _ _ _ (retire_formed formed retired) invoked
  · simp only [pure, Except.pure, Except.bind] at accepted
    exact invokeFunction_formed _ _ _ _ _ _ formed accepted

end ScopeTree
end BoundaryV2.Profile.Source.Machine
