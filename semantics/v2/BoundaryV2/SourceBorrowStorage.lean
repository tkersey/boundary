import BoundaryV2.SourceBorrowRegistry

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

theorem createScope_valid (machine : State) (context : Context) (invocation : InvocationId)
    (parent : Option LexicalScopeId) (vars : List VariableId) (values : List Located)
    (bindings : Environment) (after : State × Environment)
    (accepted : createScope machine context invocation parent vars values bindings = .ok after) (valid : Valid machine.heap) :
    Valid after.1.heap := by
  simp only [createScope, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · cases accepted; exact valid
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, heap, moved, rfl⟩ := accepted
    have next := move_valid machine.heap heap values _ moved valid
    exact next

theorem invokeFunction_valid (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction machine context function bindings arguments = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  simp only [invokeFunction, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨definition, _, body, _, captured, _, _, _, _, _, ⟨middle, entered⟩, created, rfl⟩ := accepted
  have next := createScope_valid _ _ _ _ _ _ _ _ created valid
  exact next

theorem applyClosure_valid (machine : State) (context : Context) (closure : Located)
    (arguments : List Located) (after : Transition)
    (accepted : applyClosure machine context closure arguments = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  simp only [applyClosure, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
  cases stored <;> try contradiction
  case closure schema function bindings =>
    obtain ⟨⟨rootSchema, token, reference⟩, _⟩ := CellStability.lookupObject_reference _ _ _ _ looked
    rw [reference] at accepted
    cases token with
    | none =>
      simp only [pure, Except.pure, Except.bind] at accepted
      exact invokeFunction_valid _ _ _ _ _ _ accepted valid
    | some token =>
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨heap, retired, invoked⟩ := accepted
      exact invokeFunction_valid _ _ _ _ _ _ invoked (retire_valid _ _ _ retired valid)

theorem makeClosureWithValues_valid (machine : State) (context : Context)
    (schema : SchemaId .source) (function : FunctionId .source) (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues machine context schema function values = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, ⟨middle, owner⟩, reserved, moved, movedAt, ⟨heap, result⟩, allocated, finished⟩ := accepted
  have next := temporary_valid _ _ _ reserved valid
  have transferred := move_valid _ _ _ _ movedAt next
  have created := allocate_valid _ _ _ _ _ _ _ allocated transferred (by trivial)
  exact finishTemporary_valid _ _ _ finished created

theorem makeClosure_valid (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (bindings : Environment) (after : Transition)
    (accepted : makeClosure machine context schema function bindings = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  obtain ⟨_, _, created⟩ := accepted
  exact makeClosureWithValues_valid _ _ _ _ _ _ created valid

theorem commitPure_valid (machine : State) (opcode : Opcode) (operands : List Located)
    (result : SemanticValue) (after : Transition)
    (accepted : commitPure machine opcode operands result = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  simp only [commitPure, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, reserved, accepted⟩ := accepted
  have next := temporary_valid _ _ _ reserved valid
  split at accepted
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, _, _, _, finished⟩ := accepted
    exact finishTemporary_valid _ _ _ finished next
  · simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨heap, moved, _, _, custody, _, finished⟩ := accepted
    have transferred := move_valid _ _ _ _ moved next
    exact finishTemporary_valid _ _ _ finished transferred


private theorem mapM_output (function : α → Except Invalid β) (inputs : List α) (outputs : List β)
    (accepted : inputs.mapM function = .ok outputs) (output : β) (member : output ∈ outputs) :
    ∃ input ∈ inputs, function input = .ok output := by
  induction inputs generalizing outputs with
  | nil => cases accepted; simp at member
  | cons head tail induction =>
    simp only [List.mapM_cons, bind, except_bind_ok] at accepted
    obtain ⟨first, firstAt, rest, restAt, accepted⟩ := accepted
    cases accepted
    rcases List.mem_cons.mp member with equal | belongs
    · cases equal; exact ⟨head, by simp, firstAt⟩
    · obtain ⟨input, inputMember, checked⟩ := induction rest restAt belongs
      exact ⟨input, by simp [inputMember], checked⟩

theorem instantiateCapture_valid (machine after : State) (context : Context) (saved instantiated : Capture)
    (accepted : instantiateCapture machine context saved = .ok (after, instantiated)) (valid : Valid machine.heap) : Valid after.heap := by
  unfold instantiateCapture at accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨copied, copiedAt, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  cases accepted
  have copiedValid : ∀ entry ∈ copied, ∀ stored ∈ entry, ObjectValid machine.heap stored := by
    intro entry member stored present
    obtain ⟨node, nodeCopied, checked⟩ := mapM_output _ _ _ copiedAt entry member
    simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at checked
    obtain ⟨original, originalAt, rfl⟩ := checked
    cases present
    cases original <;> try trivial
    case borrow schema resource region invocation =>
      have impossible := (List.mem_filter.mp nodeCopied).2
      simp [originalAt] at impossible
  intro entry member stored present
  rcases List.mem_append.mp member with old | copied
  · exact valid entry old stored present
  · exact copiedValid entry copied stored present

theorem takeCapture_valid (machine : State) (context : Context) (token : Located) (after : State × Capture)
    (accepted : takeCapture machine context token = .ok after) (valid : Valid machine.heap) : Valid after.1.heap := by
  simp only [takeCapture, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, _, accepted⟩ := accepted
  cases stored <;> try contradiction
  case oneShot saved =>
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨heap, retired, rfl⟩ := accepted
    exact retire_valid _ _ _ retired valid
  case multiTemplate saved => exact instantiateCapture_valid _ _ _ _ _ accepted valid

theorem activateCapture_valid (machine after : State) (context : Context) (saved : Capture)
    (successor : Option (HandlerId .source × List Located × Environment))
    (accepted : activateCapture machine context saved successor = .ok after)
    (valid : Valid machine.heap) : Valid after.heap := by
  simp only [activateCapture, bind, except_bind_ok, pure, Except.pure] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  cases successor with
  | none => cases accepted; exact valid
  | some successor =>
    rcases successor with ⟨handler, stored, bindings⟩
    simp only [except_bind_ok, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, _, rfl, rfl⟩ := accepted
    exact valid

theorem resumeValue_valid (machine : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (accepted : resumeValue machine context token argument successor = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  simp only [resumeValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, saved⟩, taken, _, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, active, activated, ⟨temporary, owner⟩, reserved, store, moved, finished⟩ := accepted
  have next := activateCapture_valid _ _ _ _ _ activated (takeCapture_valid _ _ _ _ taken valid)
  exact finishTemporary_valid _ _ _ finished (move_valid _ _ _ _ moved (temporary_valid _ _ _ reserved next))

theorem resumeComputation_valid (machine : State) (context : Context) (token computation : Located) (after : Transition)
    (accepted : resumeComputation machine context token computation = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, active, activated, applied⟩ := accepted
  exact applyClosure_valid _ _ _ _ _ applied (activateCapture_valid _ _ _ _ _ activated (takeCapture_valid _ _ _ _ captured valid))

end BorrowRegistry
end BoundaryV2.Profile.Source.Machine
