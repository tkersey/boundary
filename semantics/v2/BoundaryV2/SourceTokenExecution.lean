import BoundaryV2.SourceTokenCleanup

namespace BoundaryV2.Profile.Source.Machine
namespace TokenInventory

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem executeControlTerm_preserves_token_bounds (machine : State) (context : Context) (after : Transition)
    (accepted : executeControlTerm machine context = .ok after)
    (typed : ValueInventory.All (ValueTokensBounded limit) machine) :
    ValueInventory.All (ValueTokensBounded limit) after.state := by
  unfold executeControlTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  have outer : ∀ binding ∈ bindings, ValueTokensBounded limit binding.located.value := by
    intro binding member
    apply typed
    simp only [ValueInventory.state, executing, ValueInventory.control, ValueInventory.environment,
      List.mem_append, List.mem_map]
    grind only []
  have inputs : ∀ value ∈ operands, ValueTokensBounded limit value.value := by
    intro value member
    apply typed
    simp only [ValueInventory.state, executing, ValueInventory.control, List.mem_append, List.mem_map]
    grind only []
  cases term <;> simp only at accepted <;> try contradiction
  case conditional condition yes no =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.environment,
      List.mem_append, List.mem_map] at typed ⊢
    grind only []
  case call function arguments =>
    cases accepted
    simpa only [ValueInventory.All, ValueInventory.state, executing, ValueInventory.control] using typed
  case apply function arguments =>
    split at accepted <;> try contradiction
    rename_i closure args operandsEqual
    exact ValueInventory.applyClosure_preserves_all machine context closure args after accepted _ typed
      (fun value member => inputs value (by simp [member]))
  case fail failure =>
    split at accepted <;> try contradiction
    rename_i value operandsEqual
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, rfl⟩ := accepted
    have failed := inputs value (by simp)
    simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, exitValues,
      List.append_nil, List.mem_append, List.mem_singleton] at typed ⊢
    grind only []
  case matchSum value cases =>
    split at accepted <;> try contradiction
    rename_i schema tag payload owner operandsEqual
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨⟨binder, body⟩, _, accepted⟩ := accepted
    have whole := inputs ⟨.variant schema tag payload, owner⟩ (by simp)
    have payloadTyped : ValueTokensBounded limit payload := by simpa only [ValueTokensBounded, ownedTokens] using whole
    exact ValueInventory.enterPattern_preserves_all machine context [binder] [payload] owner body bindings after
      accepted _ typed outer (by simpa using payloadTyped)
  case unpackProduct value vars body =>
    split at accepted <;> try contradiction
    rename_i schema fields owner operandsEqual
    have whole := inputs ⟨.product schema fields, owner⟩ (by simp)
    have fieldsTyped : ∀ child ∈ fields, ValueTokensBounded limit child := by
      intro child member token tokenMember
      apply whole token
      simpa only [ownedTokens] using List.mem_flatMap.mpr ⟨child, member, tokenMember⟩
    exact ValueInventory.enterPattern_preserves_all machine context vars fields owner body bindings after
      accepted _ typed outer fieldsTyped

theorem unwindStep_preserves_token_bounds (machine : State) (context : Context) (after : Transition)
    (original : Cleanup.Exit .source) (unwinding : machine.control = .unwind original)
    (accepted : unwindStep machine context = .ok after)
    (typed : ValueInventory.All (ValueTokensBounded limit) machine) : ValueInventory.All (ValueTokensBounded limit) after.state := by
  have originalTyped : ∀ value ∈ exitValues original, ValueTokensBounded limit value := by
    intro value member
    apply typed
    simp [ValueInventory.state, unwinding, ValueInventory.control, member]
  have observedTyped : ∀ value ∈ exitValues (observedExit machine original), ValueTokensBounded limit value :=
    fun value member => originalTyped value (ValueInventory.observed_exit_subset machine original member)
  simp only [unwindStep, unwinding, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨scope, scopeAt, accepted⟩ := accepted
  have holdingsTyped := ValueInventory.scope_holdings_preserve_all machine machine.scope scope scopeAt _ typed
  have pendingTyped := liveOwned_holdings_preserve_token_bounds machine.heap scope.holdings holdingsTyped
  have pendingStateTyped : ValueInventory.All (ValueTokensBounded limit)
      { machine with control := .discard (scope.holdings.flatMap (liveOwned machine.heap)) (.unwind (observedExit machine original)) } := by
    simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.afterRelease,
      List.mem_append, List.mem_map] at typed ⊢
    grind only []
  cases stacked : machine.stack with
  | nil =>
    simp only [stacked] at accepted
    split at accepted
    · cases accepted
      simpa only [ValueInventory.All, ValueInventory.state, stacked] using pendingStateTyped
    · split at accepted <;> try contradiction
      all_goals cases accepted
      all_goals simp only [ValueInventory.All, ValueInventory.state, ValueInventory.status,
        List.mem_append, unwinding, stacked] at typed ⊢
      all_goals grind only []
  | cons saved tail =>
    have frameTyped := ValueInventory.frame_preserves_all machine saved (by simp [stacked]) _ typed
    have tailTyped : ∀ value ∈ tail.flatMap ValueInventory.frame, ValueTokensBounded limit value := by
      intro value member
      apply typed
      simp [ValueInventory.state, stacked, member]
    have tailStateTyped : ValueInventory.All (ValueTokensBounded limit) { machine with stack := tail } := by
      simp only [ValueInventory.All, ValueInventory.state, List.mem_append] at typed ⊢
      grind only []
    cases saved <;> simp only [stacked] at accepted
    case invocation invocation parent =>
      split at accepted
      · cases accepted
        simpa only [ValueInventory.All, ValueInventory.state, stacked] using pendingStateTyped
      · cases accepted
        simpa only [ValueInventory.All, ValueInventory.state, unwinding] using tailStateTyped
    case restore invocation parent => cases accepted; simpa only [ValueInventory.All, ValueInventory.state, unwinding] using tailStateTyped
    case lexical identity =>
      split at accepted
      · cases accepted
        simpa only [ValueInventory.All, ValueInventory.state, stacked] using pendingStateTyped
      · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨_, _, parent, _, rfl⟩ := accepted
        simpa only [ValueInventory.All, ValueInventory.state, unwinding] using tailStateTyped
    case binding binder body bindings parent => cases accepted; simpa only [ValueInventory.All, ValueInventory.state, unwinding] using tailStateTyped
    case operands intent bindings remaining evaluated => cases accepted; simpa only [ValueInventory.All, ValueInventory.state, unwinding] using tailStateTyped
    case handler active => cases accepted; simpa only [ValueInventory.All, ValueInventory.state, unwinding] using tailStateTyped
    case region region => cases accepted; simpa only [ValueInventory.All, ValueInventory.state, unwinding] using tailStateTyped
    case injection values => cases accepted; simpa only [ValueInventory.All, ValueInventory.state, unwinding] using tailStateTyped
    case protection identity =>
      apply beginCleanup_preserves_token_bounds _ _ _ _ _ _ _ accepted typed observedTyped (by simp) tailTyped
    case cleanupReturn identity invocation outer normal =>
      apply cleanupFailed_preserves_token_bounds _ _ _ _ _ _ _ _ accepted typed _ observedTyped _ tailTyped
      · intro value member
        exact frameTyped value (List.mem_append_left _ member)
      · intro value member
        apply frameTyped
        simp only [ValueInventory.frame, List.mem_append, List.mem_map, Option.mem_toList]
        exact Or.inr ⟨value, by simpa using member, rfl⟩
    case releaseReturn scope afterRelease =>
      cases accepted
      have mergedTyped := ValueInventory.merge_after_preserves_all afterRelease (observedExit machine original) _ frameTyped observedTyped
      simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control,
        List.mem_append] at tailStateTyped ⊢
      grind only []
    case disposalReturn remaining afterRelease invocation parent =>
      have remainingTyped : ∀ value ∈ remaining, ValueTokensBounded limit value.value := by
        intro value member
        apply frameTyped
        simp only [ValueInventory.frame, List.mem_append, List.mem_map]
        exact Or.inl ⟨value, member, rfl⟩
      have afterTyped : ∀ value ∈ ValueInventory.afterRelease afterRelease, ValueTokensBounded limit value := by
        intro value member
        apply frameTyped
        exact List.mem_append_right _ member
      have mergedTyped := ValueInventory.merge_after_preserves_all afterRelease (observedExit machine original) _ afterTyped observedTyped
      cases primaryIs : (observedExit machine original).primary <;> simp only [primaryIs] at accepted
      all_goals cases afterRelease <;> simp only [pure, Except.pure, Except.bind] at accepted
      all_goals cases accepted
      all_goals simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control,
        ValueInventory.afterRelease, List.mem_append, List.mem_map] at tailStateTyped mergedTyped afterTyped ⊢
      all_goals grind only []

theorem tickRunning_preserves_token_bounds (machine : State) (context : Context) (after : Transition)
    (accepted : tickRunning machine context = .ok after) (contextTyped : context.typingValid = true)
    (upper : after.state.heap.nextCustody ≤ limit)
    (typed : ValueInventory.All (ValueTokensBounded limit) machine) :
    ValueInventory.All (ValueTokensBounded limit) after.state := by
  cases executing : machine.control <;> simp only [tickRunning, executing] at accepted
  case term => exact ValueInventory.enterTerm_preserves_all _ _ _ accepted _ typed
  case expression => exact enterExpression_preserves_token_bounds _ _ _ accepted contextTyped upper typed
  case invoke => exact ValueInventory.enterInvocation_preserves_all _ _ _ accepted _ typed
  case release => exact releaseScope_preserves_token_bounds _ _ accepted typed
  case discard => exact discardValues_preserves_token_bounds _ _ _ accepted typed
  case unwind => exact unwindStep_preserves_token_bounds _ _ _ _ executing accepted typed
  case execute intent bindings operands =>
    cases intent with
    | primitive => exact executePrimitive_preserves_token_bounds _ _ _ accepted contextTyped upper typed
    | term term =>
      cases term <;> first
        | exact executeEffectTerm_preserves_token_bounds _ _ _ accepted upper typed
        | exact executeCleanupTerm_preserves_token_bounds _ _ _ accepted typed
        | exact executeControlTerm_preserves_token_bounds _ _ _ accepted typed
  case delivered value =>
    have valueTyped : ValueTokensBounded limit value.value := by
      apply typed
      simp [ValueInventory.state, executing, ValueInventory.control]
    cases stacked : machine.stack with
    | nil =>
      simp only [stacked, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
      simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.status,
        List.mem_append, List.mem_singleton] at typed ⊢
      grind only []
    | cons saved tail =>
      have frameTyped := ValueInventory.frame_preserves_all machine saved (by simp [stacked]) _ typed
      have tailTyped : ∀ child ∈ tail.flatMap ValueInventory.frame, ValueTokensBounded limit child := by
        intro child member
        apply typed
        simp [ValueInventory.state, stacked, member]
      have tailState : ValueInventory.All (ValueTokensBounded limit) {machine with stack := tail} := by
        simp only [ValueInventory.All, ValueInventory.state, List.mem_append] at typed ⊢
        grind only []
      cases saved <;> simp only [stacked] at accepted
      all_goals first
        | exact ValueInventory.enterBinding_preserves_all _ _ _ accepted _ typed
        | exact ValueInventory.deliverOperand_preserves_all _ _ accepted _ typed
        | exact ValueInventory.leaveInvocation_preserves_all _ _ accepted _ typed
        | exact leaveLexical_preserves_token_bounds _ _ accepted typed
        | exact ValueInventory.restoreResumeCaller_preserves_all _ _ accepted _ typed
        | exact ValueInventory.completeHandler_preserves_all _ _ _ accepted _ typed
        | exact ValueInventory.finishCleanup_preserves_all _ _ _ accepted _ typed
        | (cases accepted; simpa only [executing] using tailState)
        | skip
      case protection identity =>
        exact beginCleanup_preserves_token_bounds _ _ _ _ _ _ _ accepted typed
          (by simpa [exitValues] using valueTyped) (by simpa using valueTyped) tailTyped
      case disposalReturn => contradiction
      case releaseReturn scope released =>
        cases accepted
        simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.frame,
          List.mem_append] at tailState frameTyped ⊢
        grind only []

theorem tick_preserves_token_bounds (machine : State) (context : Context) (after : Transition)
    (accepted : tick machine context = .ok after) (contextTyped : context.typingValid = true)
    (upper : after.state.heap.nextCustody ≤ limit)
    (typed : ValueInventory.All (ValueTokensBounded limit) machine) :
    ValueInventory.All (ValueTokensBounded limit) after.state := by
  cases phase : machine.status <;> simp only [tick, phase] at accepted
  · exact tickRunning_preserves_token_bounds _ _ _ accepted contextTyped upper typed
  all_goals cases accepted; exact typed

theorem step_preserves_token_bounds (context : Context) (before after : State) (events : List Event)
    (step : Step context before events after) (contextTyped : context.typingValid = true)
    (upper : after.heap.nextCustody ≤ limit)
    (typed : ValueInventory.All (ValueTokensBounded limit) before) :
    ValueInventory.All (ValueTokensBounded limit) after := by
  cases step with
  | internal accepted => exact tick_preserves_token_bounds _ _ _ accepted contextTyped upper typed
  | external accepted => exact external_preserves _ _ _ _ accepted typed

theorem step_preserves_allocated_tokens (context : Context) (before after : State) (events : List Event)
    (step : Step context before events after) (contextTyped : context.typingValid = true)
    (typed : All before.heap.nextCustody before) : All after.heap.nextCustody after := by
  have grown := all_mono _ _ before typed (step_allocation step).heap.custody
  exact step_preserves_token_bounds _ _ _ _ step contextTyped (Nat.le_refl _) grown

theorem steps_preserve_allocated_tokens (context : Context) (before after : State) (events : List Event)
    (steps : Steps context before events after) (contextTyped : context.typingValid = true)
    (typed : All before.heap.nextCustody before) : All after.heap.nextCustody after := by
  induction steps with
  | refl => exact typed
  | cons step _ induction => exact induction (step_preserves_allocated_tokens _ _ _ _ step contextTyped typed)

theorem initialized_execution_preserves_token_bounds (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : All after.heap.nextCustody after := by
  have contextTyped : context.typingValid = true := by
    simpa only [Context.typingValid, Option.any_eq_true] using initial_checks_typing _ _ _ initialized
  exact steps_preserve_allocated_tokens _ _ _ _ steps contextTyped (initial_bounded _ _ _ initialized)

/-- Every retained token, including spent tokens in lexical remnants, precedes
all future custody allocations along the actual initialized execution. -/
theorem historical_tokens_precede_future_supply (context : Context) (arguments : List SemanticValue)
    (initialState before after : State) (prefixEvents suffixEvents : List Event)
    (initialized : initial context arguments = .ok initialState)
    (reached : Steps context initialState prefixEvents before) (continued : Steps context before suffixEvents after)
    (value : SemanticValue) (member : value ∈ ValueInventory.state before)
    (token : CustodyToken) (owned : token ∈ ownedTokens value) : token.value < after.heap.nextCustody := by
  have bounded := initialized_execution_preserves_token_bounds _ _ _ _ _ initialized reached value member token owned
  exact Nat.lt_of_lt_of_le bounded (steps_allocation continued).heap.custody

theorem fresh_token_absent_from_retained_values (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (value : SemanticValue)
    (member : value ∈ ValueInventory.state machine) :
    (⟨machine.heap.nextCustody⟩ : CustodyToken) ∉ ownedTokens value := by
  intro present
  have below := initialized_execution_preserves_token_bounds _ _ _ _ _ initialized steps value member _ present
  exact Nat.lt_irrefl _ below

end TokenInventory
end BoundaryV2.Profile.Source.Machine
