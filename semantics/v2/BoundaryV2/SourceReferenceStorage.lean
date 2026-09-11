import BoundaryV2.SourceReferenceContracts

namespace BoundaryV2.Profile.Source.Machine
namespace ReferenceContracts

private theorem bind_ok (value : Option α) (next : α → Option β) (result : β) :
    value.bind next = some result ↔ ∃ input, value = some input ∧ next input = some result := by
  cases value <;> simp

theorem usable_after_relocation (book : Custody.Book) (moves : List Custody.Move)
    (token : Option CustodyToken) (usable : Usable (Custody.relocate book moves) token) : Usable book token := by
  cases token with
  | none => trivial
  | some token =>
    obtain ⟨entry, member, same⟩ := usable
    obtain ⟨original, oldMember, rfl⟩ := List.mem_map.mp member
    exact ⟨original, oldMember, (Custody.destination_token moves original).symm.trans same⟩

theorem moveValues_value_valid (schemas : List (Schema .source)) (before after : Heap)
    (values : List Located) (receiver : Nat → Custody.Owner) (value : SemanticValue)
    (accepted : moveValues before values receiver = some after) (valid : ValueValid schemas before value) :
    ValueValid schemas after value := by
  simp only [moveValues, bind, bind_ok, pure, Option.some.injEq] at accepted
  obtain ⟨book, committed, rfl⟩ := accepted
  unfold Custody.commit at committed
  split at committed <;> try contradiction
  cases committed
  apply references_mono value _ _ valid
  intro schema node token checked usable
  exact checked (usable_after_relocation _ _ _ usable)

theorem consumeValue_value_valid (schemas : List (Schema .source)) (before after : Heap)
    (located : Located) (value : SemanticValue) (accepted : consumeValue before located = some after)
    (valid : ValueValid schemas before value) : ValueValid schemas after value := by
  simp only [consumeValue, bind, bind_ok, pure, Option.some.injEq] at accepted
  obtain ⟨book, consumed, rfl⟩ := accepted
  unfold Custody.consume at consumed
  split at consumed <;> try contradiction
  cases consumed
  apply references_mono value _ _ valid
  intro schema node token checked usable
  apply checked
  cases token with
  | none => trivial
  | some token =>
    obtain ⟨entry, member, same⟩ := usable
    exact ⟨entry, (List.mem_filter.mp member).1, same⟩

theorem replaceObject_value_valid (schemas : List (Schema .source)) (before after : Heap)
    (node : NodeId) (stored original : Object) (value : SemanticValue)
    (found : before.lookup node = some original)
    (accepted : replaceObject before node stored = some after)
    (compatible : ∀ schema, Matches schemas schema original → Matches schemas schema stored)
    (valid : ValueValid schemas before value) : ValueValid schemas after value := by
  have lookups := replace_object_updates_only_selected_node before after node stored accepted
  have sameBook : after.custody = before.custody := by
    unfold replaceObject at accepted
    split at accepted <;> try contradiction
    cases accepted; rfl
  apply references_mono value _ _ valid
  intro schema reference token checked usable
  obtain ⟨object, atReference, matched⟩ := checked (sameBook ▸ usable)
  by_cases same : reference = node
  · subst reference
    have sameObject := Option.some.inj (found.symm.trans atReference)
    subst object
    exact ⟨stored, lookups.1, compatible schema matched⟩
  · exact ⟨object, (lookups.2 reference same).trans atReference, matched⟩

theorem allocateObject_reference_valid (schemas : List (Schema .source)) (before after : Heap)
    (schema : SchemaId .source) (stored : Object) (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject before schema stored owner exclusive = some (after, value))
    (compatible : Matches schemas schema stored) : ValueValid schemas after value.value := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, rfl⟩ := accepted
    simp only [ValueValid, Primitives.ReferencesSatisfy, ReferenceValid]
    intro _
    exact ⟨stored, by simp [Heap.lookup], compatible⟩
  · obtain ⟨_, _, rfl, rfl⟩ := accepted
    simp only [ValueValid, Primitives.ReferencesSatisfy, ReferenceValid]
    intro _
    exact ⟨stored, by simp [Heap.lookup], compatible⟩

theorem allocation_reference_valid (schemas : List (Schema .source)) (before after : Heap)
    (allocatedSchema : SchemaId .source) (stored : Object) (owner : Custody.Owner)
    (exclusive : Bool) (result : Located) (schema : SchemaId .source) (node : NodeId) (token : Option CustodyToken)
    (accepted : allocateObject before allocatedSchema stored owner exclusive = some (after, result))
    (bounded : ∀ owned ∈ token.toList, owned.value < before.nextCustody)
    (valid : ReferenceValid schemas before schema node token) : ReferenceValid schemas after schema node token := by
  have oldLookup (object : Object) (found : before.lookup node = some object) :
      ((before.objects ++ [some stored])[node.value]?.bind id) = some object := by
    have bound : node.value < before.objects.length := by
      simp only [Heap.lookup, Option.bind_eq_some_iff] at found
      obtain ⟨entry, atNode, _⟩ := found
      exact (List.getElem?_eq_some_iff.mp atNode).choose
    simpa [Heap.lookup, List.getElem?_append_left bound] using found
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, _⟩ := accepted
    intro usable
    obtain ⟨object, found, matched⟩ := valid usable
    exact ⟨object, oldLookup object found, matched⟩
  · obtain ⟨book, allocated, rfl, _⟩ := accepted
    intro usable
    have oldUsable : Usable before.custody token := by
      cases token with
      | none => trivial
      | some token =>
        obtain ⟨entry, member, same⟩ := usable
        rw [(Custody.allocation_is_fresh _ _ _ _ _ allocated).2.2] at member
        rcases List.mem_cons.mp member with rfl | member
        · have below := bounded token (by simp)
          have equal := congrArg Ref.value same
          dsimp at equal
          omega
        · exact ⟨entry, member, same⟩
    obtain ⟨object, found, matched⟩ := valid oldUsable
    exact ⟨object, oldLookup object found, matched⟩

theorem allocation_value_valid (schemas : List (Schema .source)) (before after : Heap)
    (schema : SchemaId .source) (stored : Object) (owner : Custody.Owner) (exclusive : Bool)
    (result : Located) (value : SemanticValue)
    (accepted : allocateObject before schema stored owner exclusive = some (after, result))
    (bounded : ValueTokensBounded before.nextCustody value)
    (valid : ValueValid schemas before value) : ValueValid schemas after value := by
  apply references_transport₂ value _ _ _ valid
    ((referencesSatisfy_token_bounds before.nextCustody value).mpr bounded)
  intro schema node token valid bounded
  exact allocation_reference_valid schemas before after _ stored owner exclusive result schema node token
    accepted bounded valid

end ReferenceContracts
end BoundaryV2.Profile.Source.Machine
