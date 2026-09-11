import BoundaryV2.SourceMachine

namespace BoundaryV2.Profile.Source.Machine

theorem active_obligation_cannot_begin_again (state : State) (context : Context)
    (identity : ObligationId) (exit : Cleanup.Exit .source) (normal : Option Located)
    (tail : List Frame) (obligation : Cleanup.Obligation .source)
    (found : state.heap.obligations[identity.value]? = some obligation)
    (same : obligation.id = identity) (started : 0 < obligation.phase.rank) :
    beginCleanup state context identity exit normal tail = .error .custody := by
  have rejected := Cleanup.start_requires_zero_rank obligation ⟨state.heap.nextInvocation⟩ started
  simp [beginCleanup, found, same, rejected, fromOption, require, bind, Except.bind]

theorem terminal_obligation_cannot_record_another_failure (state : State)
    (identity : ObligationId) (invocation : InvocationId) (outer inner : Cleanup.Exit .source)
    (normal : Option Located) (tail : List Frame) (failure : SemanticValue)
    (obligation : Cleanup.Obligation .source)
    (failed : inner.primary = .failure failure)
    (found : state.heap.obligations[identity.value]? = some obligation)
    (terminal : obligation.phase.rank = 2) :
    cleanupFailed state identity invocation outer normal tail inner = .error .custody := by
  have rejected := Cleanup.terminal_cleanup_cannot_complete_again obligation invocation (.error failure) terminal
  simp [cleanupFailed, failed, found, rejected, fromOption, bind, Except.bind]

theorem merge_cleanup_failure_preserves_primary (outer inner : Cleanup.Exit .source)
    (primary : SemanticValue) (existing : outer.primary = .failure primary) :
    (mergeAbrupt outer inner).primary = .failure primary := by
  cases innerPrimary : inner.primary <;> cases cancellation : inner.cancellation <;>
    simp [mergeAbrupt, innerPrimary, cancellation, Cleanup.recordFailure, Cleanup.cancel, existing]

theorem merge_cleanup_failure_keeps_order (outer inner : Cleanup.Exit .source)
    (failure : SemanticValue) (failed : inner.primary = .failure failure) :
    (mergeAbrupt outer inner).failures = outer.failures ++ [failure] ++ inner.failures := by
  cases cancellation : inner.cancellation <;>
    simp [mergeAbrupt, failed, cancellation, Cleanup.recordFailure, Cleanup.cancel]

theorem merge_cleanup_failure_keeps_first_cancellation (outer inner : Cleanup.Exit .source)
    (first : Protocol.Reason) (existing : outer.cancellation = some first) :
    (mergeAbrupt outer inner).cancellation = some first := by
  cases innerPrimary : inner.primary <;> cases cancellation : inner.cancellation <;>
    simp [mergeAbrupt, innerPrimary, cancellation, Cleanup.recordFailure, Cleanup.cancel, existing]

theorem cancellation_of_parked_cleanup_preserves_custody_and_control
    (state : State) (context : Context) (request : Request) (reason : Protocol.Reason)
    (parked : state.status = .parked request) (first : state.cancellation = none)
    (cleanup : cleanupRunning state = true)
    (valid : match reason with | .text bytes => Profile.UTF8.valid bytes = true | .bytes _ => True) :
    external state context (.cancel reason) = .ok
      ⟨{ state with cancellation := some reason }, [.requestRebound request.occurrence]⟩ := by
  cases reason <;> simp [external, parked, first, cleanup, valid, require, bind, Except.bind] <;> rfl

theorem cancellation_of_yielded_cleanup_preserves_custody_and_control
    (state : State) (context : Context) (reason : Protocol.Reason)
    (yielded : state.status = .yielded) (first : state.cancellation = none)
    (cleanup : cleanupRunning state = true)
    (valid : match reason with | .text bytes => Profile.UTF8.valid bytes = true | .bytes _ => True) :
    external state context (.cancel reason) = .ok ⟨{ state with cancellation := some reason }, []⟩ := by
  cases reason <;> simp [external, yielded, first, cleanup, valid, require, bind, Except.bind] <;> rfl

theorem running_cleanup_cancellation_does_not_restart_unwind
    (state : State) (context : Context) (reason : Protocol.Reason)
    (running : state.status = .running) (first : state.cancellation = none)
    (cleanup : cleanupRunning state = true)
    (valid : match reason with | .text bytes => Profile.UTF8.valid bytes = true | .bytes _ => True) :
    external state context (.cancel reason) = .ok ⟨{ state with cancellation := some reason }, []⟩ := by
  cases reason <;> simp [external, running, first, cleanup, valid, require, bind, Except.bind] <;> rfl

/-- The obligation record identifies running cleanup even when its continuation
is held by an effect clause instead of the active stack. -/
theorem cleanup_running_of_obligation (state : State) (identity : ObligationId)
    (obligation : Cleanup.Obligation .source) (invocation : InvocationId)
    (found : state.heap.obligations[identity.value]? = some obligation)
    (running : obligation.phase = .running invocation) : cleanupRunning state = true := by
  apply List.any_eq_true.mpr
  exact ⟨obligation, List.mem_of_getElem? found, by simp [running]⟩

/-- Cancellation records its first reason and preserves the running logical
cleanup, regardless of where its return continuation is represented. No
termination assumption or scan of captured heap frames is needed. -/
theorem cancellation_waits_for_running_obligation (state : State) (context : Context)
    (identity : ObligationId) (obligation : Cleanup.Obligation .source) (invocation : InvocationId)
    (reason : Protocol.Reason) (found : state.heap.obligations[identity.value]? = some obligation)
    (running : obligation.phase = .running invocation) (first : state.cancellation = none)
    (active : match state.status with | .running | .yielded | .parked _ => True | _ => False)
    (valid : match reason with | .text bytes => Profile.UTF8.valid bytes = true | .bytes _ => True) :
    external state context (.cancel reason) = .ok ⟨{state with cancellation := some reason},
      match state.status with | .parked request => [.requestRebound request.occurrence] | _ => []⟩ := by
  have cleanup := cleanup_running_of_obligation _ _ _ _ found running
  cases phase : state.status <;> simp only [phase] at active <;> try contradiction
  all_goals cases reason <;> simp [external, phase, first, cleanup, valid, require, bind, Except.bind] <;> rfl

/-- Pending and finished obligations do not defer ordinary cancellation. -/
theorem cancellation_without_running_cleanup_unwinds (state : State) (context : Context)
    (reason : Protocol.Reason) (first : state.cancellation = none)
    (quiet : ∀ obligation ∈ state.heap.obligations, ∀ invocation, obligation.phase ≠ .running invocation)
    (active : match state.status with | .running | .yielded | .parked _ => True | _ => False)
    (valid : match reason with | .text bytes => Profile.UTF8.valid bytes = true | .bytes _ => True) :
    external state context (.cancel reason) = .ok ⟨{state with
      cancellation := some reason, status := .running, control := cancelControl state.control reason}, []⟩ := by
  have cleanup : cleanupRunning state = false := by
    apply List.any_eq_false.mpr
    intro obligation member checked
    cases phase : obligation.phase <;> simp [phase] at checked
    exact quiet obligation member _ phase
  cases phase : state.status <;> simp only [phase] at active <;> try contradiction
  all_goals cases reason <;> simp [external, phase, first, cleanup, valid, require, bind, Except.bind] <;> rfl

end BoundaryV2.Profile.Source.Machine
