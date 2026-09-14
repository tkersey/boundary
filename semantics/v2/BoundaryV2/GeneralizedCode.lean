import BoundaryV2.GeneralizedSyntax

namespace BoundaryV2.Generalized.Target

/- First-order instruction and code data. The environment and operand-stack
indices expose argument positions and caller tails; no code field is executable
host control or an instruction to invoke the source evaluator. -/
mutual
  inductive Code (signature : Signature) (algebra : LeafAlgebra signature.Data)
      (definitions : List (BodyType signature.Data signature.Effect)) :
      List (TypeOf signature) → List (TypeOf signature) → TypeOf signature → Type where
    | ret : Code signature algebra definitions context (result :: stack) result
    | push : Datum algebra type → Code signature algebra definitions context (type :: stack) result →
      Code signature algebra definitions context stack result
    | load : Variable context type → Code signature algebra definitions context (type :: stack) result →
      Code signature algebra definitions context stack result
    | pair : Code signature algebra definitions context (.product left right :: stack) result →
      Code signature algebra definitions context (right :: left :: stack) result
    | first : Code signature algebra definitions context (left :: stack) result →
      Code signature algebra definitions context (.product left right :: stack) result
    | second : Code signature algebra definitions context (right :: stack) result →
      Code signature algebra definitions context (.product left right :: stack) result
    | left : Code signature algebra definitions context (.sum left right :: stack) result →
      Code signature algebra definitions context (left :: stack) result
    | right : Code signature algebra definitions context (.sum left right :: stack) result →
      Code signature algebra definitions context (right :: stack) result
    | close : Code signature algebra definitions (parameters ++ captured) [] answer →
      Code signature algebra definitions context (.computation use parameters answer :: stack) result →
      Code signature algebra definitions context (captured.reverse ++ stack) result
    | enter : Code signature algebra definitions (type :: context) stack result →
      Code signature algebra definitions context (type :: stack) result
    | callBlock : Code signature algebra definitions context [] input →
      Code signature algebra definitions context (input :: stack) result → Code signature algebra definitions context stack result
    | callNamed : Variable definitions body → Code signature algebra definitions context (body.result :: stack) result →
      Code signature algebra definitions context (body.parameters.reverse ++ stack) result
    | callClosure : Code signature algebra definitions context (answer :: stack) result →
      Code signature algebra definitions context (parameters.reverse ++ .computation use parameters answer :: stack) result
    | primitive : algebra.operation parameters answer → Code signature algebra definitions context (.leaf answer :: stack) result →
      Code signature algebra definitions context ((parameters.map Ty.leaf).reverse ++ stack) result
    | branch : Code signature algebra definitions (left :: context) stack result →
      Code signature algebra definitions (right :: context) stack result →
      Code signature algebra definitions context (.sum left right :: stack) result
    | dispatch : (operation : signature.operation effect) →
      Code signature algebra definitions context (signature.result operation :: stack) result →
      Code signature algebra definitions context
        (((signature.bodies operation).map BodyType.type).reverse ++ signature.payload operation :: .capability effect :: stack) result
    | attach : (effect : signature.Effect) → (mode : Mode) →
      Code signature algebra definitions (body :: context) [] answer →
      Clauses signature algebra definitions effect mode context body answer →
      Code signature algebra definitions (.capability effect :: context) [] body →
      Code signature algebra definitions context (answer :: stack) result → Code signature algebra definitions context stack result
    | resume : Code signature algebra definitions context (answer :: stack) result →
      Code signature algebra definitions context (input :: .continuation mode use effect input answer :: stack) result
    | replaceHandler : (effect : signature.Effect) →
      Code signature algebra definitions (body :: context) [] answer →
      Clauses signature algebra definitions effect .deep context body answer →
      Code signature algebra definitions context (answer :: stack) result →
      Code signature algebra definitions context (input :: .continuation .shallow use effect input body :: stack) result
    | inject : Code signature algebra definitions context (answer :: stack) result →
      Code signature algebra definitions context
        (.computation useBody [] input :: .continuation mode use effect input answer :: stack) result
    | enterRegion : Code signature algebra definitions (.region :: context) [] answer →
      Code signature algebra definitions context (answer :: stack) result → Code signature algebra definitions context stack result
    | cellNew : Code signature algebra definitions context (.cell value :: stack) result →
      Code signature algebra definitions context (value :: .region :: stack) result
    | cellRead : Code signature algebra definitions context (value :: stack) result →
      Code signature algebra definitions context (.cell value :: stack) result
    | cellWrite : Code signature algebra definitions context (.unit :: stack) result →
      Code signature algebra definitions context (value :: .cell value :: stack) result
    | protect : Code signature algebra definitions (.exit :: context) [] .unit →
      Code signature algebra definitions context [] answer → Code signature algebra definitions context (answer :: stack) result →
      Code signature algebra definitions context stack result
    | dispose : Code signature algebra definitions context (.unit :: stack) result →
      Code signature algebra definitions context (.continuation mode use effect input answer :: stack) result
    | clone : Code signature algebra definitions context (.continuation mode .multi effect input answer :: stack) result →
      Code signature algebra definitions context (.continuation mode use effect input answer :: stack) result
    | package : Code signature algebra definitions context (.package value :: stack) result →
      Code signature algebra definitions context (value :: stack) result
    | unpackage : Code signature algebra definitions context (value :: stack) result →
      Code signature algebra definitions context (.package value :: stack) result
    | fault : algebra.Fault → Code signature algebra definitions context stack result
    | yieldThen : Code signature algebra definitions context stack result → Code signature algebra definitions context stack result

  inductive Clauses (signature : Signature) (algebra : LeafAlgebra signature.Data)
      (definitions : List (BodyType signature.Data signature.Effect)) :
      (effect : signature.Effect) → Mode → List (TypeOf signature) → TypeOf signature → TypeOf signature → Type where
    | nil : Clauses signature algebra definitions effect mode context body answer
    | cons : (operation : signature.operation effect) → (use : Use) →
      Code signature algebra definitions
        (.continuation mode use effect (signature.result operation) (resumedType mode body answer) ::
          signature.payload operation :: (signature.bodies operation).map BodyType.type ++ context) [] answer →
      Clauses signature algebra definitions effect mode context body answer →
      Clauses signature algebra definitions effect mode context body answer
end

abbrev Definitions (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (signatures : List (BodyType signature.Data signature.Effect)) :=
  Tuple (fun body => Code signature algebra signatures body.parameters [] body.result) signatures

end BoundaryV2.Generalized.Target
