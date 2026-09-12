import BoundaryV2.PrimitiveProgress
import BoundaryV2.SourceFaultProgress
import BoundaryV2.SourceClosureProgress
import BoundaryV2.SourceInternalProgress

namespace BoundaryV2.Profile.Source.Machine
namespace NumericProgress

theorem current_token_free (heap : Heap) (value : Located) (free : ownedTokens value.value = []) :
    current heap value = true := by simp [current, free]

private theorem consume_empty (book : Custody.Book) (owner : Custody.Owner) : Custody.consume book [] owner = some book := by
  cases book
  simp [Custody.consume, Custody.without]

/-- Scalar computation has no custody transfer hidden behind its result.
This also applies to any token-free aggregate accepted by the pure evaluator. -/
theorem commitPure_token_free (machine : State) (opcode : Opcode) (operands : List Located) (result : SemanticValue)
    (scope : Scope) (scopeAt : machine.heap.scopes[machine.scope.value]? = some scope) (identity : scope.id = machine.scope)
    (inputsFree : ∀ value ∈ operands, ownedTokens value.value = []) (resultFree : ownedTokens result = []) :
    ∃ after, commitPure machine opcode operands result = .ok after := by
  let middle : State := { machine with heap := { machine.heap with
    scopes := machine.heap.scopes.set machine.scope.value { scope with nextOwner := scope.nextOwner + 1 } } }
  let owner := Custody.Owner.temporary machine.scope scope.nextOwner
  have temporaryOk : temporary machine = .ok (middle, owner) := by
    simp [temporary, scopeAt, identity, middle, owner, pure, Except.pure]
  have allCurrent : operands.all (current middle.heap) = true :=
    List.all_eq_true.mpr (fun value member => current_token_free _ _ (inputsFree value member))
  have moved := ClosureProgress.move_token_free middle.heap operands (fun _ => owner) inputsFree
  have tokens : (operands.flatMap fun value => ownedTokens value.value) = [] :=
    List.flatMap_eq_nil_iff.mpr inputsFree
  have middleScope : middle.heap.scopes[middle.scope.value]? = some { scope with nextOwner := scope.nextOwner + 1 } :=
    List.getElem?_set_self (List.getElem?_eq_some_iff.mp scopeAt).1
  have finished : ∃ after, finishTemporary middle ⟨result, owner⟩ = .ok after := by
    simp [finishTemporary, middleScope, pure, Except.pure]
  unfold commitPure
  simp only [temporaryOk, bind, Except.bind]
  split
  · simpa only [resultFree, List.isEmpty_nil, allCurrent, require, ↓reduceIte, Except.bind] using finished
  · simpa only [moved, fromOption, Except.bind, tokens, resultFree, List.all_nil, require, ↓reduceIte,
      List.filter_nil, consume_empty] using finished

/-- Every reachable arithmetic instruction can take its actual source tick.
The theorem includes overflow and division faults and assumes neither evaluator
success nor a successful custody check. -/
theorem reachable_arithmetic_progress (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (schema : SchemaId .source) (operation : Scalars.Arithmetic)
    (immediate : Nat) (failures : List (InstructionFailure .source)) (bindings : Environment) (operands : List Located)
    (executing : machine.control = .execute (.primitive schema (Primitives.Progress.arithmeticOpcode operation) immediate failures) bindings operands)
    (running : machine.status = .running) :
    ∃ after, tick machine context = .ok after ∧ after.state ≠ machine := by
  have typed : context.typingValid = true := by
    simpa only [Context.typingValid, Option.any_eq_true] using initial_checks_typing _ _ _ initialized
  have signature := OperandSchemas.reachable_primitive_signature _ _ _ _ _ initialized steps _ _ _ _ _ _ executing
  have admitted := OperandSchemas.signature_admits_nonresource _ _ _ _ _ _ typed signature
    (by cases operation <;> simp [Primitives.Progress.arithmeticOpcode])
    (by cases operation <;> simp [Primitives.Progress.arithmeticOpcode])
  have admittedValues : PrimitiveAdmission.operationType (Admission.primitiveContext context.source context.captures) ⟨0⟩
      ⟨Primitives.Progress.arithmeticOpcode operation, schema, immediate, failures⟩
      ((operands.map Located.value).map Profile.Value.schema) = true := by
    simpa only [OperandSchemas.schemas, List.map_map, Function.comp_def] using admitted
  have allShapes := initialized_execution_preserves_value_shapes _ _ _ _ _ initialized steps
  have inputs : ∀ value ∈ operands.map Located.value, ValueShape context.source.schemas value := by
    intro value member
    apply allShapes
    simp only [ValueInventory.state, executing, ValueInventory.control, List.mem_append]
    exact Or.inl (Or.inl (Or.inl (Or.inr member)))
  obtain ⟨left, right, source, kind, inputList, same, _, sourceAt, kindAt⟩ :=
    Primitives.Progress.admitted_arithmetic_inputs _ ⟨0⟩ operation schema immediate failures _ admittedValues
  have leftTyped := inputs left (by simp [inputList])
  have rightTyped := inputs right (by simp [inputList])
  obtain ⟨first, firstShape⟩ := Primitives.Progress.integer_value _ _ left source kind leftTyped sourceAt kindAt
  obtain ⟨second, secondShape⟩ := Primitives.Progress.integer_value _ _ right source kind rightTyped (same ▸ sourceAt) kindAt
  have inputFree : ∀ value ∈ operands.map Located.value, ownedTokens value = [] := by
    intro value member
    rw [inputList] at member
    simp only [List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl
    · rw [firstShape]; simp only [ownedTokens]
    · rw [secondShape]; simp only [ownedTokens]
  have free : ∀ value ∈ operands, ownedTokens value.value = [] :=
    fun value member => inputFree value.value (List.mem_map.mpr ⟨value, member, rfl⟩)
  have current : operands.all (Machine.current machine.heap) = true :=
    List.all_eq_true.mpr (fun value member => current_token_free _ _ (free value member))
  obtain ⟨result, evaluated⟩ := Primitives.Progress.admitted_arithmetic_succeeds
    (Admission.primitiveContext context.source context.captures) ⟨0⟩ context.executionConstants operation schema immediate failures
    (operands.map Located.value) (ReferenceOwnership context.source.schemas) inputs admittedValues
  change Primitives.evaluate context.source.schemas context.executionConstants
    (Primitives.Progress.arithmeticOpcode operation) schema immediate (operands.map Located.value) = .ok result at evaluated
  have outcome := Primitives.Progress.evaluated_arithmetic_outcome
    (Admission.primitiveContext context.source context.captures) context.executionConstants operation schema immediate
    (operands.map Located.value) result evaluated
  have finished : ∃ after, executePrimitive machine context = .ok after := by
    rcases outcome with ⟨number, rfl⟩ | ⟨fault, rfl, required⟩
    · obtain ⟨scope, scopeAt, identity⟩ :=
        (IdentitySupport.initialized_execution_has_current_records _ _ _ _ _ initialized steps).1
      obtain ⟨after, committed⟩ := commitPure_token_free machine _ operands (.scalar schema number)
        scope scopeAt identity free (by simp [ownedTokens])
      refine ⟨after, ?_⟩
      simpa only [executePrimitive, executing, current, require, ↓reduceIte, bind, Except.bind, evaluated] using committed
    · have required : fault ∈ PrimitiveAdmission.requiredFaults (Admission.primitiveContext context.source context.captures)
          (Primitives.Progress.arithmeticOpcode operation) schema (OperandSchemas.schemas operands) := by
        simpa only [OperandSchemas.schemas, List.map_map, Function.comp_def] using required
      obtain ⟨after, failed⟩ := FaultProgress.authored_failure_succeeds machine context schema _ immediate failures _ fault typed signature required
      refine ⟨after, ?_⟩
      simpa only [executePrimitive, executing, current, require, ↓reduceIte, bind, Except.bind, evaluated] using failed
  obtain ⟨after, executed⟩ := finished
  have tickOk : tick machine context = .ok after := by simpa only [tick, running, tickRunning, executing] using executed
  exact ⟨after, tickOk, InternalProgress.running_tick_changes _ _ _ running tickOk⟩


theorem reachable_nonresource_primitive_data (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (schema : SchemaId .source) (opcode : Opcode)
    (immediate : Nat) (failures : List (InstructionFailure .source)) (bindings : Environment) (operands : List Located)
    (executing : machine.control = .execute (.primitive schema opcode immediate failures) bindings operands)
    (notPack : opcode ≠ .resourcePack) (notUnpack : opcode ≠ .resourceUnpack) :
    PrimitiveAdmission.operationType (Admission.primitiveContext context.source context.captures) ⟨0⟩
      ⟨opcode, schema, immediate, failures⟩ ((operands.map Located.value).map Profile.Value.schema) = true ∧
      (∀ value ∈ operands.map Located.value, ValueShape context.source.schemas value) := by
  have typed : context.typingValid = true := by
    simpa only [Context.typingValid, Option.any_eq_true] using initial_checks_typing _ _ _ initialized
  have signature := OperandSchemas.reachable_primitive_signature _ _ _ _ _ initialized steps _ _ _ _ _ _ executing
  have admitted := OperandSchemas.signature_admits_nonresource _ _ _ _ _ _ typed signature notPack notUnpack
  refine ⟨?_, ?_⟩
  · simpa only [OperandSchemas.schemas, List.map_map, Function.comp_def] using admitted
  · have allShapes := initialized_execution_preserves_value_shapes _ _ _ _ _ initialized steps
    intro value member
    apply allShapes
    simp only [ValueInventory.state, executing, ValueInventory.control, List.mem_append]
    exact Or.inl (Or.inl (Or.inl (Or.inr member)))

theorem reachable_token_free_value_tick (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (schema : SchemaId .source) (opcode : Opcode)
    (immediate : Nat) (failures : List (InstructionFailure .source)) (bindings : Environment) (operands : List Located)
    (executing : machine.control = .execute (.primitive schema opcode immediate failures) bindings operands)
    (running : machine.status = .running) (result : SemanticValue)
    (inputsFree : ∀ value ∈ operands.map Located.value, ownedTokens value = [])
    (resultFree : ownedTokens result = [])
    (evaluated : Primitives.evaluate context.source.schemas context.executionConstants opcode schema immediate
      (operands.map Located.value) = .ok (.value result)) :
    ∃ after, tick machine context = .ok after ∧ after.state ≠ machine := by
  have free : ∀ value ∈ operands, ownedTokens value.value = [] :=
    fun value member => inputsFree value.value (List.mem_map.mpr ⟨value, member, rfl⟩)
  have current : operands.all (Machine.current machine.heap) = true :=
    List.all_eq_true.mpr (fun value member => current_token_free _ _ (free value member))
  obtain ⟨scope, scopeAt, identity⟩ :=
    (IdentitySupport.initialized_execution_has_current_records _ _ _ _ _ initialized steps).1
  obtain ⟨after, committed⟩ := commitPure_token_free machine opcode operands result scope scopeAt identity free resultFree
  have tickOk : tick machine context = .ok after := by
    simpa only [tick, running, tickRunning, executePrimitive, executing, current, require, ↓reduceIte,
      bind, Except.bind, evaluated] using committed
  exact ⟨after, tickOk, InternalProgress.running_tick_changes _ _ _ running tickOk⟩

/-- All four bitwise source operations progress from initialization and an
arbitrary actual execution prefix, including unary complement. -/
theorem reachable_bitwise_progress (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (schema : SchemaId .source) (operation : Scalars.Bitwise)
    (immediate : Nat) (failures : List (InstructionFailure .source)) (bindings : Environment) (operands : List Located)
    (executing : machine.control = .execute (.primitive schema (Primitives.Progress.bitwiseOpcode operation) immediate failures) bindings operands)
    (running : machine.status = .running) :
    ∃ after, tick machine context = .ok after ∧ after.state ≠ machine := by
  obtain ⟨admitted, inputs⟩ := reachable_nonresource_primitive_data _ _ _ _ _ initialized steps _ _ _ _ _ _ executing
    (by cases operation <;> simp [Primitives.Progress.bitwiseOpcode])
    (by cases operation <;> simp [Primitives.Progress.bitwiseOpcode])
  by_cases unary : operation = .not
  · subst operation
    obtain ⟨input, source, kind, inputList, _, sourceAt, kindAt⟩ :=
      Primitives.Progress.admitted_complement_input _ ⟨0⟩ schema immediate failures _ admitted
    obtain ⟨number, shape⟩ := Primitives.Progress.integer_value _ _ input source kind
      (inputs input (by simp [inputList])) sourceAt kindAt
    have free : ∀ value ∈ operands.map Located.value, ownedTokens value = [] := by
      intro value member
      rw [inputList] at member
      have same : value = input := by simpa only [List.mem_singleton] using member
      subst value
      rw [shape]; simp only [ownedTokens]
    obtain ⟨number, evaluated⟩ := Primitives.Progress.admitted_complement_succeeds
      (Admission.primitiveContext context.source context.captures) ⟨0⟩ context.executionConstants schema immediate failures
      (operands.map Located.value) (ReferenceOwnership context.source.schemas) inputs admitted
    exact reachable_token_free_value_tick _ _ _ _ _ initialized steps _ _ _ _ _ _ executing running
      (.scalar schema number) free (by simp [ownedTokens]) evaluated
  · obtain ⟨left, right, source, kind, inputList, same, _, sourceAt, kindAt⟩ :=
      Primitives.Progress.admitted_bitwise_inputs _ ⟨0⟩ operation schema immediate failures _ unary admitted
    obtain ⟨first, firstShape⟩ := Primitives.Progress.integer_value _ _ left source kind
      (inputs left (by simp [inputList])) sourceAt kindAt
    obtain ⟨second, secondShape⟩ := Primitives.Progress.integer_value _ _ right source kind
      (inputs right (by simp [inputList])) (same ▸ sourceAt) kindAt
    have free : ∀ value ∈ operands.map Located.value, ownedTokens value = [] := by
      intro value member
      rw [inputList] at member
      simp only [List.mem_cons, List.not_mem_nil, or_false] at member
      rcases member with rfl | rfl
      · rw [firstShape]; simp only [ownedTokens]
      · rw [secondShape]; simp only [ownedTokens]
    obtain ⟨number, evaluated⟩ := Primitives.Progress.admitted_bitwise_succeeds
      (Admission.primitiveContext context.source context.captures) ⟨0⟩ context.executionConstants operation schema immediate failures
      (operands.map Located.value) (ReferenceOwnership context.source.schemas) inputs unary admitted
    exact reachable_token_free_value_tick _ _ _ _ _ initialized steps _ _ _ _ _ _ executing running
      (.scalar schema number) free (by simp [ownedTokens]) evaluated


/-- Reachable equality and ordering cover admitted integer comparisons and
Boolean equality, without assuming evaluator or custody success. -/
theorem reachable_comparison_progress (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (schema : SchemaId .source) (less : Bool)
    (immediate : Nat) (failures : List (InstructionFailure .source)) (bindings : Environment) (operands : List Located)
    (executing : machine.control = .execute (.primitive schema (Primitives.Progress.comparisonOpcode less) immediate failures) bindings operands)
    (running : machine.status = .running) :
    ∃ after, tick machine context = .ok after ∧ after.state ≠ machine := by
  obtain ⟨admitted, inputs⟩ := reachable_nonresource_primitive_data _ _ _ _ _ initialized steps _ _ _ _ _ _ executing
    (by cases less <;> simp [Primitives.Progress.comparisonOpcode])
    (by cases less <;> simp [Primitives.Progress.comparisonOpcode])
  obtain ⟨left, right, source, inputList, same, _, sourceAt, allowed⟩ :=
    Primitives.Progress.admitted_comparison_inputs _ ⟨0⟩ less schema immediate failures _ admitted
  obtain ⟨first, firstShape, _⟩ := Primitives.Progress.comparable_value _ _ left source less
    (inputs left (by simp [inputList])) sourceAt allowed
  obtain ⟨second, secondShape, _⟩ := Primitives.Progress.comparable_value _ _ right source less
    (inputs right (by simp [inputList])) (same ▸ sourceAt) allowed
  have free : ∀ value ∈ operands.map Located.value, ownedTokens value = [] := by
    intro value member
    rw [inputList] at member
    simp only [List.mem_cons, List.not_mem_nil, or_false] at member
    rcases member with rfl | rfl
    · rw [firstShape]; simp only [ownedTokens]
    · rw [secondShape]; simp only [ownedTokens]
  obtain ⟨number, evaluated⟩ := Primitives.Progress.admitted_comparison_succeeds
    (Admission.primitiveContext context.source context.captures) ⟨0⟩ context.executionConstants less schema immediate failures
    (operands.map Located.value) (ReferenceOwnership context.source.schemas) inputs admitted
  exact reachable_token_free_value_tick _ _ _ _ _ initialized steps _ _ _ _ _ _ executing running
    (.scalar schema number) free (by simp [ownedTokens]) evaluated

theorem reachable_boolean_progress (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (schema : SchemaId .source)
    (immediate : Nat) (failures : List (InstructionFailure .source)) (bindings : Environment) (operands : List Located)
    (executing : machine.control = .execute (.primitive schema .booleanNot immediate failures) bindings operands)
    (running : machine.status = .running) :
    ∃ after, tick machine context = .ok after ∧ after.state ≠ machine := by
  obtain ⟨admitted, inputs⟩ := reachable_nonresource_primitive_data _ _ _ _ _ initialized steps _ _ _ _ _ _ executing (by decide) (by decide)
  obtain ⟨input, inputList, _, sourceAt⟩ := Primitives.Progress.admitted_boolean_input _ ⟨0⟩ schema immediate failures _ admitted
  obtain ⟨number, shape, _⟩ := Primitives.Progress.boolean_value _ _ input (inputs input (by simp [inputList])) sourceAt
  have free : ∀ value ∈ operands.map Located.value, ownedTokens value = [] := by
    intro value member
    rw [inputList] at member
    have same : value = input := by simpa only [List.mem_singleton] using member
    subst value
    rw [shape]; simp only [ownedTokens]
  obtain ⟨number, evaluated⟩ := Primitives.Progress.admitted_boolean_succeeds
    (Admission.primitiveContext context.source context.captures) ⟨0⟩ context.executionConstants schema immediate failures
    (operands.map Located.value) (ReferenceOwnership context.source.schemas) inputs admitted
  exact reachable_token_free_value_tick _ _ _ _ _ initialized steps _ _ _ _ _ _ executing running
    (.scalar schema number) free (by simp [ownedTokens]) evaluated


/-- Every admitted integer conversion advances. Empty failure interfaces on
widening conversions and authored overflow on narrowing conversions are both
justified from actual reachable operands and the checked source declarations. -/
theorem reachable_conversion_progress (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (schema : SchemaId .source)
    (immediate : Nat) (failures : List (InstructionFailure .source)) (bindings : Environment) (operands : List Located)
    (executing : machine.control = .execute (.primitive schema .integerConvert immediate failures) bindings operands)
    (running : machine.status = .running) :
    ∃ after, tick machine context = .ok after ∧ after.state ≠ machine := by
  obtain ⟨admitted, inputs⟩ := reachable_nonresource_primitive_data _ _ _ _ _ initialized steps _ _ _ _ _ _ executing (by decide) (by decide)
  obtain ⟨input, source, kind, _, _, inputList, sourceAt, kindAt, _, _⟩ :=
    Primitives.Progress.admitted_conversion_input _ ⟨0⟩ schema immediate failures _ admitted
  obtain ⟨number, shape⟩ := Primitives.Progress.integer_value _ _ input source kind (inputs input (by simp [inputList])) sourceAt kindAt
  have free : ∀ value ∈ operands.map Located.value, ownedTokens value = [] := by
    intro value member
    rw [inputList] at member
    have same : value = input := by simpa only [List.mem_singleton] using member
    subst value
    rw [shape]; simp only [ownedTokens]
  obtain ⟨result, evaluated, outcome⟩ := Primitives.Progress.admitted_conversion_succeeds
    (Admission.primitiveContext context.source context.captures) ⟨0⟩ context.executionConstants schema immediate failures
    (operands.map Located.value) (ReferenceOwnership context.source.schemas) inputs admitted
  change Primitives.evaluate context.source.schemas context.executionConstants .integerConvert schema immediate
    (operands.map Located.value) = .ok result at evaluated
  rcases outcome with ⟨number, rfl⟩ | ⟨fault, rfl, required⟩
  · exact reachable_token_free_value_tick _ _ _ _ _ initialized steps _ _ _ _ _ _ executing running
      (.scalar schema number) free (by simp [ownedTokens]) evaluated
  · have typed : context.typingValid = true := by
      simpa only [Context.typingValid, Option.any_eq_true] using initial_checks_typing _ _ _ initialized
    have signature := OperandSchemas.reachable_primitive_signature _ _ _ _ _ initialized steps _ _ _ _ _ _ executing
    have required : fault ∈ PrimitiveAdmission.requiredFaults (Admission.primitiveContext context.source context.captures)
        .integerConvert schema (OperandSchemas.schemas operands) := by
      simpa only [OperandSchemas.schemas, List.map_map, Function.comp_def] using required
    obtain ⟨after, failed⟩ := FaultProgress.authored_failure_succeeds machine context schema .integerConvert immediate failures _ fault typed signature required
    have current : operands.all (Machine.current machine.heap) = true := by
      apply List.all_eq_true.mpr
      intro value member
      exact current_token_free _ _ (free value.value (List.mem_map.mpr ⟨value, member, rfl⟩))
    have tickOk : tick machine context = .ok after := by
      simpa only [tick, running, tickRunning, executePrimitive, executing, current, require, ↓reduceIte,
        bind, Except.bind, evaluated] using failed
    exact ⟨after, tickOk, InternalProgress.running_tick_changes _ _ _ running tickOk⟩


theorem reachable_enumeration_progress (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (schema : SchemaId .source)
    (immediate : Nat) (failures : List (InstructionFailure .source)) (bindings : Environment) (operands : List Located)
    (executing : machine.control = .execute (.primitive schema .enumTag immediate failures) bindings operands)
    (running : machine.status = .running) :
    ∃ after, tick machine context = .ok after ∧ after.state ≠ machine := by
  obtain ⟨admitted, inputs⟩ := reachable_nonresource_primitive_data _ _ _ _ _ initialized steps _ _ _ _ _ _ executing (by decide) (by decide)
  obtain ⟨input, tags, inputList, sourceAt, _⟩ := Primitives.Progress.admitted_enumeration_input _ ⟨0⟩ schema immediate failures _ admitted
  obtain ⟨number, shape, _⟩ := Primitives.Progress.enumeration_value _ _ input tags (inputs input (by simp [inputList])) sourceAt
  have free : ∀ value ∈ operands.map Located.value, ownedTokens value = [] := by
    intro value member
    rw [inputList] at member
    have same : value = input := by simpa only [List.mem_singleton] using member
    subst value
    rw [shape]; simp only [ownedTokens]
  obtain ⟨number, evaluated⟩ := Primitives.Progress.admitted_enumeration_succeeds
    (Admission.primitiveContext context.source context.captures) ⟨0⟩ context.executionConstants schema immediate failures
    (operands.map Located.value) (ReferenceOwnership context.source.schemas) inputs admitted
  exact reachable_token_free_value_tick _ _ _ _ _ initialized steps _ _ _ _ _ _ executing running
    (.scalar schema number) free (by simp [ownedTokens]) evaluated

end NumericProgress
end BoundaryV2.Profile.Source.Machine
