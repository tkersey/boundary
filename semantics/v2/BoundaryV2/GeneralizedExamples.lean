import BoundaryV2.GeneralizedExit
import BoundaryV2.GeneralizedFields
import BoundaryV2.GeneralizedHandlerEntry

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

def textBindings : Source.RuntimeEnvironment signature algebra [] [.capability .text, .leaf .boolean] :=
  .cons (.datum (.capability ⟨4⟩)) (.cons (.datum (.leaf true)) .nil)

def capturedTextBody : Source.Computation signature algebra []
    [.leaf .integer, .capability .text, .leaf .boolean] (.leaf .text) :=
  Source.Computation.perform (signature := signature) (algebra := algebra) Operation.text
    (.reference (.there .here)) (.reference (.there (.there .here))) .nil

def textClosure : Source.Expression signature algebra [] [.capability .text, .leaf .boolean]
    (.computation .reusable [.leaf .integer] (.leaf .text)) :=
  .lambda (.cons .here (.cons (.there .here) .nil)) capturedTextBody

def textArguments : Source.Arguments signature algebra [] [.capability .text, .leaf .boolean] [.leaf .integer] :=
  .cons (.datum (.leaf 7)) .nil

def textBodyBindings : Source.RuntimeEnvironment signature algebra [] [.leaf .integer, .capability .text, .leaf .boolean] :=
  .cons (.datum (.leaf 7)) textBindings

def textCaller : Target.Stack signature algebra [] (.leaf .text) (.leaf .text) :=
  .push (.returnTo .ret (Defunctionalization.environment textBindings) .nil) .done

/-- An actual compiled closure call uses captured capability and Boolean
bindings, opens an operation returning text, and retains both return frames. -/
theorem compiled_captured_closure_opens_effect : ∃ count,
    Target.CallSteps (.nil : Target.Definitions signature algebra [])
      (.code (Defunctionalization.computation (.apply textClosure textArguments))
        (Defunctionalization.environment textBindings) .nil .done) count
      (.requested Operation.text ⟨4⟩ (.datum (.leaf true)) .nil
        (.push (.returnTo .ret (Defunctionalization.environment textBodyBindings) .nil) textCaller)) := by
  obtain ⟨callCount, _, called⟩ := Defunctionalization.compiled_closure_call .nil textClosure textArguments textBindings
    capturedTextBody textBindings none (.cons (.datum (.leaf 7)) .nil) rfl rfl .done
  obtain ⟨requestCount, _, requested⟩ := Defunctionalization.compiled_operation_opens_typed_future
    (signature := signature) (algebra := algebra) .nil Operation.text
    (.reference (.there .here)) (.reference (.there (.there .here))) .nil textBodyBindings ⟨4⟩ (.datum (.leaf true)) .nil
    rfl rfl rfl textCaller
  exact ⟨callCount + requestCount, called.trans requested⟩

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
    ExitComposition.Steps (.nil : Target.Definitions signature algebra []) (ExitComposition.cancel "stop" capturedCleanup) 0
      ⟨⟨2⟩, .running (.returned (.datum (.leaf true)) cleanupFuture) .active,
        capturedCleanup.fields, ⟨.failure .overflow, [], some "stop"⟩⟩ := by
  exact .cons .reattach (.cons .park (.cons .response .refl))

theorem two_cleanup_owners_remain_distinct : UseScope.Valid
    ⟨[], capturedCleanup.fields, []⟩ := by
  simp [UseScope.Valid, UseScope.inventory, UseScope.tokens, UseScope.Field.tokens, capturedCleanup]

/-- After the response, execute the saved return frame and the compiled unit
return. Completion preserves the original failure and first cancellation. -/
theorem captured_cleanup_executes_its_saved_future :
    ExitComposition.Steps (.nil : Target.Definitions signature algebra [])
      (ExitComposition.cancel "stop" capturedCleanup) 0
      ⟨⟨2⟩, .finished .returned, capturedCleanup.fields, ⟨.failure .overflow, [], some "stop"⟩⟩ := by
  exact .cons .reattach (.cons .park (.cons (.response (response := .datum (.leaf true)))
    (.cons (.execute (table := .nil) .caller)
      (.cons (.execute (table := .nil) (.operand .push))
        (.cons (.execute (table := .nil) .returned) (.cons .returned .refl))))))

def unitCleanup : ExitComposition.Cleanup signature algebra [] :=
  ⟨[], .push .unit .ret, .nil⟩

theorem cleanup_initiates_once_and_executes :
    ExitComposition.Steps (.nil : Target.Definitions signature algebra [])
      ⟨⟨2⟩, .pending unitCleanup, capturedCleanup.fields, ⟨.normal, [], none⟩⟩ 1
      ⟨⟨2⟩, .finished .returned, capturedCleanup.fields, ⟨.normal, [], none⟩⟩ := by
  exact .cons .begin (.cons (.execute (table := .nil) (.operand .push))
    (.cons (.execute (table := .nil) .returned) (.cons .returned .refl)))

end BoundaryV2.Generalized.Examples
