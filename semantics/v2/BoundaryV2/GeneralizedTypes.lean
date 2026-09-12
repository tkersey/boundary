import Std

namespace BoundaryV2.Generalized

/-- Distinct logical allocation domains cannot be interchanged. -/
inductive Domain where
  | attachment | scope | region | cell | resource | custody | occurrence | control | obligation
  deriving DecidableEq, Repr

structure Id (domain : Domain) where
  index : Nat
  deriving DecidableEq, Repr

inductive Use where
  | reusable | affine | linear | multi
  deriving DecidableEq, Repr

inductive Mode where
  | deep | shallow
  deriving DecidableEq, Repr

/-- Nominal resource authority is independent of the private representation. -/
structure ResourceName where
  index : Nat
  deriving DecidableEq, Repr

/-- Leaf data is separated from every reference that carries control authority. -/
inductive Ty (Data Effect : Type) where
  | leaf : Data → Ty Data Effect
  | unit : Ty Data Effect
  | product : Ty Data Effect → Ty Data Effect → Ty Data Effect
  | sum : Ty Data Effect → Ty Data Effect → Ty Data Effect
  | computation : Use → List (Ty Data Effect) → Ty Data Effect → Ty Data Effect
  | capability : Effect → Ty Data Effect
  | package : Ty Data Effect → Ty Data Effect
  | region : Ty Data Effect
  | cell : Ty Data Effect → Ty Data Effect
  | exit : Ty Data Effect
  | resource : ResourceName → Ty Data Effect
  | borrowed : ResourceName → Ty Data Effect
  | continuation : Mode → Use → Effect → Ty Data Effect → Ty Data Effect → Ty Data Effect

structure BodyType (Data Effect : Type) where
  use : Use
  parameters : List (Ty Data Effect)
  result : Ty Data Effect

/-- Every family may have its own operation, payload, result, and scoped bodies. -/
structure Signature where
  Data : Type
  Effect : Type
  operation : Effect → Type
  payload : {effect : Effect} → operation effect → Ty Data Effect
  result : {effect : Effect} → operation effect → Ty Data Effect
  bodies : {effect : Effect} → operation effect → List (BodyType Data Effect)

abbrev TypeOf (signature : Signature) := Ty signature.Data signature.Effect

inductive Tuple {Index : Type} (Value : Index → Type) : List Index → Type where
  | nil : Tuple Value []
  | cons : Value head → Tuple Value tail → Tuple Value (head :: tail)

inductive Variable {Index : Type} : List Index → Index → Type where
  | here : Variable (head :: tail) head
  | there : Variable tail index → Variable (head :: tail) index

def Variable.lookup {Value : Index → Type} : Variable context index → Tuple Value context → Value index
  | .here, .cons value _ => value
  | .there reference, .cons _ rest => reference.lookup rest

def Tuple.append {Value : Index → Type} : Tuple Value left → Tuple Value right → Tuple Value (left ++ right)
  | .nil, right => right
  | .cons value rest, right => .cons value (rest.append right)

def Tuple.map {First Second : Index → Type} (function : ∀ index, First index → Second index) :
    Tuple First indices → Tuple Second indices
  | .nil => .nil
  | .cons value rest => .cons (function _ value) (rest.map function)

/-- Captures name an ordered subset of lexical bindings. Unrelated caller
bindings are absent from the closure's physical environment. -/
inductive Selection {Index : Type} (context : List Index) : List Index → Type where
  | nil : Selection context []
  | cons : Variable context type → Selection context types → Selection context (type :: types)

/-- Primitive calls operate on leaf data only. They cannot construct a core
capability, continuation, borrowed reference, or ownership transfer. -/
structure LeafAlgebra (Data : Type) where
  Value : Data → Type
  Fault : Type
  Reason : Type
  operation : List Data → Data → Type
  evaluate : operation parameters result → Tuple Value parameters → Except Fault (Value result)

inductive ExitPrimary (Fault : Type) where
  | normal
  | failure : Fault → ExitPrimary Fault
  | abandoned
  | cancelled

structure ExitInfo (Fault Reason : Type) where
  primary : ExitPrimary Fault
  failures : List Fault := []
  cancellation : Option Reason := none

inductive Owner where
  | lexical : Id .scope → Nat → Owner
  | control : Nat → Nat → Owner
  | package : Nat → Nat → Owner
  | cleanup : Nat → Owner
  deriving DecidableEq, Repr

/-- An occurrence is a physical field, not a deduplicated reachability set. -/
inductive Occurrence where
  | owned : Id .custody → Owner → Occurrence
  | borrowed : Id .scope → Occurrence
  | attachment : Id .attachment → Occurrence
  | region : Id .region → Occurrence
  | cell : Id .cell → Occurrence
  deriving DecidableEq, Repr

/-- Plain data has no authority constructor. Reference-bearing products and
closure environments expose their support through the core value constructors. -/
inductive Datum {Data Effect : Type} (algebra : LeafAlgebra Data) : Ty Data Effect → Type where
  | leaf : algebra.Value type → Datum algebra (.leaf type)
  | unit : Datum algebra .unit
  | pair : Datum algebra left → Datum algebra right → Datum algebra (.product left right)
  | left : Datum algebra left → Datum algebra (.sum left right)
  | right : Datum algebra right → Datum algebra (.sum left right)
  | capability : Id .attachment → Datum algebra (.capability effect)
  | region : Id .region → Datum algebra .region
  | resource : Id .resource → Id .custody → Owner → Datum algebra (.resource name)
  | borrowed : Id .resource → Id .scope → Datum algebra (.borrowed name)

def Datum.support : Datum algebra type → List Occurrence
  | .leaf _ | .unit => []
  | .pair first second => first.support ++ second.support
  | .left value | .right value => value.support
  | .capability id => [.attachment id]
  | .region id => [.region id]
  | .resource _ token owner => [.owned token owner]
  | .borrowed _ scope => [.borrowed scope]

theorem product_support_keeps_order (left : Datum algebra a) (right : Datum algebra b) :
    (Datum.pair left right).support = left.support ++ right.support := rfl

theorem repeated_owned_field_is_not_erased (algebra : LeafAlgebra Data) (Effect : Type) (name : ResourceName)
    (resource : Id .resource) (token : Id .custody) (owner : Owner) :
    (Datum.pair (Datum.resource (name := name) (algebra := algebra) (Effect := Effect) resource token owner)
      (Datum.resource (name := name) resource token owner)).support = [.owned token owner, .owned token owner] := rfl

theorem lexical_extension_preserves_older_binding (reference : Variable context type)
    (environment : Tuple Value context) (value : Value newType) :
    (Variable.there reference).lookup (.cons value environment) = reference.lookup environment := rfl

end BoundaryV2.Generalized
