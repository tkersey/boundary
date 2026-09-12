import BoundaryV2.SourceOperandTypes
import BoundaryV2.SourceFailureExecution

namespace BoundaryV2.Profile.Source.Machine

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

theorem reachable_tickRunning_preserves_value_shapes (context : Context) (arguments : List SemanticValue)
    (initialState machine : State) (events : List Event) (initialized : initial context arguments = .ok initialState)
    (steps : Steps context initialState events machine) (after : Transition)
    (accepted : tickRunning machine context = .ok after)
    (typed : ValueInventory.All (ValueShape context.source.schemas) machine) :
    ValueInventory.All (ValueShape context.source.schemas) after.state := by
  have contextTyped : context.typingValid = true := by
    simpa only [Context.typingValid, Option.any_eq_true] using initial_checks_typing _ _ _ initialized
  cases executing : machine.control <;> simp only [tickRunning, executing] at accepted
  case term => exact ValueInventory.enterTerm_preserves_all _ _ _ accepted _ typed
  case expression => exact enterExpression_preserves_value_shapes _ _ _ accepted contextTyped typed
  case invoke => exact ValueInventory.enterInvocation_preserves_all _ _ _ accepted _ typed
  case release => exact releaseScope_preserves_value_shapes _ _ accepted typed
  case discard => exact discardValues_preserves_value_shapes _ _ _ accepted typed
  case unwind exit =>
    exact FailureSchemas.reachable_unwind_preserves_value_shapes _ _ _ _ _ initialized steps
      exit executing after accepted typed
  case execute intent bindings operands =>
    cases intent with
    | primitive => exact OperandSchemas.reachable_primitive_preserves_value_shapes _ _ _ _ _ initialized steps _ accepted typed
    | term term =>
      cases term <;> first
        | exact executeEffectTerm_preserves_value_shapes _ _ _ accepted typed
        | exact executeCleanupTerm_preserves_value_shapes _ _ _ accepted typed
        | exact executeControlTerm_preserves_value_shapes _ _ _ accepted typed
  case delivered value =>
    have valueTyped : ValueShape context.source.schemas value.value := by
      apply typed
      simp [ValueInventory.state, executing, ValueInventory.control]
    cases stacked : machine.stack with
    | nil =>
      simp only [stacked, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
      simp only [ValueInventory.All, ValueInventory.state, ValueInventory.status, executing, stacked,
        ValueInventory.control, List.flatMap_nil, List.mem_cons, List.not_mem_nil, List.mem_append] at typed ⊢
      grind only []
    | cons saved tail =>
      have tailTyped : ∀ item ∈ tail.flatMap ValueInventory.frame, ValueShape context.source.schemas item := by
        intro item member
        apply typed
        simp [ValueInventory.state, stacked, member]
      cases saved <;> simp only [stacked] at accepted
      all_goals first
        | exact ValueInventory.enterBinding_preserves_all _ _ _ accepted _ typed
        | exact ValueInventory.deliverOperand_preserves_all _ _ accepted _ typed
        | exact ValueInventory.leaveInvocation_preserves_all _ _ accepted _ typed
        | exact leaveLexical_preserves_value_shapes _ _ accepted typed
        | exact ValueInventory.restoreResumeCaller_preserves_all _ _ accepted _ typed
        | exact ValueInventory.completeHandler_preserves_all _ _ _ accepted _ typed
        | exact ValueInventory.finishCleanup_preserves_all _ _ _ accepted _ typed
        | contradiction
        | skip
      case protection identity =>
        apply beginCleanup_preserves_value_shapes _ _ _ _ _ _ _ accepted typed
        · intro item member
          have same : item = value.value := by simpa [exitValues] using member
          cases same
          exact valueTyped
        · intro item member
          cases member
          exact valueTyped
        · exact tailTyped
        · intro failure failed
          cases cancellation : machine.cancellation <;>
            simp [observedExit, cancellation, Cleanup.cancel] at failed
      all_goals cases accepted
      all_goals simp only [ValueInventory.All, ValueInventory.state, executing, stacked,
        ValueInventory.control, ValueInventory.frame, List.flatMap_cons, List.mem_append,
        List.mem_cons, List.not_mem_nil] at typed ⊢
      all_goals grind only []

theorem reachable_tick_preserves_value_shapes (context : Context) (arguments : List SemanticValue)
    (initialState machine : State) (events : List Event) (initialized : initial context arguments = .ok initialState)
    (steps : Steps context initialState events machine) (after : Transition)
    (accepted : tick machine context = .ok after)
    (typed : ValueInventory.All (ValueShape context.source.schemas) machine) :
    ValueInventory.All (ValueShape context.source.schemas) after.state := by
  cases phase : machine.status <;> simp only [tick, phase] at accepted
  · exact reachable_tickRunning_preserves_value_shapes _ _ _ _ _ initialized steps _ accepted typed
  all_goals cases accepted; exact typed

theorem reachable_step_preserves_value_shapes (context : Context) (arguments : List SemanticValue)
    (initialState before after : State) (prefixEvents events : List Event)
    (initialized : initial context arguments = .ok initialState)
    (prior : Steps context initialState prefixEvents before) (step : Step context before events after)
    (typed : ValueInventory.All (ValueShape context.source.schemas) before) :
    ValueInventory.All (ValueShape context.source.schemas) after := by
  cases step with
  | internal accepted => exact reachable_tick_preserves_value_shapes _ _ _ _ _ initialized prior _ accepted typed
  | external accepted => exact external_preserves_value_shapes _ _ _ _ accepted typed

theorem reachable_steps_preserve_value_shapes (context : Context) (arguments : List SemanticValue)
    (initialState before after : State) (prefixEvents events : List Event)
    (initialized : initial context arguments = .ok initialState)
    (prior : Steps context initialState prefixEvents before) (steps : Steps context before events after)
    (typed : ValueInventory.All (ValueShape context.source.schemas) before) :
    ValueInventory.All (ValueShape context.source.schemas) after := by
  induction steps generalizing prefixEvents with
  | refl => exact typed
  | cons step _ induction =>
    apply induction _ (steps_trans prior (.cons step .refl))
    exact reachable_step_preserves_value_shapes _ _ _ _ _ _ _ initialized prior step typed

/-- All retained source values have finite profile typing throughout every
initialized execution. Runtime primitive admission and failure schemas come
from the independent trajectory invariants; cleanup sizes are checked by the
actual constructor. No successor typing or payload bound is assumed. -/
theorem initialized_execution_preserves_value_shapes (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : ValueInventory.All (ValueShape context.source.schemas) after :=
  reachable_steps_preserve_value_shapes context arguments before before after [] events initialized .refl steps
    (initial_value_shapes _ _ _ initialized)

end BoundaryV2.Profile.Source.Machine
