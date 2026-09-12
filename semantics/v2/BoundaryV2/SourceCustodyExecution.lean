import BoundaryV2.SourceParkedControl

namespace BoundaryV2.Profile.Source.Machine
namespace CustodyCoverage

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

theorem tickRunning_valid (machine : State) (context : Context) (after : Transition)
    (accepted : tickRunning machine context = .ok after) (valid : Valid machine)
    (contracts : ClosureContracts.Valid context machine.heap.objects) (objects : ObjectOwners.Valid machine.heap)
    (cellsFree : ∀ node identity schema region content,
      machine.heap.lookup node = some (.cell identity schema region content) → ownedTokens content.value = [])
    (resourcesFree : ∀ node schema content,
      machine.heap.lookup node = some (.resource schema content) → ownedTokens content.value = []) : Valid after.state := by
  cases executing : machine.control <;> simp only [tickRunning, executing] at accepted
  case term => exact enterTerm_valid _ _ _ accepted valid
  case expression => exact enterExpression_valid _ _ _ accepted valid
  case invoke => exact enterInvocation_valid _ _ _ accepted valid
  case release => exact releaseScope_valid _ _ accepted valid
  case discard => exact discardValues_valid _ _ _ accepted valid objects resourcesFree
  case unwind original => exact unwindStep_valid _ _ _ original executing accepted valid contracts
  case execute intent bindings operands =>
    cases intent with
    | primitive => exact executePrimitive_valid _ _ _ valid cellsFree resourcesFree accepted
    | term term =>
      cases term <;> first
        | exact executeEffectTerm_valid _ _ _ accepted valid contracts
        | exact executeCleanupTerm_valid _ _ _ accepted valid contracts
        | exact executeControlTerm_valid _ _ _ accepted valid contracts
  case delivered value =>
    have empty : QueueCustody.controlFields machine.control = [] := by rw [executing]; rfl
    cases stacked : machine.stack with
    | nil =>
      simp only [stacked, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
      simpa only [Valid, fields, QueueCustody.fields_components, executing, stacked] using valid
    | cons saved tail =>
      have same (free : QueueCustody.frameFields saved = []) :
          tail.flatMap QueueCustody.frameFields = machine.stack.flatMap QueueCustody.frameFields := by
        simp only [stacked, List.flatMap_cons, free, List.nil_append]
      have next (free : QueueCustody.frameFields saved = []) : Valid {machine with stack := tail} :=
        stack_fields_valid machine tail valid (same free)
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
        | (cases accepted; simpa only [Valid, fields, QueueCustody.fields_components, QueueCustody.controlFields,
            DisposalShape.control, executing] using next rfl)
        | skip
      case protection identity =>
        exact beginCleanup_valid _ _ _ _ _ _ _ accepted valid (same rfl) empty contracts

theorem tick_valid (machine : State) (context : Context) (after : Transition)
    (accepted : tick machine context = .ok after) (valid : Valid machine)
    (contracts : ClosureContracts.Valid context machine.heap.objects) (objects : ObjectOwners.Valid machine.heap)
    (cellsFree : ∀ node identity schema region content,
      machine.heap.lookup node = some (.cell identity schema region content) → ownedTokens content.value = [])
    (resourcesFree : ∀ node schema content,
      machine.heap.lookup node = some (.resource schema content) → ownedTokens content.value = []) : Valid after.state := by
  cases phase : machine.status <;> simp only [tick, phase] at accepted
  · exact tickRunning_valid _ _ _ accepted valid contracts objects cellsFree resourcesFree
  all_goals cases accepted; exact valid

theorem external_valid (machine : State) (context : Context) (action : External) (after : Transition)
    (accepted : external machine context action = .ok after) (valid : Valid machine)
    (parkedEmpty : ParkedEmpty machine) : Valid after.state := by
  have running : Valid {machine with status := .running} := valid
  have resumed (request : Request) (parked : machine.status = .parked request) (value : SemanticValue) (result : Transition)
      (accepted : scopedValue {machine with status := .running} value = .ok result) : Valid result.state :=
    scopedValue_valid _ _ _ accepted running (parkedEmpty request parked)
  have cancelled (reason : Protocol.Reason) :
      Valid {machine with status := .running, control := cancelControl machine.control reason, cancellation := some reason} := by
    simpa only [Valid, fields, QueueCustody.fields_components, QueueCustody.controlFields,
      OwnerLocations.cancel_control_queued] using valid
  have deferred (reason : Protocol.Reason) : Valid {machine with cancellation := some reason} := valid
  cases action <;> cases phase : machine.status <;>
    simp only [external, phase, bind, pure, Except.pure, Except.bind] at accepted <;> try contradiction
  all_goals grind (gen := 32) only [except_bind_ok]

theorem external_parked (machine : State) (context : Context) (action : External) (after : Transition)
    (accepted : external machine context action = .ok after) (valid : ParkedEmpty machine) : ParkedEmpty after.state := by
  have running : ParkedEmpty {machine with status := .running} := parked_empty_of_running _ rfl
  have resumed (value : SemanticValue) (result : Transition)
      (accepted : scopedValue {machine with status := .running} value = .ok result) : ParkedEmpty result.state :=
    parked_empty_of_running _ (OperandSchemas.scopedValue_status _ _ _ accepted)
  have cancelled (reason : Protocol.Reason) :
      ParkedEmpty {machine with status := .running, control := cancelControl machine.control reason, cancellation := some reason} :=
    parked_empty_of_running _ rfl
  have deferred (reason : Protocol.Reason) : ParkedEmpty {machine with cancellation := some reason} := valid
  cases action <;> cases phase : machine.status <;>
    simp only [external, phase, bind, pure, Except.pure, Except.bind] at accepted <;> try contradiction
  all_goals grind (gen := 32) only [except_bind_ok]

theorem initial_parked (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) : ParkedEmpty machine := by
  simp only [initial, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ := accepted
  exact parked_empty_of_running _ rfl

theorem reachable_step_valid (context : Context) (arguments : List SemanticValue)
    (initialState before after : State) (prefixEvents events : List Event)
    (initialized : initial context arguments = .ok initialState)
    (prior : Steps context initialState prefixEvents before) (step : Step context before events after)
    (valid : Valid before) (parked : ParkedEmpty before) : Valid after ∧ ParkedEmpty after := by
  cases step with
  | external accepted => exact ⟨external_valid _ _ _ _ accepted valid parked, external_parked _ _ _ _ accepted parked⟩
  | internal accepted =>
    refine ⟨tick_valid _ _ _ accepted valid
      (ClosureContracts.initialized_execution_preserves_closure_contracts _ _ _ _ _ initialized prior)
      (ObjectOwners.initialized_execution_preserves_object_owners _ _ _ _ _ initialized prior)
      ?_ ?_, tick_parked _ _ _ accepted parked⟩
    · intro node identity schema region content found
      exact ObjectOwners.reachable_cell_contents_have_no_tokens _ _ _ _ _ initialized prior _ _ _ _ _ found
    · intro node schema content found
      have objects := ObjectSchemas.initialized_execution_preserves_object_schemas _ _ _ _ _ initialized prior
      obtain ⟨_, _, _, _, _, external⟩ := ObjectSchemas.heap_lookup _ _ _ _ found objects
      have shapes := initialized_execution_preserves_value_shapes _ _ _ _ _ initialized prior
      have shape := ValueInventory.lookup_preserves_all before node _ found _ shapes
      exact ValueLinearity.external_shape_has_no_tokens context.source.schemas content.value
        (shape content.value (by simp [ValueInventory.object])) (Traits.check_sound _ _ _ external)

theorem steps_valid (context : Context) (arguments : List SemanticValue)
    (initialState before after : State) (prefixEvents events : List Event)
    (initialized : initial context arguments = .ok initialState)
    (prior : Steps context initialState prefixEvents before) (steps : Steps context before events after)
    (valid : Valid before) (parked : ParkedEmpty before) : Valid after ∧ ParkedEmpty after := by
  induction steps generalizing prefixEvents with
  | refl => exact ⟨valid, parked⟩
  | cons step rest induction =>
    obtain ⟨next, parkedNext⟩ := reachable_step_valid _ _ _ _ _ _ _ initialized prior step valid parked
    exact induction _ (steps_trans prior (.cons step .refl)) next parkedNext

/-- Every actual live token retains a physical owner, including the intervals
where disposal work moves through captured continuations and cleanup returns. -/
theorem initialized_execution_preserves_custody_coverage (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : Valid after :=
  (steps_valid context arguments before before after [] events initialized .refl steps
    (initial_valid _ _ _ initialized) (initial_parked _ _ _ initialized)).1

end CustodyCoverage

namespace OwningFields

theorem reachable_entries_cover_book (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : after.heap.custody.entries ⊆ entries after :=
  CustodyCoverage.reachable_entries_cover_book_of_coverage _ _ _ _ _ initialized steps
    (CustodyCoverage.initialized_execution_preserves_custody_coverage _ _ _ _ _ initialized steps)

/-- The enumerated live physical occurrences and actual custody book coincide
with multiplicity. No inventory-side token or owner deduplication is used. -/
theorem reachable_custody_bijection (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : (entries after).Perm after.heap.custody.entries := by
  have physical : (entries after).Nodup :=
    List.Pairwise.of_map Custody.Entry.token (fun _ _ different same => different (congrArg Custody.Entry.token same))
      (reachable_entries_are_unique _ _ _ _ _ initialized steps)
  have book : after.heap.custody.entries.Nodup :=
    List.Pairwise.of_map Custody.Entry.token (fun _ _ different same => different (congrArg Custody.Entry.token same))
      after.heap.custody.tokens_unique
  apply (List.perm_ext_iff_of_nodup physical book).mpr
  intro entry
  exact ⟨fun member => reachable_entries_in_book _ _ _ _ _ initialized steps member,
    fun member => reachable_entries_cover_book _ _ _ _ _ initialized steps member⟩

end OwningFields

end BoundaryV2.Profile.Source.Machine
