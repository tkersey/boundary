import BoundaryV2.GeneralizedExit
import BoundaryV2.GeneralizedFields

namespace BoundaryV2.Generalized.Examples

inductive Data where
  | integer | boolean | text
  deriving DecidableEq, Repr

abbrev Leaf : Data → Type
  | .integer => Int
  | .boolean => Bool
  | .text => String

inductive Fault where
  | overflow
  deriving DecidableEq, Repr

inductive Primitive : List Data → Data → Type where
  | addByte : Primitive [.integer, .integer] .integer
  | negate : Primitive [.boolean] .boolean
  | concatenate : Primitive [.text, .text] .text

def evaluate : Primitive inputs output → Tuple Leaf inputs → Except Fault (Leaf output)
  | .addByte, .cons first (.cons second .nil) =>
    let result := first + second
    if -128 ≤ result ∧ result ≤ 127 then .ok result else .error .overflow
  | .negate, .cons value .nil => .ok (!value)
  | .concatenate, .cons first (.cons second .nil) => .ok (first ++ second)

abbrev algebra : LeafAlgebra Data := {
  Value := Leaf
  Fault := Fault
  Reason := String
  operation := Primitive
  evaluate := evaluate
}

inductive Effect where
  | choose | text | scoped
  deriving DecidableEq, Repr

inductive Operation : Effect → Type where
  | choice : Operation .choose
  | text : Operation .text
  | within : Operation .scoped

def signature : Signature := {
  Data := Data
  Effect := Effect
  operation := Operation
  payload := fun operation => match operation with
    | .choice => .unit
    | .text => .leaf .boolean
    | .within => .leaf .integer
  result := fun operation => match operation with
    | .choice => .leaf .boolean
    | .text => .leaf .text
    | .within => .leaf .integer
  bodies := fun operation => match operation with
    | .choice | .text => []
    | .within => [⟨.reusable, [.unit], .leaf .integer⟩]
}

theorem ordinary_scalar_result : evaluate .addByte (.cons 20 (.cons 22 .nil)) = .ok 42 := rfl

theorem authored_scalar_fault : evaluate .addByte (.cons 127 (.cons 1 .nil)) = .error .overflow := rfl

def structured : Datum (Effect := Effect) algebra (.product (.leaf .integer) (.leaf .text)) :=
  .pair (.leaf 42) (.leaf "answer")

theorem structured_data_has_no_authority : structured.support = [] := rfl

def ownedAndBorrowed : Datum (Effect := Effect) algebra
    (.product (.resource ⟨0⟩) (.borrowed ⟨0⟩)) :=
  .pair (.resource ⟨7⟩ ⟨3⟩ (.lexical ⟨2⟩ 0)) (.borrowed ⟨7⟩ ⟨2⟩)

theorem resource_and_borrow_are_distinct_occurrences : ownedAndBorrowed.support =
    [.owned ⟨3⟩ (.lexical ⟨2⟩ 0), .borrowed ⟨2⟩] := rfl

/-- Cleanup has requested a Boolean and still has its ordinary return frame.
The request's future is target code and data, not an external callback. -/
def cleanupFuture : Target.Stack signature algebra [] (.leaf .boolean) .unit :=
  .push (.returnTo (.push .unit .ret) .nil .nil) .done

def cleanupRequest : ExitComposition.Cursor signature algebra [] :=
  .requested Operation.choice ⟨8⟩ (.datum .unit) .nil cleanupFuture

def capturedCleanup : ExitComposition.Obligation signature algebra [] :=
  ⟨⟨2⟩, .running cleanupRequest (.captured ⟨9⟩),
    [.owned ⟨3⟩ (.cleanup 2), .owned ⟨4⟩ (.cleanup 2)], ⟨.failure .overflow, [], none⟩⟩

theorem captured_cleanup_survives_repeated_cancellation :
    ExitComposition.cancel "later" (ExitComposition.cancel "stop" capturedCleanup) =
      { capturedCleanup with exit := ⟨.failure .overflow, [], some "stop"⟩ } := rfl

theorem captured_cleanup_reattaches_and_accepts_typed_response :
    ExitComposition.Steps (ExitComposition.cancel "stop" capturedCleanup) 0
      ⟨⟨2⟩, .running (.returned (.datum (.leaf true)) cleanupFuture) .active,
        capturedCleanup.fields, ⟨.failure .overflow, [], some "stop"⟩⟩ := by
  exact .cons .reattach (.cons .park (.cons .response .refl))

theorem two_cleanup_owners_remain_distinct : UseScope.Valid
    ⟨[], capturedCleanup.fields, []⟩ := by
  simp [UseScope.Valid, UseScope.inventory, UseScope.tokens, UseScope.Field.tokens, capturedCleanup]

end BoundaryV2.Generalized.Examples
