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

end Defunctionalization
end BoundaryV2.Generalized
