import BoundaryV2.GeneralizedUnwinding
import BoundaryV2.GeneralizedScopedRegions

namespace BoundaryV2.Generalized

namespace ExitInfo

/-- An enclosing cleanup fails with the nested computation's primary fault,
followed by that computation's own cleanup failures. Equal faults remain
separate occurrences. Existing failure precedence and cancellation survive. -/
def nestedFailure (fault : Fault) (failures : List Fault) (reason : Option Reason)
    (exit : ExitInfo Fault Reason) : ExitInfo Fault Reason :=
  { exit.cleanupFailure fault with
    failures := exit.failures ++ fault :: failures
    cancellation := exit.cancellation.or reason }

def nestedAbandon (inner : ExitInfo Fault Reason) (exit : ExitInfo Fault Reason) : ExitInfo Fault Reason :=
  let reason := exit.cancellation.or inner.cancellation
  { primary := match exit.primary with
      | .failure fault => .failure fault
      | _ => if reason.isSome then .cancelled else inner.primary
    failures := exit.failures ++ inner.failures
    cancellation := reason }

theorem nested_failure_order (fault : Fault) (failures : List Fault) (reason : Option Reason)
    (exit : ExitInfo Fault Reason) :
    (exit.nestedFailure fault failures reason).failures = exit.failures ++ [fault] ++ failures := by
  simp only [nestedFailure, List.append_assoc, List.singleton_append]

theorem nested_failure_keeps_original (original fault : Fault) (before after : List Fault)
    (first later : Option Reason) :
    (nestedFailure fault after later ⟨.failure original, before, first⟩).primary = .failure original := rfl

end ExitInfo

namespace ExitComposition

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

/-- Resource state is stored once for the whole nested execution. Saved
parents contain continuations and exit records, never older heap snapshots. -/
structure CleanupMemory (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) where
  store : Target.ControlHeap signature algebra program
  cells : Cells signature algebra (fun context result => Target.Code signature algebra program context [] result)
  regions : List (Id .region)

structure CleanupInfo (Fault Reason : Type) where
  id : Id .obligation
  exit : ExitInfo Fault Reason

structure CleanupDiagnostics (Fault Reason : Type) where
  failures : List Fault := []
  cancellation : Option Reason := none

inductive CleanupFocus (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) where
  | executing : Phase signature algebra program → CleanupDiagnostics algebra.Fault algebra.Reason → CleanupFocus signature algebra program
  | unwinding {input : TypeOf signature} : ExitInfo algebra.Fault algebra.Reason →
      Target.Stack signature algebra program input .unit → CleanupFocus signature algebra program

structure CleanupParent (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) where
  info : CleanupInfo algebra.Fault algebra.Reason
  resume : ResumePoint signature algebra program .unit

structure NestedCleanup (signature : Signature) (algebra : LeafAlgebra signature.Data)
    (program : List (BodyType signature.Data signature.Effect)) where
  memory : CleanupMemory signature algebra program
  current : CleanupInfo algebra.Fault algebra.Reason
  focus : CleanupFocus signature algebra program
  parents : List (CleanupParent signature algebra program)

def CleanupMemory.ofRuntime (runtime : Runtime signature algebra program) : CleanupMemory signature algebra program :=
  ⟨runtime.store, runtime.cells, runtime.liveRegions⟩

def CleanupInfo.ofRuntime (runtime : Runtime signature algebra program) : CleanupInfo algebra.Fault algebra.Reason :=
  ⟨runtime.id, runtime.exit⟩

def CleanupInfo.runtime (info : CleanupInfo algebra.Fault algebra.Reason) (phase : Phase signature algebra program)
    (memory : CleanupMemory signature algebra program) : Runtime signature algebra program :=
  ⟨info.id, phase, memory.store, memory.cells, memory.regions, info.exit⟩

def NestedCleanup.start (runtime : Runtime signature algebra program) : NestedCleanup signature algebra program :=
  ⟨CleanupMemory.ofRuntime runtime, CleanupInfo.ofRuntime runtime, .executing runtime.phase ⟨[], none⟩, []⟩

def NestedCleanup.push (machine : NestedCleanup signature algebra program)
    (child : ScopeExit signature algebra program .unit) : NestedCleanup signature algebra program :=
  ⟨CleanupMemory.ofRuntime child.cleanup, CleanupInfo.ofRuntime child.cleanup,
    .executing child.cleanup.phase ⟨[], none⟩, ⟨machine.current, child.resume⟩ :: machine.parents⟩

/-- The actual protected return/failure cursor supplies the child cleanup and
its saved caller. No separately authored replacement continuation is accepted. -/
def NestedCleanup.enter (machine : NestedCleanup signature algebra program) : Option (NestedCleanup signature algebra program) :=
  match machine.focus with
  | .executing (.running cursor .active) diagnostics =>
    let state : Target.State signature algebra program .unit :=
      ⟨⟨machine.memory.store, cursor⟩, machine.memory.cells, machine.memory.regions⟩
    ((beginReturnedProtection state).or (beginFailedProtection state diagnostics.failures diagnostics.cancellation)).map machine.push
  | _ => none

/-- Completing a cleanup records the current body's entire failure result
once. Its nested failure suffix is consumed here, not appended prematurely
when the inner cleanup returns. -/
def NestedCleanup.complete (machine : NestedCleanup signature algebra program) : Option (NestedCleanup signature algebra program) :=
  match machine.focus with
  | .executing (.running cursor .active) diagnostics =>
    match cursor with
    | .returned (.datum .unit) .done =>
      some { machine with focus := .executing (.finished .returned) ⟨[], none⟩ }
    | .failed fault .done =>
      some { machine with
        current := { machine.current with exit := machine.current.exit.nestedFailure fault diagnostics.failures diagnostics.cancellation }
        focus := .executing (.finished (.failed fault)) ⟨[], none⟩ }
    | _ => none
  | _ => none

/-- Restore the parent's caller using the child's current resource state.
Cancellation/abandonment retain an unwind continuation rather than inventing
an authored fault or a response value. -/
def NestedCleanup.join (machine : NestedCleanup signature algebra program) : Option (NestedCleanup signature algebra program) :=
  match machine.parents, machine.focus with
  | parent :: rest, .executing phase _ =>
    (finish ⟨machine.current.runtime phase machine.memory, parent.resume⟩).map fun resolution =>
      match resolution with
      | .reenter state exit =>
        ⟨⟨state.control.store, state.cells, state.liveRegions⟩, parent.info,
          .executing (.running state.control.configuration .active) ⟨exit.failures, exit.cancellation⟩, rest⟩
      | .unwind runtime outside =>
        ⟨CleanupMemory.ofRuntime runtime, parent.info, .unwinding runtime.exit outside, rest⟩
  | _, _ => none

def NestedCleanup.advanceUnwind (machine : NestedCleanup signature algebra program) : Option (NestedCleanup signature algebra program) :=
  match machine.focus with
  | .unwinding exit outside =>
    match Target.unwindBoundary outside with
    | .complete =>
      match exit.primary with
      | .normal => none
      | .failure fault => some { machine with
          current := { machine.current with exit := machine.current.exit.nestedFailure fault exit.failures exit.cancellation }
          focus := .executing (.finished (.failed fault)) ⟨[], none⟩ }
      | .cancelled | .abandoned => some { machine with
          current := { machine.current with exit := machine.current.exit.nestedAbandon exit }
          focus := .executing (.finished .abandoned) ⟨[], none⟩ }
    | .protection identity body captured remaining =>
      some (machine.push ⟨⟨identity, .pending ⟨_, body, captured⟩, machine.memory.store,
        machine.memory.cells, machine.memory.regions, exit⟩, .unwind remaining⟩)
    | .region _ _ | .cleanupReturn _ _ _ _ => none
  | _ => none

/-- Abandon the actual installed continuation. Yield wrappers do not conceal
pending protection frames, and an already authored fault retains precedence. -/
def abandonCleanupCursor (diagnostics : CleanupDiagnostics algebra.Fault algebra.Reason) :
    Cursor signature algebra program → (Sigma fun input : TypeOf signature =>
      ExitInfo algebra.Fault algebra.Reason × Target.Stack signature algebra program input .unit)
  | .code _ _ _ outside | .returned _ outside | .requested _ _ _ _ outside =>
    ⟨_, ⟨⟨.abandoned, diagnostics.failures, diagnostics.cancellation⟩, outside⟩⟩
  | .failed fault outside => ⟨_, ⟨⟨.failure fault, diagnostics.failures, diagnostics.cancellation⟩, outside⟩⟩
  | .yielded next => abandonCleanupCursor diagnostics next

def NestedCleanup.abandon (machine : NestedCleanup signature algebra program) : Option (NestedCleanup signature algebra program) :=
  match machine.focus with
  | .executing (.running cursor _) diagnostics =>
    let stopped := abandonCleanupCursor diagnostics cursor
    some { machine with focus := .unwinding stopped.snd.1 stopped.snd.2 }
  | _ => none

def CleanupParent.cancel (reason : algebra.Reason) (parent : CleanupParent signature algebra program) : CleanupParent signature algebra program :=
  { parent with info := { parent.info with exit := parent.info.exit.cancel reason } }

/-- External cancellation targets the outermost running cleanup's exit. Inner
cleanup code continues under its own scope's exit argument, as in the ordinary
source oracle's nested `finishCleanup` interpretation. -/
def cancelOutermostParent (reason : algebra.Reason) : List (CleanupParent signature algebra program) → List (CleanupParent signature algebra program)
  | [] => []
  | parent :: rest => if rest.isEmpty then [parent.cancel reason] else parent :: cancelOutermostParent reason rest

def NestedCleanup.cancel (reason : algebra.Reason) (machine : NestedCleanup signature algebra program) : NestedCleanup signature algebra program :=
  { machine with
    current := if machine.parents.isEmpty then { machine.current with exit := machine.current.exit.cancel reason } else machine.current
    parents := cancelOutermostParent reason machine.parents }

def NestedCleanup.finished (machine : NestedCleanup signature algebra program) : Option (Runtime signature algebra program) :=
  match machine.parents, machine.focus with
  | [], .executing (.finished outcome) _ => some (machine.current.runtime (.finished outcome) machine.memory)
  | _, _ => none

def NestedCleanup.finishScope (resume : ResumePoint signature algebra program result)
    (machine : NestedCleanup signature algebra program) : Option (Resolution signature algebra program result) :=
  machine.finished.bind fun runtime => finish ⟨runtime, resume⟩

def NestedCleanup.closeScopedRegions (wanted : Id .scope) (forest : Scope.Forest) (bindings : RegionBindings)
    (resume : ResumePoint signature algebra program result) (external : List Reference)
    (machine : NestedCleanup signature algebra program) : Option (ScopedRegionExit signature algebra program result) :=
  machine.finished.bind fun runtime => finishScopedRegions wanted forest bindings ⟨runtime, resume⟩ external

def Phase.unfinished : Phase signature algebra program → Bool
  | .finished _ => false
  | .pending _ | .running _ _ => true

def CleanupFocus.right : CleanupFocus signature algebra program → Nat
  | .executing phase _ => phase.right
  | .unwinding _ _ => 0

theorem nested_return_entry_uses_actual_parent
    (memory : CleanupMemory signature algebra program) (info : CleanupInfo algebra.Fault algebra.Reason)
    (value : Target.RuntimeValue signature algebra program input)
    (cleanup : Target.Code signature algebra program (.exit :: context) [] .unit)
    (captured : Target.RuntimeEnvironment signature algebra program context)
    (outside : Target.Stack signature algebra program input .unit)
    (diagnostics : CleanupDiagnostics algebra.Fault algebra.Reason) (parents : List (CleanupParent signature algebra program)) :
    NestedCleanup.enter ⟨memory, info,
      .executing (.running (.returned value (.push (.protection identity cleanup captured) outside)) .active) diagnostics, parents⟩ =
      some ⟨memory, ⟨identity, ⟨.normal, [], none⟩⟩, .executing (.pending ⟨_, cleanup, captured⟩) ⟨[], none⟩,
        ⟨info, .returned value outside⟩ :: parents⟩ := rfl

theorem nested_failure_entry_keeps_body_diagnostics
    (memory : CleanupMemory signature algebra program) (info : CleanupInfo algebra.Fault algebra.Reason)
    (fault : algebra.Fault) (cleanup : Target.Code signature algebra program (.exit :: context) [] .unit)
    (captured : Target.RuntimeEnvironment signature algebra program context)
    (outside : Target.Stack signature algebra program input .unit)
    (diagnostics : CleanupDiagnostics algebra.Fault algebra.Reason) (parents : List (CleanupParent signature algebra program)) :
    NestedCleanup.enter ⟨memory, info,
      .executing (.running (.failed fault (.push (.protection identity cleanup captured) outside)) .active) diagnostics, parents⟩ =
      some ⟨memory, ⟨identity, ⟨.failure fault, diagnostics.failures, diagnostics.cancellation⟩⟩,
        .executing (.pending ⟨_, cleanup, captured⟩) ⟨[], none⟩, ⟨info, .unwind outside⟩ :: parents⟩ := rfl

theorem normal_child_restores_the_typed_parent_return
    (memory : CleanupMemory signature algebra program) (parent : CleanupInfo algebra.Fault algebra.Reason)
    (value : Target.RuntimeValue signature algebra program input)
    (outside : Target.Stack signature algebra program input .unit)
    (parents : List (CleanupParent signature algebra program)) :
    NestedCleanup.join ⟨memory, ⟨child, ⟨.normal, [], none⟩⟩, .executing (.finished .returned) ⟨[], none⟩,
      ⟨parent, .returned value outside⟩ :: parents⟩ =
      some ⟨memory, parent, .executing (.running (.returned value outside) .active) ⟨[], none⟩, parents⟩ := rfl

theorem finish_keeps_current_memory
    (accepted : finish scope = some resolution) :
    resolution.store = scope.cleanup.store ∧ resolution.cells = scope.cleanup.cells ∧ resolution.regions = scope.cleanup.liveRegions := by
  unfold finish at accepted
  split at accepted
  · cases accepted
  · cases accepted
  · split at accepted <;> cases accepted <;> exact ⟨rfl, rfl, rfl⟩

theorem joining_child_uses_current_memory_and_does_not_restart_parent
    (machine after : NestedCleanup signature algebra program) (accepted : machine.join = some after) :
    after.memory = machine.memory ∧ after.focus.right = 0 := by
  unfold NestedCleanup.join at accepted
  split at accepted
  · obtain ⟨resolution, completed, result⟩ := Option.map_eq_some_iff.mp accepted
    have memory := finish_keeps_current_memory completed
    cases resolution <;> cases result
    all_goals
      refine ⟨?_, rfl⟩
      simp only [Resolution.store, Resolution.cells, Resolution.regions, CleanupInfo.runtime] at memory
      rcases memory with ⟨store, cells, regions⟩
      simp only [CleanupMemory.ofRuntime, store, cells, regions]
  · cases accepted

theorem abandonment_preserves_pending_protection_order
    (cursor : Cursor signature algebra program) (diagnostics : CleanupDiagnostics algebra.Fault algebra.Reason) :
    pendingProtections (abandonCleanupCursor diagnostics cursor).snd.2 = cursorProtections cursor := by
  induction cursor <;> simp only [abandonCleanupCursor, cursorProtections, *]

theorem captured_cleanup_cannot_complete
    (memory : CleanupMemory signature algebra program) (info : CleanupInfo algebra.Fault algebra.Reason)
    (cursor : Cursor signature algebra program) (diagnostics : CleanupDiagnostics algebra.Fault algebra.Reason)
    (parents : List (CleanupParent signature algebra program)) (controlId : Id .control) :
    NestedCleanup.complete ⟨memory, info, .executing (.running cursor (.captured controlId)) diagnostics, parents⟩ = none := by
  rfl

theorem pending_or_running_child_cannot_rejoin
    (memory : CleanupMemory signature algebra program) (info : CleanupInfo algebra.Fault algebra.Reason)
    (phase : Phase signature algebra program) (diagnostics : CleanupDiagnostics algebra.Fault algebra.Reason)
    (parents : List (CleanupParent signature algebra program)) (unfinished : phase.unfinished = true) :
    NestedCleanup.join ⟨memory, info, .executing phase diagnostics, parents⟩ = none := by
  cases parents with
  | nil => rfl
  | cons parent rest =>
    cases phase <;> simp only [Phase.unfinished] at unfinished
    all_goals first | contradiction | rfl

theorem nested_parents_prevent_scope_completion
    (memory : CleanupMemory signature algebra program) (info : CleanupInfo algebra.Fault algebra.Reason)
    (focus : CleanupFocus signature algebra program) (parent : CleanupParent signature algebra program)
    (rest : List (CleanupParent signature algebra program)) (resume : ResumePoint signature algebra program result) :
    NestedCleanup.finishScope resume ⟨memory, info, focus, parent :: rest⟩ = none := by
  simp only [NestedCleanup.finishScope, NestedCleanup.finished, Option.bind_none]

theorem nested_parents_prevent_scope_and_region_retirement
    (memory : CleanupMemory signature algebra program) (info : CleanupInfo algebra.Fault algebra.Reason)
    (focus : CleanupFocus signature algebra program) (parent : CleanupParent signature algebra program)
    (rest : List (CleanupParent signature algebra program)) (resume : ResumePoint signature algebra program result) :
    NestedCleanup.closeScopedRegions wanted forest bindings resume external ⟨memory, info, focus, parent :: rest⟩ = none := by
  simp only [NestedCleanup.closeScopedRegions, NestedCleanup.finished, Option.bind_none]

theorem cancel_parent_keeps_first_reason (first later : algebra.Reason) (parent : CleanupParent signature algebra program) :
    (parent.cancel first).cancel later = parent.cancel first := by
  simp only [CleanupParent.cancel, ExitInfo.cancel_keeps_first_reason]

theorem cancelling_parents_preserves_emptiness (reason : algebra.Reason) (parents : List (CleanupParent signature algebra program)) :
    (cancelOutermostParent reason parents).isEmpty = parents.isEmpty := by
  cases parents with
  | nil => rfl
  | cons parent rest => cases rest <;> rfl

theorem cancelling_parents_keeps_first_reason (first later : algebra.Reason) (parents : List (CleanupParent signature algebra program)) :
    cancelOutermostParent later (cancelOutermostParent first parents) = cancelOutermostParent first parents := by
  induction parents with
  | nil => rfl
  | cons parent rest induction =>
    by_cases empty : rest.isEmpty = true
    · simp [cancelOutermostParent, empty, cancel_parent_keeps_first_reason]
    · simp only [cancelOutermostParent, empty, Bool.false_eq_true, if_false, cancelling_parents_preserves_emptiness, induction]

theorem cancellation_keeps_current_cursor_and_memory (reason : algebra.Reason) (machine : NestedCleanup signature algebra program) :
    (machine.cancel reason).focus = machine.focus ∧ (machine.cancel reason).memory = machine.memory := ⟨rfl, rfl⟩

theorem repeated_nested_cancellation (first later : algebra.Reason) (machine : NestedCleanup signature algebra program) :
    (machine.cancel first).cancel later = machine.cancel first := by
  cases machine with
  | mk memory info focus parents =>
    by_cases empty : parents.isEmpty = true
    all_goals simp only [NestedCleanup.cancel, cancelling_parents_preserves_emptiness, empty,
      Bool.false_eq_true, if_true, if_false, cancelling_parents_keeps_first_reason, ExitInfo.cancel_keeps_first_reason]

variable [DecidableEq (ControlShape signature)] [DecidableEq (TypeOf signature)]

/-- Existing ordinary execution and nonterminal lifecycle transitions remain
the local interpreter. Completion and external cancellation are owned by the
nested driver so neither can discard nested diagnostics or target an inner exit. -/
inductive NestedStep (table : Target.Definitions signature algebra program) :
    NestedCleanup signature algebra program → Nat → NestedCleanup signature algebra program → Prop where
  | local (step : RuntimeStep table (info.runtime phase memory) initiations after)
      (sameExit : after.exit = info.exit) (unfinished : after.phase.unfinished = true) :
      NestedStep table ⟨memory, info, .executing phase diagnostics, parents⟩ initiations
        ⟨CleanupMemory.ofRuntime after, CleanupInfo.ofRuntime after, .executing after.phase diagnostics, parents⟩
  | enter : before.enter = some after → NestedStep table before 0 after
  | complete : before.complete = some after → NestedStep table before 0 after
  | join : before.join = some after → NestedStep table before 0 after
  | unwind : before.advanceUnwind = some after → NestedStep table before 0 after
  | abandon : before.abandon = some after → NestedStep table before 0 after
  | cancel : NestedStep table before 0 (before.cancel reason)

inductive NestedSteps (table : Target.Definitions signature algebra program) :
    NestedCleanup signature algebra program → Nat → NestedCleanup signature algebra program → Prop where
  | refl : NestedSteps table state 0 state
  | cons : NestedStep table before count middle → NestedSteps table middle rest after → NestedSteps table before (count + rest) after

theorem NestedSteps.trans {table : Target.Definitions signature algebra program}
    {before middle after : NestedCleanup signature algebra program}
    (first : NestedSteps table before count middle) (second : NestedSteps table middle rest after) :
    NestedSteps table before (count + rest) after := by
  induction first with
  | refl => simpa only [Nat.zero_add] using second
  | cons step tail induction => simpa only [Nat.add_assoc] using NestedSteps.cons step (induction second)

theorem nested_single_execution {table : Target.Definitions signature algebra program}
    {before after : Target.State signature algebra program .unit}
    (step : Target.ExecutionStep table before after)
    (info : CleanupInfo algebra.Fault algebra.Reason) (diagnostics : CleanupDiagnostics algebra.Fault algebra.Reason)
    (parents : List (CleanupParent signature algebra program)) :
    NestedStep table
      ⟨⟨before.control.store, before.cells, before.liveRegions⟩, info, .executing (.running before.control.configuration .active) diagnostics, parents⟩ 0
      ⟨⟨after.control.store, after.cells, after.liveRegions⟩, info, .executing (.running after.control.configuration .active) diagnostics, parents⟩ :=
  .local (after := info.runtime (.running after.control.configuration .active) ⟨after.control.store, after.cells, after.liveRegions⟩)
    (.execute step) rfl rfl

/-- Every existing finite ordinary target run can execute inside the current
cleanup without touching suspended parents or losing its body diagnostics. -/
theorem nested_target_execution {table : Target.Definitions signature algebra program}
    {before after : Target.State signature algebra program .unit}
    (steps : Target.ExecutionSteps table before count after)
    (info : CleanupInfo algebra.Fault algebra.Reason) (diagnostics : CleanupDiagnostics algebra.Fault algebra.Reason)
    (parents : List (CleanupParent signature algebra program)) :
    NestedSteps table
      ⟨⟨before.control.store, before.cells, before.liveRegions⟩, info, .executing (.running before.control.configuration .active) diagnostics, parents⟩ 0
      ⟨⟨after.control.store, after.cells, after.liveRegions⟩, info, .executing (.running after.control.configuration .active) diagnostics, parents⟩ := by
  induction steps with
  | refl => exact .refl
  | cons step tail induction => exact .cons (nested_single_execution step info diagnostics parents) induction

end ExitComposition
end BoundaryV2.Generalized
