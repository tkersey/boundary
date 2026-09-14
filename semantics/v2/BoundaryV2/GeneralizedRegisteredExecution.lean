import BoundaryV2.GeneralizedRegisteredResume
import BoundaryV2.GeneralizedStateObservations

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
      ArgumentsEvaluation bindings (arena.cells.reservations.withSupport (retainedSupport registry arena)).custody store (.cons continuation (.cons response .nil))
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
      ArgumentsEvaluation bindings (arena.cells.reservations.withSupport (retainedSupport registry arena)).custody store (.cons continuation (.cons injected .nil))
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
      ArgumentsEvaluation bindings (arena.cells.reservations.withSupport (retainedSupport registry arena)).custody store (.cons continuation (.cons response .nil))
        (.ok (.cons (.continuation identity none) (.cons value .nil))) evaluated →
      Runtime.successor identity
        ⟨⟨evaluated, outside.plug (.evaluate (.resumeWith effect continuation response returned clauses) bindings)⟩, arena, regions, registry⟩
        value returned clauses bindings outside (callSupport table bindings outside evaluated) = some after →
      ResumeEntry table
        ⟨⟨store, outside.plug (.evaluate (.resumeWith effect continuation response returned clauses) bindings)⟩, arena, regions, registry⟩ after

/-- These are embeddings of the existing core, registry, and freeze operations.
Clone admission uses a description of the actual heap; callback equality alone
cannot supply that description's authored capture metadata. -/
inductive Step (table : Definitions signature algebra program) :
    Runtime signature algebra program result → Runtime signature algebra program result → Prop where
  | core : Source.ExecutionStep table before.state state before.executionSupport → Step table before (before.withState state)
  | resume : ResumeEntry table before after → Step table before after
  | clone {use : UseScope.OneShotUse}
      {expression : Expression signature algebra program context (.continuation mode use.type effect input answer)}
      {bindings : RuntimeEnvironment signature algebra program context}
      {outside : Context signature algebra program (.continuation mode .multi effect input answer) result}
      {before : Runtime signature algebra program result}
      {store evaluated : DescribedHeap signature algebra program}
      {frozen : Frozen signature algebra program ⟨mode, effect, input, answer⟩} :
      before.control.computation = outside.plug (.evaluate (.clone expression) bindings) →
      sourceHeap store = before.control.store →
      ExpressionEvaluation bindings (before.arena.cells.reservations.withSupport before.executionSupport).custody store expression
        (.ok (.continuation view.identity (some (view.authority, view.owner)))) evaluated →
      freezeInto ⟨mode, effect, input, answer⟩ view evaluated before.arena partition before.registry = some (frozen, registered) →
      Step table before
        ⟨⟨sourceHeap frozen.store, outside.plug (.returned frozen.value)⟩, frozen.arena,
          before.regions.filter (fun region => !partition.regions.contains region), registered⟩

inductive Steps (table : Definitions signature algebra program) :
    Runtime signature algebra program result → Nat → Runtime signature algebra program result → Prop where
  | refl : Steps table state 0 state
  | cons : Step table before middle → Steps table middle count after → Steps table before (count + 1) after

def Observes (table : Definitions signature algebra program) (before after : Runtime signature algebra program result)
    (observation : Source.Observation signature algebra program result) : Prop :=
  ∃ count, Steps table before count after ∧ Source.HeadObservation after.control.computation observation


/-- Lift a finite sequence of the existing state rules. Retained support is
stable under writeback, so each successor is usable by the next operation. -/
theorem Steps.from_core (runtime : Runtime signature algebra program result)
    {before after : Source.State signature algebra program result}
    (steps : Source.ExecutionSteps (retained := runtime.executionSupport) table before count after) :
    Steps table (runtime.withState before) count (runtime.withState after) := by
  induction count generalizing before after with
  | zero => cases steps; exact .refl
  | succ count induction =>
    cases steps with
    | cons step tail => exact .cons (.core step) (induction tail)

theorem Steps.trans {before middle after : Runtime signature algebra program result}
    (first : Steps table before count middle) (second : Steps table middle rest after) :
    Steps table before (count + rest) after := by
  induction first with
  | refl => simpa using second
  | cons step tail induction =>
    simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using Steps.cons step (induction second)

theorem Observes.prepend {before middle after : Runtime signature algebra program result}
    (steps : Steps table before count middle) (observed : Observes table middle after observation) :
    Observes table before after observation := by
  obtain ⟨rest, tail, head⟩ := observed
  exact ⟨count + rest, steps.trans tail, head⟩

end Source.Multi

theorem Source.Step.in_registered_context
    {table : Source.Definitions signature algebra program}
    {before after : Source.Program signature algebra program input}
    (step : Source.Step table before after) (neutral : before.needsOwnershipStep = false)
    (outside : Source.Context signature algebra program input result)
    (store : Source.ControlHeap signature algebra program)
    (arena : Source.Multi.Arena signature algebra program) (regions : List (Id .region))
    (registry : Source.Multi.Registry signature algebra program) :
    Source.Multi.Step table ⟨⟨store, outside.plug before⟩, arena, regions, registry⟩
      ⟨⟨store, outside.plug after⟩, arena, regions, registry⟩ :=
  Source.Multi.Step.core (before := ⟨⟨store, outside.plug before⟩, arena, regions, registry⟩)
    (state := ⟨⟨store, outside.plug after⟩, arena.cells, regions⟩)
    (step.in_state_context (retained := Source.Multi.retainedSupport registry arena) neutral outside store arena.cells regions)

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


inductive Step (table : Definitions signature algebra program) :
    Runtime signature algebra program result → Runtime signature algebra program result → Prop where
  | core : Target.ExecutionStep table before.state state before.executionSupport → Step table before (before.withState state)
  | resume : ResumeEntry table before after → Step table before after
  | clone {use : UseScope.OneShotUse}
      {next : Code signature algebra program context (.continuation mode .multi effect input answer :: operands) resultType}
      {bindings : RuntimeEnvironment signature algebra program context}
      {values : RuntimeEnvironment signature algebra program operands}
      {outside : Stack signature algebra program resultType result}
      {before : Runtime signature algebra program result}
      {frozen : Frozen signature algebra program ⟨mode, effect, input, answer⟩} :
      before.control.configuration = .code (.clone (mode := mode) (effect := effect) (use := use.type) next) bindings
        (.cons (.continuation view.identity (some (view.authority, view.owner))) values) outside →
      freezeInto ⟨mode, effect, input, answer⟩ view before.control.store before.arena partition before.registry = some (frozen, registered) →
      Step table before
        ⟨⟨frozen.store, .code next bindings (.cons frozen.value values) outside⟩, frozen.arena,
          before.regions.filter (fun region => !partition.regions.contains region), registered⟩

inductive Steps (table : Definitions signature algebra program) :
    Runtime signature algebra program result → Nat → Runtime signature algebra program result → Prop where
  | refl : Steps table state 0 state
  | cons : Step table before middle → Steps table middle count after → Steps table before (count + 1) after

def Observes (table : Definitions signature algebra program) (before after : Runtime signature algebra program result)
    (observation : Target.Observation signature algebra program result) : Prop :=
  ∃ count, Steps table before count after ∧ Target.HeadObservation after.control.configuration observation


/-- Operand prefixes run through the actual core execution rule and write each
successor into the same registry runtime before registered entry. -/
theorem Steps.prepend_operands
    {bindings : RuntimeEnvironment signature algebra program context}
    {before after : Operands signature algebra program context answer}
    {outside : Stack signature algebra program answer result} {arena : Arena signature algebra program}
    (operands : OwnedOperandSteps bindings (arena.cells.reservations.withSupport (retainedSupport registry arena)).custody
      store before count changed after)
    (entry : Step table ⟨⟨changed, .code after.code bindings after.values outside⟩, arena, regions, registry⟩ last) :
    Steps table ⟨⟨store, .code before.code bindings before.values outside⟩, arena, regions, registry⟩ (count + 1) last := by
  induction operands with
  | refl => exact .cons entry .refl
  | cons first rest induction => exact .cons (.core (.control (.operand first))) (induction entry)


/-- Lift a finite sequence of the existing state rules. Retained support is
stable under writeback, so each successor is usable by the next operation. -/
theorem Steps.from_core (runtime : Runtime signature algebra program result)
    {before after : Target.State signature algebra program result}
    (steps : Target.ExecutionSteps (retained := runtime.executionSupport) table before count after) :
    Steps table (runtime.withState before) count (runtime.withState after) := by
  induction count generalizing before after with
  | zero => cases steps; exact .refl
  | succ count induction =>
    cases steps with
    | cons step tail => exact .cons (.core step) (induction tail)

theorem Steps.trans {before middle after : Runtime signature algebra program result}
    (first : Steps table before count middle) (second : Steps table middle rest after) :
    Steps table before (count + rest) after := by
  induction first with
  | refl => simpa using second
  | cons step tail induction =>
    simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using Steps.cons step (induction second)

end Target.Multi
end BoundaryV2.Generalized
