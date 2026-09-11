import BoundaryV2.SourceIdentityHeap

namespace BoundaryV2.Profile.Source.Machine
namespace IdentitySupport

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem trim_frame_valid (context : Context) (bounded : FrameValid limit frame) :
    FrameValid limit (trimFrame context frame) := by
  cases frame <;> exact bounded

theorem frozen_cells_valid (bounded : HeapValid limit heap) :
    ∀ saved ∈ frozenCells heap regions, FrozenValid limit saved := by
  intro saved member
  obtain ⟨schema, found, _⟩ := (frozen_cells_are_exactly_local _ _ _).mp member
  exact heap_lookup bounded found

theorem openRequest_valid (machine : State) (context : Context) (operation : Operation)
    (operands : List Located) (after : Transition) (bounded : ValidAt limit machine)
    (upper : Upper limit after.state.heap)
    (accepted : openRequest machine context operation operands = .ok after) : ValidAt limit after.state := by
  simp only [openRequest, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨effect, _, _, _, payload, _, _, _, accepted⟩ := accepted
  split at accepted
  · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    exact ⟨bounded.heap, bounded.frames, bounded.control, bounded.scope, bounded.invocation⟩
  · simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, _, accepted⟩ := accepted
    cases stored <;> try contradiction
    rename_i identity nominal lookup
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, selected, selectedAt, definition, _, clause, _, accepted⟩ := accepted
    have reconstructed := selection_reconstructs identity machine.stack selected selectedAt
    have activationBound : ActivationValid limit selected.activation :=
      bounded.frames (.handler selected.activation) (by simp [reconstructed])
    have outsideBound : ∀ frame ∈ selected.outside, FrameValid limit frame := by
      intro frame member
      exact bounded.frames frame (by simp [reconstructed, member])
    have insideBound : ∀ frame ∈ selected.inside.map (trimFrame context), FrameValid limit frame := by
      intro frame member
      obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
      exact trim_frame_valid context (bounded.frames original (by simp [reconstructed, originalMember]))
    split at accepted
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, _, _, invoked⟩ := accepted
      exact invokeFunction_valid _ _ _ _ _ _ bounded upper invoked
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨shape, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      rename_i signature
      obtain ⟨store, moved, accepted⟩ := (except_bind_ok _ _ _).mp accepted
      have moved := (fromOption_ok _ _ _).mp moved
      have storeBound := move_heap bounded.heap moved
      have captureBound : CaptureValid limit
          ⟨clause.resumption, selected.inside.map (trimFrame context), selected.activation,
            (operands.drop operation.capability.toList.length).drop (1 + operation.bodies.length),
            activeRegions (selected.inside.map (trimFrame context)),
            frozenCells store (activeRegions (selected.inside.map (trimFrame context))), machine.scope, machine.invocation⟩ :=
        ⟨insideBound, activationBound, fun _ member => active_regions insideBound member,
          frozen_cells_valid storeBound, bounded.scope, bounded.invocation⟩
      have outsideBound : ValidAt limit {machine with heap := store, stack := selected.outside, scope := selected.activation.scope, invocation := selected.activation.invocation} :=
        ⟨storeBound, outsideBound, bounded.control, activationBound.2.1, activationBound.2.2.1⟩
      split at accepted
      all_goals
        simp only [except_bind_ok, fromOption_ok] at accepted
        try
          obtain ⟨gate, guard, rest⟩ := accepted
          have _ : Unit := gate
          clear guard
          have accepted := rest
        obtain ⟨⟨outside, owner⟩, temporaryOk, ⟨finalStore, token⟩, allocated, staged, stagedOk, invoked⟩ := accepted
        have created := allocate_valid (temporary_valid outsideBound temporaryOk)
          (by first | exact captureBound | (split <;> exact captureBound)) allocated
        exact invokeFunction_valid _ _ _ _ _ _ (finishTemporary_valid created stagedOk) upper invoked

theorem installProtection_valid (machine : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (bounded : ValidAt limit machine) (upper : Upper limit after.state.heap)
    (accepted : installProtection machine context body cleanup arguments resource loan = .ok after) : ValidAt limit after.state := by
  simp only [installProtection, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨bodyType, _, _, _, _, _, _, _, _, _, store, moved, accepted⟩ := accepted
  let record : Cleanup.Obligation .source := ⟨⟨machine.heap.nextObligation⟩, machine.scope, machine.heap.nextObligation,
    cleanup.value, resource.map Located.value, .pending⟩
  let heap := {store with obligations := store.obligations ++ [record], nextObligation := store.nextObligation + 1}
  have seedBound (high : Upper limit heap) : HeapValid limit heap := by
    have fresh : Bound limit record.id := by
      have high := high .obligation
      have growth := (moveValues_allocation _ _ _ _ moved).obligations
      change store.nextObligation + 1 ≤ limit .obligation at high
      exact Nat.lt_of_lt_of_le (Nat.lt_of_le_of_lt growth (Nat.lt_succ_self _)) high
    have storeBound := move_heap bounded.heap moved
    refine ⟨storeBound.objects, storeBound.scopes, storeBound.invocations, ?_, storeBound.loans⟩
    intro obligation member
    rcases List.mem_append.mp member with old | new
    · exact storeBound.obligations obligation old
    · cases List.mem_singleton.mp new
      exact ⟨fresh, bounded.scope, trivial⟩
  have freshBound (high : Upper limit heap) : Bound limit (⟨machine.heap.nextObligation⟩ : ObligationId) := by
    have high := high .obligation
    have growth := (moveValues_allocation _ _ _ _ moved).obligations
    change store.nextObligation + 1 ≤ limit .obligation at high
    exact Nat.lt_of_lt_of_le (Nat.lt_of_le_of_lt growth (Nat.lt_succ_self _)) high
  cases resource with
  | none =>
    cases loan <;> try contradiction
    simp only [pure, Except.pure, Except.bind] at accepted
    have high := upper_before (applyClosure_allocation _ _ _ _ _ accepted).heap upper
    apply applyClosure_valid _ _ _ _ _ ?_ upper accepted
    refine ⟨seedBound high, ?_, bounded.control, bounded.scope, bounded.invocation⟩
    intro frame member
    rcases List.mem_cons.mp member with entered | old
    · cases entered; exact freshBound high
    · exact bounded.frames frame old
  | some resourceValue =>
    cases loan with
    | none => contradiction
    | some descriptor =>
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      rename_i schema node token valueAt
      simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨borrowSchema, _, _, _, ⟨afterStore, borrowed⟩, allocated, _, rfl, applied⟩ := accepted
      have high := upper_before ((allocateObject_allocation _ _ _ _ _ _ _ allocated).trans
        (applyClosure_allocation _ _ _ _ _ applied).heap) upper
      have heapHigh : Upper limit heap := by
        intro domain
        have bound := high domain
        cases domain <;> simp only [limits, heap] at bound ⊢ <;> omega
      have regionBound : Bound limit (⟨heap.nextRegion⟩ : RegionInstanceId) := by
        have bound := high .regionInstance
        change heap.nextRegion + 1 ≤ limit .regionInstance at bound
        exact Nat.lt_of_lt_of_le (Nat.lt_succ_self _) bound
      have identityBound := freshBound heapHigh
      have heapBound := seedBound heapHigh
      let middle := {heap with nextRegion := heap.nextRegion + 1, loans := heap.loans ++ [((⟨heap.nextRegion⟩ : RegionInstanceId), (⟨machine.heap.nextObligation⟩ : ObligationId))]}
      have middleBound : HeapValid limit middle := by
        refine ⟨heapBound.objects, heapBound.scopes, heapBound.invocations, heapBound.obligations, ?_⟩
        intro item member
        rcases List.mem_append.mp member with old | new
        · exact heapBound.loans item old
        · cases List.mem_singleton.mp new
          exact ⟨regionBound, identityBound⟩
      have allocatedBound := allocate_heap middleBound (by exact ⟨regionBound, bounded.invocation⟩) allocated
      apply applyClosure_valid _ _ _ _ _ ?_ upper applied
      refine ⟨allocatedBound, ?_, bounded.control, bounded.scope, bounded.invocation⟩
      intro frame member
      simp only [List.cons_append, List.nil_append, List.mem_cons] at member
      rcases member with entered | entered | old
      · cases entered; exact regionBound
      · cases entered; exact identityBound
      · exact bounded.frames frame old

theorem executeEffectTerm_valid (machine : State) (context : Context) (after : Transition)
    (bounded : ValidAt limit machine) (upper : Upper limit after.state.heap)
    (accepted : executeEffectTerm machine context = .ok after) : ValidAt limit after.state := by
  unfold executeEffectTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · exact openRequest_valid _ _ _ _ _ bounded upper accepted
  · split at accepted <;> try contradiction
    exact installHandler_valid _ _ _ _ _ _ _ _ bounded upper accepted
  · split at accepted <;> try contradiction
    exact resumeValue_valid _ _ _ _ _ _ bounded upper accepted
  · split at accepted <;> try contradiction
    exact resumeValue_valid _ _ _ _ _ _ bounded upper accepted
  · split at accepted <;> try contradiction
    exact resumeComputation_valid _ _ _ _ _ bounded upper accepted
  · split at accepted <;> try contradiction
    exact enterRegion_valid _ _ _ _ _ _ bounded upper accepted

end IdentitySupport
end BoundaryV2.Profile.Source.Machine
