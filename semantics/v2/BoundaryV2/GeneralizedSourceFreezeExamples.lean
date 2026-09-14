import BoundaryV2.GeneralizedSourceFreeze
import BoundaryV2.GeneralizedFreezeExecution
import BoundaryV2.GeneralizedFreezeExamples

namespace BoundaryV2.Generalized.Examples

def sourceTemplateClosure : Source.RuntimeValue signature algebra [] TemplateClosure :=
  .closure (.returnValue (.datum (.capability ⟨9⟩)))
    (.cons (.cell (type := .leaf Data.integer) ⟨7⟩ ⟨3⟩)
      (.cons (.cell (type := .leaf Data.integer) ⟨7⟩ ⟨3⟩) .nil)) none

def sourceTemplateBindings : Source.RuntimeEnvironment signature algebra [] TemplateBindings :=
  .cons (.cell ⟨7⟩ ⟨3⟩) (.cons (.cell ⟨2⟩ ⟨0⟩)
    (.cons sourceTemplateClosure (.cons (.continuation ⟨6⟩ none) .nil)))

def sourceTemplateFuture : Source.Multi.Future signature algebra [] templateShape :=
  ⟨⟨9⟩, .bind (.cellRead (.reference (.there .here))) sourceTemplateBindings .done⟩

def sourceLocalCell : Cells signature algebra (Source.Computation signature algebra []) :=
  [⟨⟨7⟩, ⟨3⟩, .leaf .integer, .datum (.leaf 0)⟩]

def sourceCurrentOuterCell : Cells signature algebra (Source.Computation signature algebra []) :=
  [⟨⟨2⟩, ⟨0⟩, .leaf .integer, .datum (.leaf 99)⟩]

def sourceFreezeArena : Source.Multi.Arena signature algebra [] :=
  ⟨sourceLocalCell ++ sourceCurrentOuterCell, [Source.Multi.Record.bare ⟨6⟩ templateShape sourceTemplateFuture], []⟩

def sourceFreezeStore : Source.Multi.DescribedHeap signature algebra [] :=
  ⟨freezeStore.fields, [⟨⟨10⟩, ⟨100⟩, .linear, ⟨templateShape, sourceTemplateFuture⟩⟩], []⟩

def sourceFrozenStore : Source.Multi.DescribedHeap signature algebra [] := ⟨frozenStore.fields, [], []⟩

def sourceTemplateImage : Source.Multi.Image signature algebra [] templateShape :=
  Source.Multi.partitionImage freezePartition sourceTemplateFuture sourceFreezeArena

def sourceBranchingTemplate : Source.Multi.Template signature algebra [] templateShape :=
  ⟨sourceTemplateImage, by decide⟩

def sourceFrozenControl : Source.Multi.Frozen signature algebra [] templateShape :=
  ⟨freezeView.identity, sourceBranchingTemplate, sourceFrozenStore, ⟨sourceCurrentOuterCell, [], []⟩⟩

theorem source_freeze_uses_the_existing_branching_fixture :
    Defunctionalization.templateFuture sourceTemplateFuture = templateFuture ∧
    Defunctionalization.templateHeap sourceFreezeStore = freezeStore ∧
    Defunctionalization.templateArena sourceFreezeArena = freezeArena ∧
    Defunctionalization.frozen sourceFrozenControl = frozenControl := ⟨rfl, rfl, rfl, rfl⟩

theorem authored_source_freezes_its_registered_callback_and_current_cells :
    Source.Multi.freezeOwned templateShape freezeView sourceFreezeStore sourceFreezeArena freezePartition =
      some sourceFrozenControl := by
  have acquired : UseScope.acquireAt templateShape freezeView sourceFreezeStore =
      some ⟨sourceFrozenStore, sourceTemplateFuture⟩ := UseScope.acquire_at_recovers_typed_future rfl
  simp only [Source.Multi.freezeOwned,
    show UseScope.takeCapture freezeView.identity sourceFreezeStore.fields.retained = some (freezeCapture, []) from rfl,
    Option.bind_some, show UseScope.captureCanFreeze freezeCapture = true from rfl, ↓reduceIte, acquired]
  rfl

theorem source_freeze_consumes_the_real_source_heap_grant :
    UseScope.acquireAt templateShape freezeView (Source.Multi.sourceHeap sourceFreezeStore) =
      some ⟨Source.Multi.sourceHeap sourceFrozenStore, sourceTemplateFuture.payload⟩ ∧
    UseScope.ControlStore.Valid (Source.Multi.sourceHeap sourceFrozenStore) ∧
      freezeView.authority ∉ UseScope.inventory (Source.Multi.sourceHeap sourceFrozenStore).fields ∧
      UseScope.acquireAt templateShape freezeView (Source.Multi.sourceHeap sourceFrozenStore) = none := by
  refine ⟨Source.Multi.frozen_source_is_the_actual_acquisition
    authored_source_freezes_its_registered_callback_and_current_cells, ?_⟩
  apply Source.Multi.freeze_consumes_actual_source_ownership _ authored_source_freezes_its_registered_callback_and_current_cells
  exact freeze_store_has_unique_physical_owners

theorem general_translation_law_delivers_the_same_target_freeze :
    Target.Multi.freezeOwned templateShape freezeView freezeStore freezeArena freezePartition = some frozenControl := by
  change Target.Multi.freezeOwned templateShape freezeView
    (Defunctionalization.templateHeap sourceFreezeStore) (Defunctionalization.templateArena sourceFreezeArena) freezePartition = _
  rw [Defunctionalization.freeze_owned_corresponds templateShape freezeView sourceFreezeStore sourceFreezeArena freezePartition,
    authored_source_freezes_its_registered_callback_and_current_cells]
  rfl

theorem authored_clone_returns_the_source_template_binding :
    Source.Multi.Step (.nil : Source.Definitions signature algebra [])
      (⟨⟨Source.Multi.sourceHeap sourceFreezeStore,
        .evaluate (.clone (.reference .here)) cloneSourceBindings⟩, sourceFreezeArena, [⟨3⟩, ⟨0⟩], []⟩ :
        Source.Multi.Runtime signature algebra [] FrozenReference)
      ⟨⟨Source.Multi.sourceHeap sourceFrozenControl.store, .returned sourceFrozenControl.value⟩,
        sourceFrozenControl.arena, [⟨0⟩], [⟨freezeView.identity, ⟨templateShape, sourceBranchingTemplate⟩⟩]⟩ := by
  refine Source.Multi.Step.clone (use := .linear) (partition := freezePartition) (outside := .done)
    (expression := .reference .here) (bindings := cloneSourceBindings)
    (store := sourceFreezeStore) (evaluated := sourceFreezeStore) (frozen := sourceFrozenControl) (view := freezeView) ?_ ?_ .reference ?_
  · rfl
  · rfl
  unfold Source.Multi.freezeInto
  rw [authored_source_freezes_its_registered_callback_and_current_cells]
  rfl

theorem frozen_reference_reenters_the_caller_with_matching_source_meaning :
    Target.Multi.Steps (.nil : Target.Definitions signature algebra [])
      (⟨⟨frozenControl.store, .code .ret freezeBindings (.cons frozenControl.value .nil) .done⟩,
        frozenControl.arena, [⟨0⟩], [⟨freezeView.identity, ⟨templateShape, branchingTemplate⟩⟩]⟩ :
        Target.Multi.Runtime signature algebra [] FrozenReference) 1
      ⟨⟨frozenControl.store, .returned frozenControl.value .done⟩, frozenControl.arena, [⟨0⟩],
        [⟨freezeView.identity, ⟨templateShape, branchingTemplate⟩⟩]⟩ ∧
    Defunctionalization.ProgramRelated (.returned sourceFrozenControl.value) .done (.returned frozenControl.value .done) :=
  ⟨.cons (.core (.cell (.ordinary .returned))) .refl, .returned sourceFrozenControl.value .done⟩

def sourceCleanupTemplate : Source.Multi.Image signature algebra [] templateShape :=
  { sourceTemplateImage with
    saved := ⟨⟨9⟩, .protection ⟨4⟩ (.returnValue (.datum .unit)) .nil sourceTemplateFuture.capture⟩ }

def sourceLiteralOwnerTemplate : Source.Multi.Image signature algebra [] templateShape :=
  { sourceTemplateImage with
    saved := ⟨⟨9⟩, .bind
      (.bind (.returnValue (.datum (.resource (name := ⟨0⟩) ⟨5⟩ ⟨6⟩ (.lexical ⟨0⟩ 0))))
        (.returnValue (.datum (.leaf (type := Data.integer) 0)))) .nil .done⟩ }

theorem source_admission_rejects_live_cleanup_and_owned_code_constants :
    Source.Multi.admit sourceCleanupTemplate = none ∧
    sourceLiteralOwnerTemplate.saved.capture.copyable = true ∧
    Source.Multi.admit sourceLiteralOwnerTemplate = none ∧
    Target.Multi.admit (Defunctionalization.templateImage sourceCleanupTemplate) = none ∧
    Target.Multi.admit (Defunctionalization.templateImage sourceLiteralOwnerTemplate) = none := by
  refine ⟨rfl, rfl, rfl, ?_, ?_⟩ <;> rw [Defunctionalization.template_admission_corresponds] <;> rfl

end BoundaryV2.Generalized.Examples
