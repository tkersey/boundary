import BoundaryV2.GeneralizedCleanupCompletion
import BoundaryV2.GeneralizedNestedCleanupExamples

namespace BoundaryV2.Generalized.Examples.CleanupCompletion

open ExitComposition
abbrev leafAlgebra := Nested.leafAlgebra
def normal : ExitInfo Nat String := ⟨.normal, [], none⟩
def store : Target.ControlHeap signature leafAlgebra [] := ⟨⟨[], [], []⟩, [], []⟩
def clauses : Target.Clauses signature leafAlgebra [] .choose .deep [] (.leaf .integer) (.leaf .text) :=
  .cons Operation.choice .affine (.push (.leaf "clause") .ret) .nil
def outside : Target.Stack signature leafAlgebra [] (.leaf .integer) (.leaf .text) :=
  .push (.handler .choose .deep ⟨8⟩ (.push (.leaf "normal return") .ret) clauses .nil) .done
def original : ExitInfo Nat String := ⟨.failure 10, [11], some "first"⟩
def bodyExit : ExitInfo Nat String := ⟨.failure 20, [21, 22], some "later"⟩
def failed : Resolution signature leafAlgebra [] (.leaf .text) :=
  .reenter ⟨⟨store, .failed 20 (.push (.cleanupReturn ⟨7⟩ none original) outside)⟩, [], []⟩ bodyExit

theorem nested_failure_completes_with_original_precedence_and_order :
    finishCleanupFrame failed = some (.resolved
      (.reenter ⟨⟨store, .failed 10 outside⟩, [], []⟩ ⟨.failure 10, [11, 20, 21, 22], some "first"⟩)) := rfl

def cleanup : Target.Code signature leafAlgebra [] [.exit] [] .unit := .yieldThen (.push .unit .ret)
def originalFailure : Resolution signature leafAlgebra [] (.leaf .text) :=
  .reenter ⟨⟨store, .failed 10 (.push (.protection ⟨7⟩ cleanup .nil) outside)⟩, [], []⟩ original
def failureStarted : Resolution signature leafAlgebra [] (.leaf .text) :=
  .reenter ⟨⟨store, .code cleanup (.cons (.exit original) .nil) .nil (.push (.cleanupReturn ⟨7⟩ none original) outside)⟩, [], []⟩ normal

theorem failure_entry_keeps_the_enclosing_handler_and_separates_histories :
    beginAbruptCleanup originalFailure = some failureStarted ∧
    (Target.select ⟨8⟩ (.push (.cleanupReturn ⟨7⟩ none original) outside)).isSome = true := ⟨rfl, rfl⟩

def outerRunning : Target.Stack signature leafAlgebra [] .unit (.leaf .text) :=
  .push (.cleanupReturn ⟨7⟩ (some (.datum (.leaf 42))) normal) outside
def innerRunning : Target.Stack signature leafAlgebra [] .unit (.leaf .text) :=
  .push (.cleanupReturn ⟨9⟩ (some (.datum .unit)) normal) outerRunning
def cancelledOutside : Target.Stack signature leafAlgebra [] .unit (.leaf .text) :=
  .push (.cleanupReturn ⟨7⟩ (some (.datum (.leaf 42))) (normal.cancel "first")) outside
def cancelled : Target.Stack signature leafAlgebra [] .unit (.leaf .text) :=
  .push (.cleanupReturn ⟨9⟩ (some (.datum .unit)) normal) cancelledOutside

theorem cancellation_updates_the_outermost_running_frame_once :
    innerRunning.cancelRunning "first" = some cancelled ∧ cancelled.cancelRunning "later" = some cancelled ∧
    finishCleanupFrame (.reenter ⟨⟨store, .returned (.datum .unit) cancelled⟩, [], []⟩ normal) =
      some (.resolved (.reenter ⟨⟨store, .returned (.datum .unit) cancelledOutside⟩, [], []⟩ normal)) ∧
    finishCleanupFrame (.reenter ⟨⟨store, .returned (.datum .unit) cancelledOutside⟩, [], []⟩ normal) =
      some (.resolved (.unwind ⟨⟨7⟩, .finished .returned, store, [], [], normal.cancel "first"⟩ outside)) := ⟨rfl, rfl, rfl, rfl⟩

def view : UseScope.ControlView := ⟨⟨10⟩, ⟨100⟩, .lexical ⟨0⟩ 0⟩
abbrev controlType : TypeOf signature := .continuation .shallow .linear .choose (.leaf .boolean) .unit
abbrev controlShape : ControlShape signature := ⟨.shallow, .choose, .leaf .boolean, .unit⟩
def saved : Target.ControlPayload signature leafAlgebra [] controlShape :=
  ⟨⟨8⟩, .push (.returnTo (.push .unit .ret) .nil .nil) .done⟩
def ownedValue : Target.RuntimeValue signature leafAlgebra [] controlType :=
  .continuation view.identity (some (view.authority, view.owner))
def ownedStore : Target.ControlHeap signature leafAlgebra [] :=
  ⟨⟨[.owned ⟨100⟩ view.owner, .owned ⟨900⟩ (.lexical ⟨0⟩ 1)], [.continuation ⟨10⟩ []], []⟩,
    [⟨⟨10⟩, ⟨100⟩, .linear, ⟨controlShape, saved⟩⟩], []⟩
def afterStore : Target.ControlHeap signature leafAlgebra [] :=
  ⟨⟨[.owned ⟨900⟩ (.lexical ⟨0⟩ 1)], [], [⟨100⟩]⟩, [], []⟩
def afterOutside : Target.Stack signature leafAlgebra [] controlType (.leaf .text) :=
  .push (.returnTo (.push (.leaf "must not return") .ret) .nil .nil) .done
def exit : ExitInfo Nat String := ⟨.failure 20, [20, 21], some "first"⟩
def work : CleanupDisposal signature leafAlgebra [] (.leaf .text) :=
  ⟨controlType, ownedValue, ⟨⟨7⟩, .finished (.failed 20), ownedStore, [], [], exit⟩, afterOutside⟩
def releasedRuntime : Runtime signature leafAlgebra [] := ⟨⟨7⟩, .finished .abandoned, afterStore, [], [], exit⟩
def dropping : Target.Disposal signature leafAlgebra [] .unit :=
  ⟨.unit, .seeking releasedRuntime saved.future, .done⟩
def dropped : Target.Disposal signature leafAlgebra [] .unit := ⟨.unit, .complete releasedRuntime, .done⟩
def startedValues := ValueDisposal.start work.runtime work.value
def enteredValues : ValueDisposal signature leafAlgebra [] := .control dropping []
def completedValues : ValueDisposal signature leafAlgebra [] := .control dropped []
def finishedValues : ValueDisposal signature leafAlgebra [] := .ready releasedRuntime []

def ownedFailure : Resolution signature leafAlgebra [] (.leaf .text) :=
  .reenter ⟨⟨ownedStore, .failed 20 (.push (.cleanupReturn ⟨7⟩ (some ownedValue) normal) afterOutside)⟩, [], []⟩
    ⟨.failure 20, [21], some "first"⟩

theorem failed_cleanup_retains_an_owned_return_for_real_disposal :
    finishCleanupFrame (.reenter
      ⟨⟨ownedStore, .failed 20 (.push (.cleanupReturn ⟨7⟩ (some ownedValue) normal) afterOutside)⟩, [], []⟩
      ⟨.failure 20, [21], some "first"⟩) = some (.disposing work) ∧
    startedValues.finished = none := ⟨rfl, rfl⟩

theorem returned_control_disposal_consumes_authority_and_keeps_exit :
    ValueDisposalSteps (.nil : Target.Definitions signature leafAlgebra []) startedValues 3 finishedValues ∧
    finishedValues.finished = some releasedRuntime ∧
    afterStore.fields.spent = [⟨100⟩] ∧ UseScope.inventory afterStore.fields = [⟨900⟩] ∧
    UseScope.disposeOwned view afterStore = none := by
  refine ⟨?_, rfl, rfl, rfl, rfl⟩
  have enter : ValueDisposalStep (.nil : Target.Definitions signature leafAlgebra []) startedValues enteredValues := ValueDisposalStep.enterControl (signature := signature) (algebra := leafAlgebra) (runtime := work.runtime) (acquired := ⟨afterStore, ⟨controlShape, saved⟩⟩) rfl
  refine .cons enter ?_
  exact .cons (middle := completedValues) (.control (.unwind (.complete rfl))) (.cons .finishControl .refl)

theorem failed_frame_executes_its_owned_return_disposal_before_propagation :
    CleanupFrameSteps (.nil : Target.Definitions signature leafAlgebra []) (.running ownedFailure) 6
      (.running (.reenter ⟨⟨afterStore, .failed 20 afterOutside⟩, [], []⟩ exit)) := by
  refine .cons (middle := .disposing work) (.finish (show finishCleanupFrame ownedFailure = some (.disposing work) from rfl)) ?_
  refine .cons (middle := .values (signature := signature) (algebra := leafAlgebra) ⟨7⟩ (.failed 20) afterOutside startedValues) (.enterValues rfl) ?_
  refine .cons (middle := .values (signature := signature) (algebra := leafAlgebra) ⟨7⟩ (.failed 20) afterOutside enteredValues) (.values (ValueDisposalStep.enterControl (signature := signature) (algebra := leafAlgebra) (runtime := work.runtime) (acquired := ⟨afterStore, ⟨controlShape, saved⟩⟩) rfl)) ?_
  refine .cons (middle := .values (signature := signature) (algebra := leafAlgebra) ⟨7⟩ (.failed 20) afterOutside completedValues) (.values (.control (.unwind (.complete rfl)))) ?_
  exact .cons (.values .finishControl) (.cons (.finishValues (show finishedValues.finished = some releasedRuntime from rfl)) .refl)

theorem a_stale_nonowning_control_view_does_not_create_disposal_work :
    finalizeCleanup (some (.continuation ⟨10⟩ none : Target.RuntimeValue signature leafAlgebra [] controlType)) exit =
      some (.exiting exit) := rfl

end BoundaryV2.Generalized.Examples.CleanupCompletion
