import BoundaryV2.GeneralizedNestedCleanup
import BoundaryV2.GeneralizedDisposal

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {Body Before After : List (TypeOf signature) → TypeOf signature → Type}

def Source.Context.cancelRunning (reason : algebra.Reason) :
    Source.Context signature algebra program input result → Option (Source.Context signature algebra program input result)
  | .done => none
  | .push frame rest => match rest.cancelRunning reason with
    | some after => some (.push frame after)
    | none => match frame with
      | .cleanupReturn identity original exit => some (.push (.cleanupReturn identity original (exit.cancel reason)) rest)
      | _ => none

def Target.Stack.cancelRunning (reason : algebra.Reason) :
    Target.Stack signature algebra program input result → Option (Target.Stack signature algebra program input result)
  | .done => none
  | .push frame rest => match rest.cancelRunning reason with
    | some after => some (.push frame after)
    | none => match frame with
      | .cleanupReturn identity original exit => some (.push (.cleanupReturn identity original (exit.cancel reason)) rest)
      | _ => none

def Target.Configuration.cancelRunning (reason : algebra.Reason) :
    Target.Configuration signature algebra program result → Option (Target.Configuration signature algebra program result)
  | .code body bindings values future => (future.cancelRunning reason).map (.code body bindings values)
  | .returned value future => (future.cancelRunning reason).map (.returned value)
  | .requested operation attachment payload bodies future =>
      (future.cancelRunning reason).map (.requested operation attachment payload bodies)
  | .failed fault future => (future.cancelRunning reason).map (.failed fault)
  | .yielded next => (next.cancelRunning reason).map .yielded

theorem Target.Stack.running_cancellation_stable (first later : algebra.Reason)
    (future : Target.Stack signature algebra program input result) :
    (future.cancelRunning first).isSome = (future.cancelRunning later).isSome ∧
      ∀ after, future.cancelRunning first = some after → after.cancelRunning later = some after := by
  induction future with
  | done => exact ⟨rfl, by intro after impossible; cases impossible⟩
  | push frame rest induction =>
    cases firstAt : rest.cancelRunning first with
    | none =>
      have laterAt : rest.cancelRunning later = none := by
        have same := induction.1
        rw [firstAt] at same
        cases found : rest.cancelRunning later <;> simp_all
      cases frame <;> simp [Target.Stack.cancelRunning, firstAt, laterAt, ExitInfo.cancel_keeps_first_reason]
    | some updated =>
      have stable := induction.2 updated firstAt
      have present : (rest.cancelRunning later).isSome = true := by simpa [firstAt] using induction.1.symm
      cases laterAt : rest.cancelRunning later with
      | none => simp [laterAt] at present
      | some other =>
        simp only [Target.Stack.cancelRunning, firstAt, laterAt]
        exact ⟨rfl, by intro after same; cases same; simp only [Target.Stack.cancelRunning, stable]⟩

theorem Defunctionalization.running_cancellation_corresponds
    (reason : algebra.Reason) (related : ContextRelated signature algebra program source target) :
    Option.Rel (ContextRelated signature algebra program) (source.cancelRunning reason) (target.cancelRunning reason) := by
  induction related with
  | done => exact .none
  | @passthrough context input output source target bindings rest induction =>
    cases first : source.cancelRunning reason <;> cases second : target.cancelRunning reason <;>
      try simp only [first, second] at induction
    all_goals cases induction
    · simp only [Target.Stack.cancelRunning, second]; exact .none
    · simp only [Target.Stack.cancelRunning, second]; exact .some (.passthrough bindings ‹_›)
  | @push input middle sourceFrame targetFrame output sourceRest targetRest frame rest induction =>
    cases first : Source.Context.cancelRunning reason sourceRest <;> cases second : Target.Stack.cancelRunning reason targetRest <;>
      try simp only [first, second] at induction
    all_goals cases induction
    · cases frame <;> simp only [Source.Context.cancelRunning, Target.Stack.cancelRunning, first, second]
      all_goals first | exact .none | exact .some (.push (.cleanupReturn _ _ _) rest)
    · simp only [Source.Context.cancelRunning, Target.Stack.cancelRunning, first, second]
      exact .some (.push frame ‹_›)

namespace ExitComposition

/-- The original return value remains available until abrupt completion has
either proved it has no owners or handed it to explicit disposal. -/
inductive CleanupResult (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (Body : List (TypeOf signature) → TypeOf signature → Type) (result : TypeOf signature) where
  | returned : Value signature algebra Body result → ExitInfo algebra.Fault algebra.Reason → CleanupResult signature algebra Body result
  | exiting : ExitInfo algebra.Fault algebra.Reason → CleanupResult signature algebra Body result
  | disposing : Value signature algebra Body result → ExitInfo algebra.Fault algebra.Reason → CleanupResult signature algebra Body result

def finalizeCleanup (original : Option (Value signature algebra Body result)) (exit : ExitInfo algebra.Fault algebra.Reason) :
    Option (CleanupResult signature algebra Body result) :=
  match exit.primary with
  | .normal => original.map fun value => .returned value exit
  | _ => some (match original with
    | none => .exiting exit
    | some value => if value.owningField.tokens.isEmpty then .exiting exit else .disposing value exit)

def CleanupResult.mapBodies (transform : ∀ context type, Before context type → After context type) :
    CleanupResult signature algebra Before result → CleanupResult signature algebra After result
  | .returned value exit => .returned (value.map transform) exit
  | .exiting exit => .exiting exit
  | .disposing value exit => .disposing (value.map transform) exit

theorem cleanup_finalization_commutes_with_body_mapping
    (transform : ∀ context type, Before context type → After context type)
    (original : Option (Value signature algebra Before result)) (exit : ExitInfo algebra.Fault algebra.Reason) :
    finalizeCleanup (original.map (Value.map transform)) exit =
      (finalizeCleanup original exit).map (CleanupResult.mapBodies transform) := by
  cases exit with
  | mk primary failures cancellation =>
    cases primary <;> cases original <;>
      simp [finalizeCleanup, CleanupResult.mapBodies, Value.map_preserves_owning_fields]
    all_goals split <;> rfl

theorem abrupt_completion_retains_every_owned_return
    (value : Value signature algebra Body result) (exit : ExitInfo algebra.Fault algebra.Reason)
    (abrupt : exit.primary ≠ .normal) (owned : value.owningField.tokens.isEmpty = false) :
    finalizeCleanup (some value) exit = some (.disposing value exit) := by
  cases exit with
  | mk primary failures cancellation => cases primary <;> simp_all [finalizeCleanup]

theorem stale_nonowning_return_does_not_require_disposal
    (value : Value signature algebra Body result) (exit : ExitInfo algebra.Fault algebra.Reason)
    (abrupt : exit.primary ≠ .normal) (unowned : value.owningField.tokens.isEmpty = true) :
    finalizeCleanup (some value) exit = some (.exiting exit) := by
  cases exit with
  | mk primary failures cancellation => cases primary <;> simp_all [finalizeCleanup]

variable {program : List (BodyType signature.Data signature.Effect)}

def Resolution.cancelRunning (reason : algebra.Reason) :
    Resolution signature algebra program result → Option (Resolution signature algebra program result)
  | .reenter state exit => (state.control.configuration.cancelRunning reason).map fun configuration =>
      .reenter { state with control := { state.control with configuration := configuration } } exit
  | .unwind runtime outside => (outside.cancelRunning reason).map (.unwind runtime)

theorem frame_cancellation_preserves_resources_and_body_diagnostics
    (before after : Resolution signature algebra program result)
    (accepted : before.cancelRunning reason = some after) :
    after.store = before.store ∧ after.cells = before.cells ∧ after.regions = before.regions ∧ after.exitInfo = before.exitInfo := by
  cases before with
  | reenter state exit =>
    obtain ⟨configuration, _, same⟩ := Option.map_eq_some_iff.mp accepted
    cases same
    exact ⟨rfl, rfl, rfl, rfl⟩
  | unwind runtime outside =>
    obtain ⟨future, _, same⟩ := Option.map_eq_some_iff.mp accepted
    cases same
    exact ⟨rfl, rfl, rfl, rfl⟩

/-- This record owns the still-undisposed value and the continuation to unwind
after its disposal. The runtime carries the current resources and full exit. -/
structure CleanupDisposal (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  type : TypeOf signature
  value : Target.RuntimeValue signature algebra program type
  runtime : Runtime signature algebra program
  outside : Target.Stack signature algebra program type result

inductive CompletedCleanup (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  | resolved : Resolution signature algebra program result → CompletedCleanup signature algebra program result
  | disposing : CleanupDisposal signature algebra program result → CompletedCleanup signature algebra program result

def reenterCleanupResult (identity : Id .obligation) (completion : Completion algebra.Fault)
    (store : Target.ControlHeap signature algebra program)
    (cells : Cells signature algebra (fun context result => Target.Code signature algebra program context [] result))
    (regions : List (Id .region)) (outside : Target.Stack signature algebra program input result) :
    CleanupResult signature algebra (fun context result => Target.Code signature algebra program context [] result) input →
    CompletedCleanup signature algebra program result
  | .returned value exit => .resolved (.reenter ⟨⟨store, .returned value outside⟩, cells, regions⟩ exit)
  | .exiting exit => match exit.primary with
    | .failure fault => .resolved (.reenter ⟨⟨store, .failed fault outside⟩, cells, regions⟩ exit)
    | _ => .resolved (.unwind ⟨identity, .finished completion, store, cells, regions, exit⟩ outside)
  | .disposing value exit => .disposing ⟨_, value, ⟨identity, .finished completion, store, cells, regions, exit⟩, outside⟩

/-- Complete the actual running frame at the head of the execution stack.
Incoming diagnostics belong to this cleanup body; the frame owns the protected
computation's original exit. Neither record replaces the other. -/
def finishCleanupFrame (resolution : Resolution signature algebra program result) :
    Option (CompletedCleanup signature algebra program result) :=
  match resolution with
  | .reenter state diagnostics => match state.control.configuration with
    | .returned _ future => match future with
      | .push (.cleanupReturn identity original exit) outside =>
        (finalizeCleanup original exit).map (reenterCleanupResult identity .returned state.control.store state.cells state.liveRegions outside)
      | _ => none
    | .failed fault future => match future with
      | .push (.cleanupReturn identity original exit) outside =>
        (finalizeCleanup original (exit.nestedFailure fault diagnostics.failures diagnostics.cancellation)).map
          (reenterCleanupResult identity (.failed fault) state.control.store state.cells state.liveRegions outside)
      | _ => none
    | _ => none

  | .unwind runtime future => match future with
    | .push (.cleanupReturn identity original exit) outside =>
      let combined := match runtime.exit.primary with
        | .failure fault => exit.nestedFailure fault runtime.exit.failures runtime.exit.cancellation
        | _ => exit.nestedAbandon runtime.exit
      (finalizeCleanup original combined).map
        (reenterCleanupResult identity .abandoned runtime.store runtime.cells runtime.liveRegions outside)
    | _ => none

/-- Failure and cancellation enter cleanup beneath the actual ambient context,
with the original exit in the running frame and fresh body diagnostics. -/
def beginAbruptCleanup (resolution : Resolution signature algebra program result) :
    Option (Resolution signature algebra program result) :=
  match resolution with
  | .reenter state diagnostics => match state.control.configuration with
    | .failed fault future => match future with
      | .push (.protection identity cleanup captured) outside =>
        let original : ExitInfo algebra.Fault algebra.Reason := ⟨.failure fault, diagnostics.failures, diagnostics.cancellation⟩
        some (.reenter ⟨⟨state.control.store, .code cleanup (.cons (.exit original) captured) .nil
          (.push (.cleanupReturn identity none original) outside)⟩, state.cells, state.liveRegions⟩ ⟨.normal, [], none⟩)
      | _ => none
    | _ => none
  | .unwind runtime future => match future with
    | .push (.protection identity cleanup captured) outside =>
      some (.reenter ⟨⟨runtime.store, .code cleanup (.cons (.exit runtime.exit) captured) .nil
        (.push (.cleanupReturn identity none runtime.exit) outside)⟩, runtime.cells, runtime.liveRegions⟩ ⟨.normal, [], none⟩)
    | _ => none

structure CleanupControlDisposal (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  type : TypeOf signature
  outside : Target.Stack signature algebra program type result
  frame : Id .obligation
  completion : Completion algebra.Fault
  disposal : Target.Disposal signature algebra program .unit

/-- A returned one-shot continuation is disposed through its real authority
and saved future. Its input type need not have an inhabitant. -/
def CleanupDisposal.beginControl (work : CleanupDisposal signature algebra program result) :
    Option (CleanupControlDisposal signature algebra program result) :=
  match work with
  | ⟨type, value, runtime, outside⟩ => match runtime.phase with
    | .finished completion => match value with
      | .continuation identity (some (authority, owner)) =>
        (UseScope.disposeOwned ⟨identity, authority, owner⟩ runtime.store).map fun acquired =>
          ⟨_, outside, runtime.id, completion,
            ⟨acquired.future.fst.answer, .seeking
              ⟨runtime.id, .finished .abandoned, acquired.store, runtime.cells, runtime.liveRegions, runtime.exit⟩
              acquired.future.snd.future, .done⟩⟩
      | _ => none
    | _ => none

/-- Read the raw completed unwind rather than converting abandonment into the
unit result of an ordinary dispose expression. The enclosing exit must survive. -/
def CleanupControlDisposal.finish (work : CleanupControlDisposal signature algebra program result) :
    Option (CompletedCleanup signature algebra program result) :=
  match work.disposal.progress with
  | .complete runtime => some (reenterCleanupResult work.frame work.completion runtime.store runtime.cells runtime.liveRegions
      work.outside (.exiting runtime.exit))
  | _ => none

inductive CleanupFrameProgress (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) (result : TypeOf signature) where
  | running : Resolution signature algebra program result → CleanupFrameProgress signature algebra program result
  | disposing : CleanupDisposal signature algebra program result → CleanupFrameProgress signature algebra program result
  | control : CleanupControlDisposal signature algebra program result → CleanupFrameProgress signature algebra program result

def CompletedCleanup.progress : CompletedCleanup signature algebra program result → CleanupFrameProgress signature algebra program result
  | .resolved resolution => .running resolution
  | .disposing work => .disposing work

variable [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

/-- Boundary transitions preserve complete exit records; ordinary target work
continues in the actual context. Control disposal reuses its existing driver. -/
inductive CleanupFrameStep (table : Target.Definitions signature algebra program) :
    CleanupFrameProgress signature algebra program result → CleanupFrameProgress signature algebra program result → Prop where
  | execute : Target.ExecutionStep table before after →
      CleanupFrameStep table (.running (.reenter before diagnostics)) (.running (.reenter after diagnostics))
  | begin : beginAbruptCleanup before = some after → CleanupFrameStep table (.running before) (.running after)
  | advance : advanceFailedResolution before = some after → CleanupFrameStep table (.running before) (.running after)
  | finish : finishCleanupFrame before = some after → CleanupFrameStep table (.running before) after.progress
  | cancel : before.cancelRunning reason = some after → CleanupFrameStep table (.running before) (.running after)
  | enterControl : work.beginControl = some after → CleanupFrameStep table (.disposing work) (.control after)
  | dispose {before after : Target.Disposal signature algebra program .unit} :
      Target.DisposalStep table before selected after →
      CleanupFrameStep table (.control ⟨type, outside, frame, completion, before⟩) (.control ⟨type, outside, frame, completion, after⟩)
  | disposeNested (scope : ScopeExit signature algebra program answer) :
      NestedSteps table (NestedCleanup.start scope.cleanup) initiations after → after.finished = some runtime →
      CleanupFrameStep table
        (.control ⟨type, outside, frame, completion, ⟨answer, .cleaning scope, .done⟩⟩)
        (.control ⟨type, outside, frame, completion, ⟨answer, .cleaning ⟨runtime, scope.resume⟩, .done⟩⟩)
  | finishControl : work.finish = some after → CleanupFrameStep table (.control work) after.progress

inductive CleanupFrameSteps (table : Target.Definitions signature algebra program) :
    CleanupFrameProgress signature algebra program result → Nat → CleanupFrameProgress signature algebra program result → Prop where
  | refl : CleanupFrameSteps table state 0 state
  | cons : CleanupFrameStep table before middle → CleanupFrameSteps table middle count after → CleanupFrameSteps table before (count + 1) after

theorem owned_cleanup_result_cannot_skip_disposal
    {table : Target.Definitions signature algebra program} {work : CleanupDisposal signature algebra program result}
    {resolution : Resolution signature algebra program result} :
    ¬ CleanupFrameStep table (.disposing work) (.running resolution) := by intro step; cases step

end ExitComposition
end BoundaryV2.Generalized
