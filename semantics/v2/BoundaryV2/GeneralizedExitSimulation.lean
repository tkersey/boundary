import BoundaryV2.GeneralizedExitContextView
import BoundaryV2.GeneralizedExitCorrespondence
import BoundaryV2.GeneralizedStateSimulation

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}
  [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

/-- Failed operands may leave target administrative callers before the actual
protection frame. Both drains are finite, and cleanup entry adds a real step. -/
theorem failure_cleanup_preserved
    (table : Source.Definitions signature algebra program) (identity : Id .obligation)
    (cleanup : Source.Computation signature algebra program (.exit :: context) .unit)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (fault : algebra.Fault) (diagnostics : ExitInfo algebra.Fault algebra.Reason)
    (sourceStore : Source.ControlHeap signature algebra program)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    (sourceOutside : Source.Context signature algebra program input result)
    {target : Target.State signature algebra program result}
    (related : ExecutionStateRelated
      ⟨⟨sourceStore, sourceOutside.plug (.protection identity cleanup bindings (.failed fault))⟩, sourceCells, regions⟩ target) :
    ∃ count targetAfter, 0 < count ∧
      ExitComposition.CleanupFrameSteps (definitions table) (.running (.reenter target diagnostics)) count targetAfter retained ∧
      CleanupProgressRelated
        (.running (Source.beginExitCleanup identity cleanup bindings sourceStore sourceCells regions
          ⟨.failure fault, diagnostics.failures, diagnostics.cancellation⟩ sourceOutside)) targetAfter := by
  rcases target with ⟨⟨targetStore, configuration⟩, targetCells, targetRegions⟩
  rcases related with ⟨stores, storage, live, relation⟩
  dsimp only at stores storage live relation
  subst targetCells targetRegions
  obtain ⟨recovered, contexts, inner⟩ := open_program_context
    (.push (.protection identity cleanup bindings) sourceOutside) (.failed fault) relation .done
  simp only [Source.Context.append_done] at contexts
  obtain ⟨firstCount, first⟩ := inner.failed_state_drains (retained := retained)
    (definitions table) fault rfl targetStore (cells sourceCells) regions
  obtain ⟨targetFrame, targetOutside, restCount, frame, outside, rest⟩ := contexts.expose_failed_frame
    (retained := retained) (definitions table) fault targetStore (cells sourceCells) regions
      (.protection identity cleanup bindings) sourceOutside rfl
  cases frame
  have drain := ExitComposition.CleanupFrameSteps.of_execution (first.trans rest) diagnostics
  refine ⟨firstCount + restCount + 1, _, by omega, drain.trans (.cons (.begin rfl) .refl), .running ?_⟩
  exact cleanup_entry_corresponds identity cleanup bindings stores sourceCells regions _ outside


theorem returned_cleanup_preserved
    (table : Source.Definitions signature algebra program) (identity : Id .obligation)
    (original : Option (Source.RuntimeValue signature algebra program input))
    (cleaned : Source.RuntimeValue signature algebra program .unit)
    (exit diagnostics : ExitInfo algebra.Fault algebra.Reason)
    (sourceStore : Source.ControlHeap signature algebra program)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    (sourceOutside : Source.Context signature algebra program input result)
    {target : Target.State signature algebra program result}
    (related : ExecutionStateRelated
      ⟨⟨sourceStore, sourceOutside.plug (.cleaning identity original exit (.returned cleaned))⟩, sourceCells, regions⟩ target)
    (accepted : ExitComposition.finalizeCleanup original exit = some outcome) :
    ∃ count targetAfter, 0 < count ∧
      ExitComposition.CleanupFrameSteps (definitions table) (.running (.reenter target diagnostics)) count targetAfter retained ∧
      CleanupProgressRelated
        (Source.reenterCleanupResult identity .returned sourceStore sourceCells regions sourceOutside outcome).progress targetAfter := by
  rcases target with ⟨⟨targetStore, configuration⟩, targetCells, targetRegions⟩
  rcases related with ⟨stores, storage, live, relation⟩
  dsimp only at stores storage live relation
  subst targetCells targetRegions
  obtain ⟨recovered, contexts, inner⟩ := open_program_context
    (.push (.cleanupReturn identity original exit) sourceOutside) (.returned cleaned) relation .done
  simp only [Source.Context.append_done] at contexts
  obtain ⟨firstCount, first⟩ := inner.returned_state_drains (retained := retained)
    (definitions table) cleaned rfl targetStore (cells sourceCells) regions
  obtain ⟨targetFrame, targetOutside, restCount, frame, outside, rest⟩ := contexts.expose_returned_frame
    (retained := retained) (definitions table) (value cleaned) targetStore (cells sourceCells) regions
      (.cleanupReturn identity original exit) sourceOutside rfl
  cases frame
  have drain := ExitComposition.CleanupFrameSteps.of_execution (first.trans rest) diagnostics
  have finalized := cleanup_finalization_corresponds original exit accepted
  refine ⟨firstCount + restCount + 1, _, by omega, drain.trans (.cons (.finish
    (after := ExitComposition.reenterCleanupResult identity .returned targetStore (cells sourceCells) regions targetOutside
      (outcome.mapBodies (fun _ _ body => computation body))) ?_) .refl),
    (cleanup_reentry_corresponds identity .returned stores sourceCells regions outside outcome).progress⟩
  change (ExitComposition.finalizeCleanup (original.map value) exit).map _ = some _
  rw [finalized]
  rfl

theorem failed_cleanup_preserved
    (table : Source.Definitions signature algebra program) (identity : Id .obligation)
    (original : Option (Source.RuntimeValue signature algebra program input)) (fault : algebra.Fault)
    (exit diagnostics : ExitInfo algebra.Fault algebra.Reason)
    (sourceStore : Source.ControlHeap signature algebra program)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    (sourceOutside : Source.Context signature algebra program input result)
    {target : Target.State signature algebra program result}
    (related : ExecutionStateRelated
      ⟨⟨sourceStore, sourceOutside.plug (.cleaning identity original exit (.failed fault))⟩, sourceCells, regions⟩ target)
    (accepted : ExitComposition.finalizeCleanup original (exit.nestedFailure fault diagnostics.failures diagnostics.cancellation) = some outcome) :
    ∃ count targetAfter, 0 < count ∧
      ExitComposition.CleanupFrameSteps (definitions table) (.running (.reenter target diagnostics)) count targetAfter retained ∧
      CleanupProgressRelated
        (Source.reenterCleanupResult identity (.failed fault) sourceStore sourceCells regions sourceOutside outcome).progress targetAfter := by
  rcases target with ⟨⟨targetStore, configuration⟩, targetCells, targetRegions⟩
  rcases related with ⟨stores, storage, live, relation⟩
  dsimp only at stores storage live relation
  subst targetCells targetRegions
  obtain ⟨recovered, contexts, inner⟩ := open_program_context
    (.push (.cleanupReturn identity original exit) sourceOutside) (.failed fault) relation .done
  simp only [Source.Context.append_done] at contexts
  obtain ⟨firstCount, first⟩ := inner.failed_state_drains (retained := retained)
    (definitions table) fault rfl targetStore (cells sourceCells) regions
  obtain ⟨targetFrame, targetOutside, restCount, frame, outside, rest⟩ := contexts.expose_failed_frame
    (retained := retained) (definitions table) fault targetStore (cells sourceCells) regions
      (.cleanupReturn identity original exit) sourceOutside rfl
  cases frame
  have drain := ExitComposition.CleanupFrameSteps.of_execution (first.trans rest) diagnostics
  have finalized := cleanup_finalization_corresponds original (exit.nestedFailure fault diagnostics.failures diagnostics.cancellation) accepted
  refine ⟨firstCount + restCount + 1, _, by omega, drain.trans (.cons (.finish
    (after := ExitComposition.reenterCleanupResult identity (.failed fault) targetStore (cells sourceCells) regions targetOutside
      (outcome.mapBodies (fun _ _ body => computation body))) ?_) .refl),
    (cleanup_reentry_corresponds identity (.failed fault) stores sourceCells regions outside outcome).progress⟩
  change (ExitComposition.finalizeCleanup (original.map value) _).map _ = some _
  rw [finalized]
  rfl

theorem unwind_cleanup_preserved
    (table : Source.Definitions signature algebra program) (identity : Id .obligation)
    (cleanup : Source.Computation signature algebra program (.exit :: context) .unit)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    {source : Source.ExitRuntime signature algebra program} {target : ExitComposition.Runtime signature algebra program}
    (runtime : ExitRuntimeRelated source target)
    (sourceOutside : Source.Context signature algebra program input result)
    {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program (.push (.protection identity cleanup bindings) sourceOutside) targetOutside) :
    ∃ count targetAfter, 0 < count ∧
      ExitComposition.CleanupFrameSteps (definitions table) (.running (.unwind target targetOutside)) count targetAfter retained ∧
      CleanupProgressRelated
        (.running (Source.beginExitCleanup identity cleanup bindings source.store source.cells source.regions source.exit sourceOutside)) targetAfter := by
  obtain ⟨targetFrame, targetRest, count, frame, context, drain⟩ := outside.expose_unwind_frame
    (retained := retained) (definitions table) target runtime.completion
      (.protection identity cleanup bindings) sourceOutside rfl
  cases frame
  obtain ⟨sourceAfter, targetAfter, sourceStep, targetStep, related⟩ :=
    unwind_cleanup_entry_steps_correspond (retained := retained) table identity cleanup bindings runtime context
  cases sourceStep
  exact ⟨count + 1, targetAfter, by omega, drain.trans (.cons targetStep .refl), related⟩

theorem unwound_cleanup_preserved
    (table : Source.Definitions signature algebra program) (identity : Id .obligation)
    (original : Option (Source.RuntimeValue signature algebra program input)) (exit : ExitInfo algebra.Fault algebra.Reason)
    {source : Source.ExitRuntime signature algebra program} {target : ExitComposition.Runtime signature algebra program}
    (runtime : ExitRuntimeRelated source target)
    (sourceOutside : Source.Context signature algebra program input result)
    {targetOutside : Target.Stack signature algebra program .unit result}
    (outside : ContextRelated signature algebra program (.push (.cleanupReturn identity original exit) sourceOutside) targetOutside)
    (accepted : ExitComposition.finalizeCleanup original
      (match source.exit.primary with
        | .failure fault => exit.nestedFailure fault source.exit.failures source.exit.cancellation
        | _ => exit.nestedAbandon source.exit) = some outcome) :
    ∃ count targetAfter, 0 < count ∧
      ExitComposition.CleanupFrameSteps (definitions table) (.running (.unwind target targetOutside)) count targetAfter retained ∧
      CleanupProgressRelated (Source.reenterCleanupResult identity .abandoned source.store source.cells source.regions sourceOutside outcome).progress targetAfter := by
  obtain ⟨targetFrame, targetRest, count, frame, context, drain⟩ := outside.expose_unwind_frame
    (retained := retained) (definitions table) target runtime.completion
      (.cleanupReturn identity original exit) sourceOutside rfl
  cases frame
  obtain ⟨sourceAfter, targetAfter, sourceStep, targetStep, related⟩ :=
    unwound_cleanup_steps_correspond (retained := retained) table identity original exit runtime context accepted
  cases sourceStep with
  | unwound completed =>
    have same := Option.some.inj (accepted.symm.trans completed)
    cases same
    exact ⟨count + 1, targetAfter, by omega, drain.trans (.cons targetStep .refl), related⟩

/-- Every constructor of the source cleanup relation uses an existing core
simulation or a proved exit-boundary correspondence with finite target drains. -/
theorem cleanup_step_preserved (table : Source.Definitions signature algebra program)
    {source after : Source.CleanupProgress signature algebra program result}
    {target : ExitComposition.CleanupFrameProgress signature algebra program result}
    (step : Source.CleanupStep table source after retained) (related : CleanupProgressRelated source target) :
    ∃ count targetAfter, ExitComposition.CleanupFrameSteps (definitions table) target count targetAfter retained ∧
      CleanupProgressRelated after targetAfter := by
  cases step with
  | execute core =>
    cases related with
    | running matching =>
      cases matching with
      | reenter states =>
        obtain ⟨count, targetAfter, steps, joined⟩ := stateful_execution_step_simulates table core states
        exact ⟨count, _, ExitComposition.CleanupFrameSteps.of_execution steps _, .running (.reenter joined)⟩
  | beginFailure =>
    cases related with
    | running matching =>
      cases matching with
      | reenter states =>
        obtain ⟨count, targetAfter, _, steps, joined⟩ := failure_cleanup_preserved
          (retained := retained) table _ _ _ _ _ _ _ _ _ states
        exact ⟨count, targetAfter, steps, joined⟩
  | beginUnwind =>
    cases related with
    | running matching =>
      cases matching with
      | unwind runtime outside =>
        obtain ⟨count, targetAfter, _, steps, joined⟩ := unwind_cleanup_preserved
          (retained := retained) table _ _ _ runtime _ outside
        exact ⟨count, targetAfter, steps, joined⟩
  | returned accepted =>
    cases related with
    | running matching =>
      cases matching with
      | reenter states =>
        obtain ⟨count, targetAfter, _, steps, joined⟩ := returned_cleanup_preserved
          (retained := retained) table _ _ _ _ _ _ _ _ _ states accepted
        exact ⟨count, targetAfter, steps, joined⟩
  | failed accepted =>
    cases related with
    | running matching =>
      cases matching with
      | reenter states =>
        obtain ⟨count, targetAfter, _, steps, joined⟩ := failed_cleanup_preserved
          (retained := retained) table _ _ _ _ _ _ _ _ _ states accepted
        exact ⟨count, targetAfter, steps, joined⟩
  | unwound accepted =>
    cases related with
    | running matching =>
      cases matching with
      | unwind runtime outside =>
        obtain ⟨count, targetAfter, _, steps, joined⟩ := unwound_cleanup_preserved
          (retained := retained) table _ _ _ runtime _ outside accepted
        exact ⟨count, targetAfter, steps, joined⟩

theorem finite_cleanup_preserved (table : Source.Definitions signature algebra program)
    {source after : Source.CleanupProgress signature algebra program result}
    {target : ExitComposition.CleanupFrameProgress signature algebra program result}
    (steps : Source.CleanupSteps table source count after retained) (related : CleanupProgressRelated source target) :
    ∃ targetCount targetAfter, ExitComposition.CleanupFrameSteps (definitions table) target targetCount targetAfter retained ∧
      CleanupProgressRelated after targetAfter := by
  induction steps generalizing target with
  | refl => exact ⟨0, target, .refl, related⟩
  | cons step tail induction =>
    obtain ⟨firstCount, middle, first, joined⟩ := cleanup_step_preserved table step related
    obtain ⟨restCount, final, rest, last⟩ := induction joined
    exact ⟨firstCount + restCount, final, first.trans rest, last⟩


/-- This is preservation for the source cleanup rules implemented above, not
full D adequacy: value/region disposal and registered execution remain to join. -/
theorem cleanup_observation_preserved (table : Source.Definitions signature algebra program)
    {source : Source.CleanupProgress signature algebra program result}
    {target : ExitComposition.CleanupFrameProgress signature algebra program result}
    {sourceFinal : Source.State signature algebra program result}
    (related : CleanupProgressRelated source target)
    (steps : Source.CleanupSteps table source count (.running (.reenter sourceFinal diagnostics)) retained)
    (head : Source.HeadObservation sourceFinal.control.computation observation) :
    ∃ targetCount targetFinal targetObservation,
      ExitComposition.CleanupFrameSteps (definitions table) target targetCount
        (.running (.reenter targetFinal diagnostics)) retained ∧
      Target.HeadObservation targetFinal.control.configuration targetObservation ∧
      StateObservationRelated sourceFinal targetFinal observation targetObservation := by
  obtain ⟨prefixCount, middle, run, matched⟩ := finite_cleanup_preserved table steps related
  cases matched with
  | running resolution =>
    cases resolution with
    | reenter states =>
      obtain ⟨targetFinal, targetObservation, ⟨tailCount, tail, observed⟩, joined⟩ :=
        stateful_head_observation_preserved (retained := retained) table states head
      exact ⟨prefixCount + tailCount, targetFinal, targetObservation,
        run.trans (ExitComposition.CleanupFrameSteps.of_execution tail diagnostics), observed, joined⟩

end BoundaryV2.Generalized.Defunctionalization
