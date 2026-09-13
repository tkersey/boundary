import BoundaryV2.GeneralizedTemplates
import BoundaryV2.GeneralizedCellExecution
import BoundaryV2.GeneralizedCellExamples

namespace BoundaryV2.Generalized.Examples

open Target.Multi

abbrev templateShape : ControlShape signature := ⟨.shallow, .choose, .unit, .leaf .integer⟩
abbrev TemplateClosure : TypeOf signature := .computation .reusable [] (.capability .choose)
abbrev TemplateControl : TypeOf signature := .continuation .shallow .multi .choose .unit (.leaf .integer)
abbrev TemplateBindings : List (TypeOf signature) :=
  [.cell (.leaf .integer), .cell (.leaf .integer), TemplateClosure, TemplateControl]

def templateDormantClosure : Target.RuntimeValue signature algebra [] TemplateClosure :=
  .closure (.push (.capability ⟨9⟩) .ret)
    (.cons (.cell (type := .leaf Data.integer) ⟨7⟩ ⟨3⟩)
      (.cons (.cell (type := .leaf Data.integer) ⟨7⟩ ⟨3⟩) .nil)) none

def templateBindings : Target.RuntimeEnvironment signature algebra [] TemplateBindings :=
  .cons (.cell ⟨7⟩ ⟨3⟩) (.cons (.cell ⟨2⟩ ⟨0⟩)
    (.cons templateDormantClosure (.cons (.continuation ⟨6⟩ none) .nil)))

def templateFuture : Target.Resumption signature algebra [] .shallow .choose .unit (.leaf .integer) :=
  ⟨⟨9⟩, .push (.returnTo (.enter (.load (.there .here) (.cellRead .ret))) templateBindings .nil) .done⟩

def templateImage : Image signature algebra [] templateShape :=
  ⟨templateFuture, [⟨⟨7⟩, ⟨3⟩, .leaf .integer, .datum (.leaf 0)⟩],
    [Record.bare ⟨6⟩ templateShape templateFuture], [⟨9⟩], [⟨3⟩], []⟩

def branchingTemplate : Template signature algebra [] templateShape := ⟨templateImage, by decide⟩

def templateArena : Arena signature algebra [] := ⟨currentOuterCell, [], []⟩
def templateFirst := instantiate branchingTemplate templateArena []
def templateSecond := instantiate branchingTemplate templateFirst.arena []

theorem reusable_template_is_admitted : admit templateImage = some branchingTemplate := rfl

theorem reentrant_activation_allocates_distinct_local_names :
    (allocation templateImage templateArena []).name .cell ⟨7⟩ = ⟨15⟩ ∧
    (allocation templateImage templateFirst.arena []).name .cell ⟨7⟩ = ⟨23⟩ ∧
    templateFirst.saved.attachment = ⟨19⟩ ∧ templateSecond.saved.attachment = ⟨29⟩ ∧
    templateFirst.arena.dormant.map Record.identity = [⟨13⟩] ∧
    templateSecond.arena.dormant.map Record.identity = [⟨20⟩, ⟨13⟩] := by decide

def clonedDormantClosure : Target.RuntimeValue signature algebra [] TemplateClosure :=
  .closure (.push (.capability ⟨19⟩) .ret)
    (.cons (.cell (type := .leaf Data.integer) ⟨15⟩ ⟨7⟩)
      (.cons (.cell (type := .leaf Data.integer) ⟨15⟩ ⟨7⟩) .nil)) none

theorem dormant_code_cell_aliases_and_recursive_template_reference_are_renamed :
    Target.relocateEnvironment (allocation templateImage templateArena []) templateBindings =
      .cons (.cell ⟨15⟩ ⟨7⟩) (.cons (.cell ⟨2⟩ ⟨0⟩)
        (.cons clonedDormantClosure (.cons (.continuation ⟨13⟩ none) .nil))) := rfl

def writtenTemplateCells : ExampleCells :=
  [⟨⟨23⟩, ⟨11⟩, .leaf .integer, .datum (.leaf 0)⟩,
   ⟨⟨15⟩, ⟨7⟩, .leaf .integer, .datum (.leaf 7)⟩,
   ⟨⟨2⟩, ⟨0⟩, .leaf .integer, .datum (.leaf 99)⟩]

theorem one_branch_write_preserves_the_other_branch_and_current_outer_state :
    Cells.writeCopy (signature := signature) (algebra := algebra) ⟨15⟩ ⟨7⟩
      (.datum (.leaf (type := Data.integer) 7)) templateSecond.arena.cells = some writtenTemplateCells ∧
    Cells.readCopy (signature := signature) (algebra := algebra) ⟨23⟩ ⟨11⟩ (.leaf .integer) writtenTemplateCells =
      some (.datum (.leaf 0)) ∧
    Cells.readCopy (signature := signature) (algebra := algebra) ⟨2⟩ ⟨0⟩ (.leaf .integer) writtenTemplateCells =
      some (.datum (.leaf 99)) := by
  have cells : templateSecond.arena.cells =
      [⟨⟨23⟩, ⟨11⟩, .leaf .integer, .datum (.leaf 0)⟩,
       ⟨⟨15⟩, ⟨7⟩, .leaf .integer, .datum (.leaf 0)⟩,
       ⟨⟨2⟩, ⟨0⟩, .leaf .integer, .datum (.leaf 99)⟩] := rfl
  simp [cells, Cells.writeCopy, Cells.exchange, Cells.readCopy, Cells.read, Cells.lookup,
    writtenTemplateCells, Value.copyable, Datum.copyable]

def templateExecutionStart : Target.State signature algebra [] (.leaf .integer) :=
  ⟨⟨⟨⟨[], [], []⟩, [], []⟩, Target.reenter templateFirst.saved (.datum .unit) .done⟩,
    writtenTemplateCells, [⟨0⟩, ⟨7⟩, ⟨11⟩]⟩

def templateExecutionEnd : Target.State signature algebra [] (.leaf .integer) :=
  ⟨⟨⟨⟨[], [], []⟩, [], []⟩, .returned (.datum (.leaf 7)) .done⟩,
    writtenTemplateCells, [⟨0⟩, ⟨7⟩, ⟨11⟩]⟩

theorem instantiated_future_executes_against_its_branch_cell :
    Target.CellSteps (.nil : Target.Definitions signature algebra []) templateExecutionStart 5 templateExecutionEnd := by
  refine .cons (.ordinary .caller) ?_
  refine .cons (.ordinary .enter) ?_
  refine .cons (.ordinary (.operand (.load))) ?_
  refine .cons (.read (identity := ⟨15⟩) (region := ⟨7⟩)
    (value := (.datum (.leaf 7) : Target.RuntimeValue signature algebra [] (.leaf .integer))) (by decide) ?_) ?_
  · simp [Cells.readCopy, Cells.read, Cells.lookup, writtenTemplateCells, Value.copyable, Datum.copyable]
  exact .cons (.ordinary .returned) .refl

def exclusiveTemplateImage : Image signature algebra [] templateShape :=
  { templateImage with cells := exclusiveCell }

theorem exclusive_captures_cannot_become_multi_templates : admit exclusiveTemplateImage = none := by decide

def hiddenCaptureTemplateImage : Image signature algebra [] templateShape :=
  { templateImage with cells := [⟨⟨8⟩, ⟨3⟩, .computation .reusable [] .unit, mislabeledReusableClosure⟩] }

theorem reusable_label_cannot_hide_an_exclusive_template_capture : admit hiddenCaptureTemplateImage = none := by decide

def literalOwnerTemplateImage : Image signature algebra [] templateShape :=
  { templateImage with saved := ⟨⟨9⟩, .push (.returnTo
    (.enter (.push (.resource (name := ⟨0⟩) ⟨5⟩ ⟨6⟩ (.lexical ⟨0⟩ 0))
      (.enter (.push (.leaf (type := Data.integer) 0) .ret)))) .nil .nil) .done⟩ }

theorem dormant_code_cannot_hide_an_exclusive_template_constant :
    literalOwnerTemplateImage.saved.future.copyable = true ∧ admit literalOwnerTemplateImage = none := by decide

def cleanupTemplateImage : Image signature algebra [] templateShape :=
  { templateImage with saved := ⟨⟨9⟩, .push (.protection ⟨4⟩ (.push .unit .ret) .nil) templateFuture.future⟩ }

theorem outstanding_cleanup_cannot_become_a_multi_template : admit cleanupTemplateImage = none := by decide

end BoundaryV2.Generalized.Examples
