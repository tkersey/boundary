import BoundaryV2.GeneralizedTypes

namespace BoundaryV2.Generalized

def BodyType.type (body : BodyType Data Effect) : Ty Data Effect := .computation body.use body.parameters body.result

def resumedType (mode : Mode) (body answer : Ty Data Effect) : Ty Data Effect :=
  match mode with | .deep => answer | .shallow => body

namespace Source

/- Authored lexical bodies remain syntax in the source calculus. Evaluation
will form closures and use higher-order response/context composition. -/
mutual
  inductive Expression (signature : Signature) (algebra : LeafAlgebra signature.Data)
      (definitions : List (BodyType signature.Data signature.Effect)) :
      List (TypeOf signature) → TypeOf signature → Type where
    | datum : Datum algebra type → Expression signature algebra definitions context type
    | reference : Variable context type → Expression signature algebra definitions context type
    | pair : Expression signature algebra definitions context left → Expression signature algebra definitions context right →
      Expression signature algebra definitions context (.product left right)
    | first : Expression signature algebra definitions context (.product left right) → Expression signature algebra definitions context left
    | second : Expression signature algebra definitions context (.product left right) → Expression signature algebra definitions context right
    | left : Expression signature algebra definitions context left → Expression signature algebra definitions context (.sum left right)
    | right : Expression signature algebra definitions context right → Expression signature algebra definitions context (.sum left right)
    | primitive : algebra.operation parameters result → Arguments signature algebra definitions context (parameters.map Ty.leaf) →
      Expression signature algebra definitions context (.leaf result)
    | lambda : Selection context captured → Computation signature algebra definitions (parameters ++ captured) result →
      Expression signature algebra definitions context (.computation use parameters result)

  inductive Arguments (signature : Signature) (algebra : LeafAlgebra signature.Data)
      (definitions : List (BodyType signature.Data signature.Effect)) :
      List (TypeOf signature) → List (TypeOf signature) → Type where
    | nil : Arguments signature algebra definitions context []
    | cons : Expression signature algebra definitions context type → Arguments signature algebra definitions context rest →
      Arguments signature algebra definitions context (type :: rest)

  inductive Computation (signature : Signature) (algebra : LeafAlgebra signature.Data)
      (definitions : List (BodyType signature.Data signature.Effect)) :
      List (TypeOf signature) → TypeOf signature → Type where
    | returnValue : Expression signature algebra definitions context type → Computation signature algebra definitions context type
    | bind : Computation signature algebra definitions context input → Computation signature algebra definitions (input :: context) result →
      Computation signature algebra definitions context result
    | apply : Expression signature algebra definitions context (.computation use parameters result) →
      Arguments signature algebra definitions context parameters → Computation signature algebra definitions context result
    | call : Variable definitions body → Arguments signature algebra definitions context body.parameters →
      Computation signature algebra definitions context body.result
    | primitive : algebra.operation parameters result → Arguments signature algebra definitions context (parameters.map Ty.leaf) →
      Computation signature algebra definitions context (.leaf result)
    | matchSum : Expression signature algebra definitions context (.sum left right) →
      Computation signature algebra definitions (left :: context) result → Computation signature algebra definitions (right :: context) result →
      Computation signature algebra definitions context result
    | perform : (operation : signature.operation effect) → Expression signature algebra definitions context (.capability effect) →
      Expression signature algebra definitions context (signature.payload operation) →
      Arguments signature algebra definitions context ((signature.bodies operation).map BodyType.type) →
      Computation signature algebra definitions context (signature.result operation)
    | handle : (effect : signature.Effect) → (mode : Mode) →
      Computation signature algebra definitions (body :: context) answer →
      Clauses signature algebra definitions effect mode context body answer →
      Computation signature algebra definitions (.capability effect :: context) body →
      Computation signature algebra definitions context answer
    | resume : Expression signature algebra definitions context (.continuation mode use effect input result) →
      Expression signature algebra definitions context input → Computation signature algebra definitions context result
    | resumeWith : (effect : signature.Effect) →
      Expression signature algebra definitions context (.continuation .shallow use effect input body) →
      Expression signature algebra definitions context input →
      Computation signature algebra definitions (body :: context) answer →
      Clauses signature algebra definitions effect .deep context body answer → Computation signature algebra definitions context answer
    | inject : Expression signature algebra definitions context (.continuation mode use effect input result) →
      Expression signature algebra definitions context (.computation useBody [] input) → Computation signature algebra definitions context result
    | withRegion : Computation signature algebra definitions (.region :: context) result → Computation signature algebra definitions context result
    | cellNew : Expression signature algebra definitions context .region → Expression signature algebra definitions context value →
      Computation signature algebra definitions context (.cell value)
    | cellRead : Expression signature algebra definitions context (.cell value) → Computation signature algebra definitions context value
    | cellWrite : Expression signature algebra definitions context (.cell value) → Expression signature algebra definitions context value →
      Computation signature algebra definitions context .unit
    | protect : Computation signature algebra definitions (.exit :: context) .unit →
      Computation signature algebra definitions context result → Computation signature algebra definitions context result
    | dispose : Expression signature algebra definitions context (.continuation mode use effect input result) →
      Computation signature algebra definitions context .unit
    | clone : Expression signature algebra definitions context (.continuation mode use effect input result) →
      Computation signature algebra definitions context (.continuation mode .multi effect input result)
    | package : Expression signature algebra definitions context value → Computation signature algebra definitions context (.package value)
    | unpackage : Expression signature algebra definitions context (.package value) → Computation signature algebra definitions context value
    | fail : algebra.Fault → Computation signature algebra definitions context result
    | yieldThen : Computation signature algebra definitions context result → Computation signature algebra definitions context result

  /-- A finite authored handler handles named operations. Unlisted operations
  remain forwardable even when the surrounding signature is infinite. -/
  inductive Clauses (signature : Signature) (algebra : LeafAlgebra signature.Data)
      (definitions : List (BodyType signature.Data signature.Effect)) :
      (effect : signature.Effect) → Mode → List (TypeOf signature) → TypeOf signature → TypeOf signature → Type where
    | nil : Clauses signature algebra definitions effect mode context body answer
    | cons : (operation : signature.operation effect) → (use : Use) →
      Computation signature algebra definitions
        (.continuation mode use effect (signature.result operation) (resumedType mode body answer) ::
          signature.payload operation :: (signature.bodies operation).map BodyType.type ++ context) answer →
      Clauses signature algebra definitions effect mode context body answer →
      Clauses signature algebra definitions effect mode context body answer
end

/-- Recursive calls name positions in this finite table. The bodies contain
ordinary recursive references; no evaluation horizon belongs to the syntax. -/
abbrev Definitions (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (signatures : List (BodyType signature.Data signature.Effect)) :=
  Tuple (fun body => Computation signature algebra signatures body.parameters body.result) signatures

end Source
end BoundaryV2.Generalized
