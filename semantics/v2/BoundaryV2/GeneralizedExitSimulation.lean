import BoundaryV2.GeneralizedExitContextView
import BoundaryV2.GeneralizedExitCorrespondence
import BoundaryV2.GeneralizedSourceRegionCorrespondence
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
  obtain ⟨targetAfter, _, targetStep, related⟩ :=
    unwind_cleanup_entry_steps_correspond (retained := retained) table identity cleanup bindings runtime context
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
  obtain ⟨targetAfter, _, targetStep, related⟩ :=
    unwound_cleanup_steps_correspond (retained := retained) table identity original exit runtime context accepted
  exact ⟨count + 1, targetAfter, by omega, drain.trans (.cons targetStep .refl), related⟩

private abbrev CleanupSimulation (table : Source.Definitions signature algebra program)
    {result} (source after : Source.CleanupProgress signature algebra program result) retained
    (_ : Source.CleanupStep table source after retained) : Prop :=
  ∀ {target}, CleanupProgressRelated source target →
    ∃ count targetAfter, ExitComposition.CleanupFrameSteps (definitions table) target count targetAfter retained ∧ CleanupProgressRelated after targetAfter

private abbrev ValueSimulation (table : Source.Definitions signature algebra program)
    (source after : Source.ValueDisposal signature algebra program) retained
    (_ : Source.ValueDisposalStep table source after retained) : Prop :=
  ∀ {target}, ValueDisposalRelated source target →
    ∃ count targetAfter, ExitComposition.ValueDisposalSteps (definitions table) target count targetAfter retained ∧ ValueDisposalRelated after targetAfter

private abbrev ControlSimulation (table : Source.Definitions signature algebra program)
    {answer} (source after : Source.ControlProgress signature algebra program answer) retained
    (_ : Source.ControlProgressStep table source after retained) : Prop :=
  ∀ {target}, ControlProgressRelated source target →
    ∃ count targetAfter, ExitComposition.ControlProgressSteps (definitions table) target count targetAfter retained ∧ ControlProgressRelated after targetAfter

private abbrev RegionSimulation (table : Source.Definitions signature algebra program)
    {result} (source after : Source.RegionDisposal signature algebra program result) retained
    (_ : Source.RegionDisposalStep table source after retained) : Prop :=
  ∀ {target}, RegionDisposalRelated source target →
    ∃ count targetAfter, ExitComposition.RegionDisposalSteps (definitions table) target count targetAfter retained ∧ RegionDisposalRelated after targetAfter

/-- Every constructor of the source cleanup relation uses an existing core
simulation or a proved exit-boundary correspondence with finite target drains. -/
private theorem cleanup_step_preserved_case (table : Source.Definitions signature algebra program)
    {source after : Source.CleanupProgress signature algebra program result}
    {target : ExitComposition.CleanupFrameProgress signature algebra program result}
    (step : Source.CleanupStep table source after retained)
    (below : Source.CleanupStep.below (motive_1 := CleanupSimulation table) (motive_2 := ValueSimulation table)
      (motive_3 := ControlSimulation table) (motive_4 := RegionSimulation table) step) (related : CleanupProgressRelated source target) :
    ∃ count targetAfter, ExitComposition.CleanupFrameSteps (definitions table) target count targetAfter retained ∧
      CleanupProgressRelated after targetAfter := by
  cases below with
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
  | unwindBind =>
    cases related with
    | running matching =>
      cases matching with
      | unwind runtime outside =>
        obtain ⟨targetFrame, targetRest, count, frame, context, drain⟩ := outside.expose_unwind_frame
          (retained := retained) (definitions table) _ runtime.completion _ _ rfl
        cases frame
        refine ⟨count + 1, _, drain.trans (.cons (.unwind ?_) .refl), .running (.unwind runtime context)⟩
        simp only [ExitComposition.advanceUnwindResolution, ExitComposition.Resolution.cleanupFinished,
          runtime.completion, Bool.not_true, Bool.false_eq_true, ↓reduceIte]
  | unwindHandler =>
    cases related with
    | running matching =>
      cases matching with
      | unwind runtime outside =>
        obtain ⟨targetFrame, targetRest, count, frame, context, drain⟩ := outside.expose_unwind_frame
          (retained := retained) (definitions table) _ runtime.completion _ _ rfl
        cases frame
        refine ⟨count + 1, _, drain.trans (.cons (.unwind ?_) .refl), .running (.unwind runtime context)⟩
        simp only [ExitComposition.advanceUnwindResolution, ExitComposition.Resolution.cleanupFinished,
          runtime.completion, Bool.not_true, Bool.false_eq_true, ↓reduceIte]
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
  | enterValues =>
    cases related with
    | disposing matched =>
      cases matched with
      | same original runtime outside =>
        refine ⟨1, _, .cons (.enterValues runtime.completion) .refl, ?_⟩
        simpa only [runtime.identity, Source.ValueDisposal.start, ExitComposition.ValueDisposal.start, disposalValues, List.map_cons, List.map_nil] using CleanupProgressRelated.values outside (ValueDisposalRelated.ready [⟨_, original⟩] runtime)
  | values step childBelow simulate =>
    cases related with
    | values outside values =>
      obtain ⟨count, targetAfter, run, joined⟩ := simulate values
      rw [← context_reference_support outside] at run
      exact ⟨count, _, ExitComposition.CleanupFrameSteps.of_values _ _ _ run, .values outside joined⟩
  | finishValues finished =>
    cases related with
    | values outside values =>
      obtain ⟨runtime, targetFinished, matching⟩ := finished_value_disposal_corresponds values finished
      exact ⟨1, _, .cons (.finishValues targetFinished) .refl, finished_values_reentry_corresponds _ _ matching outside⟩
  | cancel accepted =>
    cases related with
    | running matching =>
      obtain ⟨targetAfter, cancelled, joined⟩ := matching.cancel_preserved accepted
      exact ⟨1, _, .cons (.cancel cancelled) .refl, .running joined⟩
  | parkYield =>
    cases related with
    | running matching =>
      cases matching with
      | reenter states =>
        rename_i targetState
        rcases targetState with ⟨⟨store, configuration⟩, cells, regions⟩
        obtain ⟨future, same, computation⟩ := states.computation.yielded_view _ rfl
        change configuration = .yielded future at same
        subst configuration
        exact ⟨1, _, .cons .parkYield .refl, .parked (.reenter states)⟩
  | continueYield =>
    cases related with
    | parked matching =>
      cases matching with
      | reenter states =>
        rename_i targetState
        rcases targetState with ⟨⟨store, configuration⟩, cells, regions⟩
        obtain ⟨future, same, computation⟩ := states.computation.yielded_view _ rfl
        change configuration = .yielded future at same
        subst configuration
        exact ⟨1, _, .cons .continueYield .refl,
          .running (.reenter ⟨states.store, states.cells, states.regions, computation⟩)⟩
  | cancelParked accepted =>
    cases related with
    | parked matching =>
      obtain ⟨targetAfter, cancelled, joined⟩ := matching.cancel_preserved accepted
      exact ⟨1, _, .cons (.cancelParked cancelled) .refl, .parked joined⟩
  | captureYield =>
    cases related with
    | running matching =>
      cases matching with
      | reenter states =>
        rename_i targetState
        rcases targetState with ⟨⟨store, configuration⟩, cells, regions⟩
        obtain ⟨future, same, computation⟩ := states.computation.yielded_view _ rfl
        change configuration = .yielded future at same
        subst configuration
        exact ⟨1, _, .cons .captureYield .refl, .captured (.reenter states)⟩
  | reattach =>
    cases related with
    | captured matching => exact ⟨1, _, .cons .reattach .refl, .running matching⟩
  | cancelCaptured accepted =>
    cases related with
    | captured matching =>
      obtain ⟨targetAfter, cancelled, joined⟩ := matching.cancel_preserved accepted
      exact ⟨1, _, .cons (.cancelCaptured cancelled) .refl, .captured joined⟩
  | enterRegion accepted =>
    cases related with
    | running matching =>
      obtain ⟨targetAfter, admitted, joined⟩ := option_related_some (RegionDisposalRelated.begin matching) accepted
      exact ⟨1, _, .cons (.enterRegion admitted) .refl, .region joined⟩
  | region step childBelow simulate =>
    cases related with
    | region matching =>
      obtain ⟨count, targetAfter, run, joined⟩ := simulate matching
      exact ⟨count, _, ExitComposition.CleanupFrameSteps.of_region run, .region joined⟩
  | finishRegion accepted =>
    cases related with
    | region matching =>
      obtain ⟨targetAfter, admitted, joined⟩ := option_related_some (matching.finish _) accepted
      exact ⟨1, _, .cons (.finishRegion admitted) .refl, .running joined⟩


private theorem value_disposal_step_preserved_case (table : Source.Definitions signature algebra program)
    {source after : Source.ValueDisposal signature algebra program}
    {target : ExitComposition.ValueDisposal signature algebra program}
    (step : Source.ValueDisposalStep table source after retained)
    (below : Source.ValueDisposalStep.below (motive_1 := CleanupSimulation table) (motive_2 := ValueSimulation table)
      (motive_3 := ControlSimulation table) (motive_4 := RegionSimulation table) step) (related : ValueDisposalRelated source target) :
    ∃ count targetAfter, ExitComposition.ValueDisposalSteps (definitions table) target count targetAfter retained ∧
      ValueDisposalRelated after targetAfter := by
  cases below with
  | stale inactive =>
    cases related with
    | ready pending runtime =>
      refine ⟨1, _, .cons (.stale ?_) .refl, .ready _ runtime⟩
      rw [← runtime.store.fields]
      exact (Value.active_root_check_commutes (fun _ _ body => computation body) _ _).trans inactive
  | pair => cases related with | ready pending runtime => exact ⟨1, _, .cons .pair .refl, .ready _ runtime⟩
  | left => cases related with | ready pending runtime => exact ⟨1, _, .cons .left .refl, .ready _ runtime⟩
  | right => cases related with | ready pending runtime => exact ⟨1, _, .cons .right .refl, .ready _ runtime⟩
  | datumPair => cases related with | ready pending runtime => exact ⟨1, _, .cons .datumPair .refl, .ready _ runtime⟩
  | datumLeft => cases related with | ready pending runtime => exact ⟨1, _, .cons .datumLeft .refl, .ready _ runtime⟩
  | datumRight => cases related with | ready pending runtime => exact ⟨1, _, .cons .datumRight .refl, .ready _ runtime⟩
  | package handoff =>
    cases related with
    | ready pending runtime =>
      have targetHandoff := handoff.map (fun _ _ body => computation body)
      rw [runtime.store.fields] at targetHandoff
      exact ⟨1, _, .cons (.package targetHandoff) .refl, .ready _ (runtime.with_fields _)⟩
  | @closure parameters capturedTypes result captured use authority fields sourceRuntime rest held body handoff =>
    cases related with
    | ready pending runtime =>
      have targetHandoff := handoff.map (fun _ _ body => computation body)
      rw [runtime.store.fields] at targetHandoff
      refine ⟨1, _, .cons (.closure targetHandoff) .refl, ?_⟩
      have joined := ValueDisposalRelated.ready (captured.disposalValues ++ rest) (runtime.with_fields fields)
      rw [disposal_values_append, disposal_values_environment] at joined
      exact joined
  | @resource name token owner active sourceRuntime identity rest held grant =>
    cases related with
    | ready pending runtime =>
      have targetGrant := grant
      rw [runtime.store.fields] at targetGrant
      refine ⟨1, _, .cons (.resource targetGrant) .refl, ?_⟩
      refine ValueDisposalRelated.ready rest ?_
      exact { runtime with store := { runtime.store with fields := by simp only [runtime.store.fields] } }
  | @enterControl mode use effect input answer identity authority owner sourceAcquired sourceRuntime rest held admitted =>
    rcases sourceAcquired with ⟨sourceStore, sourceFuture⟩
    cases related with
    | ready pending runtime =>
      rename_i targetRuntime
      obtain ⟨acquired, accepted, matching⟩ := corresponding_acceptance
        (UseScope.dispose_owned_corresponds (UseScope.PackedControlRelated controlPayloadRelated) runtime.store _) admitted
      rcases acquired with ⟨targetStore, targetFuture⟩
      rcases matching with ⟨stores, matchingFuture⟩
      cases matchingFuture with
      | same future =>
        refine ⟨1, _, .cons (.enterControl accepted) .refl, ?_⟩
        have resources : ExitRuntimeRelated
            ⟨sourceRuntime.id, .abandoned, sourceStore, sourceRuntime.cells, sourceRuntime.regions, sourceRuntime.exit⟩
            ⟨targetRuntime.id, .finished .abandoned, targetStore, targetRuntime.cells, targetRuntime.liveRegions, targetRuntime.exit⟩ :=
          ⟨runtime.identity, rfl, stores, runtime.cells, runtime.regions, runtime.exit⟩
        simpa only [Source.ControlProgress.seeking, ExitComposition.ControlProgress.seeking, runtime.identity, disposalValues] using
          ValueDisposalRelated.control _ (ControlProgressRelated.frames (CleanupProgressRelated.running
            (ExitResolutionRelated.unwind resources future.future)))
  | control step childBelow simulate =>
    cases related with
    | control pending matching =>
      obtain ⟨count, targetAfter, run, joined⟩ := simulate matching
      rw [← disposal_values_references] at run
      exact ⟨count, _, ExitComposition.ValueDisposalSteps.of_control _ run, .control _ joined⟩
  | finishControl =>
    cases related with
    | control pending matching =>
      cases matching with
      | complete runtime => exact ⟨1, _, .cons .finishControl .refl, .ready _ runtime⟩


private theorem control_progress_step_preserved_case (table : Source.Definitions signature algebra program)
    {source after : Source.ControlProgress signature algebra program answer}
    {target : ExitComposition.ControlProgress signature algebra program answer}
    (step : Source.ControlProgressStep table source after retained)
    (below : Source.ControlProgressStep.below (motive_1 := CleanupSimulation table) (motive_2 := ValueSimulation table)
      (motive_3 := ControlSimulation table) (motive_4 := RegionSimulation table) step) (related : ControlProgressRelated source target) :
    ∃ count targetAfter, ExitComposition.ControlProgressSteps (definitions table) target count targetAfter retained ∧
      ControlProgressRelated after targetAfter := by
  cases below with
  | frames step childBelow simulate =>
    cases related with
    | frames matching =>
      obtain ⟨count, targetAfter, run, joined⟩ := simulate matching
      exact ⟨count, _, ExitComposition.ControlProgressSteps.of_frames _ run, .frames joined⟩
  | unwindDone =>
    cases related with
    | frames matching =>
      cases matching with
      | running resolution =>
        cases resolution with
        | unwind runtime outside =>
          obtain ⟨count, run⟩ := outside.unwind_done_steps (retained := retained) (definitions table) _ runtime.completion rfl
          refine ⟨count + 1, _, (ExitComposition.ControlProgressSteps.of_frames _ run).trans
            (.cons (.finishFrames ?_) .refl), .complete runtime⟩
          unfold ExitComposition.ControlProgress.finishFrames ExitComposition.ControlProgress.terminal
          simp only [ExitComposition.Resolution.cleanupFinished, runtime.completion, Bool.not_true, Bool.false_eq_true, ↓reduceIte, Option.map_some]
  | returned =>
    cases related with
    | frames matching =>
      cases matching with
      | running resolution =>
        cases resolution with
        | reenter states =>
          rename_i targetState
          obtain ⟨count, run⟩ := states.computation.returned_state_drains (retained := retained) (definitions table) _ rfl
            targetState.control.store targetState.cells targetState.liveRegions
          exact ⟨count + 1, _, (ExitComposition.ControlProgressSteps.of_frames _
            (ExitComposition.CleanupFrameSteps.of_execution run _)).trans (.cons (.finishFrames rfl) .refl),
            .returnedValue (.ready _ ⟨rfl, rfl, states.store, states.cells, states.regions.symm, rfl⟩)⟩
  | failed =>
    cases related with
    | frames matching =>
      cases matching with
      | running resolution =>
        cases resolution with
        | reenter states =>
          rename_i targetState
          obtain ⟨count, run⟩ := states.computation.failed_state_drains (retained := retained) (definitions table) _ rfl
            targetState.control.store targetState.cells targetState.liveRegions
          exact ⟨count + 1, _, (ExitComposition.ControlProgressSteps.of_frames _ (ExitComposition.CleanupFrameSteps.of_execution run _)).trans (.cons (.finishFrames rfl) .refl),
            .complete ⟨rfl, rfl, states.store, states.cells, states.regions.symm, rfl⟩⟩
  | answerStep step childBelow simulate =>
    cases related with
    | returnedValue matching =>
      obtain ⟨count, targetAfter, run, joined⟩ := simulate matching
      exact ⟨count, _, ExitComposition.ControlProgressSteps.of_values run, .returnedValue joined⟩
  | finishAnswer finished =>
    cases related with
    | returnedValue matching =>
      obtain ⟨runtime, accepted, relatedRuntime⟩ := finished_value_disposal_corresponds matching finished
      exact ⟨1, _, .cons (.finishAnswer accepted) .refl, .complete relatedRuntime⟩

private theorem region_disposal_step_preserved_case (table : Source.Definitions signature algebra program)
    {source after : Source.RegionDisposal signature algebra program result}
    {target : ExitComposition.RegionDisposal signature algebra program result}
    (step : Source.RegionDisposalStep table source after retained)
    (below : Source.RegionDisposalStep.below (motive_1 := CleanupSimulation table) (motive_2 := ValueSimulation table)
      (motive_3 := ControlSimulation table) (motive_4 := RegionSimulation table) step) (related : RegionDisposalRelated source target) :
    ∃ count targetAfter, ExitComposition.RegionDisposalSteps (definitions table) target count targetAfter retained ∧
      RegionDisposalRelated after targetAfter := by
  cases below with
  | offer accepted =>
    obtain ⟨targetAfter, offered, joined⟩ := option_related_some related.offer accepted
    exact ⟨1, targetAfter, .cons (.offer offered) .refl, joined⟩
  | values step childBelow simulate =>
    cases related with
    | disposing outside matching =>
      obtain ⟨count, targetAfter, run, joined⟩ := simulate matching
      rw [← context_reference_support outside] at run
      exact ⟨count, _, ExitComposition.RegionDisposalSteps.of_values _ _ _ run, .disposing outside joined⟩
  | returnValue accepted =>
    obtain ⟨targetAfter, offered, joined⟩ := option_related_some related.return_value accepted
    exact ⟨1, targetAfter, .cons (.returnValue offered) .refl, joined⟩

theorem cleanup_step_preserved (table : Source.Definitions signature algebra program)
    {source after : Source.CleanupProgress signature algebra program result}
    {target : ExitComposition.CleanupFrameProgress signature algebra program result}
    (step : Source.CleanupStep table source after retained) (related : CleanupProgressRelated source target) :
    ∃ count targetAfter, ExitComposition.CleanupFrameSteps (definitions table) target count targetAfter retained ∧
      CleanupProgressRelated after targetAfter := by
  have proved : CleanupSimulation table source after retained step :=
    Source.CleanupStep.brecOn (motive_1 := CleanupSimulation table) (motive_2 := ValueSimulation table)
      (motive_3 := ControlSimulation table) (motive_4 := RegionSimulation table) step
      (fun _ _ _ current below => cleanup_step_preserved_case table current below)
      (fun _ _ _ current below => value_disposal_step_preserved_case table current below)
      (fun _ _ _ current below => control_progress_step_preserved_case table current below)
      (fun _ _ _ current below => region_disposal_step_preserved_case table current below)
  exact proved related

theorem value_disposal_step_preserved (table : Source.Definitions signature algebra program)
    {source after : Source.ValueDisposal signature algebra program}
    {target : ExitComposition.ValueDisposal signature algebra program}
    (step : Source.ValueDisposalStep table source after retained) (related : ValueDisposalRelated source target) :
    ∃ count targetAfter, ExitComposition.ValueDisposalSteps (definitions table) target count targetAfter retained ∧
      ValueDisposalRelated after targetAfter := by
  have proved : ValueSimulation table source after retained step :=
    Source.ValueDisposalStep.brecOn (motive_1 := CleanupSimulation table) (motive_2 := ValueSimulation table)
      (motive_3 := ControlSimulation table) (motive_4 := RegionSimulation table) step
      (fun _ _ _ current below => cleanup_step_preserved_case table current below)
      (fun _ _ _ current below => value_disposal_step_preserved_case table current below)
      (fun _ _ _ current below => control_progress_step_preserved_case table current below)
      (fun _ _ _ current below => region_disposal_step_preserved_case table current below)
  exact proved related

theorem control_progress_step_preserved (table : Source.Definitions signature algebra program)
    {source after : Source.ControlProgress signature algebra program result}
    {target : ExitComposition.ControlProgress signature algebra program result}
    (step : Source.ControlProgressStep table source after retained) (related : ControlProgressRelated source target) :
    ∃ count targetAfter, ExitComposition.ControlProgressSteps (definitions table) target count targetAfter retained ∧
      ControlProgressRelated after targetAfter := by
  have proved : ControlSimulation table source after retained step :=
    Source.ControlProgressStep.brecOn (motive_1 := CleanupSimulation table) (motive_2 := ValueSimulation table)
      (motive_3 := ControlSimulation table) (motive_4 := RegionSimulation table) step
      (fun _ _ _ current below => cleanup_step_preserved_case table current below)
      (fun _ _ _ current below => value_disposal_step_preserved_case table current below)
      (fun _ _ _ current below => control_progress_step_preserved_case table current below)
      (fun _ _ _ current below => region_disposal_step_preserved_case table current below)
  exact proved related


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
full D adequacy: region, suspended-work, and registered execution remain to join. -/
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

theorem finite_value_disposal_preserved (table : Source.Definitions signature algebra program)
    {source after : Source.ValueDisposal signature algebra program}
    {target : ExitComposition.ValueDisposal signature algebra program}
    (steps : Source.ValueDisposalSteps table source count after retained) (related : ValueDisposalRelated source target) :
    ∃ targetCount targetAfter, ExitComposition.ValueDisposalSteps (definitions table) target targetCount targetAfter retained ∧
      ValueDisposalRelated after targetAfter := by
  induction steps generalizing target with
  | refl => exact ⟨0, target, .refl, related⟩
  | cons step tail induction =>
    obtain ⟨firstCount, middle, first, joined⟩ := value_disposal_step_preserved table step related
    obtain ⟨restCount, final, rest, last⟩ := induction joined
    exact ⟨firstCount + restCount, final, first.trans rest, last⟩

theorem finite_control_disposal_preserved (table : Source.Definitions signature algebra program)
    {source after : Source.ControlProgress signature algebra program answer}
    {target : ExitComposition.ControlProgress signature algebra program answer}
    (steps : Source.ControlProgressSteps table source count after retained) (related : ControlProgressRelated source target) :
    ∃ targetCount targetAfter, ExitComposition.ControlProgressSteps (definitions table) target targetCount targetAfter retained ∧
      ControlProgressRelated after targetAfter := by
  induction steps generalizing target with
  | refl => exact ⟨0, target, .refl, related⟩
  | cons step tail induction =>
    obtain ⟨firstCount, middle, first, joined⟩ := control_progress_step_preserved table step related
    obtain ⟨restCount, final, rest, last⟩ := induction joined
    exact ⟨firstCount + restCount, final, first.trans rest, last⟩

theorem region_disposal_step_preserved (table : Source.Definitions signature algebra program)
    {source after : Source.RegionDisposal signature algebra program result}
    {target : ExitComposition.RegionDisposal signature algebra program result}
    (step : Source.RegionDisposalStep table source after retained) (related : RegionDisposalRelated source target) :
    ∃ count targetAfter, ExitComposition.RegionDisposalSteps (definitions table) target count targetAfter retained ∧
      RegionDisposalRelated after targetAfter := by
  have proved : RegionSimulation table source after retained step :=
    Source.RegionDisposalStep.brecOn (motive_1 := CleanupSimulation table) (motive_2 := ValueSimulation table)
      (motive_3 := ControlSimulation table) (motive_4 := RegionSimulation table) step
      (fun _ _ _ current below => cleanup_step_preserved_case table current below)
      (fun _ _ _ current below => value_disposal_step_preserved_case table current below)
      (fun _ _ _ current below => control_progress_step_preserved_case table current below)
      (fun _ _ _ current below => region_disposal_step_preserved_case table current below)
  exact proved related

theorem finite_region_disposal_preserved (table : Source.Definitions signature algebra program)
    {source after : Source.RegionDisposal signature algebra program result}
    {target : ExitComposition.RegionDisposal signature algebra program result}
    (steps : Source.RegionDisposalSteps table source count after retained) (related : RegionDisposalRelated source target) :
    ∃ targetCount targetAfter, ExitComposition.RegionDisposalSteps (definitions table) target targetCount targetAfter retained ∧
      RegionDisposalRelated after targetAfter := by
  induction steps generalizing target with
  | refl => exact ⟨0, target, .refl, related⟩
  | cons step tail induction =>
    obtain ⟨firstCount, middle, first, joined⟩ := region_disposal_step_preserved table step related
    obtain ⟨restCount, final, rest, last⟩ := induction joined
    exact ⟨firstCount + restCount, final, first.trans rest, last⟩

end BoundaryV2.Generalized.Defunctionalization
