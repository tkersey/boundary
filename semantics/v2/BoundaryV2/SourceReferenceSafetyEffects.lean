import BoundaryV2.SourceReferenceSafetyRequests

namespace BoundaryV2.Profile.Source.Machine
namespace ReferenceSafety
open ReferenceContracts

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

theorem executeEffectTerm_valid (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (after : Transition)
    (accepted : executeEffectTerm machine context = .ok after)
    (good : Valid context.source.schemas machine) : Valid context.source.schemas after.state := by
  have modes := ReferenceContracts.initialized_execution_preserves_reference_modes _ _ _ _ _ initialized steps
  unfold executeEffectTerm at accepted
  split at accepted <;> try contradiction
  rename_i term bindings operands executing
  simp only [bind, except_bind_ok] at accepted
  obtain ⟨_, _, accepted⟩ := accepted
  have outer : ∀ binding ∈ bindings,
      ValueGood context.source.schemas machine.heap binding.located.value ∧ ValueModes context.source.schemas binding.located.value := by
    intro binding member
    have member : binding.located.value ∈ ValueInventory.state machine := by
      simp only [ValueInventory.state, executing, ValueInventory.control, ValueInventory.environment,
        List.mem_append, List.mem_map]
      exact Or.inl (Or.inl (Or.inl (Or.inl ⟨binding, member, rfl⟩)))
    exact ⟨good.values _ member, modes _ member⟩
  have inputs : ∀ value ∈ operands,
      ValueGood context.source.schemas machine.heap value.value ∧ ValueModes context.source.schemas value.value := by
    intro value member
    have member : value.value ∈ ValueInventory.state machine := by
      simp only [ValueInventory.state, executing, ValueInventory.control, List.mem_append, List.mem_map]
      exact Or.inl (Or.inl (Or.inl (Or.inr ⟨value, member, rfl⟩)))
    exact ⟨good.values _ member, modes _ member⟩
  cases term <;> simp only at accepted <;> try contradiction
  case perform operation => exact openRequest_valid _ _ _ _ _ accepted good (fun value member => (inputs value member).1)
  case handle handler body arguments stored =>
    split at accepted <;> try contradiction
    rename_i closure rest operandsEqual
    apply installHandler_valid _ _ _ _ _ _ _ _ accepted good modes
      (inputs closure (by simp)).1 (inputs closure (by simp)).2
    · intro value member
      exact inputs value (by simp [List.mem_of_mem_take member])
    · intro value member
      exact inputs value (by simp [List.mem_of_mem_drop member])
    · exact outer
  case resumeValue token argument =>
    split at accepted <;> try contradiction
    rename_i tokenValue argumentValue operandsEqual
    exact resumeValue_valid _ _ _ _ _ initialized steps _ _ _ _ accepted good
      (inputs tokenValue (by simp)).1 (inputs tokenValue (by simp)).2
      (inputs argumentValue (by simp)).1 (inputs argumentValue (by simp)).2 trivial
  case resumeWith token argument handler stored =>
    split at accepted <;> try contradiction
    rename_i tokenValue argumentValue rest operandsEqual
    exact resumeValue_valid _ _ _ _ _ initialized steps _ _ _ _ accepted good
      (inputs tokenValue (by simp)).1 (inputs tokenValue (by simp)).2
      (inputs argumentValue (by simp)).1 (inputs argumentValue (by simp)).2
      ⟨fun value member => inputs value (by simp [member]), outer⟩
  case resumeComputation token computation =>
    split at accepted <;> try contradiction
    rename_i tokenValue computationValue operandsEqual
    exact resumeComputation_valid _ _ _ _ _ initialized steps _ _ _ accepted good
      (inputs tokenValue (by simp)).1 (inputs tokenValue (by simp)).2
      (inputs computationValue (by simp)).1 (inputs computationValue (by simp)).2
  case withRegion descriptor body arguments =>
    split at accepted <;> try contradiction
    rename_i closure rest operandsEqual
    exact enterRegion_valid _ _ _ _ _ _ accepted good modes
      (inputs closure (by simp)).1 (inputs closure (by simp)).2
      (fun value member => (inputs value (by simp [member])).1)
      (fun value member => (inputs value (by simp [member])).2)

end ReferenceSafety
end BoundaryV2.Profile.Source.Machine
