import BoundaryV2.GeneralizedStateSimulation
import BoundaryV2.GeneralizedMultiControlEntry
import BoundaryV2.GeneralizedFreezeExecution

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

/-- The existing finite core proof applies inside the actual registry runtime.
Each target successor uses the same retained support and current arena. -/
theorem registered_core_execution_preserved
    (table : Source.Definitions signature algebra program)
    {source : Source.Multi.Runtime signature algebra program result}
    {target : Target.Multi.Runtime signature algebra program result}
    {after : Source.State signature algebra program result}
    (related : MultiRuntimeRelated source target)
    (steps : Source.ExecutionSteps (retained := source.executionSupport) table source.state count after) :
    ∃ targetCount targetAfter,
      Target.Multi.Steps (definitions table) target targetCount targetAfter ∧
      MultiRuntimeRelated (source.withState after) targetAfter := by
  obtain ⟨targetCount, targetAfter, executed, matching⟩ :=
    finite_stateful_execution_preserved table steps related.as_state
  rw [← execution_support_corresponds related.toMultiDataRelated] at executed
  refine ⟨targetCount, target.withState targetAfter, ?_, related.toMultiDataRelated.writeback matching⟩
  exact Target.Multi.Steps.from_core target executed

omit [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)] in
/-- Recover the ordinary caller through the existing structural relation while
retaining the mapped registry and complete current arena. -/
theorem MultiRuntimeRelated.evaluation_view
    {body : Source.Computation signature algebra program context input}
    {bindings : Source.RuntimeEnvironment signature algebra program context}
    {sourceOutside : Source.Context signature algebra program input result}
    {sourceStore : Source.ControlHeap signature algebra program}
    {arena : Source.Multi.Arena signature algebra program} {regions : List (Id .region)}
    {registry : Source.Multi.Registry signature algebra program}
    {target : Target.Multi.Runtime signature algebra program result}
    (related : MultiRuntimeRelated
      ⟨⟨sourceStore, sourceOutside.plug (.evaluate body bindings)⟩, arena, regions, registry⟩ target) :
    ∃ targetOutside, ContextRelated signature algebra program sourceOutside targetOutside ∧
      target = ⟨⟨target.control.store, .code (Defunctionalization.computation body) (environment bindings) .nil targetOutside⟩,
        templateArena arena, regions, templateRegistry registry⟩ := by
  obtain ⟨targetOutside, outside, atState⟩ := related.as_state.evaluation_view body bindings sourceOutside
  refine ⟨targetOutside, outside, ?_⟩
  have atRuntime := congrArg target.withState atState
  change target = _ at atRuntime
  dsimp only [Target.Multi.Runtime.withState, Target.Multi.Runtime.state] at atRuntime
  rw [related.arena, related.registry] at atRuntime
  exact atRuntime

/-- All three registered entries compose with arbitrary related callers. Their
local correspondence proves each successor; it is not assumed by this law. -/
theorem registered_resume_execution_preserved
    (table : Source.Definitions signature algebra program)
    {source after : Source.Multi.Runtime signature algebra program result}
    {target : Target.Multi.Runtime signature algebra program result}
    (step : Source.Multi.ResumeEntry table source after)
    (related : MultiRuntimeRelated source target) :
    ∃ count targetAfter, Target.Multi.Steps (definitions table) target count targetAfter ∧
      MultiRuntimeRelated after targetAfter := by
  cases step with
  | enter operands accepted =>
    obtain ⟨targetOutside, outside, atTarget⟩ := related.evaluation_view
    obtain ⟨_, targetAfter, count, _, matching, executed⟩ :=
      compiled_multi_resumption table _ _ _ _ _ _ _ _ operands related.store outside accepted
    exact ⟨count, targetAfter, atTarget ▸ executed, matching⟩
  | injection operands handoff accepted =>
    obtain ⟨targetOutside, outside, atTarget⟩ := related.evaluation_view
    obtain ⟨_, targetAfter, count, _, matching, executed⟩ :=
      compiled_multi_injection table _ _ _ _ _ _ _ _ _ _ operands related.store handoff outside accepted
    exact ⟨count, targetAfter, atTarget ▸ executed, matching⟩
  | successor operands accepted =>
    obtain ⟨targetOutside, outside, atTarget⟩ := related.evaluation_view
    obtain ⟨_, targetAfter, count, _, matching, executed⟩ :=
      compiled_multi_successor table _ _ _ _ _ _ _ _ _ _ operands related.store outside accepted
    exact ⟨count, targetAfter, atTarget ▸ executed, matching⟩

/-- Every admitted registered source step has a finite target execution. The
clone case uses its supplied authored metadata and the actual related heap. -/
theorem registered_execution_step_preserved
    (table : Source.Definitions signature algebra program)
    {source after : Source.Multi.Runtime signature algebra program result}
    {target : Target.Multi.Runtime signature algebra program result}
    (step : Source.Multi.Step table source after) (related : MultiRuntimeRelated source target) :
    ∃ count targetAfter, Target.Multi.Steps (definitions table) target count targetAfter ∧
      MultiRuntimeRelated after targetAfter := by
  cases step with
  | core step => exact registered_core_execution_preserved table related (.cons step .refl)
  | resume step => exact registered_resume_execution_preserved table step related
  | clone atSource heap operands accepted =>
    have stores := related.store
    rw [← heap] at stores
    have programRelated := related.computation
    rw [atSource] at programRelated
    have paired : MultiRuntimeRelated (⟨⟨_, _⟩, _, _, _⟩ : Source.Multi.Runtime signature algebra program result) target :=
      ⟨⟨stores, related.arena, related.regions, related.registry⟩, programRelated⟩
    obtain ⟨targetOutside, outside, atTarget⟩ := paired.evaluation_view
    obtain ⟨targetAfter, count, _, matching, executed⟩ := related_registered_clone_execution table _ _ _ _ _ _
      ((described_heap_related_iff _ _).mpr stores) _ _ _ _ _ operands _ accepted outside
    exact ⟨count, targetAfter, atTarget ▸ executed, matching⟩

theorem finite_registered_execution_preserved
    (table : Source.Definitions signature algebra program)
    {source after : Source.Multi.Runtime signature algebra program result}
    {target : Target.Multi.Runtime signature algebra program result}
    (steps : Source.Multi.Steps table source sourceCount after) (related : MultiRuntimeRelated source target) :
    ∃ count targetAfter, Target.Multi.Steps (definitions table) target count targetAfter ∧
      MultiRuntimeRelated after targetAfter := by
  induction steps generalizing target with
  | refl => exact ⟨0, target, .refl, related⟩
  | cons step tail induction =>
    obtain ⟨firstCount, middle, first, middleRelated⟩ := registered_execution_step_preserved table step related
    obtain ⟨restCount, final, rest, finalRelated⟩ := induction middleRelated
    exact ⟨firstCount + restCount, final, first.trans rest, finalRelated⟩

theorem registered_head_observation_preserved
    (table : Source.Definitions signature algebra program)
    {source : Source.Multi.Runtime signature algebra program result}
    {target : Target.Multi.Runtime signature algebra program result}
    (related : MultiRuntimeRelated source target)
    (head : Source.HeadObservation source.control.computation observation) :
    ∃ targetAfter targetObservation,
      Target.Multi.Observes (definitions table) target targetAfter targetObservation ∧
      MultiDataRelated source targetAfter ∧
      StateObservationRelated source.state targetAfter.state observation targetObservation := by
  obtain ⟨after, targetObservation, ⟨count, steps, observed⟩, matching⟩ :=
    stateful_head_observation_preserved (retained := target.executionSupport) table related.as_state head
  refine ⟨target.withState after, targetObservation,
    ⟨count, Target.Multi.Steps.from_core target steps, observed⟩,
    ⟨matching.store, ?_, matching.regions.symm, related.registry⟩, matching⟩
  change { target.arena with cells := after.cells } = templateArena source.arena
  rw [related.arena, matching.cells]
  rfl

/-- D's registered preservation direction, over arbitrary finite source
derivations and all four observations, including related scoped bodies/futures. -/
theorem registered_observation_preserved
    (table : Source.Definitions signature algebra program)
    {source final : Source.Multi.Runtime signature algebra program result}
    {target : Target.Multi.Runtime signature algebra program result}
    (related : MultiRuntimeRelated source target)
    (observed : Source.Multi.Observes table source final observation) :
    ∃ targetFinal targetObservation,
      Target.Multi.Observes (definitions table) target targetFinal targetObservation ∧
      MultiDataRelated final targetFinal ∧
      StateObservationRelated final.state targetFinal.state observation targetObservation := by
  obtain ⟨sourceCount, sourceSteps, sourceHead⟩ := observed
  obtain ⟨count, after, executed, matching⟩ := finite_registered_execution_preserved table sourceSteps related
  obtain ⟨targetFinal, targetObservation, ⟨rest, following, head⟩, data, observations⟩ :=
    registered_head_observation_preserved table matching sourceHead
  exact ⟨targetFinal, targetObservation, ⟨count + rest, executed.trans following, head⟩, data, observations⟩

end BoundaryV2.Generalized.Defunctionalization
