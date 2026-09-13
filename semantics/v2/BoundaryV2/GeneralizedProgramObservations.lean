import BoundaryV2.GeneralizedComputationReflection

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

theorem ProgramRelated.preserves_head_observation (table : Source.Definitions signature algebra program)
    {source : Source.Program signature algebra program result}
    (related : ProgramRelated source .done target)
    (head : Source.HeadObservation source observation) :
    ∃ targetObservation, Target.Observes (definitions table) target targetObservation ∧ ObservationRelated observation targetObservation := by
  cases head with
  | returned =>
    obtain ⟨count, steps⟩ := related.returned_drains (definitions table) _ rfl
    exact ⟨_, ⟨count, _, steps, .returned⟩, .returned _⟩
  | failed =>
    obtain ⟨count, steps⟩ := related.failed_drains (definitions table) _ rfl
    exact ⟨_, ⟨count, _, steps, .failed⟩, .failed _⟩
  | yielded =>
    obtain ⟨next, rfl, nextRelated⟩ := related.yielded_view _ rfl
    exact ⟨_, ⟨0, _, .refl, .yielded⟩, .yielded nextRelated⟩
  | requested forward =>
    obtain ⟨future, saved, targetAt⟩ := related.requested_view _ _ _ _ _ rfl
    simp only [Target.Stack.append_done] at targetAt
    subst target
    exact ⟨_, ⟨0, _, .refl, .requested ((forwarding_corresponds saved).mp forward)⟩, .requested _ _ _ _ saved⟩

/-- All four ordinary source observations are preserved, including complete
yielded programs and request futures. The source and target forwarding checks
are separate and connected by their structural correspondence. -/
theorem ordinary_observation_preserved (table : Source.Definitions signature algebra program)
    {source : Source.Program signature algebra program result}
    (related : ProgramRelated source .done target)
    (observed : Source.Observes table source observation) :
    ∃ targetObservation, Target.Observes (definitions table) target targetObservation ∧ ObservationRelated observation targetObservation := by
  obtain ⟨sourceCount, sourceFinal, sourceSteps, sourceHead⟩ := observed
  obtain ⟨count, final, targetSteps, finalRelated⟩ := finite_program_steps_simulate table sourceSteps related
  obtain ⟨targetObservation, targetObserved, same⟩ := finalRelated.preserves_head_observation table sourceHead
  exact ⟨targetObservation, targetObserved.prepend targetSteps, same⟩

private theorem reflect_request_head (table : Source.Definitions signature algebra program)
    (operation : signature.operation effect) (attachment : Id .attachment)
    (payload : Source.RuntimeValue signature algebra program (signature.payload operation))
    (bodies : Source.RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type))
    {sourceFuture : Source.Context signature algebra program (signature.result operation) input}
    {targetFuture : Target.Stack signature algebra program (signature.result operation) input}
    (saved : ContextRelated signature algebra program sourceFuture targetFuture)
    {sourceOutside : Source.Context signature algebra program input result}
    {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (forward : Target.Forwards operation attachment (targetFuture.append targetOutside)) :
    ∃ sourceObservation,
      Source.Observes table (sourceOutside.plug (.request operation attachment payload bodies sourceFuture)) sourceObservation ∧
      ObservationRelated sourceObservation (.requested operation attachment (value payload) (environment bodies) (targetFuture.append targetOutside)) := by
  have combined := context_composition saved outside
  have sourceForward := (forwarding_corresponds combined).mpr forward
  have outerForward := sourceForward.append_right sourceFuture sourceOutside
  exact ⟨_, ⟨sourceOutside.length, _, outerForward.expose_request table payload bodies sourceFuture, .requested sourceForward⟩,
    .requested operation attachment payload bodies combined⟩

private theorem reflect_yield_head (table : Source.Definitions signature algebra program)
    {source : Source.Program signature algebra program input}
    {sourceOutside : Source.Context signature algebra program input result}
    {targetOutside : Target.Stack signature algebra program input result}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    (related : ProgramRelated source targetOutside target) :
    ∃ sourceObservation, Source.Observes table (sourceOutside.plug (.yielded source)) sourceObservation ∧
      ObservationRelated sourceObservation (.yielded target) :=
  ⟨_, ⟨sourceOutside.length, _, sourceOutside.forward_yield table source, .yielded⟩, .yielded (outside.close_program related)⟩

private theorem ordinary_reflect_bounded (table : Source.Definitions signature algebra program) (bound : Nat) :
    ∀ {input result} {source : Source.Program signature algebra program input}
      {sourceOutside : Source.Context signature algebra program input result}
      {targetOutside : Target.Stack signature algebra program input result}
      {target final : Target.Configuration signature algebra program result}
      {observation : Target.Observation signature algebra program result} {count},
      count < bound → ProgramRelated source targetOutside target →
      ContextRelated signature algebra program sourceOutside targetOutside →
      Target.CallSteps (definitions table) target count final → Target.HeadObservation final observation →
      ∃ sourceObservation, Source.Observes table (sourceOutside.plug source) sourceObservation ∧ ObservationRelated sourceObservation observation := by
  induction bound with
  | zero => intros; omega
  | succ bound smaller =>
    intro input result source sourceOutside targetOutside target final observation count counted related outside run head
    induction related with
    | evaluate body bindings future =>
      obtain ⟨sourceAfter, targetAfter, remaining, decreased, sourceStep, related, tail⟩ := computation_step_reflects table body bindings future run head
      obtain ⟨sourceObservation, observed, same⟩ := smaller (by omega) related outside tail head
      exact ⟨sourceObservation, observed.prepend (.single (sourceStep.in_context sourceOutside)), same⟩
    | bind body bindings inner induction =>
      simpa only [Source.Context.plug, Source.Frame.plug, Source.Frame.bindAuthored, Source.Program.bindAuthored] using
        induction (.push (.bind body bindings) outside) run head
    | handler effect mode attachment returned clauses bindings inner induction =>
      simpa only [Source.Context.plug, Source.Frame.plug] using
        induction (.push (.handler effect mode attachment returned clauses bindings) outside) run head
    | region identity inner induction =>
      simpa only [Source.Context.plug, Source.Frame.plug] using induction (.push (.region identity) outside) run head
    | protection identity cleanup bindings inner induction =>
      simpa only [Source.Context.plug, Source.Frame.plug] using
        induction (.push (.protection identity cleanup bindings) outside) run head
    | passthrough bindings inner induction => exact induction (.passthrough bindings outside) run head
    | yielded inner induction =>
      cases run with
      | refl => cases head; exact reflect_yield_head table outside inner
      | cons step tail => cases step
    | requested operation attachment payload bodies saved future =>
      cases run with
      | refl => cases head with
        | requested forward => exact reflect_request_head table operation attachment payload bodies saved outside forward
      | cons step tail => cases step
    | returned value future =>
      cases outside with
      | done =>
        cases run with
        | refl => cases head; exact ⟨_, ⟨0, _, .refl, .returned⟩, .returned value⟩
        | cons step tail => cases step
      | passthrough bindings rest =>
        obtain ⟨firstCount, firstEq, firstRun⟩ := Target.CallStep.caller.cancel_observed rfl run head
        obtain ⟨remaining, secondEq, tail⟩ := Target.CallStep.returned.cancel_observed rfl firstRun head
        exact smaller (by omega) (.returned value _) rest tail head
      | push frame rest =>
        cases frame with
        | bind body bindings =>
          obtain ⟨firstCount, firstEq, firstRun⟩ := Target.CallStep.caller.cancel_observed rfl run head
          obtain ⟨remaining, secondEq, tail⟩ := Target.CallStep.enter.cancel_observed rfl firstRun head
          obtain ⟨sourceObservation, observed, same⟩ := smaller (by omega) (.evaluate body (.cons value bindings) _) rest tail head
          exact ⟨sourceObservation, observed.prepend (.single (Source.Step.bindValue.in_context _)), same⟩
        | handler effect mode identity returned clauses bindings =>
          obtain ⟨remaining, reduced, tail⟩ := Target.CallStep.handlerReturned.cancel_observed rfl run head
          obtain ⟨sourceObservation, observed, same⟩ := smaller (by omega) (.evaluate returned (.cons value bindings) _) rest tail head
          exact ⟨sourceObservation, observed.prepend (.single (Source.Step.handlerValue.in_context _)), same⟩
        | region identity | protection identity cleanup bindings =>
          cases run with
          | refl => cases head
          | cons step tail => cases step
    | failed fault future =>
      cases outside with
      | done =>
        cases run with
        | refl => cases head; exact ⟨_, ⟨0, _, .refl, .failed⟩, .failed fault⟩
        | cons step tail => cases step
      | passthrough bindings rest =>
        obtain ⟨remaining, reduced, tail⟩ := Target.CallStep.callerFault.cancel_observed rfl run head
        exact smaller (by omega) (.failed fault _) rest tail head
      | push frame rest =>
        cases frame with
        | bind body bindings =>
          obtain ⟨remaining, reduced, tail⟩ := Target.CallStep.callerFault.cancel_observed rfl run head
          obtain ⟨sourceObservation, observed, same⟩ := smaller (by omega) (.failed fault _) rest tail head
          exact ⟨sourceObservation, observed.prepend (.single (Source.Step.bindFault.in_context _)), same⟩
        | handler effect mode identity returned clauses bindings =>
          obtain ⟨remaining, reduced, tail⟩ := Target.CallStep.handlerFault.cancel_observed rfl run head
          obtain ⟨sourceObservation, observed, same⟩ := smaller (by omega) (.failed fault _) rest tail head
          exact ⟨sourceObservation, observed.prepend (.single (Source.Step.handlerFault.in_context _)), same⟩
        | region identity | protection identity cleanup bindings =>
          cases run with
          | refl => cases head
          | cons step tail => cases step

/-- Reflection follows the actual finite target derivation. The bound is an
induction measure on that derivation, not fuel in either execution semantics. -/
theorem ordinary_observation_reflected (table : Source.Definitions signature algebra program)
    {source : Source.Program signature algebra program result}
    (related : ProgramRelated source .done target)
    (observed : Target.Observes (definitions table) target observation) :
    ∃ sourceObservation, Source.Observes table source sourceObservation ∧ ObservationRelated sourceObservation observation := by
  obtain ⟨count, final, run, head⟩ := observed
  exact ordinary_reflect_bounded table (count + 1) (by omega) related .done run head

/-- Adequacy for the ordinary transition relation, over arbitrary typed source
syntax and leaf algebras. Stateful use/capture/exit transitions retain their
separate integration obligations in the complete core. -/
theorem ordinary_defunctionalization_adequacy (table : Source.Definitions signature algebra program)
    (body : Source.Computation signature algebra program context result)
    (bindings : Source.RuntimeEnvironment signature algebra program context) :
    (∀ sourceObservation, Source.Observes table (.evaluate body bindings) sourceObservation →
      ∃ targetObservation, Target.Observes (definitions table) (.code (computation body) (environment bindings) .nil .done) targetObservation ∧
        ObservationRelated sourceObservation targetObservation) ∧
    (∀ targetObservation, Target.Observes (definitions table) (.code (computation body) (environment bindings) .nil .done) targetObservation →
      ∃ sourceObservation, Source.Observes table (.evaluate body bindings) sourceObservation ∧ ObservationRelated sourceObservation targetObservation) :=
  ⟨fun _ observed => ordinary_observation_preserved table (.evaluate body bindings .done) observed,
   fun _ observed => ordinary_observation_reflected table (.evaluate body bindings .done) observed⟩

theorem every_request_response_remains_related
    {sourceFuture : Source.Context signature algebra program input result}
    {targetFuture : Target.Stack signature algebra program input result}
    (future : ContextRelated signature algebra program sourceFuture targetFuture)
    (response : Source.RuntimeValue signature algebra program input) :
    ProgramRelated (sourceFuture.plug (.returned response)) .done (.returned (value response) targetFuture) :=
  future.close_program (.returned response targetFuture)

end BoundaryV2.Generalized.Defunctionalization
