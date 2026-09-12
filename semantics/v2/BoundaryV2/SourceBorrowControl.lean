import BoundaryV2.SourceBorrowStorage

namespace BoundaryV2.Profile.Source.Machine
namespace BorrowRegistry

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

theorem heapPrimitive_valid (machine : State) (context : Context) (operation : Primitives.GraphOperation)
    (schema : SchemaId .source) (immediate : Nat) (operands : List Located) (after : Transition)
    (valid : Valid machine.heap)
    (accepted : heapPrimitive machine context operation schema immediate operands = .ok after) : Valid after.state.heap := by
  cases operation <;> simp only [heapPrimitive, bind, except_bind_ok, fromOption_ok] at accepted
  case computation =>
    obtain ⟨_, _, _, _, accepted⟩ := accepted
    exact makeClosureWithValues_valid _ _ _ _ _ _ accepted valid
  case cellNew =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, ⟨middle, owner⟩, reserved, moved, movedAt, ⟨heap, result⟩, allocated, finished⟩ := accepted
    have next := move_valid _ _ _ _ movedAt (temporary_valid _ _ _ reserved valid)
    have staged : Valid {moved with nextCell := moved.nextCell + 1} := next
    have created := allocate_valid {moved with nextCell := moved.nextCell + 1} heap _ _ _ _ _ allocated staged (by trivial)
    exact finishTemporary_valid _ _ _ finished created
  case cellGet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact scopedValue_valid _ _ _ accepted valid
  case cellSet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, heap, replaced, accepted⟩ := accepted
    have next := replace_valid _ _ _ _ replaced valid (by trivial)
    exact scopedValue_valid _ _ _ accepted next
  case package =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, ⟨middle, owner⟩, reserved, moved, movedAt, ⟨heap, result⟩, allocated, finished⟩ := accepted
    have next := move_valid _ _ _ _ movedAt (temporary_valid _ _ _ reserved valid)
    have created := allocate_valid moved heap _ _ _ _ _ allocated next (by trivial)
    exact finishTemporary_valid _ _ _ finished created
  case unpack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, heap, retired, accepted⟩ := accepted
    exact commitPure_valid _ _ _ _ _ accepted (retire_valid _ _ _ retired valid)
  case cloneResumption =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    rename_i saved
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, cloneChecked, retired, retireOk, ⟨middle, owner⟩, reserved, ⟨heap, result⟩, allocated, finished⟩ := accepted
    have retiredValid := retire_valid _ _ _ retireOk valid
    have next := temporary_valid _ _ _ reserved retiredValid
    have created := allocate_valid _ _ _ _ _ _ _ allocated next (by trivial)
    exact finishTemporary_valid _ _ _ finished created
  case resourcePack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, ⟨middle, owner⟩, reserved, ⟨heap, result⟩, allocated, finished⟩ := accepted
    have next := temporary_valid _ _ _ reserved valid
    exact finishTemporary_valid _ _ _ finished (allocate_valid _ _ _ _ _ _ _ allocated next (by trivial))
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
      obtain ⟨_, _, heap, retired, accepted⟩ := accepted
      exact scopedValue_valid _ _ _ accepted (retire_valid _ _ _ retired valid)
    case borrow =>
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      exact scopedValue_valid _ _ _ accepted valid

theorem authoredFailure_valid (machine : State) (context : Context)
    (failures : List (InstructionFailure .source)) (fault : Fault) (after : Transition)
    (valid : Valid machine.heap) (accepted : authoredFailure machine context failures fault = .ok after) : Valid after.state.heap := by
  simp only [authoredFailure, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  exact valid

theorem executePrimitive_valid (machine : State) (context : Context) (after : Transition)
    (valid : Valid machine.heap) (accepted : executePrimitive machine context = .ok after) : Valid after.state.heap := by
  unfold executePrimitive at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · exact authoredFailure_valid _ _ _ _ _ valid accepted
  · exact commitPure_valid _ _ _ _ _ accepted valid
  · exact heapPrimitive_valid _ _ _ _ _ _ _ valid accepted


theorem enterTerm_valid (machine : State) (source : Module) (after : Transition)
    (accepted : enterTerm machine source = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  unfold enterTerm at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i authored found
  cases authored <;> simp only at accepted
  all_goals try split at accepted
  all_goals cases accepted; exact valid

theorem deliverOperand_valid (machine : State) (after : Transition)
    (accepted : deliverOperand machine = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  unfold deliverOperand at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  split at accepted <;> cases accepted <;> exact valid

theorem enterExpression_valid (machine : State) (context : Context) (after : Transition)
    (accepted : enterExpression machine context = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  unfold enterExpression at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨definition, _, accepted⟩ := accepted
  cases expression : definition.expression <;> simp only [expression] at accepted
  case «variable» var =>
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
    exact valid
  case literal literal =>
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, _, _, accepted⟩ := accepted
    exact scopedValue_valid _ _ _ accepted valid
  case lambda function => exact makeClosure_valid _ _ _ _ _ _ accepted valid
  case primitive opcode operands immediate failures =>
    cases operands <;> cases accepted <;> exact valid

theorem enterInvocation_valid (machine : State) (context : Context) (after : Transition)
    (accepted : enterInvocation machine context = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  unfold enterInvocation at accepted
  split at accepted <;> try contradiction
  exact invokeFunction_valid _ _ _ _ _ _ accepted valid

theorem enterBinding_valid (machine : State) (context : Context) (after : Transition)
    (accepted : enterBinding machine context = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  unfold enterBinding at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, created, rfl⟩ := accepted
  exact createScope_valid _ _ _ _ _ _ _ _ created valid

theorem enterPattern_valid (machine : State) (context : Context) (vars : List VariableId)
    (parts : List SemanticValue) (owner : Custody.Owner) (body : TermId) (bindings : Environment) (after : Transition)
    (accepted : enterPattern machine context vars parts owner body bindings = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, created, rfl⟩ := accepted
  exact createScope_valid _ _ _ _ _ _ _ _ created valid

theorem executeControlTerm_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executeControlTerm machine context = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  unfold executeControlTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    exact valid
  · cases accepted; exact valid
  · split at accepted <;> try contradiction
    exact applyClosure_valid _ _ _ _ _ accepted valid
  · split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, rfl⟩ := accepted
    exact valid
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact enterPattern_valid _ _ _ _ _ _ _ _ accepted valid
  · split at accepted <;> try contradiction
    exact enterPattern_valid _ _ _ _ _ _ _ _ accepted valid


theorem leaveScope_valid (machine : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition)
    (accepted : leaveScope machine parent invocation tail value = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  simp only [leaveScope, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, owner⟩, reserved, heap, moved, delivered, finished, rfl⟩ := accepted
  have entered : Valid machine.heap := valid
  have next := temporary_valid _ _ _ reserved entered
  have transferred := move_valid _ _ _ _ moved next
  have done := finishTemporary_valid _ _ _ finished transferred
  exact done

theorem leaveInvocation_valid (machine : State) (after : Transition)
    (accepted : leaveInvocation machine = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  unfold leaveInvocation at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i caller parent tail stacked
  exact leaveScope_valid _ _ _ _ _ _ accepted valid

theorem restoreResumeCaller_valid (machine : State) (after : Transition)
    (accepted : restoreResumeCaller machine = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  unfold restoreResumeCaller at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i caller parent tail stacked
  have entered : Valid machine.heap := valid
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨middle, owner⟩, reserved, heap, moved, finished⟩ := accepted
  have next := temporary_valid _ _ _ reserved entered
  exact finishTemporary_valid _ _ _ finished (move_valid _ _ _ _ moved next)

theorem leaveLexical_valid (machine : State) (after : Transition)
    (accepted : leaveLexical machine = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i scope tail stacked
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, record, _, parent, _, result, left, accepted⟩ := accepted
  have next := leaveScope_valid _ _ _ _ _ _ left valid
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨parentRecord, _, heap, moved, rfl⟩ := accepted
  have transferred := move_valid _ _ _ _ moved next
  exact transferred

theorem releaseScope_valid (machine : State) (after : Transition)
    (accepted : releaseScope machine = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  unfold releaseScope at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact valid

theorem finishDisposal_valid (machine : State) (after : Transition)
    (accepted : finishDisposal machine = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  unfold finishDisposal at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i remaining released invocation scope tail stacked
  cases accepted
  exact valid

theorem discardValues_valid (machine : State) (context : Context) (after : Transition)
    (accepted : discardValues machine context = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  unfold discardValues at accepted
  split at accepted <;> try contradiction
  split at accepted
  · cases accepted; exact valid
  · split at accepted
    · cases accepted; exact valid
    · simp only [bind, except_bind_ok] at accepted
      obtain ⟨⟨node, stored⟩, _, accepted⟩ := accepted
      cases stored <;> try contradiction
      all_goals simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
      all_goals obtain ⟨heap, retired, rfl⟩ := accepted
      all_goals have next := retire_valid _ _ _ retired valid
      all_goals exact next

end BorrowRegistry
end BoundaryV2.Profile.Source.Machine
