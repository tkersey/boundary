import BoundaryV2.GeneralizedOwnedClause
import BoundaryV2.GeneralizedSourceExecution
import BoundaryV2.GeneralizedComputationHandoff
import BoundaryV2.GeneralizedApplicationGate
import BoundaryV2.GeneralizedOwnedOperandLowering

namespace BoundaryV2.Generalized

namespace Source

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)} [DecidableEq (ControlShape signature)]

/-- Local execution with a typed owned-continuation store. Ordinary source
reductions retain that store; resumption evaluates operands before consuming
authority. Reusable/multi activation and scope/exit execution remain separate
unfinished parts of the core semantics. -/
inductive OwnedStep (table : Definitions signature algebra program) (reserved : UseScope.ReservedNames) :
    {result : TypeOf signature} →
    ControlState signature algebra program result →
    ControlState signature algebra program result → Prop where
  | ordinary (step : Step table before after) (neutral : before.needsOwnershipStep = false := by rfl) :
      OwnedStep table reserved ⟨store, before⟩ ⟨store, after⟩
  | resume {use : UseScope.OneShotUse}
      {continuation : Expression signature algebra program context (.continuation mode use.type effect input body)}
      {response : Expression signature algebra program context input}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program body result} :
      ArgumentsEvaluation bindings reserved.custody store (.cons continuation (.cons response .nil))
        (.ok (.cons (.continuation view.identity (some (view.authority, view.owner))) (.cons value .nil))) evaluated →
      resumeControl ⟨mode, effect, input, body⟩ view evaluated value outside = some after →
      OwnedStep table reserved ⟨store, outside.plug (.evaluate (.resume continuation response) bindings)⟩ after
  | successor {use : UseScope.OneShotUse}
      {continuation : Expression signature algebra program context (.continuation .shallow use.type effect input body)}
      {response : Expression signature algebra program context input}
      {returned : Computation signature algebra program (body :: context) answer}
      {clauses : Clauses signature algebra program effect .deep context body answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program answer result} :
      ArgumentsEvaluation bindings reserved.custody store (.cons continuation (.cons response .nil))
        (.ok (.cons (.continuation view.identity (some (view.authority, view.owner))) (.cons value .nil))) evaluated →
      resumeControlWith view evaluated value returned clauses bindings outside = some after →
      OwnedStep table reserved ⟨store, outside.plug (.evaluate (.resumeWith effect continuation response returned clauses) bindings)⟩ after
  | injection {use : UseScope.OneShotUse} {bodyUse : Use}
      {continuation : Expression signature algebra program context (.continuation mode use.type effect input answer)}
      {injected : Expression signature algebra program context (.computation bodyUse [] input)}
      {body : Computation signature algebra program capturedTypes input}
      {captured : RuntimeEnvironment signature algebra program capturedTypes}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program answer result} :
      ArgumentsEvaluation bindings reserved.custody store (.cons continuation (.cons injected .nil))
        (.ok (.cons (.continuation view.identity (some (view.authority, view.owner))) (.cons (.closure body captured authority) .nil))) evaluated →
      ComputationHandoff captured bodyUse authority evaluated.fields fields →
      injectControl ⟨mode, effect, input, answer⟩ view { evaluated with fields := fields } body captured outside = some after →
      OwnedStep table reserved ⟨store, outside.plug (.evaluate (.inject continuation injected) bindings)⟩ after
  /-- One selector governs requests in saved and surrounding source contexts.
  Selection and physical capture use only source data and source operations. -/
  | handledRequest {effect : signature.Effect} {operation : signature.operation effect}
      [DecidableEq (signature.operation effect)]
      {mode : Mode} {context : List (TypeOf signature)} {body answer result : TypeOf signature}
      {returned : Computation signature algebra program (body :: context) answer}
      {clauses : Clauses signature algebra program effect mode context body answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {payload : RuntimeValue signature algebra program (signature.payload operation)}
      {bodies : RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type)}
      {input : TypeOf signature}
      {saved : Context signature algebra program (signature.result operation) input}
      {around : Context signature algebra program input result}
      {inside : Context signature algebra program (signature.result operation) body}
      {outside : Context signature algebra program answer result}
      {store : ControlHeap signature algebra program} {before captured after : List UseScope.Field}
      {partition : store.fields.active = before ++ captured ++ after} {clause : OwnedClause signature algebra program result} :
      select attachment (saved.append around) =
        some ⟨effect, mode, attachment, body, answer, context, returned, clauses, bindings, inside, outside⟩ →
      dispatchOwnedClause operation attachment returned clauses bindings inside payload bodies outside
        owner before captured after store partition reserved = some clause →
      OwnedStep table reserved ⟨store, around.plug (.request operation attachment payload bodies saved)⟩ clause.state

/-- The syntactically installed handler is a derived case of request dispatch. -/
theorem OwnedStep.handled {effect : signature.Effect} {operation : signature.operation effect}
      [DecidableEq (signature.operation effect)]
      {mode : Mode} {context : List (TypeOf signature)} {body answer result : TypeOf signature}
      {returned : Computation signature algebra program (body :: context) answer}
      {clauses : Clauses signature algebra program effect mode context body answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {payload : RuntimeValue signature algebra program (signature.payload operation)}
      {bodies : RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type)}
      {inside : Context signature algebra program (signature.result operation) body}
      {outside : Context signature algebra program answer result}
      {store : ControlHeap signature algebra program} {before captured after : List UseScope.Field}
      {partition : store.fields.active = before ++ captured ++ after} {clause : OwnedClause signature algebra program result}
      (nearest : select attachment inside = none)
      (accepted :
      dispatchOwnedClause operation attachment returned clauses bindings inside payload bodies outside
        owner before captured after store partition reserved = some clause) :
      OwnedStep table reserved ⟨store, outside.plug (.handler effect mode attachment returned clauses bindings
        (.request operation attachment payload bodies inside))⟩ clause.state :=
  .handledRequest (saved := inside) (around := .push (.handler effect mode attachment returned clauses bindings) outside)
    (matching_delimiter_after_prefix attachment inside effect mode returned clauses bindings outside nearest) accepted

inductive OwnedSteps (table : Definitions signature algebra program) (reserved : UseScope.ReservedNames) :
    {result : TypeOf signature} → ControlState signature algebra program result → Nat →
    ControlState signature algebra program result → Prop where
  | refl : OwnedSteps table reserved state 0 state
  | cons : OwnedStep table reserved first middle → OwnedSteps table reserved middle count last → OwnedSteps table reserved first (count + 1) last

theorem OwnedSteps.single {before after : ControlState signature algebra program result}
    (step : OwnedStep table reserved before after) : OwnedSteps table reserved before 1 after := .cons step .refl

theorem OwnedSteps.trans {before middle after : ControlState signature algebra program result}
    (first : OwnedSteps table reserved before count middle) (second : OwnedSteps table reserved middle rest after) :
    OwnedSteps table reserved before (count + rest) after := by
  induction first with
  | refl => simpa using second
  | cons step tail induction => simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using OwnedSteps.cons step (induction second)


end Source

namespace Target

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)} [DecidableEq (ControlShape signature)]

/-- Target control inspects its own instruction and operand data. Authority is
consumed by the store operation before the resulting configuration is exposed.
Instruction mode/effect indices are bound explicitly to the acquisition shape;
independent implicit indices would admit a differently typed view of the grant. -/
inductive OwnedStep (table : Definitions signature algebra program) (reserved : UseScope.ReservedNames) :
    {result : TypeOf signature} →
    ControlState signature algebra program result →
    ControlState signature algebra program result → Prop where
  | ordinary (step : CallStep table before after) (neutral : before.needsOwnershipStep = false := by rfl) :
      OwnedStep table reserved ⟨store, before⟩ ⟨store, after⟩
  | operand {bindings : RuntimeEnvironment signature algebra program context}
      {before after : Operands signature algebra program context answer}
      {outside : Stack signature algebra program answer result} :
      OwnedOperandStep bindings reserved.custody beforeStore before afterStore after →
      OwnedStep table reserved ⟨beforeStore, .code before.code bindings before.values outside⟩
        ⟨afterStore, .code after.code bindings after.values outside⟩

  | application
      {body : Code signature algebra program (parameters ++ capturedTypes) [] answer}
      {captured : RuntimeEnvironment signature algebra program capturedTypes}
      {arguments : RuntimeEnvironment signature algebra program parameters}
      {next : Code signature algebra program context (answer :: operands) rest}
      {bindings : RuntimeEnvironment signature algebra program context}
      {values : RuntimeEnvironment signature algebra program operands}
      {outside : Stack signature algebra program rest result} :
      ComputationHandoff captured use authority store.fields fields →
      OwnedStep table reserved ⟨store, .code (.callClosure (use := use) next) bindings
        (arguments.pushReverse (.cons (.closure body captured authority) values)) outside⟩
        ⟨{ store with fields := fields }, .code body (arguments.append captured) .nil (.push (.returnTo next bindings values) outside)⟩
  | resume {use : UseScope.OneShotUse}
      {next : Code signature algebra program context (body :: operands) answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {values : RuntimeEnvironment signature algebra program operands}
      {outside : Stack signature algebra program answer result} :
      resumeControl ⟨mode, effect, input, body⟩ view store value (.push (.returnTo next bindings values) outside) = some after →
      OwnedStep table reserved ⟨store, .code (.resume (mode := mode) (effect := effect) (use := use.type) next) bindings
        (.cons value (.cons (.continuation view.identity (some (view.authority, view.owner))) values)) outside⟩ after
  | successor {use : UseScope.OneShotUse}
      {next : Code signature algebra program context (answer :: operands) rest}
      {returned : Code signature algebra program (body :: context) [] answer}
      {clauses : Clauses signature algebra program effect .deep context body answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {values : RuntimeEnvironment signature algebra program operands}
      {outside : Stack signature algebra program rest result} :
      resumeControlWith view store value returned clauses bindings (.push (.returnTo next bindings values) outside) = some after →
      OwnedStep table reserved ⟨store, .code (.replaceHandler (use := use.type) effect returned clauses next) bindings
        (.cons value (.cons (.continuation view.identity (some (view.authority, view.owner))) values)) outside⟩ after
  | injection {use : UseScope.OneShotUse} {bodyUse : Use}
      {next : Code signature algebra program context (answer :: operands) rest}
      {body : Code signature algebra program capturedTypes [] input}
      {captured : RuntimeEnvironment signature algebra program capturedTypes}
      {bindings : RuntimeEnvironment signature algebra program context}
      {values : RuntimeEnvironment signature algebra program operands}
      {outside : Stack signature algebra program rest result} :
      ComputationHandoff captured bodyUse authority store.fields fields →
      injectControl ⟨mode, effect, input, answer⟩ view { store with fields := fields } ⟨capturedTypes, body, captured⟩
        (.push (.returnTo next bindings values) outside) = some after →
      OwnedStep table reserved ⟨store, .code (.inject (mode := mode) (effect := effect) (use := use.type) (useBody := bodyUse) next) bindings
        (.cons (.closure body captured authority) (.cons (.continuation view.identity (some (view.authority, view.owner))) values)) outside⟩ after
  | handled {effect : signature.Effect} {operation : signature.operation effect}
      [DecidableEq (signature.operation effect)]
      {mode : Mode} {context : List (TypeOf signature)} {body answer result : TypeOf signature}
      {returned : Code signature algebra program (body :: context) [] answer}
      {clauses : Clauses signature algebra program effect mode context body answer}
      {bindings : RuntimeEnvironment signature algebra program context}
      {payload : RuntimeValue signature algebra program (signature.payload operation)}
      {bodies : RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type)}
      {inside : Stack signature algebra program (signature.result operation) body}
      {outside : Stack signature algebra program answer result}
      {store : ControlHeap signature algebra program} {before captured after : List UseScope.Field}
      {partition : store.fields.active = before ++ captured ++ after} {clause : OwnedClause signature algebra program result} :
      select attachment inside = none →
      dispatchOwnedClause operation attachment returned clauses bindings inside payload bodies outside
        owner before captured after store partition reserved = some clause →
      OwnedStep table reserved ⟨store, .requested operation attachment payload bodies
        (inside.append (.push (.handler effect mode attachment returned clauses bindings) outside))⟩ clause.state

inductive OwnedSteps (table : Definitions signature algebra program) (reserved : UseScope.ReservedNames) :
    {result : TypeOf signature} →
    ControlState signature algebra program result → Nat →
    ControlState signature algebra program result → Prop where
  | refl : OwnedSteps table reserved state 0 state
  | cons : OwnedStep table reserved first middle → OwnedSteps table reserved middle count last → OwnedSteps table reserved first (count + 1) last

theorem OwnedSteps.single {before after : ControlState signature algebra program result}
    (step : OwnedStep table reserved before after) : OwnedSteps table reserved before 1 after := .cons step .refl

theorem OwnedSteps.trans {before middle after : ControlState signature algebra program result}
    (first : OwnedSteps table reserved before count middle) (second : OwnedSteps table reserved middle rest after) :
    OwnedSteps table reserved before (count + rest) after := by
  induction first with
  | refl => simpa using second
  | cons step tail induction => simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using OwnedSteps.cons step (induction second)

theorem OwnedOperandSteps.with_owned_store
    {bindings : RuntimeEnvironment signature algebra program context}
    {before after : Operands signature algebra program context input}
    {beforeStore afterStore : ControlHeap signature algebra program}
    {reserved : UseScope.ReservedNames}
    (steps : OwnedOperandSteps bindings reserved.custody beforeStore before count afterStore after)
    (table : Definitions signature algebra program) (outside : Stack signature algebra program input result) :
    OwnedSteps table reserved ⟨beforeStore, .code before.code bindings before.values outside⟩ count
      ⟨afterStore, .code after.code bindings after.values outside⟩ := by
  induction steps with
  | refl => exact .refl
  | cons step tail induction => exact .cons (.operand step) (induction outside)

theorem OwnedStep.preserves_ownership {before after : ControlState signature algebra program result}
    (step : OwnedStep table reserved before after)
    (valid : UseScope.ControlStore.Valid before.store) : UseScope.ControlStore.Valid after.store := by
  cases step with
  | ordinary step neutral => exact valid
  | operand step => exact step.preserves_ownership valid
  | application handoff => exact ⟨handoff.preserves_ownership valid.1, valid.2⟩
  | resume accepted => exact resume_control_preserves_ownership valid accepted
  | successor accepted => exact successor_control_preserves_ownership valid accepted
  | injection handoff accepted =>
    have law := injection_control_consumes_before_entry (accepted := accepted)
    exact (law ⟨handoff.preserves_ownership valid.1, valid.2⟩).1
  | handled nearest accepted => exact dispatch_owned_clause_preserves_ownership valid accepted

theorem OwnedSteps.preserves_ownership {before after : ControlState signature algebra program result}
    (steps : OwnedSteps table reserved before count after)
    (valid : UseScope.ControlStore.Valid before.store) : UseScope.ControlStore.Valid after.store := by
  induction steps with
  | refl => exact valid
  | cons step tail induction => exact induction (step.preserves_ownership valid)

end Target

namespace Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)} [DecidableEq (ControlShape signature)]

theorem corresponding_acceptance (matched : Option.Rel related source target) (accepted : source = some first) :
    ∃ second, target = some second ∧ related first second := by
  subst source
  cases matched with
  | some proof => exact ⟨_, rfl, proof⟩

/-- A selected operation now moves fields into a freshly named stored future
and enters its clause in the same execution state used by later resumptions.
The independent source selector prevents skipping an inner matching delimiter. -/
theorem handled_operation_corresponds
    (table : Source.Definitions signature algebra program) (reserved : UseScope.ReservedNames)
    (operation : signature.operation effect) [DecidableEq (signature.operation effect)]
    (attachment : Id .attachment)
    (returned : Source.Computation signature algebra program (body :: context) answer)
    (clauses : Source.Clauses signature algebra program effect mode context body answer)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    {sourceInside : Source.Context signature algebra program (signature.result operation) body}
    {targetInside : Target.Stack signature algebra program (signature.result operation) body}
    (inside : ContextRelated signature algebra program sourceInside targetInside)
    (payload : Source.RuntimeValue signature algebra program (signature.payload operation))
    (bodies : Source.RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type))
    {sourceOutside : Source.Context signature algebra program answer result}
    {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (owner : Owner) (before captured after : List UseScope.Field)
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (sourcePartition : sourceStore.fields.active = before ++ captured ++ after)
    (targetPartition : targetStore.fields.active = before ++ captured ++ after)
    (nearest : Source.select attachment sourceInside = none)
    (accepted : Source.dispatchOwnedClause operation attachment returned clauses bindings sourceInside payload bodies sourceOutside
      owner before captured after sourceStore sourcePartition reserved = some sourceAfter) :
    ∃ targetAfter : Target.OwnedClause signature algebra program result, ControlStateRelated sourceAfter.state targetAfter.state ∧
      Source.OwnedStep table reserved ⟨sourceStore, sourceOutside.plug (.handler effect mode attachment returned clauses bindings
        (.request operation attachment payload bodies sourceInside))⟩ sourceAfter.state ∧
      Target.OwnedSteps (definitions table) reserved ⟨targetStore, .requested operation attachment (value payload) (environment bodies)
        (targetInside.append (.push (.handler effect mode attachment (computation returned)
          (Defunctionalization.clauses clauses) (environment bindings)) targetOutside))⟩ 1 targetAfter.state := by
  have selected := selection_corresponds attachment inside
  rw [nearest] at selected
  have nearestTarget : Target.select attachment targetInside = none := by
    cases found : Target.select attachment targetInside with
    | none => rfl
    | some selectedTarget => rw [found] at selected; cases selected
  obtain ⟨targetAfter, targetAccepted, matched⟩ := corresponding_acceptance
    (owned_clause_dispatch_corresponds operation attachment returned clauses bindings inside payload bodies outside
      owner before captured after stores sourcePartition targetPartition reserved) accepted
  exact ⟨targetAfter, ⟨matched.store, matched.entry⟩, .handled nearest accepted,
    .single (.handled nearestTarget targetAccepted)⟩


/-- Operand allocations finish before authority acquisition. The continuation
and the response retain their authored order and the caller's saved context. -/
theorem compiled_owned_resumption
    (table : Source.Definitions signature algebra program) (reserved : UseScope.ReservedNames) (use : UseScope.OneShotUse)
    (continuation : Source.Expression signature algebra program context (.continuation mode use.type effect input body))
    (response : Source.Expression signature algebra program context input)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (view : UseScope.ControlView) (inputValue : Source.RuntimeValue signature algebra program input)
    {sourceStore sourceEvaluated : Source.ControlHeap signature algebra program}
    {targetStore : Target.ControlHeap signature algebra program}
    (evaluated : Source.ArgumentsEvaluation bindings reserved.custody sourceStore (.cons continuation (.cons response .nil))
      (.ok (.cons (.continuation view.identity (some (view.authority, view.owner))) (.cons inputValue .nil))) sourceEvaluated)
    (stores : ControlHeapRelated sourceStore targetStore)
    {sourceOutside : Source.Context signature algebra program body result}
    {targetOutside : Target.Stack signature algebra program body result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (accepted : Source.resumeControl ⟨mode, effect, input, body⟩ view sourceEvaluated inputValue sourceOutside = some sourceAfter) :
    ∃ targetAfter count, 0 < count ∧ ControlStateRelated sourceAfter targetAfter ∧
      Source.OwnedStep table reserved ⟨sourceStore, sourceOutside.plug (.evaluate (.resume continuation response) bindings)⟩ sourceAfter ∧
      Target.OwnedSteps (definitions table) reserved
        ⟨targetStore, .code (computation (.resume continuation response)) (environment bindings) .nil targetOutside⟩ count targetAfter := by
  obtain ⟨count, targetEvaluated, operands, evaluatedRelated⟩ := owned_two_operands_drains
    (UseScope.PackedControlRelated controlPayloadRelated) bindings reserved.custody continuation response
    (.continuation view.identity (some (view.authority, view.owner))) inputValue evaluated (.resume .ret) stores
  obtain ⟨targetAfter, targetAccepted, matched⟩ := corresponding_acceptance
    (resume_control_corresponds evaluatedRelated ⟨mode, effect, input, body⟩ view inputValue (.passthrough bindings outside)) accepted
  refine ⟨targetAfter, count + 1, by omega, matched, .resume evaluated accepted, ?_⟩
  exact (operands.with_owned_store (definitions table) targetOutside).trans (.single (.resume targetAccepted))

theorem compiled_owned_successor
    (table : Source.Definitions signature algebra program) (reserved : UseScope.ReservedNames) (use : UseScope.OneShotUse)
    (continuation : Source.Expression signature algebra program context (.continuation .shallow use.type effect input body))
    (response : Source.Expression signature algebra program context input)
    (returned : Source.Computation signature algebra program (body :: context) answer)
    (clauses : Source.Clauses signature algebra program effect .deep context body answer)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (view : UseScope.ControlView) (inputValue : Source.RuntimeValue signature algebra program input)
    {sourceStore sourceEvaluated : Source.ControlHeap signature algebra program}
    {targetStore : Target.ControlHeap signature algebra program}
    (evaluated : Source.ArgumentsEvaluation bindings reserved.custody sourceStore (.cons continuation (.cons response .nil))
      (.ok (.cons (.continuation view.identity (some (view.authority, view.owner))) (.cons inputValue .nil))) sourceEvaluated)
    (stores : ControlHeapRelated sourceStore targetStore)
    {sourceOutside : Source.Context signature algebra program answer result}
    {targetOutside : Target.Stack signature algebra program answer result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (accepted : Source.resumeControlWith view sourceEvaluated inputValue returned clauses bindings sourceOutside = some sourceAfter) :
    ∃ targetAfter count, 0 < count ∧ ControlStateRelated sourceAfter targetAfter ∧
      Source.OwnedStep table reserved ⟨sourceStore, sourceOutside.plug (.evaluate (.resumeWith effect continuation response returned clauses) bindings)⟩ sourceAfter ∧
      Target.OwnedSteps (definitions table) reserved
        ⟨targetStore, .code (computation (.resumeWith effect continuation response returned clauses)) (environment bindings) .nil targetOutside⟩ count targetAfter := by
  obtain ⟨count, targetEvaluated, operands, evaluatedRelated⟩ := owned_two_operands_drains
    (UseScope.PackedControlRelated controlPayloadRelated) bindings reserved.custody continuation response
    (.continuation view.identity (some (view.authority, view.owner))) inputValue evaluated
    (.replaceHandler effect (computation returned) (Defunctionalization.clauses clauses) .ret) stores
  obtain ⟨targetAfter, targetAccepted, matched⟩ := corresponding_acceptance
    (successor_control_corresponds evaluatedRelated view inputValue returned clauses bindings (.passthrough bindings outside)) accepted
  refine ⟨targetAfter, count + 1, by omega, matched, .successor evaluated accepted, ?_⟩
  exact (operands.with_owned_store (definitions table) targetOutside).trans (.single (.successor targetAccepted))

end Defunctionalization
end BoundaryV2.Generalized
