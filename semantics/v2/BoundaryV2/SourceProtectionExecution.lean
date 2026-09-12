import BoundaryV2.SourceProtectionLinearity

namespace BoundaryV2.Profile.Source.Machine
namespace ProtectionLinearity

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem installProtection_cleanup (machine : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (accepted : installProtection machine context body cleanup arguments resource loan = .ok after) :
    Preserves machine.heap.obligations after.state.heap.obligations := by
  simp only [installProtection, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, store, moved, accepted⟩ := accepted
  have checked := PrimitiveLinearity.move_values_checks_unique_input_occurrences _ _ _ _ moved
  let record : Cleanup.Obligation .source := ⟨⟨machine.heap.nextObligation⟩, machine.scope,
    machine.heap.nextObligation, cleanup.value, resource.map Located.value, .pending⟩
  have added : All [record] := by
    intro actual member
    cases List.mem_singleton.mp member
    simpa only [Linear, record, Option.toList_map, List.flatMap_map, Function.comp_def, List.flatMap_cons] using checked
  have next := (moveValues_cleanup _ _ _ _ moved).trans (Preserves.append store.obligations [record] added)
  cases resource with
  | none =>
    cases loan <;> try contradiction
    simp only [pure, Except.pure, Except.bind] at accepted
    exact next.trans (applyClosure_cleanup _ _ _ _ _ accepted)
  | some value =>
    cases loan with
    | none => contradiction
    | some descriptor =>
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, ⟨afterStore, borrowed⟩, allocated, _, rfl, applied⟩ := accepted
      exact next.trans ((allocateObject_cleanup _ _ _ _ _ _ _ allocated).trans (applyClosure_cleanup _ _ _ _ _ applied))

theorem beginCleanup_cleanup (state : State) (context : Context) (identity : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (accepted : beginCleanup state context identity exit normal tail = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [beginCleanup, bind, except_bind_ok, fromOption_ok, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → applyClosure_cleanup, → Preserves.begin,
    ← Preserves.refl,
    → Preserves.trans]

theorem finishCleanup_cleanup (state : State) (context : Context) (after : Transition)
    (accepted : finishCleanup state context = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [finishCleanup, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, resumeRelease] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → Preserves.complete,
    ← Preserves.refl,
    → Preserves.trans]

theorem cleanupFailed_cleanup (state : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : cleanupFailed state identity invocation outer normal tail inner = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [cleanupFailed, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → Preserves.complete,
    ← Preserves.refl,
    → Preserves.trans]

theorem cleanupAbandoned_cleanup (state : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : cleanupAbandoned state identity invocation outer normal tail inner = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [cleanupAbandoned, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, before, found, ⟨record, events⟩, completed, rfl⟩ := accepted
  exact Preserves.complete _ _ _ _ _ _ _ found completed


theorem finishCleanupUnwind_cleanup (state : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : finishCleanupUnwind state identity invocation outer normal tail inner = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  unfold finishCleanupUnwind at accepted
  split at accepted <;> first
    | exact cleanupFailed_cleanup _ _ _ _ _ _ _ _ accepted
    | exact cleanupAbandoned_cleanup _ _ _ _ _ _ _ _ accepted
    | contradiction

theorem finishDisposal_cleanup (state : State) (after : Transition)
    (accepted : finishDisposal state = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  unfold finishDisposal at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  exact .refl _

theorem releaseScope_cleanup (state : State) (after : Transition)
    (accepted : releaseScope state = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [releaseScope, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok,
    ← Preserves.refl,
    → Preserves.trans]

theorem discardValues_cleanup (state : State) (context : Context) (after : Transition)
    (accepted : discardValues state context = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [discardValues, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw, resumeRelease] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → retireObject_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem unwindStep_cleanup (state : State) (context : Context) (after : Transition)
    (accepted : unwindStep state context = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [unwindStep, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → beginCleanup_cleanup, → finishCleanupUnwind_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem executeCleanupTerm_cleanup (state : State) (context : Context) (after : Transition)
    (accepted : executeCleanupTerm state context = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [executeCleanupTerm, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → installProtection_cleanup, → temporary_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem tickRunning_cleanup (state : State) (context : Context) (after : Transition)
    (accepted : tickRunning state context = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [tickRunning, bind, pure, Except.pure] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → enterTerm_cleanup, → enterExpression_cleanup, → enterInvocation_cleanup, → releaseScope_cleanup, → discardValues_cleanup, → unwindStep_cleanup, → executePrimitive_cleanup, → executeEffectTerm_cleanup, → executeCleanupTerm_cleanup, → executeControlTerm_cleanup, → enterBinding_cleanup, → deliverOperand_cleanup, → leaveInvocation_cleanup, → leaveLexical_cleanup, → restoreResumeCaller_cleanup, → completeHandler_cleanup, → beginCleanup_cleanup, → finishCleanup_cleanup, → finishDisposal_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem tick_cleanup (state : State) (context : Context) (after : Transition)
    (accepted : tick state context = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [tick] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → tickRunning_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem external_cleanup (state : State) (context : Context) (action : External) (after : Transition)
    (accepted : external state context action = .ok after) : Preserves state.heap.obligations after.state.heap.obligations := by
  simp only [external, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → scopedValue_cleanup,
    ← Preserves.refl,
    → Preserves.trans]

theorem step_cleanup (step : Step context before events after) :
    Preserves before.heap.obligations after.heap.obligations := by
  cases step with
  | internal checked => exact tick_cleanup _ _ _ checked
  | external checked => exact external_cleanup _ _ _ _ checked

theorem steps_cleanup (steps : Steps context before events after) :
    Preserves before.heap.obligations after.heap.obligations := by
  induction steps with
  | refl => exact .refl _
  | cons first _ induction => exact (step_cleanup first).trans induction





theorem initial_linear (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) : All machine.heap.obligations := by
  simp only [initial, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ := accepted
  simp [All]

/-- The cleanup value and protected resource of each obligation contain no
repeated owning token throughout actual initialized source execution. Their
creation transaction supplies this joint fact before custody is committed. -/
theorem initialized_execution_preserves_protection_linearity (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : All after.heap.obligations :=
  steps_cleanup steps (initial_linear _ _ _ initialized)

end ProtectionLinearity
end BoundaryV2.Profile.Source.Machine
