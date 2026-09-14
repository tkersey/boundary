import BoundaryV2.GeneralizedSourceActivation
import BoundaryV2.GeneralizedExamples
import BoundaryV2.GeneralizedUnwinding

namespace BoundaryV2.Generalized.Examples.CleanupContext

def normal : ExitInfo Fault String := ⟨.normal, [], none⟩
def afterRequest : Source.Computation signature algebra [] [.leaf .boolean, .exit] .unit := .returnValue (.datum .unit)
def request : Source.Computation signature algebra [] [.exit] (.leaf .boolean) :=
  .perform (signature := signature) (algebra := algebra) Operation.choice (.datum (.capability ⟨8⟩)) (.datum .unit) .nil
def cleanup : Source.Computation signature algebra [] [.exit] .unit := .bind request afterRequest
def normalReturn : Source.Computation signature algebra [] [.leaf .integer] (.leaf .text) := .returnValue (.datum (.leaf "finished"))
def sourceClauses : Source.Clauses signature algebra [] .choose .deep [] (.leaf .integer) (.leaf .text) :=
  .cons Operation.choice .affine (.returnValue (.datum (.leaf "clause"))) .nil
def sourceBindings : Source.RuntimeEnvironment signature algebra [] [.exit] := .cons (.exit normal) .nil
def bindings := Defunctionalization.environment sourceBindings
def sourceOutside : Source.Context signature algebra [] (.leaf .integer) (.leaf .text) :=
  .push (.handler .choose .deep ⟨8⟩ normalReturn sourceClauses .nil) .done
def outside : Target.Stack signature algebra [] (.leaf .integer) (.leaf .text) :=
  .push (.handler .choose .deep ⟨8⟩ (Defunctionalization.computation normalReturn) (Defunctionalization.clauses sourceClauses) .nil) .done
def running : Target.Stack signature algebra [] .unit (.leaf .text) :=
  .push (.cleanupReturn ⟨7⟩ (some (.datum (.leaf (type := Data.integer) 42))) normal) outside
def bindingFuture : Target.Stack signature algebra [] (.leaf .boolean) (.leaf .text) :=
  .push (.returnTo (.enter (Defunctionalization.computation afterRequest)) bindings .nil) running
def pendingFuture : Target.Stack signature algebra [] (.leaf .boolean) (.leaf .text) :=
  .push (.returnTo .ret bindings .nil) bindingFuture
def inside : Target.Stack signature algebra [] (.leaf .boolean) (.leaf .integer) :=
  .push (.returnTo .ret bindings .nil)
    (.push (.returnTo (.enter (Defunctionalization.computation afterRequest)) bindings .nil)
      (.push (.cleanupReturn ⟨7⟩ (some (.datum (.leaf 42))) normal) .done))
def sourceInside : Source.Context signature algebra [] (.leaf .boolean) (.leaf .integer) :=
  .push (.bindAuthored afterRequest sourceBindings) (.push (.cleanupReturn ⟨7⟩ (some (.datum (.leaf (type := Data.integer) 42))) normal) .done)

def before : Target.Configuration signature algebra [] (.leaf .text) :=
  .returned (.datum (.leaf (type := Data.integer) 42)) (.push (.protection ⟨7⟩ (Defunctionalization.computation cleanup) .nil) outside)
def requested : Target.Configuration signature algebra [] (.leaf .text) :=
  .requested Operation.choice ⟨8⟩ (.datum .unit) .nil pendingFuture

theorem cleanup_request_keeps_its_actual_enclosing_handler :
    Target.CallSteps (.nil : Target.Definitions signature algebra []) before 5 requested ∧
    Target.select ⟨8⟩ pendingFuture = some
      ⟨.choose, .deep, ⟨8⟩, .leaf .integer, .leaf .text, [], Defunctionalization.computation normalReturn,
        Defunctionalization.clauses sourceClauses, .nil, inside, .done⟩ := by
  refine ⟨?_, rfl⟩
  refine .cons .protectionReturn ?_
  refine .cons .block ?_
  refine .cons (.operand .push) ?_
  refine .cons (.operand .push) ?_
  exact .single (Target.CallStep.dispatch (signature := signature) (algebra := algebra) (operation := Operation.choice) (bodies := .nil) (operands := .nil))

theorem running_cleanup_context_has_a_source_representation :
    Defunctionalization.ContextRelated signature algebra [] sourceInside inside :=
  .passthrough sourceBindings (.push (.bind afterRequest sourceBindings)
    (.push (Defunctionalization.FrameRelated.cleanupReturn (signature := signature) (algebra := algebra)
      ⟨7⟩ (some (.datum (.leaf (type := Data.integer) 42))) normal) .done))

def saved : Target.Resumption signature algebra [] .deep .choose (.leaf .boolean) (.leaf .text) :=
  Target.captureResumption (signature := signature) (algebra := algebra) .deep .choose ⟨8⟩ (Defunctionalization.computation normalReturn)
    (Defunctionalization.clauses sourceClauses) .nil inside
def sourceSaved : Source.Resumption signature algebra [] .deep .choose (.leaf .boolean) (.leaf .text) :=
  Source.captureResumption (signature := signature) (algebra := algebra) .deep .choose ⟨8⟩ normalReturn sourceClauses .nil sourceInside

theorem captured_cleanup_keeps_body_and_handler_answer_types_distinct :
    Defunctionalization.ResumptionRelated sourceSaved saved := by
  exact Defunctionalization.captured_resumption_corresponds (signature := signature) (algebra := algebra) .deep .choose ⟨8⟩ normalReturn sourceClauses .nil
    running_cleanup_context_has_a_source_representation

theorem resuming_cleanup_finishes_before_the_handlers_normal_return :
    Target.CallSteps (.nil : Target.Definitions signature algebra [])
      (Target.reenter saved (.datum (.leaf true)) .done) 10 (.returned (.datum (.leaf "finished")) .done) := by
  refine .cons .caller ?_
  refine .cons .returned ?_
  refine .cons .caller ?_
  refine .cons .enter ?_
  refine .cons (.operand .push) ?_
  refine .cons .returned ?_
  refine .cons (.cleanupReturn rfl) ?_
  refine .cons .handlerReturned ?_
  refine .cons (.operand .push) ?_
  exact .single .returned

def described : Source.Capture signature algebra [] (.leaf .boolean) (.leaf .text) :=
  .bind afterRequest sourceBindings
    (.cleanupReturn ⟨7⟩ (some (.datum (.leaf (type := Data.integer) 42))) normal
      (.handler .choose .deep ⟨8⟩ normalReturn sourceClauses .nil .done))
abbrev shape : ControlShape signature := ⟨.deep, .choose, .leaf .boolean, .leaf .text⟩
def sourceImage : Source.Multi.Image signature algebra [] shape := ⟨⟨⟨8⟩, described⟩, [], [], [], [], []⟩
def targetImage : Target.Multi.Image signature algebra [] shape := ⟨saved, [], [], [], [], []⟩

theorem an_already_running_cleanup_cannot_become_a_multi_template :
    Source.Multi.admit sourceImage = none ∧ Target.Multi.admit targetImage = none := ⟨rfl, rfl⟩

theorem unwinding_identifies_a_running_cleanup_without_restarting_it :
    Target.unwindBoundary running = .cleanupReturn ⟨7⟩ (some (.datum (.leaf (type := Data.integer) 42))) normal outside ∧
    ExitComposition.pendingProtections running = [] := ⟨rfl, rfl⟩

end BoundaryV2.Generalized.Examples.CleanupContext
