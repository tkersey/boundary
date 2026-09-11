import BoundaryV2.DeclarationAdmission
import BoundaryV2.SchemaAdmission
import BoundaryV2.FiniteDependency

namespace BoundaryV2.Profile.DependencyAdmission

structure Context (space : Space) where
  schemas : List (Schema space)
  effectCount : Nat
  ambient : EffectId space → Bool

def shape (program : Context space) (id : SchemaId space) : Option (Schema space) :=
  program.schemas[id.value]?

def capability (program : Context space) (id : SchemaId space) (effect : EffectId space) : Bool :=
  shape program id == some (.internal (.capability effect))

def schemaIds (program : Context space) : List (SchemaId space) :=
  (List.range program.schemas.length).map (fun index => ⟨index⟩)

def effectDirect (program : Context space) (effect : EffectId space) : Schema space → Bool
  | .internal (.capability family) => family == effect
  | .internal (.computation signature) => signature.effects.contains effect &&
      (program.ambient effect || !signature.parameters.any (fun parameter => capability program parameter effect))
  | .internal (.resumption signature) => signature.effects.contains effect
  | _ => false

def effectChildren : Schema space → List (SchemaId space)
  | .product fields | .sum fields => fields
  | .seq item | .vector item _ | .array item _ => [item]
  | .internal (.cell item _) | .internal (.suspensionPackage item) => [item]
  | .internal (.computation signature) => signature.captureBound ++ [signature.result]
  | .internal (.resumption signature) => [signature.answer]
  | _ => []

def regionDirect (region : RegionId space) : Schema space → Bool
  | .internal (.region owner) | .internal (.cell _ owner) | .internal (.borrowed _ owner) => owner == region
  | _ => false

def regionChildren (region : RegionId space) : Schema space → List (SchemaId space)
  | .product fields | .sum fields => fields
  | .seq item | .vector item _ | .array item _ => [item]
  | .internal (.cell item _) | .internal (.borrowed item _) | .internal (.suspensionPackage item) => [item]
  | .internal (.computation signature) => signature.captureBound
  | .internal (.resumption signature) => if signature.ownedRegions.contains region then [] else signature.captureBound
  | _ => []

def schemaDirect (program : Context space) (direct : Schema space → Bool) (id : SchemaId space) : Bool :=
  (shape program id).any direct

def schemaChildren (program : Context space) (children : Schema space → List (SchemaId space))
    (id : SchemaId space) : List (SchemaId space) := ((shape program id).map children).getD []

/-- The lists contain exactly those schema IDs with no finite dependency path.
They are computed from the full program, never supplied as trusted evidence. -/
def effectSafeSchemas (program : Context space) (effect : EffectId space) : List (SchemaId space) :=
  FiniteDependency.refine (schemaDirect program (effectDirect program effect))
    (schemaChildren program effectChildren) (schemaIds program)

def regionSafeSchemas (program : Context space) (region : RegionId space) : List (SchemaId space) :=
  FiniteDependency.refine (schemaDirect program (regionDirect region))
    (schemaChildren program (regionChildren region)) (schemaIds program)

def EffectDependency (program : Context space) (effect : EffectId space) (id : SchemaId space) : Prop :=
  FiniteDependency.Depends (schemaDirect program (effectDirect program effect))
    (schemaChildren program effectChildren) id

def RegionDependency (program : Context space) (region : RegionId space) (id : SchemaId space) : Prop :=
  FiniteDependency.Depends (schemaDirect program (regionDirect region))
    (schemaChildren program (regionChildren region)) id

theorem schemaIds_member (program : Context space) (id : SchemaId space) :
    id ∈ schemaIds program ↔ id.value < program.schemas.length := by
  cases id
  simp [schemaIds]

theorem schema_references_in_bounds (program : Context space)
    (valid : SchemaAdmission.valid program.schemas = true) (type : Schema space)
    (member : type ∈ program.schemas) :
    ∀ child ∈ SchemaAdmission.references type, child.value < program.schemas.length := by
  simp only [SchemaAdmission.valid, Bool.and_eq_true] at valid
  have checked := List.all_eq_true.mp valid.1.2 type member
  simp only [SchemaAdmission.referencesValid, Bool.and_eq_true] at checked
  simpa only [List.all_eq_true, decide_eq_true_eq] using checked.1

theorem effectChildren_references (type : Schema space) :
    effectChildren type ⊆ SchemaAdmission.references type := by
  cases type <;> simp [effectChildren, SchemaAdmission.references, SchemaAdmission.structuralChildren]
  rename_i inner
  cases inner <;> simp [List.subset_def]
  intro _ member
  exact Or.inr member

theorem regionChildren_references (region : RegionId space) (type : Schema space) :
    regionChildren region type ⊆ SchemaAdmission.references type := by
  cases type <;> simp [regionChildren, SchemaAdmission.references, SchemaAdmission.structuralChildren]
  rename_i inner
  cases inner <;> simp [List.subset_def]
  · intro _ member; exact Or.inr (Or.inl member)
  · intro _ _ member; exact Or.inr (Or.inr member)

theorem schemaChildren_bounded (program : Context space) (children : Schema space → List (SchemaId space))
    (valid : SchemaAdmission.valid program.schemas = true)
    (references : ∀ type, children type ⊆ SchemaAdmission.references type) :
    ∀ id ∈ schemaIds program, ∀ child ∈ schemaChildren program children id, child ∈ schemaIds program := by
  intro id inside child member
  have inBounds := (schemaIds_member program id).mp inside
  let type := program.schemas[id.value]
  have found : program.schemas[id.value]? = some type := by simp [type, inBounds]
  have typed : child ∈ children type := by simpa [schemaChildren, shape, found] using member
  exact (schemaIds_member program child).mpr (schema_references_in_bounds program valid type
    (List.mem_of_getElem? found) child (references type typed))

theorem effectSafe_exact (program : Context space) (effect : EffectId space) (id : SchemaId space)
    (valid : SchemaAdmission.valid program.schemas = true) (inside : id.value < program.schemas.length) :
    id ∈ effectSafeSchemas program effect ↔ ¬ EffectDependency program effect id :=
  FiniteDependency.refine_exact _ _ _
    (schemaChildren_bounded program effectChildren valid effectChildren_references)
    id ((schemaIds_member program id).mpr inside)

theorem regionSafe_exact (program : Context space) (region : RegionId space) (id : SchemaId space)
    (valid : SchemaAdmission.valid program.schemas = true) (inside : id.value < program.schemas.length) :
    id ∈ regionSafeSchemas program region ↔ ¬ RegionDependency program region id :=
  FiniteDependency.refine_exact _ _ _
    (schemaChildren_bounded program (regionChildren region) valid (regionChildren_references region))
    id ((schemaIds_member program id).mpr inside)

structure EffectFacts (space : Space) where
  safe : List (List (SchemaId space))
  ambient : List Bool
  deriving DecidableEq, Repr

def effectFacts (program : Context space) : EffectFacts space :=
  ⟨(List.range program.effectCount).map (fun index => effectSafeSchemas program ⟨index⟩),
   (List.range program.effectCount).map (fun index => program.ambient ⟨index⟩)⟩

def EffectFacts.contains (facts : EffectFacts space) (type : SchemaId space) (effect : EffectId space) : Bool :=
  !(facts.safe[effect.value]?.getD []).contains type

def discharged (facts : EffectFacts space) (handler : Handler space) (body : ComputationType space)
    (effect : EffectId space) : Bool :=
  !facts.ambient[effect.value]?.getD true &&
  !body.captureBound.any (fun type => facts.contains type effect) &&
  !(body.parameters.drop handler.clauses.length).any (fun type => facts.contains type effect) &&
  handler.clauses.any (fun clause => clause.effect == effect)

end BoundaryV2.Profile.DependencyAdmission
