import BoundaryV2.GeneralizedCleanupCompletionExamples

namespace BoundaryV2.Generalized.Examples.StructuredDisposal

open ExitComposition
abbrev leafAlgebra := Nested.leafAlgebra
abbrev ControlType := CleanupCompletion.controlType
abbrev ResourceType : TypeOf signature := .resource ⟨0⟩
abbrev ClosureType : TypeOf signature := .computation .linear [] .unit
def view := CleanupCompletion.view
def saved := CleanupCompletion.saved
def control : Target.RuntimeValue signature leafAlgebra [] ControlType := CleanupCompletion.ownedValue
def resource : Target.RuntimeValue signature leafAlgebra [] ResourceType := .datum (.resource ⟨3⟩ ⟨300⟩ (.lexical ⟨0⟩ 3))
def alias : Target.RuntimeValue signature leafAlgebra [] ControlType := .continuation ⟨10⟩ none
def captures : Target.RuntimeEnvironment signature leafAlgebra [] [ResourceType, ControlType] := .cons resource (.cons alias .nil)
def closure : Target.RuntimeValue signature leafAlgebra [] ClosureType :=
  .closure (.fault 999) captures (some (⟨200⟩, .lexical ⟨0⟩ 2))
def pair : Target.RuntimeValue signature leafAlgebra [] (.product ControlType ClosureType) := .pair control closure
def packaged : Target.RuntimeValue signature leafAlgebra [] (.package (.product ControlType ClosureType)) :=
  .package ⟨500⟩ (.lexical ⟨0⟩ 0) pair
def other : UseScope.Field := .owned ⟨900⟩ (.lexical ⟨0⟩ 9)
def retained : List UseScope.Field := [.continuation ⟨10⟩ []]
def controls : List (UseScope.ControlInfo (Sigma (Target.ControlPayload signature leafAlgebra []))) :=
  [⟨⟨10⟩, ⟨100⟩, .linear, ⟨CleanupCompletion.controlShape, saved⟩⟩]
def initialFields : UseScope.State := ⟨[packaged.owningField, other], retained, []⟩
def packageFields : UseScope.State := ⟨[pair.owningField, other], retained, [⟨500⟩]⟩
def controlFields : UseScope.State :=
  ⟨[.owned ⟨200⟩ (.lexical ⟨0⟩ 2), .closure captures.owningFields, other], [], [⟨100⟩, ⟨500⟩]⟩
def closureFields : UseScope.State := ⟨captures.owningFields ++ [other], [], [⟨200⟩, ⟨100⟩, ⟨500⟩]⟩
def finalFields : UseScope.State := ⟨[other], [], [⟨300⟩, ⟨200⟩, ⟨100⟩, ⟨500⟩]⟩
def exit : ExitInfo Nat String := ⟨.failure 20, [20], some "first"⟩
def initial : Runtime signature leafAlgebra [] :=
  ⟨⟨7⟩, .finished (.failed 20), ⟨initialFields, controls, []⟩, [], [], exit⟩
def opened : Runtime signature leafAlgebra [] := { initial with store := { initial.store with fields := packageFields } }
def afterControl : Runtime signature leafAlgebra [] :=
  ⟨⟨7⟩, .finished .abandoned, ⟨controlFields, [], []⟩, [], [], exit⟩
def afterClosure : Runtime signature leafAlgebra [] := { afterControl with store := { afterControl.store with fields := closureFields } }
def final : Runtime signature leafAlgebra [] := { afterControl with store := { afterControl.store with fields := finalFields } }
def controlDisposal : Target.Disposal signature leafAlgebra [] .unit :=
  ⟨.unit, .seeking afterControl saved.future, .done⟩
def completedControl : Target.Disposal signature leafAlgebra [] .unit := ⟨.unit, .complete afterControl, .done⟩

theorem package_opens_its_actual_contents : PackageHandoff pair ⟨500⟩ (.lexical ⟨0⟩ 0) initialFields packageFields :=
  .unpack [] [other] retained []

theorem releasing_a_control_leaves_a_flat_closure_boundary :
    UseScope.disposeOwned view opened.store = some ⟨afterControl.store, ⟨CleanupCompletion.controlShape, saved⟩⟩ := rfl

theorem closure_opening_consumes_its_grant_before_exposing_captures :
    ComputationHandoff captures .linear (some (⟨200⟩, .lexical ⟨0⟩ 2)) controlFields closureFields :=
  .ownedFlat .linear ⟨200⟩ (.lexical ⟨0⟩ 2) [] [other] [] [⟨100⟩, ⟨500⟩]

theorem structured_disposal_preserves_order_and_consumes_each_owner :
    ValueDisposalSteps (.nil : Target.Definitions signature leafAlgebra [])
      (ValueDisposal.start initial packaged) 8 (.ready final []) := by
  refine .cons (middle := .ready opened [⟨_, pair⟩]) (.package package_opens_its_actual_contents) ?_
  refine .cons (middle := .ready opened [⟨_, control⟩, ⟨_, closure⟩]) .pair ?_
  refine .cons (middle := .control controlDisposal [⟨_, closure⟩])
    (ValueDisposalStep.enterControl (signature := signature) (algebra := leafAlgebra)
      (runtime := opened) releasing_a_control_leaves_a_flat_closure_boundary) ?_
  refine .cons (middle := .control completedControl [⟨_, closure⟩]) (.control (.unwind (.complete rfl))) ?_
  refine .cons (middle := .ready afterControl [⟨_, closure⟩]) .finishControl ?_
  refine .cons (middle := .ready afterClosure [⟨_, resource⟩, ⟨_, alias⟩])
    (ValueDisposalStep.closure (signature := signature) (algebra := leafAlgebra) (body := (.fault 999)) closure_opening_consumes_its_grant_before_exposing_captures) ?_
  refine .cons (middle := .ready final [⟨_, alias⟩]) (.resource rfl) ?_
  exact .cons (.stale rfl) .refl

theorem disposed_grants_and_exit_remain_distinct_from_the_other_owner :
    final.store.fields.spent.reverse = [⟨500⟩, ⟨100⟩, ⟨200⟩, ⟨300⟩] ∧
    UseScope.inventory final.store.fields = [⟨900⟩] ∧ final.exit = exit := ⟨rfl, rfl, rfl⟩

theorem a_spent_view_does_not_start_control_disposal_again :
    ValueDisposalStep (.nil : Target.Definitions signature leafAlgebra [])
      (.ready afterControl [⟨_, control⟩]) (.ready afterControl []) := .stale rfl

theorem pending_closure_cannot_finish_while_control_disposal_is_active :
    ValueDisposal.finished (.control controlDisposal [⟨_, closure⟩]) = none := rfl

theorem opening_both_container_forms_preserves_validity :
    UseScope.ControlStore.Valid initial.store ∧ UseScope.ControlStore.Valid final.store := by
  constructor <;> simp [UseScope.ControlStore.Valid, UseScope.Valid, UseScope.inventory,
    initial, final, afterControl, initialFields, finalFields, packaged, pair, closure, control, resource, alias,
    captures, other, retained, controls, CleanupCompletion.ownedValue, CleanupCompletion.view,
    Value.owningField, Datum.owningField, Environment.owningFields, authorityFields, UseScope.tokens, UseScope.Field.tokens]

def outside : Target.Stack signature leafAlgebra [] (.package (.product ControlType ClosureType)) .unit :=
  .push (.returnTo (.push .unit .ret) .nil .nil) .done
def work : CleanupDisposal signature leafAlgebra [] .unit := ⟨_, packaged, initial, outside⟩

theorem structured_cleanup_disposal_rejoins_with_the_current_exit :
    ∃ count, CleanupFrameSteps (.nil : Target.Definitions signature leafAlgebra []) (.disposing work) count
      (.running (.reenter ⟨⟨final.store, .failed 20 outside⟩, [], []⟩ exit)) := by
  have inside := CleanupFrameSteps.of_values (signature := signature) (algebra := leafAlgebra) ⟨7⟩ (.failed 20) outside
    structured_disposal_preserves_order_and_consumes_each_owner
  have finish : CleanupFrameSteps (.nil : Target.Definitions signature leafAlgebra [])
      (.values ⟨7⟩ (.failed 20) outside (.ready final [])) 1
      (.running (.reenter ⟨⟨final.store, .failed 20 outside⟩, [], []⟩ exit)) :=
    .cons (.finishValues rfl) .refl
  exact ⟨10, .cons (.enterValues rfl) (inside.trans finish)⟩

end BoundaryV2.Generalized.Examples.StructuredDisposal
