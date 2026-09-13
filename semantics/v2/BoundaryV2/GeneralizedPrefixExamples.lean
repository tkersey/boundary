import BoundaryV2.GeneralizedProgramSimulation
import BoundaryV2.GeneralizedCellExecutionExamples
import BoundaryV2.GeneralizedSelectionRelocation

namespace BoundaryV2.Generalized.Examples

def failingCellPrefix : Source.Computation signature algebra [] [.resource ⟨0⟩]
    (.cell (.product (.resource ⟨0⟩) (.leaf .integer))) :=
  .cellNew (.datum (.region ⟨0⟩)) (.pair (.reference .here)
    (.primitive .addByte (.cons (.datum (.leaf 100)) (.cons (.datum (.leaf 100)) .nil))))

theorem failing_initializer_has_a_source_transition :
    Source.Step (.nil : Source.Definitions signature algebra [])
      (.evaluate failingCellPrefix ownedCellSourceBindings) (.failed .overflow) := .operandFault rfl

def failingCellBefore : Target.State signature algebra [] (.cell (.product (.resource ⟨0⟩) (.leaf .integer))) :=
  ⟨⟨ownedCellTargetStore, .code (Defunctionalization.computation failingCellPrefix)
    (Defunctionalization.environment ownedCellSourceBindings) .nil .done⟩, [], [⟨0⟩]⟩

def failingCellAfter : Target.State signature algebra [] (.cell (.product (.resource ⟨0⟩) (.leaf .integer))) :=
  ⟨⟨ownedCellTargetStore, .failed .overflow .done⟩, [], [⟨0⟩]⟩

/-- The earlier resource value remains in the evaluating fields for exit.
The failing initializer neither allocates a cell nor transfers that owner. -/
theorem failing_initializer_preserves_earlier_owner_before_exit :
    (∃ count, Target.CellSteps (.nil : Target.Definitions signature algebra []) failingCellBefore count failingCellAfter) ∧
    failingCellBefore.physicalInventory = [⟨6⟩] ∧ failingCellAfter.physicalInventory = [⟨6⟩] ∧
    failingCellAfter.cells = [] ∧ failingCellAfter.control.store.fields.spent = [] := by
  obtain ⟨next, compiled⟩ := Defunctionalization.computation_has_operand_prefix failingCellPrefix
  obtain ⟨count, after, steps, faulted⟩ := Defunctionalization.arguments_fault_drains
    failingCellPrefix.operandPrefix.arguments ownedCellSourceBindings next .nil .overflow rfl
  cases faulted
  refine ⟨⟨count + 1, ?_⟩, rfl, rfl, rfl, rfl⟩
  have run := (steps.with_cells (.nil : Target.Definitions signature algebra []) .done ownedCellTargetStore [] [⟨0⟩]).trans
    (Target.CellSteps.single (.ordinary .fault))
  simpa only [failingCellBefore, failingCellAfter, compiled] using run

theorem initializer_fault_cannot_be_reported_as_return_yield_or_request
    (observation : Target.Observation signature algebra [] (.cell (.product (.resource ⟨0⟩) (.leaf .integer)))) :
    Target.Observes .nil failingCellBefore.control.configuration observation ↔ observation = .failed .overflow :=
  Defunctionalization.compiled_operand_fault_observation .nil failingCellPrefix ownedCellSourceBindings rfl observation

def retainedCleanupCode : Source.Computation signature algebra [] [.exit] .unit :=
  .yieldThen (.returnValue (.datum .unit))

def retainedSourceScope (type : TypeOf signature) : Source.Context signature algebra [] type type :=
  .push (.protection ⟨4⟩ retainedCleanupCode .nil) (.push (.region ⟨0⟩) .done)

def retainedTargetScope (type : TypeOf signature) : Target.Stack signature algebra [] type type :=
  .push (.protection ⟨4⟩ (Defunctionalization.computation retainedCleanupCode) .nil) (.push (.region ⟨0⟩) .done)

theorem retained_scopes_are_represented (type : TypeOf signature) :
    Defunctionalization.ContextRelated signature algebra [] (retainedSourceScope type) (retainedTargetScope type) :=
  .push (.protection (signature := signature) (algebra := algebra) (program := []) ⟨4⟩ retainedCleanupCode .nil)
    (.push (.region ⟨0⟩) .done)

def protectedYieldBody : Source.Computation signature algebra [] [] .unit := .yieldThen (.returnValue (.datum .unit))

theorem yield_is_visible_without_releasing_region_or_cleanup :
    Source.Steps (.nil : Source.Definitions signature algebra [])
      ((retainedSourceScope .unit).plug (.evaluate protectedYieldBody .nil)) 3
      (.yielded ((retainedSourceScope .unit).plug (.evaluate (.returnValue (.datum .unit)) .nil))) ∧
    Target.CallSteps (.nil : Target.Definitions signature algebra [])
      (.code (Defunctionalization.computation protectedYieldBody) .nil .nil (retainedTargetScope .unit)) 1
      (.yielded (.code (Defunctionalization.computation (.returnValue (.datum .unit))) .nil .nil (retainedTargetScope .unit))) := by
  exact ⟨.cons (Source.Step.in_context .yield _) ((retainedSourceScope .unit).forward_yield .nil _), .single .yield⟩

theorem request_is_forwarded_with_region_and_cleanup_retained :
    Source.Steps (.nil : Source.Definitions signature algebra [])
      ((retainedSourceScope (.leaf .text)).plug (.request Operation.text ⟨4⟩ (.datum (.leaf true)) .nil .done)) 2
      (.request Operation.text ⟨4⟩ (.datum (.leaf true)) .nil (retainedSourceScope (.leaf .text))) ∧
    Target.HeadObservation (signature := signature) (algebra := algebra)
      (.requested Operation.text ⟨4⟩ (.datum (.leaf true)) .nil (retainedTargetScope (.leaf .text)))
      (.requested Operation.text ⟨4⟩ (.datum (.leaf true)) .nil (retainedTargetScope (.leaf .text))) := by
  exact ⟨.cons (.regionStep .protectionRequest) (.cons .regionRequest .refl),
    .requested (Target.no_selection_is_external (signature := signature) (algebra := algebra)
      Operation.text ⟨4⟩ (retainedTargetScope (.leaf .text)) rfl)⟩

def choiceOfAttachment : Target.Configuration signature algebra [] .unit :=
  .code (Defunctionalization.computation
    (.handle .choose .deep (.returnValue (.reference .here)) .nil (.returnValue (.datum .unit)))) .nil .nil .done

def installedNames (attachment : Id .attachment) : List (Id .attachment) :=
  ((Target.nextWithAttachment .nil attachment choiceOfAttachment).map fun configuration =>
    match configuration with
    | .code _ _ _ future => future.attachments
    | _ => []).getD []

theorem installation_choice_is_preserved_as_nominal_data :
    choiceOfAttachment.installsHandler = true ∧ installedNames ⟨1⟩ = [⟨1⟩] ∧ installedNames ⟨2⟩ = [⟨2⟩] := by decide

end BoundaryV2.Generalized.Examples
