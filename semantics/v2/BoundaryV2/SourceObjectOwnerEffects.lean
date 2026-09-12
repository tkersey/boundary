import BoundaryV2.SourceObjectOwnerStorage

namespace BoundaryV2.Profile.Source.Machine
namespace ObjectOwners

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem openRequest_valid (machine : State) (context : Context) (operation : Operation)
    (operands : List Located) (after : Transition) (formed : Valid machine.heap)
    (accepted : openRequest machine context operation operands = .ok after) : Valid after.state.heap := by
  simp only [openRequest, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, accepted⟩ := accepted
  split at accepted
  · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    exact formed
  · simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, _, accepted⟩ := accepted
    cases stored <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, selected, _, definition, _, clause, _, accepted⟩ := accepted
    split at accepted
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, _, _, invoked⟩ := accepted
      exact invokeFunction_valid _ _ _ _ _ _ formed invoked
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨shape, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      obtain ⟨store, moved, accepted⟩ := (except_bind_ok _ _ _).mp accepted
      have moved := (fromOption_ok _ _ _).mp moved
      have storeValid := move_valid formed moved
      split at accepted
      all_goals
        simp only [except_bind_ok, fromOption_ok] at accepted
        try
          obtain ⟨gate, guard, rest⟩ := accepted
          have _ : Unit := gate
          clear guard
          have accepted := rest
        obtain ⟨⟨outside, owner⟩, temporaryOk, ⟨finalStore, token⟩, allocated, staged, stagedOk, invoked⟩ := accepted
        have outsideValid := temporary_valid (by exact storeValid) temporaryOk
        have created := allocation_valid _ _ _ _ _ _ _ allocated outsideValid (by first | trivial | (split <;> trivial))
        exact invokeFunction_valid _ _ _ _ _ _ (finishTemporary_valid created stagedOk) invoked

theorem installProtection_valid (machine : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (formed : Valid machine.heap)
    (accepted : installProtection machine context body cleanup arguments resource loan = .ok after) : Valid after.state.heap := by
  simp only [installProtection, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, store, moved, accepted⟩ := accepted
  have next := move_valid formed moved
  cases resource with
  | none =>
    cases loan <;> try contradiction
    simp only [pure, Except.pure, Except.bind] at accepted
    exact applyClosure_valid _ _ _ _ _ (by exact next) accepted
  | some value =>
    cases loan with
    | none => contradiction
    | some descriptor =>
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, ⟨afterStore, borrowed⟩, allocated, _, rfl, applied⟩ := accepted
      have allocatedValid := allocation_valid _ _ _ _ _ _ _ allocated (by exact next) (by trivial)
      exact applyClosure_valid _ _ _ _ _ allocatedValid applied

theorem executeEffectTerm_valid (machine : State) (context : Context) (after : Transition)
    (formed : Valid machine.heap)
    (accepted : executeEffectTerm machine context = .ok after) : Valid after.state.heap := by
  unfold executeEffectTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · exact openRequest_valid _ _ _ _ _ formed accepted
  · split at accepted <;> try contradiction
    exact installHandler_valid _ _ _ _ _ _ _ _ formed accepted
  · split at accepted <;> try contradiction
    exact resumeValue_valid _ _ _ _ _ _ formed accepted
  · split at accepted <;> try contradiction
    exact resumeValue_valid _ _ _ _ _ _ formed accepted
  · split at accepted <;> try contradiction
    exact resumeComputation_valid _ _ _ _ _ formed accepted
  · split at accepted <;> try contradiction
    exact enterRegion_valid _ _ _ _ _ _ formed accepted

theorem beginCleanup_valid (machine : State) (context : Context) (id : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (formed : Valid machine.heap)
    (accepted : beginCleanup machine context id exit normal tail = .ok after) : Valid after.state.heap := by
  simp only [beginCleanup, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, result, applied, rfl⟩ := accepted
  have next := applyClosure_valid _ _ _ _ _ (by exact formed) applied
  exact next

theorem finishCleanup_valid (machine : State) (context : Context) (after : Transition)
    (formed : Valid machine.heap)
    (accepted : finishCleanup machine context = .ok after) : Valid after.state.heap := by
  unfold finishCleanup at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, rfl⟩ := accepted
  exact formed

theorem cleanupFailed_valid (machine : State) (id : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition) (formed : Valid machine.heap)
    (accepted : cleanupFailed machine id invocation outer normal tail inner = .ok after) : Valid after.state.heap := by
  unfold cleanupFailed at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact formed

theorem cleanupAbandoned_valid (machine : State) (id : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition) (formed : Valid machine.heap)
    (accepted : cleanupAbandoned machine id invocation outer normal tail inner = .ok after) : Valid after.state.heap := by
  simp only [cleanupAbandoned, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  exact formed

theorem finishCleanupUnwind_valid (machine : State) (id : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition) (formed : Valid machine.heap)
    (accepted : finishCleanupUnwind machine id invocation outer normal tail inner = .ok after) : Valid after.state.heap := by
  unfold finishCleanupUnwind at accepted
  split at accepted <;> first
    | exact cleanupFailed_valid _ _ _ _ _ _ _ _ formed accepted
    | exact cleanupAbandoned_valid _ _ _ _ _ _ _ _ formed accepted
    | contradiction

theorem finishDisposal_valid (machine : State) (after : Transition)
    (formed : Valid machine.heap) (accepted : finishDisposal machine = .ok after) : Valid after.state.heap := by
  unfold finishDisposal at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  exact formed

theorem discardValues_valid (machine : State) (context : Context) (after : Transition)
    (formed : Valid machine.heap)
    (accepted : discardValues machine context = .ok after) : Valid after.state.heap := by
  unfold discardValues at accepted
  split at accepted <;> try contradiction
  split at accepted
  · cases accepted; exact formed
  · split at accepted
    · cases accepted; exact formed
    · simp only [bind, except_bind_ok] at accepted
      obtain ⟨⟨node, object⟩, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      all_goals
        simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨heap, retired, rfl⟩ := accepted
        have next := retire_valid _ _ _ retired formed
        exact next

theorem unwindStep_valid (machine : State) (context : Context) (after : Transition)
    (formed : Valid machine.heap)
    (accepted : unwindStep machine context = .ok after) : Valid after.state.heap := by
  simp only [unwindStep, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → beginCleanup_valid, → finishCleanupUnwind_valid]

theorem executeCleanupTerm_valid (machine : State) (context : Context) (after : Transition)
    (formed : Valid machine.heap)
    (accepted : executeCleanupTerm machine context = .ok after) : Valid after.state.heap := by
  unfold executeCleanupTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact installProtection_valid _ _ _ _ _ _ _ _ formed accepted
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, ⟨middle, owner⟩, temporaryOk, rfl⟩ := accepted
    have next := temporary_valid formed temporaryOk
    exact next

end ObjectOwners
end BoundaryV2.Profile.Source.Machine
