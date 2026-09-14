import BoundaryV2.GeneralizedSourceExits

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

structure ExitRuntimeRelated (source : Source.ExitRuntime signature algebra program)
    (target : ExitComposition.Runtime signature algebra program) : Prop where
  identity : target.id = source.id
  completion : target.phase = .finished source.completion
  store : ControlHeapRelated source.store target.store
  cells : target.cells = Defunctionalization.cells source.cells
  regions : target.liveRegions = source.regions
  exit : target.exit = source.exit

inductive ExitResolutionRelated : Source.ExitResolution signature algebra program result →
    ExitComposition.Resolution signature algebra program result → Prop where
  | reenter : ExecutionStateRelated source target →
      ExitResolutionRelated (.reenter source diagnostics) (.reenter target diagnostics)
  | unwind : ExitRuntimeRelated source target → ContextRelated signature algebra program sourceOutside targetOutside →
      ExitResolutionRelated (.unwind source sourceOutside) (.unwind target targetOutside)

inductive CleanupDisposalRelated : Source.CleanupDisposal signature algebra program result →
    ExitComposition.CleanupDisposal signature algebra program result → Prop where
  | same (original : Source.RuntimeValue signature algebra program input) :
      ExitRuntimeRelated source target → ContextRelated signature algebra program sourceOutside targetOutside →
      CleanupDisposalRelated ⟨input, original, source, sourceOutside⟩ ⟨input, value original, target, targetOutside⟩

inductive CompletedCleanupRelated : Source.CompletedCleanup signature algebra program result →
    ExitComposition.CompletedCleanup signature algebra program result → Prop where
  | resolved : ExitResolutionRelated source target → CompletedCleanupRelated (.resolved source) (.resolved target)
  | disposing : CleanupDisposalRelated source target → CompletedCleanupRelated (.disposing source) (.disposing target)

inductive CleanupProgressRelated : Source.CleanupProgress signature algebra program result →
    ExitComposition.CleanupFrameProgress signature algebra program result → Prop where
  | running : ExitResolutionRelated source target → CleanupProgressRelated (.running source) (.running target)
  | disposing : CleanupDisposalRelated source target → CleanupProgressRelated (.disposing source) (.disposing target)

theorem CompletedCleanupRelated.progress (related : CompletedCleanupRelated source target) :
    CleanupProgressRelated source.progress target.progress := by
  cases related with
  | resolved same => exact .running same
  | disposing same => exact .disposing same

/-- Shared leaf-result mapping is only a data law. Each side independently
reenters its own continuation with its current heap and stored values. -/
theorem cleanup_reentry_corresponds
    (identity : Id .obligation) (completion : ExitComposition.Completion algebra.Fault)
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceOutside : Source.Context signature algebra program input result}
    {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (outcome : ExitComposition.CleanupResult signature algebra (Source.Computation signature algebra program) input) :
    CompletedCleanupRelated
      (Source.reenterCleanupResult identity completion sourceStore sourceCells regions sourceOutside outcome)
      (ExitComposition.reenterCleanupResult identity completion targetStore (cells sourceCells) regions targetOutside
        (outcome.mapBodies (fun _ _ body => computation body))) := by
  cases outcome with
  | returned original exit =>
    exact .resolved (.reenter ⟨stores, rfl, rfl, outside.close_program (.returned original _)⟩)
  | disposing original exit =>
    exact .disposing (.same original ⟨rfl, rfl, stores, rfl, rfl, rfl⟩ outside)
  | exiting exit =>
    cases exit with
    | mk primary failures cancellation =>
      cases primary with
      | failure fault => exact .resolved (.reenter ⟨stores, rfl, rfl, outside.close_program (.failed fault _)⟩)
      | normal | cancelled | abandoned => exact .resolved (.unwind ⟨rfl, rfl, stores, rfl, rfl, rfl⟩ outside)

/-- This entry theorem retains arbitrary source handlers and callbacks in the
outside context; target cleanup uses only compiled code and data frames. -/
theorem cleanup_entry_corresponds
    (identity : Id .obligation) (cleanup : Source.Computation signature algebra program (.exit :: context) .unit)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    (exit : ExitInfo algebra.Fault algebra.Reason)
    {sourceOutside : Source.Context signature algebra program input result}
    {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    ExitResolutionRelated (Source.beginExitCleanup identity cleanup bindings sourceStore sourceCells regions exit sourceOutside)
      (.reenter ⟨⟨targetStore, .code (computation cleanup) (.cons (.exit exit) (environment bindings)) .nil
        (.push (.cleanupReturn identity none exit) targetOutside)⟩, cells sourceCells, regions⟩ ⟨.normal, [], none⟩) :=
  .reenter ⟨stores, rfl, rfl, outside.close_program (.cleaning identity none exit (.evaluate cleanup (.cons (.exit exit) bindings) _))⟩

/-- The actual saved value determines all three outcomes: return, exit, and
owned disposal. No preservation conclusion is part of the local premise. -/
theorem cleanup_finalization_corresponds
    (original : Option (Source.RuntimeValue signature algebra program input)) (exit : ExitInfo algebra.Fault algebra.Reason)
    (accepted : ExitComposition.finalizeCleanup original exit = some outcome) :
    ExitComposition.finalizeCleanup (original.map value) exit = some (outcome.mapBodies (fun _ _ body => computation body)) := by
  have mapped := ExitComposition.cleanup_finalization_commutes_with_body_mapping
    (signature := signature) (algebra := algebra) (Before := Source.Computation signature algebra program)
    (After := fun context result => Target.Code signature algebra program context [] result) (fun _ _ body => computation body) original exit
  rw [accepted] at mapped
  exact mapped

/-- Target admission of a completed result reflects to the source decision,
including the owning-result branch, by the actual data mapping. -/
theorem cleanup_finalization_reflected
    (original : Option (Source.RuntimeValue signature algebra program input)) (exit : ExitInfo algebra.Fault algebra.Reason)
    (accepted : ExitComposition.finalizeCleanup (original.map value) exit = some targetOutcome) :
    ∃ sourceOutcome, ExitComposition.finalizeCleanup original exit = some sourceOutcome ∧
      targetOutcome = sourceOutcome.mapBodies (fun _ _ body => computation body) := by
  have mapped := ExitComposition.cleanup_finalization_commutes_with_body_mapping
    (signature := signature) (algebra := algebra) (Before := Source.Computation signature algebra program)
    (After := fun context result => Target.Code signature algebra program context [] result)
      (fun _ _ body => computation body) original exit
  change ExitComposition.finalizeCleanup (original.map value) exit = _ at mapped
  rw [accepted] at mapped
  obtain ⟨sourceOutcome, sourceAccepted, same⟩ := Option.map_eq_some_iff.mp mapped.symm
  exact ⟨sourceOutcome, sourceAccepted, same.symm⟩

variable [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

theorem failure_cleanup_entry_steps_correspond
    (table : Source.Definitions signature algebra program)
    (identity : Id .obligation) (cleanup : Source.Computation signature algebra program (.exit :: context) .unit)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (fault : algebra.Fault) (diagnostics : ExitInfo algebra.Fault algebra.Reason)
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceOutside : Source.Context signature algebra program input result}
    {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    let sourceBefore := Source.CleanupProgress.running (.reenter
      ⟨⟨sourceStore, sourceOutside.plug (.protection identity cleanup bindings (.failed fault))⟩, sourceCells, regions⟩ diagnostics)
    let targetBefore := ExitComposition.CleanupFrameProgress.running (.reenter
      ⟨⟨targetStore, .failed fault (.push (.protection identity (computation cleanup) (environment bindings)) targetOutside)⟩,
        cells sourceCells, regions⟩ diagnostics)
    ∃ sourceAfter targetAfter,
      Source.CleanupStep table sourceBefore sourceAfter retained ∧
      ExitComposition.CleanupFrameStep (definitions table) targetBefore targetAfter retained ∧
      CleanupProgressRelated sourceAfter targetAfter := by
  refine ⟨_, _, .beginFailure, .begin rfl, .running ?_⟩
  exact cleanup_entry_corresponds identity cleanup bindings stores sourceCells regions _ outside

theorem unwind_cleanup_entry_steps_correspond
    (table : Source.Definitions signature algebra program)
    (identity : Id .obligation) (cleanup : Source.Computation signature algebra program (.exit :: context) .unit)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    {source : Source.ExitRuntime signature algebra program} {target : ExitComposition.Runtime signature algebra program}
    (runtime : ExitRuntimeRelated source target)
    {sourceOutside : Source.Context signature algebra program input result}
    {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    ∃ sourceAfter targetAfter,
      Source.CleanupStep table (.running (.unwind source (.push (.protection identity cleanup bindings) sourceOutside))) sourceAfter retained ∧
      ExitComposition.CleanupFrameStep (definitions table)
        (.running (.unwind target (.push (.protection identity (computation cleanup) (environment bindings)) targetOutside))) targetAfter retained ∧
      CleanupProgressRelated sourceAfter targetAfter := by
  rcases source with ⟨sourceId, completion, sourceStore, sourceCells, regions, exit⟩
  rcases target with ⟨targetId, phase, targetStore, targetCells, targetRegions, targetExit⟩
  rcases runtime with ⟨sameId, completed, stores, storage, live, sameExit⟩
  dsimp only at sameId completed stores storage live sameExit
  subst targetId phase targetCells targetRegions targetExit
  exact ⟨_, _, .beginUnwind, .begin rfl,
    .running (cleanup_entry_corresponds identity cleanup bindings stores sourceCells regions exit outside)⟩


theorem returned_cleanup_steps_correspond
    (table : Source.Definitions signature algebra program) (identity : Id .obligation)
    (original : Option (Source.RuntimeValue signature algebra program input))
    (cleaned : Source.RuntimeValue signature algebra program .unit)
    (exit diagnostics : ExitInfo algebra.Fault algebra.Reason)
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceOutside : Source.Context signature algebra program input result}
    {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (accepted : ExitComposition.finalizeCleanup original exit = some outcome) :
    ∃ sourceAfter targetAfter,
      Source.CleanupStep table (.running (.reenter
        ⟨⟨sourceStore, sourceOutside.plug (.cleaning identity original exit (.returned cleaned))⟩, sourceCells, regions⟩ diagnostics)) sourceAfter retained ∧
      ExitComposition.CleanupFrameStep (definitions table) (.running (.reenter
        ⟨⟨targetStore, .returned (value cleaned) (.push (.cleanupReturn identity (original.map value) exit) targetOutside)⟩,
          cells sourceCells, regions⟩ diagnostics)) targetAfter retained ∧
      CleanupProgressRelated sourceAfter targetAfter := by
  have finalized := cleanup_finalization_corresponds original exit accepted
  refine ⟨_, _, .returned accepted, .finish (after := ExitComposition.reenterCleanupResult identity .returned
    targetStore (cells sourceCells) regions targetOutside (outcome.mapBodies (fun _ _ body => computation body))) ?_,
    (cleanup_reentry_corresponds identity .returned stores sourceCells regions outside outcome).progress⟩
  change (ExitComposition.finalizeCleanup (original.map value) exit).map _ = some _
  rw [finalized]
  rfl

theorem failed_cleanup_steps_correspond
    (table : Source.Definitions signature algebra program) (identity : Id .obligation)
    (original : Option (Source.RuntimeValue signature algebra program input)) (fault : algebra.Fault)
    (exit diagnostics : ExitInfo algebra.Fault algebra.Reason)
    {sourceStore : Source.ControlHeap signature algebra program} {targetStore : Target.ControlHeap signature algebra program}
    (stores : ControlHeapRelated sourceStore targetStore)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program)) (regions : List (Id .region))
    {sourceOutside : Source.Context signature algebra program input result}
    {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (accepted : ExitComposition.finalizeCleanup original (exit.nestedFailure fault diagnostics.failures diagnostics.cancellation) = some outcome) :
    ∃ sourceAfter targetAfter,
      Source.CleanupStep table (.running (.reenter
        ⟨⟨sourceStore, sourceOutside.plug (.cleaning identity original exit (.failed fault))⟩, sourceCells, regions⟩ diagnostics)) sourceAfter retained ∧
      ExitComposition.CleanupFrameStep (definitions table) (.running (.reenter
        ⟨⟨targetStore, .failed fault (.push (.cleanupReturn identity (original.map value) exit) targetOutside)⟩,
          cells sourceCells, regions⟩ diagnostics)) targetAfter retained ∧
      CleanupProgressRelated sourceAfter targetAfter := by
  have finalized := cleanup_finalization_corresponds original (exit.nestedFailure fault diagnostics.failures diagnostics.cancellation) accepted
  refine ⟨_, _, .failed accepted, .finish (after := ExitComposition.reenterCleanupResult identity (.failed fault)
    targetStore (cells sourceCells) regions targetOutside (outcome.mapBodies (fun _ _ body => computation body))) ?_,
    (cleanup_reentry_corresponds identity (.failed fault) stores sourceCells regions outside outcome).progress⟩
  change (ExitComposition.finalizeCleanup (original.map value) _).map _ = some _
  rw [finalized]
  rfl

theorem unwound_cleanup_steps_correspond
    (table : Source.Definitions signature algebra program) (identity : Id .obligation)
    (original : Option (Source.RuntimeValue signature algebra program input)) (exit : ExitInfo algebra.Fault algebra.Reason)
    {source : Source.ExitRuntime signature algebra program} {target : ExitComposition.Runtime signature algebra program}
    (runtime : ExitRuntimeRelated source target)
    {sourceOutside : Source.Context signature algebra program input result}
    {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (accepted : ExitComposition.finalizeCleanup original
      (match source.exit.primary with
        | .failure fault => exit.nestedFailure fault source.exit.failures source.exit.cancellation
        | _ => exit.nestedAbandon source.exit) = some outcome) :
    ∃ sourceAfter targetAfter,
      Source.CleanupStep table (.running (.unwind source (.push (.cleanupReturn identity original exit) sourceOutside))) sourceAfter retained ∧
      ExitComposition.CleanupFrameStep (definitions table)
        (.running (.unwind target (.push (.cleanupReturn identity (original.map value) exit) targetOutside))) targetAfter retained ∧
      CleanupProgressRelated sourceAfter targetAfter := by
  rcases source with ⟨sourceId, completion, sourceStore, sourceCells, regions, diagnostics⟩
  rcases target with ⟨targetId, phase, targetStore, targetCells, targetRegions, targetExit⟩
  rcases runtime with ⟨sameId, completed, stores, storage, live, sameExit⟩
  dsimp only at sameId completed stores storage live sameExit
  subst targetId phase targetCells targetRegions targetExit
  have finalized := cleanup_finalization_corresponds original _ accepted
  refine ⟨_, _, .unwound accepted, .finish (after := ExitComposition.reenterCleanupResult identity .abandoned
    targetStore (cells sourceCells) regions targetOutside (outcome.mapBodies (fun _ _ body => computation body))) ?_,
    (cleanup_reentry_corresponds identity .abandoned stores sourceCells regions outside outcome).progress⟩
  change (ExitComposition.finalizeCleanup (original.map value) _).map _ = some _
  cases diagnostics with
  | mk primary failures cancellation =>
    cases primary <;> dsimp only at finalized ⊢
    all_goals rw [finalized]; rfl

end BoundaryV2.Generalized.Defunctionalization
