import BoundaryV2.SourceLexicalControl

namespace BoundaryV2.Profile.Source.Machine
namespace LexicalCoverage
namespace SavedFrames

def StackValid (context : Context) (frames : List Frame) : Prop := ∀ frame ∈ frames, FrameValid context frame

def ObjectValid (context : Context) : Object → Prop
  | .oneShot saved | .multiTemplate saved => StackValid context saved.frames
  | _ => True

def HeapValid (context : Context) (store : Heap) : Prop := ∀ entry ∈ store.objects, ∀ stored ∈ entry, ObjectValid context stored

def Plain (context : Context) (machine : State) : Prop := StackValid context machine.stack ∧ HeapValid context machine.heap

theorem StackValid.subset (typed : StackValid context frames) (contained : smaller ⊆ frames) : StackValid context smaller :=
  fun saved member => typed saved (contained member)

theorem StackValid.append (leftTyped : StackValid context left) (rightTyped : StackValid context right) : StackValid context (left ++ right) := by
  intro saved member
  exact (List.mem_append.mp member).elim (leftTyped saved) (rightTyped saved)

theorem stack_cons (context : Context) (saved : Frame) (tail : List Frame) :
    StackValid context (saved :: tail) ↔ FrameValid context saved ∧ StackValid context tail := by
  simp [StackValid, List.mem_cons, forall_eq_or_imp]

theorem stack_rename (context : Context) (frames : List Frame) (mapping : Renaming) (typed : StackValid context frames) :
    StackValid context (frames.map (renameFrame mapping)) := by
  intro saved member
  obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
  exact frame_rename context original mapping (typed original originalMember)

theorem stack_trim (context : Context) (frames : List Frame) (typed : StackValid context frames) :
    StackValid context (frames.map (trimFrame context)) := by
  intro saved member
  obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
  exact frame_trim context original (typed original originalMember)

theorem ObjectValid.rename {context : Context} (stored : Object) (mapping : Renaming) (typed : ObjectValid context stored) :
    ObjectValid context (renameObject mapping stored) := by
  cases stored <;> first | trivial | exact stack_rename context _ _ typed

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem heap_lookup (context : Context) (store : Heap) (node : NodeId) (stored : Object)
    (found : store.lookup node = some stored) (typed : HeapValid context store) : ObjectValid context stored := by
  simp only [Heap.lookup, Option.bind_eq_some_iff] at found
  obtain ⟨entry, atNode, present⟩ := found
  cases entry <;> simp [id] at present
  cases present
  exact typed _ (List.mem_of_getElem? atNode) _ rfl

theorem lookupObject_valid (context : Context) (machine : State) (value : Located) (node : NodeId) (stored : Object)
    (accepted : lookupObject machine value = .ok (node, stored)) (typed : HeapValid context machine.heap) : ObjectValid context stored := by
  simp only [lookupObject, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, found, equal⟩ := accepted
  cases equal
  exact heap_lookup context _ _ _ found typed

theorem allocateObject_valid (context : Context) (before after : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject before schema stored owner exclusive = some (after, value))
    (typed : HeapValid context before) (storedTyped : ObjectValid context stored) : HeapValid context after := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, _⟩ := accepted
    simp only [HeapValid, List.mem_append, List.mem_singleton] at typed ⊢
    grind only [Option.mem_def]
  · obtain ⟨_, _, rfl, _⟩ := accepted
    simp only [HeapValid, List.mem_append, List.mem_singleton] at typed ⊢
    grind only [Option.mem_def]

theorem replaceObject_valid (context : Context) (before after : Heap) (node : NodeId) (stored : Object)
    (accepted : replaceObject before node stored = some after)
    (typed : HeapValid context before) (storedTyped : ObjectValid context stored) : HeapValid context after := by
  unfold replaceObject at accepted
  split at accepted <;> try contradiction
  cases accepted
  simp only [HeapValid] at typed ⊢
  grind only [→ List.mem_or_eq_of_mem_set, Option.mem_def]

theorem retireObject_valid (context : Context) (before after : Heap) (value : Located)
    (accepted : retireObject before value = some after) (typed : HeapValid context before) : HeapValid context after := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, Option.bind_eq_some_iff, consumeValue, pure, Option.some.injEq] at accepted
  obtain ⟨_, _, _, ⟨_, _, rfl⟩, rfl⟩ := accepted
  simp only [HeapValid] at typed ⊢
  grind only [→ List.mem_or_eq_of_mem_set, Option.mem_def]

theorem moveValues_valid (context : Context) (before after : Heap) (values : List Located) (receiver : Nat → Custody.Owner)
    (accepted : moveValues before values receiver = some after) (typed : HeapValid context before) : HeapValid context after := by
  simp [moveValues, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  exact typed

theorem makeClosureWithValues_shape (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues machine context schema function values = .ok after)
    (typed : HeapValid context machine.heap) :
    (∃ result, after.state.control = .delivered result) ∧ after.state.stack = machine.stack ∧ HeapValid context after.state.heap := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, ⟨middle, owner⟩, temporaryOk, moved, movedOk, ⟨store, result⟩, allocated, finished⟩ := accepted
  have middleShape := OperandStructure.temporary_shape _ _ _ temporaryOk
  have middleTyped : HeapValid context middle.heap := by simpa only [HeapValid, middleShape.2.2] using typed
  have movedTyped := moveValues_valid context _ _ _ _ movedOk middleTyped
  have allocatedTyped := allocateObject_valid context _ _ _ _ _ _ _ allocated movedTyped trivial
  have finalShape := OperandStructure.finishTemporary_shape _ _ _ finished
  refine ⟨⟨_, finalShape.1⟩, finalShape.2.1.trans middleShape.2.1, ?_⟩
  simpa only [HeapValid, finalShape.2.2] using allocatedTyped

theorem makeClosure_shape (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (bindings : Environment) (after : Transition)
    (accepted : makeClosure machine context schema function bindings = .ok after)
    (typed : HeapValid context machine.heap) :
    (∃ result, after.state.control = .delivered result) ∧ after.state.stack = machine.stack ∧ HeapValid context after.state.heap := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  exact makeClosureWithValues_shape _ _ _ _ _ _ accepted typed

theorem HeapValid.of_objects {context : Context} (typed : HeapValid context before) (same : after.objects = before.objects) : HeapValid context after := by
  simpa only [HeapValid, same] using typed

theorem finishTemporary_valid (context : Context) (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) (typed : HeapValid context machine.heap) :
    (∃ result, after.state.control = .delivered result) ∧ after.state.stack = machine.stack ∧ HeapValid context after.state.heap := by
  have shape := OperandStructure.finishTemporary_shape _ _ _ accepted
  exact ⟨⟨_, shape.1⟩, shape.2.1, typed.of_objects shape.2.2⟩

theorem scopedValue_valid (context : Context) (machine : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue machine value = .ok after) (typed : HeapValid context machine.heap) :
    (∃ result, after.state.control = .delivered result) ∧ after.state.stack = machine.stack ∧ HeapValid context after.state.heap := by
  have shape := OperandStructure.scopedValue_shape _ _ _ accepted
  exact ⟨shape.1, shape.2.1, typed.of_objects shape.2.2⟩

theorem commitPure_valid (context : Context) (machine : State) (opcode : Opcode) (operands : List Located)
    (value : SemanticValue) (after : Transition) (accepted : commitPure machine opcode operands value = .ok after)
    (typed : HeapValid context machine.heap) :
    (∃ result, after.state.control = .delivered result) ∧ after.state.stack = machine.stack ∧ HeapValid context after.state.heap := by
  have shape := OperandStructure.commitPure_shape _ _ _ _ _ accepted
  exact ⟨shape.1, shape.2.1, typed.of_objects shape.2.2⟩

theorem heapPrimitive_shape (machine : State) (context : Context)
    (operation : Primitives.GraphOperation) (schema : SchemaId .source) (immediate : Nat)
    (operands : List Located) (after : Transition)
    (accepted : heapPrimitive machine context operation schema immediate operands = .ok after)
    (typed : HeapValid context machine.heap) :
    (∃ result, after.state.control = .delivered result) ∧ after.state.stack = machine.stack ∧ HeapValid context after.state.heap := by
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
    have movedTyped := moveValues_valid context _ _ _ _ moveOk (typed.of_objects middleShape.2.2)
    have allocatedTyped := allocateObject_valid context { moved with nextCell := moved.nextCell + 1 } _ _ _ _ _ _ allocated movedTyped trivial
    have finalShape := finishTemporary_valid context _ _ _ finished allocatedTyped
    exact ⟨finalShape.1, finalShape.2.1.trans middleShape.2.1, finalShape.2.2⟩
  case cellGet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact scopedValue_valid context _ _ _ accepted typed
  case cellSet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, store, replaced, accepted⟩ := accepted
    have storeTyped := replaceObject_valid context _ _ _ _ replaced typed trivial
    have finalShape := scopedValue_valid context _ _ _ accepted storeTyped
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
    have movedTyped := moveValues_valid context _ _ _ _ moveOk (typed.of_objects middleShape.2.2)
    have allocatedTyped := allocateObject_valid context _ _ _ _ _ _ _ allocated movedTyped trivial
    have finalShape := finishTemporary_valid context _ _ _ finished allocatedTyped
    exact ⟨finalShape.1, finalShape.2.1.trans middleShape.2.1, finalShape.2.2⟩
  case unpack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, store, retired, accepted⟩ := accepted
    have storeTyped := retireObject_valid context _ _ _ retired typed
    have finalShape := commitPure_valid context _ _ _ _ _ accepted storeTyped
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
    have captureTyped := lookupObject_valid context _ _ _ _ looked typed
    have retiredTyped := retireObject_valid context _ _ _ retireOk typed
    have middleShape := OperandStructure.temporary_shape _ _ _ temporaryOk
    have allocatedTyped := allocateObject_valid context _ _ _ _ _ _ _ allocated (retiredTyped.of_objects middleShape.2.2) captureTyped
    have finalShape := finishTemporary_valid context _ _ _ finished allocatedTyped
    exact ⟨finalShape.1, finalShape.2.1.trans middleShape.2.1, finalShape.2.2⟩
  case resourcePack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, ⟨middle, owner⟩, temporaryOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have middleShape := OperandStructure.temporary_shape _ _ _ temporaryOk
    have allocatedTyped := allocateObject_valid context _ _ _ _ _ _ _ allocated (typed.of_objects middleShape.2.2) trivial
    have finalShape := finishTemporary_valid context _ _ _ finished allocatedTyped
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
      have storeTyped := retireObject_valid context _ _ _ retired typed
      have finalShape := scopedValue_valid context _ _ _ accepted storeTyped
      exact finalShape
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      exact scopedValue_valid context _ _ _ accepted typed
    · contradiction

theorem plain_of_shape (context : Context) (before : State) (after : State) (typed : Plain context before)
    (stacked : after.stack = before.stack) (stored : HeapValid context after.heap) : Plain context after :=
  ⟨by simpa only [stacked] using typed.1, stored⟩

theorem scopedValue_plain (context : Context) (machine : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue machine value = .ok after) (typed : Plain context machine) : Plain context after.state := by
  have shape := scopedValue_valid context _ _ _ accepted typed.2
  exact plain_of_shape context _ _ typed shape.2.1 shape.2.2

theorem finishTemporary_plain (context : Context) (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) (typed : Plain context machine) : Plain context after.state := by
  have shape := finishTemporary_valid context _ _ _ accepted typed.2
  exact plain_of_shape context _ _ typed shape.2.1 shape.2.2

theorem temporary_plain (context : Context) (machine after : State) (owner : Custody.Owner)
    (accepted : temporary machine = .ok (after, owner)) (typed : Plain context machine) : Plain context after := by
  have shape := OperandStructure.temporary_shape _ _ _ accepted
  exact plain_of_shape context _ _ typed shape.2.1 (typed.2.of_objects shape.2.2)

theorem invokeFunction_plain (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction machine context function bindings arguments = .ok after)
    (typed : Plain context machine) : Plain context after.state := by
  simp only [invokeFunction, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, ⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have shape := OperandStructure.createScope_shape _ _ _ _ _ _ _ _ _ scopeOk
  refine ⟨?_, typed.2.of_objects shape.2.2⟩
  exact (stack_cons context _ _).mpr ⟨(by trivial), typed.1⟩

theorem applyClosure_plain (machine : State) (context : Context) (closure : Located)
    (arguments : List Located) (after : Transition)
    (accepted : applyClosure machine context closure arguments = .ok after) (typed : Plain context machine) : Plain context after.state := by
  simp only [applyClosure, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  · simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨store, retired, accepted⟩ := accepted
    have startTyped : Plain context { machine with heap := store } := ⟨typed.1, retireObject_valid context _ _ _ retired typed.2⟩
    exact invokeFunction_plain _ _ _ _ _ _ accepted startTyped
  · simp only [pure, Except.pure, Except.bind] at accepted
    exact invokeFunction_plain _ _ _ _ _ _ accepted typed

private theorem mapM_preserves (function : α → Except Invalid β) (property : β → Prop)
    (preserves : ∀ input output, function input = .ok output → property output)
    (inputs : List α) (outputs : List β) (accepted : inputs.mapM function = .ok outputs) :
    ∀ output ∈ outputs, property output := by
  induction inputs generalizing outputs with
  | nil => cases accepted; simp
  | cons head tail induction =>
    simp only [List.mapM_cons, bind, except_bind_ok] at accepted
    obtain ⟨first, firstAt, rest, restAt, accepted⟩ := accepted
    cases accepted
    exact fun value member => (List.mem_cons.mp member).elim
      (fun equal => equal ▸ preserves head first firstAt) (induction rest restAt value)

theorem instantiateCapture_shape (machine : State) (context : Context) (saved : Capture)
    (after : State × Capture) (accepted : instantiateCapture machine context saved = .ok after)
    (typed : HeapValid context machine.heap) (captureTyped : StackValid context saved.frames) :
    after.1.stack = machine.stack ∧ HeapValid context after.1.heap ∧ StackValid context after.2.frames := by
  unfold instantiateCapture at accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨objects, objectsAt, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  cases accepted
  have objectsTyped : ∀ entry ∈ objects, ∀ stored ∈ entry, ObjectValid context stored := by
    refine mapM_preserves _ (fun entry : Option Object => ∀ stored ∈ entry, ObjectValid context stored) ?_ _ _ objectsAt
    intro input output checked
    simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at checked
    obtain ⟨stored, looked, rfl⟩ := checked
    intro renamed present
    cases present
    apply ObjectValid.rename
    have storedTyped := heap_lookup context _ _ _ looked typed
    cases stored <;> first | exact storedTyped | trivial
  refine ⟨rfl, ?_, stack_rename context _ _ captureTyped⟩
  simp only [HeapValid, List.mem_append] at typed ⊢
  grind only []

theorem takeCapture_shape (machine : State) (context : Context) (token : Located) (after : State × Capture)
    (accepted : takeCapture machine context token = .ok after) (typed : HeapValid context machine.heap) :
    after.1.stack = machine.stack ∧ HeapValid context after.1.heap ∧ StackValid context after.2.frames := by
  simp only [takeCapture, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
  have storedTyped := lookupObject_valid context _ _ _ _ looked typed
  cases stored <;> try contradiction
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨store, retired, rfl⟩ := accepted
    exact ⟨rfl, retireObject_valid context _ _ _ retired typed, storedTyped⟩
  · exact instantiateCapture_shape _ _ _ _ accepted typed storedTyped

theorem activateCapture_plain (machine : State) (context : Context) (saved : Capture)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : State)
    (accepted : activateCapture machine context saved successor = .ok after) (typed : Plain context machine)
    (captureTyped : StackValid context saved.frames) : Plain context after := by
  simp only [activateCapture, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  cases successor with
  | none =>
    simp only [Option.isSome_none, Bool.false_or, pure, Except.pure, Except.bind, Except.ok.injEq] at accepted
    cases accepted
    split
    all_goals refine ⟨?_, typed.2⟩
    all_goals simp only [Plain, StackValid, List.mem_append, List.mem_cons, List.not_mem_nil, or_false] at typed captureTyped ⊢
    all_goals grind only [FrameValid]
  | some successor =>
    rcases successor with ⟨handler, stored, bindings⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, _, rfl, rfl⟩ := accepted
    refine ⟨?_, typed.2⟩
    simp only [Option.isSome_some, Bool.true_or, if_true, Plain, StackValid, List.mem_append,
      List.mem_cons, List.not_mem_nil, or_false] at typed captureTyped ⊢
    grind only [FrameValid]

theorem resumeValue_plain (machine : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (accepted : resumeValue machine context token argument successor = .ok after) (typed : Plain context machine) : Plain context after.state := by
  simp only [resumeValue, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, _, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, active, activated, ⟨middle, owner⟩, temporaryOk, store, moved, finished⟩ := accepted
  have capturedShape := takeCapture_shape _ _ _ _ captured typed.2
  have takenTyped := plain_of_shape context _ _ typed capturedShape.1 capturedShape.2.1
  have activeTyped := activateCapture_plain _ _ _ _ _ activated takenTyped capturedShape.2.2
  have middleTyped := temporary_plain context _ _ _ temporaryOk activeTyped
  have movedTyped : Plain context { middle with heap := store } := ⟨middleTyped.1, moveValues_valid context _ _ _ _ moved middleTyped.2⟩
  exact finishTemporary_plain context _ _ _ finished movedTyped

theorem resumeComputation_plain (machine : State) (context : Context) (token computation : Located) (after : Transition)
    (accepted : resumeComputation machine context token computation = .ok after) (typed : Plain context machine) : Plain context after.state := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, active, activated, applied⟩ := accepted
  have capturedShape := takeCapture_shape _ _ _ _ captured typed.2
  have takenTyped := plain_of_shape context _ _ typed capturedShape.1 capturedShape.2.1
  have activeTyped := activateCapture_plain _ _ _ _ _ activated takenTyped capturedShape.2.2
  exact applyClosure_plain _ _ _ _ _ applied activeTyped

end SavedFrames
end LexicalCoverage
end BoundaryV2.Profile.Source.Machine
