import BoundaryV2.SourceCloneSupport

namespace BoundaryV2.Profile.Source.Machine
namespace CloneTraits
open ReferenceContracts ReferenceStructureContracts

theorem reachable_safe_object_token_free (context : Context) (arguments : List SemanticValue)
    (before machine after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (saved instantiated : Capture)
    (accepted : instantiateCapture machine context saved = .ok (after, instantiated))
    (node : NodeId) (supported : node ∈ cloneSupport machine.heap saved)
    (stored : Object) (found : machine.heap.lookup node = some stored)
    (safeNode : NodeSafe context.source machine.heap node) :
    ∀ value ∈ ValueInventory.object stored, ownedTokens value = [] := by
  obtain ⟨schema, original, originalAt, compatible, safe⟩ := safeNode
  cases Option.some.inj (found.symm.trans originalAt)
  have structures := initialized_execution_preserves_reference_structure _ _ _ _ _ initialized steps
  have fields := ValueInventory.lookup_preserves_all machine node stored found _ structures
  have objects := ObjectSchemas.initialized_execution_preserves_object_schemas _ _ _ _ _ initialized steps
  have storedType := ObjectSchemas.heap_lookup context.source machine.heap node stored found objects
  cases stored with
  | capability _ _ | region _ _ _ _ | borrow _ _ _ _ => simp [ValueInventory.object]
  | closure storedSchema function bindings =>
    simp only [Matches] at compatible
    subst schema
    have free := reachable_copy_closure_has_no_owned_captures _ _ _ _ _ initialized steps _ _ _ _ found
      (safe.clone_implies_copy _ _)
    intro value member
    simp only [ValueInventory.object, ValueInventory.environment] at member
    obtain ⟨binding, bindingMember, rfl⟩ := List.mem_map.mp member
    exact free binding bindingMember
  | cell identity storedSchema region content =>
    simp only [Matches] at compatible
    subst schema
    obtain ⟨descriptor, shape⟩ := storedType
    have childSafe : Traits.Safe context.source.schemas (content.value.schema, .clone) := by
      apply safe.reachable
      apply Traits.Reach.step .refl
        (show Traits.rule context.source.schemas (storedSchema, .clone) = some [(content.value.schema, .clone)] by
          simp [Traits.rule, shape, Traits.premises])
      simp
    intro value member
    cases List.mem_singleton.mp member
    exact ReferenceStructureContracts.clone_value_has_no_tokens _ _ (fields _ (by simp [ValueInventory.object])) childSafe
  | multiTemplate capture =>
    have checked := (clone_safe_has_no_captured_custody _ _ _
      (instantiation_checks_dormant_templates _ _ _ _ _ _ node supported found accepted)).1
    exact fun value member => (clone_safe_capture_inventory context.source capture checked value member).2
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

theorem frozen_object_token_free (saved : Capture) (dormant : List Capture) (node : NodeId) (stored : Object)
    (free : ∀ value ∈ ValueInventory.object stored, ownedTokens value = [])
    (rootFree : ∀ cell ∈ saved.frozenCells, ownedTokens cell.content.value = [])
    (dormantFree : ∀ inner ∈ dormant, ∀ cell ∈ inner.frozenCells, ownedTokens cell.content.value = []) :
    ∀ value ∈ ValueInventory.object (frozenObject saved dormant node stored), ownedTokens value = [] := by
  cases stored <;> try exact free
  rename_i identity schema region content
  intro value member
  simp only [frozenObject, ValueInventory.object, List.mem_singleton] at member
  cases member
  cases selected : (saved.frozenCells ++ dormant.flatMap Capture.frozenCells).find? (fun cell => cell.node == node) with
  | none => simpa only [selected, Option.map_none, Option.getD_none] using free content.value (by simp [ValueInventory.object])
  | some cell =>
    have member := List.mem_of_find?_eq_some selected
    have cellFree : ownedTokens cell.content.value = [] := by
      rcases List.mem_append.mp member with root | nested
      · exact rootFree cell root
      · obtain ⟨inner, innerMember, cellMember⟩ := List.mem_flatMap.mp nested
        exact dormantFree inner innerMember cell cellMember
    simpa only [selected, Option.map_some, Option.getD_some] using cellFree

theorem reachable_instantiation_preserves_alignment (context : Context) (arguments : List SemanticValue)
    (before machine after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (saved instantiated : Capture)
    (accepted : instantiateCapture machine context saved = .ok (after, instantiated))
    (valid : ValueInventory.All (ValueValid context.source.schemas machine.heap) machine)
    (aligned : ValueInventory.All (ValueAligned machine.heap.custody) machine)
    (captureValid : ∀ value ∈ ValueInventory.capture saved, ValueValid context.source.schemas machine.heap value)
    (captureStructure : ∀ value ∈ ValueInventory.capture saved, ValueStructure context.source.schemas value)
    (frozen : FrozenContracts.Valid machine.heap saved) :
    ValueInventory.All (ValueAligned after.heap.custody) after ∧
      (∀ value ∈ ValueInventory.capture instantiated, ValueAligned after.heap.custody value) := by
  have sameBook := instantiate_preserves_custody _ _ _ _ _ accepted
  have oldAligned : ValueInventory.All (ValueAligned after.heap.custody) machine := sameBook ▸ aligned
  have rootChecked := instantiation_root_safe _ _ _ _ _ accepted
  have supportSafe := reachable_clone_support_safe _ _ _ _ _ _ initialized steps _ _ accepted valid captureValid captureStructure frozen
  obtain ⟨mapping, _, captured, _, inventory⟩ := instantiation_inventory machine after context saved instantiated accepted
  let dormant := (cloneSupport machine.heap saved).filterMap (fun node => match machine.heap.lookup node with
    | some (.multiTemplate inner) => some inner | _ => none)
  have objectValues : ∀ entry ∈ after.heap.objects,
      ∀ value ∈ entry.toList.flatMap ValueInventory.object, ValueAligned after.heap.custody value := by
    intro entry member value valueMember
    rcases inventory entry member with old | ⟨node, nodeMember, stored, found, rfl⟩
    · apply oldAligned value
      simp only [ValueInventory.state, ValueInventory.heap, List.mem_append, List.mem_flatMap]
      exact Or.inl (Or.inr (Or.inl (Or.inl ⟨entry, old, List.mem_flatMap.mp valueMember⟩)))
    · have supported := (List.mem_filter.mp nodeMember).1
      have originalFree := reachable_safe_object_token_free _ _ _ _ _ _ initialized steps _ _ accepted
        node supported stored found (supportSafe node supported)
      have allFree := frozen_object_token_free saved dormant node stored originalFree
        (fun cell member => (clone_safe_captured_values context.source saved rootChecked).2.2 cell member |>.2)
        (by
          intro inner innerMember
          obtain ⟨innerNode, innerSupported, selected⟩ := List.mem_filterMap.mp innerMember
          have innerFound : machine.heap.lookup innerNode = some (.multiTemplate inner) := by
            cases lookup : machine.heap.lookup innerNode with
            | none => simp [lookup] at selected
            | some original =>
              cases original <;> simp [lookup] at selected
              cases selected; rfl
          have checked := (clone_safe_has_no_captured_custody _ _ _
            (instantiation_checks_dormant_templates _ _ _ _ _ _ innerNode innerSupported innerFound accepted)).1
          exact fun cell member => (clone_safe_captured_values context.source inner checked).2.2 cell member |>.2)
      simp only [Option.toList_some, List.flatMap_cons, List.flatMap_nil, List.append_nil,
        ValueInventory.rename_object] at valueMember
      obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp valueMember
      exact token_free_renaming_preserves_alignment mapping after.heap.custody original (allFree original originalMember)
  constructor
  · exact instantiation_inventory_preserves_all _ _ _ _ _ accepted _ oldAligned objectValues
  · rw [captured, ValueInventory.rename_capture]
    intro value member
    obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
    exact token_free_renaming_preserves_alignment mapping after.heap.custody original
      (clone_safe_capture_inventory context.source saved rootChecked original originalMember).2

theorem instantiateCapture_preserves_custody_live (machine after : State) (context : Context)
    (saved instantiated : Capture) (accepted : instantiateCapture machine context saved = .ok (after, instantiated))
    (live : machine.heap.CustodyLive) : after.heap.CustodyLive := by
  have sameBook := instantiate_preserves_custody _ _ _ _ _ accepted
  intro entry member
  have old := live entry (sameBook ▸ member)
  have bound : entry.object.value < machine.heap.objects.length := by
    by_cases inside : entry.object.value < machine.heap.objects.length
    · exact inside
    · have absent : machine.heap.objects[entry.object.value]? = none := List.getElem?_eq_none (by omega)
      simp [Heap.lookup, absent] at old
  rw [source_instantiation_retains_outside_lookup _ _ _ _ _ entry.object bound accepted]
  exact old

/-- The actual stored-template invocation derives its capture premises from
heap lookup and initialized execution, then preserves compatibility, token
alignment, and live custody for the entire resulting state and capture. -/
theorem reachable_template_instantiation_preserves_references (context : Context) (arguments : List SemanticValue)
    (before machine after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (node : NodeId) (saved instantiated : Capture)
    (stored : machine.heap.lookup node = some (.multiTemplate saved))
    (accepted : instantiateCapture machine context saved = .ok (after, instantiated))
    (valid : ValueInventory.All (ValueValid context.source.schemas machine.heap) machine)
    (aligned : ValueInventory.All (ValueAligned machine.heap.custody) machine)
    (live : machine.heap.CustodyLive) :
    ValueInventory.All (ValueValid context.source.schemas after.heap) after ∧
    ValueInventory.All (ValueAligned after.heap.custody) after ∧ after.heap.CustodyLive ∧
    (∀ value ∈ ValueInventory.capture instantiated, ValueValid context.source.schemas after.heap value) ∧
    (∀ value ∈ ValueInventory.capture instantiated, ValueAligned after.heap.custody value) := by
  have captureValid := ValueInventory.lookup_preserves_all machine node (.multiTemplate saved) stored _ valid
  have captureStructure := ValueInventory.lookup_preserves_all machine node (.multiTemplate saved) stored _
    (initialized_execution_preserves_reference_structure _ _ _ _ _ initialized steps)
  have captureFrozen := FrozenContracts.heap_lookup machine.heap node (.multiTemplate saved) stored
    (FrozenContracts.initialized_execution_preserves_frozen_cells _ _ _ _ _ initialized steps)
  have validity := instantiateCapture_preserves_reference_validity _ _ _ _ _ accepted valid captureValid
  have alignment := reachable_instantiation_preserves_alignment _ _ _ _ _ _ initialized steps _ _ accepted
    valid aligned captureValid captureStructure captureFrozen
  exact ⟨validity.1, alignment.1, instantiateCapture_preserves_custody_live _ _ _ _ _ accepted live,
    validity.2, alignment.2⟩

end CloneTraits
end BoundaryV2.Profile.Source.Machine
