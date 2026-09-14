import BoundaryV2.GeneralizedRegisteredExecution
import BoundaryV2.GeneralizedFreeze
import BoundaryV2.GeneralizedTemplateExamples

namespace BoundaryV2.Generalized.Examples
open Target.Multi

def freezeView : UseScope.ControlView := ⟨⟨10⟩, ⟨100⟩, .lexical ⟨0⟩ 0⟩
def freezeCapture : List UseScope.Field := [.borrowed ⟨0⟩]
def freezeStore : Target.ControlHeap signature algebra [] :=
  ⟨⟨[.owned ⟨100⟩ freezeView.owner, .owned ⟨900⟩ (.lexical ⟨0⟩ 1)], [.continuation ⟨10⟩ freezeCapture], []⟩,
    [⟨⟨10⟩, ⟨100⟩, .linear, ⟨templateShape, templateFuture⟩⟩], []⟩
def freezeArena : Arena signature algebra [] :=
  ⟨templateImage.cells ++ currentOuterCell, templateImage.dormant, []⟩
def freezePartition : Partition := ⟨[⟨9⟩], [⟨3⟩], [], [⟨6⟩]⟩
def frozenStore : Target.ControlHeap signature algebra [] :=
  ⟨⟨freezeCapture ++ [.owned ⟨900⟩ (.lexical ⟨0⟩ 1)], [], [⟨100⟩]⟩, [], []⟩
def frozenControl : Frozen signature algebra [] templateShape :=
  ⟨freezeView.identity, branchingTemplate, frozenStore, templateArena⟩

theorem owned_continuation_freezes_actual_future_and_local_cells :
    freezeOwned templateShape freezeView freezeStore freezeArena freezePartition = some frozenControl ∧
    frozenControl.template.image.saved = templateFuture ∧
    frozenControl.template.image.cells = templateImage.cells ∧
    frozenControl.arena.cells = currentOuterCell ∧ frozenControl.store.fields.spent = [⟨100⟩] := by
  have acquired : UseScope.acquireAt templateShape freezeView freezeStore = some ⟨frozenStore, templateFuture⟩ :=
    UseScope.acquire_at_recovers_typed_future rfl
  refine ⟨?_, rfl, rfl, rfl, rfl⟩
  simp only [freezeOwned, show UseScope.takeCapture freezeView.identity freezeStore.fields.retained =
    some (freezeCapture, []) from rfl, Option.bind_some,
    show captureCanFreeze freezeCapture = true from rfl, ↓reduceIte, acquired]
  exact rfl

theorem freeze_store_has_unique_physical_owners : UseScope.ControlStore.Valid freezeStore := by
  simp [UseScope.ControlStore.Valid, UseScope.Valid, UseScope.inventory, freezeStore, freezeView,
    freezeCapture, UseScope.tokens, UseScope.Field.tokens]

theorem freezing_consumes_the_original_without_losing_other_owners :
    UseScope.ControlStore.Valid frozenControl.store ∧
    freezeView.authority ∉ UseScope.inventory frozenControl.store.fields ∧
    UseScope.acquireAt templateShape freezeView frozenControl.store = none :=
  freeze_preserves_ownership_and_consumes_original freeze_store_has_unique_physical_owners
    owned_continuation_freezes_actual_future_and_local_cells.1

abbrev FrozenReference : TypeOf signature := .continuation .shallow .multi .choose .unit (.leaf .integer)
def cloneSourceBindings : Source.RuntimeEnvironment signature algebra []
    [.continuation .shallow .linear .choose .unit (.leaf .integer)] :=
  .cons (.continuation freezeView.identity (some (freezeView.authority, freezeView.owner))) .nil

def freezeBindings : Target.RuntimeEnvironment signature algebra []
    [.continuation .shallow .linear .choose .unit (.leaf .integer)] := Defunctionalization.environment cloneSourceBindings

theorem target_clone_instruction_returns_its_template_binding :
    Target.Multi.Step (.nil : Target.Definitions signature algebra [])
      (⟨⟨freezeStore, .code (.clone (use := Use.linear) .ret) freezeBindings
        (.cons (.continuation freezeView.identity (some (freezeView.authority, freezeView.owner))) .nil) .done⟩,
        freezeArena, [⟨3⟩, ⟨0⟩], []⟩ : Target.Multi.Runtime signature algebra [] FrozenReference)
      ⟨⟨frozenControl.store, .code .ret freezeBindings (.cons frozenControl.value .nil) .done⟩,
        frozenControl.arena, [⟨0⟩], [⟨freezeView.identity, ⟨templateShape, branchingTemplate⟩⟩]⟩ := by
  refine Target.Multi.Step.clone (use := .linear) (partition := freezePartition)
    (frozen := frozenControl) (view := freezeView) ?_ ?_
  · rfl
  unfold Target.Multi.freezeInto
  rw [owned_continuation_freezes_actual_future_and_local_cells.1]
  rfl

theorem authored_clone_reaches_the_freeze_operation :
    Target.Multi.Steps (.nil : Target.Definitions signature algebra [])
      (⟨⟨freezeStore, .code (Defunctionalization.computation (.clone (.reference .here)))
        (Defunctionalization.environment cloneSourceBindings) .nil .done⟩, freezeArena, [⟨3⟩, ⟨0⟩], []⟩ :
        Target.Multi.Runtime signature algebra [] FrozenReference) 1
      ⟨⟨freezeStore, .code (.clone (use := Use.linear) .ret) (Defunctionalization.environment cloneSourceBindings)
        (.cons (.continuation freezeView.identity (some (freezeView.authority, freezeView.owner))) .nil) .done⟩,
        freezeArena, [⟨3⟩, ⟨0⟩], []⟩ := .cons (.core (.cell (.ordinary (.operand .load)))) .refl

theorem reentrant_activation_of_the_frozen_control_uses_distinct_names :
    let first := instantiate frozenControl.template frozenControl.arena []
    let second := instantiate frozenControl.template first.arena []
    first.saved.attachment = ⟨19⟩ ∧ second.saved.attachment = ⟨29⟩ ∧
    first.arena.cells.identities = [⟨15⟩, ⟨2⟩] ∧ second.arena.cells.identities = [⟨23⟩, ⟨15⟩, ⟨2⟩] := by
  exact ⟨rfl, rfl, rfl, rfl⟩

def exclusiveFreezeStore : Target.ControlHeap signature algebra [] :=
  { freezeStore with fields := { freezeStore.fields with retained := [.continuation ⟨10⟩ [.owned ⟨300⟩ (.control 10 0)]] } }
def cleanupFreezeStore : Target.ControlHeap signature algebra [] :=
  { freezeStore with fields := { freezeStore.fields with retained := [.continuation ⟨10⟩ [.cleanup ⟨7⟩ []]] } }

theorem exclusive_capture_and_cleanup_obligations_reject_before_freezing :
    freezeOwned templateShape freezeView exclusiveFreezeStore freezeArena freezePartition = none ∧
    freezeOwned templateShape freezeView cleanupFreezeStore freezeArena freezePartition = none ∧
    UseScope.acquireAt templateShape freezeView cleanupFreezeStore ≠ none := by
  refine ⟨rfl, rfl, ?_⟩
  have acquired : UseScope.acquireAt templateShape freezeView cleanupFreezeStore =
      some ⟨⟨⟨[.cleanup ⟨7⟩ [], .owned ⟨900⟩ (.lexical ⟨0⟩ 1)], [], [⟨100⟩]⟩, [], []⟩, templateFuture⟩ :=
    UseScope.acquire_at_recovers_typed_future rfl
  rw [acquired]
  intro impossible
  cases impossible

theorem exclusive_local_cell_cannot_enter_a_frozen_template :
    freezeOwned templateShape freezeView freezeStore
      { freezeArena with cells := ⟨⟨7⟩, ⟨3⟩, .resource ⟨0⟩, exclusiveResource⟩ :: currentOuterCell } freezePartition = none := by
  have acquired : UseScope.acquireAt templateShape freezeView freezeStore = some ⟨frozenStore, templateFuture⟩ :=
    UseScope.acquire_at_recovers_typed_future rfl
  simp only [freezeOwned, show UseScope.takeCapture freezeView.identity freezeStore.fields.retained =
    some (freezeCapture, []) from rfl, Option.bind_some,
    show captureCanFreeze freezeCapture = true from rfl, ↓reduceIte, acquired]
  exact rfl

def unusedFreezeBindings : Source.RuntimeEnvironment signature algebra [] [.resource ⟨0⟩] :=
  .cons (.datum (.resource ⟨1⟩ ⟨6⟩ (.lexical ⟨0⟩ 2))) .nil

def unusedFreezeFuture : Target.Stack signature algebra [] .unit .unit :=
  .push (.returnTo .ret (Defunctionalization.environment unusedFreezeBindings) .nil) .done

theorem neutral_frame_views_are_removed_without_changing_the_source_context :
    unusedFreezeFuture.copyable = false ∧ unusedFreezeFuture.cloneView = .done ∧
    Defunctionalization.ContextRelated signature algebra [] .done unusedFreezeFuture.cloneView :=
  ⟨rfl, rfl, Defunctionalization.clone_view_preserves_context_relation (.passthrough unusedFreezeBindings .done)⟩

theorem neutral_frame_still_has_the_same_ordinary_return :
    Target.CallSteps (.nil : Target.Definitions signature algebra [])
      (.returned (.datum .unit) unusedFreezeFuture) 2 (.returned (.datum .unit) unusedFreezeFuture.cloneView) :=
  Defunctionalization.return_passthrough_takes_two_steps .nil _ _ .nil .done

theorem clone_view_never_erases_a_live_cleanup :
    ExitComposition.pendingProtections
      (Target.Stack.push (.returnTo .ret (Defunctionalization.environment unusedFreezeBindings) .nil)
        (.push (.protection ⟨7⟩ (.fault .overflow) .nil) (.done : Target.Stack signature algebra [] .unit .unit))).cloneView = [⟨7⟩] := rfl

abbrev neutralFreezeShape : ControlShape signature := ⟨.shallow, .choose, .unit, .unit⟩
def neutralFreezePayload : Target.ControlPayload signature algebra [] neutralFreezeShape := ⟨⟨8⟩, unusedFreezeFuture⟩
def neutralFreezeStore : Target.ControlHeap signature algebra [] :=
  ⟨⟨[.owned ⟨100⟩ freezeView.owner, .owned ⟨6⟩ (.lexical ⟨0⟩ 2)], [.continuation ⟨10⟩ []], []⟩,
    [⟨⟨10⟩, ⟨100⟩, .linear, ⟨neutralFreezeShape, neutralFreezePayload⟩⟩], []⟩
def neutralFrozenStore : Target.ControlHeap signature algebra [] :=
  ⟨⟨[.owned ⟨6⟩ (.lexical ⟨0⟩ 2)], [], [⟨100⟩]⟩, [], []⟩
def neutralFrozenTemplate : Template signature algebra [] neutralFreezeShape :=
  ⟨⟨⟨⟨8⟩, .done⟩, [], [], [⟨8⟩], [], []⟩, by decide⟩

theorem neutral_frame_metadata_does_not_forbid_a_valid_freeze :
    freezeOwned neutralFreezeShape freezeView neutralFreezeStore ⟨[], [], []⟩ ⟨[⟨8⟩], [], [], []⟩ =
      some ⟨freezeView.identity, neutralFrozenTemplate, neutralFrozenStore, ⟨[], [], []⟩⟩ := by
  have acquired : UseScope.acquireAt neutralFreezeShape freezeView neutralFreezeStore =
      some ⟨neutralFrozenStore, neutralFreezePayload⟩ := UseScope.acquire_at_recovers_typed_future rfl
  simp only [freezeOwned, show UseScope.takeCapture freezeView.identity neutralFreezeStore.fields.retained =
    some ([], []) from rfl, Option.bind_some, show captureCanFreeze [] = true from rfl, ↓reduceIte, acquired]
  exact rfl

end BoundaryV2.Generalized.Examples
