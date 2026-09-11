import BoundaryV2.SourceReferenceSafetyCapture

namespace BoundaryV2.Profile.Source.Machine
namespace ReferenceSafety
open ReferenceContracts

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

theorem enterRegion_valid (machine : State) (context : Context) (descriptor : RegionId .source)
    (body : Located) (arguments : List Located) (after : Transition)
    (accepted : enterRegion machine context descriptor body arguments = .ok after)
    (good : Valid context.source.schemas machine)
    (modes : ValueInventory.All (ValueModes context.source.schemas) machine)
    (bodyGood : ValueGood context.source.schemas machine.heap body.value)
    (bodyModes : ValueModes context.source.schemas body.value)
    (inputs : ∀ value ∈ arguments, ValueGood context.source.schemas machine.heap value.value)
    (inputModes : ∀ value ∈ arguments, ValueModes context.source.schemas value.value) :
    Valid context.source.schemas after.state := by
  simp only [enterRegion, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, signature, _, schema, _, _, schemaOk, ⟨store, value⟩, allocated, applied⟩ := accepted
  have shape : context.source.schemas[schema.value]? = some (.internal (.region descriptor)) := by
    simpa using require_ok _ _ _ schemaOk
  let middle := {machine with heap := {machine.heap with nextRegion := machine.heap.nextRegion + 1}}
  have middleGood : Valid context.source.schemas middle := ⟨fun value member => fields_value machine.heap _ _ rfl rfl rfl (good.values value member), good.live⟩
  have allocatedGood := allocation_valid middle _ _ _ _ _ _ allocated middleGood (by simp [ValueInventory.object])
  have valueGood := allocation_result _ _ _ _ _ _ _ allocated shape
  have valueModes : ValueModes context.source.schemas value.value := by
    rw [ValueInventory.allocateObject_result _ _ _ _ _ _ _ allocated]
    exact typed_has_reference_modes _ _ (.reference shape rfl)
  have frameGood : Valid context.source.schemas
      {machine with heap := store, stack := .region ⟨machine.heap.nextRegion⟩ :: machine.stack} := by
    refine ⟨?_, allocatedGood.live⟩
    simpa only [ValueInventory.All, ValueInventory.state, List.flatMap_cons, ValueInventory.frame,
      List.nil_append] using allocatedGood.values
  have allocatedModes := ValueInventory.allocateObject_preserves_all middle _ _ _ _ _ _ allocated _ modes (by simp [ValueInventory.object])
  have frameModes : ValueInventory.All (ValueModes context.source.schemas)
      {machine with heap := store, stack := .region ⟨machine.heap.nextRegion⟩ :: machine.stack} := by
    simpa only [ValueInventory.All, ValueInventory.state, List.flatMap_cons, ValueInventory.frame,
      List.nil_append] using allocatedModes
  have transport : ∀ child, ValueGood context.source.schemas machine.heap child → ValueGood context.source.schemas store child :=
    fun child holds => allocation_value _ _ _ _ _ _ _ child allocated
      (fields_value machine.heap middle.heap child rfl rfl rfl holds)
  exact applyClosure_valid _ _ _ _ _ applied frameGood frameModes (transport _ bodyGood) bodyModes
    (by simpa using And.intro valueGood (fun value member => transport _ (inputs value member)))
    (by simpa using And.intro valueModes inputModes)

private theorem foldlM_preserves (items : List β) (step : α → β → Except Invalid α)
    (property : α → Prop) (preserved : ∀ before item after, step before item = .ok after → property before → property after)
    (before after : α) (accepted : items.foldlM step before = .ok after) (holds : property before) : property after := by
  induction items generalizing before with
  | nil => cases accepted; exact holds
  | cons first rest induction =>
    simp only [List.foldlM_cons, bind, except_bind_ok] at accepted
    obtain ⟨middle, stepped, accepted⟩ := accepted
    exact induction middle accepted (preserved before first middle stepped holds)

theorem installHandler_valid (machine : State) (context : Context) (handler : HandlerId .source)
    (body : Located) (arguments stored : List Located) (bindings : Environment) (after : Transition)
    (accepted : installHandler machine context handler body arguments stored bindings = .ok after)
    (good : Valid context.source.schemas machine)
    (modes : ValueInventory.All (ValueModes context.source.schemas) machine)
    (bodyGood : ValueGood context.source.schemas machine.heap body.value)
    (bodyModes : ValueModes context.source.schemas body.value)
    (inputs : ∀ value ∈ arguments, ValueGood context.source.schemas machine.heap value.value ∧ ValueModes context.source.schemas value.value)
    (storedGood : ∀ value ∈ stored, ValueGood context.source.schemas machine.heap value.value ∧ ValueModes context.source.schemas value.value)
    (outer : ∀ binding ∈ bindings, ValueGood context.source.schemas machine.heap binding.located.value ∧ ValueModes context.source.schemas binding.located.value) :
    Valid context.source.schemas after.state := by
  simp only [installHandler, bind, except_bind_ok] at accepted
  obtain ⟨definition, _, _, _, _, _, _, _, signature, _, _, _, ⟨store, capabilities⟩, allocated, applied⟩ := accepted
  let property (pair : Heap × List Located) : Prop :=
    Valid context.source.schemas {machine with heap := pair.1} ∧
    ValueInventory.All (ValueModes context.source.schemas) {machine with heap := pair.1} ∧
    (∀ value ∈ pair.2, ValueGood context.source.schemas pair.1 value.value ∧ ValueModes context.source.schemas value.value) ∧
    ∀ value, ValueGood context.source.schemas machine.heap value → ValueGood context.source.schemas pair.1 value
  have seed : property ({machine.heap with nextAttachment := machine.heap.nextAttachment + 1}, []) :=
    ⟨⟨fun value member => fields_value machine.heap _ _ rfl rfl rfl (good.values value member), good.live⟩,
      modes, by simp, fun value holds => fields_value machine.heap _ _ rfl rfl rfl holds⟩
  have allGood := foldlM_preserves _ _ property (by
    intro before item after stepOk beforeGood
    rcases before with ⟨heap, capabilities⟩
    rcases item with ⟨clause, schema⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at stepOk
    obtain ⟨_, schemaOk, ⟨next, value⟩, allocated, rfl⟩ := stepOk
    have shape : context.source.schemas[schema.value]? = some (.internal (.capability clause.effect)) := by
      simpa using require_ok _ _ _ schemaOk
    have heapGood := allocation_valid {machine with heap := heap} _ _ _ _ _ _ allocated beforeGood.1 (by simp [ValueInventory.object])
    have valueGood := allocation_result _ _ _ _ _ _ _ allocated shape
    have valueModes : ValueModes context.source.schemas value.value := by
      rw [ValueInventory.allocateObject_result _ _ _ _ _ _ _ allocated]
      exact typed_has_reference_modes _ _ (.reference shape rfl)
    refine ⟨heapGood, ValueInventory.allocateObject_preserves_all {machine with heap := heap} _ _ _ _ _ _ allocated _ beforeGood.2.1 (by simp [ValueInventory.object]), ?_, ?_⟩
    · intro child member
      rcases List.mem_append.mp member with member | member
      · exact ⟨allocation_value _ _ _ _ _ _ _ _ allocated (beforeGood.2.2.1 child member).1, (beforeGood.2.2.1 child member).2⟩
      · cases List.mem_singleton.mp member; exact ⟨valueGood, valueModes⟩
    · exact fun child holds => allocation_value _ _ _ _ _ _ _ _ allocated (beforeGood.2.2.2 child holds)) _ _ allocated seed
  have selected : ∀ value ∈ ValueInventory.environment (handlerEnvironment context definition bindings),
      ValueGood context.source.schemas store value ∧ ValueModes context.source.schemas value := by
    intro value member
    have originalMember := ValueInventory.handler_environment_subset context definition bindings member
    obtain ⟨binding, bindingMember, rfl⟩ := List.mem_map.mp originalMember
    exact ⟨allGood.2.2.2 _ (outer binding bindingMember).1, (outer binding bindingMember).2⟩
  have retained : ∀ value ∈ stored, ValueGood context.source.schemas store value.value ∧ ValueModes context.source.schemas value.value :=
    fun value member => ⟨allGood.2.2.2 _ (storedGood value member).1, (storedGood value member).2⟩
  let framed := {machine with heap := store, stack := (Frame.handler ⟨⟨machine.heap.nextAttachment⟩, handler, handlerEnvironment context definition bindings, stored,
    machine.invocation, machine.scope, (activeAttachments machine.stack).head?⟩) :: machine.stack}
  have frameGood : Valid context.source.schemas framed := by
    refine ⟨?_, allGood.1.live⟩
    have values := allGood.1.values
    simp only [framed, ValueInventory.All, ValueInventory.state, List.flatMap_cons, ValueInventory.frame,
      ValueInventory.activation, List.mem_append, List.mem_map] at values ⊢
    grind only []
  have frameModes : ValueInventory.All (ValueModes context.source.schemas) framed := by
    have values := allGood.2.1
    simp only [framed, ValueInventory.All, ValueInventory.state, List.flatMap_cons, ValueInventory.frame,
      ValueInventory.activation, List.mem_append, List.mem_map] at values ⊢
    grind only []
  apply applyClosure_valid _ _ _ _ _ applied frameGood frameModes (allGood.2.2.2 _ bodyGood) bodyModes
  · intro value member
    rcases List.mem_append.mp member with member | member
    · exact (allGood.2.2.1 value member).1
    · exact allGood.2.2.2 _ (inputs value member).1
  · intro value member
    rcases List.mem_append.mp member with member | member
    · exact (allGood.2.2.1 value member).2
    · exact (inputs value member).2

end ReferenceSafety
end BoundaryV2.Profile.Source.Machine
