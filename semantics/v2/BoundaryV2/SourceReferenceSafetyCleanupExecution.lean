import BoundaryV2.SourceReferenceSafetyProtection

namespace BoundaryV2.Profile.Source.Machine
namespace ReferenceSafety
open ReferenceContracts

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem cleanupFailed_valid (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : cleanupFailed machine identity invocation outer normal tail inner = .ok after)
    (good : Valid schemas machine)
    (outerTyped : ∀ value ∈ exitValues outer, ValueGood schemas machine.heap value)
    (innerTyped : ∀ value ∈ exitValues inner, ValueGood schemas machine.heap value)
    (normalTyped : ∀ value ∈ normal, ValueGood schemas machine.heap value.value)
    (tailTyped : ∀ value ∈ tail.flatMap ValueInventory.frame, ValueGood schemas machine.heap value) :
    Valid schemas after.state := by
  have typed := good.values
  unfold cleanupFailed at accepted
  split at accepted <;> try contradiction
  rename_i failure failed
  have failureTyped : ValueGood schemas machine.heap failure := innerTyped failure (by simp [exitValues, failed])
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨before, found, ⟨afterRecord, events⟩, completed, rfl⟩ := accepted
  have beforeTyped := ValueInventory.lookup_obligation_preserves_all machine identity before found _ typed
  have recordTyped := ValueInventory.complete_obligation_preserves_all before afterRecord invocation (.error failure) events completed _ beforeTyped
    (by intro value equal; cases equal; exact failureTyped)
  have heapTyped := ValueInventory.set_obligation_preserves_all machine identity.value afterRecord _ typed recordTyped
  have remainingTyped := liveOwned_holdings_good
    { machine.heap with obligations := machine.heap.obligations.set identity.value afterRecord } machine.heap normal.toList
    (by simpa using normalTyped)
  have exitTyped : ∀ value ∈ exitValues (mergeAbrupt outer inner), ValueGood schemas machine.heap value := by
    intro value member
    rcases List.mem_append.mp (ValueInventory.merge_abrupt_subset outer inner member) with member | member
    · exact outerTyped value member
    · exact innerTyped value member
  refine ⟨?_, good.live⟩
  intro value member
  apply fields_value machine.heap _ _ rfl rfl rfl
  simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.afterRelease,
    List.mem_append, List.mem_map] at heapTyped member
  grind only []

theorem cleanupAbandoned_valid (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : cleanupAbandoned machine identity invocation outer normal tail inner = .ok after)
    (good : Valid schemas machine)
    (outerTyped : ∀ value ∈ exitValues outer, ValueGood schemas machine.heap value)
    (innerTyped : ∀ value ∈ exitValues inner, ValueGood schemas machine.heap value)
    (normalTyped : ∀ value ∈ normal, ValueGood schemas machine.heap value.value)
    (tailTyped : ∀ value ∈ tail.flatMap ValueInventory.frame, ValueGood schemas machine.heap value) :
    Valid schemas after.state := by
  have typed := good.values
  simp only [cleanupAbandoned, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, guard, before, found, ⟨afterRecord, events⟩, completed, rfl⟩ := accepted
  clear guard
  have beforeTyped := ValueInventory.lookup_obligation_preserves_all machine identity before found _ typed
  have recordTyped := ValueInventory.complete_obligation_preserves_all before afterRecord invocation (.ok ()) events completed _ beforeTyped
    (by intro value equal; cases equal)
  have heapTyped := ValueInventory.set_obligation_preserves_all machine identity.value afterRecord _ typed recordTyped
  have remainingTyped := liveOwned_holdings_good
    { machine.heap with obligations := machine.heap.obligations.set identity.value afterRecord } machine.heap normal.toList
    (by simpa using normalTyped)
  have exitTyped : ∀ value ∈ exitValues (propagateExit outer inner), ValueGood schemas machine.heap value := by
    intro value member
    rcases List.mem_append.mp (ValueInventory.propagate_exit_subset outer inner member) with member | member
    · exact outerTyped value member
    · exact innerTyped value member
  refine ⟨?_, good.live⟩
  intro value member
  apply fields_value machine.heap _ _ rfl rfl rfl
  simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.afterRelease,
    List.mem_append, List.mem_map] at heapTyped member
  grind only []

theorem finishCleanupUnwind_valid (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : finishCleanupUnwind machine identity invocation outer normal tail inner = .ok after)
    (good : Valid schemas machine)
    (outerTyped : ∀ value ∈ exitValues outer, ValueGood schemas machine.heap value)
    (innerTyped : ∀ value ∈ exitValues inner, ValueGood schemas machine.heap value)
    (normalTyped : ∀ value ∈ normal, ValueGood schemas machine.heap value.value)
    (tailTyped : ∀ value ∈ tail.flatMap ValueInventory.frame, ValueGood schemas machine.heap value) :
    Valid schemas after.state := by
  unfold finishCleanupUnwind at accepted
  split at accepted <;> first
    | exact cleanupFailed_valid _ _ _ _ _ _ _ _ accepted good outerTyped innerTyped normalTyped tailTyped
    | exact cleanupAbandoned_valid _ _ _ _ _ _ _ _ accepted good outerTyped innerTyped normalTyped tailTyped
    | contradiction

theorem finishDisposal_valid (machine : State) (after : Transition)
    (accepted : finishDisposal machine = .ok after) (good : Valid schemas machine) : Valid schemas after.state := by
  have typed := good.values
  unfold finishDisposal at accepted
  split at accepted <;> try contradiction
  rename_i value executing
  split at accepted <;> try contradiction
  rename_i remaining release invocation scope tail stacked
  have valueTyped : ValueGood schemas machine.heap value.value := by
    apply typed
    simp [ValueInventory.state, executing, ValueInventory.control]
  have ownedTyped := liveOwnedValue_good machine.heap machine.heap value.owner value.value valueTyped
  cases accepted
  refine ⟨?_, good.live⟩
  simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.frame,
    executing, stacked, List.flatMap_cons, List.mem_append, List.map_append, List.mem_map,
    List.mem_cons, List.not_mem_nil] at typed ⊢
  grind only [liveOwned]

theorem executeCleanupTerm_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executeCleanupTerm machine context = .ok after)
    (good : Valid context.source.schemas machine)
    (modes : ValueInventory.All (ValueModes context.source.schemas) machine) : Valid context.source.schemas after.state := by
  have typed := good.values
  unfold executeCleanupTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  have inputs : ∀ value ∈ operands, ValueGood context.source.schemas machine.heap value.value := by
    intro value member
    apply typed
    simp only [ValueInventory.state, executing, ValueInventory.control, List.mem_append, List.mem_map]
    grind only []
  have inputModes : ∀ value ∈ operands, ValueModes context.source.schemas value.value := by
    intro value member
    apply modes
    simp only [ValueInventory.state, executing, ValueInventory.control, List.mem_append, List.mem_map]
    grind only []
  cases term <;> simp only at accepted <;> try contradiction
  case protect body cleanup arguments resource loan =>
    split at accepted <;> try contradiction
    rename_i bodyValue cleanupValue rest operandsEqual
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    refine installProtection_valid _ _ _ _ _ _ _ _ accepted good modes
      ⟨inputs bodyValue (by simp), inputModes bodyValue (by simp)⟩
      ⟨inputs cleanupValue (by simp), inputModes cleanupValue (by simp)⟩ ?_ ?_
    · intro value member
      exact ⟨inputs value (by simp [List.mem_of_mem_take member]), inputModes value (by simp [List.mem_of_mem_take member])⟩
    · intro value member
      exact ⟨inputs value (by simp [List.mem_of_getElem? member]), inputModes value (by simp [List.mem_of_getElem? member])⟩
  case dispose token =>
    split at accepted <;> try contradiction
    rename_i value operandsEqual
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨shape, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, index, found, ⟨middle, owner⟩, temporaryOk, rfl⟩ := accepted
    obtain ⟨bound, isUnit, _⟩ := List.findIdx?_eq_some_iff_getElem.mp found
    have unitShape : context.source.schemas[index]? = some .unit := by
      rw [List.getElem?_eq_getElem bound]
      congr 1
      simpa using isUnit
    have unitTyped := scalar_good context.source.schemas middle.heap (⟨index⟩ : SchemaId .source) 0
    have valueTyped := temporary_value _ _ _ _ temporaryOk (inputs value (by simp))
    have middleGood := temporary_valid _ _ _ temporaryOk good
    have middleTyped := middleGood.values
    refine ⟨?_, middleGood.live⟩
    simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.afterRelease,
      List.map_cons, List.map_nil, List.mem_append, List.mem_singleton] at middleTyped ⊢
    grind only []


end ReferenceSafety
end BoundaryV2.Profile.Source.Machine
