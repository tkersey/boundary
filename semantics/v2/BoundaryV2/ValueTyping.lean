import BoundaryV2.Primitives

namespace BoundaryV2.Profile.Value

/-- Finite value typing leaves graph references to the machine's heap relation.
It neither unfolds a referenced object nor requires an acyclic heap or schema
catalog. Scalar, byte, and container constraints use the actual value rules. -/
inductive Typed (schemas : List (Schema space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop) :
    Value space → Prop where
  | scalar {id : SchemaId space} : schemas[id.value]? = some shape → scalarValid shape number = true →
      Typed schemas references (.scalar id number)
  | blob {id : SchemaId space} : schemas[id.value]? = some shape → blobValid shape bytes = true →
      Typed schemas references (.blob id bytes)
  | product {id : SchemaId space} : schemas[id.value]? = some (.product types) → types = fields.map schema →
      (∀ child ∈ fields, Typed schemas references child) → Typed schemas references (.product id fields)
  | variant {id : SchemaId space} : schemas[id.value]? = some (.sum alternatives) → tag < wordLimit →
      alternatives[tag]? = some payload.schema → Typed schemas references payload →
      Typed schemas references (.variant id tag payload)
  | sequence {id : SchemaId space} : schemas[id.value]? = some shape → sequenceLengthValid shape fields.length = true →
      (∀ child ∈ fields, sequenceElement shape = some child.schema) →
      (∀ child ∈ fields, Typed schemas references child) →
      Typed schemas references (.sequence id fields)
  | reference {id : SchemaId space} : schemas[id.value]? = some (.internal inner) → references id inner node token →
      Typed schemas references (.reference id node token)

/-- Actual external tree admission supplies the full finite typing derivation;
the reference relation is irrelevant because no such leaf is admitted. -/
theorem treeValid_typed (schemas : List (Schema space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (value : Value space) (accepted : treeValid schemas value = true) : Typed schemas references value := by
  cases value with
  | scalar id number =>
    simp only [treeValid] at accepted
    split at accepted
    · exact .scalar (by assumption) accepted
    · contradiction
  | blob id bytes =>
    simp only [treeValid] at accepted
    split at accepted
    · exact .blob (by assumption) accepted
    · contradiction
  | product id fields =>
    simp only [treeValid] at accepted
    split at accepted
    · rename_i types found
      have checked := Bool.and_eq_true_iff.mp accepted
      refine .product found (by simpa using checked.1) ?_
      intro child member
      exact treeValid_typed schemas references child
        (List.all_eq_true.mp checked.2 ⟨child, member⟩ (List.mem_attach ..))
    · contradiction
  | variant id tag payload =>
    simp only [treeValid] at accepted
    split at accepted
    · have checked := Bool.and_eq_true_iff.mp accepted
      have header := Bool.and_eq_true_iff.mp checked.1
      exact .variant (by assumption) (by simpa using header.1) (by simpa using header.2)
        (treeValid_typed schemas references payload checked.2)
    · contradiction
  | sequence id fields =>
    simp only [treeValid] at accepted
    split at accepted
    · have checked := Bool.and_eq_true_iff.mp accepted
      refine .sequence (by assumption) checked.1 ?_ ?_
      · intro child member
        have item := Bool.and_eq_true_iff.mp (List.all_eq_true.mp checked.2 ⟨child, member⟩ (List.mem_attach ..))
        simpa using item.1
      · intro child member
        have item := Bool.and_eq_true_iff.mp (List.all_eq_true.mp checked.2 ⟨child, member⟩ (List.mem_attach ..))
        exact treeValid_typed schemas references child item.2
    · contradiction
  | reference id node token => simp [treeValid] at accepted
termination_by sizeOf value
decreasing_by
  all_goals subst value
  all_goals simp_wf
  all_goals first | omega | exact Nat.lt_trans (List.sizeOf_lt_of_mem member) (by omega)

variable {schemas : List (Schema space)}
    {references other : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop}
    {value : Value space}

theorem Typed.references_mono (typed : Typed schemas references value)
    (implies : ∀ id inner node token, references id inner node token → other id inner node token) :
    Typed schemas other value := by
  induction typed with
  | scalar found checked => exact .scalar found checked
  | blob found checked => exact .blob found checked
  | product found exactTypes _ induction => exact .product found exactTypes induction
  | variant found bounded exactType _ induction => exact .variant found bounded exactType induction
  | sequence found bounded exactTypes _ induction =>
    exact .sequence found bounded exactTypes induction
  | reference found checked => exact .reference found (implies _ _ _ _ checked)

/-- Every reference leaf inherits the structural trait of the complete value.
Unused sum alternatives remain governed by the trait checker; this theorem
does not replace that check with a walk of the selected payload alone. -/
theorem Typed.reference_traits (typed : Typed schemas references value) (kind : Traits.Kind)
    (safe : Traits.Safe schemas (value.schema, kind)) :
    Primitives.ReferencesSatisfy (fun id node token =>
      Traits.Safe schemas (id, kind) ∧ ∃ inner,
        schemas[id.value]? = some (.internal inner) ∧ references id inner node token) value := by
  induction typed with
  | scalar found checked => simp [Primitives.ReferencesSatisfy]
  | blob found checked => simp [Primitives.ReferencesSatisfy]
  | @product types fields id found exactTypes checked induction =>
    simp only [Primitives.ReferencesSatisfy, schema] at safe ⊢
    intro child member
    apply induction child member
    apply safe.reachable
    apply Traits.Reach.step Traits.Reach.refl
      (show Traits.rule schemas (id, kind) = some (types.map (·, kind)) by
        simp [Traits.rule, found, Traits.premises])
    exact List.mem_map.mpr ⟨child.schema, exactTypes ▸ List.mem_map.mpr ⟨child, member, rfl⟩, rfl⟩
  | @variant alternatives tag payload id found bounded exactType checked induction =>
    simp only [Primitives.ReferencesSatisfy, schema] at safe ⊢
    apply induction
    apply safe.reachable
    apply Traits.Reach.step Traits.Reach.refl
      (show Traits.rule schemas (id, kind) = some (alternatives.map (·, kind)) by
        simp [Traits.rule, found, Traits.premises])
    exact List.mem_map.mpr ⟨payload.schema, List.mem_of_getElem? exactType, rfl⟩
  | @sequence shape fields id found bounded exactTypes checked induction =>
    simp only [Primitives.ReferencesSatisfy, schema] at safe ⊢
    intro child member
    apply induction child member
    have element := exactTypes child member
    apply safe.reachable
    apply Traits.Reach.step Traits.Reach.refl
      (show Traits.rule schemas (id, kind) = some [(child.schema, kind)] by
        cases shape <;> simp_all [sequenceElement, Traits.rule, Traits.premises])
    simp
  | reference found checked =>
    simp only [Primitives.ReferencesSatisfy, schema] at safe ⊢
    exact ⟨safe, _, found, checked⟩

theorem Typed.scalar_schema_is_not_a_reference (id : SchemaId space)
    (found : schemas[id.value]? = some .unit) (typed : Typed schemas references (.reference id node token)) : False := by
  cases typed with
  | reference shape _ => simp [found] at shape

end BoundaryV2.Profile.Value
