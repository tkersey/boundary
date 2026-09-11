import BoundaryV2.SourceTokenLifetime

namespace BoundaryV2.Profile.Source.Machine
namespace TokenInventory

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem cleanupFailed_preserves_token_bounds (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : cleanupFailed machine identity invocation outer normal tail inner = .ok after)
    (typed : ValueInventory.All (ValueTokensBounded limit) machine)
    (outerTyped : ∀ value ∈ exitValues outer, ValueTokensBounded limit value)
    (innerTyped : ∀ value ∈ exitValues inner, ValueTokensBounded limit value)
    (normalTyped : ∀ value ∈ normal, ValueTokensBounded limit value.value)
    (tailTyped : ∀ value ∈ tail.flatMap ValueInventory.frame, ValueTokensBounded limit value) :
    ValueInventory.All (ValueTokensBounded limit) after.state := by
  unfold cleanupFailed at accepted
  split at accepted <;> try contradiction
  rename_i failure failed
  have failureTyped : ValueTokensBounded limit failure := innerTyped failure (by simp [exitValues, failed])
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨before, found, ⟨afterRecord, events⟩, completed, rfl⟩ := accepted
  have beforeTyped := ValueInventory.lookup_obligation_preserves_all machine identity before found _ typed
  have recordTyped := ValueInventory.complete_obligation_preserves_all before afterRecord invocation (.error failure) events completed _ beforeTyped
    (by intro value equal; cases equal; exact failureTyped)
  have heapTyped := ValueInventory.set_obligation_preserves_all machine identity.value afterRecord _ typed recordTyped
  have remainingTyped := liveOwned_holdings_preserve_token_bounds
    { machine.heap with obligations := machine.heap.obligations.set identity.value afterRecord } normal.toList
    (by simpa using normalTyped)
  have exitTyped : ∀ value ∈ exitValues (mergeAbrupt outer inner), ValueTokensBounded limit value := by
    intro value member
    rcases List.mem_append.mp (ValueInventory.merge_abrupt_subset outer inner member) with member | member
    · exact outerTyped value member
    · exact innerTyped value member
  simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.afterRelease,
    List.mem_append, List.mem_map] at heapTyped ⊢
  grind only []

theorem installProtection_preserves_token_bounds (machine : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (accepted : installProtection machine context body cleanup arguments resource loan = .ok after)
    (typed : ValueInventory.All (ValueTokensBounded limit) machine)
    (cleanupTyped : ValueTokensBounded limit cleanup.value)
    (argumentsTyped : ∀ value ∈ arguments, ValueTokensBounded limit value.value)
    (resourceTyped : ∀ value ∈ resource, ValueTokensBounded limit value.value) :
    ValueInventory.All (ValueTokensBounded limit) after.state := by
  simp only [installProtection, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨bodyType, _, _, _, _, _, _, _, _, _, store, moved, accepted⟩ := accepted
  have movedTyped := ValueInventory.moveValues_preserves_all machine store _ _ moved _ typed
  let record : Cleanup.Obligation .source := ⟨⟨machine.heap.nextObligation⟩, machine.scope, machine.heap.nextObligation,
    cleanup.value, resource.map Located.value, .pending⟩
  let heap := { store with obligations := store.obligations ++ [record], nextObligation := store.nextObligation + 1 }
  have recordTyped : ∀ value ∈ ValueInventory.obligation record, ValueTokensBounded limit value := by
    simp only [record, ValueInventory.obligation, List.mem_cons, List.mem_append, List.not_mem_nil, or_false]
    intro value member
    rcases member with equal | member
    · cases equal; exact cleanupTyped
    · have found : resource.map Located.value = some value := by simpa using member
      obtain ⟨original, originalMember, rfl⟩ := Option.map_eq_some_iff.mp found
      exact resourceTyped original originalMember
  have heapTyped : ValueInventory.All (ValueTokensBounded limit) { machine with heap := heap } := by
    simp only [heap, ValueInventory.All, ValueInventory.state, ValueInventory.heap,
      List.flatMap_append, List.flatMap_cons, List.flatMap_nil, List.append_nil, List.mem_append] at movedTyped ⊢
    grind only []
  cases resource with
  | none =>
    cases loan <;> try contradiction
    simp only [pure, Except.pure, Except.bind] at accepted
    apply ValueInventory.applyClosure_preserves_all _ _ _ _ _ accepted _ _ argumentsTyped
    simpa only [ValueInventory.All, ValueInventory.state, List.singleton_append, List.flatMap_cons,
      ValueInventory.frame, List.nil_append] using heapTyped
  | some resourceValue =>
    cases loan with
    | none => contradiction
    | some descriptor =>
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      rename_i schema node token valueAt
      simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨borrowSchema, _, _, checked, ⟨afterStore, borrowed⟩, allocated, _, rfl, applied⟩ := accepted
      have shape : context.source.schemas[borrowSchema.value]? = some (.internal (.borrowed resourceValue.value.schema descriptor)) := by
        unfold require at checked
        split at checked <;> try contradiction
        rename_i admitted
        simpa using admitted
      have allocatedTyped := ValueInventory.allocateObject_preserves_all
        { machine with heap := { heap with nextRegion := heap.nextRegion + 1, loans := heap.loans ++ [(⟨heap.nextRegion⟩, ⟨machine.heap.nextObligation⟩)] } }
        afterStore borrowSchema _ _ false borrowed allocated _ heapTyped (by simp [ValueInventory.object])
      have borrowedTyped : ValueTokensBounded limit borrowed.value := by
        rw [ValueInventory.allocateObject_result _ _ _ _ _ _ _ allocated]
        simp [ValueTokensBounded, ownedTokens]
      refine ValueInventory.applyClosure_preserves_all _ _ _ _ _ applied (ValueTokensBounded limit) ?_ ?_
      · simpa only [ValueInventory.All, ValueInventory.state, List.cons_append, List.nil_append,
          List.flatMap_cons, ValueInventory.frame] using allocatedTyped
      · intro child member
        rcases List.mem_cons.mp member with equal | member
        · cases equal; exact borrowedTyped
        · exact argumentsTyped child member

theorem executeCleanupTerm_preserves_token_bounds (machine : State) (context : Context) (after : Transition)
    (accepted : executeCleanupTerm machine context = .ok after)
    (typed : ValueInventory.All (ValueTokensBounded limit) machine) :
    ValueInventory.All (ValueTokensBounded limit) after.state := by
  unfold executeCleanupTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  have inputs : ∀ value ∈ operands, ValueTokensBounded limit value.value := by
    intro value member
    apply typed
    simp only [ValueInventory.state, executing, ValueInventory.control, List.mem_append, List.mem_map]
    grind only []
  cases term <;> simp only at accepted <;> try contradiction
  case protect body cleanup arguments resource loan =>
    split at accepted <;> try contradiction
    rename_i bodyValue cleanupValue rest operandsEqual
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    refine installProtection_preserves_token_bounds _ _ _ _ _ _ _ _ accepted typed (inputs cleanupValue (by simp)) ?_ ?_
    · intro value member
      exact inputs value (by simp [List.mem_of_mem_take member])
    · intro value member
      exact inputs value (by simp [List.mem_of_getElem? member])
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
    have unitTyped : ValueTokensBounded limit (.scalar ⟨index⟩ 0) := by simp [ValueTokensBounded, ownedTokens]
    have valueTyped := inputs value (by simp)
    have middleTyped := ValueInventory.temporary_preserves_all _ _ _ temporaryOk _ typed
    simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.afterRelease,
      List.map_cons, List.map_nil, List.mem_append, List.mem_singleton] at middleTyped ⊢
    grind only []

theorem beginCleanup_preserves_token_bounds (machine : State) (context : Context) (identity : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (accepted : beginCleanup machine context identity exit normal tail = .ok after)
    (typed : ValueInventory.All (ValueTokensBounded limit) machine)
    (exitTyped : ∀ value ∈ exitValues exit, ValueTokensBounded limit value)
    (normalTyped : ∀ value ∈ normal, ValueTokensBounded limit value.value)
    (tailTyped : ∀ value ∈ tail.flatMap ValueInventory.frame, ValueTokensBounded limit value) : ValueInventory.All (ValueTokensBounded limit) after.state := by
  simp only [beginCleanup, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨before, found, _, _, ⟨record, events⟩, begun, signature, _, infoType, _, information, informationAt, result, applied, rfl⟩ := accepted
  have beforeTyped := ValueInventory.lookup_obligation_preserves_all machine identity before found _ typed
  have recordTyped := ValueInventory.begin_obligation_preserves_all before record _ events begun _ beforeTyped
  have heapTyped := ValueInventory.set_obligation_preserves_all machine identity.value record _ typed recordTyped
  have observedTyped : ∀ value ∈ exitValues (observedExit machine exit), ValueTokensBounded limit value :=
    fun value member => exitTyped value (ValueInventory.observed_exit_subset machine exit member)
  have informationTyped := cleanupInformation_preserves context infoType (observedExit machine exit)
    information informationAt observedTyped
  have normalListTyped : ∀ value ∈ normal.toList, ValueTokensBounded limit value.value := by simpa using normalTyped
  apply ValueInventory.applyClosure_preserves_all _ _ _ _ _ applied (ValueTokensBounded limit)
  · simp only [ValueInventory.All, ValueInventory.state, List.flatMap_cons, ValueInventory.frame,
      List.mem_append, List.mem_map] at heapTyped ⊢
    grind only []
  · intro value member
    rcases List.mem_cons.mp member with equal | member
    · cases equal; exact informationTyped
    · obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
      exact recordTyped original (by simp only [ValueInventory.obligation, List.mem_cons, List.mem_append]; exact Or.inl (Or.inr originalMember))

end TokenInventory
end BoundaryV2.Profile.Source.Machine
