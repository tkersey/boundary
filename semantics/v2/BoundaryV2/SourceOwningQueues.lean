import BoundaryV2.SourceQueueExecution
import BoundaryV2.SourceOwningProtectionFields

namespace BoundaryV2.Profile.Source.Machine
namespace OwningFields

def queueFields (machine : State) : List Located :=
  control machine.heap machine.control ++ machine.stack.flatMap (frame machine.heap) ++
    machine.heap.objects.flatMap (fun entry => entry.toList.flatMap (captured machine.heap))

def queueEntries (machine : State) : List Custody.Entry := (queueFields machine).flatMap (live machine.heap.custody)

theorem state_entries_split (machine : State) : entries machine = heapEntries machine.heap ++ queueEntries machine := by
  simp only [entries, state, heapEntries, queueEntries, queueFields, List.flatMap_append, List.append_assoc]

theorem control_queue (heap : Heap) (executing : Control) : control heap executing = queue heap (DisposalShape.control executing) := by
  cases executing <;> rfl

theorem frame_queue (heap : Heap) (saved : Frame) : frame heap saved = queue heap (DisposalShape.frame saved) := by
  cases saved <;> rfl

theorem captured_queue (heap : Heap) (stored : Object) : captured heap stored = queue heap (DisposalShape.object stored) := by
  have frames : frame heap = fun saved => queue heap (DisposalShape.frame saved) := funext (frame_queue heap)
  cases stored <;> try rfl
  all_goals simp only [captured, capture, DisposalShape.object, frames, queue, List.filter_flatMap]

theorem queue_fields_exact (machine : State) : queueFields machine = queue machine.heap (OwnerLocations.queuedValues machine) := by
  have frames : frame machine.heap = fun saved => queue machine.heap (DisposalShape.frame saved) := funext (frame_queue machine.heap)
  have stored : captured machine.heap = fun saved => queue machine.heap (DisposalShape.object saved) := funext (captured_queue machine.heap)
  simp only [queueFields, OwnerLocations.queuedValues, frames, stored, control_queue, queue, List.filter_append, List.filter_flatMap]

theorem ordinary_queue_has_no_live_entries (heap : Heap) (field : Located) (ordinary : OwnerLocations.Ordinary field) :
    (queue heap [field]).flatMap (live heap.custody) = [] := by
  rcases ordinary with inScope | free
  · cases ownerAt : field.owner <;> simp only [ownerAt, OwnerLocations.Scoped] at inScope <;> try contradiction
    all_goals simp [queue, detached, ownerAt]
  · simp only [queue, List.filter_cons, List.filter_nil]
    split
    · simp only [List.flatMap_cons, List.flatMap_nil, live_empty_of_token_free heap.custody field free, List.nil_append]
    · rfl

theorem queued_field_retired (machine : State) (field : Located) (valid : OwnerLocations.Valid machine)
    (member : field ∈ queueFields machine) (liveToken : token ∈ (live machine.heap.custody field).map Custody.Entry.token) :
    OwnerLocations.Retired machine.heap field.owner := by
  rw [queue_fields_exact] at member
  obtain ⟨queuedAt, detachedAt⟩ := List.mem_filter.mp member
  rcases valid.2 field queuedAt with ordinary | retired
  · have empty := ordinary_queue_has_no_live_entries machine.heap field ordinary
    have equal : queue machine.heap [field] = [field] := by simp [queue, detachedAt]
    rw [equal] at empty
    simp only [List.flatMap_cons, List.flatMap_nil, List.append_nil] at empty
    simp [empty] at liveToken
  · exact retired

theorem heap_token_avoids_retired (store : Heap) (token : CustodyToken) (node : NodeId) (index : Nat)
    (objects : ObjectOwners.Valid store) (scopes : HoldingOwners.Valid store)
    (cellFree : ∀ node stored, store.lookup node = some stored → CellFree stored)
    (absent : store.lookup node = none) (held : Custody.owns store.custody token (.closure node index))
    (member : token ∈ (heapEntries store).map Custody.Entry.token) : False := by
  have split : (heapEntries store).map Custody.Entry.token =
      (store.objects.flatMap fun entry => entry.toList.flatMap (objectEntries store.custody)).map Custody.Entry.token ++
      (store.obligations.flatMap (obligationEntries store.custody)).map Custody.Entry.token ++
      ((store.scopes.flatMap Scope.holdings).flatMap (live store.custody)).map Custody.Entry.token := by
    simp only [heapEntries, heap, objectEntries, obligationEntries, List.flatMap_append, List.map_append, List.flatMap_assoc, List.map_flatMap]
  rw [split] at member
  rcases List.mem_append.mp member with other | scopeAt
  · rcases List.mem_append.mp other with objectAt | protectionAt
    · obtain ⟨parent, slot, stored, found, owned⟩ := heap_object_token_owner store token objects cellFree objectAt
      have equal := Custody.unique_custodian store.custody token _ _ held owned
      cases equal
      simp [found] at absent
    · obtain ⟨id, owned⟩ := heap_protection_token_owner store token protectionAt
      have impossible := Custody.unique_custodian store.custody token _ _ held owned
      cases impossible
  · obtain ⟨scope, slot, owned⟩ := scope_token_owner store token scopes scopeAt
    rcases owned with lexical | temporary
    · have impossible := Custody.unique_custodian store.custody token _ _ held lexical
      cases impossible
    · have impossible := Custody.unique_custodian store.custody token _ _ held temporary
      cases impossible

/-- Active or captured detached queue entries cannot also be heap-owned fields.
Retired parent addresses and live physical parent addresses are disjoint. -/
theorem reachable_heap_queue_tokens_disjoint (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) :
    ∀ token ∈ (heapEntries after.heap).map Custody.Entry.token, token ∉ (queueEntries after).map Custody.Entry.token := by
  have valid := OwnerLocations.initialized_execution_preserves_owner_locations _ _ _ _ _ initialized steps
  have objects := ObjectOwners.initialized_execution_preserves_object_owners _ _ _ _ _ initialized steps
  have scopes := HoldingOwners.initialized_execution_preserves_holding_owners _ _ _ _ _ initialized steps
  have free : ∀ node stored, after.heap.lookup node = some stored → CellFree stored := by
    intro node stored found
    cases stored <;> try trivial
    exact ObjectOwners.reachable_cell_contents_have_no_tokens _ _ _ _ _ initialized steps _ _ _ _ _ found
  intro token heapAt queueAt
  simp only [queueEntries, List.map_flatMap, List.mem_flatMap] at queueAt
  obtain ⟨field, fieldAt, tokenAt⟩ := queueAt
  obtain ⟨node, index, ownerAt, _, absent⟩ := queued_field_retired after field valid fieldAt tokenAt
  have held := live_token_held after.heap.custody field token tokenAt
  rw [ownerAt] at held
  exact heap_token_avoids_retired after.heap token node index objects scopes free absent held heapAt

theorem queue_fields_sublist (machine : State) : (queueFields machine).Sublist (QueueCustody.fields machine) := by
  rw [queue_fields_exact]
  unfold QueueCustody.fields
  apply List.sublist_filter_iff.mpr
  refine ⟨queue machine.heap (OwnerLocations.queuedValues machine), List.filter_sublist, ?_⟩
  symm
  apply List.filter_eq_self.mpr
  intro value member
  have detachedAt := (List.mem_filter.mp member).2
  cases ownerAt : value.owner <;> simp_all [detached, QueueCustody.closureOwner]

private theorem flatMap_congr (values : List α) (first second : α → List β)
    (same : ∀ value ∈ values, first value = second value) : values.flatMap first = values.flatMap second := by
  induction values with
  | nil => rfl
  | cons value values induction =>
    simp only [List.flatMap_cons]
    rw [same value (by simp), induction (fun child member => same child (List.mem_cons_of_mem _ member))]

theorem reachable_queue_entries_are_unique (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : ((queueEntries after).map Custody.Entry.token).Nodup := by
  have valid := QueueCustody.initialized_execution_preserves_queue_custody _ _ _ _ _ initialized steps
  have selected := QueueCustody.Linear.sublist _ _ _ (queue_fields_sublist after) valid
  have exactTokens : (queueEntries after).map Custody.Entry.token = QueueCustody.tokens (queueFields after) := by
    simp only [queueEntries, List.map_flatMap, QueueCustody.tokens]
    apply flatMap_congr
    intro value valueAt
    rw [QueueCustody.live_entry_tokens, liveOwned, QueueCustody.live_tokens]
    exact List.filter_eq_self.mpr (fun token member =>
      List.all_eq_true.mp (Bool.and_eq_true_iff.mp (selected.2 value valueAt)).2 token member)
  rw [exactTokens]
  exact selected.1

/-- Every physical owning field in an actual initialized source state has a
unique live token, including active queues and queues held in resumptions.
The enumeration retains occurrences; no set quotient establishes uniqueness. -/
theorem reachable_entries_are_unique (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : ((entries after).map Custody.Entry.token).Nodup := by
  rw [state_entries_split, List.map_append]
  apply List.nodup_append.mpr
  exact ⟨reachable_heap_entries_are_unique _ _ _ _ _ initialized steps,
    reachable_queue_entries_are_unique _ _ _ _ _ initialized steps,
    fun first firstAt second secondAt same => reachable_heap_queue_tokens_disjoint _ _ _ _ _ initialized steps
      first firstAt (same ▸ secondAt)⟩

end OwningFields
end BoundaryV2.Profile.Source.Machine
