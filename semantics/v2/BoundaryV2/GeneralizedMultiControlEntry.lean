import BoundaryV2.GeneralizedMultiEntry

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)]

/-- The injected closure's actual authority is consumed after both operands
finish, before its body enters the freshly instantiated use-site context. -/
theorem compiled_multi_injection
    (table : Source.Definitions signature algebra program)
    (continuation : Source.Expression signature algebra program context (.continuation mode .multi effect input answer))
    (injected : Source.Expression signature algebra program context (.computation bodyUse [] input))
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (body : Source.Computation signature algebra program capturedTypes input)
    (captured : Source.RuntimeEnvironment signature algebra program capturedTypes)
    (authority : Option (Id .custody × Owner)) (identity : Id .control)
    (sourceArena : Source.Multi.Arena signature algebra program) (regions : List (Id .region))
    (registry : Source.Multi.Registry signature algebra program)
    {sourceStore evaluated : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (operands : Source.ArgumentsEvaluation bindings sourceArena.cells.reservations.custody sourceStore
      (.cons continuation (.cons injected .nil))
      (.ok (.cons (.continuation identity none) (.cons (.closure body captured authority) .nil))) evaluated)
    (stores : ControlHeapRelated sourceStore targetStore)
    (handoff : ComputationHandoff captured bodyUse authority evaluated.fields fields)
    {sourceOutside : Source.Context signature algebra program answer result} {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (accepted : Source.Multi.Runtime.inject ⟨mode, effect, input, answer⟩ identity
      ⟨⟨{ evaluated with fields := fields }, sourceOutside.plug (.evaluate (.inject continuation injected) bindings)⟩, sourceArena, regions, registry⟩
      body captured sourceOutside (Source.Multi.callSupport table bindings sourceOutside { evaluated with fields := fields }) = some sourceAfter) :
    Source.Multi.ResumeEntry table
      ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.inject continuation injected) bindings)⟩, sourceArena, regions, registry⟩ sourceAfter ∧
    ∃ targetAfter count, 0 < count ∧ MultiRuntimeRelated sourceAfter targetAfter ∧
      Target.Multi.ResumeRun (definitions table)
        ⟨⟨targetStore, .code (computation (.inject continuation injected)) (environment bindings) .nil targetOutside⟩,
          templateArena sourceArena, regions, templateRegistry registry⟩ count targetAfter := by
  obtain ⟨count, targetEvaluated, steps, related⟩ := owned_two_operands_drains
    (UseScope.PackedControlRelated controlPayloadRelated) bindings sourceArena.cells.reservations.custody continuation injected
    (.continuation identity none) (.closure body captured authority) operands (.inject .ret) stores
  have updated : ControlHeapRelated { evaluated with fields := fields } { targetEvaluated with fields := fields } :=
    ⟨rfl, related.controls, related.disposing⟩
  have targetHandoff : ComputationHandoff (environment captured) bodyUse authority targetEvaluated.fields fields := by
    simpa only [environment, ← related.fields] using handoff.map (fun _ _ body => computation body)
  let targetReady : Target.Multi.Runtime signature algebra program result :=
    ⟨⟨{ targetEvaluated with fields := fields },
      .code (.inject (mode := mode) (effect := effect) (use := Use.multi) (useBody := bodyUse) .ret) (environment bindings)
        (.cons (.closure (computation body) (environment captured) authority) (.cons (.continuation identity none) .nil)) targetOutside⟩,
      templateArena sourceArena, regions, templateRegistry registry⟩
  have joined : MultiDataRelated
      (⟨⟨{ evaluated with fields := fields }, sourceOutside.plug (.evaluate (.inject continuation injected) bindings)⟩,
        sourceArena, regions, registry⟩ : Source.Multi.Runtime signature algebra program result) targetReady := ⟨updated, rfl, rfl, rfl⟩
  obtain ⟨targetAfter, entered, matching⟩ := corresponding_acceptance
    (registered_injection_corresponds joined ⟨mode, effect, input, answer⟩ identity body captured (.passthrough bindings outside)
      (Source.Multi.callSupport table bindings sourceOutside { evaluated with fields := fields })) accepted
  rw [← multi_call_support_corresponds table bindings outside updated] at entered
  have reservations : (templateArena sourceArena).cells.reservations = sourceArena.cells.reservations :=
    Cells.reservations_mapBodies _ sourceArena.cells
  rw [← reservations] at steps
  exact ⟨.injection operands handoff accepted, targetAfter, count + 1, by omega, matching,
    Target.Multi.ResumeRun.after_operands steps (.injection targetHandoff entered)⟩

/-- Successor return and operation clauses remain ordinary effectful source
computations, with the resumed body and outside answer typed separately. -/
theorem compiled_multi_successor
    (table : Source.Definitions signature algebra program)
    (continuation : Source.Expression signature algebra program context (.continuation .shallow .multi effect input body))
    (response : Source.Expression signature algebra program context input)
    (returned : Source.Computation signature algebra program (body :: context) answer)
    (clauses : Source.Clauses signature algebra program effect .deep context body answer)
    (bindings : Source.RuntimeEnvironment signature algebra program context) (identity : Id .control)
    (inputValue : Source.RuntimeValue signature algebra program input)
    (sourceArena : Source.Multi.Arena signature algebra program) (regions : List (Id .region))
    (registry : Source.Multi.Registry signature algebra program)
    {sourceStore evaluated : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (operands : Source.ArgumentsEvaluation bindings sourceArena.cells.reservations.custody sourceStore
      (.cons continuation (.cons response .nil)) (.ok (.cons (.continuation identity none) (.cons inputValue .nil))) evaluated)
    (stores : ControlHeapRelated sourceStore targetStore)
    {sourceOutside : Source.Context signature algebra program answer result} {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (accepted : Source.Multi.Runtime.successor identity
      ⟨⟨evaluated, sourceOutside.plug (.evaluate (.resumeWith effect continuation response returned clauses) bindings)⟩, sourceArena, regions, registry⟩
      inputValue returned clauses bindings sourceOutside (Source.Multi.callSupport table bindings sourceOutside evaluated) = some sourceAfter) :
    Source.Multi.ResumeEntry table
      ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.resumeWith effect continuation response returned clauses) bindings)⟩,
        sourceArena, regions, registry⟩ sourceAfter ∧
    ∃ targetAfter count, 0 < count ∧ MultiRuntimeRelated sourceAfter targetAfter ∧
      Target.Multi.ResumeRun (definitions table)
        ⟨⟨targetStore, .code (computation (.resumeWith effect continuation response returned clauses)) (environment bindings) .nil targetOutside⟩,
          templateArena sourceArena, regions, templateRegistry registry⟩ count targetAfter := by
  obtain ⟨count, targetEvaluated, steps, related⟩ := owned_two_operands_drains
    (UseScope.PackedControlRelated controlPayloadRelated) bindings sourceArena.cells.reservations.custody continuation response
    (.continuation identity none) inputValue operands
    (.replaceHandler (use := Use.multi) effect (computation returned) (Defunctionalization.clauses clauses) .ret) stores
  let targetReady : Target.Multi.Runtime signature algebra program result :=
    ⟨⟨targetEvaluated, .code (.replaceHandler (use := Use.multi) effect (computation returned) (Defunctionalization.clauses clauses) .ret)
      (environment bindings) (.cons (value inputValue) (.cons (.continuation identity none) .nil)) targetOutside⟩,
      templateArena sourceArena, regions, templateRegistry registry⟩
  have joined : MultiDataRelated
      (⟨⟨evaluated, sourceOutside.plug (.evaluate (.resumeWith effect continuation response returned clauses) bindings)⟩,
        sourceArena, regions, registry⟩ : Source.Multi.Runtime signature algebra program result) targetReady := ⟨related, rfl, rfl, rfl⟩
  obtain ⟨targetAfter, entered, matching⟩ := corresponding_acceptance
    (registered_successor_corresponds joined identity inputValue returned clauses bindings (.passthrough bindings outside)
      (Source.Multi.callSupport table bindings sourceOutside evaluated)) accepted
  rw [← multi_call_support_corresponds table bindings outside related] at entered
  have reservations : (templateArena sourceArena).cells.reservations = sourceArena.cells.reservations :=
    Cells.reservations_mapBodies _ sourceArena.cells
  rw [← reservations] at steps
  exact ⟨.successor operands accepted, targetAfter, count + 1, by omega, matching,
    Target.Multi.ResumeRun.after_operands steps (.successor entered)⟩

end BoundaryV2.Generalized.Defunctionalization
