import BoundaryV2.GeneralizedMultiControlEntry
import BoundaryV2.GeneralizedRegisteredSimulation
import BoundaryV2.GeneralizedRegisteredReflection
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
      Target.Multi.Steps (.nil : Target.Definitions signature algebra [])
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

/-- One authored computation crosses clone, immutable registration, a normal
caller, reusable activation, and the branch's actual cell read. -/
def cloneResumeBody : Source.Computation signature algebra []
    (FrozenReference :: [.continuation .shallow .linear .choose .unit (.leaf .integer)]) (.leaf .integer) :=
  .resume (.reference .here) (.datum .unit)

def cloneResumeProgram : Source.Computation signature algebra []
    [.continuation .shallow .linear .choose .unit (.leaf .integer)] (.leaf .integer) :=
  .bind (.clone (.reference .here)) cloneResumeBody

def cloneResumeStart : Source.Multi.Runtime signature algebra [] (.leaf .integer) :=
  ⟨⟨Source.Multi.sourceHeap sourceFreezeStore, .evaluate cloneResumeProgram cloneSourceBindings⟩,
    sourceFreezeArena, [⟨3⟩, ⟨0⟩], []⟩

def cloneResumeEnd : Source.Multi.Runtime signature algebra [] (.leaf .integer) :=
  { sourceRegisteredAfter with control := ⟨sourceRegisteredAfter.control.store, .returned (.datum (.leaf 0))⟩ }

def sourceCloneResumeReady : Source.Multi.Runtime signature algebra [] (.leaf .integer) :=
  ⟨⟨Source.Multi.sourceHeap sourceFrozenControl.store,
    .evaluate cloneResumeBody (.cons sourceFrozenControl.value cloneSourceBindings)⟩,
    sourceFrozenControl.arena, [⟨0⟩], sourceRegistry⟩

def cloneResumeExternal : List Reference := Source.Multi.callSupport .nil
  (.cons sourceFrozenControl.value cloneSourceBindings)
  (.done : Source.Context signature algebra [] (.leaf .integer) (.leaf .integer)) sourceCloneResumeReady.control.store

theorem clone_resume_activation_uses_the_registered_arena :
    sourceCloneResumeReady.activate templateShape freezeView.identity cloneResumeExternal =
      some ⟨registeredActivation, [⟨7⟩, ⟨0⟩], activatedRegistry⟩ := by
  unfold Source.Multi.Runtime.activate
  change (TemplateRegistry.lookup templateShape freezeView.identity sourceRegistry).bind _ = _
  rw [registered_template_lookup]
  rfl

theorem source_clone_and_resume_compose_to_a_finite_observation :
    Source.Multi.Steps (.nil : Source.Definitions signature algebra []) cloneResumeStart 6 cloneResumeEnd := by
  refine .cons (.core (.cell (.ordinary .bind))) ?_
  refine .cons (Source.Multi.Step.clone (use := .linear) (partition := freezePartition)
    (expression := .reference .here) (bindings := cloneSourceBindings)
    (outside := .push (.bindAuthored cloneResumeBody cloneSourceBindings) .done)
    (store := sourceFreezeStore) (evaluated := sourceFreezeStore) (frozen := sourceFrozenControl)
    (view := freezeView) rfl rfl .reference freezing_registers_the_actual_template) ?_
  refine .cons (.core (.cell (.ordinary .bindValue))) ?_
  have resumed : Source.Multi.ResumeEntry (.nil : Source.Definitions signature algebra [])
      ⟨⟨Source.Multi.sourceHeap sourceFrozenControl.store,
        .evaluate cloneResumeBody (.cons sourceFrozenControl.value cloneSourceBindings)⟩,
        sourceFrozenControl.arena, [⟨0⟩], sourceRegistry⟩ sourceRegisteredAfter := by
    refine .enter (outside := .done) (.cons .reference (.cons .datum .nil)) ?_
    unfold Source.Multi.Runtime.resume Source.Multi.Runtime.activate
    change ((TemplateRegistry.lookup templateShape freezeView.identity sourceRegistry).bind _).map _ = _
    rw [registered_template_lookup]
    rfl
  refine .cons (.resume resumed) (.cons (.core (.cell (.ordinary .bindValue))) ?_)
  refine .cons (.core (.cell (Source.CellStep.read (outside := .done) (identity := ⟨15⟩) (region := ⟨7⟩)
    (value := (.datum (.leaf 0) : Source.RuntimeValue signature algebra [] (.leaf .integer)))
    .reference (by decide) ?_))) .refl
  change Cells.readCopy (signature := signature) (algebra := algebra) (Body := Source.Computation signature algebra []) ⟨15⟩ ⟨7⟩ (.leaf .integer)
    [⟨⟨15⟩, ⟨7⟩, .leaf .integer, .datum (.leaf 0)⟩, ⟨⟨2⟩, ⟨0⟩, .leaf .integer, .datum (.leaf 99)⟩] = _
  simp [Cells.readCopy, Cells.read, Cells.lookup, Value.copyable, Datum.copyable]

def targetCloneResumeStart : Target.Multi.Runtime signature algebra [] (.leaf .integer) :=
  ⟨⟨freezeStore, .code (Defunctionalization.computation cloneResumeProgram) freezeBindings .nil .done⟩,
    freezeArena, [⟨3⟩, ⟨0⟩], []⟩

def targetCloneResumeEnd : Target.Multi.Runtime signature algebra [] (.leaf .integer) :=
  ⟨⟨frozenControl.store, .returned (.datum (.leaf 0)) .done⟩, Defunctionalization.templateArena sourceRegisteredAfter.arena,
    [⟨7⟩, ⟨0⟩], Defunctionalization.templateRegistry activatedRegistry⟩


def targetCloneResumeReady : Target.Multi.Runtime signature algebra [] (.leaf .integer) :=
  ⟨⟨frozenControl.store, .code (.resume (use := Use.multi) .ret)
      (Defunctionalization.environment (.cons sourceFrozenControl.value cloneSourceBindings))
      (.cons (.datum .unit) (.cons frozenControl.value .nil)) .done⟩,
    frozenControl.arena, [⟨0⟩], Defunctionalization.templateRegistry sourceRegistry⟩

def targetCloneResumeActivated : Target.Multi.Runtime signature algebra [] (.leaf .integer) :=
  ⟨⟨frozenControl.store, Target.reenter (Defunctionalization.templateFuture registeredActivation.saved) (.datum .unit)
      (.push (.returnTo .ret (Defunctionalization.environment (.cons sourceFrozenControl.value cloneSourceBindings)) .nil) .done)⟩,
    Defunctionalization.templateArena sourceRegisteredAfter.arena, [⟨7⟩, ⟨0⟩],
    Defunctionalization.templateRegistry activatedRegistry⟩

theorem target_clone_and_resume_compose_to_the_same_finite_observation :
    Target.Multi.Steps (.nil : Target.Definitions signature algebra []) targetCloneResumeStart 16 targetCloneResumeEnd := by
  refine .cons (.core (.cell (.ordinary .block))) ?_
  refine .cons (.core (.cell (.ordinary (.operand .load)))) ?_
  refine .cons (Target.Multi.Step.clone (use := .linear) (partition := freezePartition)
    (frozen := frozenControl) (view := freezeView)
    (registered := Defunctionalization.templateRegistry sourceRegistry) rfl ?_) ?_
  · change Target.Multi.freezeInto templateShape freezeView freezeStore freezeArena freezePartition [] =
      some (frozenControl, Defunctionalization.templateRegistry sourceRegistry)
    unfold Target.Multi.freezeInto
    rw [owned_continuation_freezes_actual_future_and_local_cells.1]
    rfl
  refine .cons (.core (.cell (.ordinary .returned))) ?_
  refine .cons (.core (.cell (.ordinary .caller))) ?_
  refine .cons (.core (.cell (.ordinary .enter))) ?_
  refine .cons (.core (.cell (.ordinary (.operand .load)))) ?_
  refine .cons (.core (.cell (.ordinary (.operand .push)))) ?_
  change Target.Multi.Steps .nil targetCloneResumeReady 8 targetCloneResumeEnd
  refine .cons (.resume (.enter (after := targetCloneResumeActivated) ?_)) ?_
  · have joined : Defunctionalization.MultiDataRelated sourceCloneResumeReady targetCloneResumeReady :=
      ⟨Defunctionalization.template_heap_correspondence sourceFrozenControl.store, rfl, rfl, rfl⟩
    have supported := Defunctionalization.multi_call_support_corresponds
      (sourceOutside := (.done : Source.Context signature algebra [] (.leaf .integer) (.leaf .integer)))
      (targetOutside := (.done : Target.Stack signature algebra [] (.leaf .integer) (.leaf .integer)))
      (.nil : Source.Definitions signature algebra []) (.cons sourceFrozenControl.value cloneSourceBindings)
      Defunctionalization.ContextRelated.done (Defunctionalization.template_heap_correspondence sourceFrozenControl.store)
    change Target.Multi.callSupport .nil (Defunctionalization.environment (.cons sourceFrozenControl.value cloneSourceBindings))
      .nil .ret .done frozenControl.store = cloneResumeExternal at supported
    unfold Target.Multi.Runtime.resume
    change (targetCloneResumeReady.activate templateShape freezeView.identity
      (Target.Multi.callSupport .nil (Defunctionalization.environment (.cons sourceFrozenControl.value cloneSourceBindings))
        .nil .ret .done frozenControl.store)).map _ = _
    rw [supported]
    change (targetCloneResumeReady.activate templateShape freezeView.identity cloneResumeExternal).map _ = _
    rw [Defunctionalization.registered_activation_corresponds joined, clone_resume_activation_uses_the_registered_arena]
    rfl
  refine .cons (.core (.cell (.ordinary .caller))) ?_
  refine .cons (.core (.cell (.ordinary .enter))) ?_
  refine .cons (.core (.cell (.ordinary (.operand .load)))) ?_
  refine .cons (.core (.cell (.read (identity := ⟨15⟩) (region := ⟨7⟩)
    (value := (.datum (.leaf 0) : Target.RuntimeValue signature algebra [] (.leaf .integer))) (by decide) ?_))) ?_
  · change Cells.readCopy (signature := signature) (algebra := algebra)
      (Body := fun context result => Target.Code signature algebra [] context [] result) ⟨15⟩ ⟨7⟩ (.leaf .integer)
      [⟨⟨15⟩, ⟨7⟩, .leaf .integer, .datum (.leaf 0)⟩, ⟨⟨2⟩, ⟨0⟩, .leaf .integer, .datum (.leaf 99)⟩] = _
    simp [Cells.readCopy, Cells.read, Cells.lookup, Value.copyable, Datum.copyable]
  refine .cons (.core (.cell (.ordinary .returned))) ?_
  refine .cons (.core (.cell (.ordinary .caller))) ?_
  exact .cons (.core (.cell (.ordinary .returned))) .refl

theorem cloned_registered_observations_keep_current_resources :
    Source.Multi.Observes .nil cloneResumeStart cloneResumeEnd (.returned (.datum (.leaf 0))) ∧
    Target.Multi.Observes .nil targetCloneResumeStart targetCloneResumeEnd (.returned (.datum (.leaf 0))) ∧
    cloneResumeEnd.arena.cells = sourceRegisteredAfter.arena.cells ∧
    cloneResumeEnd.registry = activatedRegistry ∧
    Cells.readCopy (signature := signature) (algebra := algebra) ⟨2⟩ ⟨0⟩ (.leaf .integer) cloneResumeEnd.arena.cells =
      some (.datum (.leaf 99)) := by
  refine ⟨⟨6, source_clone_and_resume_compose_to_a_finite_observation, .returned⟩,
    ⟨16, target_clone_and_resume_compose_to_the_same_finite_observation, .returned⟩, rfl, rfl, ?_⟩
  change Cells.readCopy (signature := signature) (algebra := algebra) (Body := Source.Computation signature algebra []) ⟨2⟩ ⟨0⟩ (.leaf .integer)
    [⟨⟨15⟩, ⟨7⟩, .leaf .integer, .datum (.leaf 0)⟩, ⟨⟨2⟩, ⟨0⟩, .leaf .integer, .datum (.leaf 99)⟩] = _
  simp [Cells.readCopy, Cells.read, Cells.lookup, Value.copyable, Datum.copyable]

def registeredCellAllocation : Target.Multi.Runtime signature algebra [] (.cell (.leaf .integer)) :=
  ⟨⟨frozenControl.store, .code (.cellNew .ret) .nil
      (.cons (.datum (.leaf 42)) (.cons (.datum (.region ⟨0⟩)) .nil)) .done⟩,
    frozenControl.arena, [⟨0⟩], Defunctionalization.templateRegistry sourceRegistry⟩

def registeredCellAllocated : Target.Multi.Runtime signature algebra [] (.cell (.leaf .integer)) :=
  ⟨⟨frozenControl.store, .returned (.cell ⟨8⟩ ⟨0⟩) .done⟩,
    { frozenControl.arena with cells := ⟨⟨8⟩, ⟨0⟩, .leaf .integer, .datum (.leaf 42)⟩ :: currentOuterCell },
    [⟨0⟩], Defunctionalization.templateRegistry sourceRegistry⟩

/-- Cell 7 is retained only in the immutable template. Ordinary allocation
reserves that support and writes cell 8 into the current arena, keeping cell 2. -/
theorem ordinary_allocation_reserves_registry_cells_and_updates_current_storage :
    Target.Multi.Steps (.nil : Target.Definitions signature algebra []) registeredCellAllocation 2 registeredCellAllocated ∧
    registeredCellAllocated.arena.cells.identities = [⟨8⟩, ⟨2⟩] ∧
    registeredCellAllocated.registry = registeredCellAllocation.registry := by
  refine ⟨?_, rfl, rfl⟩
  refine .cons (.core (.cell (Target.CellStep.allocate (reserved := [])
    (region := ⟨0⟩) (by decide) (.unowned rfl)))) ?_
  exact .cons (.core (.cell (.ordinary .returned))) .refl

/-- A real target heap can have a silent return frame before its saved body.
It remains related to the source callback and its retained authored metadata. -/
def noncanonicalFreezeStore : Target.ControlHeap signature algebra [] :=
  { freezeStore with controls :=
    [⟨⟨10⟩, ⟨100⟩, .linear, ⟨templateShape,
      ⟨⟨9⟩, .push (.returnTo .ret .nil .nil) templateFuture.future⟩⟩⟩] }

theorem noncanonical_freeze_heap_retains_the_same_source_meaning :
    Defunctionalization.ControlHeapRelated (Source.Multi.sourceHeap sourceFreezeStore) noncanonicalFreezeStore ∧
    (noncanonicalFreezeStore.controls.map (fun record => record.future.snd.future.length)) = [2] ∧
    (freezeStore.controls.map (fun record => record.future.snd.future.length)) = [1] :=
  ⟨⟨rfl, .cons ⟨rfl, rfl, rfl, .same ⟨rfl, .passthrough .nil
    (Defunctionalization.capture_correspondence sourceTemplateFuture.capture)⟩⟩ .nil, .nil⟩, rfl, rfl⟩

theorem general_preservation_executes_clone_from_the_noncanonical_target_heap :
    ∃ targetFinal,
      Target.Multi.Observes (.nil : Target.Definitions signature algebra [])
        { targetCloneResumeStart with control := { targetCloneResumeStart.control with store := noncanonicalFreezeStore } }
        targetFinal (.returned (.datum (.leaf 0))) ∧
      targetFinal.registry = Defunctionalization.templateRegistry activatedRegistry ∧
      targetFinal.arena = Defunctionalization.templateArena cloneResumeEnd.arena := by
  have related := Defunctionalization.registered_initialization cloneResumeProgram cloneSourceBindings
    noncanonical_freeze_heap_retains_the_same_source_meaning.1 sourceFreezeArena [⟨3⟩, ⟨0⟩] []
  obtain ⟨targetFinal, targetObservation, observed, data, observation⟩ :=
    Defunctionalization.registered_observation_preserved (.nil : Source.Definitions signature algebra [])
      related cloned_registered_observations_keep_current_resources.1
  refine ⟨targetFinal, ?_, data.registry, data.arena⟩
  cases observation.observation
  exact observed

/-- The target trace alone supplies the execution premise. Reflection must
recover the source clone/resume observation and its retained resources. -/
theorem target_trace_reflects_registered_clone_and_resumption :
    ∃ sourceFinal sourceObservation,
      Source.Multi.Observes (.nil : Source.Definitions signature algebra []) cloneResumeStart sourceFinal sourceObservation ∧
      Defunctionalization.ObservationRelated sourceObservation (.returned (.datum (.leaf 0))) ∧
      Defunctionalization.templateRegistry sourceFinal.registry = targetCloneResumeEnd.registry ∧
      sourceFinal.control.store.fields = targetCloneResumeEnd.control.store.fields := by
  have related := Defunctionalization.registered_initialization cloneResumeProgram cloneSourceBindings
    (Defunctionalization.template_heap_correspondence sourceFreezeStore) sourceFreezeArena [⟨3⟩, ⟨0⟩] []
  obtain ⟨sourceFinal, sourceObservation, observed, data, matching⟩ :=
    Defunctionalization.registered_observation_reflected (.nil : Source.Definitions signature algebra []) related
      (⟨16, target_clone_and_resume_compose_to_the_same_finite_observation, .returned⟩ :
        Target.Multi.Observes .nil targetCloneResumeStart targetCloneResumeEnd (.returned (.datum (.leaf 0))))
  exact ⟨sourceFinal, sourceObservation, observed, matching.observation, data.registry.symm, data.store.fields⟩

end BoundaryV2.Generalized.Examples
