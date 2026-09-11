import BoundaryV2.SourceEffectTypes
import BoundaryV2.PrimitiveResultSchema

namespace BoundaryV2.Profile.Source.Machine

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

theorem finishTemporary_delivers (machine : State) (value : Located) (after : Transition)
    (accepted : finishTemporary machine value = .ok after) : after.state.control = .delivered value := by
  unfold finishTemporary at accepted
  split at accepted <;> try contradiction
  cases accepted
  rfl

theorem scopedValue_delivers (machine : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue machine value = .ok after) :
    ∃ located, after.state.control = .delivered located ∧ located.value = value := by
  simp only [scopedValue, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, _, finished⟩ := accepted
  exact ⟨_, finishTemporary_delivers _ _ _ finished, rfl⟩

theorem scopedValue_result_schema (machine : State) (value : SemanticValue) (after : Transition)
    (accepted : scopedValue machine value = .ok after) (result : Located)
    (delivered : after.state.control = .delivered result) : result.value.schema = value.schema := by
  obtain ⟨located, control, same⟩ := scopedValue_delivers _ _ _ accepted
  rw [control] at delivered
  cases delivered
  rw [same]

theorem commitPure_delivers (machine : State) (opcode : Opcode) (operands : List Located)
    (value : SemanticValue) (after : Transition) (accepted : commitPure machine opcode operands value = .ok after) :
    ∃ located, after.state.control = .delivered located ∧ located.value = value := by
  simp only [commitPure, bind, except_bind_ok] at accepted
  obtain ⟨⟨middle, owner⟩, _, accepted⟩ := accepted
  split at accepted <;> simp only [except_bind_ok, fromOption_ok] at accepted
  · obtain ⟨_, _, _, _, finished⟩ := accepted
    exact ⟨_, finishTemporary_delivers _ _ _ finished, rfl⟩
  · obtain ⟨_, _, _, _, _, _, finished⟩ := accepted
    exact ⟨_, finishTemporary_delivers _ _ _ finished, rfl⟩

theorem commitPure_result_schema (machine : State) (opcode : Opcode) (operands : List Located)
    (value : SemanticValue) (after : Transition) (accepted : commitPure machine opcode operands value = .ok after)
    (result : Located) (delivered : after.state.control = .delivered result) : result.value.schema = value.schema := by
  obtain ⟨located, control, same⟩ := commitPure_delivers _ _ _ _ _ accepted
  rw [control] at delivered
  cases delivered
  rw [same]

theorem makeClosureWithValues_result_schema (machine : State) (context : Context) (schema : SchemaId .source)
    (function : FunctionId .source) (values : List Located) (after : Transition)
    (accepted : makeClosureWithValues machine context schema function values = .ok after)
    (result : Located) (delivered : after.state.control = .delivered result) : result.value.schema = schema := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, ⟨middle, owner⟩, _, _, _, ⟨store, value⟩, allocated, finished⟩ := accepted
  rw [finishTemporary_delivers _ _ _ finished] at delivered
  cases delivered
  rw [ValueInventory.allocateObject_result _ _ _ _ _ _ _ allocated]
  rfl

set_option maxRecDepth 4096 in
set_option maxHeartbeats 1600000 in
theorem heapPrimitive_result_schema (machine : State) (context : Context)
    (operation : Primitives.GraphOperation) (schema : SchemaId .source) (immediate : Nat)
    (operands : List Located) (after : Transition)
    (accepted : heapPrimitive machine context operation schema immediate operands = .ok after)
    (result : Located) (delivered : after.state.control = .delivered result) : result.value.schema = schema := by
  cases operation <;> simp only [heapPrimitive, bind, throw, throwThe, MonadExceptOf.throw] at accepted
  all_goals try split at accepted
  all_goals grind (gen := 32) only [except_bind_ok, fromOption_ok, → require_ok,
    → finishTemporary_delivers, → ValueInventory.allocateObject_result, → scopedValue_result_schema,
    → commitPure_result_schema, → makeClosureWithValues_result_schema, Profile.Value.schema]

theorem executePrimitive_result_schema (machine : State) (context : Context)
    (schema : SchemaId .source) (opcode : Opcode) (immediate : Nat)
    (failures : List (InstructionFailure .source)) (bindings : Environment) (operands : List Located)
    (after : Transition) (result : Located)
    (executing : machine.control = .execute (.primitive schema opcode immediate failures) bindings operands)
    (accepted : executePrimitive machine context = .ok after)
    (delivered : after.state.control = .delivered result) : result.value.schema = schema := by
  simp only [executePrimitive, executing, bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  split at accepted
  · contradiction
  · simp only [authoredFailure, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
    obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
    cases delivered
  · rename_i value evaluated
    rw [commitPure_result_schema _ _ _ _ _ accepted _ delivered]
    exact Primitives.evaluate_result_schema _ _ _ _ _ _ _ evaluated
  · exact heapPrimitive_result_schema _ _ _ _ _ _ _ accepted _ delivered

end BoundaryV2.Profile.Source.Machine
