import BoundaryV2.SourceInitialLaws
import BoundaryV2.SourceStorageLaws

namespace BoundaryV2.Profile.Source.Machine

/-- Exclusive reference occurrences, including leaves of public aggregates.
The physical node accompanies its token; projecting tokens alone loses this
identity information. Reusable references contribute no owning occurrence. -/
def ownedReferences : SemanticValue → List (CustodyToken × NodeId)
  | .reference _ node token => token.toList.map (·, node)
  | .product _ fields | .sequence _ fields => fields.flatMap ownedReferences
  | .variant _ _ payload => ownedReferences payload
  | .scalar .. | .blob .. => []

theorem ownedReferences_tokens (value : SemanticValue) :
    (ownedReferences value).map Prod.fst = ownedTokens value := by
  cases value with
  | scalar _ _ | blob _ _ => simp [ownedReferences, ownedTokens]
  | reference _ _ token => cases token <;> simp [ownedReferences, ownedTokens]
  | product _ fields | sequence _ fields =>
    simp only [ownedReferences, ownedTokens, List.map_flatMap]
    simp only [List.flatMap_def]
    apply congrArg List.flatten
    apply List.map_congr_left
    intro child member
    exact ownedReferences_tokens child
  | variant _ _ payload => simpa only [ownedReferences, ownedTokens] using ownedReferences_tokens payload
termination_by sizeOf value
decreasing_by
  all_goals subst value
  all_goals simp_wf
  all_goals first | omega | exact Nat.lt_trans (List.sizeOf_lt_of_mem member) (by omega)

/-- A stale value can retain a spent token. Whenever the token is live, its
physical object must agree with the value, independently of its current owner.
This permits lexical remnants after a legal transfer without permitting a
token to designate a different object. -/
def ValueAligned (book : Custody.Book) (value : SemanticValue) : Prop :=
  ∀ pair ∈ ownedReferences value, ∀ entry ∈ book.entries,
    entry.token = pair.1 → entry.object = pair.2

def ValueTokensBounded (supply : Nat) (value : SemanticValue) : Prop :=
  ∀ token ∈ ownedTokens value, token.value < supply

theorem token_free_aligned (book : Custody.Book) (value : SemanticValue)
    (free : ownedTokens value = []) : ValueAligned book value := by
  intro pair member
  have tokenMember : pair.1 ∈ ownedTokens value := by
    rw [← ownedReferences_tokens]
    exact List.mem_map.mpr ⟨pair, member, rfl⟩
  simp [free] at tokenMember

theorem admitted_tree_aligned (schemas : List (Schema .source)) (book : Custody.Book)
    (value : SemanticValue) (admitted : Profile.Value.treeValid schemas value = true) :
    ValueAligned book value ∧ ValueTokensBounded supply value := by
  have free := (admitted_tree_has_no_runtime_handles schemas value admitted).2
  exact ⟨token_free_aligned book value free, by simp [ValueTokensBounded, free]⟩

theorem alignment_after_removal (before after : Custody.Book) (value : SemanticValue)
    (retained : after.entries ⊆ before.entries) (aligned : ValueAligned before value) :
    ValueAligned after value := by
  intro pair member entry live same
  exact aligned pair member entry (retained live) same

theorem alignment_after_relocation (book : Custody.Book) (moves : List Custody.Move)
    (value : SemanticValue) (aligned : ValueAligned book value) :
    ValueAligned (Custody.relocate book moves) value := by
  intro pair member entry live same
  obtain ⟨original, originalLive, rfl⟩ := List.mem_map.mp live
  exact (Custody.destination_object moves original).trans
    (aligned pair member original originalLive ((Custody.destination_token moves original).symm.trans same))

theorem moveValues_preserves_alignment (before after : Heap) (values : List Located)
    (receiver : Nat → Custody.Owner) (value : SemanticValue)
    (accepted : moveValues before values receiver = some after)
    (aligned : ValueAligned before.custody value) : ValueAligned after.custody value := by
  simp [moveValues, Option.bind_eq_some_iff] at accepted
  obtain ⟨book, committed, rfl⟩ := accepted
  unfold Custody.commit at committed
  split at committed <;> try contradiction
  cases committed
  exact alignment_after_relocation _ _ _ aligned

theorem consumeValue_preserves_alignment (before after : Heap) (located : Located)
    (value : SemanticValue) (accepted : consumeValue before located = some after)
    (aligned : ValueAligned before.custody value) : ValueAligned after.custody value := by
  simp [consumeValue, Option.bind_eq_some_iff] at accepted
  obtain ⟨book, consumed, rfl⟩ := accepted
  unfold Custody.consume at consumed
  split at consumed <;> try contradiction
  cases consumed
  exact alignment_after_removal _ _ _ (fun _ member => (List.mem_filter.mp member).1) aligned

theorem allocation_preserves_prior_alignment (before after : Heap) (schema : SchemaId .source)
    (object : Object) (owner : Custody.Owner) (exclusive : Bool) (result : Located)
    (value : SemanticValue) (accepted : allocateObject before schema object owner exclusive = some (after, result))
    (bounded : ValueTokensBounded before.nextCustody value)
    (aligned : ValueAligned before.custody value) : ValueAligned after.custody value := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, _⟩ := accepted
    exact aligned
  · obtain ⟨book, allocated, rfl, _⟩ := accepted
    have entries := (Custody.allocation_is_fresh _ _ _ _ _ allocated).2.2
    intro pair member entry live same
    rw [entries] at live
    rcases List.mem_cons.mp live with rfl | live
    · have tokenMember : pair.1 ∈ ownedTokens value := by
        rw [← ownedReferences_tokens]
        exact List.mem_map.mpr ⟨pair, member, rfl⟩
      have below := bounded pair.1 tokenMember
      have equal := congrArg Ref.value same
      dsimp at equal
      omega
    · exact aligned pair member entry live same

theorem allocation_returns_aligned_reference (before after : Heap) (schema : SchemaId .source)
    (object : Object) (owner : Custody.Owner) (exclusive : Bool) (result : Located)
    (accepted : allocateObject before schema object owner exclusive = some (after, result)) :
    ValueAligned after.custody result.value ∧ ValueTokensBounded after.nextCustody result.value := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, rfl⟩ := accepted
    simp [ValueAligned, ValueTokensBounded, ownedReferences, ownedTokens]
  · obtain ⟨book, allocated, rfl, rfl⟩ := accepted
    obtain ⟨fresh, _, entries⟩ := Custody.allocation_is_fresh _ _ _ _ _ allocated
    constructor
    · intro pair member entry live same
      simp only [ownedReferences, Option.toList_some, List.map_cons, List.map_nil,
        List.mem_singleton] at member
      subst pair
      rw [entries] at live
      rcases List.mem_cons.mp live with rfl | live
      · rfl
      · exact False.elim (fresh (List.mem_map.mpr ⟨entry, live, same⟩))
    · simp [ValueTokensBounded, ownedTokens]

/-- Every currently owned object is present, rather than merely an in-bounds
tombstone. This is a heap component of well-formedness, not the complete state
invariant. -/
def Heap.CustodyLive (heap : Heap) : Prop :=
  ∀ entry ∈ heap.custody.entries, (heap.lookup entry.object).isSome = true

theorem current_aligned_owned_references_are_live (heap : Heap) (value : Located)
    (checked : current heap value = true) (aligned : ValueAligned heap.custody value.value)
    (live : heap.CustodyLive) (pair : CustodyToken × NodeId)
    (member : pair ∈ ownedReferences value.value) : (heap.lookup pair.2).isSome = true := by
  have tokenMember : pair.1 ∈ ownedTokens value.value := by
    rw [← ownedReferences_tokens]
    exact List.mem_map.mpr ⟨pair, member, rfl⟩
  have has := List.all_eq_true.mp (Bool.and_eq_true_iff.mp checked).2 pair.1 tokenMember
  obtain ⟨entry, entryMember, same, _⟩ :
      ∃ entry ∈ heap.custody.entries, entry.token = pair.1 ∧ entry.owner = value.owner := by
    simpa [Custody.has, List.any_eq_true, Bool.and_eq_true] using has
  rw [← aligned pair member entry entryMember same]
  exact live entry entryMember

theorem moveValues_preserves_live_objects (before after : Heap) (values : List Located)
    (receiver : Nat → Custody.Owner) (accepted : moveValues before values receiver = some after)
    (live : before.CustodyLive) : after.CustodyLive := by
  simp [moveValues, Option.bind_eq_some_iff] at accepted
  obtain ⟨book, committed, rfl⟩ := accepted
  unfold Custody.commit at committed
  split at committed <;> try contradiction
  cases committed
  intro entry member
  obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
  simpa [Heap.lookup, Custody.destination_object] using live original originalMember

theorem consumeValue_preserves_live_objects (before after : Heap) (value : Located)
    (accepted : consumeValue before value = some after) (live : before.CustodyLive) :
    after.CustodyLive := by
  simp [consumeValue, Option.bind_eq_some_iff] at accepted
  obtain ⟨book, consumed, rfl⟩ := accepted
  unfold Custody.consume at consumed
  split at consumed <;> try contradiction
  cases consumed
  intro entry member
  exact live entry (List.mem_filter.mp member).1

theorem allocateObject_preserves_live_objects (before after : Heap) (schema : SchemaId .source)
    (object : Object) (owner : Custody.Owner) (exclusive : Bool) (result : Located)
    (accepted : allocateObject before schema object owner exclusive = some (after, result))
    (live : before.CustodyLive) : after.CustodyLive := by
  have oldLookup (entry : Custody.Entry) (member : entry ∈ before.custody.entries) :
      ((before.objects ++ [some object])[entry.object.value]?.bind id).isSome = true := by
    have present := live entry member
    have bound : entry.object.value < before.objects.length := by
      by_cases bound : entry.object.value < before.objects.length
      · exact bound
      · have absent : before.objects[entry.object.value]? = none := List.getElem?_eq_none (by omega)
        simp [Heap.lookup, absent] at present
    simpa [Heap.lookup, List.getElem?_append_left bound] using present
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, _⟩ := accepted
    exact oldLookup
  · obtain ⟨book, allocated, rfl, _⟩ := accepted
    have entries := (Custody.allocation_is_fresh _ _ _ _ _ allocated).2.2
    intro entry member
    rw [entries] at member
    rcases List.mem_cons.mp member with rfl | member
    · simp [Heap.lookup]
    · exact oldLookup entry member

theorem replaceObject_preserves_live_objects (before after : Heap) (node : NodeId) (object : Object)
    (accepted : replaceObject before node object = some after) (live : before.CustodyLive) :
    after.CustodyLive := by
  have lookup := replace_object_updates_only_selected_node _ _ _ _ accepted
  have book : after.custody = before.custody := by
    unfold replaceObject at accepted
    split at accepted <;> try contradiction
    cases accepted; rfl
  intro entry member
  rw [book] at member
  by_cases same : entry.object = node
  · simp [same, lookup.1]
  · rw [lookup.2 _ same]
    exact live entry member

theorem retireObject_preserves_alignment (before after : Heap) (located : Located)
    (value : SemanticValue) (accepted : retireObject before located = some after)
    (aligned : ValueAligned before.custody value) : ValueAligned after.custody value := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, Option.bind_eq_some_iff, pure, Option.some.injEq] at accepted
  obtain ⟨_, _, middle, consumed, rfl⟩ := accepted
  exact consumeValue_preserves_alignment before middle located value consumed aligned

/-- Retirement removes the exact object belonging to the consumed token.
Value alignment is essential: token ownership alone does not imply this law
for arbitrary raw, forged locators. -/
theorem retireObject_preserves_live_objects (before after : Heap) (value : Located)
    (accepted : retireObject before value = some after) (live : before.CustodyLive)
    (aligned : ValueAligned before.custody value.value) : after.CustodyLive := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  rename_i schema node token shape
  simp only [bind, Option.bind_eq_some_iff, pure, Option.some.injEq] at accepted
  obtain ⟨object, found, middle, consumed, rfl⟩ := accepted
  simp [consumeValue, Option.bind_eq_some_iff] at consumed
  obtain ⟨book, consumed, rfl⟩ := consumed
  rw [shape] at consumed
  simp only [ownedTokens, Option.toList_some] at consumed
  unfold Custody.consume at consumed
  split at consumed <;> try contradiction
  rename_i admitted
  have owns : Custody.has before.custody token value.owner = true := by simpa using admitted
  obtain ⟨ownerEntry, ownerMember, ownerToken, _⟩ :
      ∃ entry ∈ before.custody.entries, entry.token = token ∧ entry.owner = value.owner := by
    simpa [Custody.has, List.any_eq_true, Bool.and_eq_true] using owns
  have ownerObject : ownerEntry.object = node := by
    apply aligned (token, node) ?_ ownerEntry ownerMember ownerToken
    simp [shape, ownedReferences]
  cases consumed
  intro entry member
  have parts := List.mem_filter.mp member
  have oldLive := live entry parts.1
  have different : entry.object ≠ node := by
    intro same
    have equal := Custody.object_identifies_entry before.custody entry ownerEntry parts.1 ownerMember
      (same.trans ownerObject.symm)
    have absent : entry.token ≠ token := by simpa using parts.2
    exact absent (equal ▸ ownerToken)
  have indices : node.value ≠ entry.object.value := by
    intro same
    apply different
    exact congrArg (fun number => (⟨number⟩ : NodeId)) same.symm
  simpa [Heap.lookup, List.getElem?_set_ne indices] using oldLive

theorem renamed_owned_references (mapping : Renaming) (value : SemanticValue) :
    ownedReferences (renameValue mapping value) =
      (ownedReferences value).map (fun pair => (pair.1, renamed mapping.nodes pair.2)) := by
  cases value with
  | scalar _ _ | blob _ _ => simp [renameValue, ownedReferences]
  | reference _ _ token => cases token <;> simp [renameValue, ownedReferences]
  | product _ fields | sequence _ fields =>
    simp only [renameValue, ownedReferences, List.flatMap_map, List.map_flatMap]
    simp only [List.flatMap_def]
    apply congrArg List.flatten
    apply List.map_congr_left
    intro child member
    exact renamed_owned_references mapping child
  | variant _ _ payload =>
    simpa only [renameValue, ownedReferences] using renamed_owned_references mapping payload
termination_by sizeOf value
decreasing_by
  all_goals subst value
  all_goals simp_wf
  all_goals first | omega | exact Nat.lt_trans (List.sizeOf_lt_of_mem member) (by omega)

theorem renaming_preserves_owned_tokens (mapping : Renaming) (value : SemanticValue) :
    ownedTokens (renameValue mapping value) = ownedTokens value := by
  rw [← ownedReferences_tokens, renamed_owned_references, List.map_map]
  exact ownedReferences_tokens value

theorem token_free_renaming_preserves_alignment (mapping : Renaming) (book : Custody.Book)
    (value : SemanticValue) (free : ownedTokens value = []) :
    ValueAligned book (renameValue mapping value) :=
  token_free_aligned _ _ ((renaming_preserves_owned_tokens mapping value).trans free)

namespace CustodyAlignmentExamples

private def book : Custody.Book := ⟨
  [⟨⟨0⟩, ⟨0⟩, .temporary ⟨0⟩ 0⟩, ⟨⟨1⟩, ⟨1⟩, .temporary ⟨0⟩ 1⟩],
  by decide, by decide⟩

/-- A valid token does not authorize replacing its physical object identity. -/
theorem mismatched_node_is_not_aligned :
    ¬ ValueAligned book (.reference ⟨0⟩ ⟨1⟩ (some ⟨0⟩)) := by
  simp [ValueAligned, ownedReferences, book]

/-- Historical lexical values may retain a token after its owner consumes it.
Its absence grants no present custody and does not falsify alignment. -/
theorem spent_reference_remains_aligned :
    ValueAligned (Custody.without book [⟨0⟩]) (.reference ⟨0⟩ ⟨0⟩ (some ⟨0⟩)) := by
  simp [ValueAligned, ownedReferences, Custody.without, book]

end CustodyAlignmentExamples

end BoundaryV2.Profile.Source.Machine
