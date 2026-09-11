import BoundaryV2.SourceEffectTypes

namespace BoundaryV2.Profile.Source.Machine

namespace EnvironmentInventory

def frame : Frame → Environment
  | .binding _ _ bindings _ | .operands _ bindings _ _ => bindings
  | .handler active => active.environment
  | _ => []

def capture (saved : Capture) : Environment := saved.frames.flatMap frame ++ saved.delimiter.environment

def object : Object → Environment
  | .closure _ _ bindings => bindings
  | .oneShot saved | .multiTemplate saved => capture saved
  | _ => []

def heap (store : Heap) : Environment := store.objects.flatMap (fun entry => entry.toList.flatMap object)

def control : Control → Environment
  | .term _ bindings | .expression _ bindings | .execute _ bindings _ | .invoke _ bindings _ => bindings
  | _ => []

def state (machine : State) : Environment := control machine.control ++ machine.stack.flatMap frame ++ heap machine.heap

def All (source : Module) (machine : State) : Prop := Environment.Types source (state machine)

theorem frame_types (source : Module) (machine : State) (saved : Frame) (member : saved ∈ machine.stack)
    (typed : All source machine) : Environment.Types source (frame saved) := by
  intro binding belongs
  apply typed
  simp only [state, List.mem_append, List.mem_flatMap]
  exact Or.inl (Or.inr ⟨saved, member, belongs⟩)

theorem control_types (source : Module) (machine : State) (typed : All source machine) :
    Environment.Types source (control machine.control) := by
  intro binding member
  exact typed binding (List.mem_append_left _ (List.mem_append_left _ member))

theorem stack_types (source : Module) (machine : State) (typed : All source machine) :
    Environment.Types source (machine.stack.flatMap frame) := by
  intro binding member
  exact typed binding (List.mem_append_left _ (List.mem_append_right _ member))

theorem with_control_types (source : Module) (machine : State) (next : Control) (typed : All source machine)
    (nextTyped : Environment.Types source (control next)) : All source { machine with control := next } := by
  simp only [All, Environment.Types, state, List.mem_append] at typed ⊢
  simp only [Environment.Types] at nextTyped
  grind only []

theorem with_stack_types (source : Module) (machine : State) (next : List Frame) (typed : All source machine)
    (nextTyped : Environment.Types source (next.flatMap frame)) : All source { machine with stack := next } := by
  simp only [All, Environment.Types, state, List.mem_append] at typed ⊢
  simp only [Environment.Types] at nextTyped
  grind only []

theorem tail_types (source : Module) (machine : State) (saved : Frame) (tail : List Frame)
    (stacked : machine.stack = saved :: tail) (typed : All source machine) :
    Environment.Types source (tail.flatMap frame) := by
  intro binding member
  apply stack_types source machine typed
  simp [stacked, member]

theorem lookup_types (source : Module) (machine : State) (node : NodeId) (stored : Object)
    (found : machine.heap.lookup node = some stored) (typed : All source machine) :
    Environment.Types source (object stored) := by
  simp only [Heap.lookup, Option.bind_eq_some_iff] at found
  obtain ⟨entry, atNode, present⟩ := found
  have nodeMember := List.mem_of_getElem? atNode
  cases entry <;> simp [id] at present
  cases present
  intro binding member
  apply typed
  simp only [state, heap, List.mem_append, List.mem_flatMap]
  grind only [Option.toList_some, List.mem_singleton]

theorem rename_frame (mapping : Renaming) (saved : Frame) :
    frame (renameFrame mapping saved) = renameEnvironment mapping (frame saved) := by
  cases saved <;> rfl

theorem rename_capture (mapping : Renaming) (saved : Capture) :
    capture (renameCapture mapping saved) = renameEnvironment mapping (capture saved) := by
  simp [capture, renameCapture, renameActivation, renameEnvironment, rename_frame,
    List.flatMap_map, List.map_flatMap]

theorem rename_object (mapping : Renaming) (stored : Object) :
    object (renameObject mapping stored) = renameEnvironment mapping (object stored) := by
  cases stored <;> simp [object, renameObject, rename_capture, renameEnvironment]

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

private theorem require_ok (condition : Bool) (reason : Invalid) (result : Unit)
    (accepted : require condition reason = .ok result) : condition = true := by
  unfold require at accepted
  split at accepted <;> first | assumption | contradiction

theorem initial_types (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) : All context.source machine := by
  simp only [initial, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ := accepted
  simp [All, Environment.Types, state, control, heap]

theorem finishValue_preserves_types (source : Module) (machine : State) (value : Located)
    (typed : All source machine) : All source (finishValue machine value).state := by
  simp only [finishValue, All, Environment.Types, state, control, List.nil_append, List.mem_append] at typed ⊢
  grind only []

theorem temporary_preserves_types (source : Module) (machine after : State) (owner : Custody.Owner)
    (accepted : temporary machine = .ok (after, owner)) (typed : All source machine) : All source after := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  exact typed

theorem finishTemporary_preserves_types (source : Module) (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) (typed : All source machine) : All source after.state := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  cases accepted
  simp only [finishValue, All, Environment.Types, state, control, heap, List.nil_append, List.mem_append] at typed ⊢
  grind only []

theorem scopedValue_preserves_types (source : Module) (machine : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue machine value = .ok after) (typed : All source machine) : All source after.state := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, finished⟩ := accepted
  exact finishTemporary_preserves_types _ _ _ _ finished (temporary_preserves_types _ _ _ _ temporaryOk typed)

theorem moveValues_preserves_types (source : Module) (machine : State) (store : Heap) (values : List Located)
    (receiver : Nat → Custody.Owner) (accepted : moveValues machine.heap values receiver = some store)
    (typed : All source machine) : All source { machine with heap := store } := by
  simp [moveValues, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  exact typed

theorem allocateObject_preserves_types (source : Module) (machine : State) (store : Heap) (schema : SchemaId .source)
    (stored : Object) (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject machine.heap schema stored owner exclusive = some (store, value))
    (typed : All source machine) (storedTyped : Environment.Types source (object stored)) :
    All source { machine with heap := store } := by
  simp only [Environment.Types] at storedTyped
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, _⟩ := accepted
    simp only [All, Environment.Types, state, heap, List.flatMap_append, List.flatMap_cons, List.flatMap_nil,
      Option.toList_some, List.append_nil, List.mem_append] at typed ⊢
    grind only []
  · obtain ⟨_, _, rfl, _⟩ := accepted
    simp only [All, Environment.Types, state, heap, List.flatMap_append, List.flatMap_cons, List.flatMap_nil,
      Option.toList_some, List.append_nil, List.mem_append] at typed ⊢
    grind only []

theorem replaceObject_preserves_types (source : Module) (machine : State) (node : NodeId) (stored : Object) (store : Heap)
    (accepted : replaceObject machine.heap node stored = some store) (typed : All source machine)
    (storedTyped : Environment.Types source (object stored)) : All source { machine with heap := store } := by
  simp only [Environment.Types] at storedTyped
  unfold replaceObject at accepted
  split at accepted <;> try contradiction
  cases accepted
  simp only [All, Environment.Types, state, heap, List.mem_append, List.mem_flatMap] at typed ⊢
  grind only [→ List.mem_or_eq_of_mem_set, Option.toList_some, List.mem_singleton]

theorem retireObject_preserves_types (source : Module) (machine : State) (located : Located) (store : Heap)
    (accepted : retireObject machine.heap located = some store) (typed : All source machine) :
    All source { machine with heap := store } := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, Option.bind_eq_some_iff, consumeValue, pure, Option.some.injEq] at accepted
  obtain ⟨_, _, _, ⟨_, _, rfl⟩, rfl⟩ := accepted
  simp only [All, Environment.Types, state, heap, List.mem_append, List.mem_flatMap] at typed ⊢
  grind only [→ List.mem_or_eq_of_mem_set, Option.toList_none, List.not_mem_nil]

theorem commitPure_preserves_types (source : Module) (machine : State) (opcode : Opcode)
    (operands : List Located) (value : SemanticValue) (after : Transition)
    (accepted : commitPure machine opcode operands value = .ok after) (typed : All source machine) :
    All source after.state := by
  simp only [commitPure, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, accepted⟩ := accepted
  have middleTyped := temporary_preserves_types _ _ _ _ temporaryOk typed
  split at accepted <;> simp only [except_bind_ok, fromOption_ok] at accepted
  · obtain ⟨_, _, _, _, finished⟩ := accepted
    exact finishTemporary_preserves_types _ _ _ _ finished middleTyped
  · obtain ⟨moved, movedOk, _, _, _, _, finished⟩ := accepted
    have movedTyped := moveValues_preserves_types _ _ _ _ _ movedOk middleTyped
    exact finishTemporary_preserves_types _ _ _ _ finished movedTyped

theorem authoredFailure_preserves_types (machine : State) (context : Context)
    (failures : List (InstructionFailure .source)) (fault : Fault) (after : Transition)
    (accepted : authoredFailure machine context failures fault = .ok after) (typed : All context.source machine) :
    All context.source after.state := by
  simp only [authoredFailure, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  simp only [All, Environment.Types, state, control, List.nil_append, List.mem_append] at typed ⊢
  grind only []

theorem makeClosureWithValues_preserves_types (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues machine context schema function values = .ok after)
    (typed : All context.source machine) : All context.source after.state := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, checked, ⟨middle, owner⟩, temporaryOk, moved, movedOk, ⟨store, result⟩, allocated, finished⟩ := accepted
  have fields := (Bool.and_eq_true_iff.mp (require_ok _ _ _ checked)).2
  have middleTyped := temporary_preserves_types _ _ _ _ temporaryOk typed
  have movedTyped := moveValues_preserves_types _ _ _ _ _ movedOk middleTyped
  have storedTyped : Environment.Types context.source (object (.closure schema function
      (((Analysis.captures context.captures function).zip values).mapIdx (fun index (binder, value) =>
        Binding.mk binder (retainAt value (.closure ⟨middle.heap.objects.length⟩ index)))))) := by
    intro binding member
    simp only [object, List.mapIdx_eq_zipIdx_map, List.mem_map] at member
    obtain ⟨⟨⟨binder, value⟩, index⟩, member, rfl⟩ := member
    have pairMember := List.fst_mem_of_mem_zipIdx member
    simpa only [beq_iff_eq, retainAt] using List.all_eq_true.mp fields (binder, value) pairMember
  have allocatedTyped := allocateObject_preserves_types _ _ _ _ _ _ _ _ allocated movedTyped storedTyped
  exact finishTemporary_preserves_types _ _ _ _ finished allocatedTyped

theorem makeClosure_preserves_types (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (bindings : Environment) (after : Transition)
    (accepted : makeClosure machine context schema function bindings = .ok after)
    (typed : All context.source machine) : All context.source after.state := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  exact makeClosureWithValues_preserves_types _ _ _ _ _ _ accepted typed

theorem createScope_preserves_types (machine : State) (context : Context) (invocation : InvocationId)
    (parent : Option LexicalScopeId) (vars : List VariableId) (values : List Located) (bindings : Environment)
    (after : State) (entered : Environment)
    (accepted : createScope machine context invocation parent vars values bindings = .ok (after, entered))
    (typed : All context.source machine) : All context.source after := by
  simp only [createScope, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · cases accepted; exact typed
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, store, moved, equal⟩ := accepted
    have movedTyped := moveValues_preserves_types _ _ _ _ _ moved typed
    cases equal
    exact movedTyped

theorem invokeFunction_preserves_types (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction machine context function bindings arguments = .ok after)
    (typed : All context.source machine) : All context.source after.state := by
  simp only [invokeFunction, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨definition, _, body, _, captured, _, _, _, _, _, ⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have middleTyped := createScope_preserves_types _ _ _ _ _ _ _ _ _ scopeOk typed
  have enteredTyped := createScope_preserves_environment_types _ _ _ _ _ _ _ _ _
    (by simp [Environment.Types]) scopeOk
  have sameStack := (ValueInventory.createScope_preserves_control_stack _ _ _ _ _ _ _ _ _ scopeOk).2
  simp only [All, Environment.Types, state, control, heap, sameStack, List.flatMap_cons, frame,
    List.nil_append, List.mem_append] at middleTyped ⊢
  simp only [Environment.Types] at enteredTyped
  grind only []

theorem enterExpression_preserves_types (machine : State) (context : Context) (after : Transition)
    (accepted : enterExpression machine context = .ok after) (typed : All context.source machine) :
    All context.source after.state := by
  unfold enterExpression at accepted
  split at accepted <;> try contradiction
  rename_i reference bindings executing
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨schema, expression⟩, _, accepted⟩ := accepted
  cases expression with
  | «variable» binder =>
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨value, _, _, _, _, _, rfl⟩ := accepted
    exact finishValue_preserves_types _ _ _ typed
  | literal constant =>
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨value, _, _, _, accepted⟩ := accepted
    exact scopedValue_preserves_types _ _ _ _ accepted typed
  | lambda function => exact makeClosure_preserves_types _ _ _ _ _ _ accepted typed
  | primitive opcode operands immediate failures =>
    cases operands <;> cases accepted
    all_goals simp only [All, Environment.Types, state, executing, control, frame,
      List.flatMap_cons, List.mem_append] at typed ⊢
    all_goals grind only []

theorem enterTerm_preserves_types (machine : State) (source : Module) (after : Transition)
    (accepted : enterTerm machine source = .ok after) (typed : All source machine) : All source after.state := by
  unfold enterTerm at accepted
  split at accepted <;> try contradiction
  rename_i reference bindings executing
  split at accepted <;> try contradiction
  repeat' split at accepted
  all_goals cases accepted
  all_goals simp only [All, Environment.Types, state, executing, control, frame,
    List.flatMap_cons, List.mem_append] at typed ⊢
  all_goals grind only []

theorem deliverOperand_preserves_types (machine : State) (after : Transition)
    (accepted : deliverOperand machine = .ok after) (typed : All source machine) : All source after.state := by
  unfold deliverOperand at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i intent bindings remaining evaluated tail stacked
  split at accepted <;> cases accepted
  all_goals simp only [All, Environment.Types, state, stacked, control, frame,
    List.flatMap_cons, List.mem_append] at typed ⊢
  all_goals grind only []

theorem lookupObject_types (source : Module) (machine : State) (value : Located) (node : NodeId) (stored : Object)
    (accepted : lookupObject machine value = .ok (node, stored)) (typed : All source machine) :
    Environment.Types source (object stored) := by
  simp only [lookupObject, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, found, equal⟩ := accepted
  cases equal
  exact lookup_types _ _ _ _ found typed

theorem applyClosure_preserves_types (machine : State) (context : Context) (closure : Located)
    (arguments : List Located) (after : Transition)
    (accepted : applyClosure machine context closure arguments = .ok after) (typed : All context.source machine) :
    All context.source after.state := by
  simp only [applyClosure, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, object⟩, _, accepted⟩ := accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  · simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨store, retired, accepted⟩ := accepted
    exact invokeFunction_preserves_types _ _ _ _ _ _ accepted (retireObject_preserves_types _ _ _ _ retired typed)
  · simp only [pure, Except.pure, Except.bind] at accepted
    exact invokeFunction_preserves_types _ _ _ _ _ _ accepted typed

theorem enterInvocation_preserves_types (machine : State) (context : Context) (after : Transition)
    (accepted : enterInvocation machine context = .ok after) (typed : All context.source machine) :
    All context.source after.state := by
  unfold enterInvocation at accepted
  split at accepted <;> try contradiction
  exact invokeFunction_preserves_types _ _ _ _ _ _ accepted typed

theorem enterBinding_preserves_types (machine : State) (context : Context) (after : Transition)
    (accepted : enterBinding machine context = .ok after) (typed : All context.source machine) :
    All context.source after.state := by
  unfold enterBinding at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i binder body bindings parent tail stacked
  have bindingsTyped := frame_types context.source machine (.binding binder body bindings parent) (by simp [stacked]) typed
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have middleTyped := createScope_preserves_types _ _ _ _ _ _ _ _ _ scopeOk typed
  have enteredTyped := createScope_preserves_environment_types _ _ _ _ _ _ _ _ _ bindingsTyped scopeOk
  have sameStack := (ValueInventory.createScope_preserves_control_stack _ _ _ _ _ _ _ _ _ scopeOk).2
  split
  all_goals simp only [All, Environment.Types, state, control, sameStack, stacked, List.flatMap_cons, frame,
    List.nil_append, List.mem_append] at middleTyped ⊢
  all_goals simp only [Environment.Types] at enteredTyped
  all_goals grind only []

theorem enterPattern_preserves_types (machine : State) (context : Context) (vars : List VariableId)
    (parts : List SemanticValue) (owner : Custody.Owner) (body : TermId) (bindings : Environment) (after : Transition)
    (accepted : enterPattern machine context vars parts owner body bindings = .ok after)
    (typed : All context.source machine) (outer : Environment.Types context.source bindings) :
    All context.source after.state := by
  simp only [enterPattern, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have middleTyped := createScope_preserves_types _ _ _ _ _ _ _ _ _ scopeOk typed
  have enteredTyped := createScope_preserves_environment_types _ _ _ _ _ _ _ _ _ outer scopeOk
  have sameStack := (ValueInventory.createScope_preserves_control_stack _ _ _ _ _ _ _ _ _ scopeOk).2
  split
  all_goals simp only [All, Environment.Types, state, control, sameStack, List.flatMap_cons, frame,
    List.nil_append, List.mem_append] at middleTyped ⊢
  all_goals simp only [Environment.Types] at enteredTyped
  all_goals grind only []

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

theorem instantiateCapture_preserves_types (machine : State) (context : Context) (saved : Capture)
    (after : State × Capture) (accepted : instantiateCapture machine context saved = .ok after)
    (typed : All context.source machine) (captureTyped : Environment.Types context.source (capture saved)) :
    All context.source after.1 ∧ Environment.Types context.source (capture after.2) := by
  unfold instantiateCapture at accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨objects, objectsAt, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  obtain ⟨_, _, accepted⟩ := (except_bind_ok _ _ _).mp accepted
  cases accepted
  have objectsTyped : ∀ entry ∈ objects, Environment.Types context.source (entry.toList.flatMap object) := by
    refine mapM_preserves _ (fun entry : Option Object => Environment.Types context.source (entry.toList.flatMap object))
      ?_ _ _ objectsAt
    intro input output checked
    simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at checked
    obtain ⟨stored, looked, rfl⟩ := checked
    have storedTyped := lookup_types _ _ _ _ looked typed
    simp only [Option.toList_some, List.flatMap_cons, List.flatMap_nil, List.append_nil, rename_object]
    apply Environment.Types.rename
    cases stored <;> first | exact storedTyped | simp [object, Environment.Types]
  have objectsAll : Environment.Types context.source (objects.flatMap (fun entry => entry.toList.flatMap object)) := by
    intro binding member
    obtain ⟨entry, entryMember, member⟩ := List.mem_flatMap.mp member
    exact objectsTyped entry entryMember binding member
  constructor
  · simp only [All, Environment.Types, state, heap, List.flatMap_append, List.mem_append] at typed ⊢
    simp only [Environment.Types] at objectsAll
    grind only []
  · rw [rename_capture]
    exact captureTyped.rename _ _ _

theorem leaveScope_preserves_types (source : Module) (machine : State) (parent : LexicalScopeId)
    (invocation : InvocationId) (tail : List Frame) (value : Located) (after : Transition)
    (accepted : leaveScope machine parent invocation tail value = .ok after) (typed : All source machine)
    (tailTyped : Environment.Types source (tail.flatMap frame)) : All source after.state := by
  simp only [leaveScope, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, store, moved, finished, finishOk, rfl⟩ := accepted
  have startTyped := with_stack_types source machine tail typed tailTyped
  have middleTyped := temporary_preserves_types _ _ _ _ temporaryOk startTyped
  have movedTyped := moveValues_preserves_types _ _ _ _ _ moved middleTyped
  have finishedTyped := finishTemporary_preserves_types _ _ _ _ finishOk movedTyped
  exact with_control_types _ _ _ finishedTyped (by simp [Environment.Types, control])

theorem leaveInvocation_preserves_types (source : Module) (machine : State) (after : Transition)
    (accepted : leaveInvocation machine = .ok after) (typed : All source machine) : All source after.state := by
  unfold leaveInvocation at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i invocation parent tail stacked
  exact leaveScope_preserves_types _ _ _ _ _ _ _ accepted typed (tail_types _ _ _ _ stacked typed)

theorem leaveLexical_preserves_types (source : Module) (machine : State) (after : Transition)
    (accepted : leaveLexical machine = .ok after) (typed : All source machine) : All source after.state := by
  unfold leaveLexical at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i scope tail stacked
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, record, _, parent, _, result, leaving, accepted⟩ := accepted
  have leavingTyped := leaveScope_preserves_types _ _ _ _ _ _ _ leaving typed (tail_types _ _ _ _ stacked typed)
  split at accepted <;> try contradiction
  rename_i releasedScope delivered controlAt
  simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, store, moved, rfl⟩ := accepted
  have movedTyped := moveValues_preserves_types _ _ _ _ _ moved leavingTyped
  have finalTyped := with_control_types _ _ (.delivered delivered) movedTyped (by simp [control, Environment.Types])
  exact finalTyped

theorem resumeRelease_preserves_types (source : Module) (machine : State) (after : AfterRelease)
    (typed : All source machine) : All source (resumeRelease machine after).state := by
  cases after <;> exact with_control_types _ _ _ typed (by simp [control, Environment.Types])

theorem finishEmptyRelease_preserves_types (source : Module) (machine : State) (after : Transition)
    (accepted : finishEmptyRelease machine = .ok after) (typed : All source machine) : All source after.state := by
  unfold finishEmptyRelease at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, rfl⟩ := accepted
  exact resumeRelease_preserves_types _ _ _ typed

theorem restoreResumeCaller_preserves_types (source : Module) (machine : State) (after : Transition)
    (accepted : restoreResumeCaller machine = .ok after) (typed : All source machine) : All source after.state := by
  unfold restoreResumeCaller at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  rename_i invocation scope tail stacked
  have tailTyped := tail_types _ _ _ _ stacked typed
  have startTyped := with_stack_types _ _ _ typed tailTyped
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, store, moved, finished⟩ := accepted
  have middleTyped := temporary_preserves_types _ _ _ _ temporaryOk startTyped
  have movedTyped := moveValues_preserves_types _ _ _ _ _ moved middleTyped
  exact finishTemporary_preserves_types _ _ _ _ finished movedTyped

theorem cancel_control_has_no_bindings (before : Control) (reason : Protocol.Reason) :
    control (cancelControl before reason) = [] := by
  cases before <;> simp only [cancelControl]
  all_goals repeat' split
  all_goals rfl

theorem external_preserves_types (machine : State) (context : Context) (action : External) (after : Transition)
    (accepted : external machine context action = .ok after) (typed : All context.source machine) :
    All context.source after.state := by
  have running : All context.source { machine with status := .running } := typed
  have cancelled (reason : Protocol.Reason) : All context.source
      { machine with status := .running, control := cancelControl machine.control reason, cancellation := some reason } := by
    have cleared := with_control_types context.source machine (cancelControl machine.control reason) typed
      (by simp [cancel_control_has_no_bindings, Environment.Types])
    exact cleared
  have cancellationOnly (reason : Protocol.Reason) :
      All context.source { machine with cancellation := some reason } := typed
  have scopedResult (value : SemanticValue) (transition : Transition)
      (checked : scopedValue { machine with status := .running } value = .ok transition) :
      All context.source transition.state := scopedValue_preserves_types _ _ _ _ checked running
  cases phase : machine.status <;> cases action <;>
    simp only [external, phase, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw,
      Except.bind] at accepted <;> try contradiction
  all_goals grind (gen := 32) only []

end EnvironmentInventory
end BoundaryV2.Profile.Source.Machine
