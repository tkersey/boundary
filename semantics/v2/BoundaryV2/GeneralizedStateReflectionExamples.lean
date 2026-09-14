import BoundaryV2.GeneralizedStateReflection
import BoundaryV2.GeneralizedOwnedOperandExamples

namespace BoundaryV2.Generalized.Examples.Reflection

abbrev ResultType : TypeOf signature := .product OwnedApplicationType (.leaf .integer)

def sourceExpression : Source.Expression signature algebra []
    [.leaf .boolean, .resource ⟨0⟩, .leaf .integer] ResultType :=
  .pair authoredOwnedLambda ownedOperandOverflow

def start : Target.State signature algebra [] ResultType :=
  ⟨⟨creationTargetStore, .code (Defunctionalization.computation (.returnValue sourceExpression))
    (Defunctionalization.environment lambdaBindings) .nil .done⟩, Defunctionalization.cells creationCells, [⟨1⟩]⟩

def final : Target.State signature algebra [] ResultType :=
  ⟨⟨createdTargetComputation.store, .failed .overflow .done⟩, Defunctionalization.cells creationCells, [⟨1⟩]⟩

/-- Execute only target instructions: load an exclusive capture, allocate the
closure, then fail in a later primitive operand. No source evaluation supplies
this trace or chooses its intermediate owning state. -/
theorem actual_target_trace :
    Target.ExecutionSteps (.nil : Target.Definitions signature algebra []) start 6 final := by
  refine .cons (.cell (.ordinary (.operand .load))) ?_
  refine .cons (.control (.operand (Target.OwnedOperandStep.ownedClose (parameters := [.leaf Data.boolean]) .linear
    (Defunctionalization.computation applicationBody) (Defunctionalization.environment applicationCaptures)
    (Defunctionalization.expression ownedOperandOverflow (.pair .ret)) .nil applicationOwner
    [.owned ⟨100⟩ (.lexical ⟨0⟩ 1)] [] creationTargetStore rfl))) ?_
  exact .cons (.cell (.ordinary (.operand .push)))
    (.cons (.cell (.ordinary (.operand .push)))
      (.cons (.cell (.ordinary (.operand (.primitiveFault (signature := signature) (algebra := algebra) (operation := Primitive.addByte)
        (arguments := .cons (.datum (.leaf 100)) (.cons (.datum (.leaf 100)) .nil)) rfl))))
        (.cons (.cell (.ordinary .fault)) .refl)))

/-- The general inverse reconstructs source failure and its actual physical
state from the target run. The newly allocated closure is not lost at failure. -/
theorem target_failure_reconstructs_source_custody :
    ∃ sourceFinal,
      Source.StateObserves (.nil : Source.Definitions signature algebra [])
        ⟨⟨creationSourceStore, .evaluate (.returnValue sourceExpression) lambdaBindings⟩, creationCells, [⟨1⟩]⟩
        sourceFinal (.failed .overflow) ∧
      sourceFinal.control.store.fields = createdSourceComputation.store.fields ∧
      UseScope.inventory sourceFinal.control.store.fields = [⟨100⟩, ⟨301⟩, ⟨6⟩] ∧
      Defunctionalization.cells sourceFinal.cells = Defunctionalization.cells creationCells := by
  obtain ⟨sourceFinal, observation, observed, matched⟩ :=
    Defunctionalization.returned_expression_observation_reflected .nil sourceExpression lambdaBindings creationCells [⟨1⟩]
      (targetStore := creationTargetStore) ⟨rfl, .nil, .nil⟩ ⟨6, actual_target_trace, .failed⟩
  have fields := matched.store.fields
  cases matched.observation with
  | failed fault =>
    refine ⟨sourceFinal, observed, ?_, ?_, ?_⟩
    · exact fields
    · rw [fields]; rfl
    · exact matched.cells.symm

end BoundaryV2.Generalized.Examples.Reflection
