import BoundaryV2.SourceOperandStructure

namespace BoundaryV2.Profile.Source.Machine
namespace OperandStructure

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

private theorem foldlM_preserves (items : List β) (step : α → β → Except Invalid α)
    (property : α → Prop) (preserved : ∀ before item after, step before item = .ok after → property before → property after)
    (before after : α) (accepted : items.foldlM step before = .ok after) (holds : property before) : property after := by
  induction items generalizing before with
  | nil => cases accepted; exact holds
  | cons first rest induction =>
    simp only [List.foldlM_cons, bind, except_bind_ok] at accepted
    obtain ⟨middle, stepped, accepted⟩ := accepted
    exact induction middle accepted (preserved before first middle stepped holds)

theorem installHandler_plain (machine : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (bindings : Environment) (after : Transition)
    (accepted : installHandler machine context handler body arguments stored bindings = .ok after)
    (typed : Plain machine) : Plain after.state := by
  simp only [installHandler, bind, except_bind_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, ⟨store, capabilities⟩, allocated, applied⟩ := accepted
  let property (pair : Heap × List Located) : Prop := HeapValid pair.1
  have seedTyped : property ({ machine.heap with nextAttachment := machine.heap.nextAttachment + 1 }, []) := typed.2
  have allTyped := foldlM_preserves _ _ property (by
    intro before item after stepOk beforeTyped
    rcases before with ⟨heap, capabilities⟩
    rcases item with ⟨clause, schema⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at stepOk
    obtain ⟨_, _, ⟨next, value⟩, allocated, rfl⟩ := stepOk
    exact allocateObject_valid _ _ _ _ _ _ _ allocated beforeTyped trivial) _ _ allocated seedTyped
  apply applyClosure_plain _ _ _ _ _ applied
  exact ⟨(noOperands_cons _ _).mpr ⟨(by intro _ _ _ _ unequal; cases unequal), typed.1⟩, allTyped⟩

theorem enterRegion_plain (machine : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition)
    (accepted : enterRegion machine context descriptor body arguments = .ok after) (typed : Plain machine) : Plain after.state := by
  simp only [enterRegion, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, ⟨store, value⟩, allocated, applied⟩ := accepted
  have allocatedTyped := allocateObject_valid { machine.heap with nextRegion := machine.heap.nextRegion + 1 }
    _ _ _ _ _ _ allocated typed.2 trivial
  apply applyClosure_plain _ _ _ _ _ applied
  exact ⟨(noOperands_cons _ _).mpr ⟨(by intro _ _ _ _ unequal; cases unequal), typed.1⟩, allocatedTyped⟩

theorem openRequest_plain (machine : State) (context : Context) (operation : Operation) (operands : List Located)
    (after : Transition) (accepted : openRequest machine context operation operands = .ok after) (typed : Plain machine) :
    Plain after.state := by
  simp only [openRequest, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, accepted⟩ := accepted
  split at accepted
  · simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, rfl⟩ := accepted
    exact typed
  · simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, _, accepted⟩ := accepted
    cases stored <;> try contradiction
    rename_i identity nominal lookup
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, selected, selectedAt, _, _, clause, _, accepted⟩ := accepted
    have reconstructed := selection_reconstructs identity machine.stack selected selectedAt
    have outsideTyped : NoOperands selected.outside := typed.1.subset (by
      intro saved member; simp [reconstructed, member])
    have insideTyped : NoOperands selected.inside := typed.1.subset (by
      intro saved member; simp [reconstructed, member])
    have framesTyped := noOperands_trim _ context insideTyped
    split at accepted
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, _, _, invoked⟩ := accepted
      exact invokeFunction_plain _ _ _ _ _ _ invoked typed
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨shape, shapeAt, accepted⟩ := accepted
      split at accepted <;> try contradiction
      obtain ⟨store, moved, accepted⟩ := (except_bind_ok _ _ _).mp accepted
      have moved : moveValues machine.heap (_ :: _) (Custody.Owner.receiver ⟨machine.heap.nextInvocation⟩) = some store :=
        (fromOption_ok _ _ _).mp moved
      have storeTyped := moveValues_valid _ _ _ _ moved typed.2
      split at accepted
      all_goals
        simp only [except_bind_ok, fromOption_ok] at accepted
        try
          obtain ⟨gate, guard, rest⟩ := accepted
          have _ : Unit := gate
          clear guard
          have accepted := rest
        obtain ⟨⟨outside, owner⟩, temporaryOk, ⟨finalStore, token⟩, allocated, staged, stagedOk, invoked⟩ := accepted
        have outsideShape := temporary_shape _ _ _ temporaryOk
        have outsideTypes : Plain outside := ⟨by simpa only [outsideShape.2.1] using outsideTyped,
          storeTyped.of_objects outsideShape.2.2⟩
        have allocatedTyped := allocateObject_valid _ _ _ _ _ _ _ allocated outsideTypes.2 (by
          try split
          all_goals exact framesTyped)
        have stagedTypes := finishTemporary_plain _ _ _ stagedOk (show Plain { outside with heap := finalStore } from
          ⟨outsideTypes.1, allocatedTyped⟩)
        exact invokeFunction_plain _ _ _ _ _ _ invoked stagedTypes

theorem executeEffectTerm_plain (machine : State) (context : Context) (after : Transition)
    (accepted : executeEffectTerm machine context = .ok after) (typed : Plain machine) : Plain after.state := by
  unfold executeEffectTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · exact openRequest_plain _ _ _ _ _ accepted typed
  all_goals split at accepted <;> try contradiction
  all_goals first
    | exact installHandler_plain _ _ _ _ _ _ _ _ accepted typed
    | exact resumeValue_plain _ _ _ _ _ _ accepted typed
    | exact resumeComputation_plain _ _ _ _ _ accepted typed
    | exact enterRegion_plain _ _ _ _ _ _ accepted typed


theorem installProtection_plain (machine : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (accepted : installProtection machine context body cleanup arguments resource loan = .ok after)
    (typed : Plain machine) : Plain after.state := by
  simp only [installProtection, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨bodyType, _, _, _, _, _, _, _, _, _, store, moved, accepted⟩ := accepted
  have movedTyped := moveValues_valid _ _ _ _ moved typed.2
  let record : Cleanup.Obligation .source := ⟨⟨machine.heap.nextObligation⟩, machine.scope, machine.heap.nextObligation,
    cleanup.value, resource.map Located.value, .pending⟩
  let heap := { store with obligations := store.obligations ++ [record], nextObligation := store.nextObligation + 1 }
  have heapTyped : HeapValid heap := movedTyped
  cases resource with
  | none =>
    cases loan <;> try contradiction
    simp only [pure, Except.pure, Except.bind] at accepted
    apply applyClosure_plain _ _ _ _ _ accepted
    exact ⟨(noOperands_cons _ _).mpr ⟨by simp, typed.1⟩, heapTyped⟩
  | some resourceValue =>
    cases loan with
    | none => contradiction
    | some descriptor =>
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, ⟨afterStore, borrowed⟩, allocated, _, rfl, applied⟩ := accepted
      have allocatedTyped := allocateObject_valid
        { heap with nextRegion := heap.nextRegion + 1, loans := heap.loans ++ [(⟨heap.nextRegion⟩, ⟨machine.heap.nextObligation⟩)] }
        _ _ _ _ _ _ allocated heapTyped trivial
      apply applyClosure_plain _ _ _ _ _ applied
      refine ⟨?_, allocatedTyped⟩
      simp only [List.cons_append, List.nil_append, noOperands_cons]
      exact ⟨by simp, by simp, typed.1⟩

theorem beginCleanup_plain (machine : State) (context : Context) (identity : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (accepted : beginCleanup machine context identity exit normal tail = .ok after)
    (typed : HeapValid machine.heap) (tailTyped : NoOperands tail) : Plain after.state := by
  simp only [beginCleanup, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, ⟨_, _⟩, _, _, _, _, _, _, _, transition, applied, rfl⟩ := accepted
  apply applyClosure_plain _ _ _ _ _ applied
  exact ⟨(noOperands_cons _ _).mpr ⟨by simp, tailTyped⟩, typed⟩

theorem resumeRelease_plain (machine : State) (after : AfterRelease) (typed : Plain machine) :
    Plain (resumeRelease machine after).state := by
  cases after <;> exact typed

theorem finishCleanup_plain (machine : State) (context : Context) (after : Transition)
    (accepted : finishCleanup machine context = .ok after) (typed : Plain machine) : Plain after.state := by
  unfold finishCleanup at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i identity invocation exit normal tail stacked
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, ⟨_, _⟩, _, _, _, rfl⟩ := accepted
  apply resumeRelease_plain
  exact ⟨(noOperands_cons _ _).mp (by simpa only [stacked] using typed.1) |>.2, typed.2⟩

theorem cleanupFailed_plain (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : cleanupFailed machine identity invocation outer normal tail inner = .ok after)
    (typed : HeapValid machine.heap) (tailTyped : NoOperands tail) : Plain after.state := by
  unfold cleanupFailed at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, ⟨_, _⟩, _, rfl⟩ := accepted
  exact ⟨tailTyped, typed⟩

theorem releaseScope_plain (machine : State) (after : Transition)
    (accepted : releaseScope machine = .ok after) (typed : Plain machine) : Plain after.state := by
  unfold releaseScope at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact typed

theorem executeCleanupTerm_plain (machine : State) (context : Context) (after : Transition)
    (accepted : executeCleanupTerm machine context = .ok after) (typed : Plain machine) : Plain after.state := by
  unfold executeCleanupTerm at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact installProtection_plain _ _ _ _ _ _ _ _ accepted typed
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, ⟨middle, owner⟩, temporaryOk, rfl⟩ := accepted
    have middleTyped := temporary_plain _ _ _ temporaryOk typed
    exact middleTyped

theorem discardValues_plain (machine : State) (context : Context) (after : Transition)
    (accepted : discardValues machine context = .ok after) (typed : Plain machine) : Plain after.state := by
  unfold discardValues at accepted
  split at accepted <;> try contradiction
  split at accepted
  · cases accepted; exact resumeRelease_plain _ _ typed
  · split at accepted
    · cases accepted; exact typed
    · simp only [bind, except_bind_ok] at accepted
      obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
      have storedTyped := lookupObject_valid _ _ _ _ looked typed.2
      cases stored <;> try contradiction
      all_goals
        simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨store, retired, rfl⟩ := accepted
        have heapTyped := retireObject_valid _ _ _ retired typed.2
      all_goals first
        | exact ⟨typed.1, heapTyped⟩
        | (refine ⟨?_, heapTyped⟩
           simp only [Plain, ObjectValid, NoOperands, List.mem_append, List.mem_cons,
             List.not_mem_nil, or_false] at typed storedTyped ⊢
           grind only [])

end OperandStructure
end BoundaryV2.Profile.Source.Machine
