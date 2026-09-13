import BoundaryV2.GeneralizedProgramSimulation

namespace BoundaryV2.Generalized

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

theorem Source.Arguments.cons_evaluated
    {first : Source.Expression signature algebra program context type}
    {rest : Source.Arguments signature algebra program context types}
    {bindings : Source.RuntimeEnvironment signature algebra program context}
    {values : Source.RuntimeEnvironment signature algebra program (type :: types)}
    (evaluated : (Source.Arguments.cons first rest).evaluate bindings = .ok values) :
    ∃ firstValue restValues, values = .cons firstValue restValues ∧
      first.evaluate bindings = .ok firstValue ∧ rest.evaluate bindings = .ok restValues := by
  cases firstAt : first.evaluate bindings with
  | error fault => simp only [Source.Arguments.evaluate, firstAt] at evaluated; contradiction
  | ok firstValue =>
    cases restAt : rest.evaluate bindings with
    | error fault => simp only [Source.Arguments.evaluate, firstAt, restAt] at evaluated; contradiction
    | ok restValues =>
      exact ⟨firstValue, restValues,
        by simpa only [Source.Arguments.evaluate, firstAt, restAt, Except.ok.injEq] using evaluated.symm,
        rfl, rfl⟩

namespace Defunctionalization

private theorem configuration_reindex
    {first second : List (TypeOf signature)} (same : first = second)
    (body : Target.Code signature algebra program context first input)
    (bindings : Target.RuntimeEnvironment signature algebra program context)
    (values : Target.RuntimeEnvironment signature algebra program first)
    (outside : Target.Stack signature algebra program input result)
    (codeType : Target.Code signature algebra program context first input = Target.Code signature algebra program context second input)
    (valueType : Target.RuntimeEnvironment signature algebra program first = Target.RuntimeEnvironment signature algebra program second) :
    Target.Configuration.code (codeType.mp body) bindings (valueType.mp values) outside = .code body bindings values outside := by
  cases same
  rfl

/-- The effective tail cannot invent a source control step. Successful store
operations are handled by their separate execution relation; they produce no
ordinary next step here. -/
theorem operand_tail_reflects (table : Source.Definitions signature algebra program)
    (body : Source.Computation signature algebra program context input)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (values : Source.RuntimeEnvironment signature algebra program body.operandPrefix.types)
    (evaluated : body.operandPrefix.arguments.evaluate bindings = .ok values)
    (attachment : Id .attachment) (outside : Target.Stack signature algebra program input result)
    {targetAfter : Target.Configuration signature algebra program result}
    (computed : Target.nextWithAttachment (definitions table) attachment
      (.code (operandTail body) (environment bindings) ((environment values).pushReverse .nil) outside) = some targetAfter) :
    ∃ sourceAfter, Source.Step table (.evaluate body bindings) sourceAfter ∧ ProgramRelated sourceAfter outside targetAfter := by
  cases body with
  | returnValue expression =>
    obtain ⟨value, rest, rfl, firstAt, _⟩ := Source.Arguments.cons_evaluated evaluated
    cases rest
    change some (.returned (Defunctionalization.value value) outside) = some targetAfter at computed
    cases computed
    exact ⟨_, .returnValue firstAt, .returned value outside⟩
  | primitive operation inputs =>
    obtain ⟨value, rest, rfl, firstAt, _⟩ := Source.Arguments.cons_evaluated evaluated
    cases rest
    change some (.returned (Defunctionalization.value value) outside) = some targetAfter at computed
    cases computed
    exact ⟨_, .primitive firstAt, .returned value outside⟩
  | call reference inputs =>
    simp only [operandTail, Target.nextWithAttachment, Target.codeNext, Target.operandNextCode,
      Environment.popReverse_pushReverse, recursive_table_lookup, Option.some.injEq] at computed
    subst targetAfter
    exact ⟨_, .call evaluated, .passthrough bindings (.evaluate (reference.lookup table) values _)⟩
  | @apply context use parameters input function inputs =>
    obtain ⟨functionValue, actual, rfl, functionAt, inputsAt⟩ := Source.Arguments.cons_evaluated evaluated
    cases functionValue with
    | datum datum => cases datum
    | closure body captured authority =>
      have stateAt : Target.Configuration.code (operandTail (.apply function inputs)) (environment bindings)
          ((environment (.cons (.closure body captured authority) actual)).pushReverse .nil) outside =
          .code (.callClosure (use := use) (parameters := parameters) .ret) (environment bindings)
            ((environment actual).pushReverse (.cons (.closure (use := use) (parameters := parameters)
              (computation body) (environment captured) authority) .nil)) outside := by
        simp only [operandTail, environment, Environment.map, Value.map, Environment.pushReverse]
        apply configuration_reindex
        simp [List.reverse_cons]
      rw [stateAt] at computed
      simp only [Target.nextWithAttachment, Target.codeNext, Target.operandNextCode,
        Environment.popReverse_pushReverse, Option.some.injEq] at computed
      subst targetAfter
      refine ⟨_, .apply functionAt inputsAt, ?_⟩
      simpa only [Source.enterClosure, captured_arguments_keep_order] using
        ProgramRelated.passthrough bindings (ProgramRelated.evaluate body (actual.append captured) _)
  | matchSum expression left right =>
    obtain ⟨sum, rest, rfl, firstAt, _⟩ := Source.Arguments.cons_evaluated evaluated
    cases rest
    change (match (value sum).asSum with
      | .inl payload => some (.code (computation left) (.cons payload (environment bindings)) .nil outside)
      | .inr payload => some (.code (computation right) (.cons payload (environment bindings)) .nil outside)) = some targetAfter at computed
    cases selected : sum.asSum with
    | inl payload =>
      simp only [value, Value.map_asSum, selected, Sum.map_inl, Option.some.injEq] at computed
      subst targetAfter
      exact ⟨_, .matchLeft firstAt selected, .evaluate left (.cons payload bindings) _⟩
    | inr payload =>
      simp only [value, Value.map_asSum, selected, Sum.map_inr, Option.some.injEq] at computed
      subst targetAfter
      exact ⟨_, .matchRight firstAt selected, .evaluate right (.cons payload bindings) _⟩
  | perform operation capability payload bodies =>
    obtain ⟨capabilityValue, tail, rfl, capabilityAt, tailAt⟩ := Source.Arguments.cons_evaluated evaluated
    obtain ⟨payloadValue, actualBodies, rfl, payloadAt, bodiesAt⟩ := Source.Arguments.cons_evaluated tailAt
    cases capabilityValue with
    | datum datum => cases datum with
      | capability identity =>
        have stateAt : Target.Configuration.code (operandTail (.perform operation capability payload bodies)) (environment bindings)
            ((environment (.cons (.datum (.capability identity)) (.cons payloadValue actualBodies))).pushReverse .nil) outside =
            .code (.dispatch operation .ret) (environment bindings)
              ((environment actualBodies).pushReverse (.cons (value payloadValue) (.cons (.datum (.capability identity)) .nil))) outside := by
          simp only [operandTail, environment, Environment.map, Value.map, Environment.pushReverse, value,
            eq_mpr_eq_cast, cast_cast]
          apply configuration_reindex
          simp [List.reverse_cons, List.append_assoc]
        rw [stateAt] at computed
        simp only [Target.nextWithAttachment, Target.codeNext, Target.operandNextCode,
          Environment.popReverse_pushReverse, Option.some.injEq] at computed
        subst targetAfter
        exact ⟨_, .perform capabilityAt payloadAt bodiesAt,
          .passthrough bindings (.requested operation identity payloadValue actualBodies .done _)⟩
  | bind first rest =>
    cases values
    simp only [operandTail, computation, Target.nextWithAttachment, Target.codeNext, Target.operandNextCode,
      environment, Environment.map, Environment.pushReverse, Option.some.injEq] at computed
    subst targetAfter
    exact ⟨_, .bind, .bind rest bindings (.evaluate first bindings _)⟩
  | handle effect mode returned clauses body =>
    cases values
    simp only [operandTail, computation, Target.nextWithAttachment, Target.codeNext, Target.operandNextCode,
      environment, Environment.map, Environment.pushReverse, Option.some.injEq] at computed
    subst targetAfter
    exact ⟨_, .handle, .passthrough bindings (.handler effect mode attachment returned clauses bindings (.evaluate body _ _))⟩
  | fail fault =>
    cases values
    simp only [operandTail, computation, Target.nextWithAttachment, Target.codeNext, Target.operandNextCode,
      environment, Environment.map, Environment.pushReverse, Option.some.injEq] at computed
    subst targetAfter
    exact ⟨_, .fail, .failed fault outside⟩
  | yieldThen body =>
    cases values
    simp only [operandTail, computation, Target.nextWithAttachment, Target.codeNext, Target.operandNextCode,
      environment, Environment.map, Environment.pushReverse, Option.some.injEq] at computed
    subst targetAfter
    exact ⟨_, .yield, .yielded (.evaluate body bindings outside)⟩
  | resume | resumeWith | inject | cellNew | cellRead | cellWrite | dispose | clone | package | unpackage | withRegion | protect =>
    simp only [operandTail, computation, Target.nextWithAttachment, Target.codeNext, Target.operandNextCode] at computed
    contradiction

/-- Every observing ordinary target run from compiled computation syntax can
be split at a corresponding source reduction. The residual target run is
strictly shorter, including when the operand prefix fails. -/
theorem computation_step_reflects (table : Source.Definitions signature algebra program)
    (body : Source.Computation signature algebra program context input)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (outside : Target.Stack signature algebra program input result)
    {final : Target.Configuration signature algebra program result}
    (run : Target.CallSteps (definitions table) (.code (computation body) (environment bindings) .nil outside) count final)
    (observed : Target.HeadObservation final observation) :
    ∃ sourceAfter targetAfter remaining, remaining < count ∧
      Source.Step table (.evaluate body bindings) sourceAfter ∧ ProgramRelated sourceAfter outside targetAfter ∧
      Target.CallSteps (definitions table) targetAfter remaining final := by
  rw [computation_operand_prefix body] at run
  cases evaluated : body.operandPrefix.arguments.evaluate bindings with
  | error fault =>
    obtain ⟨prefixCount, after, prefixSteps, faulted⟩ := arguments_fault_drains body.operandPrefix.arguments bindings (operandTail body) .nil fault evaluated
    obtain ⟨rest, counted, tail⟩ := prefixSteps.cancel_observed_prefix outside run observed
    cases faulted
    obtain ⟨remaining, reduced, following⟩ := (Target.CallStep.fault (table := definitions table)).cancel_observed rfl tail observed
    exact ⟨_, _, remaining, by omega, .operandFault evaluated, .failed fault outside, following⟩
  | ok values =>
    obtain ⟨prefixCount, prefixSteps⟩ := arguments_drains body.operandPrefix.arguments bindings (operandTail body) .nil values evaluated
    obtain ⟨rest, counted, tail⟩ := prefixSteps.cancel_observed_prefix outside run observed
    cases tail with
    | refl => cases observed
    | cons actual following =>
      obtain ⟨attachment, computed⟩ := actual.computes_next
      obtain ⟨sourceAfter, sourceStep, related⟩ := operand_tail_reflects table body bindings values evaluated attachment outside computed
      exact ⟨sourceAfter, _, _, by omega, sourceStep, related, following⟩

theorem observing_computation_reflects (table : Source.Definitions signature algebra program)
    (body : Source.Computation signature algebra program context input)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (outside : Target.Stack signature algebra program input result)
    (observed : Target.Observes (definitions table)
      (.code (computation body) (environment bindings) .nil outside) observation) :
    ∃ sourceAfter targetAfter, Source.Step table (.evaluate body bindings) sourceAfter ∧
      ProgramRelated sourceAfter outside targetAfter ∧ Target.Observes (definitions table) targetAfter observation := by
  obtain ⟨count, final, run, head⟩ := observed
  obtain ⟨sourceAfter, targetAfter, remaining, _, step, related, tail⟩ := computation_step_reflects table body bindings outside run head
  exact ⟨sourceAfter, targetAfter, step, related, remaining, final, tail, head⟩

end Defunctionalization
end BoundaryV2.Generalized
