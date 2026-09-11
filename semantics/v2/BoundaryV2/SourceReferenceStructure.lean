import BoundaryV2.ReferencePrimitives
import BoundaryV2.SourceReferenceClone

namespace BoundaryV2.Profile.Source.Machine
namespace ReferenceStructureContracts

def ValueStructure (schemas : List (Schema .source)) :=
  Profile.Value.ReferenceStructure schemas (ReferenceOwnership schemas)

theorem typed_has_reference_structure (schemas : List (Schema .source)) (value : SemanticValue)
    (typed : ValueShape schemas value) : ValueStructure schemas value :=
  .of_typed typed

theorem structure_has_reference_modes (schemas : List (Schema .source)) (value : SemanticValue)
    (structured : ValueStructure schemas value) : ReferenceContracts.ValueModes schemas value := by
  induction structured with
  | scalarAny | blobAny => simp [ReferenceContracts.ValueModes, Primitives.ReferencesSatisfy]
  | product _ _ _ ih | sequenceAny _ _ _ ih => simpa only [ReferenceContracts.ValueModes, Primitives.ReferencesSatisfy] using ih
  | variantAny _ _ _ ih => simpa only [ReferenceContracts.ValueModes, Primitives.ReferencesSatisfy] using ih
  | reference found owned =>
    simp only [ReferenceContracts.ValueModes, Primitives.ReferencesSatisfy]
    exact Profile.Value.Typed.reference found owned

theorem rename_value_structure (schemas : List (Schema .source)) (mapping : Renaming)
    (value : SemanticValue) (typed : ValueStructure schemas value) : ValueStructure schemas (renameValue mapping value) := by
  induction typed with
  | scalarAny => simp only [renameValue]; exact .scalarAny
  | blobAny => simp only [renameValue]; exact .blobAny
  | product found exactTypes _ induction =>
    simp only [renameValue]
    apply Profile.Value.ReferenceStructure.product found
    · simpa only [List.map_map, Function.comp_def, renaming_preserves_value_schema] using exactTypes
    · intro child member
      obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
      exact induction original originalMember
  | variantAny found exactType _ induction =>
    simp only [renameValue]
    exact .variantAny found (by simpa only [renaming_preserves_value_schema] using exactType) induction
  | sequenceAny found exactTypes _ induction =>
    simp only [renameValue]
    apply Profile.Value.ReferenceStructure.sequenceAny found
    · intro child member
      obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
      simpa only [renaming_preserves_value_schema] using exactTypes original originalMember
    · intro child member
      obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
      exact induction original originalMember
  | reference found owned =>
    simp only [renameValue]
    exact .reference found owned

theorem initial_reference_structure (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) :
    ValueInventory.All (ValueStructure context.source.schemas) machine :=
  ValueInventory.all_mono _ _ machine (initial_value_shapes context arguments machine accepted)
    (typed_has_reference_structure context.source.schemas)

theorem external_preserves_reference_structure (machine : State) (context : Context) (action : External)
    (after : Transition) (accepted : external machine context action = .ok after)
    (modes : ValueInventory.All (ValueStructure context.source.schemas) machine) :
    ValueInventory.All (ValueStructure context.source.schemas) after.state := by
  apply ValueInventory.external_preserves_all machine context action after accepted _ modes
  intro value admitted
  exact typed_has_reference_structure _ _ (external_value_has_shape _ _ admitted)

theorem primitive_preserves_reference_structure (schemas : List (Schema .source))
    (constants : List SemanticValue) (opcode : Opcode) (schema : SchemaId .source) (immediate : Nat)
    (operands : List SemanticValue) (result : SemanticValue)
    (constantsValid : ∀ value ∈ constants, ValueStructure schemas value)
    (operandsValid : ∀ value ∈ operands, ValueStructure schemas value)
    (accepted : Primitives.evaluate schemas constants opcode schema immediate operands = .ok (.value result)) :
    ValueStructure schemas result :=
  ReferencePrimitives.evaluate_preserves_reference_structure schemas (ReferenceOwnership schemas) constants opcode schema immediate operands result constantsValid operandsValid accepted

theorem instantiateCapture_preserves_reference_structure (machine after : State) (context : Context)
    (saved instantiated : Capture)
    (accepted : instantiateCapture machine context saved = .ok (after, instantiated))
    (valid : ValueInventory.All (ValueStructure context.source.schemas) machine)
    (captureValid : ∀ value ∈ ValueInventory.capture saved, ValueStructure context.source.schemas value) :
    ValueInventory.All (ValueStructure context.source.schemas) after ∧
      (∀ value ∈ ValueInventory.capture instantiated, ValueStructure context.source.schemas value) := by
  obtain ⟨mapping, captured, _, inventory⟩ := ReferenceContracts.instantiation_reference_map machine after context saved instantiated accepted
  exact ReferenceContracts.instantiation_values_of_inventory machine after context saved instantiated accepted mapping captured _ _
    valid captureValid (fun _ holds => holds) (rename_value_structure context.source.schemas mapping) inventory

end ReferenceStructureContracts
end BoundaryV2.Profile.Source.Machine
