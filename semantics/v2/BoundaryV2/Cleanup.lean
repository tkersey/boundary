import BoundaryV2.Custody

namespace BoundaryV2.Profile.Cleanup

inductive Primary (space : Space) where
  | normal : Value space → Primary space
  | failure : Value space → Primary space
  | cancellation | abandoned

structure Exit (space : Space) where
  primary : Primary space
  failures : List (Value space) := []
  cancellation : Option Protocol.Reason := none

def cancel (exit : Exit space) (reason : Protocol.Reason) : Exit space :=
  { exit with
    primary := match exit.primary with
      | .normal _ | .abandoned => .cancellation
      | other => other
    cancellation := exit.cancellation.or (some reason) }

def recordFailure (exit : Exit space) (failure : Value space) (nested : List (Value space)) : Exit space :=
  { exit with
    primary := match exit.primary with
      | .normal _ | .abandoned => .failure failure
      | other => other
    failures := exit.failures ++ [failure] ++ nested }

theorem cancellation_preserves_primary_failure (exit : Exit space) (value : Value space)
    (primary : exit.primary = .failure value) (reason : Protocol.Reason) :
    (cancel exit reason).primary = .failure value := by simp [cancel, primary]

theorem first_cancellation_preserved (exit : Exit space) (first next : Protocol.Reason)
    (existing : exit.cancellation = some first) : (cancel exit next).cancellation = some first := by
  simp [cancel, existing]

theorem repeated_cancellation_idempotent (exit : Exit space) (first next : Protocol.Reason) :
    cancel (cancel exit first) next = cancel exit first := by
  cases exit with
  | mk primary failures cancellation => cases primary <;> cases cancellation <;> rfl

theorem cleanup_failure_preserves_primary_failure (exit : Exit space) (primary failure : Value space)
    (existing : exit.primary = .failure primary) (nested : List (Value space)) :
    (recordFailure exit failure nested).primary = .failure primary := by simp [recordFailure, existing]

theorem cleanup_failures_keep_order (exit : Exit space) (first second : Value space)
    (innerFirst innerSecond : List (Value space)) :
    (recordFailure (recordFailure exit first innerFirst) second innerSecond).failures =
      exit.failures ++ [first] ++ innerFirst ++ [second] ++ innerSecond := rfl

inductive Phase (space : Space) where
  | pending
  | running : InvocationId → Phase space
  | completed
  | failed : Value space → Phase space

def Phase.rank : Phase space → Nat
  | .pending => 0 | .running _ => 1 | .completed | .failed _ => 2

structure Obligation (space : Space) where
  id : ObligationId
  scope : LexicalScopeId
  creation : Nat
  cleanup : Value space
  resource : Option (Value space)
  phase : Phase space := .pending

inductive Event where
  | started : ObligationId → InvocationId → Event
  | completed : ObligationId → Event
  | failed : ObligationId → Event
  deriving DecidableEq, Repr

def begin (obligation : Obligation space) (invocation : InvocationId) : Option (Obligation space × List Event) :=
  match obligation.phase with
  | .pending => some ({ obligation with phase := .running invocation }, [.started obligation.id invocation])
  | .running _ | .completed | .failed _ => none

def complete (obligation : Obligation space) (invocation : InvocationId)
    (result : Except (Value space) Unit) : Option (Obligation space × List Event) :=
  match obligation.phase with
  | .running active =>
    if active == invocation then match result with
      | .ok () => some ({ obligation with phase := .completed }, [.completed obligation.id])
      | .error value => some ({ obligation with phase := .failed value }, [.failed obligation.id])
    else none
  | .pending | .completed | .failed _ => none

/-- Yielding and parked cleanup preserve the current lifecycle and holdings.
The request machine, not this projection, determines request occurrences. -/
def suspend (obligation : Obligation space) : Obligation space × List Event := (obligation, [])

inductive Step : Obligation space → List Event → Obligation space → Prop where
  | start : begin before invocation = some (after, events) → Step before events after
  | finish : complete before invocation result = some (after, events) → Step before events after
  | suspended : Step obligation [] obligation

theorem begin_advances_once (before after : Obligation space) (invocation : InvocationId) (events : List Event)
    (accepted : begin before invocation = some (after, events)) :
    before.phase.rank = 0 ∧ after.phase.rank = 1 ∧
    after.cleanup = before.cleanup ∧ after.resource = before.resource ∧
    after.id = before.id ∧ events = [.started before.id invocation] := by
  unfold begin at accepted
  split at accepted
  · rename_i phase
    cases accepted
    simp [phase, Phase.rank]
  · cases accepted
  · cases accepted
  · cases accepted

theorem complete_advances_once (before after : Obligation space) (invocation : InvocationId)
    (result : Except (Value space) Unit) (events : List Event)
    (accepted : complete before invocation result = some (after, events)) :
    before.phase.rank = 1 ∧ after.phase.rank = 2 ∧ after.id = before.id := by
  unfold complete at accepted
  split at accepted
  · rename_i active phase
    split at accepted
    · cases result with
      | ok resultValue => cases resultValue; cases accepted; simp [phase, Phase.rank]
      | error value => cases accepted; simp [phase, Phase.rank]
    · cases accepted
  · cases accepted
  · cases accepted
  · cases accepted

theorem step_rank_monotone (step : Step before events after) : before.phase.rank ≤ after.phase.rank := by
  cases step with
  | start accepted =>
    have both := begin_advances_once _ _ _ _ accepted
    omega
  | finish accepted =>
    have both := complete_advances_once _ _ _ _ _ accepted
    omega
  | suspended => exact Nat.le_refl _

theorem started_obligation_cannot_start_again (before after : Obligation space)
    (first second : InvocationId) (events : List Event)
    (accepted : begin before first = some (after, events)) : begin after second = none := by
  unfold begin at accepted
  split at accepted
  · cases accepted; rfl
  · cases accepted
  · cases accepted
  · cases accepted

inductive Path : Obligation space → List Event → Obligation space → Prop where
  | nil : Path obligation [] obligation
  | cons : Step before first middle → Path middle rest after → Path before (first ++ rest) after

theorem path_rank_monotone (path : Path before events after) : before.phase.rank ≤ after.phase.rank := by
  induction path with
  | nil => exact Nat.le_refl _
  | cons step _ induction => exact Nat.le_trans (step_rank_monotone step) induction

theorem start_requires_zero_rank (obligation : Obligation space) (invocation : InvocationId)
    (positive : 0 < obligation.phase.rank) : begin obligation invocation = none := by
  cases phase : obligation.phase <;> simp_all [begin, Phase.rank]

theorem no_second_start_on_trajectory (before started later : Obligation space)
    (first second : InvocationId) (events rest : List Event)
    (accepted : begin before first = some (started, events)) (path : Path started rest later) :
    begin later second = none := by
  have startRank := (begin_advances_once _ _ _ _ accepted).2.1
  have laterRank := path_rank_monotone path
  exact start_requires_zero_rank later second (by omega)

theorem terminal_cleanup_cannot_complete_again (obligation : Obligation space)
    (invocation : InvocationId) (result : Except (Value space) Unit)
    (terminal : obligation.phase.rank = 2) : complete obligation invocation result = none := by
  cases phase : obligation.phase <;> simp_all [complete, Phase.rank]

/-- Scope order is innermost first. Each scope's obligations retain creation
order; cancellation does not sort by resource value or failure payload. -/
def unwindOrder (scopes : List (List (Obligation space))) : List (Obligation space) := scopes.flatten

theorem inner_scope_before_outer (inner outer : List (Obligation space)) :
    unwindOrder [inner, outer] = inner ++ outer := by simp [unwindOrder]

end BoundaryV2.Profile.Cleanup
