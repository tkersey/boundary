import BoundaryV2.SourceEnvironmentExecution
import BoundaryV2.SourcePrimitiveResults

namespace BoundaryV2.Profile.Source.Machine
namespace OperandStructure

def NoOperands (frames : List Frame) : Prop := ∀ frame ∈ frames, ∀ intent bindings remaining evaluated,
  frame ≠ .operands intent bindings remaining evaluated

inductive Layout : List Frame → Prop where
  | plain : NoOperands frames → Layout frames
  | primitive : Layout tail → Layout (.operands (.primitive schema opcode immediate failures) bindings remaining evaluated :: tail)
  | term : NoOperands tail → Layout (.operands (.term term) bindings remaining evaluated :: tail)

def Fits (control : Control) (frames : List Frame) : Prop := match control with
  | .expression .. | .delivered _ | .execute (.primitive ..) .. | .unwind _ => Layout frames
  | _ => NoOperands frames

def ObjectValid : Object → Prop
  | .oneShot saved | .multiTemplate saved => NoOperands saved.frames
  | _ => True

def HeapValid (store : Heap) : Prop := ∀ entry ∈ store.objects, ∀ stored ∈ entry, ObjectValid stored

def Valid (machine : State) : Prop := Fits machine.control machine.stack ∧ HeapValid machine.heap

def Plain (machine : State) : Prop := NoOperands machine.stack ∧ HeapValid machine.heap

theorem noOperands_nil : NoOperands [] := by simp [NoOperands]

theorem NoOperands.subset (typed : NoOperands frames) (contained : smaller ⊆ frames) : NoOperands smaller :=
  fun saved member => typed saved (contained member)

theorem NoOperands.append (leftTyped : NoOperands left) (rightTyped : NoOperands right) : NoOperands (left ++ right) := by
  intro saved member
  exact (List.mem_append.mp member).elim (leftTyped saved) (rightTyped saved)

theorem noOperands_cons (saved : Frame) (tail : List Frame) :
    NoOperands (saved :: tail) ↔ (∀ intent bindings remaining evaluated, saved ≠ .operands intent bindings remaining evaluated) ∧ NoOperands tail := by
  simp [NoOperands, List.mem_cons, forall_eq_or_imp]

theorem Layout.tail {saved : Frame} {tail : List Frame} (typed : Layout (saved :: tail)) : Layout tail := by
  cases typed with
  | plain holds => exact .plain (noOperands_cons _ _ |>.mp holds).2
  | primitive holds => exact holds
  | term holds => exact .plain holds

theorem Layout.nonoperand {saved : Frame} {tail : List Frame} (typed : Layout (saved :: tail))
    (different : ∀ intent bindings remaining evaluated, saved ≠ .operands intent bindings remaining evaluated) :
    NoOperands (saved :: tail) := by
  cases typed with
  | plain holds => exact holds
  | primitive => exact False.elim (different _ _ _ _ rfl)
  | term => exact False.elim (different _ _ _ _ rfl)

theorem Layout.primitive_tail {schema : SchemaId .source} {opcode : Opcode} {immediate : Nat}
    {failures : List (InstructionFailure .source)} {bindings : Environment} {remaining : List SourceValueId}
    {evaluated : List Located} {tail : List Frame} (typed : Layout (.operands (.primitive schema opcode immediate failures) bindings remaining evaluated :: tail)) :
    Layout tail := typed.tail

theorem Layout.term_tail {term : Source.Term} {bindings : Environment} {remaining : List SourceValueId}
    {evaluated : List Located} {tail : List Frame} (typed : Layout (.operands (.term term) bindings remaining evaluated :: tail)) :
    NoOperands tail := by
  cases typed with
  | plain holds => exact False.elim (holds _ (List.mem_cons_self) _ _ _ _ rfl)
  | term holds => exact holds

theorem Layout.replace_operands {intent : Intent} {bindings : Environment} {remaining : List SourceValueId}
    {evaluated : List Located} {tail : List Frame} (typed : Layout (.operands intent bindings remaining evaluated :: tail))
    (nextBindings : Environment) (nextRemaining : List SourceValueId) (nextEvaluated : List Located) :
    Layout (.operands intent nextBindings nextRemaining nextEvaluated :: tail) := by
  cases typed with
  | plain holds => exact False.elim (holds _ (List.mem_cons_self) _ _ _ _ rfl)
  | primitive holds => exact .primitive holds
  | term holds => exact .term holds

theorem Fits.layout (typed : Fits next frames) : Layout frames := by
  cases next with
  | execute intent bindings values => cases intent <;> first | exact typed | exact Layout.plain typed
  | expression | delivered | unwind => exact typed
  | term | invoke | release | discard => exact Layout.plain typed

theorem Plain.valid (typed : Plain machine) : Valid machine := by
  refine ⟨?_, typed.2⟩
  cases machine.control with
  | execute intent bindings values => cases intent <;> first | exact typed.1 | exact Layout.plain typed.1
  | expression | delivered | unwind => exact Layout.plain typed.1
  | term | invoke | release | discard => exact typed.1

theorem Valid.layout (typed : Valid machine) : Layout machine.stack := typed.1.layout

theorem Valid.nonoperand (typed : Valid machine) (stacked : machine.stack = saved :: tail)
    (different : ∀ intent bindings remaining evaluated, saved ≠ .operands intent bindings remaining evaluated) : Plain machine := by
  refine ⟨?_, typed.2⟩
  have layout : Layout (saved :: tail) := by simpa only [stacked] using typed.layout
  simpa only [stacked] using layout.nonoperand different

theorem Plain.with_control (typed : Plain machine) (next : Control) : Plain { machine with control := next } := typed

theorem noOperands_rename (frames : List Frame) (mapping : Renaming) (typed : NoOperands frames) :
    NoOperands (frames.map (renameFrame mapping)) := by
  intro saved member
  obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
  have originalTyped := typed original originalMember
  cases original <;> try simp [renameFrame]
  exact False.elim (originalTyped _ _ _ _ rfl)

theorem noOperands_trim (frames : List Frame) (context : Context) (typed : NoOperands frames) :
    NoOperands (frames.map (trimFrame context)) := by
  intro saved member
  obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
  have originalTyped := typed original originalMember
  cases original <;> simp_all [trimFrame]

theorem ObjectValid.rename (stored : Object) (mapping : Renaming) (typed : ObjectValid stored) :
    ObjectValid (renameObject mapping stored) := by
  cases stored <;> first | trivial | exact noOperands_rename _ _ typed

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem heap_lookup (store : Heap) (node : NodeId) (stored : Object)
    (found : store.lookup node = some stored) (typed : HeapValid store) : ObjectValid stored := by
  simp only [Heap.lookup, Option.bind_eq_some_iff] at found
  obtain ⟨entry, atNode, present⟩ := found
  cases entry <;> simp [id] at present
  cases present
  exact typed _ (List.mem_of_getElem? atNode) _ rfl

theorem lookupObject_valid (machine : State) (value : Located) (node : NodeId) (stored : Object)
    (accepted : lookupObject machine value = .ok (node, stored)) (typed : HeapValid machine.heap) : ObjectValid stored := by
  simp only [lookupObject, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, found, equal⟩ := accepted
  cases equal
  exact heap_lookup _ _ _ found typed

theorem allocateObject_valid (before after : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject before schema stored owner exclusive = some (after, value))
    (typed : HeapValid before) (storedTyped : ObjectValid stored) : HeapValid after := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, _⟩ := accepted
    simp only [HeapValid, List.mem_append, List.mem_singleton] at typed ⊢
    grind only [Option.mem_def]
  · obtain ⟨_, _, rfl, _⟩ := accepted
    simp only [HeapValid, List.mem_append, List.mem_singleton] at typed ⊢
    grind only [Option.mem_def]

theorem replaceObject_valid (before after : Heap) (node : NodeId) (stored : Object)
    (accepted : replaceObject before node stored = some after)
    (typed : HeapValid before) (storedTyped : ObjectValid stored) : HeapValid after := by
  unfold replaceObject at accepted
  split at accepted <;> try contradiction
  cases accepted
  simp only [HeapValid] at typed ⊢
  grind only [→ List.mem_or_eq_of_mem_set, Option.mem_def]

theorem retireObject_valid (before after : Heap) (value : Located)
    (accepted : retireObject before value = some after) (typed : HeapValid before) : HeapValid after := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, Option.bind_eq_some_iff, consumeValue, pure, Option.some.injEq] at accepted
  obtain ⟨_, _, _, ⟨_, _, rfl⟩, rfl⟩ := accepted
  simp only [HeapValid] at typed ⊢
  grind only [→ List.mem_or_eq_of_mem_set, Option.mem_def]

theorem moveValues_valid (before after : Heap) (values : List Located) (receiver : Nat → Custody.Owner)
    (accepted : moveValues before values receiver = some after) (typed : HeapValid before) : HeapValid after := by
  simp [moveValues, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  exact typed


theorem temporary_shape (machine after : State) (owner : Custody.Owner)
    (accepted : temporary machine = .ok (after, owner)) :
    after.control = machine.control ∧ after.stack = machine.stack ∧ after.heap.objects = machine.heap.objects := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  exact ⟨rfl, rfl, rfl⟩

theorem finishTemporary_shape (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) :
    after.state.control = .delivered value ∧ after.state.stack = machine.stack ∧ after.state.heap.objects = machine.heap.objects := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  cases accepted
  exact ⟨rfl, rfl, rfl⟩

theorem scopedValue_shape (machine : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue machine value = .ok after) :
    (∃ result, after.state.control = .delivered result) ∧ after.state.stack = machine.stack ∧ after.state.heap.objects = machine.heap.objects := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, finished⟩ := accepted
  have middleShape := temporary_shape _ _ _ temporaryOk
  have finalShape := finishTemporary_shape _ _ _ finished
  exact ⟨⟨_, finalShape.1⟩, finalShape.2.1.trans middleShape.2.1, finalShape.2.2.trans middleShape.2.2⟩

theorem moveValues_objects (before after : Heap) (values : List Located) (receiver : Nat → Custody.Owner)
    (accepted : moveValues before values receiver = some after) : after.objects = before.objects := by
  simp [moveValues, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  rfl

theorem commitPure_shape (machine : State) (opcode : Opcode) (operands : List Located)
    (value : SemanticValue) (after : Transition) (accepted : commitPure machine opcode operands value = .ok after) :
    (∃ result, after.state.control = .delivered result) ∧ after.state.stack = machine.stack ∧ after.state.heap.objects = machine.heap.objects := by
  simp only [commitPure, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, accepted⟩ := accepted
  have middleShape := temporary_shape _ _ _ temporaryOk
  split at accepted <;> simp only [except_bind_ok, fromOption_ok] at accepted
  · obtain ⟨_, _, _, _, finished⟩ := accepted
    have finalShape := finishTemporary_shape _ _ _ finished
    exact ⟨⟨_, finalShape.1⟩, finalShape.2.1.trans middleShape.2.1, finalShape.2.2.trans middleShape.2.2⟩
  · obtain ⟨moved, movedOk, _, _, _, _, finished⟩ := accepted
    have movedShape := moveValues_objects _ _ _ _ movedOk
    have finalShape := finishTemporary_shape _ _ _ finished
    exact ⟨⟨_, finalShape.1⟩, finalShape.2.1.trans middleShape.2.1, finalShape.2.2.trans (movedShape.trans middleShape.2.2)⟩

theorem makeClosureWithValues_shape (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues machine context schema function values = .ok after)
    (typed : HeapValid machine.heap) :
    (∃ result, after.state.control = .delivered result) ∧ after.state.stack = machine.stack ∧ HeapValid after.state.heap := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, ⟨middle, owner⟩, temporaryOk, moved, movedOk, ⟨store, result⟩, allocated, finished⟩ := accepted
  have middleShape := temporary_shape _ _ _ temporaryOk
  have middleTyped : HeapValid middle.heap := by simpa only [HeapValid, middleShape.2.2] using typed
  have movedTyped := moveValues_valid _ _ _ _ movedOk middleTyped
  have allocatedTyped := allocateObject_valid _ _ _ _ _ _ _ allocated movedTyped trivial
  have finalShape := finishTemporary_shape _ _ _ finished
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

theorem authoredFailure_shape (machine : State) (context : Context) (failures : List (InstructionFailure .source))
    (fault : Fault) (after : Transition) (accepted : authoredFailure machine context failures fault = .ok after) :
    (∃ exit, after.state.control = .unwind exit) ∧ after.state.stack = machine.stack ∧ after.state.heap.objects = machine.heap.objects := by
  simp only [authoredFailure, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  exact ⟨⟨_, rfl⟩, rfl, rfl⟩


theorem HeapValid.of_objects (typed : HeapValid before) (same : after.objects = before.objects) : HeapValid after := by
  simpa only [HeapValid, same] using typed

theorem finishTemporary_valid (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) (typed : HeapValid machine.heap) :
    (∃ result, after.state.control = .delivered result) ∧ after.state.stack = machine.stack ∧ HeapValid after.state.heap := by
  have shape := finishTemporary_shape _ _ _ accepted
  exact ⟨⟨_, shape.1⟩, shape.2.1, typed.of_objects shape.2.2⟩

theorem scopedValue_valid (machine : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue machine value = .ok after) (typed : HeapValid machine.heap) :
    (∃ result, after.state.control = .delivered result) ∧ after.state.stack = machine.stack ∧ HeapValid after.state.heap := by
  have shape := scopedValue_shape _ _ _ accepted
  exact ⟨shape.1, shape.2.1, typed.of_objects shape.2.2⟩

theorem commitPure_valid (machine : State) (opcode : Opcode) (operands : List Located)
    (value : SemanticValue) (after : Transition) (accepted : commitPure machine opcode operands value = .ok after)
    (typed : HeapValid machine.heap) :
    (∃ result, after.state.control = .delivered result) ∧ after.state.stack = machine.stack ∧ HeapValid after.state.heap := by
  have shape := commitPure_shape _ _ _ _ _ accepted
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
    have middleShape := temporary_shape _ _ _ temporaryOk
    have movedTyped := moveValues_valid _ _ _ _ moveOk (typed.of_objects middleShape.2.2)
    have allocatedTyped := allocateObject_valid { moved with nextCell := moved.nextCell + 1 } _ _ _ _ _ _ allocated movedTyped trivial
    have finalShape := finishTemporary_valid _ _ _ finished allocatedTyped
    exact ⟨finalShape.1, finalShape.2.1.trans middleShape.2.1, finalShape.2.2⟩
  case cellGet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact scopedValue_valid _ _ _ accepted typed
  case cellSet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, store, replaced, accepted⟩ := accepted
    have storeTyped := replaceObject_valid _ _ _ _ replaced typed trivial
    have finalShape := scopedValue_valid _ _ _ accepted storeTyped
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
    have middleShape := temporary_shape _ _ _ temporaryOk
    have movedTyped := moveValues_valid _ _ _ _ moveOk (typed.of_objects middleShape.2.2)
    have allocatedTyped := allocateObject_valid _ _ _ _ _ _ _ allocated movedTyped trivial
    have finalShape := finishTemporary_valid _ _ _ finished allocatedTyped
    exact ⟨finalShape.1, finalShape.2.1.trans middleShape.2.1, finalShape.2.2⟩
  case unpack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, store, retired, accepted⟩ := accepted
    have storeTyped := retireObject_valid _ _ _ retired typed
    have finalShape := commitPure_valid _ _ _ _ _ accepted storeTyped
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
    have retiredTyped := retireObject_valid _ _ _ retireOk typed
    have middleShape := temporary_shape _ _ _ temporaryOk
    have allocatedTyped := allocateObject_valid _ _ _ _ _ _ _ allocated (retiredTyped.of_objects middleShape.2.2) captureTyped
    have finalShape := finishTemporary_valid _ _ _ finished allocatedTyped
    exact ⟨finalShape.1, finalShape.2.1.trans middleShape.2.1, finalShape.2.2⟩
  case resourcePack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, ⟨middle, owner⟩, temporaryOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have middleShape := temporary_shape _ _ _ temporaryOk
    have allocatedTyped := allocateObject_valid _ _ _ _ _ _ _ allocated (typed.of_objects middleShape.2.2) trivial
    have finalShape := finishTemporary_valid _ _ _ finished allocatedTyped
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
      have storeTyped := retireObject_valid _ _ _ retired typed
      have finalShape := scopedValue_valid _ _ _ accepted storeTyped
      exact finalShape
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      exact scopedValue_valid _ _ _ accepted typed
    · contradiction


theorem delivered_valid (before : State) (after : Transition) (layout : Layout before.stack)
    (shape : (∃ result, after.state.control = .delivered result) ∧ after.state.stack = before.stack ∧ HeapValid after.state.heap) :
    Valid after.state := by
  obtain ⟨⟨value, delivered⟩, stacked, stored⟩ := shape
  exact ⟨by simpa only [Fits, delivered, stacked] using layout, stored⟩

theorem plain_of_shape (before : State) (after : State) (typed : Plain before)
    (stacked : after.stack = before.stack) (stored : HeapValid after.heap) : Plain after :=
  ⟨by simpa only [stacked] using typed.1, stored⟩

theorem scopedValue_plain (machine : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue machine value = .ok after) (typed : Plain machine) : Plain after.state := by
  have shape := scopedValue_valid _ _ _ accepted typed.2
  exact plain_of_shape _ _ typed shape.2.1 shape.2.2

theorem finishTemporary_plain (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) (typed : Plain machine) : Plain after.state := by
  have shape := finishTemporary_valid _ _ _ accepted typed.2
  exact plain_of_shape _ _ typed shape.2.1 shape.2.2

theorem temporary_plain (machine after : State) (owner : Custody.Owner)
    (accepted : temporary machine = .ok (after, owner)) (typed : Plain machine) : Plain after := by
  have shape := temporary_shape _ _ _ accepted
  exact plain_of_shape _ _ typed shape.2.1 (typed.2.of_objects shape.2.2)

theorem createScope_shape (machine : State) (context : Context) (invocation : InvocationId)
    (parent : Option LexicalScopeId) (vars : List VariableId) (values : List Located) (bindings : Environment)
    (after : State) (entered : Environment)
    (accepted : createScope machine context invocation parent vars values bindings = .ok (after, entered)) :
    after.control = machine.control ∧ after.stack = machine.stack ∧ after.heap.objects = machine.heap.objects := by
  simp only [createScope, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · cases accepted; exact ⟨rfl, rfl, rfl⟩
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, store, moved, equal⟩ := accepted
    have same := moveValues_objects _ _ _ _ moved
    cases equal
    exact ⟨rfl, rfl, same⟩

theorem invokeFunction_plain (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction machine context function bindings arguments = .ok after)
    (typed : Plain machine) : Plain after.state := by
  simp only [invokeFunction, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, ⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have shape := createScope_shape _ _ _ _ _ _ _ _ _ scopeOk
  refine ⟨?_, typed.2.of_objects shape.2.2⟩
  exact (noOperands_cons _ _).mpr ⟨(by intro _ _ _ _ unequal; cases unequal), typed.1⟩

theorem applyClosure_plain (machine : State) (context : Context) (closure : Located)
    (arguments : List Located) (after : Transition)
    (accepted : applyClosure machine context closure arguments = .ok after) (typed : Plain machine) : Plain after.state := by
  simp only [applyClosure, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  · simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨store, retired, accepted⟩ := accepted
    have startTyped : Plain { machine with heap := store } := ⟨typed.1, retireObject_valid _ _ _ retired typed.2⟩
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
    (typed : HeapValid machine.heap) (captureTyped : NoOperands saved.frames) :
    after.1.stack = machine.stack ∧ HeapValid after.1.heap ∧ NoOperands after.2.frames := by
  unfold instantiateCapture at accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨objects, objectsAt, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  cases accepted
  have objectsTyped : ∀ entry ∈ objects, ∀ stored ∈ entry, ObjectValid stored := by
    refine mapM_preserves _ (fun entry : Option Object => ∀ stored ∈ entry, ObjectValid stored) ?_ _ _ objectsAt
    intro input output checked
    simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at checked
    obtain ⟨stored, looked, rfl⟩ := checked
    intro renamed present
    cases present
    apply ObjectValid.rename
    have storedTyped := heap_lookup _ _ _ looked typed
    cases stored <;> first | exact storedTyped | trivial
  refine ⟨rfl, ?_, noOperands_rename _ _ captureTyped⟩
  simp only [HeapValid, List.mem_append] at typed ⊢
  grind only []

theorem takeCapture_shape (machine : State) (context : Context) (token : Located) (after : State × Capture)
    (accepted : takeCapture machine context token = .ok after) (typed : HeapValid machine.heap) :
    after.1.stack = machine.stack ∧ HeapValid after.1.heap ∧ NoOperands after.2.frames := by
  simp only [takeCapture, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
  have storedTyped := lookupObject_valid _ _ _ _ looked typed
  cases stored <;> try contradiction
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨store, retired, rfl⟩ := accepted
    exact ⟨rfl, retireObject_valid _ _ _ retired typed, storedTyped⟩
  · exact instantiateCapture_shape _ _ _ _ accepted typed storedTyped

theorem activateCapture_plain (machine : State) (context : Context) (saved : Capture)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : State)
    (accepted : activateCapture machine context saved successor = .ok after) (typed : Plain machine)
    (captureTyped : NoOperands saved.frames) : Plain after := by
  simp only [activateCapture, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  cases successor with
  | none =>
    simp only [Option.isSome_none, Bool.false_or, pure, Except.pure, Except.bind, Except.ok.injEq] at accepted
    cases accepted
    split
    all_goals refine ⟨?_, typed.2⟩
    all_goals simp only [Plain, NoOperands, List.mem_append, List.mem_cons, List.not_mem_nil, or_false] at typed captureTyped ⊢
    all_goals grind only []
  | some successor =>
    rcases successor with ⟨handler, stored, bindings⟩
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, _, rfl, rfl⟩ := accepted
    refine ⟨?_, typed.2⟩
    simp only [Option.isSome_some, Bool.true_or, if_true, Plain, NoOperands, List.mem_append,
      List.mem_cons, List.not_mem_nil, or_false] at typed captureTyped ⊢
    grind only []

theorem resumeValue_plain (machine : State) (context : Context) (token argument : Located)
    (successor : Option (HandlerId .source × List Located × Environment)) (after : Transition)
    (accepted : resumeValue machine context token argument successor = .ok after) (typed : Plain machine) : Plain after.state := by
  simp only [resumeValue, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, _, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, active, activated, ⟨middle, owner⟩, temporaryOk, store, moved, finished⟩ := accepted
  have capturedShape := takeCapture_shape _ _ _ _ captured typed.2
  have takenTyped := plain_of_shape _ _ typed capturedShape.1 capturedShape.2.1
  have activeTyped := activateCapture_plain _ _ _ _ _ activated takenTyped capturedShape.2.2
  have middleTyped := temporary_plain _ _ _ temporaryOk activeTyped
  have movedTyped : Plain { middle with heap := store } := ⟨middleTyped.1, moveValues_valid _ _ _ _ moved middleTyped.2⟩
  exact finishTemporary_plain _ _ _ finished movedTyped

theorem resumeComputation_plain (machine : State) (context : Context) (token computation : Located) (after : Transition)
    (accepted : resumeComputation machine context token computation = .ok after) (typed : Plain machine) : Plain after.state := by
  simp only [resumeComputation, bind, except_bind_ok] at accepted
  obtain ⟨⟨taken, saved⟩, captured, active, activated, applied⟩ := accepted
  have capturedShape := takeCapture_shape _ _ _ _ captured typed.2
  have takenTyped := plain_of_shape _ _ typed capturedShape.1 capturedShape.2.1
  have activeTyped := activateCapture_plain _ _ _ _ _ activated takenTyped capturedShape.2.2
  exact applyClosure_plain _ _ _ _ _ applied activeTyped

end OperandStructure
end BoundaryV2.Profile.Source.Machine
