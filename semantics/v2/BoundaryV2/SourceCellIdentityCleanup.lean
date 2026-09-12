import BoundaryV2.SourceCellIdentityControl

namespace BoundaryV2.Profile.Source.Machine
namespace CellIdentities

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem openRequest_unique (machine : State) (context : Context) (operation : Operation)
    (operands : List Located) (after : Transition) (formed : Unique machine.heap)
    (accepted : openRequest machine context operation operands = .ok after) : Unique after.state.heap := by
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
      exact invokeFunction_unique _ _ _ _ _ _ formed invoked
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨shape, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      obtain ⟨store, moved, accepted⟩ := (except_bind_ok _ _ _).mp accepted
      have moved := (fromOption_ok _ _ _).mp moved
      have storeUnique := move_unique formed moved
      split at accepted
      all_goals
        simp only [except_bind_ok, fromOption_ok] at accepted
        try
          obtain ⟨gate, guard, rest⟩ := accepted
          have _ : Unit := gate
          clear guard
          have accepted := rest
        obtain ⟨⟨outside, owner⟩, temporaryOk, ⟨finalStore, token⟩, allocated, staged, stagedOk, invoked⟩ := accepted
        have outsideUnique := temporary_unique (by exact storeUnique) temporaryOk
        have created := allocate_noncell_unique _ _ _ _ _ _ _ allocated (by first | rfl | (split <;> rfl)) outsideUnique
        exact invokeFunction_unique _ _ _ _ _ _ (finishTemporary_unique created stagedOk) invoked

theorem installProtection_unique (machine : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (formed : Unique machine.heap)
    (accepted : installProtection machine context body cleanup arguments resource loan = .ok after) : Unique after.state.heap := by
  simp only [installProtection, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, store, moved, accepted⟩ := accepted
  have next := move_unique formed moved
  cases resource with
  | none =>
    cases loan <;> try contradiction
    simp only [pure, Except.pure, Except.bind] at accepted
    exact applyClosure_unique _ _ _ _ _ (by exact next) accepted
  | some value =>
    cases loan with
    | none => contradiction
    | some descriptor =>
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, ⟨afterStore, borrowed⟩, allocated, _, rfl, applied⟩ := accepted
      have allocatedUnique := allocate_noncell_unique _ _ _ _ _ _ _ allocated rfl (by exact next)
      exact applyClosure_unique _ _ _ _ _ allocatedUnique applied

theorem executeEffectTerm_unique (machine : State) (context : Context) (after : Transition)
    (formed : Unique machine.heap) (bounded : IdentitySupport.Valid machine)
    (accepted : executeEffectTerm machine context = .ok after) : Unique after.state.heap := by
  unfold executeEffectTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · exact openRequest_unique _ _ _ _ _ formed accepted
  · split at accepted <;> try contradiction
    exact installHandler_unique _ _ _ _ _ _ _ _ formed accepted
  · split at accepted <;> try contradiction
    exact resumeValue_unique _ _ _ _ _ _ formed bounded accepted
  · split at accepted <;> try contradiction
    exact resumeValue_unique _ _ _ _ _ _ formed bounded accepted
  · split at accepted <;> try contradiction
    exact resumeComputation_unique _ _ _ _ _ formed bounded accepted
  · split at accepted <;> try contradiction
    exact enterRegion_unique _ _ _ _ _ _ formed accepted

theorem beginCleanup_unique (machine : State) (context : Context) (id : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (formed : Unique machine.heap)
    (accepted : beginCleanup machine context id exit normal tail = .ok after) : Unique after.state.heap := by
  simp only [beginCleanup, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, result, applied, rfl⟩ := accepted
  have next := applyClosure_unique _ _ _ _ _ (by exact formed) applied
  exact next

theorem finishCleanup_unique (machine : State) (context : Context) (after : Transition)
    (formed : Unique machine.heap)
    (accepted : finishCleanup machine context = .ok after) : Unique after.state.heap := by
  unfold finishCleanup at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, rfl⟩ := accepted
  exact formed

theorem cleanupFailed_unique (machine : State) (id : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition) (formed : Unique machine.heap)
    (accepted : cleanupFailed machine id invocation outer normal tail inner = .ok after) : Unique after.state.heap := by
  unfold cleanupFailed at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact formed

theorem cleanupAbandoned_unique (machine : State) (id : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition) (formed : Unique machine.heap)
    (accepted : cleanupAbandoned machine id invocation outer normal tail inner = .ok after) : Unique after.state.heap := by
  simp only [cleanupAbandoned, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  exact formed

theorem finishCleanupUnwind_unique (machine : State) (id : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition) (formed : Unique machine.heap)
    (accepted : finishCleanupUnwind machine id invocation outer normal tail inner = .ok after) : Unique after.state.heap := by
  unfold finishCleanupUnwind at accepted
  split at accepted <;> first
    | exact cleanupFailed_unique _ _ _ _ _ _ _ _ formed accepted
    | exact cleanupAbandoned_unique _ _ _ _ _ _ _ _ formed accepted
    | contradiction

theorem finishDisposal_unique (machine : State) (after : Transition)
    (formed : Unique machine.heap) (accepted : finishDisposal machine = .ok after) : Unique after.state.heap := by
  unfold finishDisposal at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  exact formed

theorem discardValues_unique (machine : State) (context : Context) (after : Transition)
    (formed : Unique machine.heap)
    (accepted : discardValues machine context = .ok after) : Unique after.state.heap := by
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
        have next := retire_unique _ _ _ retired formed
        exact next

theorem unwindStep_unique (machine : State) (context : Context) (after : Transition)
    (formed : Unique machine.heap)
    (accepted : unwindStep machine context = .ok after) : Unique after.state.heap := by
  simp only [unwindStep, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → beginCleanup_unique, → finishCleanupUnwind_unique]

theorem executeCleanupTerm_unique (machine : State) (context : Context) (after : Transition)
    (formed : Unique machine.heap)
    (accepted : executeCleanupTerm machine context = .ok after) : Unique after.state.heap := by
  unfold executeCleanupTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact installProtection_unique _ _ _ _ _ _ _ _ formed accepted
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, ⟨middle, owner⟩, temporaryOk, rfl⟩ := accepted
    have next := temporary_unique formed temporaryOk
    exact next

end CellIdentities
end BoundaryV2.Profile.Source.Machine
