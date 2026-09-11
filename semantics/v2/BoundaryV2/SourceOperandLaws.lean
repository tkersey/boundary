import BoundaryV2.SourceMachine

namespace BoundaryV2.Profile.Source.Machine

private theorem bind_success (value : Except Invalid α) (next : α → Except Invalid β)
    (result : β) (accepted : value.bind next = .ok result) :
    ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value with
  | error error => cases accepted
  | ok input => exact ⟨input, rfl, accepted⟩

/-- The source machine's actual transfer retains the complete object and token
inventory. Only ownership locations change after every sender is checked. -/
theorem move_values_preserves_inventory (before after : Heap) (values : List Located)
    (receiver : Nat → Custody.Owner)
    (accepted : moveValues before values receiver = some after) :
    after.objects = before.objects ∧
    after.custody.entries.map Custody.Entry.token = before.custody.entries.map Custody.Entry.token ∧
    after.custody.entries.map Custody.Entry.object = before.custody.entries.map Custody.Entry.object := by
  unfold moveValues at accepted
  simp only [bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨custody, committed, rfl⟩ := accepted
  exact ⟨rfl, Custody.commit_preserves_exact_objects _ _ _ committed⟩

private theorem operand_move_member (values : List Located) (receiver : Nat → Custody.Owner)
    (index : Nat) (inBounds : index < values.length) (token : CustodyToken)
    (member : token ∈ ownedTokens values[index].value) :
    (⟨token, values[index].owner, receiver index⟩ : Custody.Move) ∈
      (values.mapIdx (fun index value => value.moves (receiver index))).flatten := by
  apply List.mem_flatten.mpr
  refine ⟨values[index].moves (receiver index), ?_, ?_⟩
  · exact List.mem_mapIdx.mpr ⟨index, inBounds, rfl⟩
  · exact List.mem_map.mpr ⟨token, member, rfl⟩

/-- Each exclusive leaf of each indexed operand is transferred to that
operand's receiver. A successful transfer cannot silently omit a prefix. -/
theorem move_values_transfers_each_operand (before after : Heap) (values : List Located)
    (receiver : Nat → Custody.Owner) (index : Nat) (inBounds : index < values.length)
    (token : CustodyToken) (member : token ∈ ownedTokens values[index].value)
    (accepted : moveValues before values receiver = some after) :
    Custody.has before.custody token values[index].owner = true ∧
    Custody.owns after.custody token (receiver index) := by
  unfold moveValues at accepted
  simp only [bind, pure, Option.bind_eq_some_iff, Option.some.injEq] at accepted
  obtain ⟨custody, committed, rfl⟩ := accepted
  have moving := operand_move_member values receiver index inBounds token member
  exact ⟨Custody.commit_checks_every_sender _ _ _ committed moving,
    Custody.commit_transfers_to_receiver _ _ _ committed moving⟩

theorem moved_operand_sender_cannot_reuse (before after : Heap) (values : List Located)
    (receiver : Nat → Custody.Owner) (index : Nat) (inBounds : index < values.length)
    (token : CustodyToken) (member : token ∈ ownedTokens values[index].value)
    (accepted : moveValues before values receiver = some after)
    (different : receiver index ≠ values[index].owner) :
    ¬ Custody.owns after.custody token values[index].owner := by
  intro reuse
  have moved := (move_values_transfers_each_operand _ _ _ _ _ inBounds _ member accepted).2
  exact different (Custody.unique_custodian _ _ _ _ moved reuse)

/-- Fault dispatch retains the entire heap, including the outstanding owners,
ordered scope holdings, obligations, and already evaluated operand frames. -/
theorem authored_failure_retains_owners (state : State) (context : Context)
    (failures : List (InstructionFailure .source)) (fault : Fault) (transition : Transition)
    (accepted : authoredFailure state context failures fault = .ok transition) :
    ∃ value, transition.state = { state with control := .unwind ⟨.failure value, [], none⟩ } ∧
      transition.events = [] := by
  unfold authoredFailure at accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨value, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  cases accepted
  exact ⟨value, rfl, rfl⟩

/-- A fault in a later primitive operand enters unwind with the evaluated
prefix at its existing owners. The failed primitive performs no transfer. -/
theorem primitive_fault_keeps_operand_prefix (state : State) (context : Context)
    (schema : SchemaId .source) (opcode : Opcode) (immediate : Nat)
    (failures : List (InstructionFailure .source)) (environment savedEnvironment : Environment)
    (operands evaluated : List Located) (intent : Intent) (remaining : List SourceValueId)
    (tail : List Frame) (fault : Fault) (transition : Transition)
    (control : state.control = .execute (.primitive schema opcode immediate failures) environment operands)
    (stack : state.stack = .operands intent savedEnvironment remaining evaluated :: tail)
    (evaluation : Primitives.evaluate context.source.schemas context.executionConstants opcode schema immediate
      (operands.map Located.value) = .ok (.fault fault))
    (accepted : executePrimitive state context = .ok transition) :
    ∃ value, transition.state.control = .unwind ⟨.failure value, [], none⟩ ∧
      transition.state.heap = state.heap ∧
      transition.state.stack = .operands intent savedEnvironment remaining evaluated :: tail ∧
      transition.events = [] := by
  simp only [executePrimitive, control, evaluation] at accepted
  obtain ⟨_, _, accepted⟩ := bind_success _ _ _ accepted
  obtain ⟨value, after, events⟩ := authored_failure_retains_owners _ _ _ _ _ accepted
  exact ⟨value, by rw [after], by rw [after], by simpa only [after] using stack, events⟩

end BoundaryV2.Profile.Source.Machine
