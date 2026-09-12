import BoundaryV2.SourceOwnerLocationExecution
import BoundaryV2.SourceOwningObjectFields

namespace BoundaryV2.Profile.Source.Machine
namespace QueueCustody

def closureOwner : Custody.Owner → Bool
  | .closure .. => true
  | _ => false

/-- Raw detached owning leaves, without consulting mutable custody or lookup
state. Ordinary scope disposal entries remain views of their retained slots. -/
def fields (machine : State) : List Located :=
  OwnerLocations.queuedValues machine |>.filter (fun value => closureOwner value.owner)

def tokens (values : List Located) : List CustodyToken := values.flatMap (fun value => ownedTokens value.value)

def Linear (heap : Heap) (values : List Located) : Prop :=
  (tokens values).Nodup ∧ ∀ value ∈ values, current heap value = true

def Valid (machine : State) : Prop := Linear machine.heap (fields machine)

theorem raw_leaves (machine : State) (valid : DisposalShape.Valid machine) :
    ∀ value ∈ OwnerLocations.queuedValues machine, DisposalProgress.Leaf value := by
  intro value member
  simp only [OwnerLocations.queuedValues, List.mem_append, List.mem_flatMap] at member
  rcases member with (executing | stacked) | ⟨entry, entryAt, stored, storedAt, valueAt⟩
  · exact valid.1 value executing
  · exact valid.2.1 value (List.mem_flatMap.mpr stacked)
  · exact valid.2.2 entry entryAt value (List.mem_flatMap.mpr ⟨stored, storedAt, valueAt⟩)

theorem closure_owner_retired (heap : Heap) (value : Located) (queued : OwnerLocations.Queued heap value)
    (leaf : DisposalProgress.Leaf value) (closed : closureOwner value.owner = true) :
    OwnerLocations.Retired heap value.owner := by
  rcases queued with ordinary | retired
  · rcases ordinary with inScope | free
    · cases ownerAt : value.owner <;> simp_all [OwnerLocations.Scoped, closureOwner]
    · obtain ⟨schema, node, token, shape⟩ := leaf
      simp [shape, ownedTokens] at free
  · exact retired

theorem initialized_fields_retired (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) :
    ∀ value ∈ fields after, OwnerLocations.Retired after.heap value.owner := by
  have owners := OwnerLocations.initialized_execution_preserves_owner_locations _ _ _ _ _ initialized steps
  have leaves := DisposalShape.initialized_execution_preserves_disposal_leaves _ _ _ _ _ initialized steps
  intro value member
  obtain ⟨valueAt, closed⟩ := List.mem_filter.mp member
  exact closure_owner_retired after.heap value (owners.2 value valueAt) (raw_leaves after leaves value valueAt) closed

theorem ordinary_fields_empty (values : List Located) (ordinary : ∀ value ∈ values, OwnerLocations.Ordinary value)
    (leaves : ∀ value ∈ values, DisposalProgress.Leaf value) :
    values.filter (fun value => closureOwner value.owner) = [] := by
  apply List.filter_eq_nil_iff.mpr
  intro value member
  cases ownerAt : value.owner <;> try (solve | simp [closureOwner])
  rcases ordinary value member with inScope | free
  · simp [ownerAt, OwnerLocations.Scoped] at inScope
  · obtain ⟨schema, node, token, shape⟩ := leaves value member
    simp [shape, ownedTokens] at free

private theorem flatMap_congr (values : List α) (first second : α → List β)
    (same : ∀ value ∈ values, first value = second value) : values.flatMap first = values.flatMap second := by
  induction values with
  | nil => rfl
  | cons value values induction =>
    simp only [List.flatMap_cons]
    rw [same value (by simp), induction (fun child member => same child (List.mem_cons_of_mem _ member))]

theorem live_tokens (heap : Heap) (owner : Custody.Owner) (value : SemanticValue) :
    tokens (liveOwnedValue heap owner value) = (ownedTokens value).filter (fun token => Custody.has heap.custody token owner) := by
  cases value with
  | reference schema node token =>
    cases token <;> simp only [liveOwnedValue, ownedTokens, Option.toList]
    · rfl
    · split <;> simp_all [tokens, ownedTokens]
  | product schema fields | sequence schema fields =>
    simp only [liveOwnedValue, ownedTokens, tokens, List.flatMap_assoc, List.filter_flatMap]
    apply flatMap_congr
    intro child member
    exact live_tokens heap owner child
  | variant schema tag payload =>
    simp only [liveOwnedValue, ownedTokens]
    exact live_tokens heap owner payload
  | scalar schema payload | blob schema payload => simp [liveOwnedValue, tokens, ownedTokens]
termination_by sizeOf value
decreasing_by
  all_goals subst value
  all_goals simp_wf
  all_goals first | omega | exact Nat.lt_trans (List.sizeOf_lt_of_mem member) (by omega)

theorem live_current (heap : Heap) (owner : Custody.Owner) (value : SemanticValue) :
    ∀ child ∈ liveOwnedValue heap owner value, current heap child = true := by
  cases value with
  | reference schema node token =>
    cases token <;> simp only [liveOwnedValue]
    · simp
    · split <;> simp_all [current, ownedTokens]
  | product schema fields | sequence schema fields =>
    intro child member
    simp only [liveOwnedValue] at member
    obtain ⟨original, originalAt, childAt⟩ := List.mem_flatMap.mp member
    exact live_current heap owner original child childAt
  | variant schema tag payload =>
    simp only [liveOwnedValue]
    exact live_current heap owner payload
  | scalar schema payload | blob schema payload => simp [liveOwnedValue]
termination_by sizeOf value
decreasing_by
  all_goals subst value
  all_goals simp_wf
  all_goals first | omega | exact Nat.lt_trans (List.sizeOf_lt_of_mem originalAt) (by omega)

theorem live_linear (heap : Heap) (value : Located) (linear : (ownedTokens value.value).Nodup) :
    Linear heap (liveOwned heap value) := by
  refine ⟨?_, live_current heap value.owner value.value⟩
  rw [liveOwned, live_tokens]
  exact linear.sublist List.filter_sublist

theorem current_of_entries (before after : Heap) (value : Located)
    (kept : ∀ entry ∈ before.custody.entries, entry.token ∈ ownedTokens value.value → entry.owner = value.owner → entry ∈ after.custody.entries)
    (usable : current before value = true) : current after value = true := by
  obtain ⟨unique, held⟩ := Bool.and_eq_true_iff.mp usable
  apply Bool.and_eq_true_iff.mpr
  refine ⟨unique, List.all_eq_true.mpr ?_⟩
  intro token member
  have present := List.all_eq_true.mp held token member
  obtain ⟨entry, entryAt, tokenAt, ownerAt⟩ : ∃ entry ∈ before.custody.entries,
      entry.token = token ∧ entry.owner = value.owner := by
    simpa only [Custody.has, List.any_eq_true, Bool.and_eq_true, beq_iff_eq] using present
  exact List.any_eq_true.mpr ⟨entry, kept entry entryAt (tokenAt ▸ member) ownerAt, by simp [tokenAt, ownerAt]⟩

theorem commit_keeps_entry (before after : Custody.Book) (moves : List Custody.Move) (entry : Custody.Entry)
    (accepted : Custody.commit before moves = some after) (present : entry ∈ before.entries)
    (separate : ∀ move ∈ moves, move.source ≠ entry.owner) : entry ∈ after.entries := by
  have absent : moves.find? (fun move => move.token == entry.token) = none := by
    apply List.find?_eq_none.mpr
    intro move member
    intro same
    have same : move.token = entry.token := by simpa using same
    have sender := Custody.commit_checks_every_sender before moves after accepted member
    have held : Custody.owns before entry.token move.source := by
      simpa only [Custody.has, Custody.owns, List.any_eq_true, Bool.and_eq_true, beq_iff_eq, same] using sender
    exact separate move member (Custody.unique_custodian before entry.token _ _ held ⟨entry, present, rfl, rfl⟩)
  unfold Custody.commit at accepted
  split at accepted <;> try contradiction
  cases accepted
  apply List.mem_map.mpr
  exact ⟨entry, present, by simp [Custody.destination, absent]⟩

theorem consume_keeps_entry (before after : Custody.Book) (removed : List CustodyToken) (owner : Custody.Owner)
    (entry : Custody.Entry) (accepted : Custody.consume before removed owner = some after)
    (present : entry ∈ before.entries) (notRemoved : entry.token ∉ removed) : entry ∈ after.entries := by
  unfold Custody.consume at accepted
  split at accepted <;> try contradiction
  cases accepted
  exact List.mem_filter.mpr ⟨present, by simpa using notRemoved⟩

theorem allocation_keeps_current (heap after : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (created pinned : Located)
    (accepted : allocateObject heap schema stored owner exclusive = some (after, created))
    (usable : current heap pinned = true) : current after pinned = true := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, _⟩ := accepted; exact usable
  · obtain ⟨book, allocated, rfl, _⟩ := accepted
    apply current_of_entries heap _ pinned ?_ usable
    intro entry member _ _
    rw [(Custody.allocation_is_fresh _ _ _ _ _ allocated).2.2]
    exact List.mem_cons_of_mem _ member

theorem moves_keep_current (before after : Heap) (values : List Located) (receiver : Nat → Custody.Owner)
    (pinned : Located) (accepted : moveValues before values receiver = some after)
    (usable : current before pinned = true)
    (separate : ∀ value ∈ values, value.owner ≠ pinned.owner ∨ ownedTokens value.value = []) :
    current after pinned = true := by
  simp only [moveValues, bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨book, committed, rfl⟩ := accepted
  apply current_of_entries before _ pinned ?_ usable
  intro entry member _ ownerAt
  apply commit_keeps_entry _ _ _ entry committed member
  intro move moving
  obtain ⟨list, listAt, moveAt⟩ := List.mem_flatten.mp moving
  obtain ⟨index, inBounds, rfl⟩ := List.mem_mapIdx.mp listAt
  obtain ⟨token, tokenAt, rfl⟩ := List.mem_map.mp moveAt
  rcases separate values[index] (List.getElem_mem _) with different | free
  · simpa only [ownerAt] using different
  · simp [free] at tokenAt

theorem ordinary_move_keeps_closure (before after : Heap) (values : List Located) (receiver : Nat → Custody.Owner)
    (pinned : Located) (accepted : moveValues before values receiver = some after)
    (usable : current before pinned = true) (closed : closureOwner pinned.owner = true)
    (ordinary : ∀ value ∈ values, OwnerLocations.Ordinary value) : current after pinned = true := by
  apply moves_keep_current _ _ _ _ _ accepted usable
  intro value member
  rcases ordinary value member with inScope | free
  · left
    intro same
    rw [same] at inScope
    cases ownerAt : pinned.owner <;> simp_all [closureOwner, OwnerLocations.Scoped]
  · exact Or.inr free

theorem consume_keeps_current (before after : Heap) (value pinned : Located)
    (accepted : consumeValue before value = some after) (usable : current before pinned = true)
    (separate : ∀ token ∈ ownedTokens pinned.value, token ∉ ownedTokens value.value) : current after pinned = true := by
  simp only [consumeValue, bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨book, consumed, rfl⟩ := accepted
  apply current_of_entries before _ pinned ?_ usable
  intro entry member tokenAt _
  exact consume_keeps_entry _ _ _ _ entry consumed member (separate entry.token tokenAt)

theorem consume_distinct_owner_keeps_current (before after : Heap) (value pinned : Located)
    (accepted : consumeValue before value = some after) (usable : current before pinned = true)
    (separate : value.owner ≠ pinned.owner) : current after pinned = true := by
  apply consume_keeps_current _ _ _ _ accepted usable
  intro token pinnedAt valueAt
  have pinnedHeld := List.all_eq_true.mp (Bool.and_eq_true_iff.mp usable).2 token pinnedAt
  have checked : (ownedTokens value.value).all (fun token => Custody.has before.custody token value.owner) = true := by
    simp only [consumeValue, bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
    obtain ⟨book, consumed, _⟩ := accepted
    unfold Custody.consume at consumed
    split at consumed <;> try contradiction
    exact (Bool.and_eq_true_iff.mp (by assumption)).2
  have valueHeld := List.all_eq_true.mp checked token valueAt
  have first : Custody.owns before.custody token value.owner := by
    simpa only [Custody.has, Custody.owns, List.any_eq_true, Bool.and_eq_true, beq_iff_eq] using valueHeld
  have second : Custody.owns before.custody token pinned.owner := by
    simpa only [Custody.has, Custody.owns, List.any_eq_true, Bool.and_eq_true, beq_iff_eq] using pinnedHeld
  exact separate (Custody.unique_custodian _ _ _ _ first second)

theorem retire_keeps_current (before after : Heap) (value pinned : Located)
    (accepted : retireObject before value = some after) (usable : current before pinned = true)
    (separate : ∀ token ∈ ownedTokens pinned.value, token ∉ ownedTokens value.value) : current after pinned = true := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨_, _, middle, consumed, rfl⟩ := accepted
  exact consume_keeps_current before middle value pinned consumed usable separate

theorem Linear.sublist (heap : Heap) (before after : List Located)
    (included : after.Sublist before) (valid : Linear heap before) : Linear heap after := by
  have tokenSubset : (tokens after).Sublist (tokens before) := by
    clear valid
    induction included with
    | slnil => exact .slnil
    | cons value included ih =>
      exact ih.trans (List.sublist_append_right (ownedTokens value.value) _)
    | cons_cons value included ih => exact ih.append_left _
  exact ⟨valid.1.sublist tokenSubset, fun value member => valid.2 value (included.subset member)⟩

theorem Linear.perm (heap : Heap) (before after : List Located) (same : before.Perm after)
    (valid : Linear heap before) : Linear heap after := by
  have tokenSame : (tokens before).Perm (tokens after) := by
    clear valid
    induction same with
    | nil => exact .nil
    | cons value same ih => exact List.Perm.append_left _ ih
    | swap first second values =>
      simp only [tokens, List.flatMap_cons]
      simpa only [List.append_assoc] using List.Perm.append_right (values.flatMap (fun value => ownedTokens value.value))
        (List.perm_append_comm (l₁ := ownedTokens second.value) (l₂ := ownedTokens first.value))
    | trans _ _ first second => exact first.trans second
  exact ⟨valid.1.perm tokenSame, fun value member => valid.2 value (same.mem_iff.mpr member)⟩

theorem Linear.append (heap : Heap) (first second : List Located) (left : Linear heap first) (right : Linear heap second)
    (separate : ∀ token ∈ tokens first, token ∉ tokens second) : Linear heap (first ++ second) := by
  constructor
  · simp only [tokens, List.flatMap_append]
    exact List.nodup_append.mpr ⟨left.1, right.1, fun first firstAt second secondAt same => separate first firstAt (same ▸ secondAt)⟩
  · intro value member
    exact (List.mem_append.mp member).elim (left.2 value) (right.2 value)

theorem Linear.heap (before after : Heap) (values : List Located) (valid : Linear before values)
    (kept : ∀ value ∈ values, current before value = true → current after value = true) : Linear after values :=
  ⟨valid.1, fun value member => kept value member (valid.2 value member)⟩

theorem Linear.nil (heap : Heap) : Linear heap [] := by simp [Linear, tokens]

def controlFields (executing : Control) : List Located :=
  (DisposalShape.control executing).filter (fun value => closureOwner value.owner)

def frameFields (saved : Frame) : List Located :=
  (DisposalShape.frame saved).filter (fun value => closureOwner value.owner)

def objectFields (stored : Object) : List Located :=
  (DisposalShape.object stored).filter (fun value => closureOwner value.owner)

def heapFields (heap : Heap) : List Located :=
  heap.objects.flatMap (fun entry => entry.toList.flatMap objectFields)

theorem fields_components (machine : State) : fields machine =
    controlFields machine.control ++ machine.stack.flatMap frameFields ++ heapFields machine.heap := by
  simp only [fields, controlFields, heapFields, OwnerLocations.queuedValues,
    List.filter_append, List.filter_flatMap]
  rfl

theorem Linear.parts (heap : Heap) (first second : List Located) (valid : Linear heap (first ++ second)) :
    Linear heap first ∧ Linear heap second ∧ ∀ token ∈ tokens first, token ∉ tokens second := by
  have unique := List.nodup_append.mp (show (tokens first ++ tokens second).Nodup by simpa only [tokens, List.flatMap_append] using valid.1)
  exact ⟨⟨unique.1, fun value member => valid.2 value (List.mem_append_left _ member)⟩,
    ⟨unique.2.1, fun value member => valid.2 value (List.mem_append_right _ member)⟩,
    fun token firstAt secondAt => unique.2.2 token firstAt token secondAt rfl⟩

theorem fields_valid (machine : State) (valid : Valid machine) :
    Linear machine.heap (controlFields machine.control ++ machine.stack.flatMap frameFields ++ heapFields machine.heap) := by
  simpa only [Valid, fields_components] using valid

theorem empty_control_valid (machine : State) (next : Control) (valid : Valid machine)
    (empty : controlFields next = []) : Valid {machine with control := next} := by
  have old := fields_valid machine valid
  have retained : Linear machine.heap (machine.stack.flatMap frameFields ++ heapFields machine.heap) := by
    apply Linear.sublist _ _ _ _ old
    simpa only [List.append_assoc] using List.sublist_append_right (controlFields machine.control)
      (machine.stack.flatMap frameFields ++ heapFields machine.heap)
  simpa only [Valid, fields_components, empty, List.nil_append] using retained

private theorem flatMap_sublist (before after : List α) (f : α → List β) (included : after.Sublist before) :
    (after.flatMap f).Sublist (before.flatMap f) := by
  induction included with
  | slnil => exact .slnil
  | cons value included ih => exact ih.trans (List.sublist_append_right (f value) _)
  | cons_cons value included ih => exact ih.append_left _

theorem substack_valid (machine : State) (next : List Frame) (valid : Valid machine)
    (included : next.Sublist machine.stack) : Valid {machine with stack := next} := by
  have old := fields_valid machine valid
  have sublist := ((flatMap_sublist _ _ frameFields included).append_left (controlFields machine.control)).append_right (heapFields machine.heap)
  simpa only [Valid, fields_components] using Linear.sublist machine.heap _ _ sublist old

theorem same_storage_valid (machine : State) (heap : Heap) (valid : Valid machine)
    (objects : heap.objects = machine.heap.objects)
    (custody : heap.custody = machine.heap.custody) : Valid {machine with heap := heap} := by
  simpa only [Valid, fields_components, heapFields, Linear, current, objects, custody] using valid

theorem temporary_valid (machine after : State) (owner : Custody.Owner)
    (accepted : temporary machine = .ok (after, owner)) (valid : Valid machine) : Valid after := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  exact valid

theorem finishTemporary_valid (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  cases accepted
  exact empty_control_valid machine (.delivered value) valid rfl

theorem fields_same_objects (machine : State) (heap : Heap) (same : heap.objects = machine.heap.objects) :
    fields {machine with heap := heap} = fields machine := by
  simp only [fields_components, heapFields, same]

theorem move_valid (machine : State) (heap : Heap) (values : List Located) (receiver : Nat → Custody.Owner)
    (accepted : moveValues machine.heap values receiver = some heap) (valid : Valid machine)
    (separate : ∀ value ∈ values, ∀ pinned ∈ fields machine,
      value.owner ≠ pinned.owner ∨ ownedTokens value.value = []) : Valid {machine with heap := heap} := by
  have same := fields_same_objects machine heap (ObjectOwners.move_objects _ _ _ _ accepted)
  unfold Valid
  rw [same]
  apply Linear.heap machine.heap heap (fields machine) valid
  intro pinned pinnedAt usable
  exact moves_keep_current _ _ _ _ _ accepted usable (fun value member => separate value member pinned pinnedAt)

theorem move_ordinary_valid (machine : State) (heap : Heap) (values : List Located) (receiver : Nat → Custody.Owner)
    (accepted : moveValues machine.heap values receiver = some heap) (valid : Valid machine)
    (ordinary : ∀ value ∈ values, OwnerLocations.Ordinary value) : Valid {machine with heap := heap} := by
  apply move_valid _ _ _ _ accepted valid
  intro value valueAt pinned pinnedAt
  have closed := (List.mem_filter.mp pinnedAt).2
  rcases ordinary value valueAt with inScope | free
  · left
    intro same
    rw [same] at inScope
    cases ownerAt : pinned.owner <;> simp_all [closureOwner, OwnerLocations.Scoped]
  · exact Or.inr free

theorem consume_valid (machine : State) (heap : Heap) (value : Located)
    (accepted : consumeValue machine.heap value = some heap) (valid : Valid machine)
    (separate : ∀ token ∈ tokens (fields machine), token ∉ ownedTokens value.value) : Valid {machine with heap := heap} := by
  have same := fields_same_objects machine heap (ObjectOwners.consume_objects _ _ _ accepted)
  unfold Valid
  rw [same]
  apply Linear.heap machine.heap heap (fields machine) valid
  intro pinned pinnedAt usable
  apply consume_keeps_current _ _ _ _ accepted usable
  intro token tokenAt
  exact separate token (List.mem_flatMap.mpr ⟨pinned, pinnedAt, tokenAt⟩)

theorem consume_ordinary_valid (machine : State) (heap : Heap) (value : Located)
    (accepted : consumeValue machine.heap value = some heap) (valid : Valid machine)
    (ordinary : OwnerLocations.Ordinary value) : Valid {machine with heap := heap} := by
  have same := fields_same_objects machine heap (ObjectOwners.consume_objects _ _ _ accepted)
  unfold Valid
  rw [same]
  apply Linear.heap machine.heap heap (fields machine) valid
  intro pinned pinnedAt usable
  rcases ordinary with inScope | free
  · apply consume_distinct_owner_keeps_current _ _ _ _ accepted usable
    intro same
    have closed := (List.mem_filter.mp pinnedAt).2
    rw [same] at inScope
    cases ownerAt : pinned.owner <;> simp_all [closureOwner, OwnerLocations.Scoped]
  · exact consume_keeps_current _ _ _ _ accepted usable (by simp [free])

private theorem flatMap_set_empty (values : List α) (index : Nat) (replacement : α) (f : α → List β)
    (empty : f replacement = []) : ((values.set index replacement).flatMap f).Sublist (values.flatMap f) := by
  induction values generalizing index with
  | nil => simp
  | cons value values induction =>
    cases index with
    | zero => simpa only [List.set_cons_zero, List.flatMap_cons, empty, List.nil_append] using List.sublist_append_right (f value) (values.flatMap f)
    | succ index => exact (induction index).append_left (f value)

theorem erase_object_valid (machine : State) (index : Nat) (valid : Valid machine) :
    Valid {machine with heap := {machine.heap with objects := machine.heap.objects.set index none}} := by
  have included := flatMap_set_empty machine.heap.objects index none
    (fun entry => entry.toList.flatMap objectFields) rfl
  have allFields := included.append_left (controlFields machine.control ++ machine.stack.flatMap frameFields)
  have next := Linear.sublist machine.heap _ _ allFields (fields_valid machine valid)
  simpa only [Valid, fields_components, Linear, current, heapFields] using next

theorem retire_valid (machine : State) (heap : Heap) (value : Located)
    (accepted : retireObject machine.heap value = some heap) (valid : Valid machine)
    (separate : ∀ token ∈ tokens (fields machine), token ∉ ownedTokens value.value) : Valid {machine with heap := heap} := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨_, _, middle, consumed, rfl⟩ := accepted
  exact erase_object_valid {machine with heap := middle} _ (consume_valid _ _ _ consumed valid separate)

theorem retire_ordinary_valid (machine : State) (heap : Heap) (value : Located)
    (accepted : retireObject machine.heap value = some heap) (valid : Valid machine)
    (ordinary : OwnerLocations.Ordinary value) : Valid {machine with heap := heap} := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨_, _, middle, consumed, rfl⟩ := accepted
  exact erase_object_valid {machine with heap := middle} _ (consume_ordinary_valid _ _ _ consumed valid ordinary)

theorem allocate_empty_valid (machine : State) (heap : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject machine.heap schema stored owner exclusive = some (heap, value))
    (valid : Valid machine) (empty : objectFields stored = []) : Valid {machine with heap := heap} := by
  have objects : heap.objects = machine.heap.objects ++ [some stored] := by
    cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
    · obtain ⟨rfl, _⟩ := accepted; rfl
    · obtain ⟨_, _, rfl, _⟩ := accepted; rfl
  have same : fields {machine with heap := heap} = fields machine := by
    simp only [fields_components, heapFields, objects, List.flatMap_append, List.flatMap_cons,
      List.flatMap_nil, Option.toList_some, empty, List.append_nil]
  unfold Valid
  rw [same]
  exact Linear.heap _ _ _ valid (fun pinned _ usable => allocation_keeps_current _ _ _ _ _ _ _ _ accepted usable)

theorem retire_ordinary_keeps_current (before after : Heap) (value pinned : Located)
    (accepted : retireObject before value = some after) (usable : current before pinned = true)
    (ordinary : OwnerLocations.Ordinary value) (closed : closureOwner pinned.owner = true) : current after pinned = true := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨_, _, middle, consumed, rfl⟩ := accepted
  rcases ordinary with inScope | free
  · apply consume_distinct_owner_keeps_current before middle value pinned consumed usable
    intro same
    rw [same] at inScope
    cases ownerAt : pinned.owner <;> simp_all [closureOwner, OwnerLocations.Scoped]
  · exact consume_keeps_current before middle value pinned consumed usable (by simp [free])

private theorem flatMap_remove_perm (values : List α) (index : Nat) (removed replacement : α)
    (f : α → List β) (found : values[index]? = some removed) (empty : f replacement = []) :
    (values.flatMap f).Perm ((values.set index replacement).flatMap f ++ f removed) := by
  induction values generalizing index with
  | nil => simp at found
  | cons value values induction =>
    cases index with
    | zero =>
      cases found
      simpa only [List.set_cons_zero, List.flatMap_cons, empty, List.nil_append] using
        (List.perm_append_comm (l₁ := f removed) (l₂ := values.flatMap f))
    | succ index =>
      simpa only [List.set_cons_succ, List.flatMap_cons, List.append_assoc] using
        List.Perm.append_left (f value) (induction index found)

theorem erase_object_partition (machine : State) (node : NodeId) (stored : Object)
    (found : machine.heap.lookup node = some stored) :
    (fields machine).Perm
      (fields {machine with heap := {machine.heap with objects := machine.heap.objects.set node.value none}} ++ objectFields stored) := by
  have position : machine.heap.objects[node.value]? = some (some stored) := by
    simp only [Heap.lookup, Option.bind_eq_some_iff] at found
    obtain ⟨entry, atEntry, isStored⟩ := found
    cases entry <;> try contradiction
    cases isStored
    exact atEntry
  have partition := flatMap_remove_perm machine.heap.objects node.value (some stored) none
    (fun entry => entry.toList.flatMap objectFields) position rfl
  have allFields := List.Perm.append_left (controlFields machine.control ++ machine.stack.flatMap frameFields) partition
  simpa only [fields_components, heapFields, Option.toList_some, List.flatMap_singleton, List.append_assoc] using allFields

theorem retire_partition (machine : State) (heap : Heap) (value : Located) (node : NodeId) (stored : Object)
    (looked : lookupObject machine value = .ok (node, stored))
    (accepted : retireObject machine.heap value = some heap) :
    (fields machine).Perm (fields {machine with heap := heap} ++ objectFields stored) := by
  obtain ⟨⟨schema, token, reference⟩, found⟩ := CellStability.lookupObject_reference _ _ _ _ looked
  unfold retireObject at accepted
  rw [reference] at accepted
  cases token <;> try contradiction
  simp only [bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨_, _, middle, consumed, rfl⟩ := accepted
  have same := ObjectOwners.consume_objects _ _ _ consumed
  simpa only [fields_components, heapFields, same] using erase_object_partition machine node stored found

theorem retire_ordinary_partition_linear (machine : State) (heap : Heap) (value : Located) (node : NodeId) (stored : Object)
    (looked : lookupObject machine value = .ok (node, stored))
    (accepted : retireObject machine.heap value = some heap) (valid : Valid machine)
    (ordinary : OwnerLocations.Ordinary value) :
    Linear heap (fields {machine with heap := heap} ++ objectFields stored) := by
  have kept : Linear heap (fields machine) := Linear.heap _ _ _ valid (by
    intro pinned pinnedAt usable
    exact retire_ordinary_keeps_current _ _ _ _ accepted usable ordinary (List.mem_filter.mp pinnedAt).2)
  exact Linear.perm _ _ _ (retire_partition _ _ _ _ _ looked accepted) kept

end QueueCustody
end BoundaryV2.Profile.Source.Machine
