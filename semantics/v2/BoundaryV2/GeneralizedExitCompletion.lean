import BoundaryV2.GeneralizedStatefulCleanup

namespace BoundaryV2.Generalized.ExitComposition

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

/-- Saved values are views of the owning fields in the cleanup runtime. The
continuation is first-order data and contains no host callback. -/
inductive ResumePoint (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  | returned {input : TypeOf signature} : Target.RuntimeValue signature algebra program input →
      Target.Stack signature algebra program input result → ResumePoint signature algebra program result
  | unwind {input : TypeOf signature} : Target.Stack signature algebra program input result → ResumePoint signature algebra program result

structure ScopeExit (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  cleanup : Runtime signature algebra program
  resume : ResumePoint signature algebra program result

/-- Reentry carries the complete exit information alongside the machine state.
Cancellation and abandonment retain their outside continuation for further
unwinding, rather than being turned into an invented authored fault. -/
inductive Resolution (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  | reenter : Target.State signature algebra program result → ExitInfo algebra.Fault algebra.Reason → Resolution signature algebra program result
  | unwind {input : TypeOf signature} : Runtime signature algebra program →
      Target.Stack signature algebra program input result → Resolution signature algebra program result

/-- An outer boundary cannot consume the current cleanup's pending or running
work. This is the common admission condition for all resolution consumers. -/
def Resolution.cleanupFinished : Resolution signature algebra program result → Bool
  | .reenter _ _ => true
  | .unwind runtime _ => match runtime.phase with
    | .finished _ => true
    | .pending _ | .running _ _ => false

def beginReturnedProtection (state : Target.State signature algebra program result) :
    Option (ScopeExit signature algebra program result) :=
  match state.control.configuration with
  | .returned value future => match future with
    | .push (.protection identity cleanup bindings) outside =>
      some ⟨⟨identity, .pending ⟨_, cleanup, bindings⟩, state.control.store, state.cells, state.liveRegions, ⟨.normal, [], none⟩⟩,
        .returned value outside⟩
    | _ => none
  | _ => none

def beginFailedProtection (state : Target.State signature algebra program result)
    (failures : List algebra.Fault) (cancellation : Option algebra.Reason) :
    Option (ScopeExit signature algebra program result) :=
  match state.control.configuration with
  | .failed fault future => match future with
    | .push (.protection identity cleanup bindings) outside =>
      some ⟨⟨identity, .pending ⟨_, cleanup, bindings⟩, state.control.store, state.cells, state.liveRegions,
        ⟨.failure fault, failures, cancellation⟩⟩, .unwind outside⟩
    | _ => none
  | _ => none

def finish (scope : ScopeExit signature algebra program result) : Option (Resolution signature algebra program result) :=
  match scope.cleanup.phase with
  | .pending _ | .running _ _ => none
  | .finished _ =>
    match scope.cleanup.exit.primary, scope.resume with
    | .normal, .returned value outside =>
      some (.reenter ⟨⟨scope.cleanup.store, .returned value outside⟩, scope.cleanup.cells, scope.cleanup.liveRegions⟩ scope.cleanup.exit)
    | .normal, .unwind _ => none
    | .failure fault, .returned _ outside | .failure fault, .unwind outside =>
      some (.reenter ⟨⟨scope.cleanup.store, .failed fault outside⟩, scope.cleanup.cells, scope.cleanup.liveRegions⟩ scope.cleanup.exit)
    | .cancelled, .returned _ outside | .cancelled, .unwind outside |
      .abandoned, .returned _ outside | .abandoned, .unwind outside => some (.unwind scope.cleanup outside)

/-- A failure reaching another protected scope carries the history produced by
the preceding cleanup; callers do not reconstruct its failure list or reason. -/
def beginFollowingFailedProtection (resolution : Resolution signature algebra program result) :
    Option (ScopeExit signature algebra program result) :=
  match resolution with
  | .reenter state exit => beginFailedProtection state exit.failures exit.cancellation
  | .unwind _ _ => none

theorem following_failed_scope_retains_accumulated_history
    (store : Target.ControlHeap signature algebra program)
    (cells : Cells signature algebra (fun context result => Target.Code signature algebra program context [] result))
    (regions : List (Id .region)) (identity : Id .obligation)
    (cleanup : Target.Code signature algebra program (.exit :: context) [] .unit)
    (bindings : Target.RuntimeEnvironment signature algebra program context)
    (outside : Target.Stack signature algebra program input result)
    (original : algebra.Fault) (prior : List algebra.Fault) (reason : Option algebra.Reason) :
    beginFollowingFailedProtection
      (.reenter ⟨⟨store, .failed original (.push (.protection identity cleanup bindings) outside)⟩, cells, regions⟩
        ⟨.failure original, prior, reason⟩) =
      some ⟨⟨identity, .pending ⟨context, cleanup, bindings⟩, store, cells, regions,
        ⟨.failure original, prior, reason⟩⟩, .unwind outside⟩ := rfl

theorem unfinished_cleanup_cannot_reenter
    (scope : ScopeExit signature algebra program result)
    (running : scope.cleanup.phase = .running cursor location) : finish scope = none := by
  simp only [finish, running]

theorem pending_cleanup_cannot_reenter
    (scope : ScopeExit signature algebra program result)
    (pending : scope.cleanup.phase = .pending cleanup) : finish scope = none := by
  simp only [finish, pending]

theorem normal_cleanup_reentry_preserves_resources
    (runtime : Runtime signature algebra program) (completed : runtime.phase = .finished .returned)
    (normal : runtime.exit.primary = .normal) (value : Target.RuntimeValue signature algebra program input)
    (outside : Target.Stack signature algebra program input result) :
    finish ⟨runtime, .returned value outside⟩ =
      some (.reenter ⟨⟨runtime.store, .returned value outside⟩, runtime.cells, runtime.liveRegions⟩ runtime.exit) := by
  simp only [finish, completed, normal]

theorem original_failure_reenters_with_all_cleanup_information
    (runtime : Runtime signature algebra program) (completed : runtime.phase = .finished outcome)
    (failed : runtime.exit.primary = .failure fault) (outside : Target.Stack signature algebra program input result) :
    finish ⟨runtime, .unwind outside⟩ =
      some (.reenter ⟨⟨runtime.store, .failed fault outside⟩, runtime.cells, runtime.liveRegions⟩ runtime.exit) := by
  simp only [finish, completed, failed]

theorem finished_failure_overrides_a_saved_return_value
    (runtime : Runtime signature algebra program) (completed : runtime.phase = .finished outcome)
    (failed : runtime.exit.primary = .failure fault) (value : Target.RuntimeValue signature algebra program input)
    (outside : Target.Stack signature algebra program input result) :
    finish ⟨runtime, .returned value outside⟩ =
      some (.reenter ⟨⟨runtime.store, .failed fault outside⟩, runtime.cells, runtime.liveRegions⟩ runtime.exit) := by
  simp only [finish, completed, failed]

theorem cleanup_failure_preserves_original_failure_and_order
    (runtime : Runtime signature algebra program) (original cleanupFault : algebra.Fault)
    (prior : List algebra.Fault) (reason : Option algebra.Reason)
    (outside : Target.Stack signature algebra program input result) :
    let after := { runtime with
      phase := .finished (.failed cleanupFault)
      exit := (⟨.failure original, prior, reason⟩ : ExitInfo algebra.Fault algebra.Reason).cleanupFailure cleanupFault }
    finish ⟨after, .unwind outside⟩ =
      some (.reenter ⟨⟨runtime.store, .failed original outside⟩, runtime.cells, runtime.liveRegions⟩
        ⟨.failure original, prior ++ [cleanupFault], reason⟩) := rfl

theorem cancellation_keeps_the_outside_for_unwinding
    (runtime : Runtime signature algebra program) (completed : runtime.phase = .finished outcome)
    (cancelled : runtime.exit.primary = .cancelled) (outside : Target.Stack signature algebra program input result) :
    finish ⟨runtime, .unwind outside⟩ = some (.unwind runtime outside) := by
  simp only [finish, completed, cancelled]

theorem abandonment_keeps_the_outside_for_unwinding
    (runtime : Runtime signature algebra program) (completed : runtime.phase = .finished .abandoned)
    (abandoned : runtime.exit.primary = .abandoned) (outside : Target.Stack signature algebra program input result) :
    finish ⟨runtime, .unwind outside⟩ = some (.unwind runtime outside) := by
  simp only [finish, completed, abandoned]


end BoundaryV2.Generalized.ExitComposition

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

theorem cleanup_return_reentry_corresponds
    (runtime : ExitComposition.Runtime signature algebra program)
    (completed : runtime.phase = .finished .returned) (normal : runtime.exit.primary = .normal)
    (returned : Source.RuntimeValue signature algebra program input)
    (sourceStore : Source.ControlHeap signature algebra program)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program))
    (stores : ControlHeapRelated sourceStore runtime.store) (sameCells : runtime.cells = cells sourceCells)
    {sourceOutside : Source.Context signature algebra program input result}
    {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    ∃ targetAfter, ExitComposition.finish ⟨runtime, .returned (value returned) targetOutside⟩ = some (.reenter targetAfter runtime.exit) ∧
      CellStateRelated ⟨⟨sourceStore, sourceOutside.plug (.returned returned)⟩, sourceCells, runtime.liveRegions⟩ targetAfter := by
  exact ⟨_, ExitComposition.normal_cleanup_reentry_preserves_resources runtime completed normal _ _,
    ⟨⟨stores, .returned returned outside⟩, sameCells, rfl⟩⟩

theorem cleanup_failure_reentry_corresponds
    (runtime : ExitComposition.Runtime signature algebra program)
    (completed : runtime.phase = .finished outcome) (failed : runtime.exit.primary = .failure fault)
    (sourceStore : Source.ControlHeap signature algebra program)
    (sourceCells : Cells signature algebra (Source.Computation signature algebra program))
    (stores : ControlHeapRelated sourceStore runtime.store) (sameCells : runtime.cells = cells sourceCells)
    {sourceOutside : Source.Context signature algebra program input result}
    {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    ∃ targetAfter, ExitComposition.finish ⟨runtime, .unwind targetOutside⟩ = some (.reenter targetAfter runtime.exit) ∧
      CellStateRelated ⟨⟨sourceStore, sourceOutside.plug (.failed fault)⟩, sourceCells, runtime.liveRegions⟩ targetAfter := by
  exact ⟨_, ExitComposition.original_failure_reenters_with_all_cleanup_information runtime completed failed _,
    ⟨⟨stores, .failed fault outside⟩, sameCells, rfl⟩⟩

end BoundaryV2.Generalized.Defunctionalization
