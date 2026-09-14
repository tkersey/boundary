import BoundaryV2.GeneralizedDisposal
import BoundaryV2.GeneralizedPackages
import BoundaryV2.GeneralizedComputationHandoff

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {Body Before After : List (TypeOf signature) → TypeOf signature → Type}

def Environment.disposalValues : {types : List (TypeOf signature)} → Environment signature algebra Body types →
    List (Sigma (Value signature algebra Body))
  | _, .nil => []
  | _, .cons value rest => ⟨_, value⟩ :: rest.disposalValues

def Value.hasActiveRoot (fields : UseScope.State) (value : Value signature algebra Body type) : Bool :=
  value.roots.any fun (token, owner) => (UseScope.takeGrant token owner (UseScope.activeFields fields.active)).isSome

theorem Value.roots_map (transform : ∀ context type, Before context type → After context type)
    (value : Value signature algebra Before type) : (value.map transform).roots = value.roots := by
  cases value with
  | datum | closure | continuation | package | cell | exit => rfl
  | pair first second => simp only [Value.map, Value.roots, roots_map transform first, roots_map transform second]
  | left value | right value => exact roots_map transform value
termination_by sizeOf value

theorem Value.active_root_check_commutes (transform : ∀ context type, Before context type → After context type)
    (fields : UseScope.State) (value : Value signature algebra Before type) :
    (value.map transform).hasActiveRoot fields = value.hasActiveRoot fields := by
  simp only [Value.hasActiveRoot, Value.roots_map]

theorem Environment.disposal_values_map (transform : ∀ context type, Before context type → After context type)
    (values : Environment signature algebra Before types) :
    (values.map transform).disposalValues = values.disposalValues.map (fun value => ⟨value.fst, value.snd.map transform⟩) := by
  cases values with
  | nil => rfl
  | cons value rest => simp only [Environment.map, Environment.disposalValues, List.map_cons, disposal_values_map transform rest]
termination_by sizeOf values

namespace ExitComposition

variable {program : List (BodyType signature.Data signature.Effect)}

abbrev DisposalValues (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) := List (Sigma (Target.RuntimeValue signature algebra program))

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

mutual
  /-- Queue entries are views. The current runtime, or the active control
  disposal, owns all physical fields. No older resource snapshot is retained. -/
  inductive ValueDisposal (signature : Signature) (algebra : LeafAlgebra signature.Data)
      (program : List (BodyType signature.Data signature.Effect)) where
    | ready : Runtime signature algebra program → DisposalValues signature algebra program → ValueDisposal signature algebra program
    | control {answer : TypeOf signature} : ControlProgress signature algebra program answer →
        DisposalValues signature algebra program → ValueDisposal signature algebra program

  /-- Only the active phase owns the runtime. A value disposal keeps the region
  identity, outside continuation, and offered-cell names, not a heap snapshot. -/
  inductive RegionDisposal (signature : Signature) (algebra : LeafAlgebra signature.Data)
      (program : List (BodyType signature.Data signature.Effect)) : TypeOf signature → Type where
    | offering {input : TypeOf signature} : RegionHandoff signature algebra program input result → RegionDisposal signature algebra program result
    | disposing {input : TypeOf signature} : Id .region → Target.Stack signature algebra program input result →
        List (Id .cell) → ValueDisposal signature algebra program → RegionDisposal signature algebra program result

  inductive CleanupFrameProgress (signature : Signature) (algebra : LeafAlgebra signature.Data)
      (program : List (BodyType signature.Data signature.Effect)) : TypeOf signature → Type where
    | running : Resolution signature algebra program result → CleanupFrameProgress signature algebra program result
    | parked : Resolution signature algebra program result → CleanupFrameProgress signature algebra program result
    | captured : Id .control → Resolution signature algebra program result → CleanupFrameProgress signature algebra program result
    | disposing : CleanupDisposal signature algebra program result → CleanupFrameProgress signature algebra program result
    | region : RegionDisposal signature algebra program result → CleanupFrameProgress signature algebra program result
    | values {input : TypeOf signature} : Id .obligation → Completion algebra.Fault →
        Target.Stack signature algebra program input result → ValueDisposal signature algebra program →
        CleanupFrameProgress signature algebra program result
  /-- The frame driver owns the abandoned future. A returned handler answer
  is disposed through the same value queue before the operation can finish. -/
  inductive ControlProgress (signature : Signature) (algebra : LeafAlgebra signature.Data)
      (program : List (BodyType signature.Data signature.Effect)) : TypeOf signature → Type where
    | frames : Id .obligation → CleanupFrameProgress signature algebra program answer → ControlProgress signature algebra program answer
    | returnedValue : ValueDisposal signature algebra program → ControlProgress signature algebra program answer
    | complete : Runtime signature algebra program → ControlProgress signature algebra program answer

end

def ValueDisposal.start (runtime : Runtime signature algebra program) (value : Target.RuntimeValue signature algebra program type) :
    ValueDisposal signature algebra program := .ready runtime [⟨type, value⟩]

def ValueDisposal.finished : ValueDisposal signature algebra program → Option (Runtime signature algebra program)
  | .ready runtime [] => some runtime
  | _ => none

def RegionDisposal.begin (resolution : Resolution signature algebra program result) :
    Option (RegionDisposal signature algebra program result) :=
  if !resolution.cleanupFinished then none else
  match resolution with
  | .unwind runtime future => match Target.unwindBoundary future with
    | .region identity outside => some (.offering (beginRegionHandoff identity runtime outside))
    | _ => none
  | _ => none

def RegionDisposal.offer : RegionDisposal signature algebra program result → Option (RegionDisposal signature algebra program result)
  | .offering handoff =>
    if !(Resolution.unwind handoff.runtime handoff.outside).cleanupFinished then none else
    handoff.offerNext.map fun (value, after) =>
      .disposing after.identity after.outside after.kept (ValueDisposal.start after.runtime value.snd)
  | _ => none

def RegionDisposal.returnValue : RegionDisposal signature algebra program result → Option (RegionDisposal signature algebra program result)
  | .disposing identity outside kept work => work.finished.map fun runtime => .offering ⟨identity, runtime, outside, kept⟩
  | _ => none

theorem unfinished_cleanup_cannot_offer_region_cells
    (handoff : RegionHandoff signature algebra program input result)
    (unfinished : (Resolution.unwind handoff.runtime handoff.outside).cleanupFinished = false) :
    RegionDisposal.offer (.offering handoff) = none := by
  change (if !(Resolution.unwind handoff.runtime handoff.outside).cleanupFinished then none else _) = none
  simp only [unfinished, Bool.not_false, if_true]

/-- An exhausted offer loop does not itself authorize retirement. The existing
retirement operation checks completion, physical fields, and all surviving roots. -/
def RegionDisposal.finish (external : List Reference) :
    RegionDisposal signature algebra program result → Option (Resolution signature algebra program result)
  | .offering handoff =>
    if handoff.offerNext.isNone then (Resolution.unwind handoff.runtime handoff.outside).retireRegions [handoff.identity] external
    else none
  | _ => none


end ExitComposition
end BoundaryV2.Generalized

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
  if !resolution.cleanupFinished then none else
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
  if !resolution.cleanupFinished then none else
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

theorem unfinished_cleanup_cannot_cross_outer_boundaries
    (resolution : Resolution signature algebra program result)
    (unfinished : resolution.cleanupFinished = false) :
    finishCleanupFrame resolution = none ∧ beginAbruptCleanup resolution = none ∧
      RegionDisposal.begin resolution = none ∧ followUnwindResolution resolution = none := by
  simp only [finishCleanupFrame, beginAbruptCleanup, RegionDisposal.begin,
    followUnwindResolution, unfinished, Bool.not_false, if_true, and_self]

def CompletedCleanup.progress : CompletedCleanup signature algebra program result → CleanupFrameProgress signature algebra program result
  | .resolved resolution => .running resolution
  | .disposing work => .disposing work


/-- Discard only ordinary caller/handler frames while seeking the next actual
exit boundary. The remaining enclosing context stays attached to cleanup. -/
def advanceUnwindResolution (resolution : Resolution signature algebra program result) :
    Option (Resolution signature algebra program result) :=
  if !resolution.cleanupFinished then none else
  match resolution with
  | .unwind runtime (.push frame outside) => match frame with
    | .returnTo _ _ _ | .handler _ _ _ _ _ _ => some (.unwind runtime outside)
    | _ => none
  | _ => none

def ControlProgress.seeking (runtime : Runtime signature algebra program)
    (future : Target.Stack signature algebra program input answer) : ControlProgress signature algebra program answer :=
  .frames runtime.id (.running (.unwind runtime future))

/-- This terminal view does not consume a returned answer. The control
transition hands that value to actual disposal before publishing completion. -/
def ControlProgress.terminal (identity : Id .obligation)
    (resolution : Resolution signature algebra program answer) :
    Option (Runtime signature algebra program × Option (Sigma (Target.RuntimeValue signature algebra program))) :=
  if !resolution.cleanupFinished then none else
  match resolution with
  | .unwind runtime .done => some (runtime, none)
  | .reenter state diagnostics => match state.control.configuration with
    | .returned value .done => some
        (⟨identity, .finished .returned, state.control.store, state.cells, state.liveRegions, diagnostics⟩, some ⟨_, value⟩)
    | .failed fault .done => some
        (⟨identity, .finished (.failed fault), state.control.store, state.cells, state.liveRegions,
          { diagnostics with primary := .failure fault }⟩, none)
    | _ => none
  | _ => none

def ControlProgress.finishFrames : ControlProgress signature algebra program answer → Option (ControlProgress signature algebra program answer)
  | .frames identity (.running resolution) => (ControlProgress.terminal identity resolution).map fun (runtime, value) =>
      match value with
      | none => .complete runtime
      | some value => .returnedValue (ValueDisposal.start runtime value.snd)
  | _ => none

/-- A handler's answer is distinct from disposal's unit result. Its actual
value enters disposal even when it contains owned control or resources. -/
theorem control_answer_enters_actual_value_disposal
    (identity : Id .obligation) (store : Target.ControlHeap signature algebra program)
    (cells : Cells signature algebra (fun context result => Target.Code signature algebra program context [] result))
    (regions : List (Id .region)) (diagnostics : ExitInfo algebra.Fault algebra.Reason)
    (value : Target.RuntimeValue signature algebra program answer) :
    ControlProgress.finishFrames (.frames identity (.running (.reenter
      ⟨⟨store, .returned value .done⟩, cells, regions⟩ diagnostics))) =
      some (.returnedValue (ValueDisposal.start
        ⟨identity, .finished .returned, store, cells, regions, diagnostics⟩ value)) := rfl

end ExitComposition
end BoundaryV2.Generalized
