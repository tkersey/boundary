import BoundaryV2.SourceValueInventory
import BoundaryV2.SourceCustodyBounds

namespace BoundaryV2.Profile.Source.Machine

/-- The owned-reference component of state well-formedness. It includes stale
tokens in retained values, while requiring every live custody entry to name a
present object. Typing, reusable references, scopes, and obligations have
separate obligations. -/
structure State.OwnedReferenceWF (state : State) : Prop where
  aligned : ValueInventory.All (ValueAligned state.heap.custody) state
  tokens : ValueInventory.All (ValueTokensBounded state.heap.nextCustody) state
  live : state.heap.CustodyLive
  bounded : state.heap.CustodyBounded

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

theorem initial_owned_reference_wf (context : Context) (arguments : List SemanticValue) (state : State)
    (accepted : initial context arguments = .ok state) : state.OwnedReferenceWF := by
  have empty := initialization_excludes_hidden_handles _ _ _ accepted
  have values := ValueInventory.initial_has_no_runtime_handles _ _ _ accepted
  refine ⟨?_, ?_, ?_, initial_custody_bounded _ _ _ accepted⟩
  · exact ValueInventory.all_mono _ _ state values (fun value free => token_free_aligned _ _ free.2)
  · exact ValueInventory.all_mono _ _ state values
      (fun value free => by simp [ValueTokensBounded, free.2])
  · intro entry member
    rw [empty.2.2.1] at member
    contradiction

theorem external_retains_reference_custody (state : State) (context : Context) (action : External)
    (after : Transition) (accepted : external state context action = .ok after) :
    after.state.heap.objects = state.heap.objects ∧ after.state.heap.custody = state.heap.custody ∧
      after.state.heap.nextCustody = state.heap.nextCustody := by
  have temporarySame (state after : State) (owner : Custody.Owner)
      (accepted : temporary state = .ok (after, owner)) :
      after.heap.objects = state.heap.objects ∧ after.heap.custody = state.heap.custody ∧
        after.heap.nextCustody = state.heap.nextCustody := by
    unfold temporary at accepted
    split at accepted <;> try contradiction
    split at accepted <;> try contradiction
    cases accepted; exact ⟨rfl, rfl, rfl⟩
  have finishSame (state : State) (value : Located) (after : Transition)
      (accepted : finishTemporary state value = .ok after) :
      after.state.heap.objects = state.heap.objects ∧ after.state.heap.custody = state.heap.custody ∧
        after.state.heap.nextCustody = state.heap.nextCustody := by
    unfold finishTemporary at accepted
    split at accepted <;> try contradiction
    cases accepted; exact ⟨rfl, rfl, rfl⟩
  have scopedSame (state : State) (value : SemanticValue) (after : Transition)
      (accepted : scopedValue state value = .ok after) :
      after.state.heap.objects = state.heap.objects ∧ after.state.heap.custody = state.heap.custody ∧
        after.state.heap.nextCustody = state.heap.nextCustody := by
    simp only [scopedValue, bind] at accepted
    grind only [except_bind_ok]
  cases phase : state.status <;> cases action <;>
    simp only [external, phase, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw,
      Except.bind] at accepted <;> try contradiction
  all_goals grind (gen := 32) only []

theorem external_owned_reference_wf (state : State) (context : Context) (action : External)
    (after : Transition) (accepted : external state context action = .ok after)
    (formed : state.OwnedReferenceWF) : after.state.OwnedReferenceWF := by
  obtain ⟨objects, custody, supply⟩ := external_retains_reference_custody _ _ _ _ accepted
  refine ⟨?_, ?_, ?_, external_custody_bounded _ _ _ _ accepted formed.bounded⟩
  · rw [custody]
    apply ValueInventory.external_preserves_all _ _ _ _ accepted _ formed.aligned
    intro value checked
    exact token_free_aligned _ _ (external_value_has_no_runtime_handles _ _ checked).2
  · rw [supply]
    apply ValueInventory.external_preserves_all _ _ _ _ accepted _ formed.tokens
    intro value checked
    simp [ValueTokensBounded, (external_value_has_no_runtime_handles _ _ checked).2]
  · intro entry member
    simpa only [Heap.lookup, custody, objects] using formed.live entry (custody ▸ member)

theorem commitPure_owned_reference_wf (state : State) (opcode : Opcode) (operands : List Located)
    (result : SemanticValue) (after : Transition) (accepted : commitPure state opcode operands result = .ok after)
    (formed : state.OwnedReferenceWF) (resultAligned : ValueAligned state.heap.custody result)
    (resultBounded : ValueTokensBounded state.heap.nextCustody result) : after.state.OwnedReferenceWF := by
  have storage := commitPure_retains_storage_and_supply _ _ _ _ _ accepted
  refine ⟨?_, ?_, commitPure_preserves_live_objects _ _ _ _ _ accepted formed.live,
    commitPure_custody_bounded _ _ _ _ _ accepted formed.bounded⟩
  · apply ValueInventory.commitPure_preserves_all _ _ _ _ _ accepted
    · exact ValueInventory.all_mono _ _ state formed.aligned
        (fun value aligned => commitPure_preserves_alignment _ _ _ _ _ _ accepted aligned)
    · exact commitPure_preserves_alignment _ _ _ _ _ _ accepted resultAligned
  · rw [storage.2]
    exact ValueInventory.commitPure_preserves_all _ _ _ _ _ accepted _ formed.tokens resultBounded

/-- This is the actual successful-value branch of the full primitive dispatcher.
The opcode theorem supplies reference preservation for all primitive shapes;
checked source admission supplies the constants without runtime handles. -/
theorem pure_primitive_owned_reference_wf (state : State) (context : Context) (opcode : Opcode)
    (schema : SchemaId .source) (immediate : Nat) (failures : List (InstructionFailure .source))
    (environment : Environment) (operands : List Located) (result : SemanticValue) (after : Transition)
    (control : state.control = .execute (.primitive schema opcode immediate failures) environment operands)
    (typed : context.typingValid = true) (formed : state.OwnedReferenceWF)
    (evaluated : Primitives.evaluate context.source.schemas context.executionConstants opcode schema immediate
      (operands.map Located.value) = .ok (.value result))
    (accepted : executePrimitive state context = .ok after) : after.state.OwnedReferenceWF := by
  have committed : commitPure state opcode operands result = .ok after := by
    have checked : (require (operands.all (current state.heap)) .custody).bind
        (fun _ => commitPure state opcode operands result) = .ok after := by
      simpa [executePrimitive, control, evaluated, bind] using accepted
    obtain ⟨_, _, committed⟩ := (except_bind_ok _ _ _).mp checked
    exact committed
  have operandMember (value : Located) (member : value ∈ operands) : value.value ∈ ValueInventory.state state := by
    simp only [ValueInventory.state, control, ValueInventory.control]
    exact List.mem_append_left _ (List.mem_append_left _ (List.mem_append_left _
      (List.mem_append_right _ (List.mem_map.mpr ⟨value, member, rfl⟩))))
  have constants := checked_execution_constants_have_no_handles context typed
  apply commitPure_owned_reference_wf _ _ _ _ _ committed formed
  · apply primitive_preserves_alignment _ _ _ _ _ _ _ _ ?_ ?_ evaluated
    · intro value member
      exact token_free_aligned _ _ (constants value member).2
    · intro value member
      obtain ⟨located, locatedMember, rfl⟩ := List.mem_map.mp member
      exact formed.aligned _ (operandMember located locatedMember)
  · apply primitive_preserves_token_bounds _ _ _ _ _ _ _ _ ?_ ?_ evaluated
    · intro value member
      simp [ValueTokensBounded, (constants value member).2]
    · intro value member
      obtain ⟨located, locatedMember, rfl⟩ := List.mem_map.mp member
      exact formed.tokens _ (operandMember located locatedMember)

theorem authoredFailure_owned_reference_wf (state : State) (context : Context)
    (failures : List (InstructionFailure .source)) (fault : Fault) (after : Transition)
    (accepted : authoredFailure state context failures fault = .ok after)
    (typed : context.typingValid = true) (formed : state.OwnedReferenceWF) : after.state.OwnedReferenceWF := by
  unfold authoredFailure at accepted
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨failure, _, value, found, _, _, rfl⟩ := accepted
  have valueFound : context.executionConstants[failure.value.value]? = some value := by
    cases original : context.executionConstants[failure.value.value]? <;> simp [fromOption, original] at found ⊢
    exact found
  have free := (checked_execution_constants_have_no_handles context typed value (List.mem_of_getElem? valueFound)).2
  have preserve (property : SemanticValue → Prop) (holds : ValueInventory.All property state)
      (valueHolds : property value) :
      ValueInventory.All property { state with control := .unwind ⟨.failure value, [], none⟩ } := by
    simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, exitValues,
      List.append_nil, List.mem_append, List.mem_singleton] at holds ⊢
    grind only []
  exact ⟨preserve _ formed.aligned (token_free_aligned _ _ free),
    preserve _ formed.tokens (by simp [ValueTokensBounded, free]), formed.live, formed.bounded⟩

theorem faulting_primitive_owned_reference_wf (state : State) (context : Context) (opcode : Opcode)
    (schema : SchemaId .source) (immediate : Nat) (failures : List (InstructionFailure .source))
    (environment : Environment) (operands : List Located) (fault : Fault) (after : Transition)
    (control : state.control = .execute (.primitive schema opcode immediate failures) environment operands)
    (typed : context.typingValid = true) (formed : state.OwnedReferenceWF)
    (evaluated : Primitives.evaluate context.source.schemas context.executionConstants opcode schema immediate
      (operands.map Located.value) = .ok (.fault fault))
    (accepted : executePrimitive state context = .ok after) : after.state.OwnedReferenceWF := by
  apply authoredFailure_owned_reference_wf state context failures fault after ?_ typed formed
  have checked : (require (operands.all (current state.heap)) .custody).bind
      (fun _ => authoredFailure state context failures fault) = .ok after := by
    simpa [executePrimitive, control, evaluated, bind] using accepted
  obtain ⟨_, _, failed⟩ := (except_bind_ok _ _ _).mp checked
  exact failed

end BoundaryV2.Profile.Source.Machine
