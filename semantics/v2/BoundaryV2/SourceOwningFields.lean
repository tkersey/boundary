import BoundaryV2.SourceLinearityExecution
import BoundaryV2.SourceHoldingExecution
import BoundaryV2.SourceReferenceSafetyExecution

namespace BoundaryV2.Profile.Source.Machine
namespace OwningFields

/-- Canonical heap fields. Suspended scopes remain in the heap, while
ordinary environments and immutable frozen cells retain views of those fields. -/
def object : Object → List Located
  | .closure _ _ bindings => bindings.map Binding.located
  | .cell _ _ _ content | .package _ content | .resource _ content => [content]
  | .capability .. | .region .. | .oneShot .. | .multiTemplate .. | .borrow .. => []

def obligation (record : Cleanup.Obligation .source) : List Located :=
  ⟨record.cleanup, .protection record.id⟩ :: record.resource.toList.map (fun value => ⟨value, .protection record.id⟩)

def heap (store : Heap) : List Located :=
  store.objects.flatMap (fun entry => entry.toList.flatMap object) ++
    store.obligations.flatMap obligation ++ store.scopes.flatMap Scope.holdings

/-- Retired copies retain their old tags. Only occurrences still held by that
field's owner contribute live entries. Filtering keeps list multiplicity. -/
def live (book : Custody.Book) (field : Located) : List Custody.Entry :=
  ((ownedReferences field.value).filter fun pair => Custody.has book pair.1 field.owner).map
    (fun pair => ⟨pair.1, pair.2, field.owner⟩)

def heapEntries (store : Heap) : List Custody.Entry := (heap store).flatMap (live store.custody)

theorem object_subset (stored : Object) (field : Located) (member : field ∈ object stored) :
    field.value ∈ ValueInventory.object stored := by
  cases stored <;> simp_all [object, ValueInventory.object, ValueInventory.environment]
  obtain ⟨binding, member, rfl⟩ := member
  exact ⟨binding, member, rfl⟩

theorem obligation_subset (record : Cleanup.Obligation .source) (field : Located)
    (member : field ∈ obligation record) : field.value ∈ ValueInventory.obligation record := by
  simp only [obligation] at member
  rcases List.mem_cons.mp member with rfl | member
  · simp [ValueInventory.obligation]
  · obtain ⟨value, valueAt, rfl⟩ := List.mem_map.mp member
    apply List.mem_append_left
    exact List.mem_cons_of_mem _ valueAt

theorem heap_subset (store : Heap) (field : Located) (member : field ∈ heap store) :
    field.value ∈ ValueInventory.heap store := by
  simp only [heap, List.mem_append, List.mem_flatMap] at member
  rcases member with ((⟨entry, entryAt, stored, storedAt, member⟩ | ⟨record, recordAt, member⟩) | ⟨scope, scopeAt, member⟩)
  · apply List.mem_append_left
    apply List.mem_append_left
    exact List.mem_flatMap.mpr ⟨entry, entryAt, List.mem_flatMap.mpr ⟨stored, storedAt, object_subset stored field member⟩⟩
  · apply List.mem_append_left
    apply List.mem_append_right
    exact List.mem_flatMap.mpr ⟨record, recordAt, obligation_subset record field member⟩
  · apply List.mem_append_right
    exact List.mem_flatMap.mpr ⟨scope, scopeAt, List.mem_map.mpr ⟨field, member, rfl⟩⟩

theorem heap_fields_in_state (machine : State) (field : Located) (member : field ∈ heap machine.heap) :
    field.value ∈ ValueInventory.state machine := by
  simp only [ValueInventory.state, List.mem_append]
  exact Or.inl (Or.inr (heap_subset machine.heap field member))

theorem live_entry_in_book (book : Custody.Book) (field : Located) (entry : Custody.Entry)
    (aligned : ValueAligned book field.value) (member : entry ∈ live book field) : entry ∈ book.entries := by
  unfold live at member
  obtain ⟨pair, pairAt, rfl⟩ := List.mem_map.mp member
  obtain ⟨present, held⟩ := List.mem_filter.mp pairAt
  obtain ⟨actual, actualAt, token, owner⟩ : ∃ actual ∈ book.entries,
      actual.token = pair.1 ∧ actual.owner = field.owner := by
    simpa only [Custody.has, List.any_eq_true, Bool.and_eq_true, beq_iff_eq] using held
  have node := aligned pair present actual actualAt token
  have same : actual = ⟨pair.1, pair.2, field.owner⟩ := by cases actual; simp_all
  exact same ▸ actualAt


theorem live_tokens_unique (book : Custody.Book) (field : Located)
    (unique : (ownedTokens field.value).Nodup) :
    ((live book field).map Custody.Entry.token).Nodup := by
  simp only [live, List.map_map, Function.comp_def]
  rw [← ownedReferences_tokens field.value] at unique
  exact unique.sublist ((List.filter_sublist).map Prod.fst)

theorem live_token_held (book : Custody.Book) (field : Located) (token : CustodyToken)
    (member : token ∈ (live book field).map Custody.Entry.token) : Custody.owns book token field.owner := by
  simp only [live, List.map_map, Function.comp_def, List.mem_map] at member
  obtain ⟨pair, pairAt, tokenAt⟩ := member
  have held := (List.mem_filter.mp pairAt).2
  rw [tokenAt] at held
  simpa only [Custody.has, Custody.owns, List.any_eq_true, Bool.and_eq_true, beq_iff_eq] using held

/-- Distinct physical owners plus per-value occurrence uniqueness prevent
live tokens from appearing twice, even when stored values retain stale aliases. -/
theorem unique_owners_give_unique_live_tokens (book : Custody.Book) (fields : List Located)
    (owners : (fields.map Located.owner).Nodup)
    (values : ∀ field ∈ fields, (ownedTokens field.value).Nodup) :
    ((fields.flatMap (live book)).map Custody.Entry.token).Nodup := by
  simp only [List.map_flatMap]
  apply List.pairwise_flatMap.mpr
  refine ⟨fun field member => live_tokens_unique book field (values field member), ?_⟩
  apply (List.pairwise_map.mp owners).imp_of_mem
  intro first second _ _ distinct firstToken firstAt secondToken secondAt same
  apply distinct
  apply Custody.unique_custodian book firstToken first.owner second.owner
  · exact live_token_held book first firstToken firstAt
  · exact live_token_held book second firstToken (same ▸ secondAt)

theorem reachable_scope_entries_are_unique (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) :
    (((after.heap.scopes.flatMap Scope.holdings).flatMap (live after.heap.custody)).map Custody.Entry.token).Nodup := by
  apply unique_owners_give_unique_live_tokens
  · simpa only [List.map_flatMap] using
      HoldingOwners.reachable_scope_owners_are_unique _ _ _ _ _ initialized steps
  · intro field member
    apply ValueLinearity.initialized_execution_preserves_linearity _ _ _ _ _ initialized steps
    apply heap_fields_in_state
    apply List.mem_append_right
    exact member

/-- Values queued after their original closure or package is retired own the
remaining work. Queues whose original field still exists contain views. -/
def detached (store : Heap) (field : Located) : Bool := match field.owner with
  | .closure node _ => (store.lookup node).isNone
  | _ => false

def queue (store : Heap) (values : List Located) : List Located := values.filter (detached store)

def frame (store : Heap) : Frame → List Located
  | .disposalReturn remaining .. => queue store remaining
  | _ => []

def capture (store : Heap) (saved : Capture) : List Located := saved.frames.flatMap (frame store)

def captured (store : Heap) : Object → List Located
  | .oneShot saved | .multiTemplate saved => capture store saved
  | _ => []

def control (store : Heap) : Control → List Located
  | .discard remaining _ => queue store remaining
  | _ => []

/-- Finite storage occurrences, including active and captured disposal queues.
No graph-path expansion or token deduplication enters this enumeration. -/
def state (machine : State) : List Located :=
  heap machine.heap ++ control machine.heap machine.control ++
    machine.stack.flatMap (frame machine.heap) ++
    machine.heap.objects.flatMap (fun entry => entry.toList.flatMap (captured machine.heap))

def entries (machine : State) : List Custody.Entry := (state machine).flatMap (live machine.heap.custody)

theorem frame_subset (store : Heap) (saved : Frame) (field : Located) (member : field ∈ frame store saved) :
    field.value ∈ ValueInventory.frame saved := by
  cases saved <;> simp only [frame, List.not_mem_nil] at member
  case disposalReturn remaining released invocation scope =>
    have belongs := (List.mem_filter.mp member).1
    exact List.mem_append_left _ (List.mem_map.mpr ⟨field, belongs, rfl⟩)

theorem captured_subset (store : Heap) (saved : Object) (field : Located)
    (member : field ∈ captured store saved) : field.value ∈ ValueInventory.object saved := by
  cases saved <;> simp only [captured, List.not_mem_nil] at member
  all_goals
    obtain ⟨saved, savedAt, member⟩ := List.mem_flatMap.mp member
    have belongs := frame_subset store saved field member
    simp only [ValueInventory.object, ValueInventory.capture, List.mem_append]
    exact Or.inl (Or.inl (Or.inl (List.mem_flatMap.mpr ⟨saved, savedAt, belongs⟩)))

theorem control_subset (store : Heap) (executing : Control) (field : Located)
    (member : field ∈ control store executing) : field.value ∈ ValueInventory.control executing := by
  cases executing <;> simp only [control, List.not_mem_nil] at member
  have belongs := (List.mem_filter.mp member).1
  exact List.mem_append_left _ (List.mem_map.mpr ⟨field, belongs, rfl⟩)

theorem state_subset (machine : State) (field : Located) (member : field ∈ state machine) :
    field.value ∈ ValueInventory.state machine := by
  simp only [state, List.mem_append, List.mem_flatMap] at member
  rcases member with (((stored | pending) | ⟨saved, savedAt, member⟩) | ⟨entry, entryAt, saved, savedAt, member⟩)
  · exact heap_fields_in_state machine field stored
  · have belongs := control_subset machine.heap machine.control field pending
    simp only [ValueInventory.state, List.mem_append]
    exact Or.inl (Or.inl (Or.inl belongs))
  · have belongs := frame_subset machine.heap saved field member
    simp only [ValueInventory.state, List.mem_append]
    exact Or.inl (Or.inl (Or.inr (List.mem_flatMap.mpr ⟨saved, savedAt, belongs⟩)))
  · have belongs := captured_subset machine.heap saved field member
    apply List.mem_append_left
    apply List.mem_append_right
    apply List.mem_append_left
    apply List.mem_append_left
    exact List.mem_flatMap.mpr ⟨entry, entryAt, List.mem_flatMap.mpr ⟨saved, savedAt, belongs⟩⟩

/-- Every listed occurrence has a matching actual custody record. Coverage and
cross-field multiplicity remain separate obligations for the full bijection. -/
theorem reachable_entries_in_book (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : entries after ⊆ after.heap.custody.entries := by
  have aligned := ReferenceSafety.values_aligned
    (ReferenceSafety.initialized_execution_preserves_reference_safety _ _ _ _ _ initialized steps)
  intro entry member
  obtain ⟨field, fieldAt, member⟩ := List.mem_flatMap.mp member
  exact live_entry_in_book _ _ _ (aligned field.value (state_subset after field fieldAt)) member

theorem reachable_fields_linear (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) :
    ∀ field ∈ state after, (ownedTokens field.value).Nodup := by
  intro field member
  exact ValueLinearity.initialized_execution_preserves_linearity _ _ _ _ _ initialized steps
    field.value (state_subset after field member)

end OwningFields
end BoundaryV2.Profile.Source.Machine
