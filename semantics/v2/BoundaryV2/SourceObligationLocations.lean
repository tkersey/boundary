import BoundaryV2.SourceCustodyExecution

namespace BoundaryV2.Profile.Source.Machine
namespace ObligationLocations

/-- Pending protection and running cleanup have distinct physical frames. -/
structure Entry where
  id : ObligationId
  invocation : Option InvocationId
  deriving DecidableEq

def record (obligation : Cleanup.Obligation .source) : List Entry := match obligation.phase with
  | .pending => [⟨obligation.id, none⟩]
  | .running invocation => [⟨obligation.id, some invocation⟩]
  | .completed | .failed _ => []

def frame : Frame → List Entry
  | .protection id => [⟨id, none⟩]
  | .cleanupReturn id invocation _ _ => [⟨id, some invocation⟩]
  | _ => []

def object : Object → List Entry
  | .oneShot saved | .multiTemplate saved => saved.frames.flatMap frame
  | _ => []

def fields (machine : State) : List Entry :=
  machine.stack.flatMap frame ++ machine.heap.objects.flatMap (fun entry => entry.toList.flatMap object)

def expected (heap : Heap) : List Entry := heap.obligations.flatMap record

def Valid (machine : State) : Prop := (fields machine).Perm (expected machine.heap)

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem initial_valid (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) : Valid machine := by
  simp only [initial, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ := accepted
  exact .refl []

theorem same_storage_valid (machine : State) (heap : Heap) (valid : Valid machine)
    (objects : heap.objects = machine.heap.objects) (obligations : heap.obligations = machine.heap.obligations) :
    Valid {machine with heap := heap} := by
  simpa only [Valid, fields, expected, objects, obligations] using valid

theorem stack_valid (machine : State) (stack : List Frame) (valid : Valid machine)
    (same : stack.flatMap frame = machine.stack.flatMap frame) : Valid {machine with stack := stack} := by
  simpa only [Valid, fields, same] using valid

theorem temporary_parts (machine after : State) (owner : Custody.Owner)
    (accepted : temporary machine = .ok (after, owner)) :
    fields after = fields machine ∧ after.heap.obligations = machine.heap.obligations := by
  unfold temporary at accepted
  split at accepted <;> try contradiction
  split at accepted <;> try contradiction
  cases accepted
  exact ⟨rfl, rfl⟩

theorem temporary_valid (machine after : State) (owner : Custody.Owner)
    (accepted : temporary machine = .ok (after, owner)) (valid : Valid machine) : Valid after := by
  obtain ⟨same, obligations⟩ := temporary_parts _ _ _ accepted
  simpa only [Valid, same, expected, obligations] using valid

theorem finishTemporary_valid (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) (valid : Valid machine) : Valid after.state := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  cases accepted
  exact valid

theorem scopedValue_valid (machine : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue machine value = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, reserved, finished⟩ := accepted
  exact finishTemporary_valid _ _ _ finished (temporary_valid _ _ _ reserved valid)

theorem move_parts (before after : Heap) (values : List Located) (receiver : Nat → Custody.Owner)
    (accepted : moveValues before values receiver = some after) :
    after.objects = before.objects ∧ after.obligations = before.obligations := by
  simp only [moveValues, bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  exact ⟨rfl, rfl⟩

theorem move_valid (machine : State) (heap : Heap) (values : List Located) (receiver : Nat → Custody.Owner)
    (accepted : moveValues machine.heap values receiver = some heap) (valid : Valid machine) :
    Valid {machine with heap := heap} :=
  same_storage_valid _ _ valid (move_parts _ _ _ _ accepted).1 (move_parts _ _ _ _ accepted).2

theorem consume_parts (before after : Heap) (value : Located) (accepted : consumeValue before value = some after) :
    after.objects = before.objects ∧ after.obligations = before.obligations := by
  simp only [consumeValue, bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨_, _, rfl⟩ := accepted
  exact ⟨rfl, rfl⟩

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
      (fields {machine with heap := {machine.heap with objects := machine.heap.objects.set node.value none}} ++ object stored) := by
  have position : machine.heap.objects[node.value]? = some (some stored) := by
    simp only [Heap.lookup, Option.bind_eq_some_iff] at found
    obtain ⟨entry, atEntry, isStored⟩ := found
    cases entry <;> try contradiction
    cases isStored
    exact atEntry
  have partition := flatMap_remove_perm machine.heap.objects node.value (some stored) none
    (fun entry => entry.toList.flatMap object) position rfl
  simpa only [fields, Option.toList_some, List.flatMap_singleton, List.append_assoc] using
    List.Perm.append_left (machine.stack.flatMap frame) partition

theorem retire_parts (machine : State) (heap : Heap) (value : Located) (node : NodeId) (stored : Object)
    (looked : lookupObject machine value = .ok (node, stored))
    (accepted : retireObject machine.heap value = some heap) :
    (fields machine).Perm (fields {machine with heap := heap} ++ object stored) ∧
      heap.obligations = machine.heap.obligations := by
  obtain ⟨⟨schema, token, reference⟩, found⟩ := CellStability.lookupObject_reference _ _ _ _ looked
  unfold retireObject at accepted
  rw [reference] at accepted
  cases token <;> try contradiction
  simp only [bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨_, _, middle, consumed, rfl⟩ := accepted
  have same := consume_parts _ _ _ consumed
  exact ⟨by simpa only [fields, same.1] using erase_object_partition machine node stored found, same.2⟩

theorem retire_empty_valid (machine : State) (heap : Heap) (value : Located) (node : NodeId) (stored : Object)
    (looked : lookupObject machine value = .ok (node, stored))
    (accepted : retireObject machine.heap value = some heap) (valid : Valid machine) (empty : object stored = []) :
    Valid {machine with heap := heap} := by
  obtain ⟨partition, obligations⟩ := retire_parts _ _ _ _ _ looked accepted
  have partition : (fields machine).Perm (fields {machine with heap := heap}) := by simpa only [empty, List.append_nil] using partition
  simpa only [Valid, expected, obligations] using partition.symm.trans valid

theorem allocate_parts (machine : State) (heap : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject machine.heap schema stored owner exclusive = some (heap, value)) :
    fields {machine with heap := heap} = fields machine ++ object stored ∧
      heap.obligations = machine.heap.obligations := by
  cases exclusive <;> simp [allocateObject, Option.bind_eq_some_iff] at accepted
  · obtain ⟨rfl, _⟩ := accepted
    exact ⟨by simp [fields, List.flatMap_append, List.append_assoc], rfl⟩
  · obtain ⟨_, _, rfl, _⟩ := accepted
    exact ⟨by simp [fields, List.flatMap_append, List.append_assoc], rfl⟩

theorem allocate_empty_valid (machine : State) (heap : Heap) (schema : SchemaId .source) (stored : Object)
    (owner : Custody.Owner) (exclusive : Bool) (value : Located)
    (accepted : allocateObject machine.heap schema stored owner exclusive = some (heap, value)) (valid : Valid machine)
    (empty : object stored = []) : Valid {machine with heap := heap} := by
  obtain ⟨same, obligations⟩ := allocate_parts _ _ _ _ _ _ _ accepted
  simpa only [Valid, same, empty, List.append_nil, expected, obligations] using valid

private theorem flatMap_set_same (values : List α) (index : Nat) (replacement original : α)
    (f : α → List β) (found : values[index]? = some original) (same : f replacement = f original) :
    (values.set index replacement).flatMap f = values.flatMap f := by
  induction values generalizing index with
  | nil => simp at found
  | cons value values induction =>
    cases index with
    | zero => cases found; simp [same]
    | succ index => simpa only [List.set_cons_succ, List.flatMap_cons] using congrArg (f value ++ ·) (induction index found)

theorem replace_empty_valid (machine : State) (heap : Heap) (node : NodeId) (before after : Object)
    (found : machine.heap.lookup node = some before)
    (accepted : replaceObject machine.heap node after = some heap) (valid : Valid machine)
    (emptyBefore : object before = []) (emptyAfter : object after = []) : Valid {machine with heap := heap} := by
  have position : machine.heap.objects[node.value]? = some (some before) := by
    simp only [Heap.lookup, Option.bind_eq_some_iff] at found
    obtain ⟨entry, atEntry, isStored⟩ := found
    cases entry <;> try contradiction
    cases isStored
    exact atEntry
  unfold replaceObject at accepted
  split at accepted <;> try contradiction
  cases accepted
  have same := flatMap_set_same machine.heap.objects node.value (some after) (some before)
    (fun entry => entry.toList.flatMap object) position (by simp [emptyBefore, emptyAfter])
  simpa only [Valid, fields, expected, same] using valid

theorem createScope_valid (machine : State) (context : Context) (invocation : InvocationId)
    (parent : Option LexicalScopeId) (vars : List VariableId) (values : List Located)
    (bindings : Environment) (after : State × Environment)
    (accepted : createScope machine context invocation parent vars values bindings = .ok after) (valid : Valid machine) :
    Valid after.1 ∧ after.1.stack = machine.stack := by
  simp only [createScope, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · cases accepted; exact ⟨valid, rfl⟩
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, heap, moved, rfl⟩ := accepted
    have next := move_valid machine heap values _ moved valid
    exact ⟨next, rfl⟩

theorem invokeFunction_valid (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction machine context function bindings arguments = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [invokeFunction, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨definition, _, body, _, captured, _, _, _, _, _, ⟨middle, entered⟩, created, rfl⟩ := accepted
  have next := createScope_valid _ _ _ _ _ _ _ _ created valid
  have stackSame : middle.stack = machine.stack := next.2
  simpa only [Valid, fields, frame, expected, List.flatMap_cons, List.nil_append, stackSame] using next.1

theorem applyClosure_valid (machine : State) (context : Context) (closure : Located)
    (arguments : List Located) (after : Transition)
    (accepted : applyClosure machine context closure arguments = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [applyClosure, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
  cases stored <;> try contradiction
  case closure schema function bindings =>
    obtain ⟨⟨rootSchema, token, reference⟩, _⟩ := CellStability.lookupObject_reference _ _ _ _ looked
    rw [reference] at accepted
    cases token with
    | none =>
      simp only [pure, Except.pure, Except.bind] at accepted
      exact invokeFunction_valid _ _ _ _ _ _ accepted valid
    | some token =>
      simp only [except_bind_ok, fromOption_ok] at accepted
      obtain ⟨heap, retired, invoked⟩ := accepted
      exact invokeFunction_valid _ _ _ _ _ _ invoked (retire_empty_valid _ _ _ _ _ looked retired valid rfl)

theorem makeClosureWithValues_valid (machine : State) (context : Context)
    (schema : SchemaId .source) (function : FunctionId .source) (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues machine context schema function values = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, ⟨middle, owner⟩, reserved, moved, movedAt, ⟨heap, result⟩, allocated, finished⟩ := accepted
  have next := temporary_valid _ _ _ reserved valid
  have transferred := move_valid _ _ _ _ movedAt next
  have created := allocate_empty_valid _ _ _ _ _ _ _ allocated transferred rfl
  exact finishTemporary_valid _ _ _ finished created

theorem makeClosure_valid (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (bindings : Environment) (after : Transition)
    (accepted : makeClosure machine context schema function bindings = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [makeClosure, bind, except_bind_ok] at accepted
  obtain ⟨_, _, created⟩ := accepted
  exact makeClosureWithValues_valid _ _ _ _ _ _ created valid

theorem commitPure_valid (machine : State) (opcode : Opcode) (operands : List Located)
    (result : SemanticValue) (after : Transition)
    (accepted : commitPure machine opcode operands result = .ok after) (valid : Valid machine) : Valid after.state := by
  simp only [commitPure, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, reserved, accepted⟩ := accepted
  have next := temporary_valid _ _ _ reserved valid
  split at accepted
  · simp only [except_bind_ok] at accepted
    obtain ⟨_, _, _, _, finished⟩ := accepted
    exact finishTemporary_valid _ _ _ finished next
  · simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨heap, moved, _, _, custody, _, finished⟩ := accepted
    have transferred := move_valid _ _ _ _ moved next
    exact finishTemporary_valid _ _ _ finished transferred

end ObligationLocations
end BoundaryV2.Profile.Source.Machine
