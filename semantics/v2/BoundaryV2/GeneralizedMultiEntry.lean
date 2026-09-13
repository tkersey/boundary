import BoundaryV2.GeneralizedRegisteredResume
import BoundaryV2.GeneralizedStateExecution

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

namespace Source.Multi

def callSupport (table : Definitions signature algebra program)
    (bindings : RuntimeEnvironment signature algebra program context)
    (outside : Context signature algebra program answer result) (store : ControlHeap signature algebra program) : List Reference :=
  definitionReferences table ++ environmentReferences bindings ++ outside.referenceSupport ++ storeReferences store

inductive ResumeEntry (table : Definitions signature algebra program) :
    Runtime signature algebra program result → Runtime signature algebra program result → Prop where
  | enter
      {continuation : Expression signature algebra program context (.continuation mode .multi effect input answer)}
      {response : Expression signature algebra program context input}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program answer result}
      {store evaluated : ControlHeap signature algebra program} {arena : Arena signature algebra program}
      {registry : Registry signature algebra program} {value : RuntimeValue signature algebra program input} :
      ArgumentsEvaluation bindings arena.cells.reservations.custody store (.cons continuation (.cons response .nil))
        (.ok (.cons (.continuation identity none) (.cons value .nil))) evaluated →
      Runtime.resume ⟨mode, effect, input, answer⟩ identity
        ⟨⟨evaluated, outside.plug (.evaluate (.resume continuation response) bindings)⟩, arena, regions, registry⟩ value outside
        (callSupport table bindings outside evaluated) = some after →
      ResumeEntry table
        ⟨⟨store, outside.plug (.evaluate (.resume continuation response) bindings)⟩, arena, regions, registry⟩ after
  | injection {bodyUse : Use}
      {continuation : Expression signature algebra program context (.continuation mode .multi effect input answer)}
      {injected : Expression signature algebra program context (.computation bodyUse [] input)}
      {body : Computation signature algebra program capturedTypes input}
      {captured : RuntimeEnvironment signature algebra program capturedTypes}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program answer result}
      {store evaluated : ControlHeap signature algebra program} {arena : Arena signature algebra program}
      {registry : Registry signature algebra program} :
      ArgumentsEvaluation bindings arena.cells.reservations.custody store (.cons continuation (.cons injected .nil))
        (.ok (.cons (.continuation identity none) (.cons (.closure body captured authority) .nil))) evaluated →
      ComputationHandoff captured bodyUse authority evaluated.fields fields →
      Runtime.inject ⟨mode, effect, input, answer⟩ identity
        ⟨⟨{ evaluated with fields := fields }, outside.plug (.evaluate (.inject continuation injected) bindings)⟩, arena, regions, registry⟩
        body captured outside (callSupport table bindings outside { evaluated with fields := fields }) = some after →
      ResumeEntry table
        ⟨⟨store, outside.plug (.evaluate (.inject continuation injected) bindings)⟩, arena, regions, registry⟩ after
  | successor
      {continuation : Expression signature algebra program context (.continuation .shallow .multi effect input body)}
      {response : Expression signature algebra program context input}
      {returned : Computation signature algebra program (body :: context) answer}
      {clauses : Clauses signature algebra program effect .deep context body answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program answer result}
      {store evaluated : ControlHeap signature algebra program} {arena : Arena signature algebra program}
      {registry : Registry signature algebra program} {value : RuntimeValue signature algebra program input} :
      ArgumentsEvaluation bindings arena.cells.reservations.custody store (.cons continuation (.cons response .nil))
        (.ok (.cons (.continuation identity none) (.cons value .nil))) evaluated →
      Runtime.successor identity
        ⟨⟨evaluated, outside.plug (.evaluate (.resumeWith effect continuation response returned clauses) bindings)⟩, arena, regions, registry⟩
        value returned clauses bindings outside (callSupport table bindings outside evaluated) = some after →
      ResumeEntry table
        ⟨⟨store, outside.plug (.evaluate (.resumeWith effect continuation response returned clauses) bindings)⟩, arena, regions, registry⟩ after

end Source.Multi

namespace Target.Multi

def callSupport (table : Definitions signature algebra program)
    (bindings : RuntimeEnvironment signature algebra program context) (values : RuntimeEnvironment signature algebra program operands)
    (next : Code signature algebra program context (answer :: operands) rest)
    (outside : Stack signature algebra program rest result) (store : ControlHeap signature algebra program) : List Reference :=
  definitionReferences table ++ environmentReferences bindings ++ environmentReferences values ++ next.references ++
    outside.installationReferences ++ storeReferences store

inductive ResumeEntry (table : Definitions signature algebra program) :
    Runtime signature algebra program result → Runtime signature algebra program result → Prop where
  | enter
      {next : Code signature algebra program context (answer :: operands) rest}
      {bindings : RuntimeEnvironment signature algebra program context} {values : RuntimeEnvironment signature algebra program operands}
      {outside : Stack signature algebra program rest result}
      {store : ControlHeap signature algebra program} {arena : Arena signature algebra program}
      {registry : Registry signature algebra program} {value : RuntimeValue signature algebra program input} :
      Runtime.resume ⟨mode, effect, input, answer⟩ identity
        ⟨⟨store, .code (.resume (mode := mode) (effect := effect) (use := Use.multi) next) bindings
          (.cons value (.cons (.continuation identity none) values)) outside⟩, arena, regions, registry⟩ value
        (.push (.returnTo next bindings values) outside) (callSupport table bindings values next outside store) = some after →
      ResumeEntry table
        ⟨⟨store, .code (.resume (mode := mode) (effect := effect) (use := Use.multi) next) bindings
          (.cons value (.cons (.continuation identity none) values)) outside⟩, arena, regions, registry⟩ after
  | injection {bodyUse : Use}
      {next : Code signature algebra program context (answer :: operands) rest}
      {body : Code signature algebra program capturedTypes [] input}
      {captured : RuntimeEnvironment signature algebra program capturedTypes}
      {bindings : RuntimeEnvironment signature algebra program context} {values : RuntimeEnvironment signature algebra program operands}
      {outside : Stack signature algebra program rest result}
      {store : ControlHeap signature algebra program} {arena : Arena signature algebra program}
      {registry : Registry signature algebra program} :
      ComputationHandoff captured bodyUse authority store.fields fields →
      Runtime.inject ⟨mode, effect, input, answer⟩ identity
        ⟨⟨{ store with fields := fields }, .code (.inject (mode := mode) (effect := effect) (use := Use.multi) (useBody := bodyUse) next)
          bindings (.cons (.closure body captured authority) (.cons (.continuation identity none) values)) outside⟩, arena, regions, registry⟩
        ⟨capturedTypes, body, captured⟩ (.push (.returnTo next bindings values) outside)
        (callSupport table bindings values next outside { store with fields := fields }) = some after →
      ResumeEntry table
        ⟨⟨store, .code (.inject (mode := mode) (effect := effect) (use := Use.multi) (useBody := bodyUse) next)
          bindings (.cons (.closure body captured authority) (.cons (.continuation identity none) values)) outside⟩, arena, regions, registry⟩ after
  | successor
      {next : Code signature algebra program context (answer :: operands) rest}
      {returned : Code signature algebra program (body :: context) [] answer}
      {clauses : Clauses signature algebra program effect .deep context body answer}
      {bindings : RuntimeEnvironment signature algebra program context} {values : RuntimeEnvironment signature algebra program operands}
      {outside : Stack signature algebra program rest result}
      {store : ControlHeap signature algebra program} {arena : Arena signature algebra program}
      {registry : Registry signature algebra program} {value : RuntimeValue signature algebra program input} :
      Runtime.successor identity
        ⟨⟨store, .code (.replaceHandler (use := Use.multi) effect returned clauses next) bindings
          (.cons value (.cons (.continuation identity none) values)) outside⟩, arena, regions, registry⟩
        value returned clauses bindings (.push (.returnTo next bindings values) outside)
        (callSupport table bindings values next outside store) = some after →
      ResumeEntry table
        ⟨⟨store, .code (.replaceHandler (use := Use.multi) effect returned clauses next) bindings
          (.cons value (.cons (.continuation identity none) values)) outside⟩, arena, regions, registry⟩ after

/-- Operand evaluation changes only its actual control state; the registry and
branch arena travel through every step before the registered entry occurs. -/
inductive ResumeRun (table : Definitions signature algebra program) :
    Runtime signature algebra program result → Nat → Runtime signature algebra program result → Prop where
  | entry : ResumeEntry table before after → ResumeRun table before 1 after
  | operand
      {bindings : RuntimeEnvironment signature algebra program context}
      {before after : Operands signature algebra program context answer}
      {outside : Stack signature algebra program answer result} {arena : Arena signature algebra program} :
      OwnedOperandStep bindings arena.cells.reservations.custody store before changed after →
      ResumeRun table ⟨⟨changed, .code after.code bindings after.values outside⟩, arena, regions, registry⟩ count last →
      ResumeRun table ⟨⟨store, .code before.code bindings before.values outside⟩, arena, regions, registry⟩ (count + 1) last

omit [DecidableEq (TypeOf signature)] in
theorem ResumeRun.after_operands
    {bindings : RuntimeEnvironment signature algebra program context}
    {before after : Operands signature algebra program context answer}
    {outside : Stack signature algebra program answer result} {arena : Arena signature algebra program}
    (operands : OwnedOperandSteps bindings arena.cells.reservations.custody store before count changed after)
    (entry : ResumeEntry table ⟨⟨changed, .code after.code bindings after.values outside⟩, arena, regions, registry⟩ last) :
    ResumeRun table ⟨⟨store, .code before.code bindings before.values outside⟩, arena, regions, registry⟩ (count + 1) last := by
  induction operands with
  | refl => exact .entry entry
  | cons first rest induction => exact .operand first (induction entry)

end Target.Multi

namespace Defunctionalization

omit [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)] in
theorem multi_call_support_corresponds
    (table : Source.Definitions signature algebra program) (bindings : Source.RuntimeEnvironment signature algebra program context)
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (stores : ControlHeapRelated sourceStore targetStore) :
    Target.Multi.callSupport (definitions table) (environment bindings) .nil .ret targetOutside targetStore =
      Source.Multi.callSupport table bindings sourceOutside sourceStore := by
  simp only [Target.Multi.callSupport, Source.Multi.callSupport, definitions, definition_reference_support,
    environment_reference_support, Target.environmentReferences, Target.Code.references, List.append_nil,
    context_reference_support outside, store_reference_support stores]

omit [DecidableEq (TypeOf signature)] in
/-- Both operands finish before lookup and activation. The returned source and
target entries retain the same registry and current arena, with related futures. -/
theorem compiled_multi_resumption
    (table : Source.Definitions signature algebra program)
    (continuation : Source.Expression signature algebra program context (.continuation mode .multi effect input answer))
    (response : Source.Expression signature algebra program context input)
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
    (accepted : Source.Multi.Runtime.resume ⟨mode, effect, input, answer⟩ identity
      ⟨⟨evaluated, sourceOutside.plug (.evaluate (.resume continuation response) bindings)⟩, sourceArena, regions, registry⟩ inputValue sourceOutside
      (Source.Multi.callSupport table bindings sourceOutside evaluated) = some sourceAfter) :
    Source.Multi.ResumeEntry table
      ⟨⟨sourceStore, sourceOutside.plug (.evaluate (.resume continuation response) bindings)⟩, sourceArena, regions, registry⟩ sourceAfter ∧
    ∃ targetAfter count, 0 < count ∧ MultiRuntimeRelated sourceAfter targetAfter ∧
      Target.Multi.ResumeRun (definitions table)
        ⟨⟨targetStore, .code (computation (.resume continuation response)) (environment bindings) .nil targetOutside⟩,
          templateArena sourceArena, regions, templateRegistry registry⟩ count targetAfter := by
  obtain ⟨count, targetEvaluated, steps, related⟩ := owned_two_operands_drains
    (UseScope.PackedControlRelated controlPayloadRelated) bindings sourceArena.cells.reservations.custody continuation response
    (.continuation identity none) inputValue operands (.resume (use := Use.multi) .ret) stores
  let targetReady : Target.Multi.Runtime signature algebra program result :=
    ⟨⟨targetEvaluated, .code (.resume (mode := mode) (effect := effect) (use := Use.multi) .ret) (environment bindings)
      (.cons (value inputValue) (.cons (.continuation identity none) .nil)) targetOutside⟩,
      templateArena sourceArena, regions, templateRegistry registry⟩
  have joined : MultiDataRelated
      (⟨⟨evaluated, sourceOutside.plug (.evaluate (.resume continuation response) bindings)⟩, sourceArena, regions, registry⟩ :
        Source.Multi.Runtime signature algebra program result) targetReady := ⟨related, rfl, rfl, rfl⟩
  obtain ⟨targetAfter, resumed, matching⟩ := corresponding_acceptance
    (registered_resume_corresponds joined ⟨mode, effect, input, answer⟩ identity inputValue
      (.passthrough bindings outside) (Source.Multi.callSupport table bindings sourceOutside evaluated)) accepted
  rw [← multi_call_support_corresponds table bindings outside related] at resumed
  have reservations : (templateArena sourceArena).cells.reservations = sourceArena.cells.reservations :=
    Cells.reservations_mapBodies _ sourceArena.cells
  rw [← reservations] at steps
  exact ⟨.enter operands accepted, targetAfter, count + 1, by omega, matching,
    Target.Multi.ResumeRun.after_operands steps (.enter resumed)⟩

end Defunctionalization
end BoundaryV2.Generalized
