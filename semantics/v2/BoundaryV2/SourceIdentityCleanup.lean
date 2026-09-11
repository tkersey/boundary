import BoundaryV2.SourceIdentityControl

namespace BoundaryV2.Profile.Source.Machine
namespace IdentitySupport

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem resumeValue_valid (machine : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (bounded : ValidAt limit machine) (upper : Upper limit after.state.heap)
    (accepted : resumeValue machine context token argument successor = .ok after) : ValidAt limit after.state := by
  simp only [resumeValue, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, _, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, active, activated, ⟨middle, owner⟩, temporaryOk, store, moved, finished⟩ := accepted
  have finishGrowth := (finishTemporary_allocation _ _ _ finished).heap
  have moveGrowth := moveValues_allocation _ _ _ _ moved
  have temporaryGrowth := (temporary_allocation _ _ _ temporaryOk).heap
  have activateGrowth := (activateCapture_allocation _ _ _ _ _ activated).heap
  have takenUpper := upper_before (activateGrowth.trans (temporaryGrowth.trans (moveGrowth.trans finishGrowth))) upper
  have takenBounded := takeCapture_valid _ _ _ _ bounded takenUpper captured
  have activeBounded := activateCapture_valid _ _ _ _ _ takenBounded.1 takenBounded.2 activated
  exact finishTemporary_valid (move_valid (temporary_valid activeBounded temporaryOk) moved) finished

theorem resumeComputation_valid (machine : State) (context : Context) (token computation : Located) (after : Transition)
    (bounded : ValidAt limit machine) (upper : Upper limit after.state.heap)
    (accepted : resumeComputation machine context token computation = .ok after) : ValidAt limit after.state := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, active, activated, applied⟩ := accepted
  have growth := (activateCapture_allocation _ _ _ _ _ activated).heap.trans (applyClosure_allocation _ _ _ _ _ applied).heap
  have takenBounded := takeCapture_valid _ _ _ _ bounded (upper_before growth upper) captured
  exact applyClosure_valid _ _ _ _ _ (activateCapture_valid _ _ _ _ _ takenBounded.1 takenBounded.2 activated) upper applied

theorem set_obligation (bounded : HeapValid limit heap) (recordBounded : ObligationValid limit record) :
    HeapValid limit { heap with obligations := heap.obligations.set index record } := by
  refine ⟨bounded.objects, bounded.scopes, bounded.invocations, ?_, bounded.loans⟩
  intro obligation member
  rcases List.mem_or_eq_of_mem_set member with old | replaced
  · exact bounded.obligations obligation old
  · cases replaced; exact recordBounded

theorem begin_obligation (bounded : ObligationValid limit before) (invocationBound : Bound limit invocation)
    (accepted : Cleanup.begin before invocation = some (after, events)) : ObligationValid limit after := by
  unfold Cleanup.begin at accepted
  split at accepted <;> try contradiction
  cases accepted
  exact ⟨bounded.1, bounded.2.1, invocationBound⟩

theorem complete_obligation (bounded : ObligationValid limit before)
    (accepted : Cleanup.complete before invocation result = some (after, events)) : ObligationValid limit after := by
  unfold Cleanup.complete at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases result with
  | ok value => cases value; cases accepted; exact ⟨bounded.1, bounded.2.1, trivial⟩
  | error value => cases accepted; exact ⟨bounded.1, bounded.2.1, trivial⟩

theorem beginCleanup_valid (machine : State) (context : Context) (identity : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (bounded : ValidAt limit machine) (framesBound : ∀ frame ∈ tail, FrameValid limit frame)
    (upper : Upper limit after.state.heap)
    (accepted : beginCleanup machine context identity exit normal tail = .ok after) : ValidAt limit after.state := by
  simp only [beginCleanup, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨before, found, _, identityOk, ⟨record, events⟩, begun, signature, _, infoType, _, information, _, result, applied, rfl⟩ := accepted
  have beforeBounded := bounded.heap.obligations before (List.mem_of_getElem? found)
  have sameIdentity : before.id = identity := by
    unfold require at identityOk
    split at identityOk <;> try contradiction
    simpa using (by assumption : (before.id == identity) = true)
  have identityBound : Bound limit identity := sameIdentity ▸ beforeBounded.1
  have fresh : Bound limit (⟨machine.heap.nextInvocation⟩ : InvocationId) := by
    have increment := applyClosure_invocation_counter _ _ _ _ _ applied
    change result.state.heap.nextInvocation = machine.heap.nextInvocation + 1 at increment
    have high := upper .invocation
    simp only [limits] at high
    simp only [Bound]
    omega
  have recordBounded := begin_obligation beforeBounded fresh begun
  apply applyClosure_valid _ _ _ _ result ?_ upper applied
  refine ⟨set_obligation bounded.heap recordBounded, ?_, bounded.control, bounded.scope, bounded.invocation⟩
  intro frame member
  rcases List.mem_cons.mp member with current | outer
  · cases current; exact ⟨identityBound, fresh⟩
  · exact framesBound frame outer

theorem finishCleanup_valid (machine : State) (context : Context) (after : Transition)
    (bounded : ValidAt limit machine) (accepted : finishCleanup machine context = .ok after) : ValidAt limit after.state := by
  unfold finishCleanup at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i identity invocation exit normal tail stacked
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, before, found, ⟨record, events⟩, completed, released, _, rfl⟩ := accepted
  have beforeBounded := bounded.heap.obligations before (List.mem_of_getElem? found)
  have recordBounded := complete_obligation beforeBounded completed
  have resumed : ValidAt limit {machine with
      heap := {machine.heap with obligations := machine.heap.obligations.set identity.value record}, stack := tail} :=
    ⟨set_obligation bounded.heap recordBounded,
      fun frame member => bounded.frames frame (by simp [stacked, member]), bounded.control, bounded.scope, bounded.invocation⟩
  exact resumeRelease_valid _ _ resumed

theorem cleanupFailed_valid (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition) (bounded : ValidAt limit machine)
    (framesBound : ∀ frame ∈ tail, FrameValid limit frame)
    (accepted : cleanupFailed machine identity invocation outer normal tail inner = .ok after) : ValidAt limit after.state := by
  unfold cleanupFailed at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨before, found, ⟨record, events⟩, completed, rfl⟩ := accepted
  have recordBounded := complete_obligation (bounded.heap.obligations before (List.mem_of_getElem? found)) completed
  exact ⟨set_obligation bounded.heap recordBounded, framesBound, trivial, bounded.scope, bounded.invocation⟩

private theorem foldlM_preserves (items : List β) (step : α → β → Except Invalid α)
    (property : α → Prop) (preserved : ∀ before item after, step before item = .ok after → property before → property after)
    (before after : α) (accepted : items.foldlM step before = .ok after) (holds : property before) : property after := by
  induction items generalizing before with
  | nil => cases accepted; exact holds
  | cons first rest induction =>
    simp only [List.foldlM_cons, bind, except_bind_ok] at accepted
    obtain ⟨middle, stepped, accepted⟩ := accepted
    exact induction middle accepted (preserved before first middle stepped holds)

theorem enterRegion_valid (machine : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition)
    (bounded : ValidAt limit machine) (upper : Upper limit after.state.heap)
    (accepted : enterRegion machine context descriptor body arguments = .ok after) : ValidAt limit after.state := by
  simp only [enterRegion, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, signature, _, schema, _, _, _, ⟨store, value⟩, allocated, applied⟩ := accepted
  have growth := (allocateObject_allocation _ _ _ _ _ _ _ allocated).trans (applyClosure_allocation _ _ _ _ _ applied).heap
  have high := upper_before growth upper .regionInstance
  have fresh : Bound limit (⟨machine.heap.nextRegion⟩ : RegionInstanceId) := by
    change machine.heap.nextRegion + 1 ≤ limit .regionInstance at high
    exact Nat.lt_of_lt_of_le (Nat.lt_succ_self _) high
  have seed : HeapValid limit {machine.heap with nextRegion := machine.heap.nextRegion + 1} :=
    ⟨bounded.heap.objects, bounded.heap.scopes, bounded.heap.invocations, bounded.heap.obligations, bounded.heap.loans⟩
  have regionBound : ObjectValid limit
      (.region ⟨machine.heap.nextRegion⟩ descriptor machine.invocation (activeRegions machine.stack).head?) :=
    ⟨fresh, bounded.invocation, fun parent member => active_regions bounded.frames (List.mem_of_head? member)⟩
  have heap := allocate_heap seed regionBound allocated
  apply applyClosure_valid _ _ _ _ _ ?_ upper applied
  refine ⟨heap, ?_, bounded.control, bounded.scope, bounded.invocation⟩
  intro frame member
  rcases List.mem_cons.mp member with entered | outer
  · cases entered; exact fresh
  · exact bounded.frames frame outer

theorem installHandler_valid (machine : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (bindings : Environment) (after : Transition)
    (bounded : ValidAt limit machine) (upper : Upper limit after.state.heap)
    (accepted : installHandler machine context handler body arguments stored bindings = .ok after) : ValidAt limit after.state := by
  simp only [installHandler, bind, except_bind_ok] at accepted
  obtain ⟨definition, _, _, _, _, _, _, _, signature, _, _, _, ⟨store, capabilities⟩, allocated, applied⟩ := accepted
  have lower : machine.heap.nextAttachment + 1 ≤ store.nextAttachment := by
    apply foldlM_preserves _ _ (fun pair : Heap × List Located => machine.heap.nextAttachment + 1 ≤ pair.1.nextAttachment) ?_ _ _ allocated (Nat.le_refl _)
    intro before item after accepted lower
    rcases before with ⟨heap, capabilities⟩
    rcases item with ⟨clause, schema⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, ⟨next, value⟩, allocated, rfl⟩ := accepted
    exact Nat.le_trans lower (allocateObject_allocation _ _ _ _ _ _ _ allocated).attachments
  have high := upper_before (applyClosure_allocation _ _ _ _ _ applied).heap upper .attachment
  have fresh : Bound limit (⟨machine.heap.nextAttachment⟩ : AttachmentId) := by
    change store.nextAttachment ≤ limit .attachment at high
    exact Nat.lt_of_lt_of_le (Nat.lt_of_lt_of_le (Nat.lt_succ_self _) lower) high
  have heap : HeapValid limit store := by
    apply foldlM_preserves _ _ (fun pair : Heap × List Located => HeapValid limit pair.1) ?_ _ _ allocated
      ⟨bounded.heap.objects, bounded.heap.scopes, bounded.heap.invocations, bounded.heap.obligations, bounded.heap.loans⟩
    intro before item after accepted bounded
    rcases before with ⟨heap, capabilities⟩
    rcases item with ⟨clause, schema⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, ⟨next, value⟩, allocated, rfl⟩ := accepted
    exact allocate_heap bounded (by exact fresh) allocated
  apply applyClosure_valid _ _ _ _ _ ?_ upper applied
  refine ⟨heap, ?_, bounded.control, bounded.scope, bounded.invocation⟩
  intro frame member
  rcases List.mem_cons.mp member with entered | outer
  · cases entered
    exact ⟨fresh, bounded.scope, bounded.invocation,
      fun parent member => active_attachments bounded.frames (List.mem_of_head? member)⟩
  · exact bounded.frames frame outer

end IdentitySupport
end BoundaryV2.Profile.Source.Machine
