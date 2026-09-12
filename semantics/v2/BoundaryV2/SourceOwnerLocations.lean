import BoundaryV2.SourceObjectOwnerExecution
import BoundaryV2.SourceDisposalExecution
import BoundaryV2.SourceTokenExecution
import BoundaryV2.SourceHoldingOwners

namespace BoundaryV2.Profile.Source.Machine
namespace OwnerLocations

/-- Ordinary executing values are views of lexical/temporary slots, or carry
no exclusive token. Heap-owned children enter explicit disposal queues. -/
def Scoped : Custody.Owner → Prop
  | .lexical .. | .temporary .. => True
  | _ => False

def Ordinary (value : Located) : Prop := Scoped value.owner ∨ ownedTokens value.value = []

def Retired (heap : Heap) (owner : Custody.Owner) : Prop :=
  ∃ node index, owner = .closure node index ∧ node.value < heap.objects.length ∧ heap.lookup node = none

def Queued (heap : Heap) (value : Located) : Prop := Ordinary value ∨ Retired heap value.owner

def afterValues : AfterRelease → List Located
  | .deliver value => [value]
  | .unwind _ => []

def activationValues (active : Activation) : List Located := active.environment.map Binding.located ++ active.state

def frameValues : Frame → List Located
  | .binding _ _ bindings _ => bindings.map Binding.located
  | .operands _ bindings _ evaluated => bindings.map Binding.located ++ evaluated
  | .handler active => activationValues active
  | .cleanupReturn _ _ _ normal => normal.toList
  | .disposalReturn _ after .. | .releaseReturn _ after => afterValues after
  | .injection values => values
  | _ => []

def captureValues (saved : Capture) : List Located :=
  saved.frames.flatMap frameValues ++ activationValues saved.delimiter ++ saved.useSiteCapabilities

def objectValues : Object → List Located
  | .oneShot saved | .multiTemplate saved => captureValues saved
  | _ => []

def heapValues (heap : Heap) : List Located :=
  heap.objects.flatMap (fun entry => entry.toList.flatMap objectValues) ++ heap.scopes.flatMap Scope.holdings

def controlValues : Control → List Located
  | .term _ bindings | .expression _ bindings => bindings.map Binding.located
  | .execute _ bindings values | .invoke _ bindings values => bindings.map Binding.located ++ values
  | .delivered value => [value]
  | .release _ after | .discard _ after => afterValues after
  | .unwind _ => []

def statusValues : Status → List Located
  | .parked request => request.bodies ++ request.useSiteCapabilities
  | _ => []

def ordinaryValues (machine : State) : List Located :=
  controlValues machine.control ++ machine.stack.flatMap frameValues ++ heapValues machine.heap ++ statusValues machine.status

def queuedValues (machine : State) : List Located :=
  DisposalShape.control machine.control ++ machine.stack.flatMap DisposalShape.frame ++
    machine.heap.objects.flatMap (fun entry => entry.toList.flatMap DisposalShape.object)

def Normal (machine : State) : Prop := ∀ value ∈ ordinaryValues machine, Ordinary value

def Pending (machine : State) : Prop := ∀ value ∈ queuedValues machine, Queued machine.heap value

def Valid (machine : State) : Prop := Normal machine ∧ Pending machine

/-- Appending objects and replacing an existing live object cannot resurrect
an old in-range tombstone. -/
def RetainsRetired (before after : Heap) : Prop :=
  before.objects.length ≤ after.objects.length ∧
  ∀ node, node.value < before.objects.length → before.lookup node = none → after.lookup node = none

theorem retired_mono (before after : Heap) (owner : Custody.Owner)
    (retained : RetainsRetired before after) (retired : Retired before owner) : Retired after owner := by
  obtain ⟨node, index, ownerAt, bounded, missing⟩ := retired
  exact ⟨node, index, ownerAt, Nat.lt_of_lt_of_le bounded retained.1, retained.2 node bounded missing⟩

theorem queued_mono (before after : Heap) (value : Located)
    (retained : RetainsRetired before after) (queued : Queued before value) : Queued after value :=
  queued.elim Or.inl (fun retired => Or.inr (retired_mono before after value.owner retained retired))

theorem scoped_rename (mapping : Renaming) (owner : Custody.Owner) (inScope : Scoped owner) :
    Scoped (renameOwner mapping owner) := by
  cases owner <;> exact inScope

theorem ordinary_rename (mapping : Renaming) (value : Located) (ordinary : Ordinary value) :
    Ordinary (renameLocated mapping value) := by
  rcases ordinary with inScope | free
  · exact Or.inl (scoped_rename mapping value.owner inScope)
  · exact Or.inr (by simpa only [renameLocated, renaming_preserves_owned_tokens] using free)

theorem liveOwnedValue_owner (heap : Heap) (owner : Custody.Owner) (original : SemanticValue)
    (child : Located) (member : child ∈ liveOwnedValue heap owner original) : child.owner = owner := by
  cases original with
  | scalar _ _ | blob _ _ => simp [liveOwnedValue] at member
  | reference schema node token =>
    cases token <;> simp only [liveOwnedValue] at member
    · contradiction
    · split at member
      · cases List.mem_singleton.mp member; rfl
      · contradiction
  | product schema fields | sequence schema fields =>
    simp only [liveOwnedValue] at member
    obtain ⟨value, valueAt, member⟩ := List.mem_flatMap.mp member
    exact liveOwnedValue_owner heap owner value child member
  | variant schema tag value =>
    simp only [liveOwnedValue] at member
    exact liveOwnedValue_owner heap owner value child member
termination_by sizeOf original
decreasing_by
  all_goals subst original
  all_goals simp_wf
  all_goals first | omega | exact Nat.lt_trans (List.sizeOf_lt_of_mem valueAt) (by omega)

theorem liveOwnedValue_free (heap : Heap) (owner : Custody.Owner) (original : SemanticValue)
    (free : ownedTokens original = []) : liveOwnedValue heap owner original = [] := by
  have bounds : ValueTokensBounded 0 original := by simp [ValueTokensBounded, free]
  cases found : liveOwnedValue heap owner original with
  | nil => rfl
  | cons child tail =>
    have member : child ∈ liveOwnedValue heap owner original := by simp [found]
    have bounded := TokenInventory.liveOwnedValue_preserves heap owner original bounds child member
    obtain ⟨schema, node, token, shape⟩ := DisposalProgress.liveOwnedValue_leaf heap owner original child member
    have impossible := bounded token (by simp [shape, ownedTokens])
    omega

theorem ordinary_liveOwned (heap : Heap) (value : Located) (ordinary : Ordinary value) :
    ∀ child ∈ liveOwned heap value, Ordinary child := by
  intro child member
  rcases ordinary with inScope | free
  · exact Or.inl ((liveOwnedValue_owner heap value.owner value.value child member).symm ▸ inScope)
  · simp only [liveOwned, liveOwnedValue_free heap value.owner value.value free, List.not_mem_nil] at member

theorem queued_liveOwned (heap : Heap) (value : Located) (queued : Queued heap value) :
    ∀ child ∈ liveOwned heap value, Queued heap child := by
  intro child member
  rcases queued with ordinary | retired
  · exact Or.inl (ordinary_liveOwned heap value ordinary child member)
  · exact Or.inr ((liveOwnedValue_owner heap value.owner value.value child member).symm ▸ retired)


theorem RetainsRetired.refl (heap : Heap) : RetainsRetired heap heap := ⟨Nat.le_refl _, fun _ _ found => found⟩

theorem RetainsRetired.trans (first : RetainsRetired before middle) (second : RetainsRetired middle after) :
    RetainsRetired before after :=
  ⟨Nat.le_trans first.1 second.1, fun node bounded missing =>
    second.2 node (Nat.lt_of_lt_of_le bounded first.1) (first.2 node bounded missing)⟩

theorem RetainsRetired.of_objects (before after : Heap) (same : after.objects = before.objects) :
    RetainsRetired before after := by simp [RetainsRetired, Heap.lookup, same]

theorem RetainsRetired.append (heap : Heap) (added : List (Option Object)) :
    RetainsRetired heap {heap with objects := heap.objects ++ added} := by
  refine ⟨by simp, ?_⟩
  intro node bounded missing
  simpa only [Heap.lookup, List.getElem?_append_left bounded] using missing

theorem RetainsRetired.set_live (heap : Heap) (node : NodeId) (old : Object) (replacement : Option Object)
    (found : heap.lookup node = some old) :
    RetainsRetired heap {heap with objects := heap.objects.set node.value replacement} := by
  refine ⟨by simp, ?_⟩
  intro other _ missing
  by_cases same : node.value = other.value
  · have equal : node = other := by cases node; cases other; simpa using same
    subst other
    simp [found] at missing
  · simpa only [Heap.lookup, List.getElem?_set_ne same] using missing

theorem allocation_retains (heap after : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (result : Located)
    (accepted : allocateObject heap schema stored owner exclusive = some (after, result)) : RetainsRetired heap after := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, _⟩ := accepted
    exact RetainsRetired.append heap [some stored]
  · obtain ⟨_, _, rfl, _⟩ := accepted
    exact RetainsRetired.append heap [some stored]

theorem replace_retains (heap after : Heap) (node : NodeId) (old stored : Object)
    (found : heap.lookup node = some old) (accepted : replaceObject heap node stored = some after) :
    RetainsRetired heap after := by
  unfold replaceObject at accepted
  split at accepted <;> try contradiction
  cases accepted
  exact RetainsRetired.set_live heap node old (some stored) found

theorem retire_retains (heap after : Heap) (value : Located)
    (accepted : retireObject heap value = some after) : RetainsRetired heap after := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  rename_i schema node token reference
  simp only [bind, Option.bind_eq_some_iff, pure, Option.some.injEq] at accepted
  obtain ⟨stored, found, middle, consumed, rfl⟩ := accepted
  have same := ObjectOwners.consume_objects _ _ _ consumed
  have prior := RetainsRetired.of_objects heap middle same
  apply prior.trans
  apply RetainsRetired.set_live middle node stored none
  simpa only [Heap.lookup, same] using found

theorem normal_control (machine : State) (valid : Normal machine) :
    ∀ value ∈ controlValues machine.control, Ordinary value := by
  intro value member
  apply valid
  simp only [ordinaryValues, List.mem_append]
  exact Or.inl (Or.inl (Or.inl member))

theorem normal_stack (machine : State) (valid : Normal machine) :
    ∀ value ∈ machine.stack.flatMap frameValues, Ordinary value := by
  intro value member
  apply valid
  simp only [ordinaryValues, List.mem_append]
  exact Or.inl (Or.inl (Or.inr member))

theorem normal_heap (machine : State) (valid : Normal machine) :
    ∀ value ∈ heapValues machine.heap, Ordinary value := by
  intro value member
  apply valid
  simp only [ordinaryValues, List.mem_append]
  exact Or.inl (Or.inr member)

theorem normal_status (machine : State) (valid : Normal machine) :
    ∀ value ∈ statusValues machine.status, Ordinary value := by
  intro value member
  apply valid
  simp only [ordinaryValues, List.mem_append]
  exact Or.inr member

theorem pending_control (machine : State) (valid : Pending machine) :
    ∀ value ∈ DisposalShape.control machine.control, Queued machine.heap value := by
  intro value member
  exact valid value (List.mem_append_left _ (List.mem_append_left _ member))

theorem pending_stack (machine : State) (valid : Pending machine) :
    ∀ value ∈ machine.stack.flatMap DisposalShape.frame, Queued machine.heap value := by
  intro value member
  exact valid value (List.mem_append_left _ (List.mem_append_right _ member))

theorem pending_heap (machine : State) (valid : Pending machine) :
    ∀ value ∈ machine.heap.objects.flatMap (fun entry => entry.toList.flatMap DisposalShape.object), Queued machine.heap value := by
  intro value member
  exact valid value (List.mem_append_right _ member)

theorem with_control (machine : State) (next : Control) (valid : Valid machine)
    (ordinary : ∀ value ∈ controlValues next, Ordinary value)
    (queued : ∀ value ∈ DisposalShape.control next, Queued machine.heap value) : Valid {machine with control := next} := by
  constructor
  · have stack := normal_stack machine valid.1
    have heap := normal_heap machine valid.1
    have status := normal_status machine valid.1
    simp only [Normal, ordinaryValues, List.mem_append]
    grind only []
  · have stack := pending_stack machine valid.2
    have heap := pending_heap machine valid.2
    simp only [Pending, queuedValues, List.mem_append]
    grind only []

theorem with_stack (machine : State) (next : List Frame) (valid : Valid machine)
    (ordinary : ∀ value ∈ next.flatMap frameValues, Ordinary value)
    (queued : ∀ value ∈ next.flatMap DisposalShape.frame, Queued machine.heap value) : Valid {machine with stack := next} := by
  constructor
  · have control := normal_control machine valid.1
    have heap := normal_heap machine valid.1
    have status := normal_status machine valid.1
    simp only [Normal, ordinaryValues, List.mem_append]
    grind only []
  · have control := pending_control machine valid.2
    have heap := pending_heap machine valid.2
    simp only [Pending, queuedValues, List.mem_append]
    grind only []

theorem with_status (machine : State) (next : Status) (valid : Valid machine)
    (ordinary : ∀ value ∈ statusValues next, Ordinary value) : Valid {machine with status := next} := by
  refine ⟨?_, valid.2⟩
  have control := normal_control machine valid.1
  have stack := normal_stack machine valid.1
  have heap := normal_heap machine valid.1
  simp only [Normal, ordinaryValues, List.mem_append]
  grind only []

theorem with_heap (machine : State) (next : Heap) (valid : Valid machine)
    (retained : RetainsRetired machine.heap next)
    (ordinary : ∀ value ∈ heapValues next, Ordinary value)
    (queued : ∀ value ∈ next.objects.flatMap (fun entry => entry.toList.flatMap DisposalShape.object), Queued next value) :
    Valid {machine with heap := next} := by
  constructor
  · have control := normal_control machine valid.1
    have stack := normal_stack machine valid.1
    have status := normal_status machine valid.1
    simp only [Normal, ordinaryValues, List.mem_append]
    grind only []
  · have control := pending_control machine valid.2
    have stack := pending_stack machine valid.2
    intro value member
    simp only [queuedValues, List.mem_append] at member
    rcases member with (current | saved) | stored
    · exact queued_mono machine.heap next value retained (control value current)
    · exact queued_mono machine.heap next value retained (stack value saved)
    · exact queued value stored


def ObjectValid (heap : Heap) (stored : Object) : Prop :=
  (∀ value ∈ objectValues stored, Ordinary value) ∧
  (∀ value ∈ DisposalShape.object stored, Queued heap value)

def HeapValid (heap : Heap) : Prop :=
  (∀ entry ∈ heap.objects, ∀ stored ∈ entry, ObjectValid heap stored) ∧
  (∀ scope ∈ heap.scopes, ∀ value ∈ scope.holdings, Ordinary value)

theorem ObjectValid.mono (before after : Heap) (stored : Object)
    (retained : RetainsRetired before after) (valid : ObjectValid before stored) : ObjectValid after stored :=
  ⟨valid.1, fun value member => queued_mono before after value retained (valid.2 value member)⟩

theorem heap_valid (machine : State) (valid : Valid machine) : HeapValid machine.heap := by
  have normal := normal_heap machine valid.1
  have pending := pending_heap machine valid.2
  constructor
  · intro entry entryAt stored storedAt
    have storedList : stored ∈ entry.toList := by simpa using storedAt
    constructor
    · intro value member
      apply normal
      apply List.mem_append_left
      exact List.mem_flatMap.mpr ⟨entry, entryAt, List.mem_flatMap.mpr ⟨stored, storedList, member⟩⟩
    · intro value member
      exact pending value (List.mem_flatMap.mpr ⟨entry, entryAt, List.mem_flatMap.mpr ⟨stored, storedList, member⟩⟩)
  · intro scope scopeAt value member
    exact normal value (List.mem_append_right _ (List.mem_flatMap.mpr ⟨scope, scopeAt, member⟩))

theorem with_heap_valid (machine : State) (next : Heap) (valid : Valid machine)
    (retained : RetainsRetired machine.heap next) (heapValid : HeapValid next) : Valid {machine with heap := next} := by
  apply with_heap machine next valid retained
  · intro value member
    simp only [heapValues, List.mem_append, List.mem_flatMap] at member
    rcases member with ⟨entry, entryAt, stored, storedAt, member⟩ | ⟨scope, scopeAt, member⟩
    · exact (heapValid.1 entry entryAt stored (by simpa using storedAt)).1 value member
    · exact heapValid.2 scope scopeAt value member
  · intro value member
    simp only [List.mem_flatMap] at member
    obtain ⟨entry, entryAt, stored, storedAt, member⟩ := member
    exact (heapValid.1 entry entryAt stored (by simpa using storedAt)).2 value member

theorem same_storage (machine : State) (next : Heap) (valid : Valid machine)
    (objects : next.objects = machine.heap.objects) (scopes : next.scopes = machine.heap.scopes) :
    Valid {machine with heap := next} := by
  apply with_heap_valid machine next valid (RetainsRetired.of_objects _ _ objects)
  have before := heap_valid machine valid
  constructor
  · intro entry entryAt stored storedAt
    apply ObjectValid.mono machine.heap next stored (RetainsRetired.of_objects _ _ objects)
    exact before.1 entry (objects ▸ entryAt) stored storedAt
  · simpa only [scopes] using before.2

theorem lookup_valid (machine : State) (node : NodeId) (stored : Object) (valid : Valid machine)
    (found : machine.heap.lookup node = some stored) : ObjectValid machine.heap stored := by
  simp only [Heap.lookup, Option.bind_eq_some_iff] at found
  obtain ⟨entry, entryAt, storedAt⟩ := found
  cases entry with
  | none => contradiction
  | some original =>
    cases storedAt
    exact (heap_valid machine valid).1 _ (List.mem_of_getElem? entryAt) stored rfl

theorem allocation_valid (machine : State) (after : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (result : Located)
    (accepted : allocateObject machine.heap schema stored owner exclusive = some (after, result))
    (valid : Valid machine) (newObject : ObjectValid after stored) : Valid {machine with heap := after} := by
  have retained := allocation_retains _ _ _ _ _ _ _ accepted
  have before := heap_valid machine valid
  apply with_heap_valid machine after valid retained
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  all_goals first | obtain ⟨rfl, _⟩ := accepted | obtain ⟨_, _, rfl, _⟩ := accepted
  all_goals
    refine ⟨?_, before.2⟩
    intro entry entryAt object objectAt
    rcases List.mem_append.mp entryAt with old | added
    · exact ObjectValid.mono _ _ _ retained (before.1 entry old object objectAt)
    · cases List.mem_singleton.mp added
      cases objectAt
      exact newObject

theorem replace_valid (machine : State) (after : Heap) (node : NodeId) (old stored : Object)
    (found : machine.heap.lookup node = some old) (accepted : replaceObject machine.heap node stored = some after)
    (valid : Valid machine) (newObject : ObjectValid after stored) : Valid {machine with heap := after} := by
  have retained := replace_retains _ _ _ _ _ found accepted
  have before := heap_valid machine valid
  unfold replaceObject at accepted
  split at accepted <;> try contradiction
  cases accepted
  apply with_heap_valid machine _ valid retained
  refine ⟨?_, before.2⟩
  intro entry entryAt object objectAt
  rcases List.mem_or_eq_of_mem_set entryAt with old | rfl
  · exact ObjectValid.mono _ _ _ retained (before.1 entry old object objectAt)
  · cases objectAt
    exact newObject

theorem retire_valid (machine : State) (after : Heap) (value : Located)
    (accepted : retireObject machine.heap value = some after) (valid : Valid machine) : Valid {machine with heap := after} := by
  have retained := retire_retains _ _ _ accepted
  have before := heap_valid machine valid
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, Option.bind_eq_some_iff, consumeValue, pure, Option.some.injEq] at accepted
  obtain ⟨_, _, _, ⟨_, _, rfl⟩, rfl⟩ := accepted
  apply with_heap_valid machine _ valid retained
  refine ⟨?_, before.2⟩
  intro entry entryAt object objectAt
  rcases List.mem_or_eq_of_mem_set entryAt with old | rfl
  · exact ObjectValid.mono _ _ _ retained (before.1 entry old object objectAt)
  · cases objectAt

theorem move_valid (machine : State) (after : Heap) (values : List Located) (receiver : Nat → Custody.Owner)
    (accepted : moveValues machine.heap values receiver = some after) (valid : Valid machine) : Valid {machine with heap := after} :=
  same_storage machine after valid (ObjectOwners.move_objects _ _ _ _ accepted) (HoldingOwners.move_scopes _ _ _ _ accepted)

theorem consume_valid (machine : State) (after : Heap) (value : Located)
    (accepted : consumeValue machine.heap value = some after) (valid : Valid machine) : Valid {machine with heap := after} :=
  same_storage machine after valid (ObjectOwners.consume_objects _ _ _ accepted) (HoldingOwners.consume_scopes _ _ _ accepted)


theorem set_scope (machine : State) (index : Nat) (replacement : Scope) (valid : Valid machine)
    (ordinary : ∀ value ∈ replacement.holdings, Ordinary value) :
    Valid {machine with heap := {machine.heap with scopes := machine.heap.scopes.set index replacement}} := by
  have heap := heap_valid machine valid
  apply with_heap_valid machine {machine.heap with scopes := machine.heap.scopes.set index replacement} valid
    (RetainsRetired.of_objects machine.heap {machine.heap with scopes := machine.heap.scopes.set index replacement} rfl)
  refine ⟨heap.1, ?_⟩
  intro scope scopeAt value member
  rcases List.mem_or_eq_of_mem_set scopeAt with old | rfl
  · exact heap.2 scope old value member
  · exact ordinary value member

theorem append_scope (machine : State) (replacement : Scope) (valid : Valid machine)
    (ordinary : ∀ value ∈ replacement.holdings, Ordinary value) :
    Valid {machine with heap := {machine.heap with scopes := machine.heap.scopes ++ [replacement]}} := by
  have heap := heap_valid machine valid
  apply with_heap_valid machine {machine.heap with scopes := machine.heap.scopes ++ [replacement]} valid
    (RetainsRetired.of_objects machine.heap {machine.heap with scopes := machine.heap.scopes ++ [replacement]} rfl)
  refine ⟨heap.1, ?_⟩
  intro scope scopeAt value member
  rcases List.mem_append.mp scopeAt with old | added
  · exact heap.2 scope old value member
  · cases List.mem_singleton.mp added
    exact ordinary value member

theorem temporary_valid (machine after : State) (owner : Custody.Owner)
    (accepted : temporary machine = .ok (after, owner)) (valid : Valid machine) : Valid after ∧ Scoped owner := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  rename_i record found
  split at accepted <;> try contradiction
  cases accepted
  refine ⟨set_scope machine _ _ valid ?_, trivial⟩
  exact (heap_valid machine valid).2 record (List.mem_of_getElem? found)

theorem finishTemporary_valid (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) (valid : Valid machine) (ordinary : Ordinary value) : Valid after.state := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  rename_i scope found
  cases accepted
  have original := (heap_valid machine valid).2 scope (List.mem_of_getElem? found)
  have next := set_scope machine machine.scope.value {scope with holdings := scope.holdings ++ [value]} valid (by
    intro child member
    rcases List.mem_append.mp member with old | added
    · exact original child old
    · cases List.mem_singleton.mp added
      exact ordinary)
  exact with_control _ (.delivered value) next (by simpa [controlValues] using ordinary) (by simp [DisposalShape.control])

end OwnerLocations
end BoundaryV2.Profile.Source.Machine
