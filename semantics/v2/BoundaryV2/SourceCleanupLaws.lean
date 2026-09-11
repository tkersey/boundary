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

end BoundaryV2.Profile.Source.Machine
