import BoundaryV2.GeneralizedControlExecution
import BoundaryV2.GeneralizedObservationExamples

namespace BoundaryV2.Generalized.Examples

local instance : DecidableEq signature.Data := inferInstanceAs (DecidableEq Data)
local instance : DecidableEq signature.Effect := inferInstanceAs (DecidableEq Effect)

def choiceShape : ControlShape signature := ⟨.shallow, .choose, .leaf .boolean, .leaf .boolean⟩
def textShape : ControlShape signature := ⟨.shallow, .text, .leaf .text, .leaf .text⟩

def successorView : UseScope.ControlView := ⟨⟨10⟩, ⟨100⟩, .lexical ⟨0⟩ 0⟩
def otherTypedView : UseScope.ControlView := ⟨⟨11⟩, ⟨101⟩, .lexical ⟨0⟩ 1⟩

def mixedControlFields : UseScope.State :=
  ⟨[.owned ⟨100⟩ (.lexical ⟨0⟩ 0), .owned ⟨101⟩ (.lexical ⟨0⟩ 1)],
    [.continuation ⟨10⟩ [], .continuation ⟨11⟩ []], []⟩

def mixedSourceControls : Source.ControlHeap signature algebra [] :=
  ⟨mixedControlFields,
    [⟨⟨10⟩, ⟨100⟩, .affine, ⟨choiceShape, ⟨⟨8⟩, .done⟩⟩⟩,
     ⟨⟨11⟩, ⟨101⟩, .linear, ⟨textShape, ⟨⟨4⟩, .done⟩⟩⟩], []⟩

/-- Both shapes occupy the same first-order registry and custody namespace. -/
def mixedTargetControls : Target.ControlHeap signature algebra [] :=
  ⟨mixedControlFields,
    [⟨⟨10⟩, ⟨100⟩, .affine, ⟨choiceShape, ⟨⟨8⟩, .done⟩⟩⟩,
     ⟨⟨11⟩, ⟨101⟩, .linear, ⟨textShape, ⟨⟨4⟩, .done⟩⟩⟩], []⟩

theorem mixed_controls_correspond : Defunctionalization.ControlHeapRelated mixedSourceControls mixedTargetControls := by
  exact ⟨rfl, .cons ⟨rfl, rfl, rfl, .same ⟨rfl, .done⟩⟩
    (.cons ⟨rfl, rfl, rfl, .same ⟨rfl, .done⟩⟩ .nil), .nil⟩

theorem mixed_control_heap_valid : UseScope.ControlStore.Valid mixedTargetControls := by
  simp [UseScope.ControlStore.Valid, UseScope.Valid, UseScope.inventory, UseScope.tokens,
    UseScope.Field.tokens, mixedTargetControls, mixedControlFields]

theorem matching_identity_with_wrong_type_rejects :
    UseScope.acquireAt textShape successorView mixedTargetControls = none := rfl

def afterMixedFields : UseScope.State :=
  ⟨[.owned ⟨101⟩ (.lexical ⟨0⟩ 1)], [.continuation ⟨11⟩ []], [⟨100⟩]⟩

def sourceAfterChoice : Source.ControlHeap signature algebra [] :=
  ⟨afterMixedFields, mixedSourceControls.controls.tail, []⟩

def targetAfterChoice : Target.ControlHeap signature algebra [] :=
  ⟨afterMixedFields, mixedTargetControls.controls.tail, []⟩

theorem source_choice_acquires : UseScope.acquireAt choiceShape successorView mixedSourceControls =
    some ⟨sourceAfterChoice, ⟨⟨8⟩, .done⟩⟩ :=
  UseScope.acquire_at_recovers_typed_future rfl

theorem target_choice_acquires : UseScope.acquireAt choiceShape successorView mixedTargetControls =
    some ⟨targetAfterChoice, ⟨⟨8⟩, .done⟩⟩ :=
  UseScope.acquire_at_recovers_typed_future rfl

def successorBindings : Source.RuntimeEnvironment signature algebra []
    [.continuation .shallow .affine .choose (.leaf .boolean) (.leaf .boolean)] :=
  .cons (.continuation successorView.identity (some (successorView.authority, successorView.owner))) .nil

def effectfulSuccessorReturn : Source.Computation signature algebra []
    [.leaf .boolean, .continuation .shallow .affine .choose (.leaf .boolean) (.leaf .boolean)] (.leaf .text) :=
  Source.Computation.perform (signature := signature) (algebra := algebra)
    Operation.text (.datum (.capability ⟨4⟩)) (.reference .here) .nil

def successorPostprocessing : Source.Computation signature algebra []
    [.leaf .text, .continuation .shallow .affine .choose (.leaf .boolean) (.leaf .boolean)] (.leaf .text) :=
  .yieldThen (.returnValue (.reference .here))

def successorSourceCaller : Source.Context signature algebra [] (.leaf .text) (.leaf .text) :=
  .push (.bind (fun value => .evaluate successorPostprocessing (.cons value successorBindings))) .done

def successorTargetCaller : Target.Stack signature algebra [] (.leaf .text) (.leaf .text) :=
  .push (.returnTo (.enter (Defunctionalization.computation successorPostprocessing))
    (Defunctionalization.environment successorBindings) .nil) .done

def compiledSuccessor : Source.Computation signature algebra []
    [.continuation .shallow .affine .choose (.leaf .boolean) (.leaf .boolean)] (.leaf .text) :=
  .resumeWith .choose (.reference .here) (.datum (.leaf true)) effectfulSuccessorReturn .nil

def successorSourceAfter := Source.resumeControlWith (signature := signature) (algebra := algebra) (effect := Effect.choose)
  successorView mixedSourceControls (.datum (.leaf (type := Data.boolean) true)) effectfulSuccessorReturn .nil successorBindings successorSourceCaller

theorem compiled_successor_executes_with_two_different_control_types :
    ∃ sourceAfter targetAfter count, successorSourceAfter = some sourceAfter ∧ 0 < count ∧
      Defunctionalization.ControlStateRelated sourceAfter targetAfter ∧
      Target.OwnedSteps .nil ⟨mixedTargetControls,
        .code (Defunctionalization.computation compiledSuccessor)
          (Defunctionalization.environment successorBindings) .nil successorTargetCaller⟩ count targetAfter := by
  have accepted : ∃ after, successorSourceAfter = some after := by
    unfold successorSourceAfter Source.resumeControlWith
    erw [source_choice_acquires]
    exact ⟨_, rfl⟩
  obtain ⟨sourceAfter, accepted⟩ := accepted
  obtain ⟨targetAfter, count, positive, matched, _, steps⟩ := Defunctionalization.compiled_owned_successor
    (signature := signature) (algebra := algebra) .nil .affine
    (.reference .here) (.datum (.leaf true)) effectfulSuccessorReturn .nil successorBindings successorView
    (.datum (.leaf true)) rfl rfl mixed_controls_correspond
    (.push (.bind successorPostprocessing successorBindings) .done) accepted
  exact ⟨sourceAfter, targetAfter, count, accepted, positive, matched, steps⟩

def successorTargetAfter := Target.resumeControlWith (signature := signature) (algebra := algebra) (effect := Effect.choose)
  successorView mixedTargetControls (.datum (.leaf (type := Data.boolean) true)) (Defunctionalization.computation effectfulSuccessorReturn)
  .nil (Defunctionalization.environment successorBindings)
  (.push (.returnTo .ret (Defunctionalization.environment successorBindings) .nil) successorTargetCaller)

theorem successor_preserves_the_other_control_and_consumes_only_its_own :
    (successorTargetAfter.map fun after =>
      (after.store.fields.spent, after.store.controls.map UseScope.ControlInfo.identity)) = some ([⟨100⟩], [⟨11⟩]) := by
  unfold successorTargetAfter Target.resumeControlWith
  erw [target_choice_acquires]
  rfl

theorem successor_normal_return_can_perform_an_effect :
    ∃ after count future, successorTargetAfter = some after ∧
      Target.CallSteps .nil after.configuration count (.requested Operation.text ⟨4⟩ (.datum (.leaf true)) .nil future) := by
  obtain ⟨count, _, steps⟩ := Defunctionalization.compiled_operation_opens_typed_future
    (signature := signature) (algebra := algebra) .nil Operation.text
    (.datum (.capability ⟨4⟩)) (.reference .here) .nil (.cons (.datum (.leaf true)) successorBindings)
    ⟨4⟩ (.datum (.leaf true)) .nil rfl rfl rfl
    (.push (.returnTo .ret (Defunctionalization.environment successorBindings) .nil) successorTargetCaller)
  refine ⟨⟨targetAfterChoice, .returned (.datum (.leaf true))
    (.push (.handler Effect.choose .deep ⟨8⟩ (Defunctionalization.computation effectfulSuccessorReturn)
      .nil (Defunctionalization.environment successorBindings))
      (.push (.returnTo .ret (Defunctionalization.environment successorBindings) .nil) successorTargetCaller))⟩,
    1 + count,
    .push (.returnTo .ret (Defunctionalization.environment (.cons (.datum (.leaf (type := Data.boolean) true)) successorBindings)) .nil)
      (.push (.returnTo .ret (Defunctionalization.environment successorBindings) .nil) successorTargetCaller), ?_, ?_⟩
  · unfold successorTargetAfter Target.resumeControlWith
    erw [target_choice_acquires]
    rfl
  · exact (Target.CallSteps.single .handlerReturned).trans steps

def successorRequestFuture : Target.Stack signature algebra [] (.leaf .text) (.leaf .text) :=
  .push (.returnTo .ret
    (Defunctionalization.environment (.cons (.datum (.leaf (type := Data.boolean) true)) successorBindings)) .nil)
    (.push (.returnTo .ret (Defunctionalization.environment successorBindings) .nil) successorTargetCaller)

theorem successor_open_futures_preserve_the_clause_caller :
    Defunctionalization.ObservationRelated
      (Source.Observation.requested (signature := signature) (algebra := algebra)
        Operation.text ⟨4⟩ (.datum (.leaf true)) .nil successorSourceCaller)
      (.requested Operation.text ⟨4⟩ (.datum (.leaf true)) .nil successorRequestFuture) :=
  .requested Operation.text ⟨4⟩ (.datum (.leaf true)) .nil
    (.passthrough (.cons (.datum (.leaf (type := Data.boolean) true)) successorBindings)
      (.passthrough successorBindings (.push (.bind successorPostprocessing successorBindings) .done)))

/-- Every text response reaches the caller's authored yield. The administrative
return frames drain in seven target steps and cannot absorb the caller's work. -/
theorem successor_caller_executes_after_every_text_response (text : String) :
    Source.Steps (signature := signature) (algebra := algebra) .nil
      (successorSourceCaller.plug (.returned (.datum (.leaf text)))) 2
      (.yielded (.evaluate (.returnValue (.reference .here)) (.cons (.datum (.leaf (type := Data.text) text)) successorBindings))) ∧
    Target.CallSteps (signature := signature) (algebra := algebra) .nil
      (.returned (.datum (.leaf (type := Data.text) text)) successorRequestFuture) 7
      (.yielded (.code (.load .here .ret)
        (Defunctionalization.environment (.cons (.datum (.leaf (type := Data.text) text)) successorBindings)) .nil .done)) := by
  exact ⟨.cons .bindValue (.cons .yield .refl),
    .cons .caller (.cons .returned (.cons .caller (.cons .returned
      (.cons .caller (.cons .enter (.cons .yield .refl))))))⟩

end BoundaryV2.Generalized.Examples
