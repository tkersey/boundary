import BoundaryV2.SourceDisposalProgress

namespace BoundaryV2.Profile.Source.Machine
namespace DisposalShape
open DisposalProgress

def frame : Frame → List Located
  | .disposalReturn remaining .. => remaining
  | _ => []

def object : Object → List Located
  | .oneShot saved | .multiTemplate saved => saved.frames.flatMap frame
  | _ => []

def control : Control → List Located
  | .discard remaining _ => remaining
  | _ => []

def HeapValid (heap : Heap) : Prop :=
  ∀ stored ∈ heap.objects, ∀ value ∈ stored.toList.flatMap object, Leaf value

def Valid (machine : State) : Prop :=
  (∀ value ∈ control machine.control, Leaf value) ∧
  (∀ value ∈ machine.stack.flatMap frame, Leaf value) ∧ HeapValid machine.heap

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem liveOwned_leaves (heap : Heap) (located : Located) : ∀ value ∈ liveOwned heap located, Leaf value :=
  liveOwnedValue_leaf heap located.owner located.value

theorem rename_leaf (mapping : Renaming) (value : Located) (leaf : Leaf value) : Leaf (renameLocated mapping value) := by
  obtain ⟨schema, node, token, same⟩ := leaf
  exact ⟨schema, renamed mapping.nodes node, token, by simp [renameLocated, same, renameValue]⟩

theorem frame_rename (mapping : Renaming) (saved : Frame) :
    frame (renameFrame mapping saved) = (frame saved).map (renameLocated mapping) := by
  cases saved <;> simp [frame, renameFrame]

theorem object_rename (mapping : Renaming) (stored : Object) :
    object (renameObject mapping stored) = (object stored).map (renameLocated mapping) := by
  cases stored <;> simp [object, renameObject, renameCapture, List.flatMap_map, frame_rename, List.map_flatMap]

theorem heap_lookup (heap : Heap) (node : NodeId) (stored : Object)
    (found : heap.lookup node = some stored) (valid : HeapValid heap) :
    ∀ value ∈ object stored, Leaf value := by
  simp only [Heap.lookup, Option.bind_eq_some_iff] at found
  obtain ⟨entry, entryAt, present⟩ := found
  cases entry <;> simp [id] at present
  cases present
  simpa using valid _ (List.mem_of_getElem? entryAt)

theorem lookupObject_valid (machine : State) (value : Located) (node : NodeId) (stored : Object)
    (accepted : lookupObject machine value = .ok (node, stored)) (valid : HeapValid machine.heap) :
    ∀ value ∈ object stored, Leaf value := by
  simp only [lookupObject, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, found, equal⟩ := accepted
  cases equal
  exact heap_lookup _ _ _ found valid

theorem allocate_valid (before after : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject before schema stored owner exclusive = some (after, value))
    (valid : HeapValid before) (fresh : ∀ value ∈ object stored, Leaf value) : HeapValid after := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, _⟩ := accepted
    simp only [HeapValid, List.mem_append, List.mem_singleton] at valid ⊢
    grind only [Option.toList_some, List.flatMap_singleton]
  · obtain ⟨_, _, rfl, _⟩ := accepted
    simp only [HeapValid, List.mem_append, List.mem_singleton] at valid ⊢
    grind only [Option.toList_some, List.flatMap_singleton]

theorem replace_valid (before after : Heap) (node : NodeId) (stored : Object)
    (accepted : replaceObject before node stored = some after)
    (valid : HeapValid before) (fresh : ∀ value ∈ object stored, Leaf value) : HeapValid after := by
  unfold replaceObject at accepted
  split at accepted <;> try contradiction
  cases accepted
  simp only [HeapValid] at valid ⊢
  grind only [→ List.mem_or_eq_of_mem_set, Option.toList_some, List.flatMap_singleton]

theorem retire_valid (before after : Heap) (value : Located)
    (accepted : retireObject before value = some after) (valid : HeapValid before) : HeapValid after := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, Option.bind_eq_some_iff, consumeValue, pure, Option.some.injEq] at accepted
  obtain ⟨_, _, _, ⟨_, _, rfl⟩, rfl⟩ := accepted
  simp only [HeapValid] at valid ⊢
  grind only [→ List.mem_or_eq_of_mem_set, Option.toList_none, List.flatMap_nil, List.not_mem_nil]

theorem move_valid (before after : Heap) (values : List Located) (receiver : Nat → Custody.Owner)
    (accepted : moveValues before values receiver = some after) (valid : HeapValid before) : HeapValid after := by
  simp [moveValues, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  exact valid

theorem Valid.of_shape (before after : State) (valid : Valid before)
    (controlled : after.control = before.control) (stacked : after.stack = before.stack)
    (objects : after.heap.objects = before.heap.objects) : Valid after := by
  simpa only [Valid, controlled, stacked, HeapValid, objects] using valid

theorem temporary_valid (machine after : State) (owner : Custody.Owner)
    (accepted : temporary machine = .ok (after, owner)) (valid : Valid machine) : Valid after := by
  obtain ⟨controlled, stacked, objects⟩ := OperandStructure.temporary_shape _ _ _ accepted
  exact valid.of_shape _ _ controlled stacked objects

theorem finishTemporary_valid (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) (valid : Valid machine) : Valid after.state := by
  obtain ⟨controlled, stacked, objects⟩ := OperandStructure.finishTemporary_shape _ _ _ accepted
  exact ⟨by simp [controlled, control], by simpa only [stacked] using valid.2.1,
    by simpa only [HeapValid, objects] using valid.2.2⟩

theorem scopedValue_valid (machine : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue machine value = .ok after) (valid : Valid machine) : Valid after.state := by
  obtain ⟨⟨result, controlled⟩, stacked, objects⟩ := OperandStructure.scopedValue_shape _ _ _ accepted
  exact ⟨by simp [controlled, control], by simpa only [stacked] using valid.2.1,
    by simpa only [HeapValid, objects] using valid.2.2⟩

theorem commitPure_valid (machine : State) (opcode : Opcode) (operands : List Located)
    (value : SemanticValue) (after : Transition) (accepted : commitPure machine opcode operands value = .ok after)
    (valid : Valid machine) : Valid after.state := by
  obtain ⟨⟨result, controlled⟩, stacked, objects⟩ := OperandStructure.commitPure_shape _ _ _ _ _ accepted
  exact ⟨by simp [controlled, control], by simpa only [stacked] using valid.2.1,
    by simpa only [HeapValid, objects] using valid.2.2⟩

theorem createScope_valid (machine : State) (context : Context) (invocation : InvocationId)
    (parent : Option LexicalScopeId) (vars : List VariableId) (values : List Located) (bindings : Environment)
    (after : State) (entered : Environment)
    (accepted : createScope machine context invocation parent vars values bindings = .ok (after, entered))
    (valid : Valid machine) : Valid after := by
  obtain ⟨controlled, stacked, objects⟩ := OperandStructure.createScope_shape _ _ _ _ _ _ _ _ _ accepted
  exact valid.of_shape _ _ controlled stacked objects

theorem makeClosureWithValues_shape (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues machine context schema function values = .ok after)
    (typed : HeapValid machine.heap) :
    (∃ result, after.state.control = .delivered result) ∧ after.state.stack = machine.stack ∧ HeapValid after.state.heap := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, ⟨middle, owner⟩, temporaryOk, moved, movedOk, ⟨store, result⟩, allocated, finished⟩ := accepted
  have middleShape := OperandStructure.temporary_shape _ _ _ temporaryOk
  have middleTyped : HeapValid middle.heap := by simpa only [HeapValid, middleShape.2.2] using typed
  have movedTyped := move_valid _ _ _ _ movedOk middleTyped
  have allocatedTyped := allocate_valid _ _ _ _ _ _ _ allocated movedTyped (by simp [object])
  have finalShape := OperandStructure.finishTemporary_shape _ _ _ finished
  refine ⟨⟨_, finalShape.1⟩, finalShape.2.1.trans middleShape.2.1, ?_⟩
  simpa only [HeapValid, finalShape.2.2] using allocatedTyped

theorem makeClosure_shape (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (bindings : Environment) (after : Transition)
    (accepted : makeClosure machine context schema function bindings = .ok after)
    (typed : HeapValid machine.heap) :
    (∃ result, after.state.control = .delivered result) ∧ after.state.stack = machine.stack ∧ HeapValid after.state.heap := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  exact makeClosureWithValues_shape _ _ _ _ _ _ accepted typed

theorem HeapValid.of_objects (typed : HeapValid before) (same : after.objects = before.objects) : HeapValid after := by
  simpa only [HeapValid, same] using typed

theorem finishTemporary_heap (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) (typed : HeapValid machine.heap) :
    (∃ result, after.state.control = .delivered result) ∧ after.state.stack = machine.stack ∧ HeapValid after.state.heap := by
  have shape := OperandStructure.finishTemporary_shape _ _ _ accepted
  exact ⟨⟨_, shape.1⟩, shape.2.1, typed.of_objects shape.2.2⟩

theorem scopedValue_heap (machine : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue machine value = .ok after) (typed : HeapValid machine.heap) :
    (∃ result, after.state.control = .delivered result) ∧ after.state.stack = machine.stack ∧ HeapValid after.state.heap := by
  have shape := OperandStructure.scopedValue_shape _ _ _ accepted
  exact ⟨shape.1, shape.2.1, typed.of_objects shape.2.2⟩

theorem commitPure_heap (machine : State) (opcode : Opcode) (operands : List Located)
    (value : SemanticValue) (after : Transition) (accepted : commitPure machine opcode operands value = .ok after)
    (typed : HeapValid machine.heap) :
    (∃ result, after.state.control = .delivered result) ∧ after.state.stack = machine.stack ∧ HeapValid after.state.heap := by
  have shape := OperandStructure.commitPure_shape _ _ _ _ _ accepted
  exact ⟨shape.1, shape.2.1, typed.of_objects shape.2.2⟩

theorem heapPrimitive_shape (machine : State) (context : Context)
    (operation : Primitives.GraphOperation) (schema : SchemaId .source) (immediate : Nat)
    (operands : List Located) (after : Transition)
    (accepted : heapPrimitive machine context operation schema immediate operands = .ok after)
    (typed : HeapValid machine.heap) :
    (∃ result, after.state.control = .delivered result) ∧ after.state.stack = machine.stack ∧ HeapValid after.state.heap := by
  cases operation <;> simp only [heapPrimitive, bind, except_bind_ok, fromOption_ok] at accepted
  case computation =>
    obtain ⟨_, _, _, _, accepted⟩ := accepted
    exact makeClosureWithValues_shape _ _ _ _ _ _ accepted typed
  case cellNew =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, ⟨middle, owner⟩, temporaryOk, moved, moveOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have middleShape := OperandStructure.temporary_shape _ _ _ temporaryOk
    have movedTyped := move_valid _ _ _ _ moveOk (typed.of_objects middleShape.2.2)
    have allocatedTyped := allocate_valid { moved with nextCell := moved.nextCell + 1 } _ _ _ _ _ _ allocated movedTyped (by simp [object])
    have finalShape := finishTemporary_heap _ _ _ finished allocatedTyped
    exact ⟨finalShape.1, finalShape.2.1.trans middleShape.2.1, finalShape.2.2⟩
  case cellGet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact scopedValue_heap _ _ _ accepted typed
  case cellSet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, store, replaced, accepted⟩ := accepted
    have storeTyped := replace_valid _ _ _ _ replaced typed (by simp [object])
    have finalShape := scopedValue_heap _ _ _ accepted storeTyped
    exact finalShape
  case package =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, ⟨middle, owner⟩, temporaryOk, moved, moveOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have middleShape := OperandStructure.temporary_shape _ _ _ temporaryOk
    have movedTyped := move_valid _ _ _ _ moveOk (typed.of_objects middleShape.2.2)
    have allocatedTyped := allocate_valid _ _ _ _ _ _ _ allocated movedTyped (by simp [object])
    have finalShape := finishTemporary_heap _ _ _ finished allocatedTyped
    exact ⟨finalShape.1, finalShape.2.1.trans middleShape.2.1, finalShape.2.2⟩
  case unpack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, store, retired, accepted⟩ := accepted
    have storeTyped := retire_valid _ _ _ retired typed
    have finalShape := commitPure_heap _ _ _ _ _ accepted storeTyped
    exact finalShape
  case cloneResumption =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
    split at accepted <;> try contradiction
    rename_i storedNode saved matched
    cases matched
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, retired, retireOk, ⟨middle, owner⟩, temporaryOk,
      ⟨store, result⟩, allocated, finished⟩ := accepted
    have captureTyped := lookupObject_valid _ _ _ _ looked typed
    have retiredTyped := retire_valid _ _ _ retireOk typed
    have middleShape := OperandStructure.temporary_shape _ _ _ temporaryOk
    have allocatedTyped := allocate_valid _ _ _ _ _ _ _ allocated (retiredTyped.of_objects middleShape.2.2) captureTyped
    have finalShape := finishTemporary_heap _ _ _ finished allocatedTyped
    exact ⟨finalShape.1, finalShape.2.1.trans middleShape.2.1, finalShape.2.2⟩
  case resourcePack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, ⟨middle, owner⟩, temporaryOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have middleShape := OperandStructure.temporary_shape _ _ _ temporaryOk
    have allocatedTyped := allocate_valid _ _ _ _ _ _ _ allocated (typed.of_objects middleShape.2.2) (by simp [object])
    have finalShape := finishTemporary_heap _ _ _ finished allocatedTyped
    exact ⟨finalShape.1, finalShape.2.1.trans middleShape.2.1, finalShape.2.2⟩
  case resourceUnpack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, accepted⟩ := accepted
    split at accepted
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, store, retired, accepted⟩ := accepted
      have storeTyped := retire_valid _ _ _ retired typed
      have finalShape := scopedValue_heap _ _ _ accepted storeTyped
      exact finalShape
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      exact scopedValue_heap _ _ _ accepted typed
    · contradiction

end DisposalShape
end BoundaryV2.Profile.Source.Machine
