import BoundaryV2.GeneralizedStatefulOperandExecution
import BoundaryV2.GeneralizedOwnedOperandExamples
import BoundaryV2.GeneralizedPrefixExamples

namespace BoundaryV2.Generalized.Examples

def compoundCallBefore : Target.State signature algebra [] (.leaf .boolean) :=
  ⟨⟨creationTargetStore, .code (Defunctionalization.computation compoundOwnedCall)
    (Defunctionalization.environment lambdaBindings) .nil .done⟩,
    Defunctionalization.cells creationCells, [⟨1⟩]⟩

def compoundCallSourceAfter : Source.State signature algebra [] (.leaf .boolean) :=
  ⟨⟨{ createdSourceComputation.store with fields := createdApplicationFields },
    Source.enterClosure applicationBody (.cons (.datum (.leaf false)) .nil) applicationCaptures⟩, creationCells, [⟨1⟩]⟩

/-- Allocation and entry use the original authored compound expression. The
new closure grant is already spent when execution reaches its yielding body. -/
theorem authored_compound_call_enters_with_owned_captures :
    Source.ExecutionStep (.nil : Source.Definitions signature algebra [])
      ⟨⟨creationSourceStore, .evaluate compoundOwnedCall lambdaBindings⟩, creationCells, [⟨1⟩]⟩ compoundCallSourceAfter ∧
    ∃ count targetAfter, 0 < count ∧ Target.ExecutionSteps .nil compoundCallBefore count targetAfter ∧
      Defunctionalization.CellStateRelated compoundCallSourceAfter targetAfter ∧
      targetAfter.physicalInventory = [⟨100⟩, ⟨6⟩, ⟨300⟩] ∧
      targetAfter.control.store.fields.spent = [⟨301⟩, ⟨17⟩] := by
  obtain ⟨sourceStep, count, positive, steps, related⟩ :=
    Defunctionalization.compiled_owned_operand_application (signature := signature) (algebra := algebra)
      .nil compoundOwnedFunction (.cons (.datum (.leaf false)) .nil) lambdaBindings
      applicationBody applicationCaptures (.cons (.datum (.leaf false)) .nil)
      (some (createdSourceComputation.authority, applicationOwner)) creationCells [⟨1⟩]
      (targetStore := creationTargetStore) compound_call_operands_evaluate_in_order created_application_handoff
      ⟨rfl, .nil, .nil⟩ .done
  exact ⟨sourceStep, count, _, positive, steps, related, rfl, rfl⟩

def compoundCallYielded : Target.State signature algebra [] (.leaf .boolean) :=
  ⟨⟨{ creationTargetStore with fields := createdApplicationFields },
    .yielded (.code (.load .here .ret)
      (Defunctionalization.environment (.cons (.datum (.leaf false)) applicationCaptures)) .nil
      (.push (.returnTo .ret (Defunctionalization.environment lambdaBindings) .nil) .done))⟩,
    Defunctionalization.cells creationCells, [⟨1⟩]⟩

theorem authored_body_yields_after_consuming_its_closure_grant :
    (∃ count, 0 < count ∧ Target.ExecutionSteps (.nil : Target.Definitions signature algebra [])
      compoundCallBefore count compoundCallYielded) ∧
    compoundCallYielded.physicalInventory = [⟨100⟩, ⟨6⟩, ⟨300⟩] ∧
    compoundCallYielded.control.store.fields.spent = [⟨301⟩, ⟨17⟩] := by
  obtain ⟨_, count, positive, steps, _⟩ :=
    Defunctionalization.compiled_owned_operand_application (signature := signature) (algebra := algebra)
      .nil compoundOwnedFunction (.cons (.datum (.leaf false)) .nil) lambdaBindings
      applicationBody applicationCaptures (.cons (.datum (.leaf false)) .nil)
      (some (createdSourceComputation.authority, applicationOwner)) creationCells [⟨1⟩]
      (targetStore := creationTargetStore) compound_call_operands_evaluate_in_order created_application_handoff
      ⟨rfl, .nil, .nil⟩ .done
  exact ⟨⟨count + 1, by omega, steps.trans (.single (.cell (.ordinary .yield)))⟩, rfl, rfl⟩

def statefulFailureBefore : Target.State signature algebra [] (.leaf .boolean) :=
  ⟨⟨creationTargetStore, .code (Defunctionalization.computation ownedCallWithLaterFailure)
    (Defunctionalization.environment lambdaBindings) .nil (retainedTargetScope (.leaf .boolean))⟩,
    Defunctionalization.cells creationCells, [⟨0⟩, ⟨1⟩]⟩

def statefulFailureSourceAfter : Source.State signature algebra [] (.leaf .boolean) :=
  ⟨⟨createdSourceComputation.store, (retainedSourceScope (.leaf .boolean)).plug (.failed .overflow)⟩,
    creationCells, [⟨0⟩, ⟨1⟩]⟩

theorem stateful_later_failure_keeps_cleanup_and_unspent_ownership :
    Source.ExecutionStep (.nil : Source.Definitions signature algebra [])
      ⟨⟨creationSourceStore, (retainedSourceScope (.leaf .boolean)).plug
        (.evaluate ownedCallWithLaterFailure lambdaBindings)⟩, creationCells, [⟨0⟩, ⟨1⟩]⟩ statefulFailureSourceAfter ∧
    ∃ count targetAfter, 0 < count ∧ Target.ExecutionSteps .nil statefulFailureBefore count targetAfter ∧
      Defunctionalization.CellStateRelated statefulFailureSourceAfter targetAfter ∧
      targetAfter.control.configuration = .failed .overflow (retainedTargetScope (.leaf .boolean)) ∧
      targetAfter.physicalInventory = [⟨100⟩, ⟨301⟩, ⟨6⟩, ⟨300⟩] ∧
      targetAfter.control.store.fields.spent = [⟨17⟩] := by
  obtain ⟨sourceStep, count, targetStore, positive, steps, related⟩ :=
    Defunctionalization.compiled_owned_operand_failure (signature := signature) (algebra := algebra)
      .nil ownedCallWithLaterFailure lambdaBindings .overflow creationCells [⟨0⟩, ⟨1⟩]
      (targetStore := creationTargetStore) later_argument_failure_retains_the_constructed_closure
      ⟨rfl, .nil, .nil⟩ (retained_scopes_are_represented (.leaf .boolean))
  refine ⟨sourceStep, count, _, positive, steps, related, rfl, ?_, ?_⟩
  · change UseScope.inventory targetStore.fields ++ _ = _
    rw [← related.control.store.fields]
    rfl
  · rw [← related.control.store.fields]
    rfl

theorem authored_compound_closure_can_be_returned :
    ∃ count targetAfter, 0 < count ∧ Target.ExecutionSteps (.nil : Target.Definitions signature algebra [])
      ⟨⟨creationTargetStore, .code (Defunctionalization.computation (.returnValue compoundOwnedFunction))
        (Defunctionalization.environment lambdaBindings) .nil .done⟩,
        Defunctionalization.cells creationCells, [⟨1⟩]⟩ count targetAfter ∧
      Defunctionalization.CellStateRelated
        ⟨⟨createdSourceComputation.store, .returned createdSourceComputation.value⟩, creationCells, [⟨1⟩]⟩ targetAfter := by
  obtain ⟨_, count, targetStore, positive, steps, related⟩ :=
    Defunctionalization.compiled_owned_operand_return (signature := signature) (algebra := algebra)
      .nil compoundOwnedFunction lambdaBindings createdSourceComputation.value creationCells [⟨1⟩]
      (targetStore := creationTargetStore) compound_function_evaluates_with_its_grant ⟨rfl, .nil, .nil⟩ .done
  exact ⟨count, _, positive, steps, related⟩

end BoundaryV2.Generalized.Examples
