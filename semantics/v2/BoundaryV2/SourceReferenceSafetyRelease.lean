import BoundaryV2.SourceReferenceSafetyLifetime

namespace BoundaryV2.Profile.Source.Machine
namespace ReferenceSafety
open ReferenceContracts

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem leaveLexical_reference_facts (machine : State) (after : Transition)
    (accepted : leaveLexical machine = .ok after) :
    (∀ value, ValueGood schemas machine.heap value → ValueGood schemas after.state.heap value) ∧
    (machine.heap.CustodyLive → after.state.heap.CustodyLive) := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, record, recordFound, parent, _, result, leftOk, accepted⟩ := accepted
  have facts := leaveScope_reference_facts (schemas := schemas) _ _ _ _ _ _ leftOk
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨parentRecord, parentFound, store, movedOk, rfl⟩ := accepted
  exact ⟨fun value holds => fields_value store _ _ rfl rfl rfl
      (move_value result.state.heap store _ _ _ movedOk (facts.1 value holds)),
    fun live => moveValues_preserves_live_objects result.state.heap store _ _ movedOk (facts.2 live)⟩

theorem leaveLexical_valid (machine : State) (after : Transition)
    (accepted : leaveLexical machine = .ok after)
    (good : Valid schemas machine) : Valid schemas after.state := by
  let target := after.state.heap
  have facts := leaveLexical_reference_facts (schemas := schemas) _ _ accepted
  have typed : ValueInventory.All (ValueGood schemas target) machine :=
    fun value member => facts.1 _ (good.values value member)
  refine ⟨?_, facts.2 good.live⟩
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  rename_i value delivered
  split at accepted <;> try contradiction
  rename_i scope tail stacked
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, record, recordFound, parent, _, result, leftOk, accepted⟩ := accepted
  have valueTyped : ValueGood schemas target value.value := by
    apply typed
    simp [ValueInventory.state, delivered, ValueInventory.control]
  have tailTyped : ∀ child ∈ tail.flatMap ValueInventory.frame, ValueGood schemas target child := by
    intro child member
    apply typed
    simp [ValueInventory.state, stacked, ValueInventory.frame, member]
  have resultTyped := ValueInventory.leaveScope_preserves_all machine parent machine.invocation tail value result
    leftOk _ typed tailTyped valueTyped
  have holdingsTyped := ValueInventory.scope_holdings_preserve_all machine scope record recordFound _ typed
  have remainingTyped : ∀ child ∈ record.holdings.flatMap (liveOwned result.state.heap), ValueGood schemas target child.value := by
    intro child member
    obtain ⟨original, originalMember, member⟩ := List.mem_flatMap.mp member
    exact liveOwnedValue_good result.state.heap target original.owner original.value
      (holdingsTyped original originalMember) child member
  split at accepted <;> try contradiction
  rename_i departed resultValue resultControl
  have resultValueTyped : ValueGood schemas target resultValue.value := by
    apply resultTyped
    simp [ValueInventory.state, resultControl, ValueInventory.control, ValueInventory.afterRelease]
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨parentRecord, parentFound, store, movedOk, rfl⟩ := accepted
  have parentTyped := ValueInventory.scope_holdings_preserve_all result.state parent parentRecord parentFound _ resultTyped
  have movedTyped := ValueInventory.moveValues_preserves_all _ _ _ _ movedOk _ resultTyped
  have inheritedTyped : ∀ child ∈ (record.holdings.flatMap (liveOwned result.state.heap)).mapIdx
      (fun index located => retainAt located (.temporary parent (parentRecord.nextOwner + index))),
      ValueGood schemas target child.value := by
    intro child member
    simp only [List.mapIdx_eq_zipIdx_map, List.mem_map] at member
    obtain ⟨⟨original, index⟩, originalMember, rfl⟩ := member
    exact remainingTyped original (List.fst_mem_of_mem_zipIdx originalMember)
  simp only [ValueInventory.All, ValueInventory.state, ValueInventory.heap, ValueInventory.control,
    List.mem_append, List.mem_flatMap, List.mem_map, List.mem_singleton] at movedTyped ⊢
  grind only [→ List.mem_or_eq_of_mem_set, List.mem_append]

theorem releaseScope_valid (machine : State) (after : Transition)
    (accepted : releaseScope machine = .ok after)
    (good : Valid schemas machine) : Valid schemas after.state := by
  have typed := good.values
  unfold releaseScope at accepted
  split at accepted <;> try contradiction
  rename_i scope released releasing
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨record, recordFound, _, _, rfl⟩ := accepted
  refine ⟨?_, good.live⟩
  have holdingTypes := ValueInventory.scope_holdings_preserve_all machine scope record recordFound _ typed
  have liveTypes := liveOwned_holdings_good machine.heap machine.heap record.holdings holdingTypes
  simp only [ValueInventory.All, ValueInventory.state, releasing, ValueInventory.control,
    List.mem_append, List.mem_map] at typed ⊢
  grind only []

theorem discardValues_valid (machine : State) (context : Context) (after : Transition)
    (accepted : discardValues machine context = .ok after)
    (good : Valid context.source.schemas machine)
    (modes : ValueInventory.All (ValueModes context.source.schemas) machine) : Valid context.source.schemas after.state := by
  have typed := good.values
  unfold discardValues at accepted
  split at accepted <;> try contradiction
  rename_i values released discarding
  have releasesTyped : ∀ value ∈ ValueInventory.afterRelease released, ValueGood context.source.schemas machine.heap value := by
    intro value member
    apply typed
    simp [ValueInventory.state, discarding, ValueInventory.control, member]
  cases values with
  | nil =>
    cases accepted
    exact ⟨ValueInventory.resumeRelease_preserves_all machine released _ typed releasesTyped, good.live⟩
  | cons value rest =>
    simp only at accepted
    have restTyped : ∀ child ∈ rest, ValueGood context.source.schemas machine.heap child.value := by
      intro child member
      apply typed
      simp only [ValueInventory.state, discarding, ValueInventory.control, List.map_cons, List.mem_append,
        List.mem_cons, List.mem_map]
      grind only []
    split at accepted
    · cases accepted
      refine ⟨?_, good.live⟩
      simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, List.mem_append, List.mem_map] at typed ⊢
      grind only []
    · simp only [bind, except_bind_ok] at accepted
      obtain ⟨⟨node, stored⟩, lookup, accepted⟩ := accepted
      have storedTypes := ValueInventory.lookupObject_preserves_all machine value node stored lookup _ typed
      have storedModes := ValueInventory.lookupObject_preserves_all machine value node stored lookup _ modes
      have valueMember : value.value ∈ ValueInventory.state machine := by
        simp [ValueInventory.state, discarding, ValueInventory.control]
      have valueGood := good.values _ valueMember
      have valueModes := modes _ valueMember
      cases stored <;> simp only at accepted <;> try contradiction
      case oneShot saved =>
        simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨store, retired, rfl⟩ := accepted
        have valueShape := retirement_shape _ _ _ retired valueModes
        have transport : ∀ child, ValueModes context.source.schemas child →
            ValueGood context.source.schemas machine.heap child → ValueGood context.source.schemas store child :=
          fun child mode holds => retirement_value _ _ _ _ retired good.live valueShape valueGood mode holds
        have oldTyped : ValueInventory.All (ValueGood context.source.schemas store) machine :=
          fun child member => transport child (modes child member) (typed child member)
        have storeTyped := ValueInventory.retireObject_preserves_all machine value store retired _ oldTyped
        have storedTypes := fun child member => transport child (storedModes child member) (storedTypes child member)
        have releasesTyped : ∀ child ∈ ValueInventory.afterRelease released, ValueGood context.source.schemas store child := by
          intro child member
          apply oldTyped
          simp only [ValueInventory.state, discarding, ValueInventory.control, List.map_cons,
            List.mem_append, List.mem_cons, List.mem_map]
          grind only []
        have restTyped : ∀ child ∈ rest, ValueGood context.source.schemas store child.value := by
          intro child member
          apply oldTyped
          simp only [ValueInventory.state, discarding, ValueInventory.control, List.map_cons,
            List.mem_append, List.mem_cons, List.mem_map]
          grind only []
        refine ⟨?_, retireObject_preserves_live_objects _ _ _ retired good.live valueGood.2.1⟩
        cases released <;> simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control,
          ValueInventory.object, ValueInventory.capture, ValueInventory.frame, ValueInventory.afterRelease,
          exitValues, List.mem_append, List.mem_map, List.flatMap_append, List.flatMap_cons, List.flatMap_nil,
          List.append_nil, List.mem_cons, List.not_mem_nil] at storeTyped storedTypes releasesTyped ⊢
        all_goals grind only []
      case closure schema function bindings =>
        simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨store, retired, rfl⟩ := accepted
        have valueShape := retirement_shape _ _ _ retired valueModes
        have transport : ∀ child, ValueModes context.source.schemas child →
            ValueGood context.source.schemas machine.heap child → ValueGood context.source.schemas store child :=
          fun child mode holds => retirement_value _ _ _ _ retired good.live valueShape valueGood mode holds
        have oldTyped : ValueInventory.All (ValueGood context.source.schemas store) machine :=
          fun child member => transport child (modes child member) (typed child member)
        have storeTyped := ValueInventory.retireObject_preserves_all machine value store retired _ oldTyped
        have storedTypes := fun child member => transport child (storedModes child member) (storedTypes child member)
        have releasesTyped : ∀ child ∈ ValueInventory.afterRelease released, ValueGood context.source.schemas store child := by
          intro child member
          apply oldTyped
          simp only [ValueInventory.state, discarding, ValueInventory.control, List.map_cons,
            List.mem_append, List.mem_cons, List.mem_map]
          grind only []
        have restTyped : ∀ child ∈ rest, ValueGood context.source.schemas store child.value := by
          intro child member
          apply oldTyped
          simp only [ValueInventory.state, discarding, ValueInventory.control, List.map_cons,
            List.mem_append, List.mem_cons, List.mem_map]
          grind only []
        refine ⟨?_, retireObject_preserves_live_objects _ _ _ retired good.live valueGood.2.1⟩
        have childrenTyped : ∀ child ∈ bindings.flatMap (fun binding => liveOwned store binding.located),
            ValueGood context.source.schemas store child.value := by
          intro child member
          obtain ⟨binding, bindingMember, childMember⟩ := List.mem_flatMap.mp member
          have bindingTyped := storedTypes binding.located.value (List.mem_map.mpr ⟨binding, bindingMember, rfl⟩)
          exact liveOwnedValue_good store store binding.located.owner binding.located.value bindingTyped child childMember
        simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, List.map_append,
          List.mem_append, List.mem_map] at storeTyped ⊢
        grind only []
      case package schema content =>
        simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨store, retired, rfl⟩ := accepted
        have valueShape := retirement_shape _ _ _ retired valueModes
        have transport : ∀ child, ValueModes context.source.schemas child →
            ValueGood context.source.schemas machine.heap child → ValueGood context.source.schemas store child :=
          fun child mode holds => retirement_value _ _ _ _ retired good.live valueShape valueGood mode holds
        have oldTyped : ValueInventory.All (ValueGood context.source.schemas store) machine :=
          fun child member => transport child (modes child member) (typed child member)
        have storeTyped := ValueInventory.retireObject_preserves_all machine value store retired _ oldTyped
        have storedTypes := fun child member => transport child (storedModes child member) (storedTypes child member)
        have releasesTyped : ∀ child ∈ ValueInventory.afterRelease released, ValueGood context.source.schemas store child := by
          intro child member
          apply oldTyped
          simp only [ValueInventory.state, discarding, ValueInventory.control, List.map_cons,
            List.mem_append, List.mem_cons, List.mem_map]
          grind only []
        have restTyped : ∀ child ∈ rest, ValueGood context.source.schemas store child.value := by
          intro child member
          apply oldTyped
          simp only [ValueInventory.state, discarding, ValueInventory.control, List.map_cons,
            List.mem_append, List.mem_cons, List.mem_map]
          grind only []
        refine ⟨?_, retireObject_preserves_live_objects _ _ _ retired good.live valueGood.2.1⟩
        have childrenTyped := liveOwnedValue_good store store content.owner content.value
          (storedTypes content.value (by simp [ValueInventory.object]))
        change ∀ child ∈ liveOwned store content, ValueGood context.source.schemas store child.value at childrenTyped
        simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, List.map_append,
          List.mem_append, List.mem_map] at storeTyped ⊢
        grind only []
      case resource schema content =>
        simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨store, retired, rfl⟩ := accepted
        have valueShape := retirement_shape _ _ _ retired valueModes
        have transport : ∀ child, ValueModes context.source.schemas child →
            ValueGood context.source.schemas machine.heap child → ValueGood context.source.schemas store child :=
          fun child mode holds => retirement_value _ _ _ _ retired good.live valueShape valueGood mode holds
        have oldTyped : ValueInventory.All (ValueGood context.source.schemas store) machine :=
          fun child member => transport child (modes child member) (typed child member)
        have storeTyped := ValueInventory.retireObject_preserves_all machine value store retired _ oldTyped
        have storedTypes := fun child member => transport child (storedModes child member) (storedTypes child member)
        have releasesTyped : ∀ child ∈ ValueInventory.afterRelease released, ValueGood context.source.schemas store child := by
          intro child member
          apply oldTyped
          simp only [ValueInventory.state, discarding, ValueInventory.control, List.map_cons,
            List.mem_append, List.mem_cons, List.mem_map]
          grind only []
        have restTyped : ∀ child ∈ rest, ValueGood context.source.schemas store child.value := by
          intro child member
          apply oldTyped
          simp only [ValueInventory.state, discarding, ValueInventory.control, List.map_cons,
            List.mem_append, List.mem_cons, List.mem_map]
          grind only []
        refine ⟨?_, retireObject_preserves_live_objects _ _ _ retired good.live valueGood.2.1⟩
        simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control,
          List.mem_append, List.mem_map] at storeTyped ⊢
        grind only []

end ReferenceSafety
end BoundaryV2.Profile.Source.Machine
