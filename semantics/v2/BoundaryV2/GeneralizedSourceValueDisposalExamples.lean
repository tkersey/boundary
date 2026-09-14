import BoundaryV2.GeneralizedSourceExitExamples

namespace BoundaryV2.Generalized.Examples.SourceValueDisposal

open Defunctionalization

abbrev Resource : TypeOf signature := .resource ⟨1⟩
abbrev Closure : TypeOf signature := .computation .linear [] .unit
def first : Source.RuntimeValue signature algebra [] Resource := .datum (.resource ⟨3⟩ ⟨300⟩ (.lexical ⟨0⟩ 1))
def second : Source.RuntimeValue signature algebra [] Resource := .datum (.resource ⟨4⟩ ⟨400⟩ (.lexical ⟨0⟩ 2))
def captures : Source.RuntimeEnvironment signature algebra [] [Resource] := .cons second .nil
def closure : Source.RuntimeValue signature algebra [] Closure := .closure (.fail Fault.overflow) captures (some (⟨200⟩, .lexical ⟨0⟩ 3))
def pair : Source.RuntimeValue signature algebra [] (.product Resource Closure) := .pair first closure
def package : Source.RuntimeValue signature algebra [] (.package (.product Resource Closure)) := .package ⟨500⟩ (.lexical ⟨0⟩ 0) pair
def other : UseScope.Field := .owned ⟨901⟩ (.lexical ⟨0⟩ 9)
def initialFields : UseScope.State := ⟨[package.owningField, other], [], []⟩
def packageFields : UseScope.State := ⟨[pair.owningField, other], [], [⟨500⟩]⟩
def firstFields : UseScope.State := ⟨[.owned ⟨200⟩ (.lexical ⟨0⟩ 3), .closure captures.owningFields, other], [], [⟨300⟩, ⟨500⟩]⟩
def closureFields : UseScope.State := ⟨captures.owningFields ++ [other], [], [⟨200⟩, ⟨300⟩, ⟨500⟩]⟩
def finalFields : UseScope.State := ⟨[other], [], [⟨400⟩, ⟨200⟩, ⟨300⟩, ⟨500⟩]⟩
def exit : ExitInfo Fault String := ⟨.failure Fault.overflow, [Fault.overflow], some "first"⟩
def runtime (fields : UseScope.State) : Source.ExitRuntime signature algebra [] :=
  ⟨⟨7⟩, .failed Fault.overflow, ⟨fields, [], []⟩, [], [], exit⟩
def targetRuntime : ExitComposition.Runtime signature algebra [] :=
  ⟨⟨7⟩, .finished (.failed Fault.overflow), ⟨initialFields, [], []⟩, [], [], exit⟩

theorem source_structured_disposal_uses_declared_fields_in_order :
    Source.ValueDisposalSteps (.nil : Source.Definitions signature algebra [])
      (Source.ValueDisposal.start (runtime initialFields) package) 5 (.ready (runtime finalFields) []) := by
  refine .cons (middle := .ready (runtime packageFields) [⟨_, pair⟩])
    (.package (.unpack [] [other] [] [])) ?_
  refine .cons (middle := .ready (runtime packageFields) [⟨_, first⟩, ⟨_, closure⟩]) .pair ?_
  refine .cons (middle := .ready (runtime firstFields) [⟨_, closure⟩]) (.resource rfl) ?_
  refine .cons (middle := .ready (runtime closureFields) [⟨_, second⟩])
    (Source.ValueDisposalStep.closure (signature := signature) (algebra := algebra) (parameters := [])
      (result := .unit) (rest := []) (captured := captures)
      (runtime := runtime firstFields) (body := (.fail Fault.overflow : Source.Computation signature algebra [] [Resource] .unit))
      (.ownedFlat .linear ⟨200⟩ (.lexical ⟨0⟩ 3) [] [other] [] [⟨300⟩, ⟨500⟩])) ?_
  exact .cons (middle := .ready (runtime finalFields) []) (.resource rfl) .refl

theorem source_structured_disposal_has_the_same_target_meaning :
    ∃ count after,
      ExitComposition.ValueDisposalSteps (.nil : Target.Definitions signature algebra [])
        (ExitComposition.ValueDisposal.start targetRuntime (value package)) count after ∧
      ValueDisposalRelated (.ready (runtime finalFields) []) after := by
  exact finite_value_disposal_preserved (.nil : Source.Definitions signature algebra [])
    source_structured_disposal_uses_declared_fields_in_order
    (.ready [⟨_, package⟩] ⟨rfl, rfl, ⟨rfl, .nil, .nil⟩, rfl, rfl, rfl⟩)

theorem source_structured_disposal_keeps_other_ownership_and_exit :
    (runtime finalFields).store.fields.spent.reverse = [⟨500⟩, ⟨300⟩, ⟨200⟩, ⟨400⟩] ∧
    UseScope.inventory (runtime finalFields).store.fields = [⟨901⟩] ∧ (runtime finalFields).exit = exit := ⟨rfl, rfl, rfl⟩

abbrev controlShape : ControlShape signature := ⟨.shallow, .choose, .unit, .unit⟩
abbrev controlType : TypeOf signature := .continuation .shallow .linear .choose .unit .unit
def view : UseScope.ControlView := ⟨⟨10⟩, ⟨100⟩, .lexical ⟨0⟩ 0⟩
def cleanup : Source.Computation signature algebra [] [.exit] .unit := .returnValue (.datum .unit)
def future : Source.ControlPayload signature algebra [] controlShape := ⟨⟨8⟩, .push (.protection ⟨7⟩ cleanup .nil) .done⟩
def targetFuture : Target.ControlPayload signature algebra [] controlShape :=
  ⟨⟨8⟩, .push (.protection ⟨7⟩ (computation cleanup) .nil) .done⟩
def control : Source.RuntimeValue signature algebra [] controlType := .continuation view.identity (some (view.authority, view.owner))
def controlFields : UseScope.State := ⟨[.owned ⟨100⟩ view.owner, other], [.continuation ⟨10⟩ [.cleanup ⟨7⟩ []]], []⟩
def afterFields : UseScope.State := ⟨[.cleanup ⟨7⟩ [], other], [], [⟨100⟩]⟩
def controlStore : Source.ControlHeap signature algebra [] :=
  ⟨controlFields, [⟨⟨10⟩, ⟨100⟩, .linear, ⟨controlShape, future⟩⟩], []⟩
def controlTargetStore : Target.ControlHeap signature algebra [] :=
  ⟨controlFields, [⟨⟨10⟩, ⟨100⟩, .linear, ⟨controlShape, targetFuture⟩⟩], []⟩
def afterStore : Source.ControlHeap signature algebra [] := ⟨afterFields, [], []⟩
def abandoned : ExitInfo Fault String := ⟨.abandoned, [], none⟩
def normal : ExitInfo Fault String := ⟨.normal, [], none⟩
def beforeControl : Source.ExitRuntime signature algebra [] := ⟨⟨0⟩, .abandoned, controlStore, [], [], abandoned⟩
def afterControl : Source.ExitRuntime signature algebra [] := ⟨⟨0⟩, .abandoned, afterStore, [], [], abandoned⟩
def finishedControl : Source.ExitRuntime signature algebra [] := ⟨⟨7⟩, .returned, afterStore, [], [], abandoned⟩
def executing : Source.CleanupProgress signature algebra [] .unit :=
  .running (.reenter ⟨⟨afterStore, .cleaning ⟨7⟩ none abandoned
    (.evaluate cleanup (.cons (.exit abandoned) .nil))⟩, [], []⟩ normal)
def returned : Source.CleanupProgress signature algebra [] .unit :=
  .running (.reenter ⟨⟨afterStore, .cleaning ⟨7⟩ none abandoned (.returned (.datum .unit))⟩, [], []⟩ normal)

theorem source_control_disposal_composes_with_cleanup :
    Source.ValueDisposalSteps (.nil : Source.Definitions signature algebra [])
      (Source.ValueDisposal.start beforeControl control) 6 (.ready finishedControl []) := by
  refine .cons (middle := .control (Source.ControlProgress.seeking afterControl future.future) [])
    (Source.ValueDisposalStep.enterControl (runtime := beforeControl) (acquired := ⟨afterStore, ⟨controlShape, future⟩⟩) rfl) ?_
  refine .cons (middle := .control (.frames ⟨0⟩ executing) []) (.control (.frames .beginUnwind)) ?_
  refine .cons (middle := .control (.frames ⟨0⟩ returned) [])
    (.control (.frames (.execute (.cell (.ordinary (.cleaningStep (.returnValue rfl)) rfl))))) ?_
  refine .cons (middle := .control (.frames ⟨0⟩ (.running (.unwind finishedControl (.done : Source.Context signature algebra [] .unit .unit)))) [])
    (.control (.frames (Source.CleanupStep.returned (signature := signature) (algebra := algebra)
      (outside := (.done : Source.Context signature algebra [] .unit .unit))
      (identity := ⟨7⟩) (store := afterStore) (original := none) (exit := abandoned)
      (outcome := .exiting abandoned) rfl))) ?_
  refine .cons (middle := .control (.complete (answer := .unit) finishedControl) []) (.control .unwindDone) ?_
  exact .cons .finishControl .refl

theorem source_control_disposal_preserves_the_target_execution :
    ∃ count after,
      ExitComposition.ValueDisposalSteps (.nil : Target.Definitions signature algebra [])
        (ExitComposition.ValueDisposal.start ⟨⟨0⟩, .finished .abandoned, controlTargetStore, [], [], abandoned⟩ (value control)) count after ∧
      ValueDisposalRelated (.ready finishedControl []) after := by
  have futureRelated : ResumptionRelated future targetFuture := ⟨rfl, .push (.protection ⟨7⟩ cleanup .nil) .done⟩
  have stores : ControlHeapRelated controlStore controlTargetStore :=
    ⟨rfl, .cons ⟨rfl, rfl, rfl, .same futureRelated⟩ .nil, .nil⟩
  exact finite_value_disposal_preserved (.nil : Source.Definitions signature algebra [])
    source_control_disposal_composes_with_cleanup
      (.ready [⟨_, control⟩] ⟨rfl, rfl, stores, rfl, rfl, rfl⟩)

end BoundaryV2.Generalized.Examples.SourceValueDisposal
