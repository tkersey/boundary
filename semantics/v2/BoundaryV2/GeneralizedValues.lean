import BoundaryV2.GeneralizedCompile

namespace BoundaryV2.Generalized

/- Code is an explicit parameter of this pure value container. Source values
carry authored bodies; target values carry only compiled instruction data.
Interpreters and continuation dispatch are deliberately not shared here. -/
mutual
  inductive Value (signature : Signature) (algebra : LeafAlgebra signature.Data)
      (Body : List (TypeOf signature) → TypeOf signature → Type) : TypeOf signature → Type where
    | datum : Datum algebra type → Value signature algebra Body type
    | pair : Value signature algebra Body left → Value signature algebra Body right →
      Value signature algebra Body (.product left right)
    | left : Value signature algebra Body left → Value signature algebra Body (.sum left right)
    | right : Value signature algebra Body right → Value signature algebra Body (.sum left right)
    | closure : Body (parameters ++ captured) result → Environment signature algebra Body captured →
      Option (Id .custody × Owner) → Value signature algebra Body (.computation use parameters result)
    | continuation : Id .control → Option (Id .custody × Owner) →
      Value signature algebra Body (.continuation mode use effect input answer)
    | package : Id .custody → Owner → Value signature algebra Body content → Value signature algebra Body (.package content)
    | cell : Id .cell → Id .region → Value signature algebra Body (.cell type)
    | exit : ExitInfo algebra.Fault algebra.Reason → Value signature algebra Body .exit

  inductive Environment (signature : Signature) (algebra : LeafAlgebra signature.Data)
      (Body : List (TypeOf signature) → TypeOf signature → Type) : List (TypeOf signature) → Type where
    | nil : Environment signature algebra Body []
    | cons : Value signature algebra Body type → Environment signature algebra Body types →
      Environment signature algebra Body (type :: types)
end

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {Body Before After : List (TypeOf signature) → TypeOf signature → Type}
  {context left right types : List (TypeOf signature)} {type : TypeOf signature}
  {codeSignatures : List (BodyType signature.Data signature.Effect)}

def Environment.lookup : {context : List (TypeOf signature)} → {type : TypeOf signature} →
    Variable context type → Environment signature algebra Body context → Value signature algebra Body type
  | _, _, .here, .cons value _ => value
  | _, _, .there reference, .cons _ rest => rest.lookup reference

def Environment.append : {left : List (TypeOf signature)} → Environment signature algebra Body left → Environment signature algebra Body right →
    Environment signature algebra Body (left ++ right)
  | _, .nil, right => right
  | _, .cons value rest, right => .cons value (rest.append right)

mutual
  def Value.map (transform : ∀ context type, Before context type → After context type) :
      {type : TypeOf signature} → Value signature algebra Before type → Value signature algebra After type
    | _, .datum datum => .datum datum
    | _, .pair first second => .pair (first.map transform) (second.map transform)
    | _, .left value => .left (value.map transform)
    | _, .right value => .right (value.map transform)
    | _, .closure body captured authority => .closure (transform _ _ body) (captured.map transform) authority
    | _, .continuation reference authority => .continuation reference authority
    | _, .package token owner content => .package token owner (content.map transform)
    | _, .cell reference region => .cell reference region
    | _, .exit information => .exit information

  def Environment.map (transform : ∀ context type, Before context type → After context type) :
      {types : List (TypeOf signature)} → Environment signature algebra Before types → Environment signature algebra After types
    | _, .nil => .nil
    | _, .cons value rest => .cons (value.map transform) (rest.map transform)
end

theorem Environment.map_append (transform : ∀ context type, Before context type → After context type)
    (first : Environment signature algebra Before left) (second : Environment signature algebra Before right) :
    (first.append second).map transform = (first.map transform).append (second.map transform) := by
  induction left with
  | nil => cases first; rfl
  | cons type types induction =>
    cases first with
    | cons value rest => exact congrArg (Environment.cons (value.map transform)) (induction rest)

theorem Environment.lookup_map (transform : ∀ context type, Before context type → After context type)
    (reference : Variable context type) (environment : Environment signature algebra Before context) :
    (environment.map transform).lookup reference = (environment.lookup reference).map transform := by
  induction reference with
  | here => cases environment; rfl
  | there reference induction => cases environment; exact induction _

/-- A value refers to the authority of its outer objects. Captured object fields
live in their own physical container and are not counted again through a view. -/
def Value.roots : {type : TypeOf signature} → Value signature algebra Body type → List (Id .custody × Owner)
  | _, .datum value => value.support.filterMap fun occurrence => match occurrence with
    | .owned token owner => some (token, owner)
    | _ => none
  | _, .pair first second => first.roots ++ second.roots
  | _, .left value | _, .right value => value.roots
  | _, .closure _ _ authority | _, .continuation _ authority => authority.toList
  | _, .package token owner _ => [(token, owner)]
  | _, .cell _ _ | _, .exit _ => []

def Environment.roots : {types : List (TypeOf signature)} → Environment signature algebra Body types → List (Id .custody × Owner)
  | _, .nil => []
  | _, .cons value rest => value.roots ++ rest.roots

def Datum.retag (owner : Owner) : {type : TypeOf signature} → Datum (Effect := signature.Effect) algebra type → Datum algebra type
  | _, .leaf value => .leaf value
  | _, .unit => .unit
  | _, .pair first second => .pair (first.retag owner) (second.retag owner)
  | _, .left value => .left (value.retag owner)
  | _, .right value => .right (value.retag owner)
  | _, .capability id => .capability id
  | _, .region id => .region id
  | _, .resource id token _ => .resource id token owner
  | _, .borrowed id scope => .borrowed id scope

def Value.retag (owner : Owner) : {type : TypeOf signature} → Value signature algebra Body type → Value signature algebra Body type
  | _, .datum value => .datum (value.retag owner)
  | _, .pair first second => .pair (first.retag owner) (second.retag owner)
  | _, .left value => .left (value.retag owner)
  | _, .right value => .right (value.retag owner)
  | _, .closure body captured authority => .closure body captured (authority.map fun pair => (pair.1, owner))
  | _, .continuation reference authority => .continuation reference (authority.map fun pair => (pair.1, owner))
  | _, .package token _ content => .package token owner content
  | _, .cell reference region => .cell reference region
  | _, .exit information => .exit information

def Environment.retag (owner : Owner) : {types : List (TypeOf signature)} → Environment signature algebra Body types → Environment signature algebra Body types
  | _, .nil => .nil
  | _, .cons value rest => .cons (value.retag owner) (rest.retag owner)

def Environment.select : {selected : List (TypeOf signature)} → Generalized.Selection context selected →
    Environment signature algebra Body context → Environment signature algebra Body selected
  | _, .nil, _ => .nil
  | _, .cons reference rest, values => .cons (values.lookup reference) (values.select rest)

namespace Defunctionalization

abbrev sourceValue (signature : Signature) (algebra : LeafAlgebra signature.Data) (codeSignatures) :=
  Value signature algebra (Source.Computation signature algebra codeSignatures)
abbrev targetValue (signature : Signature) (algebra : LeafAlgebra signature.Data) (codeSignatures) :=
  Value signature algebra (fun context result => Target.Code signature algebra codeSignatures context [] result)

def value (source : sourceValue signature algebra codeSignatures type) : targetValue signature algebra codeSignatures type :=
  source.map (fun _ _ body => computation body)

def environment (source : Environment signature algebra (Source.Computation signature algebra codeSignatures) context) :
    Environment signature algebra (fun context result => Target.Code signature algebra codeSignatures context [] result) context :=
  source.map (fun _ _ body => computation body)

theorem captured_arguments_keep_order
    (arguments : Environment signature algebra (Source.Computation signature algebra codeSignatures) parameters)
    (captured : Environment signature algebra (Source.Computation signature algebra codeSignatures) context) :
    environment (arguments.append captured) = (environment arguments).append (environment captured) :=
  Environment.map_append _ _ _

theorem lexical_lookup_corresponds (reference : Variable context type)
    (bindings : Environment signature algebra (Source.Computation signature algebra codeSignatures) context) :
    (environment bindings).lookup reference = value (bindings.lookup reference) :=
  Environment.lookup_map _ _ _

end Defunctionalization
end BoundaryV2.Generalized
