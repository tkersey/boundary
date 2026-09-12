import BoundaryV2.SourceReferenceSafetyExecution
import BoundaryV2.SourceValueExecution
import BoundaryV2.SourceInternalProgress

namespace BoundaryV2.Profile.Source.Machine
namespace DisposalProgress

/-- One pending disposal item is an owning edge, not an aggregate traversal. -/
def Leaf (value : Located) : Prop :=
  ∃ schema node token, value.value = .reference schema node (some token)

def Disposable : Object → Prop
  | .closure .. | .oneShot _ | .package .. | .resource .. => True
  | _ => False

theorem owned_object_disposable (source : Module) (schema : SchemaId .source)
    (node : NodeId) (token : CustodyToken) (stored : Object)
    (shape : ValueShape source.schemas (.reference schema node (some token)))
    (compatible : ReferenceContracts.Matches source.schemas schema stored)
    (valid : ObjectSchemas.ObjectValid source stored) : Disposable stored := by
  cases shape with
  | reference found owned =>
    cases stored <;> try trivial
    all_goals simp only [ReferenceContracts.Matches, ObjectSchemas.ObjectValid] at compatible valid
    all_goals simp_all only [ReferenceOwnership, Option.isSome_some]
    all_goals grind only [ReferenceOwnership]

theorem liveOwnedValue_leaf (heap : Heap) (owner : Custody.Owner) (original : SemanticValue) :
    ∀ value ∈ liveOwnedValue heap owner original, Leaf value := by
  cases original with
  | reference schema node token =>
    cases token <;> simp only [liveOwnedValue]
    · simp
    · split <;> simp_all [Leaf]
  | product schema fields | sequence schema fields =>
    simp only [liveOwnedValue, List.mem_flatMap]
    rintro value ⟨child, member, present⟩
    exact liveOwnedValue_leaf heap owner child value present
  | variant schema tag payload => simpa only [liveOwnedValue] using liveOwnedValue_leaf heap owner payload
  | scalar _ _ | blob _ _ => simp [liveOwnedValue]
termination_by sizeOf original
decreasing_by
  all_goals subst original
  all_goals simp_wf
  all_goals first | omega | exact Nat.lt_trans (List.sizeOf_lt_of_mem member) (by omega)

theorem discard_leaf (machine : State) (context : Context) (values : List Located) (released : AfterRelease)
    (executing : machine.control = .discard values released)
    (leaves : ∀ value ∈ values, Leaf value)
    (shapes : ValueInventory.All (ValueShape context.source.schemas) machine)
    (references : ReferenceSafety.Valid context.source.schemas machine)
    (objects : ObjectSchemas.Valid context.source machine.heap.objects) :
    ∃ after, discardValues machine context = .ok after := by
  cases values with
  | nil => exact ⟨resumeRelease machine released, by simp [discardValues, executing]; rfl⟩
  | cons value rest =>
    obtain ⟨schema, node, token, leaf⟩ := leaves value (by simp)
    by_cases live : Custody.has machine.heap.custody token value.owner = true
    · have shape : ValueShape context.source.schemas value.value := by
        apply shapes
        simp [ValueInventory.state, executing, ValueInventory.control]
      have good : ReferenceContracts.ValueValid context.source.schemas machine.heap value.value := by
        apply ReferenceSafety.values_valid references
        simp [ValueInventory.state, executing, ValueInventory.control]
      have usable : ReferenceContracts.Usable machine.heap.custody (some token) := by
        simp only [Custody.has, List.any_eq_true, Bool.and_eq_true, beq_iff_eq] at live
        obtain ⟨entry, member, same, _⟩ := live
        exact ⟨entry, member, same⟩
      rw [leaf] at shape good
      simp only [ReferenceContracts.ValueValid, Primitives.ReferencesSatisfy, ReferenceContracts.ReferenceValid] at good
      obtain ⟨stored, storedAt, compatible⟩ := good usable
      have valid := ObjectSchemas.heap_lookup _ _ _ _ storedAt objects
      have allowed := owned_object_disposable context.source schema node token stored shape compatible valid
      have looked : lookupObject machine value = .ok (node, stored) := by
        simp [lookupObject, current, leaf, ownedTokens, live, require, fromOption, storedAt, bind, Except.bind, pure, Except.pure]
      have retired : ∃ heap, retireObject machine.heap value = some heap := by
        simp [retireObject, leaf, storedAt, consumeValue, ownedTokens, Custody.consume, live]
      obtain ⟨heap, retired⟩ := retired
      have nonempty : (liveOwned machine.heap value).isEmpty = false := by
        simp [liveOwned, liveOwnedValue, leaf, live]
      cases stored <;> try contradiction
      all_goals simp only [discardValues, executing, nonempty, Bool.false_eq_true, ↓reduceIte,
        looked, bind, Except.bind, retired, fromOption, pure, Except.pure]
      all_goals exact ⟨_, rfl⟩
    · refine ⟨{ state := { machine with control := .discard rest released } }, ?_⟩
      simp [discardValues, executing, liveOwned, liveOwnedValue, leaf, live, pure, Except.pure]

/-- On an initialized trajectory the reference and object premises are derived.
The remaining premise identifies the pending owning-edge occurrences. -/
theorem reachable_discard_leaves (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (values : List Located) (released : AfterRelease)
    (executing : machine.control = .discard values released) (leaves : ∀ value ∈ values, Leaf value)
    (running : machine.status = .running) :
    ∃ after, tick machine context = .ok after ∧ after.state ≠ machine := by
  obtain ⟨after, accepted⟩ := discard_leaf machine context values released executing leaves
    (initialized_execution_preserves_value_shapes _ _ _ _ _ initialized steps)
    (ReferenceSafety.initialized_execution_preserves_reference_safety _ _ _ _ _ initialized steps)
    (ObjectSchemas.initialized_execution_preserves_object_schemas _ _ _ _ _ initialized steps)
  have tickOk : tick machine context = .ok after := by simpa only [tick, running, tickRunning, executing] using accepted
  exact ⟨after, tickOk, InternalProgress.running_tick_changes _ _ _ running tickOk⟩

end DisposalProgress
end BoundaryV2.Profile.Source.Machine
