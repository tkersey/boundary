import BoundaryV2.SourceCloneTraits

namespace BoundaryV2.Profile.Source.Machine
namespace CloneTraits
open ReferenceContracts ReferenceStructureContracts

theorem clone_safe_frame_inventory (source : Module) (saved : Frame)
    (checked : frameCloneSafe source saved = true) :
    ∀ value ∈ ValueInventory.frame saved,
      Traits.check source.schemas .clone value.schema = true ∧ ownedTokens value = [] := by
  have same : ValueInventory.frame saved = (frameValues saved).map Located.value := by
    cases saved <;> simp only [frameCloneSafe] at checked <;> try contradiction
    all_goals simp [ValueInventory.frame, frameValues, ValueInventory.environment, ValueInventory.activation,
      List.map_map, Function.comp_def]
  rw [same]
  intro value member
  obtain ⟨located, locatedMember, rfl⟩ := List.mem_map.mp member
  exact clone_safe_frame_values _ _ checked located locatedMember

theorem clone_safe_capture_inventory (source : Module) (saved : Capture)
    (checked : captureCloneSafe source saved = true) :
    ∀ value ∈ ValueInventory.capture saved,
      Traits.check source.schemas .clone value.schema = true ∧ ownedTokens value = [] := by
  have frames : saved.frames.all (frameCloneSafe source) = true := (Bool.and_eq_true_iff.mp
    (Bool.and_eq_true_iff.mp checked).1).1
  have parts := clone_safe_captured_values source saved checked
  intro value member
  simp only [ValueInventory.capture, List.mem_append, List.mem_flatMap, List.mem_map] at member
  rcases member with ((⟨frame, frameMember, member⟩ | member) | ⟨located, member, rfl⟩) | ⟨cell, member, rfl⟩
  · exact clone_safe_frame_inventory source frame (List.all_eq_true.mp frames frame frameMember) value member
  · simp only [ValueInventory.activation, ValueInventory.environment, List.mem_append, List.mem_map] at member
    rcases member with ⟨binding, member, rfl⟩ | ⟨located, member, rfl⟩
    · exact parts.2.1 binding.located (List.mem_append_left _ (List.mem_append_left _ (List.mem_map.mpr ⟨binding, member, rfl⟩)))
    · exact parts.2.1 located (by simp [member])
  · exact parts.2.1 located (by simp [member])
  · exact parts.2.2 cell member

theorem frame_reference_values (saved : Frame) (node : NodeId) (member : node ∈ frameReferences saved) :
    ∃ value ∈ ValueInventory.frame saved, node ∈ valueReferences value := by
  cases saved
  case releaseReturn scope after =>
    cases after <;> simp only [frameReferences, frameValues, ValueInventory.frame, ValueInventory.afterRelease,
      List.flatMap_nil, List.nil_append, List.mem_flatMap, List.mem_singleton] at member ⊢
    · exact ⟨_, rfl, member⟩
    · exact member
  all_goals simp only [frameReferences, frameValues, ValueInventory.frame, ValueInventory.environment, ValueInventory.activation,
    ValueInventory.afterRelease, List.mem_append, List.mem_flatMap, List.mem_map, List.not_mem_nil,
    List.append_nil, List.flatMap_map, Option.mem_toList] at member ⊢
  all_goals first | contradiction | grind only []

theorem capture_reference_values (saved : Capture) (node : NodeId) (member : node ∈ captureReferences saved) :
    (∃ value ∈ ValueInventory.capture saved, node ∈ valueReferences value) ∨
      ∃ cell ∈ saved.frozenCells, cell.node = node := by
  simp only [captureReferences, List.mem_append, List.mem_flatMap] at member
  rcases member with ((⟨frame, frameMember, member⟩ | member) | ⟨located, member, present⟩) | ⟨cell, member, present⟩
  · obtain ⟨value, valueMember, present⟩ := frame_reference_values frame node member
    exact Or.inl ⟨value, List.mem_append_left _ (List.mem_append_left _ (List.mem_append_left _ (List.mem_flatMap.mpr ⟨frame, frameMember, valueMember⟩))), present⟩
  · simp only [activationReferences, List.mem_flatMap, List.mem_append, List.mem_map] at member
    obtain ⟨located, (⟨binding, member, rfl⟩ | member), present⟩ := member
    · exact Or.inl ⟨binding.located.value, List.mem_append_left _ (List.mem_append_left _ (List.mem_append_right _ (List.mem_append_left _ (List.mem_map.mpr ⟨binding, member, rfl⟩)))), present⟩
    · exact Or.inl ⟨located.value, List.mem_append_left _ (List.mem_append_left _ (List.mem_append_right _ (List.mem_append_right _ (List.mem_map.mpr ⟨located, member, rfl⟩)))), present⟩
  · exact Or.inl ⟨located.value, List.mem_append_left _ (List.mem_append_right _ (List.mem_map.mpr ⟨located, member, rfl⟩)), present⟩
  · rcases List.mem_cons.mp present with same | present
    · exact Or.inr ⟨cell, member, same.symm⟩
    · exact Or.inl ⟨cell.content.value, List.mem_append_right _ (List.mem_map.mpr ⟨cell, member, rfl⟩), present⟩

theorem capture_nodes_safe (source : Module) (heap : Heap) (saved : Capture)
    (checked : captureCloneSafe source saved = true)
    (structured : ∀ value ∈ ValueInventory.capture saved, ValueStructure source.schemas value)
    (valid : ∀ value ∈ ValueInventory.capture saved, ValueValid source.schemas heap value)
    (objects : ObjectSchemas.Valid source heap.objects) (frozen : FrozenContracts.Valid heap saved) :
    ∀ node ∈ captureReferences saved, NodeSafe source heap node := by
  have fields := clone_safe_capture_inventory source saved checked
  intro node member
  rcases capture_reference_values saved node member with ⟨value, member, present⟩ | ⟨cell, cellMember, rfl⟩
  · exact value_nodes_safe source heap value (structured value member) (valid value member)
      (Traits.check_sound _ _ _ (fields value member).1) node present
  · obtain ⟨⟨schema, content, found, same⟩, _⟩ := frozen cell cellMember
    obtain ⟨descriptor, shape⟩ := ObjectSchemas.heap_lookup source heap cell.node _ found objects
    have child := (clone_safe_captured_values source saved checked).2.2 cell cellMember
    have childSafe : Traits.Safe source.schemas (content.value.schema, .clone) := by
      rw [same]
      exact Traits.check_sound _ _ _ child.1
    refine ⟨schema, _, found, rfl, ?_⟩
    apply Traits.safe_of_children source.schemas _ [(content.value.schema, .clone)]
    · simp [Traits.rule, shape, Traits.premises]
    · intro atom member
      cases List.mem_singleton.mp member
      exact childSafe

end CloneTraits
end BoundaryV2.Profile.Source.Machine
