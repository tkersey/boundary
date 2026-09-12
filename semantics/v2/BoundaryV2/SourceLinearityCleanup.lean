import BoundaryV2.SourceLinearityEffects

namespace BoundaryV2.Profile.Source.Machine
namespace ValueLinearity

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

theorem leaveLexical_preserves_linearity (machine : State) (after : Transition)
    (accepted : leaveLexical machine = .ok after)
    (typed : ValueInventory.All (Linear) machine) :
    ValueInventory.All (Linear) after.state := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  rename_i value delivered
  split at accepted <;> try contradiction
  rename_i scope tail stacked
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, record, recordFound, parent, _, result, leftOk, accepted⟩ := accepted
  have valueTyped : Linear value.value := by
    apply typed
    simp [ValueInventory.state, delivered, ValueInventory.control]
  have tailTyped : ∀ child ∈ tail.flatMap ValueInventory.frame, Linear child := by
    intro child member
    apply typed
    simp [ValueInventory.state, stacked, ValueInventory.frame, member]
  have resultTyped := ValueInventory.leaveScope_preserves_all machine parent machine.invocation tail value result
    leftOk _ typed tailTyped valueTyped
  have holdingsTyped := ValueInventory.scope_holdings_preserve_all machine scope record recordFound _ typed
  have remainingTyped : ∀ child ∈ record.holdings.flatMap (liveOwned result.state.heap), Linear child.value := by
    intro child member
    obtain ⟨original, originalMember, member⟩ := List.mem_flatMap.mp member
    exact liveOwnedValue_preserves result.state.heap original.owner original.value
      (holdingsTyped original originalMember) child member
  split at accepted <;> try contradiction
  rename_i departed resultValue resultControl
  have resultValueTyped : Linear resultValue.value := by
    apply resultTyped
    simp [ValueInventory.state, resultControl, ValueInventory.control, ValueInventory.afterRelease]
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨parentRecord, parentFound, store, movedOk, rfl⟩ := accepted
  have parentTyped := ValueInventory.scope_holdings_preserve_all result.state parent parentRecord parentFound _ resultTyped
  have movedTyped := ValueInventory.moveValues_preserves_all _ _ _ _ movedOk _ resultTyped
  have inheritedTyped : ∀ child ∈ (record.holdings.flatMap (liveOwned result.state.heap)).mapIdx
      (fun index located => retainAt located (.temporary parent (parentRecord.nextOwner + index))),
      Linear child.value := by
    intro child member
    simp only [List.mapIdx_eq_zipIdx_map, List.mem_map] at member
    obtain ⟨⟨original, index⟩, originalMember, rfl⟩ := member
    exact remainingTyped original (List.fst_mem_of_mem_zipIdx originalMember)
  simp only [ValueInventory.All, ValueInventory.state, ValueInventory.heap, ValueInventory.control,
    List.mem_append, List.mem_flatMap, List.mem_map, List.mem_singleton] at movedTyped ⊢
  grind only [→ List.mem_or_eq_of_mem_set, List.mem_append]

theorem liveOwned_holdings_preserve_linearity (store : Heap) (holdings : List Located)
    (typed : ∀ value ∈ holdings, Linear value.value) :
    ∀ child ∈ holdings.flatMap (liveOwned store), Linear child.value := by
  intro child member
  obtain ⟨original, originalMember, childMember⟩ := List.mem_flatMap.mp member
  exact liveOwnedValue_preserves store original.owner original.value
    (typed original originalMember) child childMember

theorem releaseScope_preserves_linearity (machine : State) (after : Transition)
    (accepted : releaseScope machine = .ok after)
    (typed : ValueInventory.All (Linear) machine) :
    ValueInventory.All (Linear) after.state := by
  unfold releaseScope at accepted
  split at accepted <;> try contradiction
  rename_i scope released releasing
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨record, recordFound, _, _, rfl⟩ := accepted
  have holdingTypes := ValueInventory.scope_holdings_preserve_all machine scope record recordFound _ typed
  have liveTypes := liveOwned_holdings_preserve_linearity machine.heap record.holdings holdingTypes
  simp only [ValueInventory.All, ValueInventory.state, releasing, ValueInventory.control,
    List.mem_append, List.mem_map] at typed ⊢
  grind only []

theorem discardValues_preserves_linearity (machine : State) (context : Context) (after : Transition)
    (accepted : discardValues machine context = .ok after)
    (typed : ValueInventory.All (Linear) machine) :
    ValueInventory.All (Linear) after.state := by
  unfold discardValues at accepted
  split at accepted <;> try contradiction
  rename_i values released discarding
  have releasesTyped : ∀ value ∈ ValueInventory.afterRelease released, Linear value := by
    intro value member
    apply typed
    simp [ValueInventory.state, discarding, ValueInventory.control, member]
  cases values with
  | nil =>
    cases accepted
    exact ValueInventory.resumeRelease_preserves_all machine released _ typed releasesTyped
  | cons value rest =>
    simp only at accepted
    have restTyped : ∀ child ∈ rest, Linear child.value := by
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
            Linear child.value := by
          intro child member
          obtain ⟨binding, bindingMember, childMember⟩ := List.mem_flatMap.mp member
          have bindingTyped := storedTypes binding.located.value (List.mem_map.mpr ⟨binding, bindingMember, rfl⟩)
          exact liveOwnedValue_preserves store binding.located.owner binding.located.value bindingTyped child childMember
        simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, List.map_append,
          List.mem_append, List.mem_map] at storeTyped ⊢
        grind only []
      case package schema content =>
        simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨store, retired, rfl⟩ := accepted
        have storeTyped := ValueInventory.retireObject_preserves_all machine value store retired _ typed
        have childrenTyped := liveOwnedValue_preserves store content.owner content.value
          (storedTypes content.value (by simp [ValueInventory.object]))
        change ∀ child ∈ liveOwned store content, Linear child.value at childrenTyped
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

theorem cleanupFailed_preserves_linearity (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : cleanupFailed machine identity invocation outer normal tail inner = .ok after)
    (typed : ValueInventory.All (Linear) machine)
    (outerTyped : ∀ value ∈ exitValues outer, Linear value)
    (innerTyped : ∀ value ∈ exitValues inner, Linear value)
    (normalTyped : ∀ value ∈ normal, Linear value.value)
    (tailTyped : ∀ value ∈ tail.flatMap ValueInventory.frame, Linear value) :
    ValueInventory.All (Linear) after.state := by
  unfold cleanupFailed at accepted
  split at accepted <;> try contradiction
  rename_i failure failed
  have failureTyped : Linear failure := innerTyped failure (by simp [exitValues, failed])
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨before, found, ⟨afterRecord, events⟩, completed, rfl⟩ := accepted
  have beforeTyped := ValueInventory.lookup_obligation_preserves_all machine identity before found _ typed
  have recordTyped := ValueInventory.complete_obligation_preserves_all before afterRecord invocation (.error failure) events completed _ beforeTyped
    (by intro value equal; cases equal; exact failureTyped)
  have heapTyped := ValueInventory.set_obligation_preserves_all machine identity.value afterRecord _ typed recordTyped
  have remainingTyped := liveOwned_holdings_preserve_linearity
    { machine.heap with obligations := machine.heap.obligations.set identity.value afterRecord } normal.toList
    (by simpa using normalTyped)
  have exitTyped : ∀ value ∈ exitValues (mergeAbrupt outer inner), Linear value := by
    intro value member
    rcases List.mem_append.mp (ValueInventory.merge_abrupt_subset outer inner member) with member | member
    · exact outerTyped value member
    · exact innerTyped value member
  simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.afterRelease,
    List.mem_append, List.mem_map] at heapTyped ⊢
  grind only []

theorem finishDisposal_preserves_linearity (machine : State) (after : Transition)
    (accepted : finishDisposal machine = .ok after)
    (typed : ValueInventory.All (Linear) machine) :
    ValueInventory.All (Linear) after.state := by
  unfold finishDisposal at accepted
  split at accepted <;> try contradiction
  rename_i value executing
  split at accepted <;> try contradiction
  rename_i remaining release invocation scope tail stacked
  have valueTyped : Linear value.value := by
    apply typed
    simp [ValueInventory.state, executing, ValueInventory.control]
  have ownedTyped := liveOwnedValue_preserves machine.heap value.owner value.value valueTyped
  cases accepted
  simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.frame,
    executing, stacked, List.flatMap_cons, List.mem_append, List.map_append, List.mem_map,
    List.mem_cons, List.not_mem_nil] at typed ⊢
  grind only [liveOwned]

theorem cleanupAbandoned_preserves_linearity (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : cleanupAbandoned machine identity invocation outer normal tail inner = .ok after)
    (typed : ValueInventory.All (Linear) machine)
    (outerTyped : ∀ value ∈ exitValues outer, Linear value)
    (innerTyped : ∀ value ∈ exitValues inner, Linear value)
    (normalTyped : ∀ value ∈ normal, Linear value.value)
    (tailTyped : ∀ value ∈ tail.flatMap ValueInventory.frame, Linear value) :
    ValueInventory.All (Linear) after.state := by
  simp only [cleanupAbandoned, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, guard, before, found, ⟨afterRecord, events⟩, completed, rfl⟩ := accepted
  clear guard
  have beforeTyped := ValueInventory.lookup_obligation_preserves_all machine identity before found _ typed
  have recordTyped := ValueInventory.complete_obligation_preserves_all before afterRecord invocation (.ok ()) events completed _ beforeTyped
    (by intro value equal; cases equal)
  have heapTyped := ValueInventory.set_obligation_preserves_all machine identity.value afterRecord _ typed recordTyped
  have remainingTyped := liveOwned_holdings_preserve_linearity
    { machine.heap with obligations := machine.heap.obligations.set identity.value afterRecord } normal.toList
    (by simpa using normalTyped)
  have exitTyped : ∀ value ∈ exitValues (propagateExit outer inner), Linear value := by
    intro value member
    rcases List.mem_append.mp (ValueInventory.propagate_exit_subset outer inner member) with member | member
    · exact outerTyped value member
    · exact innerTyped value member
  simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.afterRelease,
    List.mem_append, List.mem_map] at heapTyped ⊢
  grind only []

theorem finishCleanupUnwind_preserves_linearity (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : finishCleanupUnwind machine identity invocation outer normal tail inner = .ok after)
    (typed : ValueInventory.All (Linear) machine)
    (outerTyped : ∀ value ∈ exitValues outer, Linear value)
    (innerTyped : ∀ value ∈ exitValues inner, Linear value)
    (normalTyped : ∀ value ∈ normal, Linear value.value)
    (tailTyped : ∀ value ∈ tail.flatMap ValueInventory.frame, Linear value) :
    ValueInventory.All (Linear) after.state := by
  unfold finishCleanupUnwind at accepted
  split at accepted <;> first
    | exact cleanupFailed_preserves_linearity _ _ _ _ _ _ _ _ accepted typed outerTyped innerTyped normalTyped tailTyped
    | exact cleanupAbandoned_preserves_linearity _ _ _ _ _ _ _ _ accepted typed outerTyped innerTyped normalTyped tailTyped
    | contradiction

theorem installProtection_preserves_linearity (machine : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (accepted : installProtection machine context body cleanup arguments resource loan = .ok after)
    (typed : ValueInventory.All (Linear) machine)
    (cleanupTyped : Linear cleanup.value)
    (argumentsTyped : ∀ value ∈ arguments, Linear value.value)
    (resourceTyped : ∀ value ∈ resource, Linear value.value) :
    ValueInventory.All (Linear) after.state := by
  simp only [installProtection, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨bodyType, _, _, _, _, _, _, _, _, _, store, moved, accepted⟩ := accepted
  have movedTyped := ValueInventory.moveValues_preserves_all machine store _ _ moved _ typed
  let record : Cleanup.Obligation .source := ⟨⟨machine.heap.nextObligation⟩, machine.scope, machine.heap.nextObligation,
    cleanup.value, resource.map Located.value, .pending⟩
  let heap := { store with obligations := store.obligations ++ [record], nextObligation := store.nextObligation + 1 }
  have recordTyped : ∀ value ∈ ValueInventory.obligation record, Linear value := by
    simp only [record, ValueInventory.obligation, List.mem_cons, List.mem_append, List.not_mem_nil, or_false]
    intro value member
    rcases member with equal | member
    · cases equal; exact cleanupTyped
    · have found : resource.map Located.value = some value := by simpa using member
      obtain ⟨original, originalMember, rfl⟩ := Option.map_eq_some_iff.mp found
      exact resourceTyped original originalMember
  have heapTyped : ValueInventory.All (Linear) { machine with heap := heap } := by
    simp only [heap, ValueInventory.All, ValueInventory.state, ValueInventory.heap,
      List.flatMap_append, List.flatMap_cons, List.flatMap_nil, List.append_nil, List.mem_append] at movedTyped ⊢
    grind only []
  cases resource with
  | none =>
    cases loan <;> try contradiction
    simp only [pure, Except.pure, Except.bind] at accepted
    apply ValueInventory.applyClosure_preserves_all _ _ _ _ _ accepted _ _ argumentsTyped
    simpa only [ValueInventory.All, ValueInventory.state, List.singleton_append, List.flatMap_cons,
      ValueInventory.frame, List.nil_append] using heapTyped
  | some resourceValue =>
    cases loan with
    | none => contradiction
    | some descriptor =>
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      rename_i schema node token valueAt
      simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨borrowSchema, _, _, checked, ⟨afterStore, borrowed⟩, allocated, _, rfl, applied⟩ := accepted
      have shape : context.source.schemas[borrowSchema.value]? = some (.internal (.borrowed resourceValue.value.schema descriptor)) := by
        unfold require at checked
        split at checked <;> try contradiction
        rename_i admitted
        simpa using admitted
      have allocatedTyped := ValueInventory.allocateObject_preserves_all
        { machine with heap := { heap with nextRegion := heap.nextRegion + 1, loans := heap.loans ++ [(⟨heap.nextRegion⟩, ⟨machine.heap.nextObligation⟩)] } }
        afterStore borrowSchema _ _ false borrowed allocated _ heapTyped (by simp [ValueInventory.object])
      have borrowedTyped : Linear borrowed.value := by
        rw [ValueInventory.allocateObject_result _ _ _ _ _ _ _ allocated]
        simp [Linear, ownedTokens]
      refine ValueInventory.applyClosure_preserves_all _ _ _ _ _ applied (Linear) ?_ ?_
      · simpa only [ValueInventory.All, ValueInventory.state, List.cons_append, List.nil_append,
          List.flatMap_cons, ValueInventory.frame] using allocatedTyped
      · intro child member
        rcases List.mem_cons.mp member with equal | member
        · cases equal; exact borrowedTyped
        · exact argumentsTyped child member

theorem executeCleanupTerm_preserves_linearity (machine : State) (context : Context) (after : Transition)
    (accepted : executeCleanupTerm machine context = .ok after)
    (typed : ValueInventory.All (Linear) machine) :
    ValueInventory.All (Linear) after.state := by
  unfold executeCleanupTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  have inputs : ∀ value ∈ operands, Linear value.value := by
    intro value member
    apply typed
    simp only [ValueInventory.state, executing, ValueInventory.control, List.mem_append, List.mem_map]
    grind only []
  cases term <;> simp only at accepted <;> try contradiction
  case protect body cleanup arguments resource loan =>
    split at accepted <;> try contradiction
    rename_i bodyValue cleanupValue rest operandsEqual
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    refine installProtection_preserves_linearity _ _ _ _ _ _ _ _ accepted typed (inputs cleanupValue (by simp)) ?_ ?_
    · intro value member
      exact inputs value (by simp [List.mem_of_mem_take member])
    · intro value member
      exact inputs value (by simp [List.mem_of_getElem? member])
  case dispose token =>
    split at accepted <;> try contradiction
    rename_i value operandsEqual
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨shape, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, index, found, ⟨middle, owner⟩, temporaryOk, rfl⟩ := accepted
    obtain ⟨bound, isUnit, _⟩ := List.findIdx?_eq_some_iff_getElem.mp found
    have unitShape : context.source.schemas[index]? = some .unit := by
      rw [List.getElem?_eq_getElem bound]
      congr 1
      simpa using isUnit
    have unitTyped : Linear (.scalar ⟨index⟩ 0) := by simp [Linear, ownedTokens]
    have valueTyped := inputs value (by simp)
    have middleTyped := ValueInventory.temporary_preserves_all _ _ _ temporaryOk _ typed
    simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.afterRelease,
      List.map_cons, List.map_nil, List.mem_append, List.mem_singleton] at middleTyped ⊢
    grind only []

theorem beginCleanup_preserves_linearity (machine : State) (context : Context) (identity : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (accepted : beginCleanup machine context identity exit normal tail = .ok after)
    (exitFree : ExitFree exit)
    (typed : ValueInventory.All (Linear) machine)
    (exitTyped : ∀ value ∈ exitValues exit, Linear value)
    (normalTyped : ∀ value ∈ normal, Linear value.value)
    (tailTyped : ∀ value ∈ tail.flatMap ValueInventory.frame, Linear value) : ValueInventory.All (Linear) after.state := by
  simp only [beginCleanup, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨before, found, _, _, ⟨record, events⟩, begun, signature, _, infoType, _, information, informationAt, result, applied, rfl⟩ := accepted
  have beforeTyped := ValueInventory.lookup_obligation_preserves_all machine identity before found _ typed
  have recordTyped := ValueInventory.begin_obligation_preserves_all before record _ events begun _ beforeTyped
  have heapTyped := ValueInventory.set_obligation_preserves_all machine identity.value record _ typed recordTyped
  have observedTyped : ∀ value ∈ exitValues (observedExit machine exit), Linear value :=
    fun value member => exitTyped value (ValueInventory.observed_exit_subset machine exit member)
  have observedFree := observed_exit_free machine exit exitFree
  have informationTyped : Linear information := by
    simp only [Linear, cleanupInformation_token_free _ _ _ _ informationAt observedFree.1 observedFree.2]
    exact List.nodup_nil
  have normalListTyped : ∀ value ∈ normal.toList, Linear value.value := by simpa using normalTyped
  apply ValueInventory.applyClosure_preserves_all _ _ _ _ _ applied (Linear)
  · simp only [ValueInventory.All, ValueInventory.state, List.flatMap_cons, ValueInventory.frame,
      List.mem_append, List.mem_map] at heapTyped ⊢
    grind only []
  · intro value member
    rcases List.mem_cons.mp member with equal | member
    · cases equal; exact informationTyped
    · obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
      exact recordTyped original (by simp only [ValueInventory.obligation, List.mem_cons, List.mem_append]; exact Or.inl (Or.inr originalMember))

end ValueLinearity
end BoundaryV2.Profile.Source.Machine
