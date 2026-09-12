import BoundaryV2.GeneralizedControlMachine
import BoundaryV2.GeneralizedSourceExecution

namespace BoundaryV2.Generalized

namespace Source

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)} [DecidableEq (ControlShape signature)]

/-- Local execution with a typed owned-continuation store. Ordinary source
reductions retain that store; resumption evaluates operands before consuming
authority. Reusable/multi activation and scope/exit execution remain separate
unfinished parts of the core semantics. -/
inductive OwnedStep (table : Definitions signature algebra program) :
    {result : TypeOf signature} →
    ControlState signature algebra program result →
    ControlState signature algebra program result → Prop where
  | ordinary : Step table before after → OwnedStep table ⟨store, before⟩ ⟨store, after⟩
  | resume {use : UseScope.OneShotUse}
      {continuation : Expression signature algebra program context (.continuation mode use.type effect input body)}
      {response : Expression signature algebra program context input}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program body result} :
      continuation.evaluate bindings = .ok (.continuation view.identity (some (view.authority, view.owner))) →
      response.evaluate bindings = .ok value → resumeControl ⟨mode, effect, input, body⟩ view store value outside = some after →
      OwnedStep table ⟨store, outside.plug (.evaluate (.resume continuation response) bindings)⟩ after
  | successor {use : UseScope.OneShotUse}
      {continuation : Expression signature algebra program context (.continuation .shallow use.type effect input body)}
      {response : Expression signature algebra program context input}
      {returned : Computation signature algebra program (body :: context) answer}
      {clauses : Clauses signature algebra program effect .deep context body answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program answer result} :
      continuation.evaluate bindings = .ok (.continuation view.identity (some (view.authority, view.owner))) →
      response.evaluate bindings = .ok value → resumeControlWith view store value returned clauses bindings outside = some after →
      OwnedStep table ⟨store, outside.plug (.evaluate (.resumeWith effect continuation response returned clauses) bindings)⟩ after

end Source

namespace Target

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)} [DecidableEq (ControlShape signature)]

/-- Target control inspects its own instruction and operand data. Authority is
consumed by the store operation before the resulting configuration is exposed. -/
inductive OwnedStep (table : Definitions signature algebra program) :
    {result : TypeOf signature} →
    ControlState signature algebra program result →
    ControlState signature algebra program result → Prop where
  | ordinary : CallStep table before after → OwnedStep table ⟨store, before⟩ ⟨store, after⟩
  | resume {use : UseScope.OneShotUse}
      {next : Code signature algebra program context (body :: operands) answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {values : RuntimeEnvironment signature algebra program operands}
      {outside : Stack signature algebra program answer result} :
      resumeControl ⟨mode, effect, input, body⟩ view store value (.push (.returnTo next bindings values) outside) = some after →
      OwnedStep table ⟨store, .code (.resume (use := use.type) next) bindings
        (.cons value (.cons (.continuation view.identity (some (view.authority, view.owner))) values)) outside⟩ after
  | successor {use : UseScope.OneShotUse}
      {next : Code signature algebra program context (answer :: operands) rest}
      {returned : Code signature algebra program (body :: context) [] answer}
      {clauses : Clauses signature algebra program effect .deep context body answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {values : RuntimeEnvironment signature algebra program operands}
      {outside : Stack signature algebra program rest result} :
      resumeControlWith view store value returned clauses bindings (.push (.returnTo next bindings values) outside) = some after →
      OwnedStep table ⟨store, .code (.replaceHandler (use := use.type) effect returned clauses next) bindings
        (.cons value (.cons (.continuation view.identity (some (view.authority, view.owner))) values)) outside⟩ after

inductive OwnedSteps (table : Definitions signature algebra program) :
    {result : TypeOf signature} →
    ControlState signature algebra program result → Nat →
    ControlState signature algebra program result → Prop where
  | refl : OwnedSteps table state 0 state
  | cons : OwnedStep table first middle → OwnedSteps table middle count last → OwnedSteps table first (count + 1) last

theorem OwnedSteps.single {before after : ControlState signature algebra program result}
    (step : OwnedStep table before after) : OwnedSteps table before 1 after := .cons step .refl

theorem OwnedSteps.trans {before middle after : ControlState signature algebra program result}
    (first : OwnedSteps table before count middle) (second : OwnedSteps table middle rest after) :
    OwnedSteps table before (count + rest) after := by
  induction first with
  | refl => simpa using second
  | cons step tail induction => simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using OwnedSteps.cons step (induction second)

theorem CallSteps.with_owned_store
    (steps : CallSteps table before count after)
    (store : ControlHeap signature algebra program) :
    OwnedSteps table ⟨store, before⟩ count ⟨store, after⟩ := by
  induction steps with
  | refl => exact .refl
  | cons step tail induction => exact .cons (.ordinary step) induction

theorem OwnedStep.preserves_ownership {before after : ControlState signature algebra program result}
    (step : OwnedStep table before after)
    (valid : UseScope.ControlStore.Valid before.store) : UseScope.ControlStore.Valid after.store := by
  cases step with
  | ordinary step => exact valid
  | resume accepted => exact resume_control_preserves_ownership valid accepted
  | successor accepted => exact successor_control_preserves_ownership valid accepted

theorem OwnedSteps.preserves_ownership {before after : ControlState signature algebra program result}
    (steps : OwnedSteps table before count after)
    (valid : UseScope.ControlStore.Valid before.store) : UseScope.ControlStore.Valid after.store := by
  induction steps with
  | refl => exact valid
  | cons step tail induction => exact induction (step.preserves_ownership valid)

end Target

namespace Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)} [DecidableEq (ControlShape signature)]

private theorem corresponding_acceptance (matched : Option.Rel related source target) (accepted : source = some first) :
    ∃ second, target = some second ∧ related first second := by
  subst source
  cases matched with
  | some proof => exact ⟨_, rfl, proof⟩

/-- Every successful source owned resumption has a positive, finite compiled
execution. Operand draining keeps both the lexical bindings and caller tail. -/
theorem compiled_owned_resumption
    (table : Source.Definitions signature algebra program) (use : UseScope.OneShotUse)
    (continuation : Source.Expression signature algebra program context (.continuation mode use.type effect input body))
    (response : Source.Expression signature algebra program context input)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (view : UseScope.ControlView) (inputValue : Source.RuntimeValue signature algebra program input)
    (continuationEvaluated : continuation.evaluate bindings = .ok (.continuation view.identity (some (view.authority, view.owner))))
    (responseEvaluated : response.evaluate bindings = .ok inputValue)
    {sourceStore : Source.ControlHeap signature algebra program}
    {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    {sourceOutside : Source.Context signature algebra program body result}
    {targetOutside : Target.Stack signature algebra program body result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (accepted : Source.resumeControl ⟨mode, effect, input, body⟩ view sourceStore inputValue sourceOutside = some sourceAfter) :
    ∃ targetAfter count, 0 < count ∧ ControlStateRelated sourceAfter targetAfter ∧
      Source.OwnedStep table ⟨sourceStore, sourceOutside.plug (.evaluate (.resume continuation response) bindings)⟩ sourceAfter ∧
      Target.OwnedSteps (definitions table)
        ⟨targetStore, .code (computation (.resume continuation response)) (environment bindings) .nil targetOutside⟩ count targetAfter := by
  have nextOutside := ContextRelated.passthrough bindings outside
  obtain ⟨targetAfter, targetAccepted, matched⟩ := corresponding_acceptance
    (resume_control_corresponds stores ⟨mode, effect, input, body⟩ view inputValue nextOutside) accepted
  obtain ⟨firstCount, firstSteps⟩ := expression_drains continuation bindings
    (expression response (.resume .ret)) .nil _ continuationEvaluated
  obtain ⟨secondCount, secondSteps⟩ := expression_drains response bindings (.resume .ret)
    (.cons (.continuation view.identity (some (view.authority, view.owner))) .nil) _ responseEvaluated
  refine ⟨targetAfter, firstCount + secondCount + 1, by omega, matched,
    .resume continuationEvaluated responseEvaluated accepted, ?_⟩
  exact (((firstSteps.trans secondSteps).in_context (definitions table) targetOutside).with_owned_store targetStore).trans
    (.single (.resume targetAccepted))

theorem compiled_owned_successor
    (table : Source.Definitions signature algebra program) (use : UseScope.OneShotUse)
    (continuation : Source.Expression signature algebra program context (.continuation .shallow use.type effect input body))
    (response : Source.Expression signature algebra program context input)
    (returned : Source.Computation signature algebra program (body :: context) answer)
    (clauses : Source.Clauses signature algebra program effect .deep context body answer)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (view : UseScope.ControlView) (inputValue : Source.RuntimeValue signature algebra program input)
    (continuationEvaluated : continuation.evaluate bindings = .ok (.continuation view.identity (some (view.authority, view.owner))))
    (responseEvaluated : response.evaluate bindings = .ok inputValue)
    {sourceStore : Source.ControlHeap signature algebra program}
    {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    {sourceOutside : Source.Context signature algebra program answer result}
    {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (accepted : Source.resumeControlWith view sourceStore inputValue returned clauses bindings sourceOutside = some sourceAfter) :
    ∃ targetAfter count, 0 < count ∧ ControlStateRelated sourceAfter targetAfter ∧
      Source.OwnedStep table ⟨sourceStore, sourceOutside.plug (.evaluate (.resumeWith effect continuation response returned clauses) bindings)⟩ sourceAfter ∧
      Target.OwnedSteps (definitions table)
        ⟨targetStore, .code (computation (.resumeWith effect continuation response returned clauses)) (environment bindings) .nil targetOutside⟩ count targetAfter := by
  have nextOutside := ContextRelated.passthrough bindings outside
  obtain ⟨targetAfter, targetAccepted, matched⟩ := corresponding_acceptance
    (successor_control_corresponds stores view inputValue returned clauses bindings nextOutside) accepted
  obtain ⟨firstCount, firstSteps⟩ := expression_drains continuation bindings
    (expression response (.replaceHandler effect (computation returned) (Defunctionalization.clauses clauses) .ret)) .nil _ continuationEvaluated
  obtain ⟨secondCount, secondSteps⟩ := expression_drains response bindings
    (.replaceHandler effect (computation returned) (Defunctionalization.clauses clauses) .ret)
    (.cons (.continuation view.identity (some (view.authority, view.owner))) .nil) _ responseEvaluated
  refine ⟨targetAfter, firstCount + secondCount + 1, by omega, matched,
    .successor continuationEvaluated responseEvaluated accepted, ?_⟩
  exact (((firstSteps.trans secondSteps).in_context (definitions table) targetOutside).with_owned_store targetStore).trans
    (.single (.successor targetAccepted))

end Defunctionalization
end BoundaryV2.Generalized
