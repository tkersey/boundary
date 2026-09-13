import BoundaryV2.GeneralizedOwnedOperandLowering
import BoundaryV2.GeneralizedClosureEvaluationExamples

namespace BoundaryV2.Generalized.Examples

def compoundOwnedFunction : Source.Expression signature algebra []
    [.leaf .boolean, .resource ⟨0⟩, .leaf .integer] OwnedApplicationType :=
  .first (.pair authoredOwnedLambda (.datum (.leaf (type := Data.integer) 7)))

theorem compound_function_evaluates_with_its_grant :
    Source.ExpressionEvaluation lambdaBindings creationCells.reservations.custody creationSourceStore
      compoundOwnedFunction (.ok createdSourceComputation.value) createdSourceComputation.store :=
  .first (.pair (.closure authored_lambda_forms_owned_callable_value) .datum)

def compoundOwnedCall : Source.Computation signature algebra []
    [.leaf .boolean, .resource ⟨0⟩, .leaf .integer] (.leaf .boolean) :=
  .apply compoundOwnedFunction (.cons (.datum (.leaf false)) .nil)

def compoundCallOperands : Source.RuntimeEnvironment signature algebra [] [OwnedApplicationType, .leaf .boolean] :=
  .cons createdSourceComputation.value (.cons (.datum (.leaf false)) .nil)

theorem compound_call_operands_evaluate_in_order :
    Source.ArgumentsEvaluation lambdaBindings creationCells.reservations.custody creationSourceStore
      compoundOwnedCall.operandPrefix.arguments (.ok compoundCallOperands) createdSourceComputation.store :=
  .cons compound_function_evaluates_with_its_grant (.cons .datum .nil)

theorem compiled_compound_call_reaches_its_owned_handoff :
    ∃ count targetAfter, Target.OwnedOperandSteps
      (Defunctionalization.environment lambdaBindings) creationCells.reservations.custody creationTargetStore
      ⟨_, Defunctionalization.computation compoundOwnedCall, .nil⟩ count targetAfter
      ⟨_, Defunctionalization.operandTail compoundOwnedCall,
        (Defunctionalization.environment compoundCallOperands).pushReverse .nil⟩ ∧
      Defunctionalization.ControlHeapRelated createdSourceComputation.store targetAfter :=
  Defunctionalization.owned_computation_operand_prefix_drains
    (UseScope.PackedControlRelated Defunctionalization.controlPayloadRelated)
    lambdaBindings creationCells.reservations.custody compoundOwnedCall compoundCallOperands
    compound_call_operands_evaluate_in_order ⟨rfl, .nil, .nil⟩

def ownedOperandOverflow : Source.Expression signature algebra []
    [.leaf .boolean, .resource ⟨0⟩, .leaf .integer] (.leaf .integer) :=
  .primitive .addByte (.cons (.datum (.leaf 100)) (.cons (.datum (.leaf 100)) .nil))

theorem overflowing_operand_keeps_its_input_store (store : Source.ControlHeap signature algebra []) :
    Source.ExpressionEvaluation lambdaBindings creationCells.reservations.custody store
      ownedOperandOverflow (.error .overflow) store :=
  .primitiveFault (.cons .datum (.cons .datum .nil)) rfl

def failingOwnedArgument : Source.Expression signature algebra []
    [.leaf .boolean, .resource ⟨0⟩, .leaf .integer] (.leaf .boolean) :=
  .first (.pair (.datum (.leaf false)) ownedOperandOverflow)

def ownedCallWithLaterFailure : Source.Computation signature algebra []
    [.leaf .boolean, .resource ⟨0⟩, .leaf .integer] (.leaf .boolean) :=
  .apply compoundOwnedFunction (.cons failingOwnedArgument .nil)

theorem later_argument_failure_retains_the_constructed_closure :
    Source.ArgumentsEvaluation lambdaBindings creationCells.reservations.custody creationSourceStore
      ownedCallWithLaterFailure.operandPrefix.arguments (.error .overflow) createdSourceComputation.store :=
  .restFault compound_function_evaluates_with_its_grant
    (.firstFault (.firstFault (.pairSecondFault .datum (overflowing_operand_keeps_its_input_store _))))

theorem compiled_later_failure_retains_the_same_owning_fields :
    ∃ count targetAfter final, Target.OwnedOperandSteps
      (Defunctionalization.environment lambdaBindings) creationCells.reservations.custody creationTargetStore
      ⟨_, Defunctionalization.computation ownedCallWithLaterFailure, .nil⟩ count targetAfter final ∧
      Target.Faulted Fault.overflow final ∧
      Defunctionalization.ControlHeapRelated createdSourceComputation.store targetAfter :=
  Defunctionalization.owned_computation_operand_fault_drains
    (UseScope.PackedControlRelated Defunctionalization.controlPayloadRelated)
    lambdaBindings creationCells.reservations.custody ownedCallWithLaterFailure .overflow
    later_argument_failure_retains_the_constructed_closure ⟨rfl, .nil, .nil⟩

def failureBeforeOwnedLambda : Source.Expression signature algebra []
    [.leaf .boolean, .resource ⟨0⟩, .leaf .integer] OwnedApplicationType :=
  .second (.pair ownedOperandOverflow authoredOwnedLambda)

theorem earlier_failure_does_not_allocate_the_later_closure :
    Source.ExpressionEvaluation lambdaBindings creationCells.reservations.custody creationSourceStore
      failureBeforeOwnedLambda (.error .overflow) creationSourceStore :=
  .secondFault (.pairFirstFault (overflowing_operand_keeps_its_input_store _))

theorem compiled_earlier_failure_retains_the_original_fields :
    ∃ count targetAfter final, Target.OwnedOperandSteps
      (Defunctionalization.environment lambdaBindings) creationCells.reservations.custody creationTargetStore
      ⟨_, Defunctionalization.expression failureBeforeOwnedLambda .ret, .nil⟩ count targetAfter final ∧
      Target.Faulted Fault.overflow final ∧
      Defunctionalization.ControlHeapRelated creationSourceStore targetAfter :=
  Defunctionalization.owned_expression_fault_drains
    (UseScope.PackedControlRelated Defunctionalization.controlPayloadRelated)
    lambdaBindings creationCells.reservations.custody failureBeforeOwnedLambda .overflow
    earlier_failure_does_not_allocate_the_later_closure .ret .nil ⟨rfl, .nil, .nil⟩

theorem failure_order_preserves_distinct_cleanup_ownership :
    UseScope.inventory creationSourceStore.fields = [⟨100⟩, ⟨6⟩] ∧
    UseScope.inventory createdSourceComputation.store.fields = [⟨100⟩, ⟨301⟩, ⟨6⟩] ∧
    createdSourceComputation.store.fields.spent = creationSourceStore.fields.spent ∧
    UseScope.ControlStore.Valid createdSourceComputation.store := by
  exact ⟨rfl, rfl, rfl, creation_retains_one_owner_per_capture.1⟩

end BoundaryV2.Generalized.Examples
