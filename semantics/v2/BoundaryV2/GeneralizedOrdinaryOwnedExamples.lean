import BoundaryV2.GeneralizedOrdinaryOwnedExecution
import BoundaryV2.GeneralizedOwnedOperandExamples

namespace BoundaryV2.Generalized.Examples

abbrev NamedBodyType : BodyType Data Effect := ⟨.reusable, [.computation .reusable [.unit] (.leaf .integer)], .leaf .integer⟩
abbrev NamedProgram := [NamedBodyType]

def namedTable : Source.Definitions signature algebra NamedProgram :=
  .cons (.apply (.reference .here) (.cons (.datum .unit) .nil)) .nil

def namedBindings : Source.RuntimeEnvironment signature algebra NamedProgram [.leaf .integer, .leaf .boolean] :=
  .cons (.datum (.leaf 7)) (.cons (.datum (.leaf false)) .nil)

def namedClosureBody : Source.Computation signature algebra NamedProgram [.unit, .leaf .integer] (.leaf .integer) :=
  .returnValue (.reference (.there .here))

def namedClosure : Source.Expression signature algebra NamedProgram [.leaf .integer, .leaf .boolean]
    (.computation .reusable [.unit] (.leaf .integer)) :=
  .lambda (.cons .here .nil) namedClosureBody

def namedClosureValue : Source.RuntimeValue signature algebra NamedProgram (.computation .reusable [.unit] (.leaf .integer)) :=
  .closure namedClosureBody (.cons (.datum (.leaf 7)) .nil) none

theorem named_call_accepts_an_authored_capturing_closure :
    ∃ count targetAfter, 0 < count ∧ Target.ExecutionSteps (Defunctionalization.definitions namedTable)
      ⟨⟨⟨⟨[], [], []⟩, [], []⟩, .code (Defunctionalization.computation (.call .here (.cons namedClosure .nil)))
        (Defunctionalization.environment namedBindings) .nil .done⟩, [], []⟩ count targetAfter ∧
      Defunctionalization.CellStateRelated
        ⟨⟨⟨⟨[], [], []⟩, [], []⟩, Source.unfoldCall namedTable .here (.cons namedClosureValue .nil)⟩, [], []⟩ targetAfter := by
  have evaluated : Source.ArgumentsEvaluation namedBindings [] (⟨⟨[], [], []⟩, [], []⟩ : Source.ControlHeap signature algebra NamedProgram)
      (.cons namedClosure .nil) (.ok (.cons namedClosureValue .nil)) ⟨⟨[], [], []⟩, [], []⟩ :=
    .cons (.closure (Source.ClosureEvaluation.shared (bindings := namedBindings) (parameters := [.unit])
      .reusable (Or.inl rfl) (.cons .here .nil) namedClosureBody rfl)) .nil
  obtain ⟨_, count, store, positive, steps, related⟩ := Defunctionalization.compiled_owned_named_call (retained := [])
    namedTable .here (.cons namedClosure .nil) namedBindings (.cons namedClosureValue .nil) [] []
    (targetStore := ⟨⟨[], [], []⟩, [], []⟩) evaluated ⟨rfl, .nil, .nil⟩ .done
  exact ⟨count, _, positive, steps, related⟩

def ownedSumTest : Source.Expression signature algebra [] [.leaf .boolean, .resource ⟨0⟩, .leaf .integer]
    (.sum OwnedApplicationType (.leaf .boolean)) := .left authoredOwnedLambda

def ownedSumLeft : Source.Computation signature algebra [] (OwnedApplicationType :: [.leaf .boolean, .resource ⟨0⟩, .leaf .integer])
    (.leaf .boolean) := .apply (.reference .here) (.cons (.datum (.leaf false)) .nil)

def ownedSumRight : Source.Computation signature algebra [] (.leaf .boolean :: [.leaf .boolean, .resource ⟨0⟩, .leaf .integer])
    (.leaf .boolean) := .returnValue (.reference .here)

theorem owned_sum_branch_keeps_the_selected_closure :
    ∃ count targetAfter, 0 < count ∧ Target.ExecutionSteps (.nil : Target.Definitions signature algebra [])
      ⟨⟨creationTargetStore, .code (Defunctionalization.computation (.matchSum ownedSumTest ownedSumLeft ownedSumRight))
        (Defunctionalization.environment lambdaBindings) .nil .done⟩, Defunctionalization.cells creationCells, [⟨1⟩]⟩ count targetAfter ∧
      Defunctionalization.CellStateRelated
        ⟨⟨createdSourceComputation.store, .evaluate ownedSumLeft (.cons createdSourceComputation.value lambdaBindings)⟩,
          creationCells, [⟨1⟩]⟩ targetAfter := by
  obtain ⟨_, count, store, positive, steps, related⟩ := Defunctionalization.compiled_owned_match_left (retained := [])
    (signature := signature) (algebra := algebra) .nil ownedSumTest ownedSumLeft ownedSumRight lambdaBindings
    (.left createdSourceComputation.value) createdSourceComputation.value creationCells [⟨1⟩]
    (targetStore := creationTargetStore) (.left (.closure authored_lambda_forms_owned_callable_value)) rfl ⟨rfl, .nil, .nil⟩ .done
  exact ⟨count, _, positive, steps, related⟩

def primitiveClosureInput : Source.Expression signature algebra [] [.leaf .boolean, .resource ⟨0⟩, .leaf .integer]
    (.leaf .boolean) := .first (.pair (.datum (.leaf true)) authoredSharedLambda)

theorem primitive_operands_can_contain_a_copyable_closure :
    ∃ count targetAfter, 0 < count ∧ Target.ExecutionSteps (.nil : Target.Definitions signature algebra [])
      ⟨⟨creationTargetStore, .code (Defunctionalization.computation (.primitive Primitive.negate (.cons primitiveClosureInput .nil)))
        (Defunctionalization.environment lambdaBindings) .nil .done⟩, Defunctionalization.cells creationCells, [⟨1⟩]⟩ count targetAfter ∧
      Defunctionalization.CellStateRelated
        ⟨⟨creationSourceStore, .returned (.datum (.leaf false))⟩, creationCells, [⟨1⟩]⟩ targetAfter := by
  have lambda : Source.ClosureEvaluation lambdaBindings creationCells.reservations.custody authoredSharedLambda
      creationSourceStore sharedLambdaValue creationSourceStore :=
    Source.ClosureEvaluation.shared (bindings := lambdaBindings) (parameters := [.leaf Data.boolean])
      .reusable (Or.inl rfl) (.cons .here .nil) sharedLambdaBody rfl
  have evaluated : Source.ExpressionEvaluation lambdaBindings creationCells.reservations.custody creationSourceStore
      (.primitive Primitive.negate (.cons primitiveClosureInput .nil)) (.ok (.datum (.leaf false))) creationSourceStore :=
    .primitive (.cons (.first (.pair .datum (.closure lambda))) .nil) rfl
  obtain ⟨_, count, store, positive, steps, related⟩ := Defunctionalization.compiled_owned_primitive (retained := [])
    (signature := signature) (algebra := algebra) .nil Primitive.negate (.cons primitiveClosureInput .nil) lambdaBindings
    false creationCells [⟨1⟩] (targetStore := creationTargetStore) evaluated ⟨rfl, .nil, .nil⟩ .done
  exact ⟨count, _, positive, steps, related⟩

def scopedRequestBindings : Source.RuntimeEnvironment signature algebra [] [.capability .scoped, .capability .text, .leaf .integer] :=
  .cons (.datum (.capability ⟨20⟩)) (.cons (.datum (.capability ⟨4⟩)) (.cons (.datum (.leaf 42)) .nil))

def scopedRequestBody : Source.Computation signature algebra [] [.unit, .capability .text, .leaf .integer] (.leaf .integer) :=
  .bind (.perform (signature := signature) (algebra := algebra) Operation.text (.reference (.there .here)) (.datum (.leaf true)) .nil)
    (.returnValue (.reference (.there (.there (.there .here)))))

def scopedRequestClosure : Source.Expression signature algebra [] [.capability .scoped, .capability .text, .leaf .integer]
    (.computation .reusable [.unit] (.leaf .integer)) :=
  .lambda (.cons (.there .here) (.cons (.there (.there .here)) .nil)) scopedRequestBody

def scopedRequestClosureValue : Source.RuntimeValue signature algebra [] (.computation .reusable [.unit] (.leaf .integer)) :=
  .closure scopedRequestBody (.cons (.datum (.capability ⟨4⟩)) (.cons (.datum (.leaf 42)) .nil)) none

def scopedRequest : Source.Computation signature algebra [] [.capability .scoped, .capability .text, .leaf .integer] (.leaf .integer) :=
  .perform (signature := signature) (algebra := algebra) Operation.within
    (.reference .here) (.datum (.leaf 7)) (.cons scopedRequestClosure .nil)

theorem operation_request_keeps_an_effectful_body_and_typed_future :
    ∃ count targetAfter, 0 < count ∧ Target.ExecutionSteps (.nil : Target.Definitions signature algebra [])
      ⟨⟨creationTargetStore, .code (Defunctionalization.computation scopedRequest)
        (Defunctionalization.environment scopedRequestBindings) .nil .done⟩,
        Defunctionalization.cells creationCells, [⟨1⟩]⟩ count targetAfter ∧
      Defunctionalization.CellStateRelated
        ⟨⟨creationSourceStore, .request Operation.within ⟨20⟩ (.datum (.leaf 7)) (.cons scopedRequestClosureValue .nil) .done⟩,
          creationCells, [⟨1⟩]⟩ targetAfter := by
  have lambda : Source.ClosureEvaluation scopedRequestBindings creationCells.reservations.custody scopedRequestClosure
      creationSourceStore scopedRequestClosureValue creationSourceStore :=
    Source.ClosureEvaluation.shared (bindings := scopedRequestBindings) (parameters := [.unit]) .reusable (Or.inl rfl)
      (.cons (.there .here) (.cons (.there (.there .here)) .nil)) scopedRequestBody rfl
  obtain ⟨_, count, store, positive, steps, related⟩ := Defunctionalization.compiled_owned_operation (retained := [])
    (signature := signature) (algebra := algebra) .nil Operation.within (.reference .here) (.datum (.leaf 7))
    (.cons scopedRequestClosure .nil) scopedRequestBindings ⟨20⟩ (.datum (.leaf 7)) (.cons scopedRequestClosureValue .nil)
    creationCells [⟨1⟩] (sourceStore := creationSourceStore) (sourceAfter := creationSourceStore) (targetStore := creationTargetStore)
    (.cons .reference (.cons .datum (.cons (.closure lambda) .nil))) ⟨rfl, .nil, .nil⟩ .done
  exact ⟨count, _, positive, steps, related⟩

end BoundaryV2.Generalized.Examples
