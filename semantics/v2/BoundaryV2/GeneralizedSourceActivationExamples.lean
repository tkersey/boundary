import BoundaryV2.GeneralizedSourceActivation
import BoundaryV2.GeneralizedSourceFreezeExamples

namespace BoundaryV2.Generalized.Examples

def sourceFirstActivation := Source.Multi.instantiate sourceFrozenControl.template sourceFrozenControl.arena []
def sourceSecondActivation := Source.Multi.instantiate sourceFrozenControl.template sourceFirstActivation.arena []

theorem source_activations_compile_to_the_existing_target_branches :
    Defunctionalization.templateActivation sourceFirstActivation = templateFirst ∧
    Defunctionalization.templateActivation sourceSecondActivation = templateSecond := by
  have first : Defunctionalization.templateActivation sourceFirstActivation = templateFirst :=
    (Defunctionalization.template_instantiation_corresponds sourceFrozenControl.template sourceFrozenControl.arena []).symm
  refine ⟨first, ?_⟩
  have second := Defunctionalization.template_instantiation_corresponds sourceFrozenControl.template sourceFirstActivation.arena []
  have arena : Defunctionalization.templateArena sourceFirstActivation.arena = templateFirst.arena :=
    congrArg Target.Multi.Activation.arena first
  rw [arena] at second
  exact second.symm

theorem source_reentrant_activations_have_distinct_local_cells_and_dormant_controls :
    sourceFirstActivation.saved.attachment = ⟨19⟩ ∧ sourceSecondActivation.saved.attachment = ⟨29⟩ ∧
    sourceFirstActivation.arena.cells.identities = [⟨15⟩, ⟨2⟩] ∧
    sourceSecondActivation.arena.cells.identities = [⟨23⟩, ⟨15⟩, ⟨2⟩] ∧
    sourceSecondActivation.arena.dormant.map Source.Multi.Record.identity = [⟨20⟩, ⟨13⟩] := ⟨rfl, rfl, rfl, rfl, rfl⟩

def sourceClonedClosure : Source.RuntimeValue signature algebra [] TemplateClosure :=
  .closure (.returnValue (.datum (.capability ⟨19⟩)))
    (.cons (.cell (type := .leaf Data.integer) ⟨15⟩ ⟨7⟩)
      (.cons (.cell (type := .leaf Data.integer) ⟨15⟩ ⟨7⟩) .nil)) none

def sourceClonedBindings : Source.RuntimeEnvironment signature algebra [] TemplateBindings :=
  .cons (.cell ⟨15⟩ ⟨7⟩) (.cons (.cell ⟨2⟩ ⟨0⟩)
    (.cons sourceClonedClosure (.cons (.continuation ⟨13⟩ none) .nil)))

def sourceClonedFuture : Source.Multi.Future signature algebra [] templateShape :=
  ⟨⟨19⟩, .bind (.cellRead (.reference (.there .here))) sourceClonedBindings .done⟩

theorem source_activation_relocates_dormant_code_and_every_alias_together :
    sourceFirstActivation.saved = sourceClonedFuture ∧
    sourceFirstActivation.arena.dormant = [⟨⟨13⟩, templateShape, sourceClonedFuture⟩] := ⟨rfl, rfl⟩

def sourceWrittenCells : Cells signature algebra (Source.Computation signature algebra []) :=
  [⟨⟨23⟩, ⟨11⟩, .leaf .integer, .datum (.leaf 0)⟩,
   ⟨⟨15⟩, ⟨7⟩, .leaf .integer, .datum (.leaf 7)⟩,
   ⟨⟨2⟩, ⟨0⟩, .leaf .integer, .datum (.leaf 99)⟩]

theorem source_branch_write_preserves_the_other_branch_and_current_shared_cell :
    Cells.writeCopy (signature := signature) (algebra := algebra) ⟨15⟩ ⟨7⟩
      (.datum (.leaf (type := Data.integer) 7)) sourceSecondActivation.arena.cells = some sourceWrittenCells ∧
    Cells.readCopy (signature := signature) (algebra := algebra) ⟨23⟩ ⟨11⟩ (.leaf .integer) sourceWrittenCells =
      some (.datum (.leaf 0)) ∧
    Cells.readCopy (signature := signature) (algebra := algebra) ⟨2⟩ ⟨0⟩ (.leaf .integer) sourceWrittenCells =
      some (.datum (.leaf 99)) := by
  have cells : sourceSecondActivation.arena.cells =
      [⟨⟨23⟩, ⟨11⟩, .leaf .integer, .datum (.leaf 0)⟩,
       ⟨⟨15⟩, ⟨7⟩, .leaf .integer, .datum (.leaf 0)⟩,
       ⟨⟨2⟩, ⟨0⟩, .leaf .integer, .datum (.leaf 99)⟩] := rfl
  simp [cells, Cells.writeCopy, Cells.exchange, Cells.readCopy, Cells.read, Cells.lookup,
    sourceWrittenCells, Value.copyable, Datum.copyable]

def sourceActivationStart : Source.State signature algebra [] (.leaf .integer) :=
  ⟨⟨Source.Multi.sourceHeap sourceFrozenControl.store, Source.reenter sourceFirstActivation.saved.payload (.returned (.datum .unit))⟩,
    sourceWrittenCells, [⟨0⟩, ⟨7⟩, ⟨11⟩]⟩

def sourceActivationRead : Source.State signature algebra [] (.leaf .integer) :=
  ⟨⟨Source.Multi.sourceHeap sourceFrozenControl.store,
    .evaluate (.cellRead (.reference (.there .here))) (.cons (.datum .unit) sourceClonedBindings)⟩,
    sourceWrittenCells, [⟨0⟩, ⟨7⟩, ⟨11⟩]⟩

def sourceActivationEnd : Source.State signature algebra [] (.leaf .integer) :=
  ⟨⟨Source.Multi.sourceHeap sourceFrozenControl.store, .returned (.datum (.leaf 7))⟩,
    sourceWrittenCells, [⟨0⟩, ⟨7⟩, ⟨11⟩]⟩

theorem activated_source_callback_executes_the_correct_branch_cell_read :
    Source.ExecutionStep (.nil : Source.Definitions signature algebra []) sourceActivationStart sourceActivationRead ∧
    Source.ExecutionStep (.nil : Source.Definitions signature algebra []) sourceActivationRead sourceActivationEnd := by
  refine ⟨.cell (.ordinary .bindValue), .cell (Source.CellStep.read
    (outside := .done) (store := Source.Multi.sourceHeap sourceFrozenControl.store)
    (bindings := .cons (.datum .unit) sourceClonedBindings) (cells := sourceWrittenCells)
    (reference := .reference (.there .here)) (identity := ⟨15⟩) (region := ⟨7⟩)
    (regions := [⟨0⟩, ⟨7⟩, ⟨11⟩])
    (value := (.datum (.leaf 7) : Source.RuntimeValue signature algebra [] (.leaf .integer)))
    .reference (by decide) ?_)⟩
  simp [Cells.readCopy, Cells.read, Cells.lookup, sourceWrittenCells, Value.copyable, Datum.copyable]

end BoundaryV2.Generalized.Examples
