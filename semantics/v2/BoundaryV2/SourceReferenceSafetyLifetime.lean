import BoundaryV2.SourceReferenceSafetyEffects

namespace BoundaryV2.Profile.Source.Machine
namespace ReferenceSafety
open ReferenceContracts

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem enterInvocation_valid (machine : State) (context : Context) (after : Transition)
    (accepted : enterInvocation machine context = .ok after) (good : Valid context.source.schemas machine) :
    Valid context.source.schemas after.state := by
  unfold enterInvocation at accepted
  split at accepted <;> try contradiction
  rename_i function bindings arguments entered
  apply invokeFunction_valid _ _ _ _ _ _ accepted good
  all_goals have holds := good.values
  all_goals simp only [ValueInventory.All, ValueInventory.state, entered, ValueInventory.control,
    ValueInventory.environment, List.mem_append, List.mem_map] at holds
  all_goals grind only []

theorem enterBinding_valid (machine : State) (context : Context) (after : Transition)
    (accepted : enterBinding machine context = .ok after) (good : Valid schemas machine) : Valid schemas after.state := by
  have checked := accepted
  unfold enterBinding at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have facts := createScope_reference_facts (schemas := schemas) _ _ _ _ _ _ _ _ _ scopeOk
  exact ⟨ValueInventory.enterBinding_preserves_all _ _ _ checked _
    (fun value member => facts.1 value (good.values value member)), facts.2 good.live⟩

theorem enterPattern_valid (machine : State) (context : Context) (vars : List VariableId)
    (parts : List SemanticValue) (owner : Custody.Owner) (body : TermId) (bindings : Environment) (after : Transition)
    (accepted : enterPattern machine context vars parts owner body bindings = .ok after)
    (good : Valid schemas machine)
    (outer : ∀ binding ∈ bindings, ValueGood schemas machine.heap binding.located.value)
    (inputs : ∀ value ∈ parts, ValueGood schemas machine.heap value) : Valid schemas after.state := by
  have checked := accepted
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have facts := createScope_reference_facts (schemas := schemas) _ _ _ _ _ _ _ _ _ scopeOk
  exact ⟨ValueInventory.enterPattern_preserves_all _ _ _ _ _ _ _ _ checked _
    (fun value member => facts.1 value (good.values value member))
    (fun binding member => facts.1 _ (outer binding member))
    (fun value member => facts.1 _ (inputs value member)), facts.2 good.live⟩

theorem leaveScope_reference_facts (machine : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition)
    (accepted : leaveScope machine parent invocation tail value = .ok after) :
    (∀ value, ValueGood schemas machine.heap value → ValueGood schemas after.state.heap value) ∧
    (machine.heap.CustodyLive → after.state.heap.CustodyLive) := by
  simp only [leaveScope, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, store, moveOk, delivered, deliveredOk, rfl⟩ := accepted
  constructor
  · exact fun value holds => finishTemporary_value {middle with heap := store} _ delivered _ deliveredOk
      (move_value middle.heap store _ _ _ moveOk (temporary_value _ _ _ _ temporaryOk holds))
  · intro live
    have tempFields := temporary_fields _ _ _ temporaryOk
    have tempLive : middle.heap.CustodyLive := by
      intro entry member
      simpa only [Heap.lookup, tempFields.1] using live entry (tempFields.2.1 ▸ member)
    have storeLive := moveValues_preserves_live_objects _ _ _ _ moveOk tempLive
    have finishFields := finishTemporary_fields _ _ _ deliveredOk
    intro entry member
    simpa only [Heap.lookup, finishFields.1] using storeLive entry (finishFields.2.1 ▸ member)

theorem leaveScope_valid (machine : State) (parent : LexicalScopeId) (invocation : InvocationId)
    (tail : List Frame) (value : Located) (after : Transition)
    (accepted : leaveScope machine parent invocation tail value = .ok after)
    (good : Valid schemas machine)
    (tailGood : ∀ child ∈ tail.flatMap ValueInventory.frame, ValueGood schemas machine.heap child)
    (valueGood : ValueGood schemas machine.heap value.value) : Valid schemas after.state := by
  have facts := leaveScope_reference_facts (schemas := schemas) _ _ _ _ _ _ accepted
  exact ⟨ValueInventory.leaveScope_preserves_all _ _ _ _ _ _ accepted _
    (fun value member => facts.1 _ (good.values value member))
    (fun value member => facts.1 _ (tailGood value member)) (facts.1 _ valueGood), facts.2 good.live⟩

theorem leaveInvocation_valid (machine : State) (after : Transition)
    (accepted : leaveInvocation machine = .ok after) (good : Valid schemas machine) : Valid schemas after.state := by
  unfold leaveInvocation at accepted
  split at accepted <;> try contradiction
  rename_i value delivered
  split at accepted <;> try contradiction
  rename_i caller parent tail stacked
  apply leaveScope_valid _ _ _ _ _ _ accepted good
  all_goals have holds := good.values
  all_goals simp only [ValueInventory.All, ValueInventory.state, delivered, stacked, ValueInventory.control,
    List.flatMap_cons, ValueInventory.frame, List.nil_append, List.mem_append, List.mem_singleton] at holds
  all_goals grind only []

theorem restoreResumeCaller_valid (machine : State) (after : Transition)
    (accepted : restoreResumeCaller machine = .ok after) (good : Valid schemas machine) : Valid schemas after.state := by
  have checked := accepted
  unfold restoreResumeCaller at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, store, moved, finished⟩ := accepted
  have transport : ∀ value, ValueGood schemas machine.heap value → ValueGood schemas after.state.heap value :=
    fun value holds => finishTemporary_value _ _ _ _ finished
      (move_value _ _ _ _ _ moved (temporary_value _ _ _ _ temporaryOk holds))
  refine ⟨ValueInventory.restoreResumeCaller_preserves_all _ _ checked _
    (fun value member => transport _ (good.values value member)), ?_⟩
  have tempFields := temporary_fields _ _ _ temporaryOk
  have tempLive : middle.heap.CustodyLive := by
    intro entry member
    simpa only [Heap.lookup, tempFields.1] using good.live entry (tempFields.2.1 ▸ member)
  have storeLive := moveValues_preserves_live_objects _ _ _ _ moved tempLive
  have finishFields := finishTemporary_fields _ _ _ finished
  intro entry member
  simpa only [Heap.lookup, finishFields.1] using storeLive entry (finishFields.2.1 ▸ member)

theorem product_child_good (heap : Heap) (schema : SchemaId .source) (fields : List SemanticValue)
    (good : ValueGood schemas heap (.product schema fields)) (child : SemanticValue) (member : child ∈ fields) :
    ValueGood schemas heap child := by
  simp only [ValueGood, ValueValid, Primitives.ReferencesSatisfy, ValueAligned, ownedReferences,
    ValueTokensBounded, ownedTokens] at good ⊢
  refine ⟨good.1 child member, ?_, ?_⟩
  · intro pair belongs
    exact good.2.1 pair (List.mem_flatMap.mpr ⟨child, member, belongs⟩)
  · intro token belongs
    exact good.2.2 token (List.mem_flatMap.mpr ⟨child, member, belongs⟩)

theorem sequence_child_good (heap : Heap) (schema : SchemaId .source) (fields : List SemanticValue)
    (good : ValueGood schemas heap (.sequence schema fields)) (child : SemanticValue) (member : child ∈ fields) :
    ValueGood schemas heap child := by
  apply product_child_good heap schema fields _ child member
  simpa only [ValueGood, ValueValid, Primitives.ReferencesSatisfy, ValueAligned, ownedReferences,
    ValueTokensBounded, ownedTokens] using good

theorem variant_payload_good (heap : Heap) (schema : SchemaId .source) (tag : Nat) (payload : SemanticValue)
    (good : ValueGood schemas heap (.variant schema tag payload)) : ValueGood schemas heap payload := by
  simpa only [ValueGood, ValueValid, Primitives.ReferencesSatisfy, ValueAligned, ownedReferences,
    ValueTokensBounded, ownedTokens] using good

theorem liveOwnedValue_good (store heap : Heap) (owner : Custody.Owner) (original : SemanticValue)
    (good : ValueGood schemas heap original) :
    ∀ value ∈ liveOwnedValue store owner original, ValueGood schemas heap value.value := by
  cases original with
  | scalar _ _ | blob _ _ => simp [liveOwnedValue]
  | reference schema node token =>
    cases token with
    | none => simp [liveOwnedValue]
    | some token =>
      simp only [liveOwnedValue]
      split
      · intro value member
        cases List.mem_singleton.mp member
        exact good
      · simp
  | product schema fields =>
    simp only [liveOwnedValue, List.mem_flatMap]
    intro value member
    obtain ⟨child, childMember, member⟩ := member
    exact liveOwnedValue_good store heap owner child (product_child_good _ _ _ good child childMember) value member
  | sequence schema fields =>
    simp only [liveOwnedValue, List.mem_flatMap]
    intro value member
    obtain ⟨child, childMember, member⟩ := member
    exact liveOwnedValue_good store heap owner child (sequence_child_good _ _ _ good child childMember) value member
  | variant schema tag payload =>
    simpa only [liveOwnedValue] using liveOwnedValue_good store heap owner payload (variant_payload_good _ _ _ _ good)
termination_by sizeOf original
decreasing_by
  all_goals subst original
  all_goals simp_wf
  all_goals first | omega | exact Nat.lt_trans (List.sizeOf_lt_of_mem childMember) (by omega)

theorem liveOwned_holdings_good (store heap : Heap) (holdings : List Located)
    (good : ∀ value ∈ holdings, ValueGood schemas heap value.value) :
    ∀ child ∈ holdings.flatMap (liveOwned store), ValueGood schemas heap child.value := by
  intro child member
  obtain ⟨original, originalMember, childMember⟩ := List.mem_flatMap.mp member
  exact liveOwnedValue_good store heap original.owner original.value (good original originalMember) child childMember

end ReferenceSafety
end BoundaryV2.Profile.Source.Machine
