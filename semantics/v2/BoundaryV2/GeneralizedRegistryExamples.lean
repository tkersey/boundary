import BoundaryV2.GeneralizedMultiEntry
import BoundaryV2.GeneralizedSourceFreezeExamples

namespace BoundaryV2.Generalized.Examples

def sourceRegistry : Source.Multi.Registry signature algebra [] :=
  [⟨freezeView.identity, ⟨templateShape, sourceBranchingTemplate⟩⟩]

theorem freezing_registers_the_actual_template :
    Source.Multi.freezeInto templateShape freezeView sourceFreezeStore sourceFreezeArena freezePartition [] =
      some (sourceFrozenControl, sourceRegistry) := by
  unfold Source.Multi.freezeInto
  rw [authored_source_freezes_its_registered_callback_and_current_cells]
  rfl

theorem registered_template_lookup :
    TemplateRegistry.lookup templateShape freezeView.identity sourceRegistry = some sourceBranchingTemplate := by
  change UseScope.unpackControl templateShape ⟨templateShape, sourceBranchingTemplate⟩ = some sourceBranchingTemplate
  exact UseScope.unpack_control_exact _ _

def registeredBindings : Source.RuntimeEnvironment signature algebra [] [FrozenReference] :=
  .cons sourceFrozenControl.value .nil

def registeredProgram : Source.Computation signature algebra [] [FrozenReference] (.leaf .integer) :=
  .resume (.reference .here) (.datum .unit)

def sourceRegistered : Source.Multi.Runtime signature algebra [] (.leaf .integer) :=
  ⟨⟨Source.Multi.sourceHeap sourceFrozenControl.store, .evaluate registeredProgram registeredBindings⟩,
    sourceFrozenControl.arena, [⟨0⟩], sourceRegistry⟩

def registeredExternal : List Reference :=
  Source.Multi.callSupport .nil registeredBindings
    (.done : Source.Context signature algebra [] (.leaf .integer) (.leaf .integer)) sourceRegistered.control.store

def registeredActivation := Source.Multi.instantiate sourceBranchingTemplate sourceRegistered.arena
  (sourceRegistered.support (Source.valueReferences (.datum .unit : Source.RuntimeValue signature algebra [] .unit) ++ registeredExternal))

def registeredDormantTemplate : Source.Multi.Template signature algebra [] templateShape :=
  ⟨⟨registeredActivation.saved, [], [], [], [], []⟩, by decide⟩
def activatedRegistry : Source.Multi.Registry signature algebra [] :=
  ⟨⟨17⟩, ⟨templateShape, registeredDormantTemplate⟩⟩ :: sourceRegistry

def sourceRegisteredAfter : Source.Multi.Runtime signature algebra [] (.leaf .integer) :=
  sourceRegistered.afterActivation ⟨registeredActivation, [⟨7⟩, ⟨0⟩], activatedRegistry⟩
    (Source.reenter registeredActivation.saved.payload (.returned (.datum .unit)))

theorem registered_resume_uses_current_cells_and_makes_local_regions_live :
    sourceRegistered.resume templateShape freezeView.identity (.datum .unit) .done registeredExternal = some sourceRegisteredAfter ∧
    sourceRegisteredAfter.regions = [⟨7⟩, ⟨0⟩] ∧ sourceRegisteredAfter.arena.cells.identities = [⟨15⟩, ⟨2⟩] ∧
    sourceRegisteredAfter.registry = activatedRegistry ∧
    sourceRegisteredAfter.control.store = sourceRegistered.control.store := by
  refine ⟨?_, rfl, rfl, rfl, rfl⟩
  unfold Source.Multi.Runtime.resume Source.Multi.Runtime.activate
  change ((TemplateRegistry.lookup templateShape freezeView.identity sourceRegistry).bind _).map _ = _
  rw [registered_template_lookup]
  rfl

theorem authored_multi_resume_has_a_positive_compiled_entry :
    Source.Multi.ResumeEntry (.nil : Source.Definitions signature algebra []) sourceRegistered sourceRegisteredAfter ∧
    ∃ targetAfter count, 0 < count ∧ Defunctionalization.MultiRuntimeRelated sourceRegisteredAfter targetAfter ∧
      Target.Multi.ResumeRun (.nil : Target.Definitions signature algebra [])
        ⟨⟨Defunctionalization.templateHeap sourceFrozenControl.store,
          .code (Defunctionalization.computation registeredProgram) (Defunctionalization.environment registeredBindings) .nil .done⟩,
          Defunctionalization.templateArena sourceRegistered.arena, [⟨0⟩], Defunctionalization.templateRegistry sourceRegistry⟩ count targetAfter :=
  Defunctionalization.compiled_multi_resumption .nil (.reference .here) (.datum .unit) registeredBindings freezeView.identity
    (.datum .unit) sourceRegistered.arena [⟨0⟩] sourceRegistry (.cons .reference (.cons .datum .nil))
    (Defunctionalization.template_heap_correspondence sourceFrozenControl.store) .done
    registered_resume_uses_current_cells_and_makes_local_regions_live.1

theorem the_registry_cannot_silently_rebind_a_retained_reference :
    TemplateRegistry.insert freezeView.identity sourceBranchingTemplate sourceRegistry = none ∧
    Source.Multi.freezeInto templateShape freezeView sourceFreezeStore sourceFreezeArena freezePartition sourceRegistry = none := by
  constructor
  · rfl
  · unfold Source.Multi.freezeInto
    rw [authored_source_freezes_its_registered_callback_and_current_cells]
    rfl

theorem unknown_reference_and_wrong_shape_reject_without_changing_the_binding :
    TemplateRegistry.lookup templateShape ⟨999⟩ sourceRegistry = none ∧
    TemplateRegistry.lookup (signature := signature) (⟨.shallow, .choose, .unit, .unit⟩ : ControlShape signature)
      freezeView.identity sourceRegistry = none ∧
    TemplateRegistry.lookup templateShape freezeView.identity sourceRegistry = some sourceBranchingTemplate := by
  refine ⟨rfl, ?_, registered_template_lookup⟩
  change UseScope.unpackControl (⟨.shallow, .choose, .unit, .unit⟩ : ControlShape signature)
    ⟨templateShape, sourceBranchingTemplate⟩ = none
  apply UseScope.unpack_control_wrong_shape
  intro same
  have answers := congrArg ControlShape.answer same
  cases answers

end BoundaryV2.Generalized.Examples
