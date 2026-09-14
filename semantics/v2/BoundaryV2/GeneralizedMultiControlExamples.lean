import BoundaryV2.GeneralizedMultiControlEntry
import BoundaryV2.GeneralizedRegistryExamples

namespace BoundaryV2.Generalized.Examples.MultiControl

def injectionOwner : Owner := .lexical ⟨0⟩ 3
def injectedCapture : Source.RuntimeEnvironment signature algebra [] [.resource ⟨0⟩] :=
  .cons (.datum (.resource ⟨1⟩ ⟨6⟩ (.lexical ⟨0⟩ 2))) .nil
def injectedYieldBody : Source.Computation signature algebra [] [.resource ⟨0⟩] .unit :=
  .yieldThen (.returnValue (.datum .unit))
abbrev OwnedUnitBody : TypeOf signature := .computation .linear [] .unit
def injectedOwnedValue : Source.RuntimeValue signature algebra [] OwnedUnitBody :=
  .closure injectedYieldBody injectedCapture (some (⟨700⟩, injectionOwner))
def injectionBindings : Source.RuntimeEnvironment signature algebra [] [FrozenReference, OwnedUnitBody] :=
  .cons sourceFrozenControl.value (.cons injectedOwnedValue .nil)
def injectionProgram : Source.Computation signature algebra [] [FrozenReference, OwnedUnitBody] (.leaf .integer) :=
  .inject (.reference .here) (.reference (.there .here))

def injectionFields : UseScope.State :=
  ⟨.group [.owned ⟨700⟩ injectionOwner, .closure injectedCapture.owningFields] :: sourceRegistered.control.store.fields.active,
    [], [⟨100⟩]⟩
def injectedFields : UseScope.State :=
  ⟨injectedCapture.owningFields ++ sourceRegistered.control.store.fields.active, [], [⟨700⟩, ⟨100⟩]⟩
def injectionStore : Source.ControlHeap signature algebra [] :=
  { sourceRegistered.control.store with fields := injectionFields }
def injectedStore : Source.ControlHeap signature algebra [] :=
  { injectionStore with fields := injectedFields }

def sourceInjection : Source.Multi.Runtime signature algebra [] (.leaf .integer) :=
  ⟨⟨injectionStore, .evaluate injectionProgram injectionBindings⟩, sourceRegistered.arena, [⟨0⟩], sourceRegistry⟩
def sourceInjectionReady : Source.Multi.Runtime signature algebra [] (.leaf .integer) :=
  { sourceInjection with control := { sourceInjection.control with store := injectedStore } }
def injectionExternal : List Reference := Source.Multi.callSupport .nil injectionBindings
  (.done : Source.Context signature algebra [] (.leaf .integer) (.leaf .integer)) injectedStore
def injectedActivation := Source.Multi.instantiate sourceBranchingTemplate sourceInjectionReady.arena
  (sourceInjectionReady.support (injectedYieldBody.references ++ Source.environmentReferences injectedCapture ++ injectionExternal))
def sourceInjectionAfter : Source.Multi.Runtime signature algebra [] (.leaf .integer) :=
  sourceInjectionReady.afterActivation ⟨injectedActivation, [⟨7⟩, ⟨0⟩], activatedRegistry⟩
    (Source.reenter injectedActivation.saved.payload (.evaluate injectedYieldBody injectedCapture))

theorem injected_owned_body_handoff : ComputationHandoff injectedCapture .linear
    (some (⟨700⟩, injectionOwner)) injectionFields injectedFields :=
  .owned .linear ⟨700⟩ injectionOwner [] sourceRegistered.control.store.fields.active [] [⟨100⟩]

theorem registered_injection_enters_the_body_after_handoff :
    sourceInjectionReady.inject templateShape freezeView.identity injectedYieldBody injectedCapture .done injectionExternal =
      some sourceInjectionAfter := by
  unfold Source.Multi.Runtime.inject Source.Multi.Runtime.activate
  change ((TemplateRegistry.lookup templateShape freezeView.identity sourceRegistry).bind _).map _ = _
  rw [registered_template_lookup]
  rfl

theorem owned_injection_consumes_only_its_grant_and_exposes_its_actual_capture :
    injectedFields.spent = [⟨700⟩, ⟨100⟩] ∧ UseScope.inventory injectedFields = [⟨6⟩, ⟨900⟩] ∧
    ¬ ComputationHandoff injectedCapture .linear (some (⟨700⟩, injectionOwner)) injectedFields later := by
  refine ⟨rfl, rfl, ?_⟩
  apply injected_owned_body_handoff.owned_entry_cannot_repeat
  simp [UseScope.Valid, UseScope.inventory, UseScope.tokens, UseScope.Field.tokens, injectionFields,
    injectedCapture, Environment.owningFields, Value.owningField, Datum.owningField, sourceRegistered,
    Source.Multi.sourceHeap, UseScope.ControlStore.mapFuture, sourceFrozenControl, sourceFrozenStore,
    frozenStore, freezeCapture]

theorem injected_body_yields_inside_the_retained_future :
    Source.Step (.nil : Source.Definitions signature algebra []) sourceInjectionAfter.control.computation
      (injectedActivation.saved.payload.future.plug (.yielded (.evaluate (.returnValue (.datum .unit)) injectedCapture))) :=
  Source.Step.in_context .yield injectedActivation.saved.payload.future

theorem authored_owned_injection_has_a_registered_entry :
    Source.Multi.ResumeEntry (.nil : Source.Definitions signature algebra []) sourceInjection sourceInjectionAfter :=
  .injection (.cons .reference (.cons .reference .nil)) injected_owned_body_handoff
    registered_injection_enters_the_body_after_handoff

theorem owned_injection_compiles_to_a_positive_target_entry :
    ∃ targetAfter count, 0 < count ∧ Defunctionalization.MultiRuntimeRelated sourceInjectionAfter targetAfter ∧
      Target.Multi.Steps (.nil : Target.Definitions signature algebra [])
        ⟨⟨⟨injectionFields, [], []⟩, .code (Defunctionalization.computation injectionProgram)
          (Defunctionalization.environment injectionBindings) .nil .done⟩,
          Defunctionalization.templateArena sourceInjection.arena, [⟨0⟩], Defunctionalization.templateRegistry sourceRegistry⟩ count targetAfter :=
  (Defunctionalization.compiled_multi_injection .nil (.reference .here) (.reference (.there .here))
    injectionBindings injectedYieldBody injectedCapture (some (⟨700⟩, injectionOwner)) freezeView.identity
    sourceInjection.arena [⟨0⟩] sourceRegistry (.cons .reference (.cons .reference .nil))
    ⟨rfl, .nil, .nil⟩ injected_owned_body_handoff .done registered_injection_enters_the_body_after_handoff).2

def successorReturn : Source.Computation signature algebra [] [.leaf .integer, FrozenReference] .unit :=
  .yieldThen (.returnValue (.datum .unit))
def successorProgram : Source.Computation signature algebra [] [FrozenReference] .unit :=
  .resumeWith .choose (.reference .here) (.datum .unit) successorReturn .nil
def sourceSuccessor : Source.Multi.Runtime signature algebra [] .unit :=
  ⟨⟨sourceRegistered.control.store, .evaluate successorProgram registeredBindings⟩, sourceRegistered.arena, [⟨0⟩], sourceRegistry⟩
def successorExternal : List Reference := Source.Multi.callSupport .nil registeredBindings
  (.done : Source.Context signature algebra [] .unit .unit) sourceSuccessor.control.store
def successorActivation := Source.Multi.instantiate sourceBranchingTemplate sourceSuccessor.arena
  (sourceSuccessor.support (Source.valueReferences (.datum .unit : Source.RuntimeValue signature algebra [] .unit) ++
    successorReturn.references ++ [] ++ Source.environmentReferences registeredBindings ++ successorExternal))
def sourceSuccessorAfter : Source.Multi.Runtime signature algebra [] .unit :=
  sourceSuccessor.afterActivation ⟨successorActivation, [⟨7⟩, ⟨0⟩], activatedRegistry⟩
    (Source.reenterWith successorActivation.saved.payload (.datum .unit) successorReturn .nil registeredBindings .done)

theorem registered_successor_retains_its_effectful_changed_answer_clause :
    sourceSuccessor.successor (effect := Effect.choose) freezeView.identity (.datum .unit) successorReturn .nil registeredBindings .done successorExternal =
      some sourceSuccessorAfter := by
  unfold Source.Multi.Runtime.successor Source.Multi.Runtime.activate
  change ((TemplateRegistry.lookup templateShape freezeView.identity sourceRegistry).bind _).map _ = _
  rw [registered_template_lookup]
  rfl

theorem authored_successor_has_a_registered_entry :
    Source.Multi.ResumeEntry (.nil : Source.Definitions signature algebra []) sourceSuccessor sourceSuccessorAfter :=
  .successor (.cons .reference (.cons .datum .nil)) registered_successor_retains_its_effectful_changed_answer_clause

theorem effectful_changed_answer_successor_compiles_to_a_positive_target_entry :
    ∃ targetAfter count, 0 < count ∧ Defunctionalization.MultiRuntimeRelated sourceSuccessorAfter targetAfter ∧
      Target.Multi.Steps (.nil : Target.Definitions signature algebra [])
        ⟨⟨Defunctionalization.templateHeap sourceFrozenControl.store, .code (Defunctionalization.computation successorProgram)
          (Defunctionalization.environment registeredBindings) .nil .done⟩,
          Defunctionalization.templateArena sourceSuccessor.arena, [⟨0⟩], Defunctionalization.templateRegistry sourceRegistry⟩ count targetAfter :=
  (Defunctionalization.compiled_multi_successor .nil (.reference .here) (.datum .unit) successorReturn
    (.nil : Source.Clauses signature algebra [] .choose .deep [FrozenReference] (.leaf .integer) .unit)
    registeredBindings freezeView.identity (.datum .unit) sourceSuccessor.arena [⟨0⟩] sourceRegistry
    (.cons .reference (.cons .datum .nil)) (Defunctionalization.template_heap_correspondence sourceFrozenControl.store) .done
    registered_successor_retains_its_effectful_changed_answer_clause).2

end BoundaryV2.Generalized.Examples.MultiControl
