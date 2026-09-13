import BoundaryV2.GeneralizedInjectionExecution
import BoundaryV2.GeneralizedCellExecutionExamples
import BoundaryV2.GeneralizedProgramObservations

namespace BoundaryV2.Generalized.Examples

abbrev InjectionCaptures : List (TypeOf signature) := [.leaf .boolean, .capability .text, .resource ⟨0⟩]
abbrev InjectionControl : TypeOf signature := .continuation .shallow .linear .choose (.leaf .boolean) (.leaf .boolean)
abbrev InjectionBody : TypeOf signature := .computation .linear [] (.leaf .boolean)
abbrev injectionShape : ControlShape signature := ⟨.shallow, .choose, .leaf .boolean, .leaf .boolean⟩

def injectionOwner : Owner := .lexical ⟨0⟩ 0
def injectionView : UseScope.ControlView := ⟨⟨0⟩, ⟨1⟩, injectionOwner⟩

def injectionCaptures : Source.RuntimeEnvironment signature algebra [] InjectionCaptures :=
  .cons (.datum (.leaf true)) (.cons (.datum (.capability ⟨4⟩)) (.cons ownedCellSourceValue .nil))

def injectedBody : Source.Computation signature algebra [] InjectionCaptures (.leaf .boolean) :=
  .bind (.perform (signature := signature) (algebra := algebra) Operation.text (.reference (.there .here)) (.reference .here) .nil)
    (.returnValue (.reference (.there .here)))

def injectedClosure : Source.RuntimeValue signature algebra [] InjectionBody :=
  .closure injectedBody injectionCaptures (some (⟨8⟩, injectionOwner))

def injectionBindings : Source.RuntimeEnvironment signature algebra [] [InjectionControl, InjectionBody] :=
  .cons (.continuation injectionView.identity (some (injectionView.authority, injectionView.owner))) (.cons injectedClosure .nil)

def injectionTextClauses : Source.Clauses signature algebra [] .text .deep [] (.leaf .boolean) (.leaf .boolean) :=
  .cons Operation.text .linear (.resume (.reference .here) (.datum (.leaf "handled"))) .nil

def injectionSourceSaved : Source.Resumption signature algebra [] .shallow .choose (.leaf .boolean) (.leaf .boolean) :=
  ⟨⟨9⟩, .push (.handler .text .deep ⟨4⟩ (.returnValue (.reference .here)) injectionTextClauses .nil) .done⟩

def injectionTargetSaved : Target.Resumption signature algebra [] .shallow .choose (.leaf .boolean) (.leaf .boolean) :=
  ⟨⟨9⟩, .push (.handler .text .deep ⟨4⟩ (.load .here .ret) (Defunctionalization.clauses injectionTextClauses) .nil) .done⟩

def injectionSourceOutside : Source.Context signature algebra [] (.leaf .boolean) (.leaf .boolean) :=
  .push (.handler .text .deep ⟨5⟩ (.returnValue (.reference .here)) .nil .nil) .done

def injectionTargetOutside : Target.Stack signature algebra [] (.leaf .boolean) (.leaf .boolean) :=
  .push (.handler .text .deep ⟨5⟩ (.load .here .ret) .nil .nil) .done

def injectionSourceStore : Source.ControlHeap signature algebra [] :=
  ⟨⟨[.owned ⟨1⟩ injectionOwner, injectedClosure.owningField], [.continuation ⟨0⟩ []], []⟩,
    [⟨⟨0⟩, ⟨1⟩, .linear, ⟨injectionShape, injectionSourceSaved⟩⟩], []⟩

def injectionTargetStore : Target.ControlHeap signature algebra [] :=
  ⟨injectionSourceStore.fields, [⟨⟨0⟩, ⟨1⟩, .linear, ⟨injectionShape, injectionTargetSaved⟩⟩], []⟩

def injectionBodyFields : UseScope.State :=
  ⟨[.owned ⟨1⟩ injectionOwner] ++ injectionCaptures.owningFields, [.continuation ⟨0⟩ []], [⟨8⟩]⟩

def injectionSourceAfter : Source.ControlState signature algebra [] (.leaf .boolean) :=
  ⟨⟨⟨[.owned ⟨6⟩ injectionOwner], [], [⟨1⟩, ⟨8⟩]⟩, [], []⟩,
    injectionSourceOutside.plug (Source.reenter injectionSourceSaved (.evaluate injectedBody injectionCaptures))⟩

theorem injection_stores_are_related : Defunctionalization.ControlHeapRelated injectionSourceStore injectionTargetStore :=
  ⟨rfl, .cons ⟨rfl, rfl, rfl, .same ⟨rfl,
    .push (.handler (signature := signature) (algebra := algebra) .text .deep ⟨4⟩ (.returnValue (.reference .here)) injectionTextClauses .nil) .done⟩⟩ .nil, .nil⟩

theorem injection_outsides_are_related :
    Defunctionalization.ContextRelated signature algebra [] injectionSourceOutside injectionTargetOutside :=
  .push (.handler (signature := signature) (algebra := algebra) .text .deep ⟨5⟩ (.returnValue (.reference .here)) .nil .nil) .done

theorem injection_body_handoff : ComputationHandoff injectionCaptures .linear (some (⟨8⟩, injectionOwner))
    injectionSourceStore.fields injectionBodyFields :=
  ComputationHandoff.owned .linear ⟨8⟩ injectionOwner [.owned ⟨1⟩ injectionOwner] [] [.continuation ⟨0⟩ []] []

theorem injection_source_accepted :
    Source.injectControl injectionShape injectionView { injectionSourceStore with fields := injectionBodyFields }
      injectedBody injectionCaptures injectionSourceOutside = some injectionSourceAfter := by
  simp [Source.injectControl, UseScope.acquireAt, UseScope.acquire, injectionSourceStore, injectionBodyFields,
    injectionView, injectionOwner, UseScope.takeControl, UseScope.takeGrant, UseScope.takeCapture,
    UseScope.activeFields, UseScope.exposeField, injectionCaptures, Environment.owningFields,
    Value.owningField, Datum.owningField, ownedCellSourceValue, UseScope.unpack_control_exact, injectionSourceAfter]

theorem owned_body_and_resumption_are_consumed_with_cells_retained :
    ∃ targetAfter count, 0 < count ∧
      Defunctionalization.CellStateRelated ⟨injectionSourceAfter, [], [⟨0⟩]⟩ ⟨targetAfter, [], [⟨0⟩]⟩ ∧
      Target.ExecutionSteps (.nil : Target.Definitions signature algebra [])
        ⟨⟨injectionTargetStore, .code (Defunctionalization.computation
          (.inject (.reference .here) (.reference (.there .here))))
          (Defunctionalization.environment injectionBindings) .nil injectionTargetOutside⟩, [], [⟨0⟩]⟩
        count ⟨targetAfter, [], [⟨0⟩]⟩ := by
  obtain ⟨targetAfter, count, positive, related, _, steps⟩ := Defunctionalization.compiled_computation_injection
    (signature := signature) (algebra := algebra) .nil .linear (.reference .here) (.reference (.there .here)) injectionBindings
    injectedBody injectionCaptures (some (⟨8⟩, injectionOwner)) injectionView [] [⟨0⟩]
    (sourceEvaluated := injectionSourceStore) (.cons .reference (.cons .reference .nil))
    injection_stores_are_related injection_body_handoff injection_outsides_are_related injection_source_accepted
  exact ⟨targetAfter, count, positive, related, steps⟩

theorem injection_keeps_captured_resource_and_spends_both_grants :
    UseScope.inventory injectionSourceAfter.store.fields = [⟨6⟩] ∧
      injectionSourceAfter.store.fields.spent = [⟨1⟩, ⟨8⟩] := ⟨rfl, rfl⟩

theorem resumption_cannot_be_reused_after_injection :
    Source.injectControl injectionShape injectionView injectionSourceAfter.store
      injectedBody injectionCaptures injectionSourceOutside = none := rfl

def injectionCaller : Target.Stack signature algebra [] (.leaf .boolean) (.leaf .boolean) :=
  .push (.returnTo .ret (Defunctionalization.environment injectionBindings) .nil) injectionTargetOutside

def injectionTargetAfter : Target.ControlState signature algebra [] (.leaf .boolean) :=
  ⟨⟨injectionSourceAfter.store.fields, [], []⟩,
    .code (Defunctionalization.computation injectedBody) (Defunctionalization.environment injectionCaptures) .nil
      (injectionTargetSaved.future.append injectionCaller)⟩

theorem injection_target_accepted :
    Target.injectControl injectionShape injectionView { injectionTargetStore with fields := injectionBodyFields }
      ⟨InjectionCaptures, Defunctionalization.computation injectedBody, Defunctionalization.environment injectionCaptures⟩
      injectionCaller = some injectionTargetAfter := by
  simp [Target.injectControl, Target.inject, UseScope.acquireAt, UseScope.acquire, injectionTargetStore,
    injectionBodyFields, injectionView, injectionOwner, UseScope.takeControl, UseScope.takeGrant, UseScope.takeCapture,
    UseScope.activeFields, UseScope.exposeField, injectionCaptures, Environment.owningFields,
    Value.owningField, Datum.owningField, ownedCellSourceValue, UseScope.unpack_control_exact,
    injectionTargetAfter, injectionSourceAfter]

theorem actual_injection_enters_the_restored_future :
    Target.ExecutionSteps (.nil : Target.Definitions signature algebra [])
      ⟨⟨injectionTargetStore, .code (Defunctionalization.computation (.inject (.reference .here) (.reference (.there .here))))
        (Defunctionalization.environment injectionBindings) .nil injectionTargetOutside⟩, [], [⟨0⟩]⟩ 3
      ⟨injectionTargetAfter, [], [⟨0⟩]⟩ := by
  have handoff : ComputationHandoff (Defunctionalization.environment injectionCaptures) .linear
      (some (⟨8⟩, injectionOwner)) injectionTargetStore.fields injectionBodyFields :=
    injection_body_handoff.map (fun _ _ body => Defunctionalization.computation body)
  exact .cons (.cell (.ordinary (.operand .load))) (.cons (.cell (.ordinary (.operand .load)))
    (.cons (.control (.injection (use := .linear) (bodyUse := .linear) handoff injection_target_accepted)) .refl))

def injectionRequestPrefix : Target.Stack signature algebra [] (.leaf .text) (.leaf .boolean) :=
  .push (.returnTo .ret (Defunctionalization.environment injectionCaptures) .nil)
    (.push (.returnTo (.enter (.load (.there .here) .ret)) (Defunctionalization.environment injectionCaptures) .nil) .done)

def injectionRequestFuture : Target.Stack signature algebra [] (.leaf .text) (.leaf .boolean) :=
  injectionRequestPrefix.append (injectionTargetSaved.future.append injectionCaller)

theorem injected_code_executes_and_requests_in_its_use_site :
    ∃ count, Target.CallSteps (.nil : Target.Definitions signature algebra []) injectionTargetAfter.configuration count
      (.requested Operation.text ⟨4⟩ (.datum (.leaf true)) .nil injectionRequestFuture) := by
  obtain ⟨count, _, steps⟩ := Defunctionalization.compiled_operation_opens_typed_future
    (signature := signature) (algebra := algebra) .nil Operation.text (.reference (.there .here)) (.reference .here) .nil
    injectionCaptures ⟨4⟩ (.datum (.leaf true)) .nil rfl rfl rfl
    (.push (.returnTo (.enter (.load (.there .here) .ret)) (Defunctionalization.environment injectionCaptures) .nil)
      (injectionTargetSaved.future.append injectionCaller))
  exact ⟨count + 1, .cons .block steps⟩

theorem injected_request_selects_the_saved_handler :
    Target.Handles (signature := signature) (algebra := algebra) Operation.text ⟨4⟩ injectionRequestFuture := by
  exact ⟨.deep, [], .leaf .boolean, .leaf .boolean, .load .here .ret,
    Defunctionalization.clauses injectionTextClauses, .nil, injectionRequestPrefix, injectionCaller, rfl, List.mem_cons_self⟩

theorem injected_request_does_not_escape_to_the_clause_caller :
    ¬ Target.HeadObservation (signature := signature) (algebra := algebra)
      (.requested Operation.text ⟨4⟩ (.datum (.leaf true)) .nil injectionRequestFuture)
      (.requested Operation.text ⟨4⟩ (.datum (.leaf true)) .nil injectionRequestFuture) :=
  Target.handled_dispatch_is_not_external injected_request_selects_the_saved_handler

theorem owned_closure_without_authority_cannot_enter :
    ¬ ComputationHandoff injectionCaptures .linear none injectionSourceStore.fields injectionBodyFields :=
  ComputationHandoff.missing_owned_authority_rejects .linear

theorem injection_fields_have_unique_owners : UseScope.Valid injectionSourceStore.fields := by
  simp [UseScope.Valid, UseScope.inventory, injectionSourceStore, injectedClosure, injectionCaptures,
    Value.owningField, Environment.owningFields, authorityFields, Datum.owningField, ownedCellSourceValue,
    UseScope.tokens, UseScope.Field.tokens]

theorem consumed_closure_authority_cannot_enter_again (later : UseScope.State) :
    ¬ ComputationHandoff injectionCaptures .linear (some (⟨8⟩, injectionOwner)) injectionBodyFields later :=
  injection_body_handoff.owned_entry_cannot_repeat injection_fields_have_unique_owners

theorem exclusive_capture_cannot_use_shared_entry :
    ¬ ComputationHandoff injectionCaptures .reusable none injectionSourceStore.fields injectionSourceStore.fields := by
  intro handoff
  have impossible : false = true := handoff.unowned_captures_copyable
  contradiction

theorem deep_mode_cannot_acquire_a_shallow_future :
    Target.resumeControl (signature := signature) (algebra := algebra)
      ⟨.deep, .choose, .leaf .boolean, .leaf .boolean⟩ injectionView injectionTargetStore (.datum (.leaf true)) .done = none := by
  simp [Target.resumeControl, UseScope.acquireAt, UseScope.acquire, injectionTargetStore, injectionSourceStore,
    injectionView, injectionOwner, UseScope.takeControl, UseScope.takeGrant, UseScope.takeCapture,
    UseScope.activeFields, UseScope.exposeField, UseScope.unpackControl, injectionShape]

end BoundaryV2.Generalized.Examples
