import BoundaryV2.SourceLifetimeEffects

namespace BoundaryV2.Profile.Source.Machine
namespace LifetimeRecords

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

theorem enterTerm_preserves (machine : State) (source : Module) (after : Transition)
    (accepted : enterTerm machine source = .ok after) : Preserves machine.heap.objects after.state.heap.objects := by
  unfold enterTerm at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  repeat' split at accepted
  all_goals cases accepted; exact .refl _

theorem deliverOperand_preserves (machine : State) (after : Transition)
    (accepted : deliverOperand machine = .ok after) : Preserves machine.heap.objects after.state.heap.objects := by
  unfold deliverOperand at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  split at accepted <;> cases accepted <;> exact .refl _

theorem completeHandler_preserves (machine : State) (context : Context) (after : Transition)
    (accepted : completeHandler machine context = .ok after) : Preserves machine.heap.objects after.state.heap.objects := by
  unfold completeHandler at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact .refl _

theorem cleanupFailed_preserves (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : cleanupFailed machine identity invocation outer normal tail inner = .ok after) :
    Preserves machine.heap.objects after.state.heap.objects := by
  unfold cleanupFailed at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact .refl _

theorem cleanupAbandoned_preserves (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : cleanupAbandoned machine identity invocation outer normal tail inner = .ok after) :
    Preserves machine.heap.objects after.state.heap.objects := by
  simp only [cleanupAbandoned, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  exact .refl _

theorem finishCleanupUnwind_preserves (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : finishCleanupUnwind machine identity invocation outer normal tail inner = .ok after) :
    Preserves machine.heap.objects after.state.heap.objects := by
  unfold finishCleanupUnwind at accepted
  split at accepted <;> first
    | exact cleanupFailed_preserves _ _ _ _ _ _ _ _ accepted
    | exact cleanupAbandoned_preserves _ _ _ _ _ _ _ _ accepted
    | contradiction

theorem finishDisposal_preserves (machine : State) (after : Transition)
    (accepted : finishDisposal machine = .ok after) : Preserves machine.heap.objects after.state.heap.objects := by
  unfold finishDisposal at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  exact .refl _

theorem releaseScope_preserves (machine : State) (after : Transition)
    (accepted : releaseScope machine = .ok after) : Preserves machine.heap.objects after.state.heap.objects := by
  unfold releaseScope at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact .refl _

theorem leaveInvocation_preserves (machine : State) (after : Transition)
    (accepted : leaveInvocation machine = .ok after) : Preserves machine.heap.objects after.state.heap.objects := by
  unfold leaveInvocation at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  exact leaveScope_preserves _ _ _ _ _ _ accepted

theorem leaveLexical_preserves (machine : State) (after : Transition)
    (accepted : leaveLexical machine = .ok after) : Preserves machine.heap.objects after.state.heap.objects := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, leaving, accepted⟩ := accepted
  have first := leaveScope_preserves _ _ _ _ _ _ leaving
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, store, moved, rfl⟩ := accepted
  have second := move_preserves _ _ _ _ moved
  exact first.trans second

theorem executeControlTerm_preserves (machine : State) (context : Context) (after : Transition)
    (accepted : executeControlTerm machine context = .ok after) : Preserves machine.heap.objects after.state.heap.objects := by
  unfold executeControlTerm at accepted
  split at accepted <;> try contradiction
  rename_i authored bindings values executing
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  cases authored <;> simp only at accepted <;> try contradiction
  case conditional =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    exact .refl _
  case call => cases accepted; exact .refl _
  case apply =>
    split at accepted <;> try contradiction
    exact applyClosure_preserves _ _ _ _ _ accepted
  case fail =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, rfl⟩ := accepted
    exact .refl _
  case matchSum =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact enterPattern_preserves _ _ _ _ _ _ _ _ accepted
  case unpackProduct =>
    split at accepted <;> try contradiction
    exact enterPattern_preserves _ _ _ _ _ _ _ _ accepted

theorem executeCleanupTerm_preserves (machine : State) (context : Context) (after : Transition)
    (accepted : executeCleanupTerm machine context = .ok after) : Preserves machine.heap.objects after.state.heap.objects := by
  unfold executeCleanupTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact installProtection_preserves _ _ _ _ _ _ _ _ accepted
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, ⟨middle, owner⟩, temporaryOk, rfl⟩ := accepted
    have result := temporary_preserves _ _ _ temporaryOk
    exact result

theorem executeEffectTerm_preserves (machine : State) (context : Context) (after : Transition)
    (accepted : executeEffectTerm machine context = .ok after) : Preserves machine.heap.objects after.state.heap.objects := by
  unfold executeEffectTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  cases term <;> simp only at accepted <;> try contradiction
  case perform operation => exact openRequest_preserves _ _ _ _ _ accepted
  all_goals split at accepted <;> try contradiction
  all_goals first
    | exact installHandler_preserves _ _ _ _ _ _ _ _ accepted
    | exact resumeValue_preserves _ _ _ _ _ _ accepted
    | exact resumeComputation_preserves _ _ _ _ _ accepted
    | exact enterRegion_preserves _ _ _ _ _ _ accepted

theorem unwindStep_preserves (machine : State) (context : Context) (after : Transition)
    (accepted : unwindStep machine context = .ok after) : Preserves machine.heap.objects after.state.heap.objects := by
  unfold unwindStep at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  cases stacked : machine.stack with
  | nil =>
    simp only [stacked] at accepted
    split at accepted
    · cases accepted; exact .refl _
    · split at accepted <;> try contradiction
      all_goals cases accepted; exact .refl _
  | cons saved tail =>
    cases saved <;> simp only [stacked] at accepted
    case invocation => split at accepted <;> cases accepted <;> exact .refl _
    case lexical =>
      split at accepted
      · cases accepted; exact .refl _
      · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨_, _, _, _, rfl⟩ := accepted
        exact .refl _
    case protection => exact beginCleanup_preserves _ _ _ _ _ _ _ accepted
    case cleanupReturn => exact finishCleanupUnwind_preserves _ _ _ _ _ _ _ _ accepted
    case disposalReturn =>
      repeat' split at accepted
      all_goals simp only [pure, Except.pure, Except.bind, Except.ok.injEq] at accepted
      all_goals cases accepted; exact .refl _
    all_goals cases accepted; exact .refl _

theorem tickRunning_preserves (machine : State) (context : Context) (after : Transition)
    (accepted : tickRunning machine context = .ok after) : Preserves machine.heap.objects after.state.heap.objects := by
  cases executing : machine.control <;> simp only [tickRunning, executing] at accepted
  case term => exact enterTerm_preserves _ _ _ accepted
  case expression => exact enterExpression_preserves _ _ _ accepted
  case invoke => exact enterInvocation_preserves _ _ _ accepted
  case release => exact releaseScope_preserves _ _ accepted
  case discard => exact discardValues_preserves _ _ _ accepted
  case unwind => exact unwindStep_preserves _ _ _ accepted
  case execute intent bindings operands =>
    cases intent with
    | primitive => exact executePrimitive_preserves _ _ _ accepted
    | term term =>
      cases term <;> first
        | exact executeEffectTerm_preserves _ _ _ accepted
        | exact executeCleanupTerm_preserves _ _ _ accepted
        | exact executeControlTerm_preserves _ _ _ accepted
  case delivered value =>
    cases stacked : machine.stack with
    | nil =>
      simp only [stacked, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
      exact .refl _
    | cons saved tail =>
      cases saved <;> simp only [stacked] at accepted
      all_goals first
        | exact enterBinding_preserves _ _ _ accepted
        | exact deliverOperand_preserves _ _ accepted
        | exact leaveInvocation_preserves _ _ accepted
        | exact leaveLexical_preserves _ _ accepted
        | exact restoreResumeCaller_preserves _ _ accepted
        | exact completeHandler_preserves _ _ _ accepted
        | exact beginCleanup_preserves _ _ _ _ _ _ _ accepted
        | exact finishCleanup_preserves _ _ _ accepted
        | exact finishDisposal_preserves _ _ accepted
        | (cases accepted; exact .refl _)
        | contradiction

theorem tick_preserves (machine : State) (context : Context) (after : Transition)
    (accepted : tick machine context = .ok after) : Preserves machine.heap.objects after.state.heap.objects := by
  cases phase : machine.status <;> simp only [tick, phase] at accepted
  · exact tickRunning_preserves _ _ _ accepted
  all_goals cases accepted; exact .refl _

theorem external_preserves (machine : State) (context : Context) (action : External) (after : Transition)
    (accepted : external machine context action = .ok after) : Preserves machine.heap.objects after.state.heap.objects := by
  have scopedPreserves (value : SemanticValue) (transition : Transition)
      (checked : scopedValue { machine with status := .running } value = .ok transition) :
      Preserves machine.heap.objects transition.state.heap.objects := by
    have result := scopedValue_preserves _ _ _ checked
    exact result
  cases action <;> cases phase : machine.status <;>
    simp only [external, phase, bind, pure, Except.pure, Except.bind] at accepted <;> try contradiction
  all_goals grind (gen := 32) only [except_bind_ok, Preserves.refl]

theorem step_preserves (context : Context) (before after : State) (events : List Event)
    (step : Step context before events after) : Preserves before.heap.objects after.heap.objects := by
  cases step with
  | internal accepted => exact tick_preserves _ _ _ accepted
  | external accepted => exact external_preserves _ _ _ _ accepted

theorem steps_preserve (context : Context) (before after : State) (events : List Event)
    (steps : Steps context before events after) : Preserves before.heap.objects after.heap.objects := by
  induction steps with
  | refl => exact .refl _
  | cons step _ induction => exact (step_preserves _ _ _ _ step).trans induction

theorem signature_exact (stored shape : Object) (found : signature stored = some shape) : stored = shape := by
  cases stored <;> simp only [signature] at found <;> try contradiction
  all_goals cases found; rfl

/-- An arbitrary actual trajectory preserves the physical node and complete
metadata of an existing region, capability, or borrowed-resource record. -/
theorem source_lifetime_record_is_immutable (context : Context) (before after : State) (events : List Event)
    (steps : Steps context before events after) (node : NodeId) (stored : Object)
    (stable : signature stored = some stored) (found : before.heap.lookup node = some stored) :
    after.heap.lookup node = some stored := by
  have original : view before.heap.objects node = some stored := by
    change (before.heap.lookup node).bind signature = _
    simp only [found, Option.bind_some, stable]
  have retained := (steps_preserve _ _ _ _ steps) _ _ original
  change (after.heap.lookup node).bind signature = some stored at retained
  obtain ⟨next, nextAt, same⟩ := Option.bind_eq_some_iff.mp retained
  exact (signature_exact next stored same) ▸ nextAt

theorem source_borrow_keeps_origin (context : Context) (before after : State) (events : List Event)
    (steps : Steps context before events after) (node resource : NodeId) (schema : SchemaId .source)
    (region : RegionInstanceId) (invocation : InvocationId)
    (found : before.heap.lookup node = some (.borrow schema resource region invocation)) :
    after.heap.lookup node = some (.borrow schema resource region invocation) :=
  source_lifetime_record_is_immutable _ _ _ _ steps _ _ rfl found

theorem source_region_keeps_origin (context : Context) (before after : State) (events : List Event)
    (steps : Steps context before events after) (node : NodeId) (region : RegionInstanceId)
    (descriptor : RegionId .source) (invocation : InvocationId) (parent : Option RegionInstanceId)
    (found : before.heap.lookup node = some (.region region descriptor invocation parent)) :
    after.heap.lookup node = some (.region region descriptor invocation parent) :=
  source_lifetime_record_is_immutable _ _ _ _ steps _ _ rfl found

/-- The mapping actually returned by successful instantiation leaves borrowed
resource nodes outside the copy domain, including borrows inside closures. -/
theorem instantiation_keeps_borrow_nodes (machine after : State) (context : Context) (saved instantiated : Capture)
    (accepted : instantiateCapture machine context saved = .ok (after, instantiated)) :
    ∃ mapping, instantiated = renameCapture mapping saved ∧
      ∀ node schema resource region invocation,
        machine.heap.lookup node = some (.borrow schema resource region invocation) → renamed mapping.nodes node = node := by
  obtain ⟨mapping, nodes, renamedCapture, _, _⟩ := instantiation_inventory _ _ _ _ _ accepted
  refine ⟨mapping, renamedCapture, ?_⟩
  intro node schema resource region invocation found
  rw [nodes]
  apply renamed_outside_fresh_map
  intro member
  have impossible := (List.mem_filter.mp member).2
  simp [found] at impossible

/-- Borrow references in the instantiated capture retain their node and token;
their region and originating invocation remain in that unchanged heap record. -/
theorem instantiation_keeps_borrow_references (machine after : State) (context : Context) (saved instantiated : Capture)
    (accepted : instantiateCapture machine context saved = .ok (after, instantiated)) :
    ∃ mapping, instantiated = renameCapture mapping saved ∧
      ∀ node schema resource region invocation valueSchema token,
        machine.heap.lookup node = some (.borrow schema resource region invocation) →
        renameValue mapping (.reference valueSchema node token) = .reference valueSchema node token := by
  obtain ⟨mapping, mapped, kept⟩ := instantiation_keeps_borrow_nodes _ _ _ _ _ accepted
  exact ⟨mapping, mapped, fun node schema resource region invocation valueSchema token found => by
    simp only [renameValue, kept node schema resource region invocation found]⟩

end LifetimeRecords
end BoundaryV2.Profile.Source.Machine
