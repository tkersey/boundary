import BoundaryV2.PrimitiveAdmission
import BoundaryV2.ValueCodec

namespace BoundaryV2.Profile.DeclarationAdmission

/-- Declarative schema, effect and resource rules shared by the two profiles.
Control, lexical captures and function bodies remain language-owned. -/
structure Context (space : Space) where
  schemas : List (Schema space)
  resources : List (Resource space)
  effects : List (Effect space)
  functionCount : Nat
  regionCount : Nat

def shape (program : Context space) (id : SchemaId space) : Option (Schema space) :=
  program.schemas[id.value]?

def resourceDescriptor (program : Context space) (id : SchemaId space) : Option (Resource space) := do
  let .internal (.abstractResource resource) ← shape program id | none
  program.resources[resource.value]?

def subset [BEq α] (small large : List α) : Bool := small.all large.contains

def orderedRefs (bound : Nat) (references : List (Ref space domain)) : Bool :=
  references.all (fun reference => reference.value < bound) &&
    decide (references.Pairwise (fun left right => left.value < right.value))

def evidenceRefs (bound : Nat) (references : List (Ref space domain)) : Bool :=
  references.all (fun reference => reference.value < bound) && decide references.Nodup

def computation (program : Context space) (id : SchemaId space) : Option (ComputationType space) := do
  let .internal (.computation signature) ← shape program id | none
  return signature

def resumption (program : Context space) (id : SchemaId space) : Option (ResumptionType space) := do
  let .internal (.resumption signature) ← shape program id | none
  return signature

def capability (program : Context space) (id : SchemaId space) (effect : EffectId space) : Bool :=
  shape program id == some (.internal (.capability effect))

def schemaExists (program : Context space) (id : SchemaId space) : Bool := id.value < program.schemas.length

def resourceValid (program : Context space) (resource : Resource space) : Bool :=
  schemaExists program resource.representation && Traits.check program.schemas .external resource.representation &&
    orderedRefs program.functionCount resource.introducers &&
    orderedRefs program.functionCount resource.eliminators

def internalValid (program : Context space) : Internal space → Bool
  | .capability effect => effect.value < program.effects.length
  | .computation signature =>
    orderedRefs program.effects.length signature.effects &&
    orderedRefs program.regionCount signature.regions &&
    signature.captureBound.all (fun id =>
      (signature.use != .reusable || Traits.check program.schemas .copy id) &&
      (signature.use != .multi || Traits.check program.schemas .clone id))
  | .resumption signature =>
    orderedRefs program.effects.length signature.effects &&
    evidenceRefs program.effects.length signature.handled &&
    orderedRefs program.effects.length signature.escaping &&
    subset signature.escaping signature.effects &&
    (signature.mode != .deep || signature.escaping.isEmpty) &&
    orderedRefs program.regionCount signature.ownedRegions &&
    signature.use != .reusable &&
    (program.effects[signature.effect.value]?).any (fun effect =>
      effect.result == signature.input &&
      (signature.use != .multi || (!signature.obligations && effect.controlUse == .multi &&
        signature.captureBound.all (Traits.check program.schemas .clone))))
  | .region region => region.value < program.regionCount
  | .cell item region => region.value < program.regionCount && Traits.check program.schemas .copy item
  | .suspensionPackage _ => true -- The full schema check validates its owned token type.
  | .abstractResource resource => resource.value < program.resources.length
  | .borrowed resource region => region.value < program.regionCount &&
    (resourceDescriptor program resource).isSome

def effectValid (program : Context space) (effect : Effect space) : Bool :=
  !effect.identity.isEmpty && Profile.UTF8.valid effect.identity &&
  schemaExists program effect.payload && schemaExists program effect.result &&
  Traits.check program.schemas .external effect.result &&
  (!effect.external || (Traits.check program.schemas .external effect.payload && effect.bodies.isEmpty)) &&
  evidenceRefs program.effects.length effect.useSiteEffects &&
  effect.bodies.all (fun body => (computation program body).isSome)

end BoundaryV2.Profile.DeclarationAdmission
