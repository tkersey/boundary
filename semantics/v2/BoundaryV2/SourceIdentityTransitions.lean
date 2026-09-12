import BoundaryV2.SourceIdentityRequests

namespace BoundaryV2.Profile.Source.Machine
namespace IdentitySupport

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem executeControlTerm_valid (machine : State) (context : Context) (after : Transition)
    (bounded : ValidAt limit machine) (upper : Upper limit after.state.heap)
    (accepted : executeControlTerm machine context = .ok after) : ValidAt limit after.state := by
  unfold executeControlTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    exact ⟨bounded.heap, bounded.frames, trivial, bounded.scope, bounded.invocation⟩
  · cases accepted
    exact ⟨bounded.heap, bounded.frames, trivial, bounded.scope, bounded.invocation⟩
  · split at accepted <;> try contradiction
    exact applyClosure_valid _ _ _ _ _ bounded upper accepted
  · split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, rfl⟩ := accepted
    exact ⟨bounded.heap, bounded.frames, trivial, bounded.scope, bounded.invocation⟩
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨var, body⟩, _, accepted⟩ := accepted
    exact enterPattern_valid _ _ _ _ _ _ _ _ bounded upper accepted
  · split at accepted <;> try contradiction
    exact enterPattern_valid _ _ _ _ _ _ _ _ bounded upper accepted

theorem executeCleanupTerm_valid (machine : State) (context : Context) (after : Transition)
    (bounded : ValidAt limit machine) (upper : Upper limit after.state.heap)
    (accepted : executeCleanupTerm machine context = .ok after) : ValidAt limit after.state := by
  unfold executeCleanupTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact installProtection_valid _ _ _ _ _ _ _ _ bounded upper accepted
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨shape, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, ⟨middle, owner⟩, temporaryOk, rfl⟩ := accepted
    have next := temporary_valid bounded temporaryOk
    exact ⟨next.heap, next.frames, trivial, next.scope, next.invocation⟩

theorem discardValues_valid (machine : State) (context : Context) (after : Transition)
    (bounded : ValidAt limit machine)
    (accepted : discardValues machine context = .ok after) : ValidAt limit after.state := by
  unfold discardValues at accepted
  split at accepted <;> try contradiction
  split at accepted
  · cases accepted
    exact resumeRelease_valid _ _ bounded
  · split at accepted
    · cases accepted
      exact ⟨bounded.heap, bounded.frames, trivial, bounded.scope, bounded.invocation⟩
    · simp only [bind, except_bind_ok] at accepted
      obtain ⟨⟨node, object⟩, looked, accepted⟩ := accepted
      split at accepted <;> try contradiction
      all_goals
        simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨heap, retired, rfl⟩ := accepted
        have heapBound := retire_heap bounded.heap retired
      · rename_i saved matched
        cases matched
        have captureBound := lookupObject_bound bounded looked
        refine ⟨heapBound, ?_, trivial, captureBound.2.2.2.2.1, captureBound.2.2.2.2.2⟩
        intro frame member
        simp only [List.mem_append, List.mem_cons, List.not_mem_nil, or_false] at member
        rcases member with (captured | entered | returned) | old
        · exact captureBound.1 frame captured
        · cases entered; exact captureBound.2.1
        · cases returned; exact ⟨bounded.invocation, bounded.scope⟩
        · exact bounded.frames frame old
      all_goals exact ⟨heapBound, bounded.frames, trivial, bounded.scope, bounded.invocation⟩

theorem unwindStep_valid (machine : State) (context : Context) (after : Transition)
    (bounded : ValidAt limit machine) (upper : Upper limit after.state.heap)
    (accepted : unwindStep machine context = .ok after) : ValidAt limit after.state := by
  unfold unwindStep at accepted
  split at accepted <;> try contradiction
  rename_i original unwinding
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨scope, scopeAt, accepted⟩ := accepted
  cases stacked : machine.stack with
  | nil =>
    simp only [stacked] at accepted
    split at accepted
    · cases accepted
      exact ⟨bounded.heap, (by simpa only [stacked] using bounded.frames), trivial, bounded.scope, bounded.invocation⟩
    · split at accepted <;> try contradiction
      all_goals cases accepted; exact ⟨bounded.heap, (by simpa only [stacked] using bounded.frames), bounded.control, bounded.scope, bounded.invocation⟩
  | cons frame tail =>
    have frameBound := bounded.frames frame (by simp [stacked])
    have tailBound : ∀ frame ∈ tail, FrameValid limit frame :=
      fun frame member => bounded.frames frame (by simp [stacked, member])
    cases frame <;> simp only [stacked] at accepted
    all_goals first
      | (cases accepted; exact ⟨bounded.heap, tailBound, bounded.control, bounded.scope, bounded.invocation⟩)
      | (cases accepted; exact ⟨bounded.heap, tailBound, bounded.control, frameBound.2, frameBound.1⟩)
      | skip
    case invocation invocation parent =>
      split at accepted
      · cases accepted
        exact ⟨bounded.heap, (by simpa only [stacked] using bounded.frames), trivial, bounded.scope, bounded.invocation⟩
      · cases accepted
        exact ⟨bounded.heap, tailBound, bounded.control, frameBound.2, frameBound.1⟩
    case lexical identity =>
      split at accepted
      · cases accepted
        exact ⟨bounded.heap, (by simpa only [stacked] using bounded.frames), trivial, bounded.scope, bounded.invocation⟩
      · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨_, _, parent, parentAt, rfl⟩ := accepted
        have parentBound := (bounded.heap.scopes scope (List.mem_of_getElem? scopeAt)).2.2 parent parentAt
        exact ⟨bounded.heap, tailBound, bounded.control, parentBound, bounded.invocation⟩
    case protection identity =>
      exact beginCleanup_valid _ _ _ _ _ _ _ bounded tailBound upper accepted
    case cleanupReturn =>
      exact finishCleanupUnwind_valid _ _ _ _ _ _ _ _ bounded tailBound accepted
    case disposalReturn remaining released invocation parent =>
      cases primary : (observedExit machine original).primary <;> simp only [primary] at accepted
      all_goals cases released <;> simp only [pure, Except.pure, Except.bind] at accepted
      all_goals cases accepted
      all_goals exact ⟨bounded.heap, tailBound, trivial, frameBound.2, frameBound.1⟩
    case releaseReturn =>
      cases accepted
      exact ⟨bounded.heap, tailBound, trivial, bounded.scope, bounded.invocation⟩

end IdentitySupport
end BoundaryV2.Profile.Source.Machine
