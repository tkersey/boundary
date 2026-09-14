import BoundaryV2.GeneralizedBranching
import BoundaryV2.GeneralizedContextExecution
import BoundaryV2.GeneralizedObservationExamples

namespace BoundaryV2.Generalized.Examples

abbrev BranchInput : TypeOf signature := .sum (.leaf .boolean) (.leaf .text)
abbrev BranchContext : List (TypeOf signature) := [BranchInput, .capability .text]

def branchBindings : Source.RuntimeEnvironment signature algebra [] BranchContext :=
  .cons (.left (.datum (.leaf true))) (.cons (.datum (.capability ⟨4⟩)) .nil)

def branchDataBindings : Source.RuntimeEnvironment signature algebra [] BranchContext :=
  .cons (.datum (.left (.leaf true))) (.cons (.datum (.capability ⟨4⟩)) .nil)

def leftEffectBranch : Source.Computation signature algebra [] (.leaf .boolean :: BranchContext) (.leaf .text) :=
  .perform (signature := signature) (algebra := algebra) Operation.text
    (.reference (.there (.there .here))) (.reference .here) .nil

def rightValueBranch : Source.Computation signature algebra [] (.leaf .text :: BranchContext) (.leaf .text) :=
  .returnValue (.reference .here)

def branchProgram : Source.Computation signature algebra [] BranchContext (.leaf .text) :=
  .matchSum (.reference .here) leftEffectBranch rightValueBranch

def branchReturnClause : Source.Computation signature algebra [] [.leaf .text] (.leaf .text) :=
  .yieldThen (.returnValue (.reference .here))

def branchSourceOutside : Source.Context signature algebra [] (.leaf .text) (.leaf .text) :=
  .push (.handler (signature := signature) (algebra := algebra) Effect.choose .deep ⟨8⟩ branchReturnClause .nil .nil) .done

def branchTargetOutside : Target.Stack signature algebra [] (.leaf .text) (.leaf .text) :=
  .push (.handler .choose .deep ⟨8⟩ (Defunctionalization.computation branchReturnClause) .nil .nil) .done

theorem branch_outside_is_represented :
    Defunctionalization.ContextRelated signature algebra [] branchSourceOutside branchTargetOutside :=
  .push (.handler (signature := signature) (algebra := algebra) (program := [])
    Effect.choose .deep ⟨8⟩ branchReturnClause .nil .nil) .done

def branchPayloadBindings : Source.RuntimeEnvironment signature algebra [] (.leaf .boolean :: BranchContext) :=
  .cons (.datum (.leaf true)) branchBindings

def branchTargetRequestFuture : Target.Stack signature algebra [] (.leaf .text) (.leaf .text) :=
  .push (.returnTo .ret (Defunctionalization.environment branchPayloadBindings) .nil) branchTargetOutside

theorem effectful_sum_branch_runs_inside_the_existing_handler :
    Source.Steps (.nil : Source.Definitions signature algebra [])
      (branchSourceOutside.plug (.evaluate branchProgram branchBindings)) 3
      (.request Operation.text ⟨4⟩ (.datum (.leaf true)) .nil branchSourceOutside) ∧
    ∃ count, 0 < count ∧ Target.CallSteps (.nil : Target.Definitions signature algebra [])
      (.code (Defunctionalization.computation branchProgram) (Defunctionalization.environment branchBindings) .nil branchTargetOutside)
      count (.requested Operation.text ⟨4⟩ (.datum (.leaf true)) .nil branchTargetRequestFuture) := by
  obtain ⟨sourceMatch, count, positive, targetMatch⟩ := Defunctionalization.compiled_match_left
    (signature := signature) (algebra := algebra) .nil (.reference .here) leftEffectBranch rightValueBranch
    branchBindings (.left (.datum (.leaf true))) (.datum (.leaf true)) rfl rfl branchTargetOutside
  have sourcePerform : Source.Step (.nil : Source.Definitions signature algebra [])
      (.evaluate leftEffectBranch branchPayloadBindings) (.request Operation.text ⟨4⟩ (.datum (.leaf true)) .nil .done) :=
    .perform rfl rfl rfl
  have inner : Source.Steps (.nil : Source.Definitions signature algebra [])
      (.evaluate branchProgram branchBindings) 2 (.request Operation.text ⟨4⟩ (.datum (.leaf true)) .nil .done) :=
    .cons sourceMatch (.cons sourcePerform .refl)
  have forward : Source.Step (.nil : Source.Definitions signature algebra [])
      (branchSourceOutside.plug (.request Operation.text ⟨4⟩ (.datum (.leaf true)) .nil .done))
      (.request Operation.text ⟨4⟩ (.datum (.leaf true)) .nil branchSourceOutside) := .handlerForward (by decide)
  refine ⟨(inner.in_context branchSourceOutside).trans (.single forward), ?_⟩
  obtain ⟨rest, _, targetPerform⟩ := Defunctionalization.compiled_operation_opens_typed_future
    (signature := signature) (algebra := algebra) .nil Operation.text
    (.reference (.there (.there .here))) (.reference .here) .nil branchPayloadBindings
    ⟨4⟩ (.datum (.leaf true)) .nil rfl rfl rfl branchTargetOutside
  exact ⟨count + rest, by omega, targetMatch.trans targetPerform⟩

theorem effectful_branch_request_retains_the_corresponding_future :
    Defunctionalization.ObservationRelated (signature := signature) (algebra := algebra) (program := [])
      (.requested Operation.text ⟨4⟩ (.datum (.leaf true)) .nil branchSourceOutside)
      (.requested Operation.text ⟨4⟩ (.datum (.leaf true)) .nil branchTargetRequestFuture) :=
  .requested Operation.text ⟨4⟩ (.datum (.leaf true)) .nil
    (.passthrough branchPayloadBindings branch_outside_is_represented)

def branchResponseBindings (text : String) : Source.RuntimeEnvironment signature algebra [] [.leaf .text] :=
  .cons (.datum (.leaf text)) .nil

theorem every_response_runs_the_effectful_return_clause (text : String) :
    Source.Steps (.nil : Source.Definitions signature algebra [])
      (branchSourceOutside.plug (.returned (.datum (.leaf text)))) 2
      (.yielded (.evaluate (.returnValue (.reference .here)) (branchResponseBindings text))) ∧
    Target.CallSteps (.nil : Target.Definitions signature algebra [])
      (.returned (.datum (.leaf text)) branchTargetRequestFuture) 4
      (.yielded (.code (Defunctionalization.computation (.returnValue (.reference .here)))
        (Defunctionalization.environment (branchResponseBindings text)) .nil .done)) := by
  constructor
  · exact .cons .handlerValue (.cons .yield .refl)
  · exact .cons .caller (.cons .returned (.cons .handlerReturned (.cons .yield .refl)))

theorem plain_sum_data_selects_the_same_effectful_branch :
    ∃ count, 0 < count ∧ Target.CallSteps (.nil : Target.Definitions signature algebra [])
      (.code (Defunctionalization.computation branchProgram) (Defunctionalization.environment branchDataBindings) .nil .done)
      count (.code (Defunctionalization.computation leftEffectBranch)
        (Defunctionalization.environment (.cons (.datum (.leaf true)) branchDataBindings)) .nil .done) :=
  (Defunctionalization.compiled_match_left (signature := signature) (algebra := algebra) .nil
    (.reference .here) leftEffectBranch rightValueBranch branchDataBindings
    (.datum (.left (.leaf true))) (.datum (.leaf true)) rfl rfl .done).2

def rightBranchBindings (text : String) : Source.RuntimeEnvironment signature algebra [] BranchContext :=
  .cons (.right (.datum (.leaf text))) (.cons (.datum (.capability ⟨4⟩)) .nil)

theorem every_text_selects_the_other_branch (text : String) :
    ∃ count, 0 < count ∧ Target.CallSteps (.nil : Target.Definitions signature algebra [])
      (.code (Defunctionalization.computation branchProgram) (Defunctionalization.environment (rightBranchBindings text)) .nil .done)
      count (.code (Defunctionalization.computation rightValueBranch)
        (Defunctionalization.environment (.cons (.datum (.leaf text)) (rightBranchBindings text))) .nil .done) :=
  (Defunctionalization.compiled_match_right (signature := signature) (algebra := algebra) .nil
    (.reference .here) leftEffectBranch rightValueBranch (rightBranchBindings text)
    (.right (.datum (.leaf text))) (.datum (.leaf text)) rfl rfl .done).2

def failingBranchTest : Source.Expression signature algebra [] [] (.sum (.leaf .integer) (.leaf .text)) :=
  .left (.primitive .addByte (.cons (.datum (.leaf 100)) (.cons (.datum (.leaf 100)) .nil)))

theorem failing_test_does_not_enter_either_branch :
    ∃ count, 0 < count ∧ Target.CallSteps (.nil : Target.Definitions signature algebra [])
      (.code (Defunctionalization.computation (.matchSum failingBranchTest
        (.yieldThen (.returnValue (.datum .unit))) (.yieldThen (.returnValue (.datum .unit))))) .nil .nil .done)
      count (.failed .overflow .done) :=
  (Defunctionalization.compiled_match_fault (signature := signature) (algebra := algebra) .nil failingBranchTest
    (.yieldThen (.returnValue (.datum .unit))) (.yieldThen (.returnValue (.datum .unit))) .nil rfl .done).2

end BoundaryV2.Generalized.Examples
