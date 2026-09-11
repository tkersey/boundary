import BoundaryV2.SourceCopyValues

namespace BoundaryV2.Profile
namespace Traits

theorem safe_of_children (schemas : List (Schema space)) (root : Atom space) (children : List (Atom space))
    (found : rule schemas root = some children) (safe : ∀ child ∈ children, Safe schemas child) : Safe schemas root := by
  have first : ∀ atom, Reach schemas root atom → atom = root ∨
      ∃ child ∈ children, Reach schemas child atom := by
    intro atom reached
    induction reached with
    | refl => exact Or.inl rfl
    | @step parent descendants next _ nextRule member ih =>
      rcases ih with rfl | ⟨child, childMember, reached⟩
      · have equal := Option.some.inj (found.symm.trans nextRule)
        subst descendants
        exact Or.inr ⟨next, member, .refl⟩
      · exact Or.inr ⟨child, childMember, .step reached nextRule member⟩
  intro atom reached
  rcases first atom reached with rfl | ⟨child, member, reached⟩
  · exact ⟨children, found⟩
  · exact safe child member atom reached

end Traits
namespace Source.Machine
namespace CloneTraits
open ReferenceContracts ReferenceStructureContracts

theorem checked_context_internal_valid (context : Context) (schema : SchemaId .source) (inner : Internal .source)
    (typed : context.typingValid = true) (found : context.source.schemas[schema.value]? = some (.internal inner)) :
    Admission.internalValid context.source inner = true := by
  simp only [Context.typingValid, Option.any_eq_true] at typed
  obtain ⟨results, _, admitted⟩ := typed
  have declarations := (Admission.typed_checks_all_declarations _ _ _ _ admitted).1
  simp only [Admission.declarationsValid, Bool.and_eq_true] at declarations
  exact List.all_eq_true.mp declarations.1.1.2 _ (List.mem_of_getElem? found)

theorem borrowed_is_not_cloneable (context : Context) (schema resource : SchemaId .source) (region : RegionId .source)
    (typed : context.typingValid = true)
    (found : context.source.schemas[schema.value]? = some (.internal (.borrowed resource region))) :
    ¬ Traits.Safe context.source.schemas (schema, .clone) := by
  intro safe
  have admitted := checked_context_internal_valid context schema _ typed found
  have childSafe : Traits.Safe context.source.schemas (resource, .clone) := by
    apply safe.reachable
    apply Traits.Reach.step .refl
      (show Traits.rule context.source.schemas (schema, .clone) = some [(resource, .clone)] by
        simp [Traits.rule, found, Traits.premises])
    simp
  obtain ⟨children, childRule⟩ := childSafe _ .refl
  simp only [Admission.internalValid, DeclarationAdmission.internalValid, Bool.and_eq_true] at admitted
  have present := admitted.2
  simp only [DeclarationAdmission.resourceDescriptor, DeclarationAdmission.shape, Admission.declarationContext] at present
  cases resourceAt : context.source.schemas[resource.value]? with
  | none => simp [resourceAt] at present
  | some shape =>
    cases shape <;> simp [resourceAt] at present
    rename_i inner
    cases inner <;> simp at present
    simp [Traits.rule, resourceAt, Traits.premises] at childRule

/-- A safe clone node is a live heap object with a compatible source schema
whose clone trait follows from that catalog. -/
def NodeSafe (source : Module) (heap : Heap) (node : NodeId) : Prop :=
  ∃ schema stored, heap.lookup node = some stored ∧ Matches source.schemas schema stored ∧
    Traits.Safe source.schemas (schema, .clone)

theorem references_nodes (property : NodeId → Prop) (value : SemanticValue)
    (holds : Primitives.ReferencesSatisfy (fun _ node _ => property node) value) :
    ∀ node ∈ valueReferences value, property node := by
  cases value with
  | scalar _ _ | blob _ _ => simp [valueReferences]
  | reference schema node token => simpa only [valueReferences, List.mem_singleton, forall_eq, Primitives.ReferencesSatisfy] using holds
  | product schema fields | sequence schema fields =>
    simp only [Primitives.ReferencesSatisfy] at holds
    intro node member
    simp only [valueReferences] at member
    obtain ⟨child, childMember, member⟩ := List.mem_flatMap.mp member
    exact references_nodes property child (holds child childMember) node member
  | variant schema tag payload =>
    simpa only [valueReferences] using references_nodes property payload
      (by simpa only [Primitives.ReferencesSatisfy] using holds)
termination_by sizeOf value
decreasing_by
  all_goals subst value
  all_goals simp_wf
  all_goals first | omega | exact Nat.lt_trans (List.sizeOf_lt_of_mem childMember) (by omega)

theorem value_nodes_safe (source : Module) (heap : Heap) (value : SemanticValue)
    (structured : ValueStructure source.schemas value) (valid : ValueValid source.schemas heap value)
    (safe : Traits.Safe source.schemas (value.schema, .clone)) :
    ∀ node ∈ valueReferences value, NodeSafe source heap node := by
  apply references_nodes
  apply references_transport₂ value _ _ _ (structured.reference_traits .clone safe) valid
  intro schema node token ⟨safe, inner, shape, owned⟩ valid
  have none := copy_reference_has_no_token source.schemas schema inner node token shape
    (safe.clone_implies_copy _ _) owned
  have usable : Usable heap.custody token := by simp [none, Usable]
  obtain ⟨stored, found, compatible⟩ := valid usable
  exact ⟨schema, stored, found, compatible, safe⟩

end CloneTraits
end Source.Machine
end BoundaryV2.Profile
