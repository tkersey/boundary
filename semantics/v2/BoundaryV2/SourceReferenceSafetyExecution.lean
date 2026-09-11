import BoundaryV2.SourceReferenceSafetyTransitions

namespace BoundaryV2.Profile.Source.Machine
namespace ReferenceSafety
open ReferenceContracts

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]

theorem tickRunning_valid (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (after : Transition)
    (accepted : tickRunning machine context = .ok after)
    (good : Valid context.source.schemas machine) : Valid context.source.schemas after.state := by
  have contextTyped : context.typingValid = true := by
    simpa only [Context.typingValid, Option.any_eq_true] using initial_checks_typing _ _ _ initialized
  have modes := ReferenceContracts.initialized_execution_preserves_reference_modes _ _ _ _ _ initialized steps
  have typed := good.values
  cases executing : machine.control <;> simp only [tickRunning, executing] at accepted
  case term => exact enterTerm_valid _ _ _ accepted good
  case expression => exact enterExpression_valid _ _ _ accepted contextTyped good
  case invoke => exact enterInvocation_valid _ _ _ accepted good
  case release => exact releaseScope_valid _ _ accepted good
  case discard => exact discardValues_valid _ _ _ accepted good modes
  case unwind => exact unwindStep_valid _ _ _ _ executing accepted good modes
  case execute intent bindings operands =>
    cases intent with
    | primitive => exact executePrimitive_valid _ _ _ accepted contextTyped good modes
    | term term =>
      cases term <;> first
        | exact executeEffectTerm_valid _ _ _ _ _ initialized steps _ accepted good
        | exact executeCleanupTerm_valid _ _ _ accepted good modes
        | exact executeControlTerm_valid _ _ _ accepted good modes
  case delivered value =>
    have valueTyped : ValueGood context.source.schemas machine.heap value.value := by
      apply typed
      simp [ValueInventory.state, executing, ValueInventory.control]
    have valueModes : ValueModes context.source.schemas value.value := by
      apply modes
      simp [ValueInventory.state, executing, ValueInventory.control]
    cases stacked : machine.stack with
    | nil =>
      simp only [stacked, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
      refine ⟨?_, good.live⟩
      simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.status,
        List.mem_append, List.mem_singleton] at typed ⊢
      grind only []
    | cons saved tail =>
      have frameTyped := ValueInventory.frame_preserves_all machine saved (by simp [stacked]) _ typed
      have tailTyped : ∀ child ∈ tail.flatMap ValueInventory.frame, ValueGood context.source.schemas machine.heap child := by
        intro child member
        apply typed
        simp [ValueInventory.state, stacked, member]
      have tailState : ValueInventory.All (ValueGood context.source.schemas machine.heap) {machine with stack := tail} := by
        simp only [ValueInventory.All, ValueInventory.state, List.mem_append] at typed ⊢
        grind only []
      cases saved <;> simp only [stacked] at accepted
      all_goals first
        | exact enterBinding_valid _ _ _ accepted good
        | exact deliverOperand_valid _ _ accepted good
        | exact leaveInvocation_valid _ _ accepted good
        | exact leaveLexical_valid _ _ accepted good
        | exact restoreResumeCaller_valid _ _ accepted good
        | exact completeHandler_valid _ _ _ accepted good
        | exact finishCleanup_valid _ _ _ accepted good
        | (cases accepted; refine ⟨?_, good.live⟩; simpa only [executing] using tailState)
        | skip
      case protection identity =>
        apply beginCleanup_valid _ _ _ _ _ _ _ accepted good modes
          (by simpa [exitValues] using And.intro valueTyped valueModes)
          (by simpa using And.intro valueTyped valueModes)
        intro child member
        refine ⟨tailTyped child member, ?_⟩
        apply modes
        simp [ValueInventory.state, stacked, member]
      case disposalReturn => contradiction
      case releaseReturn scope released =>
        cases accepted
        refine ⟨?_, good.live⟩
        simp only [ValueInventory.All, ValueInventory.state, ValueInventory.control, ValueInventory.frame,
          List.mem_append] at tailState frameTyped ⊢
        grind only []

theorem tick_valid (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (after : Transition)
    (accepted : tick machine context = .ok after)
    (good : Valid context.source.schemas machine) : Valid context.source.schemas after.state := by
  cases phase : machine.status <;> simp only [tick, phase] at accepted
  · exact tickRunning_valid _ _ _ _ _ initialized steps _ accepted good
  all_goals cases accepted; exact good

theorem step_valid (context : Context) (arguments : List SemanticValue)
    (before machine after : State) (events emitted : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (step : Step context machine emitted after)
    (good : Valid context.source.schemas machine) : Valid context.source.schemas after := by
  cases step with
  | internal accepted => exact tick_valid _ _ _ _ _ initialized steps _ accepted good
  | external accepted => exact external_valid _ _ _ _ accepted good

/-- Ordinary source initialization establishes reference compatibility and
custody alignment. Every actual internal and external transition preserves
them, including reusable activation and suspended cleanup. -/
theorem initialized_execution_preserves_reference_safety (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : Valid context.source.schemas after := by
  have extend : ∀ machine emitted after, Steps context machine emitted after →
      ∀ prefixEvents, Steps context before prefixEvents machine →
        Valid context.source.schemas machine → Valid context.source.schemas after := by
    intro machine emitted after path
    induction path with
    | refl => intro _ _ good; exact good
    | @cons machine first middle rest after step suffix induction =>
      intro prefixEvents history good
      exact induction (prefixEvents ++ first) (steps_trans history (by simpa using Steps.cons step Steps.refl))
        (step_valid _ _ _ _ _ _ _ initialized history step good)
  exact extend before events after steps [] .refl (initial_valid _ _ _ initialized)

theorem initialized_execution_owned_reference_wf (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : after.OwnedReferenceWF := by
  have safety := initialized_execution_preserves_reference_safety _ _ _ _ _ initialized steps
  exact ⟨values_aligned safety, values_bounded safety, safety.live,
    steps_custody_bounded steps (initial_custody_bounded _ _ _ initialized)⟩

end ReferenceSafety
end BoundaryV2.Profile.Source.Machine
