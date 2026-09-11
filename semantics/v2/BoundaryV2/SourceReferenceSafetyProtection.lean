import BoundaryV2.SourceReferenceSafetyCleanup

namespace BoundaryV2.Profile.Source.Machine
namespace ReferenceSafety
open ReferenceContracts

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem installProtection_valid (machine : State) (context : Context) (body cleanup : Located)
    (arguments : List Located) (resource : Option Located) (loan : Option (RegionId .source)) (after : Transition)
    (accepted : installProtection machine context body cleanup arguments resource loan = .ok after)
    (good : Valid context.source.schemas machine)
    (modes : ValueInventory.All (ValueModes context.source.schemas) machine)
    (bodyTyped : ValueGood context.source.schemas machine.heap body.value ∧ ValueModes context.source.schemas body.value)
    (cleanupTyped : ValueGood context.source.schemas machine.heap cleanup.value ∧ ValueModes context.source.schemas cleanup.value)
    (argumentsTyped : ∀ value ∈ arguments, ValueGood context.source.schemas machine.heap value.value ∧ ValueModes context.source.schemas value.value)
    (resourceTyped : ∀ value ∈ resource, ValueGood context.source.schemas machine.heap value.value ∧ ValueModes context.source.schemas value.value) :
    Valid context.source.schemas after.state := by
  simp only [installProtection, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨bodyType, _, _, _, _, _, _, _, _, _, store, moved, accepted⟩ := accepted
  let record : Cleanup.Obligation .source := ⟨⟨machine.heap.nextObligation⟩, machine.scope, machine.heap.nextObligation,
    cleanup.value, resource.map Located.value, .pending⟩
  let heap := {store with obligations := store.obligations ++ [record], nextObligation := store.nextObligation + 1}
  have transport : ∀ value, ValueGood context.source.schemas machine.heap value → ValueGood context.source.schemas heap value :=
    fun value holds => fields_value store heap _ rfl rfl rfl (move_value _ _ _ _ _ moved holds)
  have typed : ValueInventory.All (fun value => ValueGood context.source.schemas heap value ∧ ValueModes context.source.schemas value) machine :=
    fun value member => ⟨transport _ (good.values value member), modes value member⟩
  have movedTyped := ValueInventory.moveValues_preserves_all machine store _ _ moved _ typed
  have recordTyped : ∀ value ∈ ValueInventory.obligation record,
      ValueGood context.source.schemas heap value ∧ ValueModes context.source.schemas value := by
    simp only [record, ValueInventory.obligation, List.mem_cons, List.mem_append, List.not_mem_nil, or_false]
    intro value member
    rcases member with equal | member
    · cases equal; exact ⟨transport _ cleanupTyped.1, cleanupTyped.2⟩
    · have found : resource.map Located.value = some value := by simpa using member
      obtain ⟨original, originalMember, rfl⟩ := Option.map_eq_some_iff.mp found
      exact ⟨transport _ (resourceTyped original originalMember).1, (resourceTyped original originalMember).2⟩
  have heapTyped : ValueInventory.All (fun value => ValueGood context.source.schemas heap value ∧ ValueModes context.source.schemas value)
      {machine with heap := heap} := by
    simp only [heap, ValueInventory.All, ValueInventory.state, ValueInventory.heap,
      List.flatMap_append, List.flatMap_cons, List.flatMap_nil, List.append_nil, List.mem_append] at movedTyped ⊢
    grind only []
  have heapLive : heap.CustodyLive := moveValues_preserves_live_objects _ store _ _ moved good.live
  cases resource with
  | none =>
    cases loan <;> try contradiction
    simp only [pure, Except.pure, Except.bind] at accepted
    have framed : ValueInventory.All (fun value => ValueGood context.source.schemas heap value ∧ ValueModes context.source.schemas value)
        {machine with heap := heap, stack := .protection ⟨machine.heap.nextObligation⟩ :: machine.stack} := by
      simpa only [ValueInventory.All, ValueInventory.state, List.singleton_append, List.flatMap_cons,
        ValueInventory.frame, List.nil_append] using heapTyped
    exact applyClosure_valid _ _ _ _ _ accepted ⟨fun value member => (framed value member).1, heapLive⟩
      (fun value member => (framed value member).2) (transport _ bodyTyped.1) bodyTyped.2
      (fun value member => transport _ (argumentsTyped value member).1) (fun value member => (argumentsTyped value member).2)
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
      let middle := {machine with heap := {heap with nextRegion := heap.nextRegion + 1, loans := heap.loans ++ [((⟨heap.nextRegion⟩ : RegionInstanceId), (⟨machine.heap.nextObligation⟩ : ObligationId))]}}
      have middleGood : Valid context.source.schemas middle :=
        ⟨fun value member => fields_value heap middle.heap _ rfl rfl rfl (heapTyped value member).1, heapLive⟩
      have allocatedGood := allocation_valid middle _ _ _ _ _ _ allocated middleGood (by simp [ValueInventory.object])
      have allocatedModes := ValueInventory.allocateObject_preserves_all middle _ _ _ _ _ _ allocated _
        (fun value member => (heapTyped value member).2) (by simp [ValueInventory.object])
      have borrowedGood := allocation_result (schemas := context.source.schemas) _ _ _ _ _ _ _ allocated (by rfl)
      have borrowedModes : ValueModes context.source.schemas borrowed.value := by
        rw [ValueInventory.allocateObject_result _ _ _ _ _ _ _ allocated]
        exact typed_has_reference_modes _ _ (.reference shape rfl)
      have nextTransport : ∀ value, ValueGood context.source.schemas machine.heap value → ValueGood context.source.schemas afterStore value :=
        fun value holds => allocation_value _ _ _ _ _ _ _ _ allocated
          (fields_value heap middle.heap _ rfl rfl rfl (transport _ holds))
      refine applyClosure_valid _ _ _ _ _ applied ?_ ?_ (nextTransport _ bodyTyped.1) bodyTyped.2 ?_ ?_
      · refine ⟨?_, allocatedGood.live⟩
        simpa only [ValueInventory.All, ValueInventory.state, List.cons_append, List.nil_append,
          List.flatMap_cons, ValueInventory.frame] using allocatedGood.values
      · simpa only [ValueInventory.All, ValueInventory.state, List.cons_append, List.nil_append,
          List.flatMap_cons, ValueInventory.frame] using allocatedModes
      · intro child member
        rcases List.mem_cons.mp member with equal | member
        · cases equal; exact borrowedGood
        · exact nextTransport _ (argumentsTyped child member).1
      · intro child member
        rcases List.mem_cons.mp member with equal | member
        · cases equal; exact borrowedModes
        · exact (argumentsTyped child member).2

end ReferenceSafety
end BoundaryV2.Profile.Source.Machine
