import BoundaryV2.SourceReferenceStructureExecution
import BoundaryV2.SourceClosureExecution

namespace BoundaryV2.Profile.Source.Machine
namespace ReferenceStructureContracts

/-- Copyable catalog paths exclude owning references at every aggregate leaf.
No premise concerns scalar payloads, byte lengths, or container wire bounds. -/
theorem copy_value_has_no_tokens (schemas : List (Schema .source)) (value : SemanticValue)
    (structured : ValueStructure schemas value) (safe : Traits.Safe schemas (value.schema, .copy)) :
    ownedTokens value = [] := by
  have inherited := structured.reference_traits .copy safe
  have zero : ValueTokensBounded 0 value := by
    apply (referencesSatisfy_token_bounds 0 value).mp
    apply ReferenceContracts.references_mono value _ _ inherited
    intro schema node token ⟨safe, inner, shape, owned⟩
    have none := copy_reference_has_no_token schemas schema inner node token shape safe owned
    simp [none]
  cases tokens : ownedTokens value with
  | nil => rfl
  | cons token tail =>
    have impossible := zero token (by simp [tokens])
    omega

theorem clone_value_has_no_tokens (schemas : List (Schema .source)) (value : SemanticValue)
    (structured : ValueStructure schemas value) (safe : Traits.Safe schemas (value.schema, .clone)) :
    ownedTokens value = [] :=
  copy_value_has_no_tokens schemas value structured (safe.clone_implies_copy schemas value.schema)

theorem initialized_copy_values_have_no_tokens (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) (value : SemanticValue) (member : value ∈ ValueInventory.state after)
    (safe : Traits.check context.source.schemas .copy value.schema = true) : ownedTokens value = [] :=
  copy_value_has_no_tokens _ _ ((initialized_execution_preserves_reference_structure _ _ _ _ _ initialized steps) value member)
    (Traits.check_sound _ _ _ safe)

/-- Every capture of an actually reached copyable closure is token-free. The
closure's source signature, runtime binder inventory, and value structure are
all derived from ordinary source initialization and execution. -/
theorem reachable_copy_closure_has_no_owned_captures (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (node : NodeId) (schema : SchemaId .source)
    (function : FunctionId .source) (bindings : Environment)
    (found : machine.heap.lookup node = some (.closure schema function bindings))
    (safe : Traits.Safe context.source.schemas (schema, .copy)) :
    ∀ binding ∈ bindings, ownedTokens binding.located.value = [] := by
  obtain ⟨signature, _, shape, _, _, _, _, _, _, captures⟩ :=
    ClosureContracts.reachable_closure_signature _ _ _ _ _ initialized steps _ _ _ _ found
  have structures := initialized_execution_preserves_reference_structure _ _ _ _ _ initialized steps
  have fields := ValueInventory.lookup_preserves_all machine node _ found _ structures
  intro binding member
  have captured := captures binding member
  have copy := safe.computation_capture _ _ _ _ _ shape (by simpa using captured.2)
  apply copy_value_has_no_tokens _ _ ?_ copy
  apply fields
  simp only [ValueInventory.object, ValueInventory.environment, List.mem_map]
  exact ⟨binding, member, rfl⟩

end ReferenceStructureContracts
end BoundaryV2.Profile.Source.Machine
