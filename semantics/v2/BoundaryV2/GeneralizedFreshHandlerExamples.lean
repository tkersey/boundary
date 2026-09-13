import BoundaryV2.GeneralizedFreshHandlerExecution
import BoundaryV2.GeneralizedExamples

namespace BoundaryV2.Generalized.Examples

def freshHandlerBindings : Source.RuntimeEnvironment signature algebra [] [.capability .text] :=
  .cons (.datum (.capability ⟨0⟩)) .nil

def freshHandlerReturn : Source.Computation signature algebra [] [.leaf .boolean, .capability .text] (.leaf .boolean) :=
  .returnValue (.reference .here)

def freshHandlerClauses : Source.Clauses signature algebra [] .text .deep [.capability .text] (.leaf .boolean) (.leaf .boolean) :=
  .cons Operation.text .affine (.returnValue (.datum (.leaf false))) .nil

def freshHandlerBody : Source.Computation signature algebra [] [.capability .text, .capability .text] (.leaf .boolean) :=
  .bind (.perform (signature := signature) (algebra := algebra) Operation.text (.reference (.there .here)) (.datum (.leaf true)) .nil)
    (.returnValue (.datum (.leaf true)))

def freshHandlerProgram : Source.Computation signature algebra [] [.capability .text] (.leaf .boolean) :=
  .handle .text .deep freshHandlerReturn freshHandlerClauses freshHandlerBody

def afterFreshHandler : Source.Computation signature algebra [] [.leaf .boolean] (.capability .text) :=
  .returnValue (.datum (.capability ⟨15⟩))

def freshSourceOutside : Source.Context signature algebra [] (.leaf .boolean) (.capability .text) :=
  .push (.bind (fun value => .evaluate afterFreshHandler (.cons value .nil))) .done

def unusedCallerBindings : Source.RuntimeEnvironment signature algebra [] [.capability .text] :=
  .cons (.datum (.capability ⟨99⟩)) .nil

def freshTargetOutside : Target.Stack signature algebra [] (.leaf .boolean) (.capability .text) :=
  .push (.returnTo (.enter (Defunctionalization.computation afterFreshHandler)) .nil .nil)
    (.push (.returnTo .ret (Defunctionalization.environment unusedCallerBindings) .nil) .done)

def dormantHandlerBody : Source.Computation signature algebra [] [] (.capability .text) :=
  .returnValue (.datum (.capability ⟨12⟩))

def handlerSupportCells : Cells signature algebra (Source.Computation signature algebra []) :=
  [⟨⟨0⟩, ⟨0⟩, .computation .reusable [] (.capability .text), .closure dormantHandlerBody .nil none⟩]

def freshSourceStore : Source.ControlHeap signature algebra [] := ⟨⟨[], [], []⟩, [], []⟩
def freshTargetStore : Target.ControlHeap signature algebra [] := ⟨⟨[], [], []⟩, [], []⟩

def installedAttachment := Target.freshAttachment (.nil : Target.Definitions signature algebra [])
  (Defunctionalization.computation freshHandlerProgram) (Defunctionalization.environment freshHandlerBindings) .nil
  freshTargetOutside freshTargetStore (Defunctionalization.cells handlerSupportCells) []

theorem installation_accounts_for_code_captures_and_continuations :
    installedAttachment = ⟨16⟩ ∧
    Reference.name .attachment ⟨12⟩ ∈ Target.cellsReferences (Defunctionalization.cells handlerSupportCells) ∧
    Reference.name .attachment ⟨15⟩ ∈ freshTargetOutside.installationReferences := by
  refine ⟨rfl, ?_, ?_⟩
  · simp [Target.cellsReferences, Target.cellReferences, Defunctionalization.cells, Cells.mapBodies, Cell.map,
      handlerSupportCells, Target.valueReferences, Value.map, Defunctionalization.computation,
      Defunctionalization.expression, Target.Code.references, Datum.references, dormantHandlerBody]
  · simp [freshTargetOutside, Target.Stack.installationReferences, Target.Frame.installationReferences,
      afterFreshHandler, Defunctionalization.computation, Defunctionalization.expression, Target.Code.references,
      Datum.references, Target.environmentReferences]

theorem fresh_handler_has_corresponding_stateful_installation :
    Source.ExecutionStep (.nil : Source.Definitions signature algebra [])
      ⟨⟨freshSourceStore, freshSourceOutside.plug (.evaluate freshHandlerProgram freshHandlerBindings)⟩, handlerSupportCells, [⟨0⟩]⟩
      ⟨⟨freshSourceStore, freshSourceOutside.plug (.handler .text .deep installedAttachment freshHandlerReturn freshHandlerClauses
        freshHandlerBindings (.evaluate freshHandlerBody (.cons (.datum (.capability installedAttachment)) freshHandlerBindings)))⟩,
        handlerSupportCells, [⟨0⟩]⟩ := by
  have outside : Defunctionalization.ContextRelated signature algebra [] freshSourceOutside freshTargetOutside :=
    .push (.bind afterFreshHandler .nil) (.passthrough unusedCallerBindings .done)
  exact (Defunctionalization.compiled_fresh_handler (signature := signature) (algebra := algebra)
    .nil .text .deep freshHandlerReturn freshHandlerClauses freshHandlerBody freshHandlerBindings outside
    (sourceStore := freshSourceStore) (targetStore := freshTargetStore) ⟨rfl, .nil, .nil⟩ handlerSupportCells [⟨0⟩] []).1

theorem installed_handler_does_not_select_the_ambient_capability :
    Target.select (signature := signature) (algebra := algebra) ⟨0⟩
      (.push (.handler .text .deep installedAttachment (Defunctionalization.computation freshHandlerReturn)
      (Defunctionalization.clauses freshHandlerClauses) (Defunctionalization.environment freshHandlerBindings)) freshTargetOutside) = none := by
  have forwarded := Defunctionalization.fresh_handler_forwards_ambient (signature := signature) (algebra := algebra)
    ⟨0⟩ installedAttachment (by decide) .text .deep (Defunctionalization.computation freshHandlerReturn)
    (Defunctionalization.clauses freshHandlerClauses) (Defunctionalization.environment freshHandlerBindings) freshTargetOutside
  exact forwarded

theorem administrative_return_bindings_do_not_affect_the_returned_value :
    Target.CallSteps (.nil : Target.Definitions signature algebra [])
      (.returned (.datum (.capability (effect := Effect.text) ⟨15⟩))
        (.push (.returnTo .ret (Defunctionalization.environment unusedCallerBindings) .nil) .done)) 2
      (.returned (.datum (.capability (effect := Effect.text) ⟨15⟩)) .done) :=
  Defunctionalization.return_passthrough_takes_two_steps .nil _ _ .nil .done

end BoundaryV2.Generalized.Examples
