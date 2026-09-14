import BoundaryV2.GeneralizedStateExecution
import BoundaryV2.GeneralizedProgramObservations

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

namespace Source

/-- Finite closure of the permission-sensitive source steps. The index counts
an existing derivation; it does not limit either evaluator. -/
inductive ExecutionSteps (table : Definitions signature algebra program) :
    State signature algebra program result → Nat → State signature algebra program result → Prop where
  | refl : ExecutionSteps table state 0 state
  | cons : ExecutionStep table before middle → ExecutionSteps table middle count after →
      ExecutionSteps table before (count + 1) after

theorem ExecutionSteps.trans {before middle after : State signature algebra program result}
    (first : ExecutionSteps table before count middle)
    (second : ExecutionSteps table middle rest after) : ExecutionSteps table before (count + rest) after := by
  induction first with
  | refl => simpa using second
  | cons step tail induction =>
    simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using ExecutionSteps.cons step (induction second)

/-- The final resource state accompanies the observation. In particular a
suspended future is resumed with current resources, not its initial heap. -/
def StateObserves (table : Definitions signature algebra program)
    (before after : State signature algebra program result)
    (observation : Observation signature algebra program result) : Prop :=
  ∃ count, ExecutionSteps table before count after ∧ HeadObservation after.control.computation observation

theorem StateObserves.prepend {before middle after : State signature algebra program result}
    (steps : ExecutionSteps table before count middle)
    (observed : StateObserves table middle after observation) : StateObserves table before after observation := by
  obtain ⟨rest, tail, head⟩ := observed
  exact ⟨count + rest, steps.trans tail, head⟩

/-- Lift a neutral source reduction under its actual higher-order context.
Ownership-changing reductions must use their explicit execution constructors. -/
theorem Step.in_state_context
    {before after : Program signature algebra program input}
    (step : Step (table : Definitions signature algebra program) before after)
    (neutral : before.needsOwnershipStep = false)
    (outside : Context signature algebra program input result)
    (store : ControlHeap signature algebra program)
    (storage : Cells signature algebra (Computation signature algebra program)) (regions : List (Id .region)) :
    ExecutionStep table ⟨⟨store, outside.plug before⟩, storage, regions⟩
      ⟨⟨store, outside.plug after⟩, storage, regions⟩ :=
  .cell (.ordinary (step.in_context outside) ((outside.computation_entry_flag before).trans neutral))

/-- The finite source forwarding derivation carries the current state unchanged
through each enclosing frame, including running cleanup and authored callbacks. -/
theorem Context.forward_yield_state (table : Definitions signature algebra program)
    (outside : Context signature algebra program input result) (body : Program signature algebra program input)
    (store : ControlHeap signature algebra program)
    (storage : Cells signature algebra (Computation signature algebra program)) (regions : List (Id .region)) :
    ExecutionSteps table ⟨⟨store, outside.plug (.yielded body)⟩, storage, regions⟩ outside.length
      ⟨⟨store, .yielded (outside.plug body)⟩, storage, regions⟩ := by
  cases outside with
  | done => exact .refl
  | push frame rest =>
    exact .cons ((frame.forward_yield table body).in_state_context
      (by rw [frame.computation_entry_flag]; rfl) rest store storage regions)
      (rest.forward_yield_state table (frame.plug body) store storage regions)
termination_by outside.length
decreasing_by simp_all [Context.length]

theorem Forwards.expose_request_state
    {operation : signature.operation effect} {attachment : Id .attachment}
    {outside : Context signature algebra program input result}
    (forward : Forwards operation attachment outside)
    (table : Definitions signature algebra program)
    (payload : RuntimeValue signature algebra program (signature.payload operation))
    (bodies : RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type))
    (saved : Context signature algebra program (signature.result operation) input)
    (store : ControlHeap signature algebra program)
    (storage : Cells signature algebra (Computation signature algebra program)) (regions : List (Id .region)) :
    ExecutionSteps table ⟨⟨store, outside.plug (.request operation attachment payload bodies saved)⟩, storage, regions⟩ outside.length
      ⟨⟨store, .request operation attachment payload bodies (saved.append outside)⟩, storage, regions⟩ := by
  classical
  induction forward with
  | done => simpa only [Context.plug, Context.length, Context.append_done] using
      (ExecutionSteps.refl (table := table)
        (state := ⟨⟨store, Program.request operation attachment payload bodies saved⟩, storage, regions⟩))
  | bind next description tail induction =>
    simpa only [Context.append_associative, Context.append, Context.plug, Frame.plug, Context.length] using
      ExecutionSteps.cons (Step.in_state_context .bindRequest rfl _ store storage regions) (induction _)
  | region identity tail induction =>
    simpa only [Context.append_associative, Context.append, Context.plug, Frame.plug, Context.length] using
      ExecutionSteps.cons (Step.in_state_context .regionRequest rfl _ store storage regions) (induction _)
  | cleanupReturn identity original exit tail induction =>
    simpa only [Context.append_associative, Context.append, Context.plug, Frame.plug, Context.length] using
      ExecutionSteps.cons (Step.in_state_context .cleaningRequest rfl _ store storage regions) (induction _)
  | protection identity cleanup bindings tail induction =>
    simpa only [Context.append_associative, Context.append, Context.plug, Frame.plug, Context.length] using
      ExecutionSteps.cons (Step.in_state_context .protectionRequest rfl _ store storage regions) (induction _)
  | different effect mode identity returned clauses bindings different tail induction =>
    simpa only [Context.append_associative, Context.append, Context.plug, Frame.plug, Context.length] using
      ExecutionSteps.cons (Step.in_state_context (.handlerForward different) rfl _ store storage regions) (induction _)
  | unhandled mode returned clauses bindings absent tail induction =>
    simpa only [Context.append_associative, Context.append, Context.plug, Frame.plug, Context.length] using
      ExecutionSteps.cons (Step.in_state_context (.handlerUnhandled ((Clauses.lookup_none_iff clauses).mpr absent))
        rfl _ store storage regions) (induction _)

end Source

namespace Target

def StateObserves (table : Definitions signature algebra program)
    (before after : State signature algebra program result)
    (observation : Observation signature algebra program result) : Prop :=
  ∃ count, ExecutionSteps table before count after ∧ HeadObservation after.control.configuration observation

theorem StateObserves.prepend {before middle after : State signature algebra program result}
    (steps : ExecutionSteps table before count middle)
    (observed : StateObserves table middle after observation) : StateObserves table before after observation := by
  obtain ⟨rest, tail, head⟩ := observed
  exact ⟨count + rest, steps.trans tail, head⟩

end Target

namespace Defunctionalization

section Structural
omit [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

/-- Structural correspondence at arbitrary reduction points. `EntryRelated`
only describes entry boundaries; `ProgramRelated` also covers an executing
higher-order bind, handler, region, or running-cleanup frame. Neither relation
assumes matching observations. -/
structure ExecutionStateRelated (source : Source.State signature algebra program result)
    (target : Target.State signature algebra program result) : Prop where
  store : ControlHeapRelated source.control.store target.control.store
  cells : target.cells = Defunctionalization.cells source.cells
  regions : source.liveRegions = target.liveRegions
  computation : ProgramRelated source.control.computation .done target.control.configuration

/-- Resource correspondence is part of every observation, including failures
and suspensions. `ObservationRelated` distinguishes the four observations and
retains related scoped bodies and complete typed request futures. -/
structure StateObservationRelated
    (sourceState : Source.State signature algebra program result)
    (targetState : Target.State signature algebra program result)
    (source : Source.Observation signature algebra program result)
    (target : Target.Observation signature algebra program result) : Prop where
  store : ControlHeapRelated sourceState.control.store targetState.control.store
  cells : targetState.cells = Defunctionalization.cells sourceState.cells
  regions : sourceState.liveRegions = targetState.liveRegions
  observation : ObservationRelated source target

/-- Initialization uses the total translation and an explicit related heap.
The environment relation is the structural, order-preserving translation. -/
theorem stateful_initialization
    (body : Source.Computation signature algebra program context result)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    {sourceStore : Source.ControlHeap signature algebra program}
    {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program))
    (regions : List (Id .region)) :
    ExecutionStateRelated
      ⟨⟨sourceStore, .evaluate body bindings⟩, sourceCells, regions⟩
      ⟨⟨targetStore, .code (computation body) (environment bindings) .nil .done⟩,
        cells sourceCells, regions⟩ :=
  ⟨stores, rfl, rfl, .evaluate body bindings .done⟩

/-- Typed response entry reuses the resources at the observation boundary.
No ownership is minted merely by supplying a response value. -/
theorem stateful_response_entry
    {sourceFuture : Source.Context signature algebra program input result}
    {targetFuture : Target.Stack signature algebra program input result}
    (future : ContextRelated signature algebra program sourceFuture targetFuture)
    (response : Source.RuntimeValue signature algebra program input)
    {sourceStore : Source.ControlHeap signature algebra program}
    {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program))
    (regions : List (Id .region)) :
    ExecutionStateRelated
      ⟨⟨sourceStore, sourceFuture.plug (.returned response)⟩, sourceCells, regions⟩
      ⟨⟨targetStore, .returned (value response) targetFuture⟩, cells sourceCells, regions⟩ :=
  ⟨stores, rfl, rfl, every_request_response_remains_related future response⟩

/-- Every existing local entry correspondence supplies the execution relation
used by D, without an observation-equivalence premise. -/
theorem CellStateRelated.as_execution
    {source : Source.State signature algebra program result}
    {target : Target.State signature algebra program result}
    (related : CellStateRelated source target) : ExecutionStateRelated source target :=
  ⟨related.control.store, related.cells, related.regions, related.control.entry.as_program⟩

end Structural

/-- The administrative return frames in the structural relation execute through
the permission-sensitive machine. Their finite drain leaves resources intact. -/
theorem ProgramRelated.returned_state_drains
    (related : ProgramRelated (source : Source.Program signature algebra program input) outside target)
    (table : Target.Definitions signature algebra program)
    (returned : Source.RuntimeValue signature algebra program input) (same : source = .returned returned)
    (store : Target.ControlHeap signature algebra program)
    (storage : Cells signature algebra (fun context result => Target.Code signature algebra program context [] result))
    (regions : List (Id .region)) :
    ∃ count, Target.ExecutionSteps table ⟨⟨store, target⟩, storage, regions⟩ count
      ⟨⟨store, .returned (value returned) outside⟩, storage, regions⟩ := by
  induction related with
  | returned value future => cases same; exact ⟨0, .refl⟩
  | passthrough bindings inner induction =>
    obtain ⟨count, steps⟩ := induction returned same
    exact ⟨count + 2, steps.trans (.cons (.cell (.ordinary .caller))
      (.cons (.cell (.ordinary .returned)) .refl))⟩
  | evaluate | failed | bind | handler | region | protection | cleaning | requested | yielded => cases same

theorem ProgramRelated.failed_state_drains
    (related : ProgramRelated (source : Source.Program signature algebra program input) outside target)
    (table : Target.Definitions signature algebra program)
    (fault : algebra.Fault) (same : source = .failed fault)
    (store : Target.ControlHeap signature algebra program)
    (storage : Cells signature algebra (fun context result => Target.Code signature algebra program context [] result))
    (regions : List (Id .region)) :
    ∃ count, Target.ExecutionSteps table ⟨⟨store, target⟩, storage, regions⟩ count
      ⟨⟨store, .failed fault outside⟩, storage, regions⟩ := by
  induction related with
  | failed failure future => cases same; exact ⟨0, .refl⟩
  | passthrough bindings inner induction =>
    obtain ⟨count, steps⟩ := induction same
    exact ⟨count + 1, steps.trans (.single (.cell (.ordinary .callerFault)))⟩
  | evaluate | returned | bind | handler | region | protection | cleaning | requested | yielded => cases same

/-- The observation boundary needed by finite stateful preservation. Unlike the
ordinary observation theorem, its target derivation uses ExecutionSteps, and
the observed resource state remains related for all four observation forms. -/
theorem stateful_head_observation_preserved (table : Source.Definitions signature algebra program)
    {source : Source.State signature algebra program result}
    {target : Target.State signature algebra program result}
    (related : ExecutionStateRelated source target)
    (head : Source.HeadObservation source.control.computation observation) :
    ∃ targetFinal targetObservation,
      Target.StateObserves (definitions table) target targetFinal targetObservation ∧
      StateObservationRelated source targetFinal observation targetObservation := by
  rcases source with ⟨⟨sourceStore, sourceProgram⟩, sourceCells, sourceRegions⟩
  change Source.HeadObservation sourceProgram observation at head
  cases head with
  | returned =>
    obtain ⟨count, steps⟩ := related.computation.returned_state_drains (definitions table) _ rfl
      target.control.store target.cells target.liveRegions
    exact ⟨_, _, ⟨count, steps, .returned⟩,
      ⟨related.store, related.cells, related.regions, .returned _⟩⟩
  | failed =>
    obtain ⟨count, steps⟩ := related.computation.failed_state_drains (definitions table) _ rfl
      target.control.store target.cells target.liveRegions
    exact ⟨_, _, ⟨count, steps, .failed⟩,
      ⟨related.store, related.cells, related.regions, .failed _⟩⟩
  | yielded =>
    obtain ⟨next, configuration, future⟩ := related.computation.yielded_view _ rfl
    exact ⟨target, _, ⟨0, .refl, configuration ▸ .yielded⟩,
      ⟨related.store, related.cells, related.regions, .yielded future⟩⟩
  | requested forward =>
    obtain ⟨future, saved, configuration⟩ := related.computation.requested_view _ _ _ _ _ rfl
    simp only [Target.Stack.append_done] at configuration
    exact ⟨target, _, ⟨0, .refl, configuration ▸ .requested ((forwarding_corresponds saved).mp forward)⟩,
      ⟨related.store, related.cells, related.regions, .requested _ _ _ _ saved⟩⟩

private theorem reflect_stateful_head_in_context (table : Source.Definitions signature algebra program)
    {source : Source.Program signature algebra program input}
    {target : Target.Configuration signature algebra program result}
    {sourceOutside : Source.Context signature algebra program input result}
    {targetOutside : Target.Stack signature algebra program input result}
    (related : ProgramRelated source targetOutside target)
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (head : Target.HeadObservation target observation)
    {sourceStore : Source.ControlHeap signature algebra program}
    {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (storage : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region)) :
    ∃ sourceFinal sourceObservation,
      Source.StateObserves table ⟨⟨sourceStore, sourceOutside.plug source⟩, storage, regions⟩ sourceFinal sourceObservation ∧
      StateObservationRelated sourceFinal ⟨⟨targetStore, target⟩, cells storage, regions⟩ sourceObservation observation := by
  induction related with
  | evaluate => cases head
  | returned value future =>
    cases head
    cases outside
    exact ⟨_, _, ⟨0, .refl, .returned⟩, ⟨stores, rfl, rfl, .returned value⟩⟩
  | failed fault future =>
    cases head
    cases outside
    exact ⟨_, _, ⟨0, .refl, .failed⟩, ⟨stores, rfl, rfl, .failed fault⟩⟩
  | passthrough bindings inner induction => exact induction (.passthrough bindings outside) head
  | bind body bindings inner induction =>
    simpa only [Source.Context.plug, Source.Frame.plug, Source.Frame.bindAuthored, Source.Program.bindAuthored] using
      induction (.push (.bind body bindings) outside) head
  | handler effect mode attachment returned clauses bindings inner induction =>
    simpa only [Source.Context.plug, Source.Frame.plug] using
      induction (.push (.handler effect mode attachment returned clauses bindings) outside) head
  | region identity inner induction =>
    simpa only [Source.Context.plug, Source.Frame.plug] using induction (.push (.region identity) outside) head
  | protection identity cleanup bindings inner induction =>
    simpa only [Source.Context.plug, Source.Frame.plug] using
      induction (.push (.protection identity cleanup bindings) outside) head
  | cleaning identity original exit inner induction =>
    simpa only [Source.Context.plug, Source.Frame.plug] using
      induction (.push (.cleanupReturn identity original exit) outside) head
  | yielded inner induction =>
    cases head
    exact ⟨_, _, ⟨sourceOutside.length, sourceOutside.forward_yield_state table _ sourceStore storage regions, .yielded⟩,
      ⟨stores, rfl, rfl, .yielded (outside.close_program inner)⟩⟩
  | requested operation attachment payload bodies saved future =>
    cases head with
    | requested forward =>
      have combined := context_composition saved outside
      have sourceForward := (forwarding_corresponds combined).mpr forward
      have outerForward := sourceForward.append_right _ sourceOutside
      exact ⟨_, _, ⟨sourceOutside.length,
        outerForward.expose_request_state table payload bodies _ sourceStore storage regions, .requested sourceForward⟩,
        ⟨stores, rfl, rfl, .requested operation attachment payload bodies combined⟩⟩

/-- Reflection at an already observable target state uses finite source
forwarding, preserving current resources and every typed suspended future. -/
theorem stateful_head_observation_reflected (table : Source.Definitions signature algebra program)
    {source : Source.State signature algebra program result}
    {target : Target.State signature algebra program result}
    (related : ExecutionStateRelated source target)
    (head : Target.HeadObservation target.control.configuration observation) :
    ∃ sourceFinal sourceObservation,
      Source.StateObserves table source sourceFinal sourceObservation ∧
      StateObservationRelated sourceFinal target sourceObservation observation := by
  rcases source with ⟨⟨sourceStore, sourceProgram⟩, sourceStorage, sourceRegions⟩
  rcases target with ⟨⟨targetStore, targetConfiguration⟩, targetStorage, targetRegions⟩
  rcases related with ⟨stores, storage, regions, entry⟩
  dsimp only at storage regions entry head
  subst targetStorage
  subst targetRegions
  exact reflect_stateful_head_in_context table entry .done head stores sourceStorage sourceRegions

end Defunctionalization
end BoundaryV2.Generalized
