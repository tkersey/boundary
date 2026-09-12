import BoundaryV2.SourceProtectionExecution
import BoundaryV2.SourceOwningObjectFields

namespace BoundaryV2.Profile.Source.Machine
namespace OwningFields

def obligationEntries (book : Custody.Book) (record : Cleanup.Obligation .source) : List Custody.Entry :=
  (obligation record).flatMap (live book)

theorem live_token_occurrences_sublist (book : Custody.Book) (field : Located) :
    List.Sublist ((live book field).map Custody.Entry.token) (ownedTokens field.value) := by
  simp only [live, List.map_map, Function.comp_def]
  rw [← ownedReferences_tokens field.value]
  exact (List.filter_sublist).map Prod.fst

theorem obligation_tokens_sublist (book : Custody.Book) (record : Cleanup.Obligation .source) :
    List.Sublist ((obligationEntries book record).map Custody.Entry.token)
      (ownedTokens record.cleanup ++ record.resource.toList.flatMap ownedTokens) := by
  cases resource : record.resource with
  | none =>
    simpa only [obligationEntries, obligation, resource, Option.toList_none, List.map_nil,
      List.flatMap_cons, List.flatMap_nil, List.append_nil] using
      live_token_occurrences_sublist book ⟨record.cleanup, .protection record.id⟩
  | some value =>
    simpa only [obligationEntries, obligation, resource, Option.toList_some, List.map_cons, List.map_nil,
      List.flatMap_cons, List.flatMap_nil, List.append_nil, List.map_append] using
      (live_token_occurrences_sublist book ⟨record.cleanup, .protection record.id⟩).append
        (live_token_occurrences_sublist book ⟨value, .protection record.id⟩)

theorem obligation_tokens_unique (book : Custody.Book) (record : Cleanup.Obligation .source)
    (linear : ProtectionLinearity.Linear record) :
    ((obligationEntries book record).map Custody.Entry.token).Nodup :=
  linear.sublist (obligation_tokens_sublist book record)

theorem obligation_token_owner (book : Custody.Book) (record : Cleanup.Obligation .source) (token : CustodyToken)
    (member : token ∈ (obligationEntries book record).map Custody.Entry.token) :
    Custody.owns book token (.protection record.id) := by
  simp only [obligationEntries, List.map_flatMap, List.mem_flatMap] at member
  obtain ⟨field, fieldAt, member⟩ := member
  have held := live_token_held book field token member
  simp only [obligation, List.mem_cons] at fieldAt
  rcases fieldAt with equal | fieldAt
  · subst field
    exact held
  · obtain ⟨value, _, rfl⟩ := List.mem_map.mp fieldAt
    exact held

theorem heap_protection_tokens_unique (store : Heap) (linear : ProtectionLinearity.All store.obligations)
    (indexed : store.Indexed) :
    ((store.obligations.flatMap (obligationEntries store.custody)).map Custody.Entry.token).Nodup := by
  simp only [List.map_flatMap]
  apply List.pairwise_flatMap.mpr
  refine ⟨fun record member => obligation_tokens_unique store.custody record (linear record member), ?_⟩
  have identifiers : (store.obligations.map fun record => record.id.value).Nodup := by
    rw [indexed.obligations]
    exact List.nodup_range
  apply (List.pairwise_map.mp identifiers).imp_of_mem
  intro first second _ _ distinct firstToken firstAt secondToken secondAt equal
  have firstOwner := obligation_token_owner store.custody first firstToken firstAt
  have secondOwner := obligation_token_owner store.custody second firstToken (equal ▸ secondAt)
  have owners := Custody.unique_custodian store.custody firstToken _ _ firstOwner secondOwner
  exact distinct (congrArg Ref.value (Custody.Owner.protection.inj owners))

theorem heap_protection_token_owner (store : Heap) (token : CustodyToken)
    (member : token ∈ (store.obligations.flatMap (obligationEntries store.custody)).map Custody.Entry.token) :
    ∃ identity, Custody.owns store.custody token (.protection identity) := by
  simp only [List.map_flatMap, List.mem_flatMap] at member
  obtain ⟨record, _, member⟩ := member
  exact ⟨record.id, obligation_token_owner store.custody record token member⟩

theorem reachable_protection_entries_are_unique (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) :
    ((after.heap.obligations.flatMap (obligationEntries after.heap.custody)).map Custody.Entry.token).Nodup :=
  heap_protection_tokens_unique after.heap
    (ProtectionLinearity.initialized_execution_preserves_protection_linearity _ _ _ _ _ initialized steps)
    (source_trajectory_indices _ _ _ _ initialized steps)


/-- All canonical heap owning fields preserve occurrence multiplicity and
have distinct live tokens, across objects, protection records, and scopes. -/
theorem reachable_heap_entries_are_unique (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : ((heapEntries after.heap).map Custody.Entry.token).Nodup := by
  let objectTokens := (after.heap.objects.flatMap fun entry => entry.toList.flatMap (objectEntries after.heap.custody)).map Custody.Entry.token
  let protectionTokens := (after.heap.obligations.flatMap (obligationEntries after.heap.custody)).map Custody.Entry.token
  let scopeTokens := ((after.heap.scopes.flatMap Scope.holdings).flatMap (live after.heap.custody)).map Custody.Entry.token
  have objectScope : (objectTokens ++ scopeTokens).Nodup := by
    simpa only [objectTokens, scopeTokens, List.map_append] using
      reachable_object_and_scope_entries_are_unique _ _ _ _ _ initialized steps
  have protection : protectionTokens.Nodup := reachable_protection_entries_are_unique _ _ _ _ _ initialized steps
  have formed := ObjectOwners.initialized_execution_preserves_object_owners _ _ _ _ _ initialized steps
  have free : ∀ node stored, after.heap.lookup node = some stored → CellFree stored := by
    intro node stored found
    cases stored <;> try trivial
    exact ObjectOwners.reachable_cell_contents_have_no_tokens _ _ _ _ _ initialized steps _ _ _ _ _ found
  have objectProtection : ∀ first ∈ objectTokens, ∀ second ∈ protectionTokens, first ≠ second := by
    intro first firstAt second secondAt equal
    obtain ⟨node, index, stored, _, objectOwner⟩ := heap_object_token_owner after.heap first formed free firstAt
    obtain ⟨identity, protectionOwner⟩ := heap_protection_token_owner after.heap first (equal ▸ secondAt)
    have impossible := Custody.unique_custodian after.heap.custody first _ _ objectOwner protectionOwner
    cases impossible
  have protectionScope : ∀ first ∈ protectionTokens, ∀ second ∈ scopeTokens, first ≠ second := by
    intro first firstAt second secondAt equal
    obtain ⟨identity, protectionOwner⟩ := heap_protection_token_owner after.heap first firstAt
    obtain ⟨scope, index, scopeOwner⟩ := scope_token_owner after.heap first
      (HoldingOwners.initialized_execution_preserves_holding_owners _ _ _ _ _ initialized steps) (equal ▸ secondAt)
    rcases scopeOwner with lexical | temporary
    · have impossible := Custody.unique_custodian after.heap.custody first _ _ protectionOwner lexical
      cases impossible
    · have impossible := Custody.unique_custodian after.heap.custody first _ _ protectionOwner temporary
      cases impossible
  have components := List.nodup_append.mp objectScope
  have combined : (objectTokens ++ protectionTokens ++ scopeTokens).Nodup := by
    apply List.nodup_append.mpr
    refine ⟨List.nodup_append.mpr ⟨components.1, protection, objectProtection⟩, components.2.1, ?_⟩
    intro first firstAt second secondAt
    rcases List.mem_append.mp firstAt with objectAt | protectionAt
    · exact components.2.2 first objectAt second secondAt
    · exact protectionScope first protectionAt second secondAt
  have same : (heapEntries after.heap).map Custody.Entry.token = objectTokens ++ protectionTokens ++ scopeTokens := by
    simp only [heapEntries, heap, objectEntries, obligationEntries, objectTokens, protectionTokens, scopeTokens,
      List.flatMap_append, List.map_append, List.flatMap_assoc, List.map_flatMap]
  rw [same]
  exact combined

end OwningFields
end BoundaryV2.Profile.Source.Machine
