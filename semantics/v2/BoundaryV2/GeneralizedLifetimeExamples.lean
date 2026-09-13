import BoundaryV2.GeneralizedLifetimeExit
import BoundaryV2.GeneralizedRegisteredLifetime
import BoundaryV2.GeneralizedScopeExamples
import BoundaryV2.GeneralizedExamples

namespace BoundaryV2.Generalized.Examples.Lifetime

def sourceStore : Source.ControlHeap signature algebra [] := ⟨ScopeExamples.retainedPackage.fields, [], []⟩
def targetStore : Target.ControlHeap signature algebra [] := ⟨ScopeExamples.retainedPackage.fields, [], []⟩

theorem retained_owned_work_survives_its_creators_checked_close :
    Source.closeLifetime ⟨1⟩ ScopeExamples.retained sourceStore []
      (.done : Source.Context signature algebra [] .unit .unit) (.datum .unit) [] =
      some (.node ⟨1⟩ [.node ⟨3⟩ []], ScopeExamples.afterCreatorClosed) ∧
    Scope.path ⟨2⟩ ScopeExamples.afterCreatorClosed = some [⟨0⟩, ⟨4⟩, ⟨5⟩, ⟨2⟩] := ⟨rfl, rfl⟩

theorem source_and_target_agree_on_checked_creator_close :
    Target.closeLifetime ⟨1⟩ ScopeExamples.retained targetStore []
      (.done : Target.Stack signature algebra [] .unit .unit) (.datum .unit) [] =
      Source.closeLifetime ⟨1⟩ ScopeExamples.retained sourceStore []
        (.done : Source.Context signature algebra [] .unit .unit) (.datum .unit) [] :=
  Defunctionalization.lifetime_closure_corresponds ⟨1⟩ ScopeExamples.retained ⟨rfl, .nil, .nil⟩ [] .done (.datum .unit) []

theorem surviving_dormant_field_borrow_prevents_close :
    UseScope.closeScoped ⟨1⟩ ScopeExamples.retained
      [.package [.closure [.borrowed ⟨3⟩]]] [] = none := rfl

theorem returned_borrows_keep_their_actual_lifetime_distinction :
    Source.closeLifetime ⟨1⟩ ScopeExamples.retained sourceStore []
      (.done : Source.Context signature algebra [] (.borrowed ⟨0⟩) (.borrowed ⟨0⟩)) (.datum (.borrowed ⟨8⟩ ⟨0⟩)) [] =
      some (.node ⟨1⟩ [.node ⟨3⟩ []], ScopeExamples.afterCreatorClosed) ∧
    Source.closeLifetime ⟨1⟩ ScopeExamples.retained sourceStore []
      (.done : Source.Context signature algebra [] (.borrowed ⟨0⟩) (.borrowed ⟨0⟩)) (.datum (.borrowed ⟨8⟩ ⟨3⟩)) [] = none :=
  ⟨rfl, rfl⟩

def borrowedBody : Source.Computation signature algebra [] [.unit] (.borrowed ⟨0⟩) :=
  .returnValue (.datum (.borrowed ⟨8⟩ ⟨3⟩))
def sourceOutside : Source.Context signature algebra [] .unit (.borrowed ⟨0⟩) :=
  .push (.bindAuthored borrowedBody .nil) .done
def targetOutside : Target.Stack signature algebra [] .unit (.borrowed ⟨0⟩) :=
  .push (.returnTo (.enter (Defunctionalization.computation borrowedBody)) .nil .nil) .done

theorem future_code_borrow_prevents_close_even_without_a_captured_borrow_field :
    UseScope.borrowedScopes (sourceStore.fields.active ++ sourceStore.fields.retained) = [⟨2⟩, ⟨0⟩] ∧
    Source.closeLifetime ⟨1⟩ ScopeExamples.retained sourceStore [] sourceOutside (.datum .unit) [] = none ∧
    Target.closeLifetime ⟨1⟩ ScopeExamples.retained targetStore [] targetOutside (.datum .unit) [] = none :=
  ⟨rfl, rfl, rfl⟩

def heldBorrow : Source.RuntimeValue signature algebra [] (.computation .reusable [] (.borrowed ⟨0⟩)) :=
  .closure (.returnValue (.datum (.borrowed ⟨8⟩ ⟨3⟩))) .nil none
def storedBorrow : Cells signature algebra (Source.Computation signature algebra []) :=
  [⟨⟨9⟩, ⟨20⟩, .computation .reusable [] (.borrowed ⟨0⟩), heldBorrow⟩]

theorem dormant_body_in_a_surviving_cell_prevents_close :
    Source.closeLifetime ⟨1⟩ ScopeExamples.retained sourceStore storedBorrow
      (.done : Source.Context signature algebra [] .unit .unit) (.datum .unit) [] = none := rfl

abbrev BorrowShape : ControlShape signature := ⟨.shallow, .choose, .unit, .borrowed ⟨0⟩⟩
def retainedTemplate : Source.Multi.Template signature algebra [] BorrowShape :=
  ⟨⟨⟨⟨9⟩, .bind borrowedBody .nil .done⟩, [], [], [⟨9⟩], [], []⟩, by decide⟩
def registeredRuntime : Source.Multi.Runtime signature algebra [] .unit :=
  ⟨⟨sourceStore, .returned (.datum .unit)⟩, ⟨[], [], []⟩, [], [⟨⟨10⟩, ⟨BorrowShape, retainedTemplate⟩⟩]⟩

theorem registry_keeps_dormant_template_borrows_in_the_close_check :
    registeredRuntime.closeLifetime ⟨1⟩ ScopeExamples.retained .done (.datum .unit) [] = none := rfl

def completed : ExitComposition.Runtime signature algebra [] :=
  ⟨⟨30⟩, .finished .returned, targetStore, [], [], ⟨.normal, [], none⟩⟩
def scope : ExitComposition.ScopeExit signature algebra [] .unit := ⟨completed, .returned (.datum .unit) .done⟩
def resolution : ExitComposition.Resolution signature algebra [] .unit :=
  .reenter ⟨⟨targetStore, .returned (.datum .unit) .done⟩, [], []⟩ ⟨.normal, [], none⟩
def closed : ExitComposition.LifetimeExit signature algebra [] .unit :=
  ⟨resolution, .node ⟨1⟩ [.node ⟨3⟩ []], ScopeExamples.afterCreatorClosed⟩

theorem completed_cleanup_closes_without_changing_its_actual_resolution :
    ExitComposition.finishLifetime ⟨1⟩ ScopeExamples.retained scope [] = some closed ∧
    closed.resolution = resolution ∧ UseScope.inventory targetStore.fields = [⟨7⟩] := ⟨rfl, rfl, rfl⟩

theorem pending_or_parked_cleanup_cannot_close :
    ExitComposition.finishLifetime ⟨1⟩ ScopeExamples.retained
      { scope with cleanup := { completed with phase := .pending ⟨[], .push .unit .ret, .nil⟩ } } [] = none ∧
    ExitComposition.finishLifetime ⟨1⟩ ScopeExamples.retained
      { scope with cleanup := { completed with phase := .running (.returned (.datum .unit) .done) (.captured ⟨17⟩) } } [] = none :=
  ⟨rfl, rfl⟩

theorem captured_external_borrow_blocks_even_a_completed_cleanup :
    ExitComposition.finishLifetime ⟨1⟩ ScopeExamples.retained scope [.name .scope ⟨3⟩] = none := rfl

theorem closing_a_failed_scope_retains_the_first_reason_and_failure_order :
    let failed := { completed with
      phase := .finished (.failed .overflow)
      exit := (⟨.failure .overflow, [.overflow, .overflow], some "first"⟩ : ExitInfo Fault String) }
    ExitComposition.finishLifetime ⟨1⟩ ScopeExamples.retained ⟨failed, .unwind (.done : Target.Stack signature algebra [] .unit .unit)⟩ [] =
      some ⟨.reenter ⟨⟨targetStore, .failed .overflow .done⟩, [], []⟩
        ⟨.failure .overflow, [.overflow, .overflow], some "first"⟩,
        .node ⟨1⟩ [.node ⟨3⟩ []], ScopeExamples.afterCreatorClosed⟩ := rfl

end BoundaryV2.Generalized.Examples.Lifetime
