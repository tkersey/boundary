import BoundaryV2.SourceObligationCapture

namespace BoundaryV2.Profile.Source.Machine
namespace ObligationLocations

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
    (valid : Valid machine)
    (accepted : heapPrimitive machine context operation schema immediate operands = .ok after) : Valid after.state := by
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
    have staged := same_storage_valid {middle with heap := moved} {moved with nextCell := moved.nextCell + 1} next rfl rfl
    have created := allocate_empty_valid {middle with heap := {moved with nextCell := moved.nextCell + 1}} heap _ _ _ _ _ allocated staged rfl
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
    have next := replace_empty_valid _ _ _ _ _ (CellStability.lookupObject_reference _ _ _ _ looked).2 replaced valid rfl rfl
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
    have created := allocate_empty_valid {middle with heap := moved} heap _ _ _ _ _ allocated next rfl
    exact finishTemporary_valid _ _ _ finished created
  case unpack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
    cases stored <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, heap, retired, accepted⟩ := accepted
    exact commitPure_valid _ _ _ _ _ accepted (retire_empty_valid _ _ _ _ _ looked retired valid rfl)
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
    have safe := (clone_safe_has_no_captured_custody _ _ _ (require_ok _ _ _ cloneChecked)).1
    have retiredValid := retire_empty_valid _ _ _ _ _ looked retireOk valid (clone_capture_empty context.source saved safe)
    have next := temporary_valid _ _ _ reserved retiredValid
    have created := allocate_empty_valid _ _ _ _ _ _ _ allocated next (clone_capture_empty context.source saved safe)
    exact finishTemporary_valid _ _ _ finished created
  case resourcePack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, ⟨middle, owner⟩, reserved, ⟨heap, result⟩, allocated, finished⟩ := accepted
    have next := temporary_valid _ _ _ reserved valid
    exact finishTemporary_valid _ _ _ finished (allocate_empty_valid _ _ _ _ _ _ _ allocated next rfl)
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
      exact scopedValue_valid _ _ _ accepted (retire_empty_valid _ _ _ _ _ looked retired valid rfl)
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
    (valid : Valid machine) (accepted : authoredFailure machine context failures fault = .ok after) : Valid after.state := by
  simp only [authoredFailure, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  exact valid

theorem executePrimitive_valid (machine : State) (context : Context) (after : Transition)
    (valid : Valid machine) (accepted : executePrimitive machine context = .ok after) : Valid after.state := by
  unfold executePrimitive at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · exact authoredFailure_valid _ _ _ _ _ valid accepted
  · exact commitPure_valid _ _ _ _ _ accepted valid
  · exact heapPrimitive_valid _ _ _ _ _ _ _ valid accepted

theorem enterTerm_valid (machine : State) (source : Module) (after : Transition)
    (accepted : enterTerm machine source = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold enterTerm at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  repeat' split at accepted
  all_goals cases accepted
  all_goals simpa only [Valid, fields, frame, List.flatMap_cons, List.nil_append] using valid

theorem deliverOperand_valid (machine : State) (after : Transition)
    (accepted : deliverOperand machine = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold deliverOperand at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i intent bindings remaining evaluated tail stacked
  split at accepted
  all_goals cases accepted
  all_goals simpa only [Valid, fields, frame, stacked, List.flatMap_cons, List.nil_append] using valid

theorem enterExpression_valid (machine : State) (context : Context) (after : Transition)
    (accepted : enterExpression machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold enterExpression at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨schema, expression⟩, _, accepted⟩ := accepted
  cases expression with
  | «variable» binder =>
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
    exact valid
  | literal constant =>
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, accepted⟩ := accepted
    exact scopedValue_valid _ _ _ accepted valid
  | lambda function => exact makeClosure_valid _ _ _ _ _ _ accepted valid
  | primitive opcode operands immediate failures =>
    cases operands <;> cases accepted
    all_goals simpa only [Valid, fields, frame, List.flatMap_cons, List.nil_append] using valid

theorem enterInvocation_valid (machine : State) (context : Context) (after : Transition)
    (accepted : enterInvocation machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold enterInvocation at accepted
  split at accepted <;> try contradiction
  exact invokeFunction_valid _ _ _ _ _ _ accepted valid

theorem enterBinding_valid (machine : State) (context : Context) (after : Transition)
    (accepted : enterBinding machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold enterBinding at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i binder body bindings parent tail stacked
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, created, rfl⟩ := accepted
  have next := createScope_valid _ _ _ _ _ _ _ _ created valid
  have stackSame : middle.stack = machine.stack := next.2
  have stackedValid := stack_valid middle (if middle.scope == parent then tail else .lexical middle.scope :: tail) next.1 (by
    split <;> simp only [stackSame, stacked, List.flatMap_cons, frame, List.nil_append])
  exact stackedValid

theorem enterPattern_valid (machine : State) (context : Context) (vars : List VariableId)
    (parts : List SemanticValue) (owner : Custody.Owner) (body : TermId) (bindings : Environment) (after : Transition)
    (accepted : enterPattern machine context vars parts owner body bindings = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, created, rfl⟩ := accepted
  have next := createScope_valid _ _ _ _ _ _ _ _ created valid
  have stackSame : middle.stack = machine.stack := next.2
  have stackedValid := stack_valid middle (if middle.scope == machine.scope then machine.stack else .lexical middle.scope :: machine.stack) next.1 (by
    split <;> simp only [stackSame, List.flatMap_cons, frame, List.nil_append])
  exact stackedValid

theorem executeControlTerm_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executeControlTerm machine context = .ok after) (valid : Valid machine) : Valid after.state := by
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
    (accepted : leaveScope machine parent invocation tail value = .ok after) (valid : Valid machine)
    (same : tail.flatMap frame = machine.stack.flatMap frame) : Valid after.state := by
  simp only [leaveScope, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, owner⟩, reserved, heap, moved, delivered, finished, rfl⟩ := accepted
  have entered : Valid {machine with scope := parent, invocation := invocation, stack := tail} := stack_valid _ _ valid same
  have next := temporary_valid _ _ _ reserved entered
  have transferred := move_valid _ _ _ _ moved next
  have done := finishTemporary_valid _ _ _ finished transferred
  exact done

theorem leaveInvocation_valid (machine : State) (after : Transition)
    (accepted : leaveInvocation machine = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold leaveInvocation at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i caller parent tail stacked
  exact leaveScope_valid _ _ _ _ _ _ accepted valid (by simp [stacked, frame])

theorem restoreResumeCaller_valid (machine : State) (after : Transition)
    (accepted : restoreResumeCaller machine = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold restoreResumeCaller at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i caller parent tail stacked
  have entered : Valid {machine with scope := parent, invocation := caller, stack := tail} :=
    stack_valid machine tail valid (by simp [stacked, frame])
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨middle, owner⟩, reserved, heap, moved, finished⟩ := accepted
  have next := temporary_valid _ _ _ reserved entered
  exact finishTemporary_valid _ _ _ finished (move_valid _ _ _ _ moved next)

theorem leaveLexical_valid (machine : State) (after : Transition)
    (accepted : leaveLexical machine = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i scope tail stacked
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, record, _, parent, _, result, left, accepted⟩ := accepted
  have next := leaveScope_valid _ _ _ _ _ _ left valid (by simp [stacked, frame])
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨parentRecord, _, heap, moved, rfl⟩ := accepted
  have transferred := move_valid _ _ _ _ moved next
  exact transferred

theorem releaseScope_valid (machine : State) (after : Transition)
    (accepted : releaseScope machine = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold releaseScope at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact valid

theorem finishDisposal_valid (machine : State) (after : Transition)
    (accepted : finishDisposal machine = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold finishDisposal at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i remaining released invocation scope tail stacked
  cases accepted
  have next := stack_valid machine tail valid (by simp [stacked, frame])
  exact next

theorem discardValues_valid (machine : State) (context : Context) (after : Transition)
    (accepted : discardValues machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold discardValues at accepted
  split at accepted <;> try contradiction
  split at accepted
  · cases accepted; exact valid
  · split at accepted
    · cases accepted; exact valid
    · simp only [bind, except_bind_ok] at accepted
      obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
      cases stored <;> try contradiction
      all_goals simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
      all_goals obtain ⟨heap, retired, rfl⟩ := accepted
      all_goals first
        | exact retire_empty_valid _ _ _ _ _ looked retired valid rfl
        | skip
      case oneShot saved =>
        obtain ⟨partition, obligations⟩ := retire_parts _ _ _ _ _ looked retired
        have next := (List.perm_append_comm (l₁ := saved.frames.flatMap frame)
          (l₂ := fields {machine with heap := heap})).trans (partition.symm.trans valid)
        simpa only [Valid, fields, frame, object, expected, obligations, List.flatMap_append,
          List.flatMap_cons, List.flatMap_nil, List.nil_append, List.append_nil, List.append_assoc] using next

end ObligationLocations
end BoundaryV2.Profile.Source.Machine
