import BoundaryV2.SourceObligationCleanup

namespace BoundaryV2.Profile.Source.Machine
namespace ObligationLocations

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem tickRunning_valid (machine : State) (context : Context) (after : Transition)
    (accepted : tickRunning machine context = .ok after) (valid : Valid machine)
    (indexed : machine.heap.Indexed) : Valid after.state := by
  cases executing : machine.control <;> simp only [tickRunning, executing] at accepted
  case term => exact enterTerm_valid _ _ _ accepted valid
  case expression => exact enterExpression_valid _ _ _ accepted valid
  case invoke => exact enterInvocation_valid _ _ _ accepted valid
  case release => exact releaseScope_valid _ _ accepted valid
  case discard => exact discardValues_valid _ _ _ accepted valid
  case unwind original => exact unwindStep_valid _ _ _ original executing accepted valid indexed
  case execute intent bindings operands =>
    cases intent with
    | primitive => exact executePrimitive_valid _ _ _ valid accepted
    | term term =>
      cases term <;> first
        | exact executeEffectTerm_valid _ _ _ accepted valid
        | exact executeCleanupTerm_valid _ _ _ accepted valid
        | exact executeControlTerm_valid _ _ _ accepted valid
  case delivered value =>
    cases stacked : machine.stack with
    | nil =>
      simp only [stacked, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
      simpa only [Valid, fields, executing, stacked] using valid
    | cons saved tail =>
      have same (free : frame saved = []) :
          tail.flatMap frame = machine.stack.flatMap frame := by
        simp only [stacked, List.flatMap_cons, free, List.nil_append]
      have next (free : frame saved = []) : Valid {machine with stack := tail} :=
        stack_valid machine tail valid (same free)
      cases saved <;> simp only [stacked] at accepted
      all_goals first
        | exact enterBinding_valid _ _ _ accepted valid
        | exact deliverOperand_valid _ _ accepted valid
        | exact leaveInvocation_valid _ _ accepted valid
        | exact leaveLexical_valid _ _ accepted valid
        | exact restoreResumeCaller_valid _ _ accepted valid
        | exact completeHandler_valid _ _ _ accepted valid
        | exact finishCleanup_valid _ _ _ accepted valid indexed
        | exact finishDisposal_valid _ _ accepted valid
        | (cases accepted; simpa only [Valid, fields] using next rfl)
        | skip
      case protection identity =>
        exact beginCleanup_valid _ _ _ _ _ _ _ accepted valid stacked

theorem tick_valid (machine : State) (context : Context) (after : Transition)
    (accepted : tick machine context = .ok after) (valid : Valid machine)
    (indexed : machine.heap.Indexed) : Valid after.state := by
  cases phase : machine.status <;> simp only [tick, phase] at accepted
  · exact tickRunning_valid _ _ _ accepted valid indexed
  all_goals cases accepted; exact valid

theorem external_valid (machine : State) (context : Context) (action : External) (after : Transition)
    (accepted : external machine context action = .ok after) (valid : Valid machine) : Valid after.state := by
  have running : Valid {machine with status := .running} := valid
  have resumed (value : SemanticValue) (result : Transition)
      (accepted : scopedValue {machine with status := .running} value = .ok result) : Valid result.state :=
    scopedValue_valid _ _ _ accepted running
  have cancelled (reason : Protocol.Reason) :
      Valid {machine with status := .running, control := cancelControl machine.control reason, cancellation := some reason} := by
    exact valid
  have deferred (reason : Protocol.Reason) : Valid {machine with cancellation := some reason} := valid
  cases action <;> cases phase : machine.status <;>
    simp only [external, phase, bind, pure, Except.pure, Except.bind] at accepted <;> try contradiction
  all_goals grind (gen := 32) only [except_bind_ok]


theorem step_valid (context : Context) (before after : State) (events : List Event)
    (step : Step context before events after) (valid : Valid before) (indexed : before.heap.Indexed) : Valid after := by
  cases step with
  | internal accepted => exact tick_valid _ _ _ accepted valid indexed
  | external accepted => exact external_valid _ _ _ _ accepted valid

theorem steps_valid (context : Context) (before after : State) (events : List Event)
    (steps : Steps context before events after) (valid : Valid before) (indexed : before.heap.Indexed) : Valid after := by
  induction steps with
  | refl => exact valid
  | cons step rest induction => exact induction (step_valid _ _ _ _ step valid indexed) (step_indexed step indexed)

/-- Every pending or running obligation has its phase frame exactly once in
active or captured storage, including across cleanup failure and cancellation. -/
theorem initialized_execution_preserves_obligation_locations (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : Valid after :=
  steps_valid _ _ _ _ steps (initial_valid _ _ _ initialized) (initial_indexed _ _ _ initialized)

theorem record_ids_sublist (records : List (Cleanup.Obligation .source)) :
    ((records.flatMap record).map (fun entry => entry.id.value)).Sublist (records.map (fun row => row.id.value)) := by
  induction records with
  | nil => exact .refl []
  | cons head tail induction =>
    cases phase : head.phase <;> simp only [List.flatMap_cons, record, phase, List.map_cons, List.map_append]
    all_goals first
      | exact induction.cons_cons _
      | exact induction.cons _

theorem fields_unique (machine : State) (valid : Valid machine) (indexed : machine.heap.Indexed) :
    ((fields machine).map (fun entry => entry.id.value)).Nodup := by
  have records := indexed.unique_ids.2.2
  have phases := records.sublist (record_ids_sublist machine.heap.obligations)
  exact ((valid.map (fun entry => entry.id.value)).nodup_iff).mpr phases

theorem record_member_id (obligation : Cleanup.Obligation .source) (entry : Entry)
    (member : entry ∈ record obligation) : entry.id = obligation.id := by
  cases phase : obligation.phase <;> simp only [record, phase, List.mem_singleton, List.not_mem_nil] at member
  all_goals cases member; rfl

theorem field_iff_lookup (machine : State) (entry : Entry) (valid : Valid machine) (indexed : machine.heap.Indexed) :
    entry ∈ fields machine ↔ ∃ obligation, machine.heap.obligations[entry.id.value]? = some obligation ∧ entry ∈ record obligation := by
  rw [valid.mem_iff]
  change entry ∈ machine.heap.obligations.flatMap record ↔ _
  constructor
  · intro member
    obtain ⟨obligation, present, member⟩ := List.mem_flatMap.mp member
    obtain ⟨index, found⟩ := List.mem_iff_getElem?.mp present
    have identity := indexed.obligation_identity found
    have same := record_member_id obligation entry member
    exact ⟨obligation, by simpa only [same, identity] using found, member⟩
  · rintro ⟨obligation, found, member⟩
    exact List.mem_flatMap.mpr ⟨obligation, List.mem_iff_getElem?.mpr ⟨entry.id.value, found⟩, member⟩

theorem phase_frame_iff (machine : State) (id : ObligationId) (invocation : Option InvocationId)
    (obligation : Cleanup.Obligation .source) (found : machine.heap.obligations[id.value]? = some obligation)
    (valid : Valid machine) (indexed : machine.heap.Indexed) :
    (⟨id, invocation⟩ : Entry) ∈ fields machine ↔ match obligation.phase with
      | .pending => invocation = none
      | .running active => invocation = some active
      | .completed | .failed _ => False := by
  rw [field_iff_lookup machine ⟨id, invocation⟩ valid indexed]
  simp only [found, Option.some.injEq]
  have identity := indexed_obligation_id _ _ _ indexed found
  cases phase : obligation.phase <;> simp [record, phase, identity, Entry.mk.injEq]

theorem reachable_phase_frames_are_unique (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : ((fields after).map (fun entry => entry.id.value)).Nodup :=
  fields_unique _ (initialized_execution_preserves_obligation_locations _ _ _ _ _ initialized steps)
    (source_trajectory_indices _ _ _ _ initialized steps)

theorem reachable_phase_frame_iff (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) (id : ObligationId) (invocation : Option InvocationId)
    (obligation : Cleanup.Obligation .source) (found : after.heap.obligations[id.value]? = some obligation) :
    (⟨id, invocation⟩ : Entry) ∈ fields after ↔ match obligation.phase with
      | .pending => invocation = none
      | .running active => invocation = some active
      | .completed | .failed _ => False :=
  phase_frame_iff _ _ _ _ found (initialized_execution_preserves_obligation_locations _ _ _ _ _ initialized steps)
    (source_trajectory_indices _ _ _ _ initialized steps)

end ObligationLocations
end BoundaryV2.Profile.Source.Machine
