import BoundaryV2.SourceQueueEffects

namespace BoundaryV2.Profile.Source.Machine
namespace QueueCustody

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

private theorem flatMap_sublist (before after : List α) (f : α → List β) (included : after.Sublist before) :
    (after.flatMap f).Sublist (before.flatMap f) := by
  induction included with
  | slnil => exact .slnil
  | cons value included ih => exact ih.trans (List.sublist_append_right (f value) _)
  | cons_cons value included ih => exact ih.append_left _

theorem same_objects_retired (machine : State) (heap : Heap)
    (same : heap.objects = machine.heap.objects)
    (retired : ∀ pinned ∈ fields machine, OwnerLocations.Retired machine.heap pinned.owner) :
    ∀ pinned ∈ fields {machine with heap := heap}, OwnerLocations.Retired heap pinned.owner := by
  simpa only [fields_components, heapFields, OwnerLocations.Retired, Heap.lookup, same] using retired

theorem installProtection_valid (machine : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (accepted : installProtection machine context body cleanup arguments resource loan = .ok after) (valid : Valid machine)
    (bodyOrdinary : OwnerLocations.Ordinary body) (cleanupOrdinary : OwnerLocations.Ordinary cleanup)
    (ordinary : ∀ value ∈ arguments, OwnerLocations.Ordinary value)
    (resourceOrdinary : ∀ value ∈ resource.toList, OwnerLocations.Ordinary value)
    (retired : ∀ pinned ∈ fields machine, OwnerLocations.Retired machine.heap pinned.owner)
    (objects : ObjectOwners.Valid machine.heap) : Valid after.state := by
  simp only [installProtection, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, store, moved, accepted⟩ := accepted
  let identity : ObligationId := ⟨machine.heap.nextObligation⟩
  let record : Cleanup.Obligation .source := ⟨identity, machine.scope, identity.value,
    cleanup.value, resource.map Located.value, .pending⟩
  let kept := {store with obligations := store.obligations ++ [record], nextObligation := store.nextObligation + 1}
  have movedValid := move_ordinary_valid _ _ _ _ moved valid (by
    intro value member
    rcases List.mem_cons.mp member with rfl | member
    · exact cleanupOrdinary
    · exact resourceOrdinary value member)
  have next := same_storage_valid {machine with heap := store} kept movedValid rfl rfl
  have storeSame := ObjectOwners.move_objects _ _ _ _ moved
  have keptRetired := same_objects_retired machine kept storeSame retired
  have keptObjects : ObjectOwners.Valid kept := by
    simpa only [ObjectOwners.Valid, Heap.lookup, kept, storeSame] using objects
  cases resource with
  | none =>
    cases loan <;> try contradiction
    simp only [pure, Except.pure, Except.bind] at accepted
    apply applyClosure_valid _ _ _ _ _ accepted ?_ (ordinary_separate _ _ bodyOrdinary)
      (fun value member => ordinary_separate _ _ (ordinary value member)) ?_ keptObjects
    · exact next
    · exact keptRetired
  | some value =>
    cases loan with
    | none => contradiction
    | some descriptor =>
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, ⟨afterStore, borrowed⟩, allocated, _, rfl, applied⟩ := accepted
      let seedHeap : Heap := {kept with nextRegion := kept.nextRegion + 1, loans := kept.loans ++ [(⟨kept.nextRegion⟩, identity)]}
      have seed := same_storage_valid {machine with heap := kept} seedHeap next rfl rfl
      have created := allocate_empty_valid _ _ _ _ _ _ _ allocated seed rfl
      have createdRetired := allocate_empty_retired {machine with heap := seedHeap} _ _ _ _ _ _ allocated rfl keptRetired
      have createdObjects := ObjectOwners.allocation_valid _ _ _ _ _ _ _ allocated keptObjects (by trivial)
      apply applyClosure_valid _ _ _ _ _ applied ?_ (ordinary_separate _ _ bodyOrdinary) ?_ ?_ createdObjects
      · exact created
      · intro child member
        rcases List.mem_cons.mp member with rfl | member
        · exact ordinary_separate _ _ (Or.inr (allocation_result_nonowning _ _ _ _ _ _ allocated))
        · exact ordinary_separate _ _ (ordinary child member)
      · exact createdRetired

theorem substack_fields_sublist (machine : State) (tail : List Frame) (included : tail.Sublist machine.stack) :
    (fields {machine with stack := tail}).Sublist (fields machine) := by
  simp only [fields_components]
  exact ((flatMap_sublist _ _ frameFields included).append_left _).append_right _

theorem beginCleanup_valid (machine : State) (context : Context) (id : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (accepted : beginCleanup machine context id exit normal tail = .ok after) (valid : Valid machine)
    (included : tail.Sublist machine.stack)
    (retired : ∀ pinned ∈ fields machine, OwnerLocations.Retired machine.heap pinned.owner)
    (objects : ObjectOwners.Valid machine.heap) : Valid after.state := by
  simp only [beginCleanup, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, ⟨record, events⟩, _, _, _, _, _, _, _, result, applied, rfl⟩ := accepted
  have tailValid := substack_valid machine tail valid included
  have stored := same_storage_valid {machine with stack := tail}
    {machine.heap with obligations := machine.heap.obligations.set id.value record} tailValid rfl rfl
  apply applyClosure_valid _ _ _ _ result applied stored (nonclosure_separate _ _ rfl) ?_ ?_ objects
  · intro value member
    rcases List.mem_cons.mp member with rfl | member
    · exact nonclosure_separate _ _ rfl
    · obtain ⟨original, _, rfl⟩ := List.mem_map.mp member
      exact nonclosure_separate _ _ rfl
  · intro pinned member
    exact retired pinned ((substack_fields_sublist machine tail included).subset member)

theorem resumeRelease_valid (machine : State) (after : AfterRelease) (valid : Valid machine) :
    Valid (resumeRelease machine after).state := by
  cases after <;> exact empty_control_valid _ _ valid rfl

theorem finishCleanup_valid (machine : State) (context : Context) (after : Transition)
    (accepted : finishCleanup machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold finishCleanup at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i id invocation exit normal tail stacked
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, ⟨record, events⟩, _, released, _, rfl⟩ := accepted
  have next := substack_valid machine tail valid (by rw [stacked]; exact List.sublist_cons_self _ _)
  have stored := same_storage_valid {machine with stack := tail}
    {machine.heap with obligations := machine.heap.obligations.set id.value record} next rfl rfl
  exact resumeRelease_valid _ _ stored

theorem cleanupFailed_valid (machine : State) (id : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : cleanupFailed machine id invocation outer normal tail inner = .ok after) (valid : Valid machine)
    (ordinary : ∀ value ∈ normal.toList, OwnerLocations.Ordinary value)
    (included : tail.Sublist machine.stack) : Valid after.state := by
  unfold cleanupFailed at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, ⟨record, events⟩, _, rfl⟩ := accepted
  let heap := {machine.heap with obligations := machine.heap.obligations.set id.value record}
  have next := same_storage_valid {machine with stack := tail} heap (substack_valid machine tail valid included) rfl rfl
  exact empty_control_valid _ _ next (ordinary_lives_fields_empty heap normal.toList ordinary)

theorem cleanupAbandoned_valid (machine : State) (id : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : cleanupAbandoned machine id invocation outer normal tail inner = .ok after) (valid : Valid machine)
    (ordinary : ∀ value ∈ normal.toList, OwnerLocations.Ordinary value)
    (included : tail.Sublist machine.stack) : Valid after.state := by
  simp only [cleanupAbandoned, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, ⟨record, events⟩, _, rfl⟩ := accepted
  let heap := {machine.heap with obligations := machine.heap.obligations.set id.value record}
  have next := same_storage_valid {machine with stack := tail} heap (substack_valid machine tail valid included) rfl rfl
  exact empty_control_valid _ _ next (ordinary_lives_fields_empty heap normal.toList ordinary)

theorem finishCleanupUnwind_valid (machine : State) (id : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition)
    (accepted : finishCleanupUnwind machine id invocation outer normal tail inner = .ok after) (valid : Valid machine)
    (ordinary : ∀ value ∈ normal.toList, OwnerLocations.Ordinary value)
    (included : tail.Sublist machine.stack) : Valid after.state := by
  unfold finishCleanupUnwind at accepted
  split at accepted <;> first
    | exact cleanupFailed_valid _ _ _ _ _ _ _ _ accepted valid ordinary included
    | exact cleanupAbandoned_valid _ _ _ _ _ _ _ _ accepted valid ordinary included
    | contradiction

theorem unwindStep_valid (machine : State) (context : Context) (after : Transition)
    (original : Cleanup.Exit .source) (unwinding : machine.control = .unwind original)
    (accepted : unwindStep machine context = .ok after) (valid : Valid machine)
    (owners : OwnerLocations.Valid machine)
    (retired : ∀ pinned ∈ fields machine, OwnerLocations.Retired machine.heap pinned.owner)
    (objects : ObjectOwners.Valid machine.heap) : Valid after.state := by
  simp only [unwindStep, unwinding, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨scope, scopeAt, accepted⟩ := accepted
  have holdings := (OwnerLocations.heap_valid machine owners).2 scope (List.mem_of_getElem? scopeAt)
  have pendingValid : Valid {machine with control := .discard (scope.holdings.flatMap (liveOwned machine.heap)) (.unwind (observedExit machine original))} := by
    exact empty_control_valid machine _ valid (ordinary_lives_fields_empty machine.heap scope.holdings holdings)

  cases stacked : machine.stack with
  | nil =>
    simp only [stacked] at accepted
    split at accepted
    · cases accepted
      simpa only [Valid, fields_components, stacked] using pendingValid
    · split at accepted <;> try contradiction
      all_goals cases accepted
      all_goals simpa only [Valid, fields_components, unwinding, stacked] using valid

  | cons saved tail =>
    have frameNormal := OwnerLocations.normal_frame machine saved (by simp [stacked]) owners.1
    have included : tail.Sublist machine.stack := by rw [stacked]; exact List.sublist_cons_self _ _
    have tailValid := substack_valid machine tail valid included
    cases saved <;> simp only [stacked] at accepted
    case invocation invocation parent =>
      split at accepted
      · cases accepted
        simpa only [Valid, fields_components, stacked] using pendingValid
      · cases accepted
        simpa only [Valid, fields_components, controlFields, DisposalShape.control, unwinding] using tailValid
    case lexical identity =>
      split at accepted
      · cases accepted
        simpa only [Valid, fields_components, stacked] using pendingValid
      · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨_, _, parent, _, rfl⟩ := accepted
        simpa only [Valid, fields_components, controlFields, DisposalShape.control, unwinding] using tailValid
    case restore invocation parent =>
      cases accepted
      simpa only [Valid, fields_components, controlFields, DisposalShape.control, unwinding] using tailValid
    case binding binder body bindings parent =>
      cases accepted
      simpa only [Valid, fields_components, controlFields, DisposalShape.control, unwinding] using tailValid
    case operands intent bindings remaining evaluated =>
      cases accepted
      simpa only [Valid, fields_components, controlFields, DisposalShape.control, unwinding] using tailValid
    case handler active =>
      cases accepted
      simpa only [Valid, fields_components, controlFields, DisposalShape.control, unwinding] using tailValid
    case region region =>
      cases accepted
      simpa only [Valid, fields_components, controlFields, DisposalShape.control, unwinding] using tailValid
    case injection values =>
      cases accepted
      simpa only [Valid, fields_components, controlFields, DisposalShape.control, unwinding] using tailValid
    case protection identity =>
      exact beginCleanup_valid _ _ _ _ _ _ _ accepted valid included retired objects
    case cleanupReturn identity invocation outer normal =>
      exact finishCleanupUnwind_valid _ _ _ _ _ _ _ _ accepted valid frameNormal included
    case releaseReturn scope afterRelease =>
      cases accepted
      exact empty_control_valid _ (.unwind _) tailValid rfl
    case disposalReturn remaining afterRelease invocation parent =>
      cases primaryIs : (observedExit machine original).primary <;> simp only [primaryIs] at accepted
      all_goals cases afterRelease <;> simp only [pure, Except.pure, Except.bind] at accepted
      all_goals cases accepted
      all_goals simpa only [Valid, fields_components, controlFields, frameFields, DisposalShape.control,
        DisposalShape.frame, unwinding, stacked, List.flatMap_cons, List.filter_nil, List.nil_append] using valid

theorem executeCleanupTerm_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executeCleanupTerm machine context = .ok after) (valid : Valid machine)
    (owners : OwnerLocations.Valid machine) (leaves : DisposalShape.Valid machine)
    (objects : ObjectOwners.Valid machine.heap)
    (shapes : ValueInventory.All (ValueShape context.source.schemas) machine) : Valid after.state := by
  have resultingLeaves := DisposalShape.executeCleanupTerm_valid _ _ _ accepted leaves shapes
  unfold executeCleanupTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  have ordinary : ∀ value ∈ operands, OwnerLocations.Ordinary value := by
    intro value member
    exact OwnerLocations.normal_control machine owners.1 value (by
      simp only [executing, OwnerLocations.controlValues]
      exact List.mem_append_right _ member)
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    apply installProtection_valid _ _ _ _ _ _ _ _ accepted valid
      (by grind only [List.mem_cons, List.not_mem_nil]) (by grind only [List.mem_cons, List.not_mem_nil])
      ?_ ?_ (fields_retired machine owners leaves) objects
    · intro value member
      exact ordinary value (List.mem_cons_of_mem _ (List.mem_cons_of_mem _ (List.mem_of_mem_take member)))
    · intro value member
      have found := Option.mem_toList.mp member
      exact ordinary value (List.mem_cons_of_mem _ (List.mem_cons_of_mem _ (List.mem_of_getElem? found)))
  · split at accepted <;> try contradiction
    rename_i value operandsAt
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, unitIndex, _, ⟨middle, owner⟩, reserved, rfl⟩ := accepted
    have next := temporary_valid _ _ _ reserved valid
    apply empty_control_valid _ _ next
    exact ordinary_fields_empty [value] (by simpa using ordinary)
      (by simpa only [DisposalShape.control] using resultingLeaves.1)

end QueueCustody
end BoundaryV2.Profile.Source.Machine
