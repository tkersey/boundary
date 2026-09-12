import BoundaryV2.SourceDisposalCapture

namespace BoundaryV2.Profile.Source.Machine
namespace DisposalShape
open DisposalProgress

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem Valid.tail {tail : List Frame} (valid : Valid machine) (stacked : machine.stack = saved :: tail) :
    ∀ value ∈ tail.flatMap frame, Leaf value := by
  intro value member
  apply valid.2.1
  simp [stacked, member]

theorem liveOwned_list (heap : Heap) (values : List Located) :
    ∀ value ∈ values.flatMap (liveOwned heap), Leaf value := by
  intro value member
  obtain ⟨original, _, present⟩ := List.mem_flatMap.mp member
  exact liveOwned_leaves _ _ _ present

theorem resumeRelease_valid (machine : State) (after : AfterRelease) (valid : Valid machine) :
    Valid (resumeRelease machine after).state := by
  cases after <;> exact ⟨by simp [control, resumeRelease], valid.2⟩

theorem finishCleanup_valid (machine : State) (context : Context) (after : Transition)
    (accepted : finishCleanup machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold finishCleanup at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i identity invocation exit normal tail stacked
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, ⟨_, _⟩, _, _, _, rfl⟩ := accepted
  apply resumeRelease_valid
  exact ⟨valid.1, valid.tail stacked, valid.2.2⟩

theorem cleanupFailed_valid (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : cleanupFailed machine identity invocation outer normal tail inner = .ok after)
    (valid : HeapValid machine.heap) (tailValid : ∀ value ∈ tail.flatMap frame, Leaf value) : Valid after.state := by
  unfold cleanupFailed at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, ⟨_, _⟩, _, rfl⟩ := accepted
  exact ⟨liveOwned_list _ _, tailValid, valid⟩

theorem cleanupAbandoned_valid (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : cleanupAbandoned machine identity invocation outer normal tail inner = .ok after)
    (valid : HeapValid machine.heap) (tailValid : ∀ value ∈ tail.flatMap frame, Leaf value) : Valid after.state := by
  simp only [cleanupAbandoned, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  exact ⟨liveOwned_list _ _, tailValid, valid⟩

theorem finishCleanupUnwind_valid (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : finishCleanupUnwind machine identity invocation outer normal tail inner = .ok after)
    (valid : HeapValid machine.heap) (tailValid : ∀ value ∈ tail.flatMap frame, Leaf value) : Valid after.state := by
  unfold finishCleanupUnwind at accepted
  split at accepted <;> first
    | exact cleanupFailed_valid _ _ _ _ _ _ _ _ accepted valid tailValid
    | exact cleanupAbandoned_valid _ _ _ _ _ _ _ _ accepted valid tailValid
    | contradiction

theorem finishDisposal_valid (machine : State) (after : Transition)
    (accepted : finishDisposal machine = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold finishDisposal at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i remaining release invocation scope tail stacked
  have remainingValid : ∀ value ∈ remaining, Leaf value := by
    intro value member
    apply valid.2.1
    simp [stacked, frame, member]
  cases accepted
  exact ⟨List.forall_mem_append.mpr ⟨liveOwned_leaves _ _, remainingValid⟩, valid.tail stacked, valid.2.2⟩

theorem releaseScope_valid (machine : State) (after : Transition)
    (accepted : releaseScope machine = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold releaseScope at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact ⟨liveOwned_list _ _, valid.2⟩

theorem resumption_leaf (source : Module) (value : Located) (signature : ResumptionType .source)
    (shape : ValueShape source.schemas value.value)
    (declared : source.schemas[value.value.schema.value]? = some (.internal (.resumption signature)))
    (use : signature.use ≠ .multi) : Leaf value := by
  rcases value with ⟨value, owner⟩
  cases shape <;> try grind only [Profile.Value.schema, Profile.Value.scalarValid, Profile.Value.blobValid, Profile.Value.sequenceLengthValid]
  case scalar found checked =>
    simp only [Profile.Value.schema] at declared
    rw [declared] at found
    cases found
    simp [Profile.Value.scalarValid, Scalars.integerType] at checked
  case blob found checked =>
    simp only [Profile.Value.schema] at declared
    rw [declared] at found
    cases found
    simp [Profile.Value.blobValid, Profile.Value.blobMaximum] at checked
  case reference found owned =>
    rename_i inner node token schema
    simp only [Profile.Value.schema] at declared
    rw [found] at declared
    cases declared
    cases token with
    | none => simp [ReferenceOwnership, use] at owned
    | some token => exact ⟨schema, node, token, rfl⟩

theorem executeCleanupTerm_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executeCleanupTerm machine context = .ok after) (valid : Valid machine)
    (shapes : ValueInventory.All (ValueShape context.source.schemas) machine) : Valid after.state := by
  unfold executeCleanupTerm at accepted
  split at accepted <;> try contradiction
  rename_i authored bindings operands executing
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  · split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact installProtection_valid _ _ _ _ _ _ _ _ accepted valid
  · split at accepted <;> try contradiction
    rename_i value matched
    have shape : ValueShape context.source.schemas value.value := by
      apply shapes
      simp [ValueInventory.state, executing, ValueInventory.control]
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, declared, accepted⟩ := accepted
    split at accepted <;> try contradiction
    rename_i signature
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, useOk, _, _, ⟨middle, owner⟩, temporaryOk, rfl⟩ := accepted
    have use : signature.use ≠ .multi := by
      intro multi
      simp [require, multi] at useOk
    have leaf := resumption_leaf context.source value signature shape declared use
    have middleValid := temporary_valid _ _ _ temporaryOk valid
    exact ⟨by simpa [control] using leaf, middleValid.2⟩

theorem discardValues_valid (machine : State) (context : Context) (after : Transition)
    (accepted : discardValues machine context = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold discardValues at accepted
  split at accepted <;> try contradiction
  rename_i values released executing
  split at accepted
  · cases accepted; exact resumeRelease_valid _ _ valid
  · rename_i value rest
    have restValid : ∀ item ∈ rest, Leaf item := by
      intro item member
      apply valid.1
      simp [control, executing, member]
    split at accepted
    · cases accepted; exact ⟨restValid, valid.2⟩
    · simp only [bind, except_bind_ok] at accepted
      obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
      have storedValid := lookupObject_valid _ _ _ _ looked valid.2.2
      cases stored <;> try contradiction
      all_goals
        simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
        obtain ⟨store, retired, rfl⟩ := accepted
        have heapValid := retire_valid _ _ _ retired valid.2.2
      case oneShot saved =>
        refine ⟨by simp [control], ?_, heapValid⟩
        simp only [object] at storedValid
        simpa only [List.flatMap_append, List.flatMap_cons, List.flatMap_nil, frame, List.nil_append,
          List.append_nil, List.append_assoc] using
          List.forall_mem_append.mpr ⟨storedValid, List.forall_mem_append.mpr ⟨restValid, valid.2.1⟩⟩
      case closure schema function bindings =>
        refine ⟨List.forall_mem_append.mpr ⟨?_, restValid⟩, valid.2.1, heapValid⟩
        intro item member
        obtain ⟨binding, _, present⟩ := List.mem_flatMap.mp member
        exact liveOwned_leaves _ _ _ present
      case package => exact ⟨List.forall_mem_append.mpr ⟨liveOwned_leaves _ _, restValid⟩, valid.2.1, heapValid⟩
      case resource => exact ⟨restValid, valid.2.1, heapValid⟩

end DisposalShape
end BoundaryV2.Profile.Source.Machine
