import BoundaryV2.SourceBorrowCleanup

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

theorem tickRunning_valid (machine : State) (context : Context) (after : Transition)
    (accepted : tickRunning machine context = .ok after) (valid : Valid machine.heap)
    (bounded : IdentitySupport.Valid machine) : Valid after.state.heap := by
  cases executing : machine.control <;> simp only [tickRunning, executing] at accepted
  case term => exact enterTerm_valid _ _ _ accepted valid
  case expression => exact enterExpression_valid _ _ _ accepted valid
  case invoke => exact enterInvocation_valid _ _ _ accepted valid
  case release => exact releaseScope_valid _ _ accepted valid
  case discard => exact discardValues_valid _ _ _ accepted valid
  case unwind original => exact unwindStep_valid _ _ _ original executing accepted valid
  case execute intent bindings operands =>
    cases intent with
    | primitive => exact executePrimitive_valid _ _ _ valid accepted
    | term term =>
      cases term <;> first
        | exact executeEffectTerm_valid _ _ _ accepted valid
        | exact executeCleanupTerm_valid _ _ _ accepted valid bounded
        | exact executeControlTerm_valid _ _ _ accepted valid
  case delivered value =>
    cases stacked : machine.stack with
    | nil =>
      simp only [stacked, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
      exact valid
    | cons saved tail =>
      cases saved <;> simp only [stacked] at accepted
      all_goals first
        | exact enterBinding_valid _ _ _ accepted valid
        | exact deliverOperand_valid _ _ accepted valid
        | exact leaveInvocation_valid _ _ accepted valid
        | exact leaveLexical_valid _ _ accepted valid
        | exact restoreResumeCaller_valid _ _ accepted valid
        | exact completeHandler_valid _ _ _ accepted valid
        | exact finishCleanup_valid _ _ _ accepted valid
        | exact finishDisposal_valid _ _ accepted valid
        | (cases accepted; exact valid)
        | skip
      case protection identity =>
        exact beginCleanup_valid _ _ _ _ _ _ _ accepted valid

theorem tick_valid (machine : State) (context : Context) (after : Transition)
    (accepted : tick machine context = .ok after) (valid : Valid machine.heap)
    (bounded : IdentitySupport.Valid machine) : Valid after.state.heap := by
  cases phase : machine.status <;> simp only [tick, phase] at accepted
  · exact tickRunning_valid _ _ _ accepted valid bounded
  all_goals cases accepted; exact valid

theorem external_valid (machine : State) (context : Context) (action : External) (after : Transition)
    (accepted : external machine context action = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  have running : Valid machine.heap := valid
  have resumed (value : SemanticValue) (result : Transition)
      (accepted : scopedValue {machine with status := .running} value = .ok result) : Valid result.state.heap :=
    scopedValue_valid _ _ _ accepted running
  have cancelled (reason : Protocol.Reason) :
      Valid machine.heap := by
    exact valid
  have deferred (reason : Protocol.Reason) : Valid machine.heap := valid
  cases action <;> cases phase : machine.status <;>
    simp only [external, phase, bind, pure, Except.pure, Except.bind] at accepted <;> try contradiction
  all_goals grind (gen := 32) only [except_bind_ok]



theorem initial_valid (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) : Valid machine.heap := by
  simp only [initial, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ := accepted
  intro entry member
  contradiction

theorem step_valid (context : Context) (before after : State) (events : List Event)
    (step : Step context before events after) (valid : Valid before.heap) (bounded : IdentitySupport.Valid before) : Valid after.heap := by
  cases step with
  | internal accepted => exact tick_valid _ _ _ accepted valid bounded
  | external accepted => exact external_valid _ _ _ _ accepted valid

theorem steps_valid (context : Context) (before after : State) (events : List Event)
    (steps : Steps context before events after) (valid : Valid before.heap) (bounded : IdentitySupport.Valid before) : Valid after.heap := by
  induction steps with
  | refl => exact valid
  | cons step rest induction =>
    exact induction (step_valid _ _ _ _ step valid bounded) (IdentitySupport.step_valid step bounded)

/-- Every actual stored borrow names the exclusive resource in its original
loan record. Cleanup phase advancement does not change that resource binding. -/
theorem initialized_execution_preserves_borrow_registry (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : Valid after.heap :=
  steps_valid _ _ _ _ steps (initial_valid _ _ _ initialized) (IdentitySupport.initial_valid _ _ _ initialized)

theorem reachable_borrow_names_protected_resource (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) (node resource : NodeId) (schema : SchemaId .source)
    (region : RegionInstanceId) (invocation : InvocationId)
    (found : after.heap.lookup node = some (.borrow schema resource region invocation)) : Registered after.heap resource region :=
  lookup_valid _ _ _ (initialized_execution_preserves_borrow_registry _ _ _ _ _ initialized steps) found

/-- Borrowed resource elimination uses the exact pending obligation and active
region, then reads the same physical resource that obligation protects. -/
theorem resourceUnpack_borrow_scope (machine : State) (context : Context) (schema : SchemaId .source)
    (immediate : Nat) (value : Located) (after : Transition) (node resource : NodeId) (borrowSchema : SchemaId .source)
    (region : RegionInstanceId) (invocation : InvocationId)
    (looked : lookupObject machine value = .ok (node, .borrow borrowSchema resource region invocation))
    (accepted : heapPrimitive machine context .resourceUnpack schema immediate [value] = .ok after)
    (valid : Valid machine.heap) :
    ∃ id obligation resourceSchema token storedSchema content,
      (machine.heap.loans.find? (fun entry => entry.1 == region)).map Prod.snd = some id ∧
      machine.heap.obligations[id.value]? = some obligation ∧
      obligation.resource = some (.reference resourceSchema resource (some token)) ∧
      obligation.phase = .pending ∧ .region region ∈ machine.stack ∧
      machine.heap.lookup resource = some (.resource storedSchema content) ∧ content.value.schema = schema := by
  simp only [heapPrimitive, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok, looked, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, rfl, accepted⟩ := accepted
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨id, loanAt, obligation, obligationAt, accepted⟩ := accepted
  split at accepted <;> try contradiction
  rename_i pending
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, active, stored, storedAt, accepted⟩ := accepted
  cases stored <;> try contradiction
  rename_i storedSchema content
  simp only [except_bind_ok] at accepted
  obtain ⟨_, schemaAt, _⟩ := accepted
  have registered := lookup_valid _ _ _ valid (CellStability.lookupObject_reference _ _ _ _ looked).2
  obtain ⟨registeredId, original, resourceSchema, token, registeredLoan, originalAt, reference⟩ := registered
  have sameId : registeredId = id := Option.some.inj (registeredLoan.symm.trans loanAt)
  subst registeredId
  have sameRecord : original = obligation := Option.some.inj (originalAt.symm.trans obligationAt)
  subst original
  refine ⟨id, obligation, resourceSchema, token, storedSchema, content, loanAt, obligationAt, reference, pending, ?_, storedAt, ?_⟩
  · obtain ⟨saved, member, matched⟩ := List.any_eq_true.mp (require_ok _ _ _ active)
    cases saved <;> try contradiction
    rename_i activeRegion
    have same : activeRegion = region := by simpa using matched
    subst activeRegion
    exact member
  · simpa using require_ok _ _ _ schemaAt

theorem reachable_borrowed_read_is_scoped (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (schema : SchemaId .source) (immediate : Nat)
    (value : Located) (after : Transition) (node resource : NodeId) (borrowSchema : SchemaId .source)
    (region : RegionInstanceId) (invocation : InvocationId)
    (looked : lookupObject machine value = .ok (node, .borrow borrowSchema resource region invocation))
    (accepted : heapPrimitive machine context .resourceUnpack schema immediate [value] = .ok after) :
    ∃ id obligation resourceSchema token storedSchema content,
      (machine.heap.loans.find? (fun entry => entry.1 == region)).map Prod.snd = some id ∧
      machine.heap.obligations[id.value]? = some obligation ∧
      obligation.resource = some (.reference resourceSchema resource (some token)) ∧
      obligation.phase = .pending ∧ .region region ∈ machine.stack ∧
      machine.heap.lookup resource = some (.resource storedSchema content) ∧ content.value.schema = schema :=
  resourceUnpack_borrow_scope _ _ _ _ _ _ _ _ _ _ _ looked accepted
    (initialized_execution_preserves_borrow_registry _ _ _ _ _ initialized steps)

end BorrowRegistry
end BoundaryV2.Profile.Source.Machine
