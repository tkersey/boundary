import BoundaryV2.GeneralizedClosureEvaluation
import BoundaryV2.GeneralizedComputationCreationExamples

namespace BoundaryV2.Generalized.Examples

def lambdaBindings : Source.RuntimeEnvironment signature algebra []
    [.leaf .boolean, .resource ⟨0⟩, .leaf .integer] :=
  .cons (.datum (.leaf true)) (.cons ownedCellSourceValue (.cons (.datum (.leaf 42)) .nil))

def lambdaCaptures : Selection (Index := TypeOf signature)
    [.leaf .boolean, .resource ⟨0⟩, .leaf .integer] [.resource ⟨0⟩] :=
  .cons (.there .here) .nil

def authoredOwnedLambda : Source.Expression signature algebra []
    [.leaf .boolean, .resource ⟨0⟩, .leaf .integer] OwnedApplicationType :=
  .lambda lambdaCaptures applicationBody

theorem authored_lambda_forms_owned_callable_value :
    Source.ClosureEvaluation lambdaBindings creationCells.reservations.custody authoredOwnedLambda
      creationSourceStore createdSourceComputation.value createdSourceComputation.store :=
  Source.ClosureEvaluation.owned (bindings := lambdaBindings) (reserved := creationCells.reservations.custody)
    (parameters := [.leaf Data.boolean]) .linear lambdaCaptures applicationBody applicationOwner
    [.owned ⟨100⟩ (.lexical ⟨0⟩ 1)] [] creationSourceStore rfl

/-- Capture selection skips a shadowing Boolean and an unrelated integer.
The target retains its pre-existing operand and continuation code unchanged. -/
theorem authored_lambda_preserves_the_receiving_context :
    ∃ count targetAfter, 0 < count ∧
      Target.OwnedOperandSteps (Defunctionalization.environment lambdaBindings) creationCells.reservations.custody
        creationTargetStore
        ⟨_, Defunctionalization.expression authoredOwnedLambda (.pair .ret),
          .cons (.datum (.leaf (type := Data.integer) 99)) .nil⟩ count
        targetAfter ⟨_, .pair .ret,
          .cons (Defunctionalization.value createdSourceComputation.value)
            (.cons (.datum (.leaf (type := Data.integer) 99)) .nil)⟩ ∧
      Defunctionalization.ControlHeapRelated createdSourceComputation.store targetAfter := by
  exact Defunctionalization.compiled_lambda_evaluation
    (UseScope.PackedControlRelated Defunctionalization.controlPayloadRelated)
    lambdaBindings creationCells.reservations.custody
    authoredOwnedLambda createdSourceComputation.value authored_lambda_forms_owned_callable_value
    (.pair .ret) (.cons (.datum (.leaf (type := Data.integer) 99)) .nil) ⟨rfl, .nil, .nil⟩

def sharedLambdaBody : Source.Computation signature algebra [] [.leaf .boolean, .leaf .boolean] (.leaf .boolean) :=
  .yieldThen (.returnValue (.reference (.there .here)))

def authoredSharedLambda : Source.Expression signature algebra []
    [.leaf .boolean, .resource ⟨0⟩, .leaf .integer]
    (.computation .reusable [.leaf .boolean] (.leaf .boolean)) :=
  .lambda (.cons .here .nil) sharedLambdaBody

def sharedLambdaValue : Source.RuntimeValue signature algebra []
    (.computation .reusable [.leaf .boolean] (.leaf .boolean)) :=
  .closure sharedLambdaBody (.cons (.datum (.leaf true)) .nil) none

theorem shared_authored_lambda_has_finite_compilation :
    ∃ count targetAfter, 0 < count ∧
      Target.OwnedOperandSteps (Defunctionalization.environment lambdaBindings) creationCells.reservations.custody
        creationTargetStore ⟨_, Defunctionalization.expression authoredSharedLambda .ret, .nil⟩ count
        targetAfter ⟨_, .ret, .cons (Defunctionalization.value sharedLambdaValue) .nil⟩ ∧
      Defunctionalization.ControlHeapRelated creationSourceStore targetAfter := by
  have evaluated : Source.ClosureEvaluation lambdaBindings creationCells.reservations.custody
      authoredSharedLambda creationSourceStore sharedLambdaValue creationSourceStore :=
    Source.ClosureEvaluation.shared (bindings := lambdaBindings) (reserved := creationCells.reservations.custody)
      (store := creationSourceStore) (parameters := [.leaf Data.boolean]) .reusable (Or.inl rfl)
      (.cons .here .nil) sharedLambdaBody rfl
  exact Defunctionalization.compiled_lambda_evaluation
    (UseScope.PackedControlRelated Defunctionalization.controlPayloadRelated)
    lambdaBindings creationCells.reservations.custody authoredSharedLambda sharedLambdaValue evaluated
    .ret .nil ⟨rfl, .nil, .nil⟩

def authoredExclusiveSharedLambda : Source.Expression signature algebra []
    [.leaf .boolean, .resource ⟨0⟩, .leaf .integer]
    (.computation .multi [.leaf .boolean] (.leaf .boolean)) :=
  .lambda lambdaCaptures applicationBody

theorem exclusive_capture_cannot_form_a_shared_lambda
    (after : Source.ControlHeap signature algebra []) :
    ¬ Source.ClosureEvaluation lambdaBindings creationCells.reservations.custody
      authoredExclusiveSharedLambda creationSourceStore
      (.closure applicationBody applicationCaptures none) after := by
  intro evaluated
  have copyable := evaluated.shared_result_copyable (Or.inr rfl)
  simp [Value.copyable, Environment.copyable, applicationCaptures, ownedCellSourceValue, Datum.copyable] at copyable

end BoundaryV2.Generalized.Examples
