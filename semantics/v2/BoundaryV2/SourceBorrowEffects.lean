import BoundaryV2.SourceBorrowControl

namespace BoundaryV2.Profile.Source.Machine
namespace BorrowRegistry

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

theorem openRequest_valid (machine : State) (context : Context) (operation : Operation)
    (operands : List Located) (after : Transition)
    (accepted : openRequest machine context operation operands = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  simp only [openRequest, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨effect, _, _, _, payload, _, _, _, accepted⟩ := accepted
  split at accepted
  · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    exact valid
  · simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, _, accepted⟩ := accepted
    cases stored <;> try contradiction
    rename_i identity nominal looked
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, selected, selectedAt, definition, _, clause, _, accepted⟩ := accepted
    split at accepted
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, _, _, invoked⟩ := accepted
      exact invokeFunction_valid _ _ _ _ _ _ invoked valid
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨shape, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      rename_i signature shapeAt
      obtain ⟨store, moved, accepted⟩ := (except_bind_ok _ _ _).mp accepted
      have moved := (fromOption_ok _ _ _).mp moved
      have storeValid := move_valid _ _ _ _ moved valid
      split at accepted
      all_goals
        simp only [except_bind_ok, fromOption_ok] at accepted
        try
          obtain ⟨gate, guard, rest⟩ := accepted
          have _ : Unit := gate
          clear guard
          have accepted := rest
        obtain ⟨⟨outside, owner⟩, reserved, ⟨finalStore, token⟩, allocated, staged, stagedOk, invoked⟩ := accepted
        have temporaryValid := temporary_valid _ _ _ reserved storeValid
        have created := allocate_valid _ _ _ _ _ _ _ allocated temporaryValid (by first | trivial | (split <;> trivial))
        have stagedValid := finishTemporary_valid _ _ _ stagedOk created
        exact invokeFunction_valid _ _ _ _ _ _ invoked stagedValid

private theorem foldlM_preserves (items : List β) (step : α → β → Except Invalid α)
    (property : α → Prop) (preserved : ∀ before item after, step before item = .ok after → property before → property after)
    (before after : α) (accepted : items.foldlM step before = .ok after) (holds : property before) : property after := by
  induction items generalizing before with
  | nil => cases accepted; exact holds
  | cons item items induction =>
    simp only [List.foldlM_cons, bind, except_bind_ok] at accepted
    obtain ⟨middle, stepped, rest⟩ := accepted
    exact induction middle rest (preserved before item middle stepped holds)

theorem installHandler_valid (machine : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (bindings : Environment) (after : Transition)
    (accepted : installHandler machine context handler body arguments stored bindings = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  simp only [installHandler, bind, except_bind_ok] at accepted
  obtain ⟨definition, _, _, _, _, _, _, _, signature, _, _, _, ⟨store, capabilities⟩, allocated, applied⟩ := accepted
  have heap : Valid store := by
    apply foldlM_preserves _ _ (fun pair : Heap × List Located => Valid pair.1) ?_ _ _ allocated valid
    intro before item after accepted formed
    rcases before with ⟨heap, capabilities⟩
    rcases item with ⟨clause, schema⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, ⟨next, value⟩, allocated, rfl⟩ := accepted
    exact allocate_valid heap _ _ _ _ _ _ allocated formed (by trivial)
  exact applyClosure_valid _ _ _ _ _ applied heap

theorem completeHandler_valid (machine : State) (context : Context) (after : Transition)
    (accepted : completeHandler machine context = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  unfold completeHandler at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i active tail stacked
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact valid

theorem enterRegion_valid (machine : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition)
    (accepted : enterRegion machine context descriptor body arguments = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  simp only [enterRegion, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, signature, _, schema, _, _, _, ⟨heap, value⟩, allocated, applied⟩ := accepted
  have seed : Valid {machine.heap with nextRegion := machine.heap.nextRegion + 1} := valid
  have next := allocate_valid _ _ _ _ _ _ _ allocated seed (by trivial)
  exact applyClosure_valid _ _ _ _ _ applied next

theorem executeEffectTerm_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executeEffectTerm machine context = .ok after) (valid : Valid machine.heap) : Valid after.state.heap := by
  unfold executeEffectTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · exact openRequest_valid _ _ _ _ _ accepted valid
  · split at accepted <;> try contradiction
    exact installHandler_valid _ _ _ _ _ _ _ _ accepted valid
  · split at accepted <;> try contradiction
    exact resumeValue_valid _ _ _ _ _ _ accepted valid
  · split at accepted <;> try contradiction
    exact resumeValue_valid _ _ _ _ _ _ accepted valid
  · split at accepted <;> try contradiction
    exact resumeComputation_valid _ _ _ _ _ accepted valid
  · split at accepted <;> try contradiction
    exact enterRegion_valid _ _ _ _ _ _ accepted valid


theorem installProtection_valid (machine : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (accepted : installProtection machine context body cleanup arguments resource loan = .ok after) (valid : Valid machine.heap)
    (bounded : IdentitySupport.Valid machine) : Valid after.state.heap := by
  simp only [installProtection, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, indexAt, store, moved, accepted⟩ := accepted
  let identity : ObligationId := ⟨machine.heap.nextObligation⟩
  let obligation : Cleanup.Obligation .source := ⟨identity, machine.scope, identity.value,
    cleanup.value, resource.map Located.value, .pending⟩
  let kept := {store with obligations := store.obligations ++ [obligation], nextObligation := store.nextObligation + 1}
  have movedValid := move_valid _ _ _ _ moved valid
  have next : Valid kept := same_objects_valid _ _ movedValid (append_obligation_tables store obligation) rfl
  cases resource with
  | none =>
    cases loan <;> try contradiction
    simp only [pure, Except.pure, Except.bind] at accepted
    exact applyClosure_valid _ _ _ _ _ accepted next
  | some value =>
    cases loan with
    | none => contradiction
    | some descriptor =>
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      rename_i valueSchema node token reference
      simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨borrowSchema, _, _, _, ⟨afterStore, borrowed⟩, allocated, _, rfl, applied⟩ := accepted
      let seedHeap : Heap := {kept with nextRegion := kept.nextRegion + 1, loans := kept.loans ++ [(⟨kept.nextRegion⟩, identity)]}
      have seed : Valid seedHeap := same_objects_valid _ _ next (append_loan_tables kept (⟨kept.nextRegion⟩, identity)) rfl
      have new : ObjectValid seedHeap (.borrow borrowSchema node ⟨kept.nextRegion⟩ machine.invocation) := by
        have parts := moved
        simp only [moveValues, bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at parts
        obtain ⟨_, _, sameStore⟩ := parts
        have storeLoans : store.loans = machine.heap.loans := by simpa only using congrArg Heap.loans sameStore.symm
        have storeRegion : store.nextRegion = machine.heap.nextRegion := by simpa only using congrArg Heap.nextRegion sameStore.symm
        have storeObligations : store.obligations = machine.heap.obligations := by simpa only using congrArg Heap.obligations sameStore.symm
        have fresh : (store.loans.find? (fun entry => entry.1 == (⟨store.nextRegion⟩ : RegionInstanceId))) = none := by
          apply List.find?_eq_none.mpr
          intro pair member
          have below := (bounded.heap.loans pair (storeLoans ▸ member)).1
          have different : pair.1 ≠ (⟨store.nextRegion⟩ : RegionInstanceId) := by
            intro same
            have equal := congrArg Ref.value same
            change pair.1.value < machine.heap.nextRegion at below
            change pair.1.value = store.nextRegion at equal
            rw [storeRegion] at equal
            omega
          simpa using different
        have size : machine.heap.nextObligation = machine.heap.obligations.length := by simpa using require_ok _ _ _ indexAt
        refine ⟨identity, obligation, valueSchema, token, ?_, ?_, ?_⟩
        · simp only [seedHeap, kept, List.find?_append, fresh, Option.or, List.find?_cons, beq_self_eq_true,
            Option.map_some]
        · simp [seedHeap, kept, identity, storeObligations, size]
        · simp only [obligation, Option.map_some, reference]
      have created := allocate_valid _ _ _ _ _ _ _ allocated seed new
      exact applyClosure_valid _ _ _ _ _ applied created

end BorrowRegistry
end BoundaryV2.Profile.Source.Machine
