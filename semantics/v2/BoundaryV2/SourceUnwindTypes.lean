import BoundaryV2.SourceCleanupValueTypes

namespace BoundaryV2.Profile.Source.Machine

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem observed_exit_idempotent (machine : State) (exit : Cleanup.Exit .source) :
    observedExit machine (observedExit machine exit) = observedExit machine exit := by
  unfold observedExit
  cases machine.cancellation
  · rfl
  · cases exit with
    | mk primary failures cancellation => cases primary <;> rfl

theorem observed_exit_failures (machine : State) (exit : Cleanup.Exit .source) :
    (observedExit machine exit).failures = exit.failures := by
  unfold observedExit
  cases machine.cancellation <;> rfl

namespace ValueInventory

theorem frame_preserves_all (machine : State) (saved : Frame) (member : saved ∈ machine.stack)
    (property : SemanticValue → Prop) (holds : All property machine) :
    ∀ value ∈ frame saved, property value := by
  intro value belongs
  apply holds
  simp only [state, List.mem_append, List.mem_flatMap]
  grind only []

theorem propagate_after_preserves_all (after : AfterRelease) (exit : Cleanup.Exit .source)
    (property : SemanticValue → Prop) (afterHolds : ∀ value ∈ afterRelease after, property value)
    (exitHolds : ∀ value ∈ exitValues exit, property value) :
    ∀ value ∈ exitValues (match after with
      | .unwind outer => propagateExit outer exit
      | .deliver value => propagateExit ⟨.normal value.value, [], none⟩ exit), property value := by
  cases after with
  | unwind outer =>
    intro value member
    exact (List.mem_append.mp (propagate_exit_subset outer exit member)).elim (afterHolds value) (exitHolds value)
  | deliver normal =>
    intro value member
    rcases List.mem_append.mp (propagate_exit_subset ⟨.normal normal.value, [], none⟩ exit member) with member | member
    · exact afterHolds value member
    · exact exitHolds value member

end ValueInventory

theorem unwindStep_preserves_value_shapes (machine : State) (context : Context) (after : Transition)
    (original : Cleanup.Exit .source) (unwinding : machine.control = .unwind original)
    (accepted : unwindStep machine context = .ok after)
    (typed : ValueInventory.All (ValueShape context.source.schemas) machine)
    (failureTypes : ∀ value, (observedExit machine original).primary = .failure value ∨ value ∈ original.failures →
      ValueShape context.source.schemas value ∧ value.schema = context.source.failure)
    : ValueInventory.All (ValueShape context.source.schemas) after.state := by
  have originalTyped : ∀ value ∈ exitValues original, ValueShape context.source.schemas value := by
    intro value member
    apply typed
    simp [ValueInventory.state, unwinding, ValueInventory.control, member]
  have observedTyped : ∀ value ∈ exitValues (observedExit machine original), ValueShape context.source.schemas value :=
    fun value member => originalTyped value (ValueInventory.observed_exit_subset machine original member)
  simp only [unwindStep, unwinding, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨scope, scopeAt, accepted⟩ := accepted
  have holdingsTyped := ValueInventory.scope_holdings_preserve_all machine machine.scope scope scopeAt _ typed
  have pendingTyped := liveOwned_holdings_preserve_value_shapes machine.heap scope.holdings holdingsTyped
  have pendingStateTyped : ValueInventory.All (ValueShape context.source.schemas)
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
    have tailTyped : ∀ value ∈ tail.flatMap ValueInventory.frame, ValueShape context.source.schemas value := by
      intro value member
      apply typed
      simp [ValueInventory.state, stacked, member]
    have tailStateTyped : ValueInventory.All (ValueShape context.source.schemas) { machine with stack := tail } := by
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
      apply beginCleanup_preserves_value_shapes _ _ _ _ _ _ _ accepted typed observedTyped (by simp) tailTyped
      · simpa only [observed_exit_idempotent, observed_exit_failures] using failureTypes
    case cleanupReturn identity invocation outer normal =>
      apply finishCleanupUnwind_preserves_value_shapes _ _ _ _ _ _ _ _ accepted typed _ observedTyped _ tailTyped
      · intro value member
        exact frameTyped value (List.mem_append_left _ member)
      · intro value member
        apply frameTyped
        simp only [ValueInventory.frame, List.mem_append, List.mem_map, Option.mem_toList]
        exact Or.inr ⟨value, by simpa using member, rfl⟩
    case releaseReturn scope afterRelease =>
      cases accepted
      have mergedTyped := ValueInventory.propagate_after_preserves_all afterRelease (observedExit machine original) _ frameTyped observedTyped
      simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control,
        List.mem_append] at tailStateTyped ⊢
      grind only []
    case disposalReturn remaining afterRelease invocation parent =>
      have remainingTyped : ∀ value ∈ remaining, ValueShape context.source.schemas value.value := by
        intro value member
        apply frameTyped
        simp only [ValueInventory.frame, List.mem_append, List.mem_map]
        exact Or.inl ⟨value, member, rfl⟩
      have afterTyped : ∀ value ∈ ValueInventory.afterRelease afterRelease, ValueShape context.source.schemas value := by
        intro value member
        apply frameTyped
        exact List.mem_append_right _ member
      have mergedTyped := ValueInventory.propagate_after_preserves_all afterRelease (observedExit machine original) _ afterTyped observedTyped
      cases primaryIs : (observedExit machine original).primary <;> simp only [primaryIs] at accepted
      all_goals cases afterRelease <;> simp only [pure, Except.pure, Except.bind] at accepted
      all_goals cases accepted
      all_goals simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control,
        ValueInventory.afterRelease, List.mem_append, List.mem_map] at tailStateTyped mergedTyped afterTyped ⊢
      all_goals grind only []

end BoundaryV2.Profile.Source.Machine
