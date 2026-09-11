import BoundaryV2.SourceCaptureTypes
import BoundaryV2.SourceValueInventory
import BoundaryV2.ValueTyping
import BoundaryV2.TraitImplications

namespace BoundaryV2.Profile.Source.Machine

/-- Reference ownership follows the source allocators. A reusable resumption
is selected by its multi use mode; a computation is selected by the derived
copy trait. This component does not resolve historical handles in the heap. -/
def ReferenceOwnership (schemas : List (Schema .source)) (schema : SchemaId .source)
    (inner : Internal .source) (_node : NodeId) (token : Option CustodyToken) : Prop :=
  match inner with
  | .computation _ => token.isSome = !Traits.check schemas .copy schema
  | .resumption signature => token.isSome = (signature.use != .multi)
  | .suspensionPackage _ | .abstractResource _ => token.isSome = true
  | .capability _ | .region _ | .cell _ _ | .borrowed _ _ => token = none

/-- Finite source value typing, including the ownership mode of every nested
reference. Live-object compatibility, custody, scopes, and obligations are
separate state components. -/
def ValueShape (schemas : List (Schema .source)) : SemanticValue → Prop :=
  Profile.Value.Typed schemas (ReferenceOwnership schemas)

theorem external_value_has_shape (schemas : List (Schema .source)) (value : SemanticValue)
    (accepted : Profile.Value.externalValid schemas value = true) : ValueShape schemas value :=
  Profile.Value.treeValid_typed schemas _ value (Bool.and_eq_true_iff.mp accepted).2

theorem copy_reference_has_no_token (schemas : List (Schema .source)) (schema : SchemaId .source)
    (inner : Internal .source) (node : NodeId) (token : Option CustodyToken)
    (shape : schemas[schema.value]? = some (.internal inner))
    (safe : Traits.Safe schemas (schema, .copy))
    (owned : ReferenceOwnership schemas schema inner node token) : token = none := by
  have checked := Traits.check_complete schemas .copy schema safe
  obtain ⟨children, rule⟩ := safe _ .refl
  cases inner with
  | computation signature =>
    simp only [ReferenceOwnership, checked, Bool.not_true, Option.isSome_eq_false_iff] at owned
    simpa using owned
  | resumption signature =>
    have multi : signature.use = .multi := by
      simp only [Traits.rule, shape, bind, Option.bind_some, Traits.premises] at rule
      split at rule <;> try contradiction
      simp only [show (Traits.Kind.copy == Traits.Kind.drop) = false from rfl, Bool.false_eq_true, ↓reduceIte] at rule
      split at rule <;> try contradiction
      simpa using ‹(signature.use == .multi) = true›
    simpa [ReferenceOwnership, multi] using owned
  | suspensionPackage _ => simp [Traits.rule, shape, Traits.premises] at rule
  | abstractResource _ => simp [Traits.rule, shape, Traits.premises] at rule
  | capability _ | region _ | cell _ _ | borrowed _ _ => exact owned

private theorem token_free_references (value : SemanticValue)
    (free : Primitives.ReferencesSatisfy (fun _ _ token => token = none) value) : ownedTokens value = [] := by
  cases value with
  | scalar _ _ | blob _ _ => simp [ownedTokens]
  | reference schema node token => simp only [Primitives.ReferencesSatisfy] at free; simp [ownedTokens, free]
  | product schema fields | sequence schema fields =>
    simp only [Primitives.ReferencesSatisfy] at free
    simp only [ownedTokens, List.flatMap_eq_nil_iff]
    exact fun child member => token_free_references child (free child member)
  | variant schema tag payload =>
    simpa only [ownedTokens] using token_free_references payload (by simpa only [Primitives.ReferencesSatisfy] using free)
termination_by sizeOf value
decreasing_by
  all_goals subst value
  all_goals simp_wf
  all_goals first | omega | exact Nat.lt_trans (List.sizeOf_lt_of_mem member) (by omega)

private theorem references_mono (value : SemanticValue)
    (first second : SchemaId .source → NodeId → Option CustodyToken → Prop)
    (holds : Primitives.ReferencesSatisfy first value)
    (implies : ∀ schema node token, first schema node token → second schema node token) :
    Primitives.ReferencesSatisfy second value := by
  cases value with
  | scalar _ _ | blob _ _ => simp [Primitives.ReferencesSatisfy]
  | reference schema node token =>
    simp only [Primitives.ReferencesSatisfy] at holds ⊢
    exact implies schema node token holds
  | product schema fields | sequence schema fields =>
    simp only [Primitives.ReferencesSatisfy] at holds ⊢
    exact fun child member => references_mono child first second (holds child member) implies
  | variant schema tag payload =>
    simpa only [Primitives.ReferencesSatisfy] using references_mono payload first second
      (by simpa only [Primitives.ReferencesSatisfy] using holds) implies
termination_by sizeOf value
decreasing_by
  all_goals subst value
  all_goals simp_wf
  all_goals first | omega | exact Nat.lt_trans (List.sizeOf_lt_of_mem member) (by omega)

/-- A typed copy-safe value cannot carry exclusive tokens, even inside a
recursive product, selected sum payload, or container. -/
theorem copy_value_has_no_tokens (schemas : List (Schema .source)) (value : SemanticValue)
    (typed : ValueShape schemas value) (safe : Traits.Safe schemas (value.schema, .copy)) :
    ownedTokens value = [] := by
  have inherited := Profile.Value.Typed.reference_traits typed .copy safe
  apply token_free_references value
  apply references_mono value _ _ inherited
  intro schema node token ⟨safe, inner, shape, owned⟩
  exact copy_reference_has_no_token schemas schema inner node token shape safe owned

theorem clone_value_has_no_tokens (schemas : List (Schema .source)) (value : SemanticValue)
    (typed : ValueShape schemas value) (safe : Traits.Safe schemas (value.schema, .clone)) :
    ownedTokens value = [] :=
  copy_value_has_no_tokens schemas value typed (safe.clone_implies_copy schemas value.schema)

theorem renaming_preserves_value_schema (mapping : Renaming) (value : SemanticValue) :
    (renameValue mapping value).schema = value.schema := by
  cases value <;> simp [renameValue, Profile.Value.schema]

theorem renaming_preserves_value_shape (schemas : List (Schema .source)) (mapping : Renaming)
    (value : SemanticValue) (typed : ValueShape schemas value) : ValueShape schemas (renameValue mapping value) := by
  induction typed with
  | scalar found checked => simpa only [renameValue, ValueShape] using Profile.Value.Typed.scalar found checked
  | blob found checked => simpa only [renameValue, ValueShape] using Profile.Value.Typed.blob found checked
  | product found exactTypes _ induction =>
    simp only [renameValue]
    apply Profile.Value.Typed.product found
    · simpa only [List.map_map, Function.comp_def, renaming_preserves_value_schema] using exactTypes
    · intro child member
      obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
      exact induction original originalMember
  | variant found bounded exactType _ induction =>
    simp only [renameValue]
    exact .variant found bounded (by simpa only [renaming_preserves_value_schema] using exactType) induction
  | sequence found bounded exactTypes _ induction =>
    simp only [renameValue]
    apply Profile.Value.Typed.sequence found (by simpa only [List.length_map] using bounded)
    · intro child member
      obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
      simpa only [renaming_preserves_value_schema] using exactTypes original originalMember
    · intro child member
      obtain ⟨original, originalMember, rfl⟩ := List.mem_map.mp member
      exact induction original originalMember
  | reference found owned =>
    simp only [renameValue]
    exact .reference found owned

theorem created_copy_closure_has_no_owned_captures (state : State) (context : Context)
    (schema : SchemaId .source) (function : FunctionId .source) (values : List Located) (after : Transition)
    (signature : ComputationType .source)
    (accepted : makeClosureWithValues state context schema function values = .ok after)
    (admitted : Admission.lambdaValid context.source context.captures function schema = true)
    (shape : context.source.schemas[schema.value]? = some (.internal (.computation signature)))
    (copy : Traits.check context.source.schemas .copy schema = true)
    (typed : ∀ value ∈ values, ValueShape context.source.schemas value.value) :
    ∀ value ∈ values, ownedTokens value.value = [] := by
  have captures := created_closure_capture_traits state context schema function values after signature .copy
    accepted admitted shape (Traits.check_sound _ _ _ copy)
  exact fun value member => copy_value_has_no_tokens _ _ (typed value member) (captures value member)

theorem initial_value_shapes (context : Context) (arguments : List SemanticValue) (state : State)
    (accepted : initial context arguments = .ok state) :
    ValueInventory.All (ValueShape context.source.schemas) state := by
  apply ValueInventory.initial_all context arguments state accepted
  intro value member
  exact external_value_has_shape _ _ ((initialization_checks_external_arguments context arguments state accepted) value member)

theorem external_preserves_value_shapes (state : State) (context : Context) (action : External)
    (after : Transition) (accepted : external state context action = .ok after)
    (typed : ValueInventory.All (ValueShape context.source.schemas) state) :
    ValueInventory.All (ValueShape context.source.schemas) after.state :=
  ValueInventory.external_preserves_all state context action after accepted _ typed
    (fun value checked => external_value_has_shape _ value checked)

theorem computation_allocation_value_shape (heap after : Heap) (schemas : List (Schema .source))
    (schema : SchemaId .source) (signature : ComputationType .source) (function : FunctionId .source)
    (environment : Environment) (owner : Custody.Owner) (value : Located)
    (shape : schemas[schema.value]? = some (.internal (.computation signature)))
    (accepted : allocateObject heap schema (.closure schema function environment) owner
      (!Traits.check schemas .copy schema) = some (after, value)) : ValueShape schemas value.value := by
  cases checked : Traits.check schemas .copy schema <;>
    simp [allocateObject, checked, Option.bind_eq_some_iff] at accepted
  · obtain ⟨_, _, _, equal⟩ := accepted
    cases equal
    exact .reference shape (by simp [ReferenceOwnership, checked])
  · obtain ⟨_, equal⟩ := accepted
    cases equal
    exact .reference shape (by simp [ReferenceOwnership, checked])

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem closure_creation_preserves_value_shapes (state : State) (context : Context)
    (schema : SchemaId .source) (signature : ComputationType .source) (function : FunctionId .source)
    (values : List Located) (after : Transition)
    (shape : context.source.schemas[schema.value]? = some (.internal (.computation signature)))
    (accepted : makeClosureWithValues state context schema function values = .ok after)
    (typed : ValueInventory.All (ValueShape context.source.schemas) state)
    (inputs : ∀ value ∈ values, ValueShape context.source.schemas value.value) :
    ValueInventory.All (ValueShape context.source.schemas) after.state := by
  simp only [makeClosureWithValues, bind, except_bind_ok, fromOption_ok] at accepted
  obtain ⟨_, _, ⟨middle, owner⟩, temporaryAccepted, moved, moveAccepted, ⟨heap, result⟩, allocated, finished⟩ := accepted
  have middleTyped := ValueInventory.temporary_preserves_all _ _ _ temporaryAccepted _ typed
  have movedTyped := ValueInventory.moveValues_preserves_all _ _ _ _ moveAccepted _ middleTyped
  have storedTyped : ∀ child ∈ ValueInventory.object (.closure schema function
      (((Analysis.captures context.captures function).zip values).mapIdx (fun index (binder, value) =>
        Binding.mk binder (retainAt value (.closure ⟨middle.heap.objects.length⟩ index))))),
      ValueShape context.source.schemas child := by
    intro child member
    simp only [ValueInventory.object, ValueInventory.environment, List.mapIdx_eq_zipIdx_map,
      List.map_map, Function.comp_def, List.mem_map, retainAt] at member
    obtain ⟨⟨⟨binder, value⟩, index⟩, pairMember, rfl⟩ := member
    exact inputs value (List.of_mem_zip (List.fst_mem_of_mem_zipIdx pairMember)).2
  have allocatedTyped := ValueInventory.allocateObject_preserves_all _ _ _ _ _ _ _ allocated _ movedTyped storedTyped
  have resultTyped := computation_allocation_value_shape _ _ _ _ signature _ _ _ _ shape allocated
  exact ValueInventory.finishTemporary_preserves_all _ _ _ finished _ allocatedTyped resultTyped

end BoundaryV2.Profile.Source.Machine
