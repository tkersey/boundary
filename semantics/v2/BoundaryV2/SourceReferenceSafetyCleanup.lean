import BoundaryV2.SourceReferenceSafetyRelease

namespace BoundaryV2.Profile.Source.Machine
namespace ReferenceSafety
open ReferenceContracts

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem cleanupInformation_good (context : Context) (heap : Heap) (schema : SchemaId .source)
    (exit : Cleanup.Exit .source) (information : SemanticValue)
    (accepted : cleanupInformation context schema exit = .ok information)
    (holds : ∀ value ∈ exitValues exit, ValueGood context.source.schemas heap value) :
    ValueGood context.source.schemas heap information := by
  refine ⟨cleanupInformation_preserves_references _ _ _ _ accepted _ (fun value member => (holds value member).1), ?_, ?_⟩
  · apply (referencesSatisfy_alignment heap.custody information).mp
    exact cleanupInformation_preserves_references _ _ _ _ accepted _
      (fun value member => (referencesSatisfy_alignment _ _).mpr (holds value member).2.1)
  · exact TokenInventory.cleanupInformation_preserves _ _ _ _ accepted (fun value member => (holds value member).2.2)

theorem cleanupInformation_modes (context : Context) (schema : SchemaId .source)
    (exit : Cleanup.Exit .source) (information : SemanticValue)
    (accepted : cleanupInformation context schema exit = .ok information)
    (holds : ∀ value ∈ exitValues exit, ValueModes context.source.schemas value) :
    ValueModes context.source.schemas information := cleanupInformation_preserves_references _ _ _ _ accepted _ holds

theorem beginCleanup_valid (machine : State) (context : Context) (identity : ObligationId)
    (exit : Cleanup.Exit .source) (normal : Option Located) (tail : List Frame) (after : Transition)
    (accepted : beginCleanup machine context identity exit normal tail = .ok after)
    (good : Valid context.source.schemas machine)
    (modes : ValueInventory.All (ValueModes context.source.schemas) machine)
    (exitTyped : ∀ value ∈ exitValues exit, ValueGood context.source.schemas machine.heap value ∧ ValueModes context.source.schemas value)
    (normalTyped : ∀ value ∈ normal, ValueGood context.source.schemas machine.heap value.value ∧ ValueModes context.source.schemas value.value)
    (tailTyped : ∀ value ∈ tail.flatMap ValueInventory.frame, ValueGood context.source.schemas machine.heap value ∧ ValueModes context.source.schemas value) :
    Valid context.source.schemas after.state := by
  have typed : ValueInventory.All (fun value => ValueGood context.source.schemas machine.heap value ∧ ValueModes context.source.schemas value) machine :=
    fun value member => ⟨good.values value member, modes value member⟩
  simp only [beginCleanup, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨before, found, _, _, ⟨record, events⟩, begun, signature, _, infoType, _, information, informationAt, result, applied, rfl⟩ := accepted
  have beforeTyped := ValueInventory.lookup_obligation_preserves_all machine identity before found _ typed
  have recordTyped := ValueInventory.begin_obligation_preserves_all before record _ events begun _ beforeTyped
  have heapTyped := ValueInventory.set_obligation_preserves_all machine identity.value record _ typed recordTyped
  have observedTyped : ∀ value ∈ exitValues (observedExit machine exit),
      ValueGood context.source.schemas machine.heap value ∧ ValueModes context.source.schemas value :=
    fun value member => exitTyped value (ValueInventory.observed_exit_subset machine exit member)
  have infoGood := cleanupInformation_good context machine.heap infoType (observedExit machine exit)
    information informationAt (fun value member => (observedTyped value member).1)
  have infoModes := cleanupInformation_modes context infoType (observedExit machine exit)
    information informationAt (fun value member => (observedTyped value member).2)
  have normalListTyped : ∀ value ∈ normal.toList,
      ValueGood context.source.schemas machine.heap value.value ∧ ValueModes context.source.schemas value.value := by simpa using normalTyped
  let framed := {machine with
    heap := {machine.heap with obligations := machine.heap.obligations.set identity.value record}
    stack := .cleanupReturn identity ⟨machine.heap.nextInvocation⟩ (observedExit machine exit) normal :: tail}
  have frameGood : Valid context.source.schemas framed := by
    refine ⟨?_, good.live⟩
    intro value member
    apply fields_value machine.heap framed.heap value rfl rfl rfl
    simp only [framed, ValueInventory.state, List.flatMap_cons, ValueInventory.frame,
      List.mem_append, List.mem_map] at member
    simp only [ValueInventory.All, ValueInventory.state, List.mem_append] at heapTyped
    grind only []
  have frameModes : ValueInventory.All (ValueModes context.source.schemas) framed := by
    simp only [framed, ValueInventory.All, ValueInventory.state, List.flatMap_cons, ValueInventory.frame,
      List.mem_append, List.mem_map] at heapTyped ⊢
    grind only []
  have cleanupTyped := recordTyped record.cleanup (by simp [ValueInventory.obligation])
  apply applyClosure_valid framed _ _ _ result applied frameGood frameModes
    (fields_value machine.heap framed.heap _ rfl rfl rfl cleanupTyped.1) cleanupTyped.2
  · intro value member
    apply fields_value machine.heap framed.heap _ rfl rfl rfl
    rcases List.mem_cons.mp member with equal | member
    · cases equal; exact infoGood
    · obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
      exact (recordTyped original (by simp only [ValueInventory.obligation, List.mem_cons, List.mem_append]; exact Or.inl (Or.inr originalMember))).1
  · intro value member
    rcases List.mem_cons.mp member with equal | member
    · cases equal; exact infoModes
    · obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
      exact (recordTyped original (by simp only [ValueInventory.obligation, List.mem_cons, List.mem_append]; exact Or.inl (Or.inr originalMember))).2

theorem finishCleanup_valid (machine : State) (context : Context) (after : Transition)
    (accepted : finishCleanup machine context = .ok after) (good : Valid schemas machine) : Valid schemas after.state := by
  have values := ValueInventory.finishCleanup_preserves_all _ _ _ accepted _ good.values
  unfold finishCleanup at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, before, _, ⟨record, events⟩, _, released, _, rfl⟩ := accepted
  cases released <;> exact ⟨fun value member => fields_value machine.heap _ _ rfl rfl rfl (values value member), good.live⟩

end ReferenceSafety
end BoundaryV2.Profile.Source.Machine
