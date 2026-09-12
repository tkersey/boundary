import BoundaryV2.SourceScopeTreeControl

namespace BoundaryV2.Profile.Source.Machine
namespace ScopeTree

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem takeCapture_formed (machine : State) (context : Context) (token : Located) (after : State × Capture)
    (formed : Formed machine.heap) (indexed : machine.heap.Indexed)
    (accepted : takeCapture machine context token = .ok after) : Formed after.1.heap := by
  simp only [takeCapture, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, _, accepted⟩ := accepted
  cases stored <;> try contradiction
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨heap, retired, rfl⟩ := accepted
    exact retire_formed formed retired
  · exact instantiateCapture_formed _ _ _ _ formed indexed accepted

theorem activateCapture_formed (machine : State) (context : Context) (saved : Capture)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : State)
    (formed : Formed machine.heap)
    (accepted : activateCapture machine context saved successor = .ok after) : Formed after.heap := by
  simp only [activateCapture, bind, except_bind_ok, pure, Except.pure] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  cases successor with
  | none => cases accepted; exact formed
  | some successor =>
    rcases successor with ⟨handler, stored, bindings⟩
    simp only [except_bind_ok, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, _, rfl, rfl⟩ := accepted
    exact formed

theorem resumeValue_formed (machine : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (formed : Formed machine.heap) (indexed : machine.heap.Indexed)
    (accepted : resumeValue machine context token argument successor = .ok after) : Formed after.state.heap := by
  simp only [resumeValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, saved⟩, captured, _, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, active, activated, ⟨temporary, owner⟩, temporaryOk, store, moved, finished⟩ := accepted
  exact finishTemporary_formed (move_formed (temporary_formed
    (activateCapture_formed _ _ _ _ _ (takeCapture_formed _ _ _ _ formed indexed captured) activated) temporaryOk) moved) finished

theorem resumeComputation_formed (machine : State) (context : Context) (token computation : Located) (after : Transition)
    (formed : Formed machine.heap) (indexed : machine.heap.Indexed)
    (accepted : resumeComputation machine context token computation = .ok after) : Formed after.state.heap := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, saved⟩, captured, active, activated, applied⟩ := accepted
  exact applyClosure_formed _ _ _ _ _
    (activateCapture_formed _ _ _ _ _ (takeCapture_formed _ _ _ _ formed indexed captured) activated) applied

theorem openRequest_formed (machine : State) (context : Context) (operation : Operation)
    (operands : List Located) (after : Transition) (formed : Formed machine.heap)
    (accepted : openRequest machine context operation operands = .ok after) : Formed after.state.heap := by
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
      exact invokeFunction_formed _ _ _ _ _ _ formed invoked
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨shape, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      obtain ⟨store, moved, accepted⟩ := (except_bind_ok _ _ _).mp accepted
      have moved := (fromOption_ok _ _ _).mp moved
      have storeFormed := move_formed formed moved
      split at accepted
      all_goals
        simp only [except_bind_ok, fromOption_ok] at accepted
        try
          obtain ⟨gate, guard, rest⟩ := accepted
          have _ : Unit := gate
          clear guard
          have accepted := rest
        obtain ⟨⟨outside, owner⟩, temporaryOk, ⟨finalStore, token⟩, allocated, staged, stagedOk, invoked⟩ := accepted
        have outsideFormed := temporary_formed (by exact storeFormed) temporaryOk
        have created := allocate_formed _ _ _ _ _ _ _ allocated outsideFormed
        exact invokeFunction_formed _ _ _ _ _ _ (finishTemporary_formed created stagedOk) invoked

theorem installProtection_formed (machine : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (formed : Formed machine.heap)
    (accepted : installProtection machine context body cleanup arguments resource loan = .ok after) : Formed after.state.heap := by
  simp only [installProtection, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, store, moved, accepted⟩ := accepted
  have next := move_formed formed moved
  cases resource with
  | none =>
    cases loan <;> try contradiction
    simp only [pure, Except.pure, Except.bind] at accepted
    exact applyClosure_formed _ _ _ _ _ (by exact next) accepted
  | some value =>
    cases loan with
    | none => contradiction
    | some descriptor =>
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, ⟨afterStore, borrowed⟩, allocated, _, rfl, applied⟩ := accepted
      have allocatedFormed := allocate_formed _ _ _ _ _ _ _ allocated (by exact next)
      exact applyClosure_formed _ _ _ _ _ allocatedFormed applied

theorem executeEffectTerm_formed (machine : State) (context : Context) (after : Transition)
    (formed : Formed machine.heap) (indexed : machine.heap.Indexed)
    (accepted : executeEffectTerm machine context = .ok after) : Formed after.state.heap := by
  unfold executeEffectTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · exact openRequest_formed _ _ _ _ _ formed accepted
  · split at accepted <;> try contradiction
    exact installHandler_formed _ _ _ _ _ _ _ _ formed accepted
  · split at accepted <;> try contradiction
    exact resumeValue_formed _ _ _ _ _ _ formed indexed accepted
  · split at accepted <;> try contradiction
    exact resumeValue_formed _ _ _ _ _ _ formed indexed accepted
  · split at accepted <;> try contradiction
    exact resumeComputation_formed _ _ _ _ _ formed indexed accepted
  · split at accepted <;> try contradiction
    exact enterRegion_formed _ _ _ _ _ _ formed accepted

theorem beginCleanup_formed (machine : State) (context : Context) (id : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (formed : Formed machine.heap)
    (accepted : beginCleanup machine context id exit normal tail = .ok after) : Formed after.state.heap := by
  simp only [beginCleanup, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, result, applied, rfl⟩ := accepted
  have next := applyClosure_formed _ _ _ _ _ (by exact formed) applied
  exact next

theorem finishCleanup_formed (machine : State) (context : Context) (after : Transition)
    (formed : Formed machine.heap)
    (accepted : finishCleanup machine context = .ok after) : Formed after.state.heap := by
  unfold finishCleanup at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, rfl⟩ := accepted
  exact formed

theorem cleanupFailed_formed (machine : State) (id : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition) (formed : Formed machine.heap)
    (accepted : cleanupFailed machine id invocation outer normal tail inner = .ok after) : Formed after.state.heap := by
  unfold cleanupFailed at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact formed

theorem cleanupAbandoned_formed (machine : State) (id : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition) (formed : Formed machine.heap)
    (accepted : cleanupAbandoned machine id invocation outer normal tail inner = .ok after) : Formed after.state.heap := by
  simp only [cleanupAbandoned, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  exact formed

theorem finishCleanupUnwind_formed (machine : State) (id : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame)
    (inner : Cleanup.Exit .source) (after : Transition) (formed : Formed machine.heap)
    (accepted : finishCleanupUnwind machine id invocation outer normal tail inner = .ok after) : Formed after.state.heap := by
  unfold finishCleanupUnwind at accepted
  split at accepted <;> first
    | exact cleanupFailed_formed _ _ _ _ _ _ _ _ formed accepted
    | exact cleanupAbandoned_formed _ _ _ _ _ _ _ _ formed accepted
    | contradiction

theorem finishDisposal_formed (machine : State) (after : Transition)
    (formed : Formed machine.heap) (accepted : finishDisposal machine = .ok after) : Formed after.state.heap := by
  unfold finishDisposal at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  exact formed

theorem discardValues_formed (machine : State) (context : Context) (after : Transition)
    (formed : Formed machine.heap)
    (accepted : discardValues machine context = .ok after) : Formed after.state.heap := by
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
        have next := retire_formed formed retired
        exact next

theorem unwindStep_formed (machine : State) (context : Context) (after : Transition)
    (formed : Formed machine.heap)
    (accepted : unwindStep machine context = .ok after) : Formed after.state.heap := by
  simp only [unwindStep, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw] at accepted
  grind (gen := 32) only [except_bind_ok, fromOption_ok, → beginCleanup_formed, → finishCleanupUnwind_formed]

theorem executeCleanupTerm_formed (machine : State) (context : Context) (after : Transition)
    (formed : Formed machine.heap)
    (accepted : executeCleanupTerm machine context = .ok after) : Formed after.state.heap := by
  unfold executeCleanupTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact installProtection_formed _ _ _ _ _ _ _ _ formed accepted
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, ⟨middle, owner⟩, temporaryOk, rfl⟩ := accepted
    have next := temporary_formed formed temporaryOk
    exact next

end ScopeTree
end BoundaryV2.Profile.Source.Machine
