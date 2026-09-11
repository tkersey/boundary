import BoundaryV2.SourceReferenceSafetyCleanupExecution

namespace BoundaryV2.Profile.Source.Machine
namespace ReferenceSafety
open ReferenceContracts

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem enterTerm_valid (machine : State) (source : Module) (after : Transition)
    (accepted : enterTerm machine source = .ok after) (good : Valid schemas machine) : Valid schemas after.state := by
  have values := ValueInventory.enterTerm_preserves_all _ _ _ accepted _ good.values
  unfold enterTerm at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  repeat' split at accepted
  all_goals cases accepted; exact ⟨values, good.live⟩

theorem deliverOperand_valid (machine : State) (after : Transition)
    (accepted : deliverOperand machine = .ok after) (good : Valid schemas machine) : Valid schemas after.state := by
  have values := ValueInventory.deliverOperand_preserves_all _ _ accepted _ good.values
  unfold deliverOperand at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  split at accepted <;> cases accepted <;> exact ⟨values, good.live⟩

theorem completeHandler_valid (machine : State) (context : Context) (after : Transition)
    (accepted : completeHandler machine context = .ok after) (good : Valid schemas machine) : Valid schemas after.state := by
  have values := ValueInventory.completeHandler_preserves_all _ _ _ accepted _ good.values
  unfold completeHandler at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact ⟨values, good.live⟩

theorem executeControlTerm_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executeControlTerm machine context = .ok after)
    (good : Valid context.source.schemas machine)
    (modes : ValueInventory.All (ValueModes context.source.schemas) machine) : Valid context.source.schemas after.state := by
  have typed := good.values
  unfold executeControlTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  have outer : ∀ binding ∈ bindings, ValueGood context.source.schemas machine.heap binding.located.value := by
    intro binding member
    apply typed
    simp only [ValueInventory.state, executing, ValueInventory.control, ValueInventory.environment,
      List.mem_append, List.mem_map]
    grind only []
  have inputs : ∀ value ∈ operands, ValueGood context.source.schemas machine.heap value.value := by
    intro value member
    apply typed
    simp only [ValueInventory.state, executing, ValueInventory.control, List.mem_append, List.mem_map]
    grind only []
  have inputModes : ∀ value ∈ operands, ValueModes context.source.schemas value.value := by
    intro value member
    apply modes
    simp only [ValueInventory.state, executing, ValueInventory.control, List.mem_append, List.mem_map]
    grind only []
  cases term <;> simp only at accepted <;> try contradiction
  case conditional condition yes no =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    refine ⟨?_, good.live⟩
    simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.environment,
      List.mem_append, List.mem_map] at typed ⊢
    grind only []
  case call function arguments =>
    cases accepted
    refine ⟨?_, good.live⟩
    simpa only [ValueInventory.All, ValueInventory.state, executing, ValueInventory.control] using typed
  case apply function arguments =>
    split at accepted <;> try contradiction
    rename_i closure args operandsEqual
    exact applyClosure_valid machine context closure args after accepted good modes
      (inputs closure (by simp)) (inputModes closure (by simp))
      (fun value member => inputs value (by simp [member]))
      (fun value member => inputModes value (by simp [member]))
  case fail failure =>
    split at accepted <;> try contradiction
    rename_i value operandsEqual
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, rfl⟩ := accepted
    have failed := inputs value (by simp)
    refine ⟨?_, good.live⟩
    simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, exitValues,
      List.append_nil, List.mem_append, List.mem_singleton] at typed ⊢
    grind only []
  case matchSum value cases =>
    split at accepted <;> try contradiction
    rename_i schema tag payload owner operandsEqual
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨⟨binder, body⟩, _, accepted⟩ := accepted
    have whole := inputs ⟨.variant schema tag payload, owner⟩ (by simp)
    have payloadTyped := variant_payload_good _ _ _ _ whole
    exact enterPattern_valid machine context [binder] [payload] owner body bindings after
      accepted good outer (by simpa using payloadTyped)
  case unpackProduct value vars body =>
    split at accepted <;> try contradiction
    rename_i schema fields owner operandsEqual
    have whole := inputs ⟨.product schema fields, owner⟩ (by simp)
    have fieldsTyped := fun child member => product_child_good _ _ _ whole child member
    exact enterPattern_valid machine context vars fields owner body bindings after
      accepted good outer fieldsTyped

theorem unwindStep_valid (machine : State) (context : Context) (after : Transition)
    (original : Cleanup.Exit .source) (unwinding : machine.control = .unwind original)
    (accepted : unwindStep machine context = .ok after)
    (good : Valid context.source.schemas machine)
    (modes : ValueInventory.All (ValueModes context.source.schemas) machine) : Valid context.source.schemas after.state := by
  have typed := good.values
  have originalTyped : ∀ value ∈ exitValues original, ValueGood context.source.schemas machine.heap value := by
    intro value member
    apply typed
    simp [ValueInventory.state, unwinding, ValueInventory.control, member]
  have observedTyped : ∀ value ∈ exitValues (observedExit machine original), ValueGood context.source.schemas machine.heap value :=
    fun value member => originalTyped value (ValueInventory.observed_exit_subset machine original member)
  have observedModes : ∀ value ∈ exitValues (observedExit machine original), ValueModes context.source.schemas value := by
    intro value member
    apply modes
    have originalMember := ValueInventory.observed_exit_subset machine original member
    simp [ValueInventory.state, unwinding, ValueInventory.control, originalMember]
  simp only [unwindStep, unwinding, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨scope, scopeAt, accepted⟩ := accepted
  have holdingsTyped := ValueInventory.scope_holdings_preserve_all machine machine.scope scope scopeAt _ typed
  have pendingTyped := liveOwned_holdings_good machine.heap machine.heap scope.holdings holdingsTyped
  have pendingStateTyped : ValueInventory.All (ValueGood context.source.schemas machine.heap)
      { machine with control := .discard (scope.holdings.flatMap (liveOwned machine.heap)) (.unwind (observedExit machine original)) } := by
    simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.afterRelease,
      List.mem_append, List.mem_map] at typed ⊢
    grind only []
  cases stacked : machine.stack with
  | nil =>
    simp only [stacked] at accepted
    split at accepted
    · cases accepted
      refine ⟨?_, good.live⟩
      simpa only [ValueInventory.All, ValueInventory.state, stacked] using pendingStateTyped
    · split at accepted <;> try contradiction
      all_goals cases accepted
      all_goals refine ⟨?_, good.live⟩
      all_goals simp only [ValueInventory.All, ValueInventory.state, ValueInventory.status,
        List.mem_append, unwinding, stacked] at typed ⊢
      all_goals grind only []
  | cons saved tail =>
    have frameTyped := ValueInventory.frame_preserves_all machine saved (by simp [stacked]) _ typed
    have tailTyped : ∀ value ∈ tail.flatMap ValueInventory.frame, ValueGood context.source.schemas machine.heap value := by
      intro value member
      apply typed
      simp [ValueInventory.state, stacked, member]
    have tailStateTyped : ValueInventory.All (ValueGood context.source.schemas machine.heap) { machine with stack := tail } := by
      simp only [ValueInventory.All, ValueInventory.state, List.mem_append] at typed ⊢
      grind only []
    cases saved <;> simp only [stacked] at accepted
    case invocation invocation parent =>
      split at accepted
      · cases accepted
        refine ⟨?_, good.live⟩
        simpa only [ValueInventory.All, ValueInventory.state, stacked] using pendingStateTyped
      · cases accepted
        refine ⟨?_, good.live⟩
        simpa only [ValueInventory.All, ValueInventory.state, unwinding] using tailStateTyped
    case restore invocation parent => cases accepted; refine ⟨?_, good.live⟩; simpa only [ValueInventory.All, ValueInventory.state, unwinding] using tailStateTyped
    case lexical identity =>
      split at accepted
      · cases accepted
        refine ⟨?_, good.live⟩
        simpa only [ValueInventory.All, ValueInventory.state, stacked] using pendingStateTyped
      · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨_, _, parent, _, rfl⟩ := accepted
        refine ⟨?_, good.live⟩
        simpa only [ValueInventory.All, ValueInventory.state, unwinding] using tailStateTyped
    case binding binder body bindings parent => cases accepted; refine ⟨?_, good.live⟩; simpa only [ValueInventory.All, ValueInventory.state, unwinding] using tailStateTyped
    case operands intent bindings remaining evaluated => cases accepted; refine ⟨?_, good.live⟩; simpa only [ValueInventory.All, ValueInventory.state, unwinding] using tailStateTyped
    case handler active => cases accepted; refine ⟨?_, good.live⟩; simpa only [ValueInventory.All, ValueInventory.state, unwinding] using tailStateTyped
    case region region => cases accepted; refine ⟨?_, good.live⟩; simpa only [ValueInventory.All, ValueInventory.state, unwinding] using tailStateTyped
    case injection values => cases accepted; refine ⟨?_, good.live⟩; simpa only [ValueInventory.All, ValueInventory.state, unwinding] using tailStateTyped
    case protection identity =>
      apply beginCleanup_valid _ _ _ _ _ _ _ accepted good modes
        (fun value member => ⟨observedTyped value member, observedModes value member⟩) (by simp)
      intro value member
      refine ⟨tailTyped value member, ?_⟩
      apply modes
      simp [ValueInventory.state, stacked, member]
    case cleanupReturn identity invocation outer normal =>
      apply cleanupFailed_valid _ _ _ _ _ _ _ _ accepted good _ observedTyped _ tailTyped
      · intro value member
        exact frameTyped value (List.mem_append_left _ member)
      · intro value member
        apply frameTyped
        simp only [ValueInventory.frame, List.mem_append, List.mem_map, Option.mem_toList]
        exact Or.inr ⟨value, by simpa using member, rfl⟩
    case releaseReturn scope afterRelease =>
      cases accepted
      have mergedTyped := ValueInventory.merge_after_preserves_all afterRelease (observedExit machine original) _ frameTyped observedTyped
      refine ⟨?_, good.live⟩
      simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control,
        List.mem_append] at tailStateTyped ⊢
      grind only []
    case disposalReturn remaining afterRelease invocation parent =>
      have remainingTyped : ∀ value ∈ remaining, ValueGood context.source.schemas machine.heap value.value := by
        intro value member
        apply frameTyped
        simp only [ValueInventory.frame, List.mem_append, List.mem_map]
        exact Or.inl ⟨value, member, rfl⟩
      have afterTyped : ∀ value ∈ ValueInventory.afterRelease afterRelease, ValueGood context.source.schemas machine.heap value := by
        intro value member
        apply frameTyped
        exact List.mem_append_right _ member
      have mergedTyped := ValueInventory.merge_after_preserves_all afterRelease (observedExit machine original) _ afterTyped observedTyped
      cases primaryIs : (observedExit machine original).primary <;> simp only [primaryIs] at accepted
      all_goals cases afterRelease <;> simp only [pure, Except.pure, Except.bind] at accepted
      all_goals cases accepted
      all_goals refine ⟨?_, good.live⟩
      all_goals simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control,
        ValueInventory.afterRelease, List.mem_append, List.mem_map] at tailStateTyped mergedTyped afterTyped ⊢
      all_goals grind only []


end ReferenceSafety
end BoundaryV2.Profile.Source.Machine
