import BoundaryV2.GeneralizedRegisteredResume
import BoundaryV2.GeneralizedRegistryExamples

namespace BoundaryV2.Generalized.Examples.Dormant

abbrev ChildBindings : List (TypeOf signature) :=
  [.cell (.leaf .integer), .cell (.leaf .integer), .cell (.leaf .integer), FrozenReference]
def childBindings : Source.RuntimeEnvironment signature algebra [] ChildBindings :=
  .cons (.cell ⟨12⟩ ⟨6⟩) (.cons (.cell ⟨7⟩ ⟨3⟩) (.cons (.cell ⟨2⟩ ⟨0⟩) (.cons (.continuation ⟨7⟩ none) .nil)))
def childFuture : Source.Multi.Future signature algebra [] templateShape :=
  ⟨⟨30⟩, .bind (.cellRead (.reference (.there .here))) childBindings .done⟩
def grandBindings : Source.RuntimeEnvironment signature algebra [] [FrozenReference] := .cons (.continuation ⟨6⟩ none) .nil
def grandFuture : Source.Multi.Future signature algebra [] templateShape :=
  ⟨⟨30⟩, .bind (.returnValue (.datum (.leaf 5))) grandBindings .done⟩
def grand : Source.Multi.Record signature algebra [] := Source.Multi.Record.bare ⟨7⟩ templateShape grandFuture
def child : Source.Multi.Record signature algebra [] :=
  ⟨⟨6⟩, templateShape, childFuture, [⟨⟨12⟩, ⟨6⟩, .leaf .integer, .datum (.leaf 8)⟩], [grand], [⟨30⟩], [⟨6⟩], []⟩
def image : Source.Multi.Image signature algebra [] templateShape := { sourceTemplateImage with dormant := [child] }
def template : Source.Multi.Template signature algebra [] templateShape := ⟨image, by decide⟩
def registry : Source.Multi.Registry signature algebra [] := [⟨⟨10⟩, ⟨templateShape, template⟩⟩]
def runtime : Source.Multi.Runtime signature algebra [] .unit :=
  ⟨⟨sourceRegistered.control.store, .returned (.datum .unit)⟩, sourceFrozenControl.arena, [⟨0⟩], registry⟩
def relocation := Source.Multi.allocation image runtime.arena (runtime.support [])
def parentActivation := Source.Multi.instantiate template runtime.arena (runtime.support [])
def copiedChild := child.relocate relocation
def copiedGrand := grand.relocate relocation
def childTemplate : Source.Multi.Template signature algebra [] templateShape := ⟨copiedChild.image, by decide⟩
def grandTemplate : Source.Multi.Template signature algebra [] templateShape := ⟨copiedGrand.image, by decide⟩
def parentRegistry : Source.Multi.Registry signature algebra [] :=
  [⟨⟨18⟩, ⟨templateShape, grandTemplate⟩⟩, ⟨⟨17⟩, ⟨templateShape, childTemplate⟩⟩, ⟨⟨10⟩, ⟨templateShape, template⟩⟩]

theorem dormant_private_names_participate_in_parent_allocation :
    image.locals .cell = [⟨7⟩, ⟨12⟩] ∧ image.locals .control = [⟨6⟩, ⟨7⟩] ∧
    relocation.name .cell ⟨7⟩ = ⟨20⟩ ∧ relocation.name .cell ⟨12⟩ = ⟨25⟩ ∧
    copiedChild.identity = ⟨17⟩ ∧ copiedGrand.identity = ⟨18⟩ := ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩

theorem parent_activation_publishes_every_nested_binding_atomically :
    runtime.activate templateShape ⟨10⟩ [] = some ⟨parentActivation, [⟨10⟩, ⟨0⟩], parentRegistry⟩ := by
  have selected : TemplateRegistry.lookup templateShape ⟨10⟩ registry = some template :=
    UseScope.unpack_control_exact _ _
  unfold Source.Multi.Runtime.activate
  change (TemplateRegistry.lookup templateShape ⟨10⟩ registry).bind _ = _
  rw [selected]
  rfl

theorem dormant_cells_stay_in_the_snapshot_until_child_activation :
    parentActivation.arena.cells.identities = [⟨20⟩, ⟨2⟩] ∧ copiedChild.cells.identities = [⟨25⟩] ∧
    copiedChild.regions = [⟨13⟩] ∧
    Source.Multi.Future.references copiedGrand.saved =
      [.name .attachment ⟨61⟩, .name .control ⟨17⟩] := ⟨rfl, rfl, rfl, rfl⟩

theorem installed_root_and_child_keep_their_actual_templates :
    TemplateRegistry.lookup templateShape ⟨10⟩ parentRegistry = some template ∧
    TemplateRegistry.lookup templateShape ⟨17⟩ parentRegistry = some childTemplate ∧
    TemplateRegistry.lookup templateShape ⟨18⟩ parentRegistry = some grandTemplate := by
  exact ⟨UseScope.unpack_control_exact _ _, UseScope.unpack_control_exact _ _, UseScope.unpack_control_exact _ _⟩

def currentCells : Cells signature algebra (Source.Computation signature algebra []) :=
  [⟨⟨20⟩, ⟨10⟩, .leaf .integer, .datum (.leaf 4)⟩, ⟨⟨2⟩, ⟨0⟩, .leaf .integer, .datum (.leaf 100)⟩]
def current : Source.Multi.Runtime signature algebra [] .unit :=
  { runtime with arena := { parentActivation.arena with cells := currentCells }, regions := [⟨10⟩, ⟨0⟩], registry := parentRegistry }
def childRelocation := Source.Multi.allocation childTemplate.image current.arena (current.support [])
def childActivation := Source.Multi.instantiate childTemplate current.arena (current.support [])
def newGrand := copiedGrand.relocate childRelocation
def newGrandTemplate : Source.Multi.Template signature algebra [] templateShape := ⟨newGrand.image, by decide⟩
def childRegistry : Source.Multi.Registry signature algebra [] := ⟨⟨37⟩, ⟨templateShape, newGrandTemplate⟩⟩ :: parentRegistry

theorem child_activation_uses_its_snapshot_and_current_outer_state :
    current.activate templateShape ⟨17⟩ [] = some ⟨childActivation, [⟨27⟩, ⟨10⟩, ⟨0⟩], childRegistry⟩ ∧
    childActivation.arena.cells.identities = [⟨51⟩, ⟨20⟩, ⟨2⟩] ∧
    Cells.readCopy (signature := signature) (algebra := algebra) ⟨51⟩ ⟨27⟩ (.leaf .integer) childActivation.arena.cells = some (.datum (.leaf 8)) ∧
    Cells.readCopy (signature := signature) (algebra := algebra) ⟨20⟩ ⟨10⟩ (.leaf .integer) childActivation.arena.cells = some (.datum (.leaf 4)) ∧
    Cells.readCopy (signature := signature) (algebra := algebra) ⟨2⟩ ⟨0⟩ (.leaf .integer) childActivation.arena.cells = some (.datum (.leaf 100)) := by
  refine ⟨?_, rfl, ?_, ?_, ?_⟩
  · have selected : TemplateRegistry.lookup templateShape ⟨17⟩ parentRegistry = some childTemplate :=
      UseScope.unpack_control_exact _ _
    unfold Source.Multi.Runtime.activate
    change (TemplateRegistry.lookup templateShape ⟨17⟩ parentRegistry).bind _ = _
    rw [selected]
    rfl
  all_goals
    have cells : childActivation.arena.cells =
        [⟨⟨51⟩, ⟨27⟩, .leaf .integer, .datum (.leaf 8)⟩,
         ⟨⟨20⟩, ⟨10⟩, .leaf .integer, .datum (.leaf 4)⟩,
         ⟨⟨2⟩, ⟨0⟩, .leaf .integer, .datum (.leaf 100)⟩] := rfl
    simp [cells, Cells.readCopy, Cells.read, Cells.lookup, Value.copyable, Datum.copyable]

theorem nested_back_reference_stays_bound_to_the_existing_child :
    Source.Multi.Future.references newGrand.saved = [.name .attachment ⟨123⟩, .name .control ⟨17⟩] := rfl

def targetRuntime : Target.Multi.Runtime signature algebra [] .unit :=
  ⟨⟨Defunctionalization.templateHeap sourceFrozenControl.store, .returned (.datum .unit) .done⟩,
    Defunctionalization.templateArena runtime.arena, runtime.regions, Defunctionalization.templateRegistry registry⟩

theorem target_activation_installs_the_same_nested_snapshot_bindings :
    targetRuntime.activate templateShape ⟨10⟩ [] =
      some ⟨Defunctionalization.templateActivation parentActivation, [⟨10⟩, ⟨0⟩], Defunctionalization.templateRegistry parentRegistry⟩ := by
  have related : Defunctionalization.MultiDataRelated runtime targetRuntime :=
    ⟨Defunctionalization.template_heap_correspondence sourceFrozenControl.store, rfl, rfl, rfl⟩
  rw [Defunctionalization.registered_activation_corresponds related, parent_activation_publishes_every_nested_binding_atomically]
  rfl

def exclusiveGrand : Source.Multi.Record signature algebra [] :=
  { grand with cells := [⟨⟨14⟩, ⟨8⟩, .resource ⟨0⟩, .datum (.resource ⟨50⟩ ⟨700⟩ (.lexical ⟨0⟩ 0))⟩], regions := [⟨8⟩] }
def exclusiveImage : Source.Multi.Image signature algebra [] templateShape :=
  { image with dormant := [{ child with dormant := [exclusiveGrand] }] }

theorem exclusive_capture_hidden_two_levels_down_is_rejected :
    Source.Multi.admit exclusiveImage = none ∧
    Target.Multi.admit (Defunctionalization.templateImage exclusiveImage) = none := by
  constructor
  · rfl
  · rw [Defunctionalization.template_admission_corresponds]
    rfl

theorem duplicate_nested_binding_does_not_publish_a_partial_registry :
    Source.Multi.registerRecords [copiedChild, copiedGrand] registry = none := rfl

theorem nested_registration_preserves_the_original_root_binding :
    TemplateRegistry.lookup templateShape ⟨10⟩ parentRegistry = some template := by
  apply Source.Multi.registerRecords_preserves_existing [copiedChild] (registry := registry)
  · exact rfl
  · exact UseScope.unpack_control_exact _ _

end BoundaryV2.Generalized.Examples.Dormant
