import BoundaryV2.SourceReferenceSafetyHeap

namespace BoundaryV2.Profile.Source.Machine
namespace ReferenceSafety
open ReferenceContracts

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem createScope_reference_facts (machine : State) (context : Context) (invocation : InvocationId)
    (parent : Option LexicalScopeId) (vars : List VariableId) (values : List Located)
    (bindings : Environment) (after : State) (entered : Environment)
    (accepted : createScope machine context invocation parent vars values bindings = .ok (after, entered)) :
    (∀ value, ValueGood schemas machine.heap value → ValueGood schemas after.heap value) ∧
    (machine.heap.CustodyLive → after.heap.CustodyLive) := by
  simp only [createScope, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · cases accepted; exact ⟨fun _ good => good, id⟩
  · simp only [except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, heap, moved, equal⟩ := accepted
    cases equal
    exact ⟨fun value good => fields_value heap _ _ rfl rfl rfl (move_value machine.heap heap _ _ _ moved good),
      fun live => moveValues_preserves_live_objects _ heap _ _ moved live⟩

theorem invokeFunction_reference_facts (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction machine context function bindings arguments = .ok after) :
    (∀ value, ValueGood schemas machine.heap value → ValueGood schemas after.state.heap value) ∧
    (machine.heap.CustodyLive → after.state.heap.CustodyLive) := by
  simp only [invokeFunction, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨definition, _, body, _, captured, _, _, _, _, _, ⟨middle, entered⟩, scopeOk, rfl⟩ := accepted
  have facts := createScope_reference_facts (schemas := schemas) _ _ _ _ _ _ _ _ _ scopeOk
  exact ⟨fun value good => fields_value _ _ _ rfl rfl rfl (facts.1 value good), facts.2⟩

theorem invokeFunction_valid (machine : State) (context : Context) (function : FunctionId .source)
    (bindings : Environment) (arguments : List Located) (after : Transition)
    (accepted : invokeFunction machine context function bindings arguments = .ok after)
    (good : Valid context.source.schemas machine)
    (outer : ∀ binding ∈ bindings, ValueGood context.source.schemas machine.heap binding.located.value)
    (inputs : ∀ value ∈ arguments, ValueGood context.source.schemas machine.heap value.value) :
    Valid context.source.schemas after.state := by
  have facts := invokeFunction_reference_facts (schemas := context.source.schemas) _ _ _ _ _ _ accepted
  exact ⟨ValueInventory.invokeFunction_preserves_all _ _ _ _ _ _ accepted _
    (fun value member => facts.1 value (good.values value member))
    (fun binding member => facts.1 _ (outer binding member))
    (fun value member => facts.1 _ (inputs value member)), facts.2 good.live⟩

theorem applyClosure_valid (machine : State) (context : Context) (closure : Located)
    (arguments : List Located) (after : Transition)
    (accepted : applyClosure machine context closure arguments = .ok after)
    (good : Valid context.source.schemas machine)
    (modes : ValueInventory.All (ValueModes context.source.schemas) machine)
    (closureGood : ValueGood context.source.schemas machine.heap closure.value)
    (closureModes : ValueModes context.source.schemas closure.value)
    (inputs : ∀ value ∈ arguments, ValueGood context.source.schemas machine.heap value.value)
    (inputModes : ∀ value ∈ arguments, ValueModes context.source.schemas value.value) :
    Valid context.source.schemas after.state := by
  simp only [applyClosure, bind, except_bind_ok] at accepted
  obtain ⟨⟨node, stored⟩, looked, accepted⟩ := accepted
  cases stored <;> try contradiction
  rename_i schema function bindings
  simp only at accepted
  have outerGood : ∀ binding ∈ bindings, ValueGood context.source.schemas machine.heap binding.located.value := by
    intro binding member
    apply lookup_good _ _ _ _ looked good
    simp only [ValueInventory.object, ValueInventory.environment, List.mem_map]
    exact ⟨binding, member, rfl⟩
  have outerModes : ∀ binding ∈ bindings, ValueModes context.source.schemas binding.located.value := by
    intro binding member
    apply ValueInventory.lookupObject_preserves_all _ _ _ _ looked _ modes
    simp only [ValueInventory.object, ValueInventory.environment, List.mem_map]
    exact ⟨binding, member, rfl⟩
  split at accepted <;> try contradiction
  · simp only [except_bind_ok, fromOption_ok] at accepted
    obtain ⟨heap, retired, invoked⟩ := accepted
    have shape := retirement_shape _ _ _ retired closureModes
    exact invokeFunction_valid _ _ _ _ _ _ invoked (retirement_valid _ _ _ retired good shape closureGood modes)
      (fun binding member => retirement_value _ _ _ _ retired good.live shape closureGood
        (outerModes binding member) (outerGood binding member))
      (fun value member => retirement_value _ _ _ _ retired good.live shape closureGood
        (inputModes value member) (inputs value member))
  · simp only [pure, Except.pure, Except.bind] at accepted
    exact invokeFunction_valid _ _ _ _ _ _ accepted good outerGood inputs

theorem authoredFailure_valid (machine : State) (context : Context)
    (failures : List (InstructionFailure .source)) (fault : Fault) (after : Transition)
    (accepted : authoredFailure machine context failures fault = .ok after)
    (good : Valid context.source.schemas machine)
    (constantsGood : ∀ value ∈ context.executionConstants, ValueGood context.source.schemas machine.heap value) :
    Valid context.source.schemas after.state := by
  have values := ValueInventory.authoredFailure_preserves_all _ _ _ _ _ accepted _ good.values constantsGood
  simp only [authoredFailure, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
  exact ⟨values, good.live⟩

theorem executePrimitive_valid (machine : State) (context : Context) (after : Transition)
    (accepted : executePrimitive machine context = .ok after) (contextTyped : context.typingValid = true)
    (good : Valid context.source.schemas machine)
    (modes : ValueInventory.All (ValueModes context.source.schemas) machine) :
    Valid context.source.schemas after.state := by
  unfold executePrimitive at accepted
  split at accepted <;> try contradiction
  rename_i schema opcode immediate failures bindings operands executing
  have members : ∀ value ∈ operands, value.value ∈ ValueInventory.state machine := by
    intro value member
    simp only [ValueInventory.state, executing, ValueInventory.control, List.mem_append, List.mem_map]
    exact Or.inl (Or.inl (Or.inl (Or.inr ⟨value, member, rfl⟩)))
  have inputs := fun value member => good.values value.value (members value member)
  have inputModes := fun value member => modes value.value (members value member)
  have constantsGood : ∀ value ∈ context.executionConstants, ValueGood context.source.schemas machine.heap value := by
    intro value member
    have free := checked_execution_constants_have_no_handles context contextTyped value member
    exact ⟨reference_free_valid _ _ _ free.1, token_free_aligned _ _ free.2, by simp [ValueTokensBounded, free.2]⟩
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · contradiction
  · exact authoredFailure_valid _ _ _ _ _ accepted good constantsGood
  · rename_i value evaluated
    have valueGood := primitive_value context.source.schemas machine.heap context.executionConstants
      opcode schema immediate (operands.map Located.value) value constantsGood (by
        intro child member
        obtain ⟨original, belongs, rfl⟩ := List.mem_map.mp member
        exact inputs original belongs) evaluated
    exact commitPure_valid _ _ _ _ _ accepted good valueGood
  · exact heapPrimitive_valid _ _ _ _ _ _ _ accepted good modes inputs inputModes

end ReferenceSafety
end BoundaryV2.Profile.Source.Machine
