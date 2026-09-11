import BoundaryV2.SourcePrimitiveTypes

namespace BoundaryV2.Profile.Source.Machine
namespace ClosureContracts

/-- Stored closure code and its ordered capture binders retain the source
admission contract. Value schemas are supplied separately by EnvironmentInventory. -/
def ObjectValid (context : Context) : Object → Prop
  | .closure schema function bindings =>
    Admission.lambdaValid context.source context.captures function schema = true ∧
    bindings.map Binding.var = Analysis.captures context.captures function
  | _ => True

def Valid (context : Context) (objects : List (Option Object)) : Prop :=
  ∀ entry ∈ objects, ∀ stored ∈ entry, ObjectValid context stored


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

theorem rename_object (context : Context) (mapping : Renaming) (stored : Object)
    (typed : ObjectValid context stored) : ObjectValid context (renameObject mapping stored) := by
  cases stored <;> simp_all [ObjectValid, renameObject, renameEnvironment, List.map_map, Function.comp_def]

theorem heap_lookup (context : Context) (store : Heap) (node : NodeId) (stored : Object)
    (found : store.lookup node = some stored) (typed : Valid context store.objects) : ObjectValid context stored := by
  simp only [Heap.lookup, Option.bind_eq_some_iff] at found
  obtain ⟨entry, atNode, present⟩ := found
  cases entry <;> simp [id] at present
  cases present
  exact typed _ (List.mem_of_getElem? atNode) _ rfl

theorem allocate_valid (context : Context) (before after : Heap) (schema : SchemaId .source)
    (stored : Object) (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject before schema stored owner exclusive = some (after, value))
    (typed : Valid context before.objects) (storedTyped : ObjectValid context stored) : Valid context after.objects := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, _⟩ := accepted
    simp only [Valid, List.mem_append, List.mem_singleton] at typed ⊢
    grind only [Option.mem_def, Option.some.inj]
  · obtain ⟨_, _, rfl, _⟩ := accepted
    simp only [Valid, List.mem_append, List.mem_singleton] at typed ⊢
    grind only [Option.mem_def, Option.some.inj]

theorem replace_valid (context : Context) (before after : Heap) (node : NodeId) (stored : Object)
    (accepted : replaceObject before node stored = some after) (typed : Valid context before.objects)
    (storedTyped : ObjectValid context stored) : Valid context after.objects := by
  unfold replaceObject at accepted
  split at accepted <;> try contradiction
  cases accepted
  intro entry member value present
  rcases List.mem_or_eq_of_mem_set member with old | rfl
  · exact typed _ old _ present
  · cases present; exact storedTyped

theorem retire_valid (context : Context) (before after : Heap) (value : Located)
    (accepted : retireObject before value = some after) (typed : Valid context before.objects) : Valid context after.objects := by
  unfold retireObject at accepted
  split at accepted <;> try contradiction
  simp only [bind, Option.bind_eq_some_iff, consumeValue, pure, Option.some.injEq] at accepted
  obtain ⟨_, _, _, ⟨_, _, rfl⟩, rfl⟩ := accepted
  intro entry member value present
  rcases List.mem_or_eq_of_mem_set member with old | rfl
  · exact typed _ old _ present
  · cases present

theorem move_valid (context : Context) (before after : Heap) (values : List Located) (receiver : Nat → Custody.Owner)
    (accepted : moveValues before values receiver = some after) (typed : Valid context before.objects) : Valid context after.objects := by
  simp [moveValues, Option.bind_eq_some_iff] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  exact typed

theorem temporary_valid (context : Context) (before after : State) (owner : Custody.Owner)
    (accepted : temporary before = .ok (after, owner)) (typed : Valid context before.heap.objects) : Valid context after.heap.objects := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted; exact typed

theorem finishTemporary_valid (context : Context) (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) (typed : Valid context machine.heap.objects) : Valid context after.state.heap.objects := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  cases accepted; exact typed

theorem scopedValue_valid (context : Context) (machine : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue machine value = .ok after) (typed : Valid context machine.heap.objects) : Valid context after.state.heap.objects := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, finished⟩ := accepted
  exact finishTemporary_valid _ _ _ _ finished (temporary_valid _ _ _ _ temporaryOk typed)

theorem commitPure_valid (context : Context) (machine : State) (opcode : Opcode) (operands : List Located)
    (value : SemanticValue) (after : Transition) (accepted : commitPure machine opcode operands value = .ok after)
    (typed : Valid context machine.heap.objects) : Valid context after.state.heap.objects := by
  simp only [commitPure, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, temporaryOk, accepted⟩ := accepted
  have middleTyped := temporary_valid _ _ _ _ temporaryOk typed
  split at accepted <;> simp only [except_bind_ok, fromOption_ok] at accepted
  · obtain ⟨_, _, _, _, finished⟩ := accepted
    exact finishTemporary_valid _ _ _ _ finished middleTyped
  · obtain ⟨moved, movedOk, _, _, _, _, finished⟩ := accepted
    have movedTyped := move_valid context _ _ _ _ movedOk middleTyped
    exact finishTemporary_valid _ _ _ _ finished movedTyped

theorem makeClosureWithValues_valid (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues machine context schema function values = .ok after)
    (typed : Valid context machine.heap.objects)
    (admitted : Admission.lambdaValid context.source context.captures function schema = true) : Valid context after.state.heap.objects := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, checked, ⟨middle, owner⟩, temporaryOk, moved, movedOk, ⟨store, result⟩, allocated, finished⟩ := accepted
  have lengthEq := (Bool.and_eq_true_iff.mp (require_ok _ _ _ checked)).1
  have middleTyped := temporary_valid _ _ _ _ temporaryOk typed
  have movedTyped := move_valid context _ _ _ _ movedOk middleTyped
  have storedTyped : ObjectValid context (.closure schema function
      (((Analysis.captures context.captures function).zip values).mapIdx (fun index (binder, value) =>
        Binding.mk binder (retainAt value (.closure ⟨middle.heap.objects.length⟩ index))))) := by
    refine ⟨admitted, ?_⟩
    simp only [beq_iff_eq] at lengthEq
    simp only [List.mapIdx_eq_zipIdx_map, List.map_map]
    change List.map (Prod.fst ∘ Prod.fst) ((Analysis.captures context.captures function).zip values).zipIdx = _
    rw [← List.map_map, List.zipIdx_map_fst, List.map_fst_zip]
    simp [lengthEq]
  have allocatedTyped := allocate_valid context _ _ _ _ _ _ _ allocated movedTyped storedTyped
  exact finishTemporary_valid _ _ _ _ finished allocatedTyped

theorem makeClosure_valid (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (bindings : Environment) (after : Transition)
    (accepted : makeClosure machine context schema function bindings = .ok after) (typed : Valid context machine.heap.objects)
    (admitted : Admission.lambdaValid context.source context.captures function schema = true) : Valid context after.state.heap.objects := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  exact makeClosureWithValues_valid _ _ _ _ _ _ accepted typed admitted

theorem checked_constructor_contract (context : Context) (index : Nat) (function : FunctionId .source)
    (schema : SchemaId .source) (typed : context.typingValid = true)
    (found : (Analysis.constructors context.source)[index]? = some (function, schema)) :
    Admission.lambdaValid context.source context.captures function schema = true := by
  obtain ⟨value, member, expression, same⟩ := Analysis.constructor_has_lambda context.source (function, schema)
    (List.mem_of_getElem? found)
  obtain ⟨reference, foundValue⟩ := List.mem_iff_getElem?.mp member
  have admitted := checked_context_checks_value context ⟨reference⟩ value typed foundValue
  simpa only [Admission.primitiveValid, expression, same] using admitted

theorem enterExpression_valid (machine : State) (context : Context) (after : Transition)
    (accepted : enterExpression machine context = .ok after) (typed : Valid context machine.heap.objects)
    (contextTyped : context.typingValid = true) : Valid context after.state.heap.objects := by
  unfold enterExpression at accepted
  split at accepted <;> try contradiction
  rename_i reference bindings executing
  simp only [bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨⟨schema, expression⟩, found, accepted⟩ := accepted
  have admitted := checked_context_checks_value context reference ⟨schema, expression⟩ contextTyped found
  cases expression with
  | «variable» =>
    simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
    exact typed
  | literal =>
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, accepted⟩ := accepted
    exact scopedValue_valid _ _ _ _ accepted typed
  | lambda => exact makeClosure_valid _ _ _ _ _ _ accepted typed admitted
  | primitive _ operands => cases operands <;> cases accepted <;> exact typed

theorem heapPrimitive_valid (machine : State) (context : Context) (operation : Primitives.GraphOperation)
    (schema : SchemaId .source) (immediate : Nat) (operands : List Located) (after : Transition)
    (accepted : heapPrimitive machine context operation schema immediate operands = .ok after)
    (typed : Valid context machine.heap.objects) (contextTyped : context.typingValid = true) : Valid context after.state.heap.objects := by
  cases operation <;> simp only [heapPrimitive, bind, except_bind_ok, fromOption_ok] at accepted
  case computation =>
    obtain ⟨⟨function, expected⟩, found, _, checked, accepted⟩ := accepted
    have same : schema = expected := by simpa only [beq_iff_eq] using require_ok _ _ _ checked
    subst expected
    exact makeClosureWithValues_valid _ _ _ _ _ _ accepted typed (checked_constructor_contract _ _ _ _ contextTyped found)
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
    have middleTyped := temporary_valid _ _ _ _ temporaryOk typed
    have movedTyped := move_valid _ _ _ _ _ moveOk middleTyped
    have allocatedTyped := allocate_valid _
      { moved with nextCell := moved.nextCell + 1 }
      _ _ _ _ _ _ allocated movedTyped (by trivial)
    exact finishTemporary_valid _ _ _ _ finished allocatedTyped
  case cellGet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    exact scopedValue_valid _ _ _ _ accepted typed
  case cellSet =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, store, replaced, accepted⟩ := accepted
    have storeTyped := replace_valid _ _ _ _ _ replaced typed (by trivial)
    exact scopedValue_valid _ _ _ _ accepted storeTyped
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
    have middleTyped := temporary_valid _ _ _ _ temporaryOk typed
    have movedTyped := move_valid _ _ _ _ _ moveOk middleTyped
    have allocatedTyped := allocate_valid _ _ _ _ _ _ _ _ allocated movedTyped (by trivial)
    exact finishTemporary_valid _ _ _ _ finished allocatedTyped
  case unpack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, store, retired, accepted⟩ := accepted
    have storeTyped := retire_valid _ _ _ _ retired typed
    exact commitPure_valid _ _ _ _ _ _ accepted storeTyped
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
    have retiredTyped := retire_valid _ _ _ _ retireOk typed
    have middleTyped := temporary_valid _ _ _ _ temporaryOk retiredTyped
    have allocatedTyped := allocate_valid _ _ _ _ _ _ _ _ allocated middleTyped (by trivial)
    exact finishTemporary_valid _ _ _ _ finished allocatedTyped
  case resourcePack =>
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, accepted⟩ := accepted
    split at accepted <;> try contradiction
    simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨_, _, _, _, _, _, _, _, ⟨middle, owner⟩, temporaryOk, ⟨store, result⟩, allocated, finished⟩ := accepted
    have middleTyped := temporary_valid _ _ _ _ temporaryOk typed
    have allocatedTyped := allocate_valid _ _ _ _ _ _ _ _ allocated middleTyped (by trivial)
    exact finishTemporary_valid _ _ _ _ finished allocatedTyped
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
      have storeTyped := retire_valid _ _ _ _ retired typed
      exact scopedValue_valid _ _ _ _ accepted storeTyped
    · simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨_, _, _, _, accepted⟩ := accepted
      split at accepted <;> try contradiction
      simp only [except_bind_ok] at accepted
      obtain ⟨_, _, accepted⟩ := accepted
      exact scopedValue_valid _ _ _ _ accepted typed
    · contradiction
end ClosureContracts
end BoundaryV2.Profile.Source.Machine
