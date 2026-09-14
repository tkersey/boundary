import BoundaryV2.GeneralizedExitCompletion

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

namespace Source

inductive UnwindBoundary (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  | complete
  | cleanupReturn {input : TypeOf signature} : Id .obligation → Option (RuntimeValue signature algebra program input) →
      ExitInfo algebra.Fault algebra.Reason → Context signature algebra program input result → UnwindBoundary signature algebra program result
  | region {input : TypeOf signature} : Id .region → Context signature algebra program input result → UnwindBoundary signature algebra program result
  | protection {input : TypeOf signature} {context : List (TypeOf signature)} :
      Id .obligation → Computation signature algebra program (.exit :: context) .unit →
      RuntimeEnvironment signature algebra program context → Context signature algebra program input result → UnwindBoundary signature algebra program result

/-- Unwinding does not execute ordinary continuation functions or normal-return
clauses. Regions remain explicit boundaries for their owning close operation. -/
def unwindBoundary : Context signature algebra program input result → UnwindBoundary signature algebra program result
  | .done => .complete
  | .push frame rest => match frame with
    | .bind _ _ | .handler _ _ _ _ _ _ => unwindBoundary rest
    | .region identity => .region identity rest
    | .protection identity cleanup bindings => .protection identity cleanup bindings rest
    | .cleanupReturn identity original exit => .cleanupReturn identity original exit rest

end Source

namespace Target

inductive UnwindBoundary (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  | complete
  | cleanupReturn {input : TypeOf signature} : Id .obligation → Option (RuntimeValue signature algebra program input) →
      ExitInfo algebra.Fault algebra.Reason → Stack signature algebra program input result → UnwindBoundary signature algebra program result
  | region {input : TypeOf signature} : Id .region → Stack signature algebra program input result → UnwindBoundary signature algebra program result
  | protection {input : TypeOf signature} {context : List (TypeOf signature)} :
      Id .obligation → Code signature algebra program (.exit :: context) [] .unit →
      RuntimeEnvironment signature algebra program context → Stack signature algebra program input result → UnwindBoundary signature algebra program result

def unwindBoundary : Stack signature algebra program input result → UnwindBoundary signature algebra program result
  | .done => .complete
  | .push frame rest => match frame with
    | .returnTo _ _ _ | .handler _ _ _ _ _ _ => unwindBoundary rest
    | .region identity => .region identity rest
    | .protection identity cleanup bindings => .protection identity cleanup bindings rest
    | .cleanupReturn identity original exit => .cleanupReturn identity original exit rest

def UnwindBoundary.pending : UnwindBoundary signature algebra program result → List (Id .obligation)
  | .complete => []
  | .cleanupReturn _ _ _ outside => ExitComposition.pendingProtections outside
  | .region _ outside => ExitComposition.pendingProtections outside
  | .protection identity _ _ outside => identity :: ExitComposition.pendingProtections outside

theorem unwind_boundary_retains_pending (future : Stack signature algebra program input result) :
    (unwindBoundary future).pending = ExitComposition.pendingProtections future := by
  induction future with
  | done => rfl
  | push frame rest induction =>
    cases frame with
    | returnTo | handler => exact induction
    | region | protection | cleanupReturn => rfl

theorem selected_cleanup_is_innermost
    (future : Stack signature algebra program input result)
    (selected : unwindBoundary future = .protection identity cleanup bindings outside) :
    ExitComposition.pendingProtections future = identity :: ExitComposition.pendingProtections outside := by
  induction future with
  | done => cases selected
  | push frame rest induction =>
    cases frame with
    | returnTo | handler => exact induction selected
    | region | cleanupReturn => cases selected
    | protection => cases selected; rfl

end Target

namespace Defunctionalization

inductive UnwindBoundaryRelated : Source.UnwindBoundary signature algebra program result →
    Target.UnwindBoundary signature algebra program result → Prop where
  | complete : UnwindBoundaryRelated .complete .complete
  | cleanupReturn (identity : Id .obligation) (original : Option (Source.RuntimeValue signature algebra program input))
      (exit : ExitInfo algebra.Fault algebra.Reason) : ContextRelated signature algebra program source target →
      UnwindBoundaryRelated (.cleanupReturn identity original exit source) (.cleanupReturn identity (original.map value) exit target)
  | region : ContextRelated signature algebra program source target → UnwindBoundaryRelated (.region identity source) (.region identity target)
  | protection (cleanup : Source.Computation signature algebra program (.exit :: context) .unit)
      (bindings : Source.RuntimeEnvironment signature algebra program context) :
      ContextRelated signature algebra program source target →
      UnwindBoundaryRelated (.protection identity cleanup bindings source)
        (.protection identity (computation cleanup) (environment bindings) target)

theorem unwind_boundary_corresponds (related : ContextRelated signature algebra program source target) :
    UnwindBoundaryRelated (Source.unwindBoundary source) (Target.unwindBoundary target) := by
  induction related with
  | done => exact .complete
  | push frame rest induction =>
    cases frame with
    | bind | handler => exact induction
    | region => exact .region rest
    | cleanupReturn identity original exit => exact .cleanupReturn identity original exit rest
    | protection identity cleanup bindings => exact .protection cleanup bindings rest
  | passthrough bindings rest induction => exact induction

end Defunctionalization

namespace ExitComposition

inductive UnwindNext (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  | complete : Runtime signature algebra program → UnwindNext signature algebra program result
  | region {input : TypeOf signature} : Id .region → Runtime signature algebra program →
      Target.Stack signature algebra program input result → UnwindNext signature algebra program result
  | cleanup : ScopeExit signature algebra program result → UnwindNext signature algebra program result
  | cleanupReturn {input : TypeOf signature} : Id .obligation → Option (Target.RuntimeValue signature algebra program input) →
      ExitInfo algebra.Fault algebra.Reason → Runtime signature algebra program → Target.Stack signature algebra program input result →
      UnwindNext signature algebra program result

def followUnwind (runtime : Runtime signature algebra program)
    (outside : Target.Stack signature algebra program input result) : UnwindNext signature algebra program result :=
  match Target.unwindBoundary outside with
  | .complete => .complete runtime
  | .cleanupReturn identity original exit rest => .cleanupReturn identity original exit runtime rest
  | .region identity rest => .region identity runtime rest
  | .protection identity cleanup bindings rest =>
    .cleanup ⟨{ runtime with id := identity, phase := .pending ⟨_, cleanup, bindings⟩ }, .unwind rest⟩

def followUnwindResolution (resolution : Resolution signature algebra program result) : Option (UnwindNext signature algebra program result) :=
  match resolution with
  | .unwind runtime outside => some (followUnwind runtime outside)
  | .reenter _ _ => none

/-- Failure propagation through ordinary return frames retains the full exit
record, which is not representable in the scalar fault field alone. Protection
and region boundaries are left for their respective owners. -/
def advanceFailedResolution (resolution : Resolution signature algebra program result) : Option (Resolution signature algebra program result) :=
  match resolution with
  | .unwind _ _ => none
  | .reenter state exit =>
    match state.control.configuration with
    | .failed fault future => match future with
      | .push (.returnTo _ _ _) outside | .push (.handler _ _ _ _ _ _) outside =>
        some (.reenter ⟨⟨state.control.store, .failed fault outside⟩, state.cells, state.liveRegions⟩ exit)
      | _ => none
    | _ => none

theorem failed_return_frame_keeps_exit_information
    (store : Target.ControlHeap signature algebra program)
    (cells : Cells signature algebra (fun context result => Target.Code signature algebra program context [] result))
    (regions : List (Id .region)) (exit : ExitInfo algebra.Fault algebra.Reason)
    (next : Target.Code signature algebra program context (input :: operands) answer)
    (bindings : Target.RuntimeEnvironment signature algebra program context)
    (values : Target.RuntimeEnvironment signature algebra program operands)
    (outside : Target.Stack signature algebra program answer result) :
    advanceFailedResolution (.reenter ⟨⟨store, .failed fault (.push (.returnTo next bindings values) outside)⟩, cells, regions⟩ exit) =
      some (.reenter ⟨⟨store, .failed fault outside⟩, cells, regions⟩ exit) := rfl

theorem failed_resolution_stops_at_protection
    (store : Target.ControlHeap signature algebra program)
    (cells : Cells signature algebra (fun context result => Target.Code signature algebra program context [] result))
    (regions : List (Id .region)) (exit : ExitInfo algebra.Fault algebra.Reason)
    (cleanup : Target.Code signature algebra program (.exit :: context) [] .unit)
    (bindings : Target.RuntimeEnvironment signature algebra program context)
    (outside : Target.Stack signature algebra program input result) :
    advanceFailedResolution (.reenter ⟨⟨store, .failed fault (.push (.protection identity cleanup bindings) outside)⟩, cells, regions⟩ exit) = none := rfl

theorem unwind_cleanup_preserves_resources_and_exit
    (runtime : Runtime signature algebra program) (outside : Target.Stack signature algebra program input result)
    (selected : followUnwind runtime outside = .cleanup scope) :
    scope.cleanup.store = runtime.store ∧ scope.cleanup.cells = runtime.cells ∧
      scope.cleanup.liveRegions = runtime.liveRegions ∧ scope.cleanup.exit = runtime.exit := by
  unfold followUnwind at selected
  split at selected <;> cases selected
  exact ⟨rfl, rfl, rfl, rfl⟩

theorem unwind_never_skips_a_region
    (runtime : Runtime signature algebra program) (outside : Target.Stack signature algebra program input result) :
    followUnwind runtime (.push (.region identity) outside) = .region identity runtime outside := rfl

theorem next_cleanup_has_its_pending_right
    (runtime : Runtime signature algebra program) (outside : Target.Stack signature algebra program input result)
    (selected : followUnwind runtime outside = .cleanup scope) : scope.cleanup.phase.right = 1 := by
  unfold followUnwind at selected
  split at selected <;> cases selected
  rfl

theorem next_cleanup_follows_pending_order
    (runtime : Runtime signature algebra program) (outside : Target.Stack signature algebra program input result)
    (selected : followUnwind runtime outside = .cleanup scope) :
    ∃ (remainingInput : TypeOf signature) (remaining : Target.Stack signature algebra program remainingInput result),
      scope.resume = .unwind remaining ∧
      pendingProtections outside = scope.cleanup.id :: pendingProtections remaining := by
  unfold followUnwind at selected
  split at selected <;> cases selected
  exact ⟨_, _, rfl, Target.selected_cleanup_is_innermost _ ‹_›⟩

inductive UnwindProgress (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  | seeking {input : TypeOf signature} : Runtime signature algebra program →
      Target.Stack signature algebra program input result → UnwindProgress signature algebra program result
  | cleaning : ScopeExit signature algebra program result → UnwindProgress signature algebra program result
  | region {input : TypeOf signature} : Id .region → Runtime signature algebra program →
      Target.Stack signature algebra program input result → UnwindProgress signature algebra program result
  | cleanupReturn {input : TypeOf signature} : Id .obligation → Option (Target.RuntimeValue signature algebra program input) →
      ExitInfo algebra.Fault algebra.Reason → Runtime signature algebra program → Target.Stack signature algebra program input result →
      UnwindProgress signature algebra program result
  | complete : Runtime signature algebra program → UnwindProgress signature algebra program result

/-- The current cleanup has already been selected; these are the obligations
still owned by its saved outer continuation. -/
def UnwindProgress.pending : UnwindProgress signature algebra program result → List (Id .obligation)
  | .seeking _ outside | .region _ _ outside | .cleanupReturn _ _ _ _ outside => pendingProtections outside
  | .cleaning scope => match scope.resume with
    | .returned _ outside | .unwind outside => pendingProtections outside
  | .complete _ => []

variable [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

inductive UnwindStep (table : Target.Definitions signature algebra program) :
    UnwindProgress signature algebra program result → List (Id .obligation) → UnwindProgress signature algebra program result → Prop where
  | select : runtime.exit.primary ≠ .normal → followUnwind runtime outside = .cleanup scope →
      UnwindStep table (.seeking runtime outside) [scope.cleanup.id] (.cleaning scope)
  | execute : RuntimeStep table before initiations after →
      UnwindStep table (.cleaning ⟨before, .unwind outside⟩) [] (.cleaning ⟨after, .unwind outside⟩)
  | finish : runtime.phase = .finished outcome → runtime.exit.primary ≠ .normal →
      UnwindStep table (.cleaning ⟨runtime, .unwind outside⟩) [] (.seeking runtime outside)
  | region : followUnwind runtime outside = .region identity runtime remaining →
      UnwindStep table (.seeking runtime outside) [] (.region identity runtime remaining)
  | cleanupReturn : followUnwind runtime outside = .cleanupReturn identity original exit runtime remaining →
      UnwindStep table (.seeking runtime outside) [] (.cleanupReturn identity original exit runtime remaining)
  | complete : followUnwind runtime outside = .complete runtime →
      UnwindStep table (.seeking runtime outside) [] (.complete runtime)

inductive UnwindSteps (table : Target.Definitions signature algebra program) :
    UnwindProgress signature algebra program result → List (Id .obligation) → UnwindProgress signature algebra program result → Prop where
  | refl : UnwindSteps table state [] state
  | cons : UnwindStep table first selected middle → UnwindSteps table middle rest after → UnwindSteps table first (selected ++ rest) after

theorem UnwindStep.selection_order {table : Target.Definitions signature algebra program}
    {before after : UnwindProgress signature algebra program result}
    (step : UnwindStep table before selected after) :
    before.pending = selected ++ after.pending := by
  cases step with
  | select _ selected =>
    unfold followUnwind at selected
    split at selected <;> cases selected
    simpa only [UnwindProgress.pending, List.singleton_append] using
      Target.selected_cleanup_is_innermost _ ‹_›
  | execute | finish => rfl
  | region selected | cleanupReturn selected | complete selected =>
    unfold followUnwind at selected
    split at selected <;> cases selected
    have retained := congrArg Target.UnwindBoundary.pending ‹Target.unwindBoundary _ = _›
    rw [Target.unwind_boundary_retains_pending] at retained
    exact retained

/-- Every finite prefix accounts for exactly the selected obligations and the
remaining continuation, in order and with multiplicity. Cleanup execution may
suspend or mutate its own state without changing this outer handoff. -/
theorem UnwindSteps.selection_order {table : Target.Definitions signature algebra program}
    {before after : UnwindProgress signature algebra program result}
    (steps : UnwindSteps table before selected after) :
    before.pending = selected ++ after.pending := by
  induction steps with
  | refl => rfl
  | cons step tail induction =>
    rw [step.selection_order, induction, List.append_assoc]

theorem completed_unwind_selects_all_pending {table : Target.Definitions signature algebra program}
    {outside : Target.Stack signature algebra program input result}
    (steps : UnwindSteps table (.seeking before outside) selected (.complete after)) :
    selected = pendingProtections outside := by
  simpa only [UnwindProgress.pending, List.append_nil] using steps.selection_order.symm

theorem unwind_never_reselects_pending {table : Target.Definitions signature algebra program}
    {before after : UnwindProgress signature algebra program result}
    (steps : UnwindSteps table before selected after) (unique : before.pending.Nodup) :
    selected.Nodup ∧ after.pending.Nodup ∧ ∀ identity ∈ selected, identity ∉ after.pending := by
  rw [steps.selection_order] at unique
  obtain ⟨selectedUnique, remainingUnique, separate⟩ := List.nodup_append.mp unique
  exact ⟨selectedUnique, remainingUnique, fun identity chosen pending => separate identity chosen identity pending rfl⟩

theorem UnwindSteps.trans {table : Target.Definitions signature algebra program}
    {before middle after : UnwindProgress signature algebra program result}
    (first : UnwindSteps table before selected middle) (second : UnwindSteps table middle rest after) :
    UnwindSteps table before (selected ++ rest) after := by
  induction first with
  | refl => exact second
  | cons step tail induction => simpa only [List.append_assoc] using UnwindSteps.cons step (induction second)

theorem run_selected_cleanup {table : Target.Definitions signature algebra program}
    {before after : Runtime signature algebra program}
    (outside : Target.Stack signature algebra program input result)
    (steps : RuntimeSteps table before initiations after)
    (completed : after.phase = .finished outcome) (exiting : after.exit.primary ≠ .normal) :
    UnwindSteps table (.cleaning ⟨before, .unwind outside⟩) [] (.seeking after outside) := by
  induction steps with
  | refl => exact .cons (.finish completed exiting) .refl
  | cons step tail induction => exact .cons (.execute step) (induction completed exiting)

theorem region_boundary_has_no_unwind_transition {table : Target.Definitions signature algebra program}
    {outside : Target.Stack signature algebra program input result} :
    ¬ UnwindStep table (.region identity runtime outside) selected after := by intro step; cases step

end ExitComposition
end BoundaryV2.Generalized
