import BoundaryV2.SourceLexicalCleanup

namespace BoundaryV2.Profile.Source.Machine
namespace LexicalCoverage

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

private theorem fromOption_ok (value : Option α) (reason : Invalid) (result : α) :
    fromOption value reason = .ok result ↔ value = some result := by
  cases value <;> simp [fromOption]


theorem cancel_control_valid (context : Context) (before : Control) (reason : Protocol.Reason) :
    ControlValid context (cancelControl before reason) := by
  cases before <;> simp only [cancelControl]
  all_goals repeat' split
  all_goals trivial

theorem external_valid (machine : State) (context : Context) (action : External) (after : Transition)
    (accepted : external machine context action = .ok after) (covered : Valid context machine) : Valid context after.state := by
  have running : Valid context { machine with status := .running } := covered
  have cancelled (reason : Protocol.Reason) : Valid context
      { machine with status := .running, control := cancelControl machine.control reason, cancellation := some reason } :=
    ⟨cancel_control_valid _ _ _, covered.2⟩
  have cancellationOnly (reason : Protocol.Reason) : Valid context { machine with cancellation := some reason } := covered
  have scopedResult (value : SemanticValue) (transition : Transition)
      (checked : scopedValue { machine with status := .running } value = .ok transition) : Valid context transition.state := by
    have shape := SavedFrames.scopedValue_valid context _ _ _ checked running.2.2
    obtain ⟨result, delivered⟩ := shape.1
    exact ⟨by simp [ControlValid, delivered], SavedFrames.plain_of_shape context _ _ running.2 shape.2.1 shape.2.2⟩
  cases phase : machine.status <;> cases action <;>
    simp only [external, phase, bind, pure, Except.pure, throw, throwThe, MonadExceptOf.throw,
      Except.bind] at accepted <;> try contradiction
  all_goals grind (gen := 32) only []

theorem tickRunning_valid (machine : State) (context : Context) (after : Transition)
    (typed : context.typingValid = true) (accepted : tickRunning machine context = .ok after)
    (covered : Valid context machine) : Valid context after.state := by
  cases executing : machine.control <;> simp only [tickRunning, executing] at accepted
  case term =>
    have next := enterTerm_valid _ _ _ typed accepted covered.1 covered.2.1
    exact ⟨next.1, next.2, SavedFrames.enterTerm_heap _ _ _ accepted covered.2.2⟩
  case expression =>
    have next := enterExpression_valid _ _ _ typed accepted covered.1 covered.2.1
    exact ⟨next.1, next.2, SavedFrames.enterExpression_heap _ _ _ accepted covered.2.2⟩
  case invoke =>
    have next := enterInvocation_valid _ _ _ typed accepted covered.2.1
    unfold enterInvocation at accepted
    split at accepted <;> try contradiction
    exact ⟨next.1, SavedFrames.invokeFunction_plain _ _ _ _ _ _ accepted covered.2⟩
  case release => exact ⟨releaseScope_control _ _ _ accepted, SavedFrames.releaseScope_plain context _ _ accepted covered.2⟩
  case discard => exact ⟨discardValues_control _ _ _ accepted, SavedFrames.discardValues_plain _ _ _ accepted covered.2⟩
  case unwind => exact unwindStep_valid _ _ _ typed accepted covered
  case execute intent bindings operands =>
    cases intent with
    | primitive =>
      have next := SavedFrames.executePrimitive_plain _ _ _ accepted covered.2
      exact ⟨next.2, next.1⟩
    | term term =>
      cases term <;> first
        | exact ⟨executeEffectTerm_control _ _ _ typed covered.1 accepted, SavedFrames.executeEffectTerm_plain _ _ _ accepted covered.2⟩
        | exact ⟨executeCleanupTerm_control _ _ _ typed accepted, SavedFrames.executeCleanupTerm_plain _ _ _ accepted covered.2⟩
        | exact ⟨(executeControlTerm_valid _ _ _ typed accepted covered.1 covered.2.1).1,
            SavedFrames.executeControlTerm_plain _ _ _ accepted covered.2⟩
  case delivered value =>
    cases stacked : machine.stack with
    | nil =>
      simp only [stacked, bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
      obtain ⟨_, _, _, _, _, _, rfl⟩ := accepted
      exact ⟨trivial, by simpa only [SavedFrames.Plain, stacked] using covered.2⟩
    | cons saved tail =>
      have tailTyped : SavedFrames.StackValid context tail := covered.2.1.subset (by intro frame member; rw [stacked]; simp [member])
      have tailPlain : SavedFrames.Plain context { machine with stack := tail } := ⟨tailTyped, covered.2.2⟩
      cases saved <;> simp only [stacked] at accepted
      case operands =>
        have next := deliverOperand_valid _ _ _ accepted covered.2.1
        exact ⟨next.1, next.2, SavedFrames.deliverOperand_heap _ _ _ accepted covered.2.2⟩
      all_goals first
        | exact ⟨(enterBinding_valid _ _ _ accepted covered.2.1).1, SavedFrames.enterBinding_plain _ _ _ accepted covered.2⟩
        | exact ⟨leaveInvocation_control _ _ _ accepted, SavedFrames.leaveInvocation_plain context _ _ accepted covered.2⟩
        | exact ⟨leaveLexical_control _ _ _ accepted, SavedFrames.leaveLexical_plain context _ _ accepted covered.2⟩
        | exact ⟨restoreResumeCaller_control _ _ _ accepted, SavedFrames.restoreResumeCaller_plain context _ _ accepted covered.2⟩
        | exact ⟨completeHandler_control _ _ _ typed accepted, SavedFrames.completeHandler_plain _ _ _ accepted covered.2⟩
        | exact ⟨beginCleanup_control _ _ _ _ _ _ _ typed accepted, SavedFrames.beginCleanup_plain _ _ _ _ _ _ _ accepted covered.2.2 tailTyped⟩
        | exact ⟨finishCleanup_control _ _ _ accepted, SavedFrames.finishCleanup_plain _ _ _ accepted covered.2⟩
        | exact ⟨finishDisposal_control _ _ _ accepted, SavedFrames.finishDisposal_plain _ _ _ accepted covered.2⟩
        | (cases accepted; exact ⟨by first | exact covered.1 | trivial, tailPlain⟩)
        | (cases accepted; exact ⟨trivial, tailPlain⟩)
        | contradiction

theorem tick_valid (machine : State) (context : Context) (after : Transition)
    (typed : context.typingValid = true) (accepted : tick machine context = .ok after)
    (covered : Valid context machine) : Valid context after.state := by
  cases phase : machine.status <;> simp only [tick, phase] at accepted
  · exact tickRunning_valid _ _ _ typed accepted covered
  all_goals cases accepted; exact covered

theorem step_valid (context : Context) (before after : State) (events : List Event)
    (typed : context.typingValid = true) (step : Step context before events after)
    (covered : Valid context before) : Valid context after := by
  cases step with
  | internal accepted => exact tick_valid _ _ _ typed accepted covered
  | external accepted => exact external_valid _ _ _ _ accepted covered

theorem steps_valid (context : Context) (before after : State) (events : List Event)
    (typed : context.typingValid = true) (steps : Steps context before events after)
    (covered : Valid context before) : Valid context after := by
  induction steps with
  | refl => exact covered
  | cons step _ induction => exact induction (step_valid _ _ _ _ typed step covered)

theorem initial_valid (context : Context) (arguments : List SemanticValue) (machine : State)
    (accepted : initial context arguments = .ok machine) : Valid context machine := by
  simp only [initial, bind, except_bind_ok, fromOption_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, _, _, _, _, entry, found, _, capturesEmpty, _, _, _, _, rfl⟩ := accepted
  have closed : Analysis.captures context.captures context.source.entry = [] := by
    unfold require at capturesEmpty
    split at capturesEmpty <;> try contradiction
    rename_i empty
    simpa using empty
  refine ⟨⟨(List.getElem?_eq_some_iff.mp found).1, ?_⟩, ?_⟩
  · change Covers [] (Analysis.captures context.captures context.source.entry)
    rw [closed]
    simp [Covers]
  · simp [SavedFrames.Plain, SavedFrames.StackValid, SavedFrames.HeapValid]

/-- Every ordinary initialized source trajectory retains bindings for active
source sites and saved continuations, including dormant and cloned captures. -/
theorem initialized_execution_preserves_lexical_coverage (context : Context) (arguments : List SemanticValue)
    (before after : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events after) : Valid context after := by
  have typed : context.typingValid = true := by
    simpa only [Context.typingValid, Option.any_eq_true] using initial_checks_typing _ _ _ initialized
  exact steps_valid _ _ _ _ typed steps (initial_valid _ _ _ initialized)

/-- A variable reached by actual execution has a binding; no lookup-success
premise is required from the caller. Custody and value typing are separate laws. -/
theorem reachable_variable_has_binding (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (reference : SourceValueId) (bindings : Environment)
    (schema : SchemaId .source) (var : VariableId) (executing : machine.control = .expression reference bindings)
    (found : context.source.values[reference.value]? = some ⟨schema, .variable var⟩) :
    ∃ value, lookupVariable bindings var = some value := by
  have valid := (initialized_execution_preserves_lexical_coverage _ _ _ _ _ initialized steps).1
  have covered : SiteValid context (.value reference) bindings := by simpa only [ControlValid, executing] using valid
  have typed : context.typingValid = true := by
    simpa only [Context.typingValid, Option.any_eq_true] using initial_checks_typing _ _ _ initialized
  apply covered.2
  exact (variables_exact _ _ (checked_capture_analysis _ typed) _ _).mpr (.direct (by simp [Analysis.direct, found]))

theorem reachable_expression_has_source (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (reference : SourceValueId) (bindings : Environment)
    (executing : machine.control = .expression reference bindings) :
    ∃ definition, context.source.values[reference.value]? = some definition := by
  have valid := (initialized_execution_preserves_lexical_coverage _ _ _ _ _ initialized steps).1
  have site : SiteValid context (.value reference) bindings := by simpa only [ControlValid, executing] using valid
  exact ⟨context.source.values[reference.value]'site.1, List.getElem?_eq_getElem site.1⟩

theorem reachable_term_has_source (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (reference : TermId) (bindings : Environment)
    (executing : machine.control = .term reference bindings) :
    ∃ definition, context.source.terms[reference.value]? = some definition := by
  have valid := (initialized_execution_preserves_lexical_coverage _ _ _ _ _ initialized steps).1
  have site : SiteValid context (.term reference) bindings := by simpa only [ControlValid, executing] using valid
  exact ⟨context.source.terms[reference.value]'site.1, List.getElem?_eq_getElem site.1⟩

/-- The actual variable evaluator cannot report a missing-reference error on a
reachable variable. Its type and custody checks retain their distinct errors. -/
theorem reachable_variable_reference_failure_impossible (context : Context) (arguments : List SemanticValue)
    (before machine : State) (events : List Event) (initialized : initial context arguments = .ok before)
    (steps : Steps context before events machine) (reference : SourceValueId) (bindings : Environment)
    (schema : SchemaId .source) (var : VariableId) (executing : machine.control = .expression reference bindings)
    (found : context.source.values[reference.value]? = some ⟨schema, .variable var⟩) :
    enterExpression machine context ≠ .error .reference := by
  obtain ⟨value, lookup⟩ := reachable_variable_has_binding _ _ _ _ _ initialized steps _ _ _ _ executing found
  cases same : value.value.schema == schema <;> cases active : current machine.heap value <;>
    simp [enterExpression, executing, found, lookup, require, fromOption, same, active, bind, Except.bind, pure, Except.pure]

end LexicalCoverage
end BoundaryV2.Profile.Source.Machine
