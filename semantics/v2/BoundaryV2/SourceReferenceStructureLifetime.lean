import BoundaryV2.SourceReferenceStructureEffects

namespace BoundaryV2.Profile.Source.Machine
namespace ReferenceStructureContracts

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem liveOwnedValue_preserves_reference_structure (store : Heap) (owner : Custody.Owner) (original : SemanticValue)
    (typed : ValueStructure schemas original) :
    ∀ value ∈ liveOwnedValue store owner original, ValueStructure schemas value.value := by
  cases original with
  | scalar _ _ | blob _ _ => simp [liveOwnedValue]
  | reference schema node token =>
    cases token with
    | none => simp [liveOwnedValue]
    | some token =>
      simp only [liveOwnedValue]
      split
      · intro value member
        cases List.mem_singleton.mp member
        exact typed
      · simp
  | product schema fields =>
    have typed := typed.product_children
    simp only [liveOwnedValue, List.mem_flatMap]
    intro value member
    obtain ⟨child, childMember, member⟩ := member
    exact liveOwnedValue_preserves_reference_structure store owner child (typed child childMember) value member
  | sequence schema fields =>
    have typed := typed.sequence_children
    simp only [liveOwnedValue, List.mem_flatMap]
    intro value member
    obtain ⟨child, childMember, member⟩ := member
    exact liveOwnedValue_preserves_reference_structure store owner child (typed child childMember) value member
  | variant schema tag payload =>
    simpa only [liveOwnedValue] using liveOwnedValue_preserves_reference_structure store owner payload typed.variant_payload
termination_by sizeOf original
decreasing_by
  all_goals subst original
  all_goals simp_wf
  all_goals first | omega | exact Nat.lt_trans (List.sizeOf_lt_of_mem childMember) (by omega)

theorem leaveLexical_preserves_reference_structure (machine : State) (after : Transition)
    (accepted : leaveLexical machine = .ok after)
    (typed : ValueInventory.All (ValueStructure schemas) machine) :
    ValueInventory.All (ValueStructure schemas) after.state := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  rename_i value delivered
  split at accepted <;> try contradiction
  rename_i scope tail stacked
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, record, recordFound, parent, _, result, leftOk, accepted⟩ := accepted
  have valueTyped : ValueStructure schemas value.value := by
    apply typed
    simp [ValueInventory.state, delivered, ValueInventory.control]
  have tailTyped : ∀ child ∈ tail.flatMap ValueInventory.frame, ValueStructure schemas child := by
    intro child member
    apply typed
    simp [ValueInventory.state, stacked, ValueInventory.frame, member]
  have resultTyped := ValueInventory.leaveScope_preserves_all machine parent machine.invocation tail value result
    leftOk _ typed tailTyped valueTyped
  have holdingsTyped := ValueInventory.scope_holdings_preserve_all machine scope record recordFound _ typed
  have remainingTyped : ∀ child ∈ record.holdings.flatMap (liveOwned result.state.heap), ValueStructure schemas child.value := by
    intro child member
    obtain ⟨original, originalMember, member⟩ := List.mem_flatMap.mp member
    exact liveOwnedValue_preserves_reference_structure result.state.heap original.owner original.value
      (holdingsTyped original originalMember) child member
  split at accepted <;> try contradiction
  rename_i departed resultValue resultControl
  have resultValueTyped : ValueStructure schemas resultValue.value := by
    apply resultTyped
    simp [ValueInventory.state, resultControl, ValueInventory.control, ValueInventory.afterRelease]
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨parentRecord, parentFound, store, movedOk, rfl⟩ := accepted
  have parentTyped := ValueInventory.scope_holdings_preserve_all result.state parent parentRecord parentFound _ resultTyped
  have movedTyped := ValueInventory.moveValues_preserves_all _ _ _ _ movedOk _ resultTyped
  have inheritedTyped : ∀ child ∈ (record.holdings.flatMap (liveOwned result.state.heap)).mapIdx
      (fun index located => retainAt located (.temporary parent (parentRecord.nextOwner + index))),
      ValueStructure schemas child.value := by
    intro child member
    simp only [List.mapIdx_eq_zipIdx_map, List.mem_map] at member
    obtain ⟨⟨original, index⟩, originalMember, rfl⟩ := member
    exact remainingTyped original (List.fst_mem_of_mem_zipIdx originalMember)
  simp only [ValueInventory.All, ValueInventory.state, ValueInventory.heap, ValueInventory.control,
    List.mem_append, List.mem_flatMap, List.mem_map, List.mem_singleton] at movedTyped ⊢
  grind only [→ List.mem_or_eq_of_mem_set, List.mem_append]

theorem liveOwned_holdings_preserve_reference_structure (store : Heap) (holdings : List Located)
    (typed : ∀ value ∈ holdings, ValueStructure schemas value.value) :
    ∀ child ∈ holdings.flatMap (liveOwned store), ValueStructure schemas child.value := by
  intro child member
  obtain ⟨original, originalMember, childMember⟩ := List.mem_flatMap.mp member
  exact liveOwnedValue_preserves_reference_structure store original.owner original.value
    (typed original originalMember) child childMember

theorem releaseScope_preserves_reference_structure (machine : State) (after : Transition)
    (accepted : releaseScope machine = .ok after)
    (typed : ValueInventory.All (ValueStructure schemas) machine) :
    ValueInventory.All (ValueStructure schemas) after.state := by
  unfold releaseScope at accepted
  split at accepted <;> try contradiction
  rename_i scope released releasing
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨record, recordFound, _, _, rfl⟩ := accepted
  have holdingTypes := ValueInventory.scope_holdings_preserve_all machine scope record recordFound _ typed
  have liveTypes := liveOwned_holdings_preserve_reference_structure machine.heap record.holdings holdingTypes
  simp only [ValueInventory.All, ValueInventory.state, releasing, ValueInventory.control,
    List.mem_append, List.mem_map] at typed ⊢
  grind only []

theorem discardValues_preserves_reference_structure (machine : State) (context : Context) (after : Transition)
    (accepted : discardValues machine context = .ok after)
    (typed : ValueInventory.All (ValueStructure schemas) machine) :
    ValueInventory.All (ValueStructure schemas) after.state := by
  unfold discardValues at accepted
  split at accepted <;> try contradiction
  rename_i values released discarding
  have releasesTyped : ∀ value ∈ ValueInventory.afterRelease released, ValueStructure schemas value := by
    intro value member
    apply typed
    simp [ValueInventory.state, discarding, ValueInventory.control, member]
  cases values with
  | nil =>
    cases accepted
    exact ValueInventory.resumeRelease_preserves_all machine released _ typed releasesTyped
  | cons value rest =>
    simp only at accepted
    have restTyped : ∀ child ∈ rest, ValueStructure schemas child.value := by
      intro child member
      apply typed
      simp only [ValueInventory.state, discarding, ValueInventory.control, List.map_cons, List.mem_append,
        List.mem_cons, List.mem_map]
      grind only []
    split at accepted
    · cases accepted
      simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, List.mem_append, List.mem_map] at typed ⊢
      grind only []
    · simp only [bind, except_bind_ok] at accepted
      obtain ⟨⟨node, stored⟩, lookup, accepted⟩ := accepted
      have storedTypes := ValueInventory.lookupObject_preserves_all machine value node stored lookup _ typed
      cases stored <;> simp only at accepted <;> try contradiction
      case oneShot saved =>
        simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨store, retired, rfl⟩ := accepted
        have storeTyped := ValueInventory.retireObject_preserves_all machine value store retired _ typed
        cases released <;> simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control,
          ValueInventory.object, ValueInventory.capture, ValueInventory.frame, ValueInventory.afterRelease,
          exitValues, List.mem_append, List.mem_map, List.flatMap_append, List.flatMap_cons, List.flatMap_nil,
          List.append_nil, List.mem_cons, List.not_mem_nil] at storeTyped storedTypes releasesTyped ⊢
        all_goals grind only []
      case closure schema function bindings =>
        simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨store, retired, rfl⟩ := accepted
        have storeTyped := ValueInventory.retireObject_preserves_all machine value store retired _ typed
        have childrenTyped : ∀ child ∈ bindings.flatMap (fun binding => liveOwned store binding.located),
            ValueStructure schemas child.value := by
          intro child member
          obtain ⟨binding, bindingMember, childMember⟩ := List.mem_flatMap.mp member
          have bindingTyped := storedTypes binding.located.value (List.mem_map.mpr ⟨binding, bindingMember, rfl⟩)
          exact liveOwnedValue_preserves_reference_structure store binding.located.owner binding.located.value bindingTyped child childMember
        simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, List.map_append,
          List.mem_append, List.mem_map] at storeTyped ⊢
        grind only []
      case package schema content =>
        simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨store, retired, rfl⟩ := accepted
        have storeTyped := ValueInventory.retireObject_preserves_all machine value store retired _ typed
        have childrenTyped := liveOwnedValue_preserves_reference_structure store content.owner content.value
          (storedTypes content.value (by simp [ValueInventory.object]))
        change ∀ child ∈ liveOwned store content, ValueStructure schemas child.value at childrenTyped
        simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, List.map_append,
          List.mem_append, List.mem_map] at storeTyped ⊢
        grind only []
      case resource schema content =>
        simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨store, retired, rfl⟩ := accepted
        have storeTyped := ValueInventory.retireObject_preserves_all machine value store retired _ typed
        simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control,
          List.mem_append, List.mem_map] at storeTyped ⊢
        grind only []

end ReferenceStructureContracts
end BoundaryV2.Profile.Source.Machine
