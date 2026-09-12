import BoundaryV2.SourceOwnerLocationEffects

namespace BoundaryV2.Profile.Source.Machine
namespace OwnerLocations

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem installProtection_valid (machine : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (accepted : installProtection machine context body cleanup arguments resource loan = .ok after)
    (valid : Valid machine) : Valid after.state := by
  simp only [installProtection, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, store, moved, accepted⟩ := accepted
  let identity : ObligationId := ⟨machine.heap.nextObligation⟩
  let record : Cleanup.Obligation .source := ⟨identity, machine.scope, identity.value,
    cleanup.value, resource.map Located.value, .pending⟩
  let kept := {store with obligations := store.obligations ++ [record], nextObligation := store.nextObligation + 1}
  have next := same_storage {machine with heap := store} kept (move_valid _ _ _ _ moved valid) rfl rfl
  cases resource with
  | none =>
    cases loan <;> try contradiction
    simp only [pure, Except.pure, Except.bind] at accepted
    apply applyClosure_valid _ _ _ _ _ accepted
    simpa only [Valid, Normal, Pending, ordinaryValues, queuedValues, List.flatMap_append, List.flatMap_cons,
      List.flatMap_nil, frameValues, DisposalShape.frame, List.nil_append] using next
  | some value =>
    cases loan with
    | none => contradiction
    | some descriptor =>
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, ⟨afterStore, borrowed⟩, allocated, _, rfl, applied⟩ := accepted
      have seed := same_storage {machine with heap := kept}
        {kept with nextRegion := kept.nextRegion + 1, loans := kept.loans ++ [(⟨kept.nextRegion⟩, identity)]} next rfl rfl
      have created := allocation_valid _ _ _ _ _ _ _ allocated seed (by simp [ObjectValid, objectValues, DisposalShape.object])
      apply applyClosure_valid _ _ _ _ _ applied
      simpa only [Valid, Normal, Pending, ordinaryValues, queuedValues, List.flatMap_append, List.flatMap_cons,
        List.flatMap_nil, frameValues, DisposalShape.frame, List.nil_append] using created

theorem beginCleanup_valid (machine : State) (context : Context) (id : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (accepted : beginCleanup machine context id exit normal tail = .ok after) (valid : Valid machine)
    (ordinary : ∀ value ∈ normal.toList, Ordinary value)
    (included : ∀ frame ∈ tail, frame ∈ machine.stack) : Valid after.state := by
  simp only [beginCleanup, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, ⟨record, events⟩, _, _, _, _, _, _, _, result, applied, rfl⟩ := accepted
  have tailValid := tail_valid machine tail valid included
  have stored := same_storage {machine with stack := tail}
    {machine.heap with obligations := machine.heap.obligations.set id.value record} tailValid rfl rfl
  have stacked := with_stack _ (.cleanupReturn id ⟨machine.heap.nextInvocation⟩ (observedExit machine exit) normal :: tail) stored
    (by
      have prior := normal_stack _ stored.1
      simp only [List.flatMap_cons, frameValues, List.mem_append]
      grind only [])
    (by simpa only [List.flatMap_cons, DisposalShape.frame, List.nil_append] using pending_stack _ stored.2)
  exact applyClosure_valid _ _ _ _ result applied stacked

theorem exitAfter_ordinary (exit : Cleanup.Exit .source) (normal : Option Located) (after : AfterRelease)
    (accepted : exitAfter exit normal = .ok after) (ordinary : ∀ value ∈ normal.toList, Ordinary value) :
    ∀ value ∈ afterValues after, Ordinary value := by
  unfold exitAfter at accepted
  split at accepted
  · simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨value, found, _, _, rfl⟩ := accepted
    simpa only [afterValues, List.mem_singleton, forall_eq] using ordinary value (by simp [found])
  · cases accepted; simp [afterValues]

theorem resumeRelease_valid (machine : State) (after : AfterRelease) (valid : Valid machine)
    (ordinary : ∀ value ∈ afterValues after, Ordinary value) : Valid (resumeRelease machine after).state := by
  cases after <;> exact with_control _ _ valid ordinary (by simp [DisposalShape.control])

theorem finishCleanup_valid (machine : State) (context : Context) (after : Transition)
    (accepted : finishCleanup machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold finishCleanup at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i id invocation exit normal tail stacked
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, ⟨record, events⟩, _, released, releasedAt, rfl⟩ := accepted
  have ordinary := normal_frame machine (.cleanupReturn id invocation exit normal) (by simp [stacked]) valid.1
  have next := tail_valid machine tail valid (by intro frame member; simp [stacked, member])
  have stored := same_storage {machine with stack := tail}
    {machine.heap with obligations := machine.heap.obligations.set id.value record} next rfl rfl
  exact resumeRelease_valid _ _ stored (exitAfter_ordinary _ _ _ releasedAt ordinary)

theorem cleanupFailed_valid (machine : State) (id : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : cleanupFailed machine id invocation outer normal tail inner = .ok after) (valid : Valid machine)
    (ordinary : ∀ value ∈ normal.toList, Ordinary value)
    (included : ∀ frame ∈ tail, frame ∈ machine.stack) : Valid after.state := by
  unfold cleanupFailed at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, ⟨record, events⟩, _, rfl⟩ := accepted
  let heap := {machine.heap with obligations := machine.heap.obligations.set id.value record}
  have next := same_storage {machine with stack := tail} heap (tail_valid machine tail valid included) rfl rfl
  apply with_control _ (.discard (normal.toList.flatMap (liveOwned heap)) (.unwind (mergeAbrupt outer inner))) next
  · simp [controlValues, afterValues]
  · intro value member
    obtain ⟨original, originalAt, valueAt⟩ := List.mem_flatMap.mp member
    exact Or.inl (ordinary_liveOwned heap original (ordinary original originalAt) value valueAt)

theorem cleanupAbandoned_valid (machine : State) (id : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : cleanupAbandoned machine id invocation outer normal tail inner = .ok after) (valid : Valid machine)
    (ordinary : ∀ value ∈ normal.toList, Ordinary value)
    (included : ∀ frame ∈ tail, frame ∈ machine.stack) : Valid after.state := by
  simp only [cleanupAbandoned, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, ⟨record, events⟩, _, rfl⟩ := accepted
  let heap := {machine.heap with obligations := machine.heap.obligations.set id.value record}
  have next := same_storage {machine with stack := tail} heap (tail_valid machine tail valid included) rfl rfl
  apply with_control _ (.discard (normal.toList.flatMap (liveOwned heap)) (.unwind (propagateExit outer inner))) next
  · simp [controlValues, afterValues]
  · intro value member
    obtain ⟨original, originalAt, valueAt⟩ := List.mem_flatMap.mp member
    exact Or.inl (ordinary_liveOwned heap original (ordinary original originalAt) value valueAt)

theorem finishCleanupUnwind_valid (machine : State) (id : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : finishCleanupUnwind machine id invocation outer normal tail inner = .ok after) (valid : Valid machine)
    (ordinary : ∀ value ∈ normal.toList, Ordinary value)
    (included : ∀ frame ∈ tail, frame ∈ machine.stack) : Valid after.state := by
  unfold finishCleanupUnwind at accepted
  split at accepted <;> first
    | exact cleanupFailed_valid _ _ _ _ _ _ _ _ accepted valid ordinary included
    | exact cleanupAbandoned_valid _ _ _ _ _ _ _ _ accepted valid ordinary included
    | contradiction

theorem unwindStep_valid (machine : State) (context : Context) (after : Transition)
    (original : Cleanup.Exit .source) (unwinding : machine.control = .unwind original)
    (accepted : unwindStep machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [unwindStep, unwinding, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨scope, scopeAt, accepted⟩ := accepted
  have holdings := (heap_valid machine valid).2 scope (List.mem_of_getElem? scopeAt)
  have pendingValid : Valid {machine with control := .discard (scope.holdings.flatMap (liveOwned machine.heap)) (.unwind (observedExit machine original))} := by
    apply with_control _ _ valid
    · simp [controlValues, afterValues]
    · intro value member
      obtain ⟨original, originalAt, valueAt⟩ := List.mem_flatMap.mp member
      exact Or.inl (ordinary_liveOwned machine.heap original (holdings original originalAt) value valueAt)
  cases stacked : machine.stack with
  | nil =>
    simp only [stacked] at accepted
    split at accepted
    · cases accepted
      simpa only [Valid, Normal, Pending, ordinaryValues, queuedValues, stacked] using pendingValid
    · split at accepted <;> try contradiction
      all_goals cases accepted
      all_goals simpa only [Valid, Normal, Pending, ordinaryValues, queuedValues, statusValues, unwinding, stacked] using
        with_status machine (.failed (observedExit machine original)) valid (by simp [statusValues])
  | cons saved tail =>
    have frameNormal := normal_frame machine saved (by simp [stacked]) valid.1
    have frameQueued := pending_frame machine saved (by simp [stacked]) valid.2
    have included : ∀ frame ∈ tail, frame ∈ machine.stack := by intro frame member; simp [stacked, member]
    have tailValid := tail_valid machine tail valid included
    cases saved <;> simp only [stacked] at accepted
    case invocation invocation parent =>
      split at accepted
      · cases accepted
        simpa only [Valid, Normal, Pending, ordinaryValues, queuedValues, stacked] using pendingValid
      · cases accepted
        simpa only [Valid, Normal, Pending, ordinaryValues, queuedValues, unwinding] using tailValid
    case lexical identity =>
      split at accepted
      · cases accepted
        simpa only [Valid, Normal, Pending, ordinaryValues, queuedValues, stacked] using pendingValid
      · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨_, _, parent, _, rfl⟩ := accepted
        simpa only [Valid, Normal, Pending, ordinaryValues, queuedValues, unwinding] using tailValid
    case restore invocation parent =>
      cases accepted
      simpa only [Valid, Normal, Pending, ordinaryValues, queuedValues, unwinding] using tailValid
    case binding binder body bindings parent =>
      cases accepted
      simpa only [Valid, Normal, Pending, ordinaryValues, queuedValues, unwinding] using tailValid
    case operands intent bindings remaining evaluated =>
      cases accepted
      simpa only [Valid, Normal, Pending, ordinaryValues, queuedValues, unwinding] using tailValid
    case handler active =>
      cases accepted
      simpa only [Valid, Normal, Pending, ordinaryValues, queuedValues, unwinding] using tailValid
    case region region =>
      cases accepted
      simpa only [Valid, Normal, Pending, ordinaryValues, queuedValues, unwinding] using tailValid
    case injection values =>
      cases accepted
      simpa only [Valid, Normal, Pending, ordinaryValues, queuedValues, unwinding] using tailValid
    case protection identity =>
      exact beginCleanup_valid _ _ _ _ _ _ _ accepted valid (by simp) included
    case cleanupReturn identity invocation outer normal =>
      exact finishCleanupUnwind_valid _ _ _ _ _ _ _ _ accepted valid frameNormal included
    case releaseReturn scope afterRelease =>
      cases accepted
      exact with_control _ (.unwind _) tailValid (by simp [controlValues]) (by simp [DisposalShape.control])
    case disposalReturn remaining afterRelease invocation parent =>
      cases primaryIs : (observedExit machine original).primary <;> simp only [primaryIs] at accepted
      all_goals cases afterRelease <;> simp only [pure, Except.pure, Except.bind] at accepted
      all_goals cases accepted
      all_goals apply with_control _ _ tailValid
      all_goals first | exact frameQueued | exact frameNormal | simp [controlValues, afterValues]

theorem executeCleanupTerm_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executeCleanupTerm machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold executeCleanupTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  have ordinary : ∀ value ∈ operands, Ordinary value := by
    intro value member
    exact normal_control machine valid.1 value (by simp only [executing, controlValues, List.mem_append]; exact Or.inr member)
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact installProtection_valid _ _ _ _ _ _ _ _ accepted valid
  · split at accepted <;> try contradiction
    rename_i value operandsAt
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, unitIndex, _, ⟨middle, owner⟩, reserved, rfl⟩ := accepted
    have next := temporary_valid _ _ _ reserved valid
    apply with_control _ (.discard [value] (.deliver ⟨.scalar ⟨unitIndex⟩ 0, owner⟩)) next.1
    · intro child member
      cases List.mem_singleton.mp member
      exact Or.inl next.2
    · intro child member
      cases List.mem_singleton.mp member
      exact Or.inl (ordinary value (by simp))

end OwnerLocations
end BoundaryV2.Profile.Source.Machine
