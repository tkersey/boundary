import BoundaryV2.SourceCloneRoots

namespace BoundaryV2.Profile.Source.Machine
namespace CloneTraits
open ReferenceContracts ReferenceStructureContracts

theorem instantiation_root_safe (machine after : State) (context : Context) (saved instantiated : Capture)
    (accepted : instantiateCapture machine context saved = .ok (after, instantiated)) :
    captureCloneSafe context.source saved = true :=
  (clone_safe_has_no_captured_custody _ _ _
    (source_instantiation_checks_clone_safety _ _ _ _ _ accepted)).1

theorem reachable_clone_children_safe (context : Context) (arguments : List SemanticValue)
    (before machine after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (saved instantiated : Capture)
    (accepted : instantiateCapture machine context saved = .ok (after, instantiated))
    (valid : ValueInventory.All (ValueValid context.source.schemas machine.heap) machine)
    (node : NodeId) (supported : node ∈ cloneSupport machine.heap saved)
    (safeNode : NodeSafe context.source machine.heap node) :
    ∀ child ∈ cloneChildren machine.heap saved.localRegions node, NodeSafe context.source machine.heap child := by
  have contextTyped : context.typingValid = true := by
    simpa only [Context.typingValid, Option.any_eq_true] using initial_checks_typing _ _ _ initialized
  have structures := initialized_execution_preserves_reference_structure _ _ _ _ _ initialized steps
  have objects := ObjectSchemas.initialized_execution_preserves_object_schemas _ _ _ _ _ initialized steps
  obtain ⟨schema, stored, found, compatible, safe⟩ := safeNode
  have storedValid := ValueInventory.lookup_preserves_all machine node stored found _ valid
  have storedStructure := ValueInventory.lookup_preserves_all machine node stored found _ structures
  have storedType := ObjectSchemas.heap_lookup context.source machine.heap node stored found objects
  cases stored with
  | capability identity effect | region identity descriptor invocation outer => simp [cloneChildren, found]
  | closure storedSchema function bindings =>
    simp only [Matches] at compatible
    subst schema
    obtain ⟨signature, _, shape, _, _, _, _, _, _, captures⟩ :=
      ClosureContracts.reachable_closure_signature _ _ _ _ _ initialized steps _ _ _ _ found
    intro child member
    simp only [cloneChildren, found, objectReferences, List.mem_flatMap] at member
    obtain ⟨binding, bindingMember, member⟩ := member
    have fieldMember : binding.located.value ∈ ValueInventory.object (.closure storedSchema function bindings) := by
      simp only [ValueInventory.object, ValueInventory.environment, List.mem_map]
      exact ⟨binding, bindingMember, rfl⟩
    have fieldSafe := safe.computation_capture _ _ _ _ _ shape (by simpa using (captures binding bindingMember).2)
    exact value_nodes_safe context.source machine.heap binding.located.value (storedStructure _ fieldMember)
      (storedValid _ fieldMember) fieldSafe child member
  | cell identity storedSchema region content =>
    simp only [Matches] at compatible
    subst schema
    obtain ⟨descriptor, shape⟩ := storedType
    have fieldSafe : Traits.Safe context.source.schemas (content.value.schema, .clone) := by
      apply safe.reachable
      apply Traits.Reach.step .refl
        (show Traits.rule context.source.schemas (storedSchema, .clone) = some [(content.value.schema, .clone)] by
          simp [Traits.rule, shape, Traits.premises])
      simp
    have fieldMember : content.value ∈ ValueInventory.object (.cell identity storedSchema region content) := by simp [ValueInventory.object]
    intro child member
    simp only [cloneChildren, found] at member
    split at member
    · exact value_nodes_safe context.source machine.heap content.value (storedStructure _ fieldMember)
        (storedValid _ fieldMember) fieldSafe child member
    · contradiction
  | multiTemplate capture =>
    have checked := (clone_safe_has_no_captured_custody _ _ _
      (instantiation_checks_dormant_templates _ _ _ _ _ _ node supported found accepted)).1
    have frozen := FrozenContracts.heap_lookup _ _ _ found
      (FrozenContracts.initialized_execution_preserves_frozen_cells _ _ _ _ _ initialized steps)
    simpa only [cloneChildren, found, objectReferences] using
      capture_nodes_safe context.source machine.heap capture checked storedStructure storedValid objects frozen
  | oneShot capture =>
    simp only [Matches] at compatible
    subst schema
    obtain ⟨signature, shape, single⟩ := storedType
    obtain ⟨children, rule⟩ := safe _ .refl
    simp [Traits.rule, shape, Traits.premises, single] at rule
  | package storedSchema content =>
    simp only [Matches] at compatible
    subst schema
    obtain ⟨children, rule⟩ := safe _ .refl
    simp only [ObjectSchemas.ObjectValid] at storedType
    simp [Traits.rule, storedType, Traits.premises] at rule
  | resource storedSchema content =>
    simp only [Matches] at compatible
    subst schema
    obtain ⟨identity, descriptor, shape, _⟩ := storedType
    obtain ⟨children, rule⟩ := safe _ .refl
    simp [Traits.rule, shape, Traits.premises] at rule
  | borrow storedSchema resource region invocation =>
    simp only [Matches] at compatible
    subst schema
    obtain ⟨resourceSchema, descriptor, shape, _⟩ := storedType
    exact False.elim (borrowed_is_not_cloneable context storedSchema resourceSchema descriptor contextTyped shape safe)

theorem clone_support_property (machine after : State) (context : Context) (saved instantiated : Capture)
    (accepted : instantiateCapture machine context saved = .ok (after, instantiated))
    (property : NodeId → Prop) (roots : ∀ node ∈ captureReferences saved, property node)
    (edges : ∀ node ∈ cloneSupport machine.heap saved, property node →
      ∀ child ∈ cloneChildren machine.heap saved.localRegions node, property child) :
    ∀ node ∈ cloneSupport machine.heap saved, property node := by
  have closed := FrozenContracts.instantiation_checks_support_closure _ _ _ _ _ accepted
  have both : ∀ node ∈ cloneSupport machine.heap saved,
      node ∈ cloneSupport machine.heap saved ∧ property node := by
    apply List.foldlRecOn (motive := fun support : List NodeId =>
      ∀ node ∈ support, node ∈ cloneSupport machine.heap saved ∧ property node)
      (List.range machine.heap.objects.length) (fun support _ => expandCloneSupport machine.heap saved.localRegions support)
    · intro node member
      have root := List.mem_eraseDups.mp member
      exact ⟨FrozenContracts.capture_references_in_support _ _ _ root, roots node root⟩
    · intro support previous index member node present
      simp only [expandCloneSupport, List.mem_eraseDups, List.mem_append, List.mem_flatMap] at present
      rcases present with old | ⟨parent, parentMember, childMember⟩
      · exact previous node old
      · have known := previous parent parentMember
        exact ⟨closed parent known.1 node childMember, edges parent known.1 known.2 node childMember⟩
  exact fun node member => (both node member).2

theorem reachable_clone_support_safe (context : Context) (arguments : List SemanticValue)
    (before machine after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (saved instantiated : Capture)
    (accepted : instantiateCapture machine context saved = .ok (after, instantiated))
    (valid : ValueInventory.All (ValueValid context.source.schemas machine.heap) machine)
    (captureValid : ∀ value ∈ ValueInventory.capture saved, ValueValid context.source.schemas machine.heap value)
    (captureStructure : ∀ value ∈ ValueInventory.capture saved, ValueStructure context.source.schemas value)
    (frozen : FrozenContracts.Valid machine.heap saved) :
    ∀ node ∈ cloneSupport machine.heap saved, NodeSafe context.source machine.heap node := by
  apply clone_support_property machine after context saved instantiated accepted
  · exact capture_nodes_safe context.source machine.heap saved
      (instantiation_root_safe _ _ _ _ _ accepted) captureStructure captureValid
      (ObjectSchemas.initialized_execution_preserves_object_schemas _ _ _ _ _ initialized steps) frozen
  · exact reachable_clone_children_safe _ _ _ _ _ _ initialized steps _ _ accepted valid

end CloneTraits
end BoundaryV2.Profile.Source.Machine
