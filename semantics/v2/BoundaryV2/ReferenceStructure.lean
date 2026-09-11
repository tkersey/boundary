import BoundaryV2.PrimitiveEvaluatorTypes

namespace BoundaryV2.Profile.Value

/-- Catalog paths from an aggregate to each reference leaf. Scalar payload,
byte encoding, and container wire bounds are separate obligations: they do not
change which reference traits follow from the enclosing schema. -/
inductive ReferenceStructure (schemas : List (Schema space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop) :
    Value space → Prop where
  | scalarAny {id : SchemaId space} : ReferenceStructure schemas references (.scalar id number)
  | blobAny {id : SchemaId space} : ReferenceStructure schemas references (.blob id bytes)
  | product {id : SchemaId space} : schemas[id.value]? = some (.product types) → types = fields.map schema →
      (∀ child ∈ fields, ReferenceStructure schemas references child) →
      ReferenceStructure schemas references (.product id fields)
  | variantAny {id : SchemaId space} : schemas[id.value]? = some (.sum alternatives) →
      alternatives[tag]? = some payload.schema → ReferenceStructure schemas references payload →
      ReferenceStructure schemas references (.variant id tag payload)
  | sequenceAny {id : SchemaId space} : schemas[id.value]? = some shape →
      (∀ child ∈ fields, sequenceElement shape = some child.schema) →
      (∀ child ∈ fields, ReferenceStructure schemas references child) →
      ReferenceStructure schemas references (.sequence id fields)
  | reference {id : SchemaId space} : schemas[id.value]? = some (.internal inner) → references id inner node token →
      ReferenceStructure schemas references (.reference id node token)

namespace ReferenceStructure

variable {id : SchemaId space} {fields remaining : List (Value space)} {payload : Value space}

variable {schemas : List (Schema space)}
    {references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop}

/-- The finite typing judgment implies this reference-only structural fact. -/
theorem of_typed (typed : Typed schemas references value) : ReferenceStructure schemas references value := by
  induction typed with
  | scalar => exact .scalarAny
  | blob => exact .blobAny
  | product found types _ ih => exact .product found types ih
  | variant found _ selected _ ih => exact .variantAny found selected ih
  | sequence found _ types _ ih => exact .sequenceAny found types ih
  | reference found checked => exact .reference found checked

theorem scalar (_found : schemas[id.value]? = some shape) (_checked : scalarValid shape number = true) :
    ReferenceStructure schemas references (.scalar id number) := .scalarAny

theorem blob (_found : schemas[id.value]? = some shape) (_checked : blobValid shape bytes = true) :
    ReferenceStructure schemas references (.blob id bytes) := .blobAny

theorem variant (found : schemas[id.value]? = some (.sum alternatives)) (_bounded : tag < wordLimit)
    (selected : alternatives[tag]? = some payload.schema) (child : ReferenceStructure schemas references payload) :
    ReferenceStructure schemas references (.variant id tag payload) := .variantAny found selected child

theorem sequence (found : schemas[id.value]? = some shape) (_bounded : sequenceLengthValid shape fields.length = true)
    (types : ∀ child ∈ fields, sequenceElement shape = some child.schema)
    (children : ∀ child ∈ fields, ReferenceStructure schemas references child) :
    ReferenceStructure schemas references (.sequence id fields) := .sequenceAny found types children

theorem product_children (typed : ReferenceStructure schemas references (.product id fields)) :
    ∀ child ∈ fields, ReferenceStructure schemas references child := by
  cases typed with | product _ _ children => exact children

theorem sequence_children (typed : ReferenceStructure schemas references (.sequence id fields)) :
    ∀ child ∈ fields, ReferenceStructure schemas references child := by
  cases typed with | sequenceAny _ _ children => exact children

theorem variant_payload (typed : ReferenceStructure schemas references (.variant id tag payload)) :
    ReferenceStructure schemas references payload := by
  cases typed with | variantAny _ _ child => exact child

theorem subset_sequence (typed : ReferenceStructure schemas references (.sequence id fields))
    (members : ∀ child ∈ remaining, child ∈ fields) :
    ReferenceStructure schemas references (.sequence id remaining) := by
  cases typed with
  | sequenceAny found types children =>
    exact .sequenceAny found (fun child member => types child (members child member))
      (fun child member => children child (members child member))
theorem reference_traits (typed : ReferenceStructure schemas references value) (kind : Traits.Kind)
    (safe : Traits.Safe schemas (value.schema, kind)) :
    Primitives.ReferencesSatisfy (fun id node token =>
      Traits.Safe schemas (id, kind) ∧ ∃ inner,
        schemas[id.value]? = some (.internal inner) ∧ references id inner node token) value := by
  induction typed with
  | scalarAny => simp [Primitives.ReferencesSatisfy]
  | blobAny => simp [Primitives.ReferencesSatisfy]
  | @product types fields id found exactTypes checked induction =>
    simp only [Primitives.ReferencesSatisfy, schema] at safe ⊢
    intro child member
    apply induction child member
    apply safe.reachable
    apply Traits.Reach.step Traits.Reach.refl
      (show Traits.rule schemas (id, kind) = some (types.map (·, kind)) by
        simp [Traits.rule, found, Traits.premises])
    exact List.mem_map.mpr ⟨child.schema, exactTypes ▸ List.mem_map.mpr ⟨child, member, rfl⟩, rfl⟩
  | @variantAny alternatives tag payload id found exactType checked induction =>
    simp only [Primitives.ReferencesSatisfy, schema] at safe ⊢
    apply induction
    apply safe.reachable
    apply Traits.Reach.step Traits.Reach.refl
      (show Traits.rule schemas (id, kind) = some (alternatives.map (·, kind)) by
        simp [Traits.rule, found, Traits.premises])
    exact List.mem_map.mpr ⟨payload.schema, List.mem_of_getElem? exactType, rfl⟩
  | @sequenceAny shape fields id found exactTypes checked induction =>
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


end ReferenceStructure
end BoundaryV2.Profile.Value
