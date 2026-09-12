import BoundaryV2.SourceEffectTypes
import BoundaryV2.SourceInformationTypes
import BoundaryV2.SourceLifetimeTypes

namespace BoundaryV2.Profile.Source.Machine

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

namespace ValueInventory

theorem observed_exit_subset (machine : State) (exit : Cleanup.Exit .source) :
    exitValues (observedExit machine exit) ⊆ exitValues exit := by
  unfold observedExit
  cases machine.cancellation
  · exact List.Subset.refl _
  · exact cancel_exit_subset _ _

theorem record_failure_subset (exit : Cleanup.Exit .source) (failure : SemanticValue) (nested : List SemanticValue) :
    exitValues (Cleanup.recordFailure exit failure nested) ⊆ exitValues exit ++ failure :: nested := by
  cases exit with
  | mk primary failures cancellation =>
    cases primary <;> simp only [Cleanup.recordFailure, exitValues, List.nil_append, List.mem_append,
      List.mem_cons, List.not_mem_nil, List.subset_def]
    all_goals grind only []

theorem merge_abrupt_subset (outer inner : Cleanup.Exit .source) :
    exitValues (mergeAbrupt outer inner) ⊆ exitValues outer ++ exitValues inner := by
  unfold mergeAbrupt
  have failureMerge (failure : SemanticValue) (failed : inner.primary = .failure failure) :
      exitValues (Cleanup.recordFailure outer failure inner.failures) ⊆ exitValues outer ++ exitValues inner := by
    simpa only [exitValues, failed, List.singleton_append] using record_failure_subset outer failure inner.failures
  have otherMerge : exitValues { outer with failures := outer.failures ++ inner.failures } ⊆ exitValues outer ++ exitValues inner := by
    cases outer with
    | mk primary failures cancellation =>
      cases primary <;> simp only [exitValues, List.nil_append, List.mem_append, List.mem_cons, List.subset_def]
      all_goals grind only []
  split
  all_goals cases inner.cancellation
  all_goals first
    | exact failureMerge _ ‹_›
    | exact List.Subset.trans (cancel_exit_subset _ _) (failureMerge _ ‹_›)
    | exact otherMerge
    | exact List.Subset.trans (cancel_exit_subset _ _) otherMerge

theorem lookup_obligation_preserves_all (machine : State) (identity : ObligationId) (record : Cleanup.Obligation .source)
    (found : machine.heap.obligations[identity.value]? = some record)
    (property : SemanticValue → Prop) (holds : All property machine) :
    ∀ value ∈ obligation record, property value := by
  have recordMember := List.mem_of_getElem? found
  intro value member
  apply holds
  simp only [state, heap, List.mem_append, List.mem_flatMap]
  grind only []

theorem begin_obligation_preserves_all (before after : Cleanup.Obligation .source) (invocation : InvocationId)
    (events : List Cleanup.Event) (accepted : Cleanup.begin before invocation = some (after, events))
    (property : SemanticValue → Prop) (holds : ∀ value ∈ obligation before, property value) :
    ∀ value ∈ obligation after, property value := by
  unfold Cleanup.begin at accepted
  split at accepted <;> try contradiction
  cases accepted
  simp only [obligation, List.mem_cons, List.mem_append] at holds ⊢
  grind only []

theorem complete_obligation_preserves_all (before after : Cleanup.Obligation .source) (invocation : InvocationId)
    (result : Except SemanticValue Unit) (events : List Cleanup.Event)
    (accepted : Cleanup.complete before invocation result = some (after, events))
    (property : SemanticValue → Prop) (holds : ∀ value ∈ obligation before, property value)
    (failureHolds : ∀ value, result = .error value → property value) :
    ∀ value ∈ obligation after, property value := by
  unfold Cleanup.complete at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases result with
  | ok resultValue =>
    cases resultValue
    cases accepted
    simp only [obligation, List.mem_cons, List.mem_append] at holds ⊢
    grind only []
  | error failure =>
    cases accepted
    have failed := failureHolds failure rfl
    simp only [obligation, List.mem_cons, List.mem_append] at holds ⊢
    grind only []

theorem set_obligation_preserves_all (machine : State) (index : Nat) (record : Cleanup.Obligation .source)
    (property : SemanticValue → Prop) (holds : All property machine)
    (recordHolds : ∀ value ∈ obligation record, property value) :
    All property { machine with heap := { machine.heap with obligations := machine.heap.obligations.set index record } } := by
  simp only [All, state, heap, List.mem_append, List.mem_flatMap] at holds ⊢
  grind only [→ List.mem_or_eq_of_mem_set]

theorem exit_after_preserves_all (exit : Cleanup.Exit .source) (normal : Option Located) (after : AfterRelease)
    (accepted : exitAfter exit normal = .ok after) (property : SemanticValue → Prop)
    (exitHolds : ∀ value ∈ exitValues exit, property value)
    (normalHolds : ∀ value ∈ normal, property value.value) :
    ∀ value ∈ afterRelease after, property value := by
  unfold exitAfter at accepted
  split at accepted
  · simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨value, found, _, _, rfl⟩ := accepted
    simpa only [afterRelease, List.mem_singleton, forall_eq] using normalHolds value found
  · cases accepted; exact exitHolds

theorem finishCleanup_preserves_all (machine : State) (context : Context) (after : Transition)
    (accepted : finishCleanup machine context = .ok after) (property : SemanticValue → Prop)
    (holds : All property machine) : All property after.state := by
  unfold finishCleanup at accepted
  split at accepted <;> try contradiction
  rename_i value delivered
  split at accepted <;> try contradiction
  rename_i identity invocation exit normal tail stacked
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, before, found, ⟨afterRecord, events⟩, completed, release, released, rfl⟩ := accepted
  have beforeHolds := lookup_obligation_preserves_all machine identity before found property holds
  have afterHolds := complete_obligation_preserves_all before afterRecord invocation (.ok ()) events completed property beforeHolds (by simp)
  have heapHolds := set_obligation_preserves_all machine identity.value afterRecord property holds afterHolds
  have tailHolds : ∀ value ∈ tail.flatMap frame, property value := by
    intro value member
    apply holds
    simp [state, stacked, member]
  have frameHolds : ∀ value ∈ frame (.cleanupReturn identity invocation exit normal), property value := by
    intro value member
    apply holds
    simp [state, stacked, member]
  have exitHolds : ∀ value ∈ exitValues (observedExit machine exit), property value := by
    intro value member
    apply frameHolds
    exact List.mem_append_left _ (observed_exit_subset machine exit member)
  have normalHolds : ∀ value ∈ normal, property value.value := by
    intro value member
    apply frameHolds
    simp only [frame, List.mem_append, List.mem_map, Option.mem_toList]
    exact Or.inr ⟨value, member, rfl⟩
  have releaseHolds := exit_after_preserves_all _ _ _ released property exitHolds normalHolds
  apply resumeRelease_preserves_all _ release property _ releaseHolds
  simp only [All, state, List.mem_append] at heapHolds ⊢
  grind only []

end ValueInventory

theorem cleanupFailed_preserves_value_shapes (machine : State) (identity : ObligationId) (invocation : InvocationId)
    (outer : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (inner : Cleanup.Exit .source)
    (after : Transition) (accepted : cleanupFailed machine identity invocation outer normal tail inner = .ok after)
    (typed : ValueInventory.All (ValueShape schemas) machine)
    (outerTyped : ∀ value ∈ exitValues outer, ValueShape schemas value)
    (innerTyped : ∀ value ∈ exitValues inner, ValueShape schemas value)
    (normalTyped : ∀ value ∈ normal, ValueShape schemas value.value)
    (tailTyped : ∀ value ∈ tail.flatMap ValueInventory.frame, ValueShape schemas value) :
    ValueInventory.All (ValueShape schemas) after.state := by
  unfold cleanupFailed at accepted
  split at accepted <;> try contradiction
  rename_i failure failed
  have failureTyped : ValueShape schemas failure := innerTyped failure (by simp [exitValues, failed])
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨before, found, ⟨afterRecord, events⟩, completed, rfl⟩ := accepted
  have beforeTyped := ValueInventory.lookup_obligation_preserves_all machine identity before found _ typed
  have recordTyped := ValueInventory.complete_obligation_preserves_all before afterRecord invocation (.error failure) events completed _ beforeTyped
    (by intro value equal; cases equal; exact failureTyped)
  have heapTyped := ValueInventory.set_obligation_preserves_all machine identity.value afterRecord _ typed recordTyped
  have remainingTyped := liveOwned_holdings_preserve_value_shapes
    { machine.heap with obligations := machine.heap.obligations.set identity.value afterRecord } normal.toList
    (by simpa using normalTyped)
  have exitTyped : ∀ value ∈ exitValues (mergeAbrupt outer inner), ValueShape schemas value := by
    intro value member
    rcases List.mem_append.mp (ValueInventory.merge_abrupt_subset outer inner member) with member | member
    · exact outerTyped value member
    · exact innerTyped value member
  simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.afterRelease,
    List.mem_append, List.mem_map] at heapTyped ⊢
  grind only []

theorem installProtection_preserves_value_shapes (machine : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (accepted : installProtection machine context body cleanup arguments resource loan = .ok after)
    (typed : ValueInventory.All (ValueShape context.source.schemas) machine)
    (cleanupTyped : ValueShape context.source.schemas cleanup.value)
    (argumentsTyped : ∀ value ∈ arguments, ValueShape context.source.schemas value.value)
    (resourceTyped : ∀ value ∈ resource, ValueShape context.source.schemas value.value) :
    ValueInventory.All (ValueShape context.source.schemas) after.state := by
  simp only [installProtection, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨bodyType, _, _, _, _, _, _, _, _, _, store, moved, accepted⟩ := accepted
  have movedTyped := ValueInventory.moveValues_preserves_all machine store _ _ moved _ typed
  let record : Cleanup.Obligation .source := ⟨⟨machine.heap.nextObligation⟩, machine.scope, machine.heap.nextObligation,
    cleanup.value, resource.map Located.value, .pending⟩
  let heap := { store with obligations := store.obligations ++ [record], nextObligation := store.nextObligation + 1 }
  have recordTyped : ∀ value ∈ ValueInventory.obligation record, ValueShape context.source.schemas value := by
    simp only [record, ValueInventory.obligation, List.mem_cons, List.mem_append, List.not_mem_nil, or_false]
    intro value member
    rcases member with equal | member
    · cases equal; exact cleanupTyped
    · have found : resource.map Located.value = some value := by simpa using member
      obtain ⟨original, originalMember, rfl⟩ := Option.map_eq_some_iff.mp found
      exact resourceTyped original originalMember
  have heapTyped : ValueInventory.All (ValueShape context.source.schemas) { machine with heap := heap } := by
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
      have borrowedTyped : ValueShape context.source.schemas borrowed.value := by
        rw [ValueInventory.allocateObject_result _ _ _ _ _ _ _ allocated]
        exact .reference shape rfl
      refine ValueInventory.applyClosure_preserves_all _ _ _ _ _ applied (ValueShape context.source.schemas) ?_ ?_
      · simpa only [ValueInventory.All, ValueInventory.state, List.cons_append, List.nil_append,
          List.flatMap_cons, ValueInventory.frame] using allocatedTyped
      · intro child member
        rcases List.mem_cons.mp member with equal | member
        · cases equal; exact borrowedTyped
        · exact argumentsTyped child member

theorem executeCleanupTerm_preserves_value_shapes (machine : State) (context : Context) (after : Transition)
    (accepted : executeCleanupTerm machine context = .ok after)
    (typed : ValueInventory.All (ValueShape context.source.schemas) machine) :
    ValueInventory.All (ValueShape context.source.schemas) after.state := by
  unfold executeCleanupTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  have inputs : ∀ value ∈ operands, ValueShape context.source.schemas value.value := by
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
    refine installProtection_preserves_value_shapes _ _ _ _ _ _ _ _ accepted typed (inputs cleanupValue (by simp)) ?_ ?_
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
    have unitTyped : ValueShape context.source.schemas (.scalar ⟨index⟩ 0) := .scalar unitShape rfl
    have valueTyped := inputs value (by simp)
    have middleTyped := ValueInventory.temporary_preserves_all _ _ _ temporaryOk _ typed
    simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.afterRelease,
      List.map_cons, List.map_nil, List.mem_append, List.mem_singleton] at middleTyped ⊢
    grind only []

theorem beginCleanup_preserves_value_shapes (machine : State) (context : Context) (identity : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (accepted : beginCleanup machine context identity exit normal tail = .ok after)
    (typed : ValueInventory.All (ValueShape context.source.schemas) machine)
    (exitTyped : ∀ value ∈ exitValues exit, ValueShape context.source.schemas value)
    (normalTyped : ∀ value ∈ normal, ValueShape context.source.schemas value.value)
    (tailTyped : ∀ value ∈ tail.flatMap ValueInventory.frame, ValueShape context.source.schemas value)
    (failureTypes : ∀ value, (observedExit machine exit).primary = .failure value ∨ value ∈ exit.failures →
      ValueShape context.source.schemas value ∧ value.schema = context.source.failure)
    : ValueInventory.All (ValueShape context.source.schemas) after.state := by
  simp only [beginCleanup, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨before, found, _, _, ⟨record, events⟩, begun, signature, _, infoType, _, information, informationAt, result, applied, rfl⟩ := accepted
  have beforeTyped := ValueInventory.lookup_obligation_preserves_all machine identity before found _ typed
  have recordTyped := ValueInventory.begin_obligation_preserves_all before record _ events begun _ beforeTyped
  have heapTyped := ValueInventory.set_obligation_preserves_all machine identity.value record _ typed recordTyped
  have observedTyped : ∀ value ∈ exitValues (observedExit machine exit), ValueShape context.source.schemas value :=
    fun value member => exitTyped value (ValueInventory.observed_exit_subset machine exit member)
  have observedFailures : (observedExit machine exit).failures = exit.failures := by
    unfold observedExit
    cases machine.cancellation <;> rfl
  have informationTyped := cleanupInformation_preserves_value_shapes context infoType (observedExit machine exit)
    information informationAt (by simpa only [observedFailures] using failureTypes)
  have normalListTyped : ∀ value ∈ normal.toList, ValueShape context.source.schemas value.value := by simpa using normalTyped
  apply ValueInventory.applyClosure_preserves_all _ _ _ _ _ applied (ValueShape context.source.schemas)
  · simp only [ValueInventory.All, ValueInventory.state, List.flatMap_cons, ValueInventory.frame,
      List.mem_append, List.mem_map] at heapTyped ⊢
    grind only []
  · intro value member
    rcases List.mem_cons.mp member with equal | member
    · cases equal; exact informationTyped
    · obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
      exact recordTyped original (by simp only [ValueInventory.obligation, List.mem_cons, List.mem_append]; exact Or.inl (Or.inr originalMember))

end BoundaryV2.Profile.Source.Machine
