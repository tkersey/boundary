import BoundaryV2.SourceObjectOwnerEffects

namespace BoundaryV2.Profile.Source.Machine
namespace ObjectOwners

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem tickRunning_valid (machine : State) (context : Context) (after : Transition)
    (formed : Valid machine.heap)
    (accepted : tickRunning machine context = .ok after) : Valid after.state.heap := by
  cases executing : machine.control <;> simp only [tickRunning, executing] at accepted
  case term => exact enterTerm_valid _ _ _ formed accepted
  case expression => exact enterExpression_valid _ _ _ formed accepted
  case invoke => exact enterInvocation_valid _ _ _ formed accepted
  case release => exact releaseScope_valid _ _ formed accepted
  case discard => exact discardValues_valid _ _ _ formed accepted
  case unwind => exact unwindStep_valid _ _ _ formed accepted
  case execute intent bindings operands =>
    cases intent with
    | primitive => exact executePrimitive_valid _ _ _ formed accepted
    | term term =>
      cases term <;> first
        | exact executeEffectTerm_valid _ _ _ formed accepted
        | exact executeCleanupTerm_valid _ _ _ formed accepted
        | exact executeControlTerm_valid _ _ _ formed accepted
  case delivered value =>
    cases stacked : machine.stack with
    | nil =>
      simp only [stacked, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
      exact formed
    | cons saved tail =>
      cases saved <;> simp only [stacked] at accepted
      all_goals first
        | exact enterBinding_valid _ _ _ formed accepted
        | exact deliverOperand_valid _ _ formed accepted
        | exact leaveInvocation_valid _ _ formed accepted
        | exact leaveLexical_valid _ _ formed accepted
        | exact restoreResumeCaller_valid _ _ formed accepted
        | exact completeHandler_valid _ _ _ formed accepted
        | exact finishCleanup_valid _ _ _ formed accepted
        | exact finishDisposal_valid _ _ formed accepted
        | exact beginCleanup_valid _ _ _ _ _ _ _ formed accepted
        | (cases accepted; exact formed)
        | contradiction

theorem tick_valid (machine : State) (context : Context) (after : Transition)
    (formed : Valid machine.heap)
    (accepted : tick machine context = .ok after) : Valid after.state.heap := by
  cases phase : machine.status <;> simp only [tick, phase] at accepted
  · exact tickRunning_valid _ _ _ formed accepted
  all_goals cases accepted; exact formed

theorem external_valid (machine : State) (context : Context) (action : External) (after : Transition)
    (formed : Valid machine.heap)
    (accepted : external machine context action = .ok after) : Valid after.state.heap := by
  have scopedBound (value : SemanticValue) (result : Transition)
      (resumed : scopedValue {machine with status := .running} value = .ok result) : Valid result.state.heap :=
    scopedValue_valid _ _ _ (by exact formed) resumed
  cases action <;> cases phase : machine.status <;>
    simp only [external, phase, bind, pure, Except.pure, Except.bind] at accepted <;> try contradiction
  all_goals grind (gen := 32) only [except_bind_ok]

theorem step_valid (step : Step context before events after) (formed : Valid before.heap)
     : Valid after.heap := by
  cases step with
  | internal accepted => exact tick_valid _ _ _ formed accepted
  | external accepted => exact external_valid _ _ _ _ formed accepted

theorem steps_valid (steps : Steps context before events after) (formed : Valid before.heap)
     : Valid after.heap := by
  induction steps with
  | refl => exact formed
  | cons step _ induction => exact induction (step_valid step formed)

theorem initial_valid (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) : Valid machine.heap := by
  simp only [initial, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ := accepted
  simp [Valid, Heap.lookup]

/-- All initialized source transitions preserve the physical owner address
of every closure capture, package content, and resource representation field.
Cloning uses the actual fresh-node map and copied-object position. -/
theorem initialized_execution_preserves_object_owners (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : Valid after.heap :=
  steps_valid steps (initial_valid _ _ _ initialized)


/-- Cell declarations require copyable contents. The runtime content schema
and value structure are preserved by ordinary initialized execution. -/
theorem reachable_cell_contents_have_no_tokens (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) (node : NodeId) (identity : CellId)
    (schema : SchemaId .source) (region : RegionInstanceId) (content : Located)
    (found : after.heap.lookup node = some (.cell identity schema region content)) : ownedTokens content.value = [] := by
  have contextTyped : context.typingValid = true := by
    simpa only [Context.typingValid, Option.any_eq_true] using initial_checks_typing _ _ _ initialized
  have objects := ObjectSchemas.initialized_execution_preserves_object_schemas _ _ _ _ _ initialized steps
  obtain ⟨descriptor, shape⟩ := ObjectSchemas.heap_lookup _ _ _ _ found objects
  have admitted := CloneTraits.checked_context_internal_valid context schema _ contextTyped shape
  have copyable : Traits.check context.source.schemas .copy content.value.schema = true := by
    simp only [Admission.internalValid, DeclarationAdmission.internalValid, Bool.and_eq_true] at admitted
    exact admitted.2
  have structures := ReferenceStructureContracts.initialized_execution_preserves_reference_structure _ _ _ _ _ initialized steps
  have field := ValueInventory.lookup_preserves_all after node _ found _ structures
  exact ReferenceStructureContracts.copy_value_has_no_tokens context.source.schemas content.value
    (field content.value (by simp [ValueInventory.object])) (Traits.check_sound _ _ _ copyable)

end ObjectOwners
end BoundaryV2.Profile.Source.Machine
