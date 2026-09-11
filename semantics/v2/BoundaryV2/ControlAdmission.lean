import BoundaryV2.DeclarationAdmission

namespace BoundaryV2.Profile.ControlAdmission

structure Context (space : Space) where
  declarations : DeclarationAdmission.Context space
  handlers : List (Handler space)
  failure : SchemaId space

def shape (program : Context space) := DeclarationAdmission.shape program.declarations
def resumption (program : Context space) := DeclarationAdmission.resumption program.declarations
abbrev subset := @DeclarationAdmission.subset

def covers (handler : Handler space) (effect : EffectId space) : Bool :=
  handler.clauses.any (fun clause => clause.effect == effect)

def continuationEffect (program : Context space) (handler : Handler space) (effect : EffectId space)
    (escapes : Bool) : Bool := handler.clauses.all fun clause =>
  (resumption program clause.resumption).any (fun signature =>
    (!(handler.mode == .shallow || escapes) || signature.effects.contains effect) &&
    (!(handler.mode == .shallow && escapes) || signature.escaping.contains effect))

def deepHandlerEffects (program : Context space) (handler : Handler space) : Bool :=
  handler.mode != .deep || handler.clauses.all (fun clause =>
    (resumption program clause.resumption).any (fun signature => subset handler.effects signature.effects))

def capturedRegion (program : Context space) (effects : List (EffectId space)) (region : RegionId space) : Bool :=
  effects.all fun effect => program.handlers.all fun handler => handler.clauses.all fun clause =>
    clause.effect != effect || clause.direct || (resumption program clause.resumption).any
      (fun signature => signature.ownedRegions.contains region)

def cleanupInfoValid (program : Context space) (id : SchemaId space) : Bool := ((do
  let .product [primary, optional, failures] ← shape program id | none
  let .sum [normal, failed, reason, abandoned] ← shape program primary | none
  let .sum [empty, optionalReason] ← shape program optional | none
  let .sum [text, bytes] ← shape program reason | none
  return shape program failures == some (.seq program.failure) && failed == program.failure &&
    reason == optionalReason && normal == abandoned && normal == empty && shape program normal == some .unit &&
    shape program text == some .text && shape program bytes == some .bytes) : Option Bool).getD false

def effectsAllowCleanup (program : Context space) (effects : List (EffectId space)) : Bool :=
  effects.all fun effect =>
    (program.declarations.effects[effect.value]?).any (fun declaration => declaration.controlUse != .multi) &&
    program.handlers.all (fun handler => handler.clauses.all (fun clause =>
      clause.effect != effect || (resumption program clause.resumption).any ResumptionType.obligations))

end BoundaryV2.Profile.ControlAdmission
