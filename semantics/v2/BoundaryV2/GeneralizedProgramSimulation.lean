import BoundaryV2.GeneralizedProgramRelation
import BoundaryV2.GeneralizedBranching
import BoundaryV2.GeneralizedOperandPrefix

namespace BoundaryV2.Generalized.Target

/-- Ordinary failure propagation skips caller/handler return code, but cannot
discard a protection frame. Its cleanup belongs to the exit transition owner. -/
theorem protected_fault_requires_exit_transition
    {signature : Signature} {algebra : LeafAlgebra signature.Data}
    {program : List (BodyType signature.Data signature.Effect)}
    {context : List (TypeOf signature)} {input result : TypeOf signature}
    (table : Definitions signature algebra program) (fault : algebra.Fault) (identity : Id .obligation)
    (cleanup : Code signature algebra program (.exit :: context) [] .unit)
    (bindings : RuntimeEnvironment signature algebra program context)
    (outside : Stack signature algebra program input result) (after : Configuration signature algebra program result) :
    ¬ CallStep table (.failed fault (.push (.protection identity cleanup bindings) outside)) after := by
  intro step
  cases step

end BoundaryV2.Generalized.Target

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

private theorem fault_execution (table : Target.Definitions signature algebra program)
    {bindings : Target.RuntimeEnvironment signature algebra program context}
    {before : Target.Operands signature algebra program context input}
    (failed : Target.ReachesFault bindings before fault)
    (outside : Target.Stack signature algebra program input result) :
    ∃ count, 0 < count ∧ Target.CallSteps table (.code before.code bindings before.values outside) count (.failed fault outside) := by
  obtain ⟨count, final, steps, faulted⟩ := failed
  cases faulted
  exact ⟨count + 1, by omega, (steps.in_context table outside).trans (.single .fault)⟩

/-- Every ordinary reduction from authored computation syntax has a positive,
finite target run. Store-dependent control operations are supplied by the
separate ownership/cell/exit transitions, not assumed in this theorem. -/
theorem computation_step_simulates (table : Source.Definitions signature algebra program)
    {body : Source.Computation signature algebra program context input}
    {bindings : Source.RuntimeEnvironment signature algebra program context}
    {after : Source.Program signature algebra program input}
    (step : Source.Step table (.evaluate body bindings) after)
    (outside : Target.Stack signature algebra program input result) :
    ∃ count targetAfter, 0 < count ∧ Target.CallSteps (definitions table)
      (.code (computation body) (environment bindings) .nil outside) count targetAfter ∧ ProgramRelated after outside targetAfter := by
  cases step with
  | operandFault failed =>
    obtain ⟨next, compiled⟩ := computation_has_operand_prefix body
    obtain ⟨count, positive, steps⟩ := fault_execution (definitions table)
      (arguments_fault_drains body.operandPrefix.arguments bindings next .nil _ failed) outside
    exact ⟨count, _, positive, by simpa only [compiled] using steps, .failed _ _⟩
  | returnValue evaluated | primitive evaluated =>
    obtain ⟨count, steps⟩ := expression_drains _ _ .ret .nil _ evaluated
    exact ⟨count + 1, _, by omega, (steps.in_context (definitions table) outside).trans (.single .returned), .returned _ _⟩
  | bind => exact ⟨1, _, by omega, .single .block, .bind _ _ (.evaluate _ _ _)⟩
  | @call definition reference context arguments bindings values evaluated =>
    obtain ⟨count, positive, steps⟩ := compiled_recursive_call table reference arguments bindings values evaluated outside
    exact ⟨count, _, positive, steps, .passthrough bindings (.evaluate _ _ _)⟩
  | apply functionEvaluated argumentsEvaluated =>
    obtain ⟨count, positive, steps⟩ := compiled_closure_call table _ _ _ _ _ _ _ functionEvaluated argumentsEvaluated outside
    exact ⟨count, _, positive, steps, .passthrough _ (.evaluate _ _ _)⟩
  | matchLeft evaluated selected =>
    obtain ⟨_, count, positive, steps⟩ := compiled_match_left table _ _ _ _ _ _ evaluated selected outside
    exact ⟨count, _, positive, steps, .evaluate _ _ _⟩
  | matchRight evaluated selected =>
    obtain ⟨_, count, positive, steps⟩ := compiled_match_right table _ _ _ _ _ _ evaluated selected outside
    exact ⟨count, _, positive, steps, .evaluate _ _ _⟩
  | @perform effect operation context capability payload bodies bindings attachment payloadValue bodyValues capabilityAt payloadAt bodiesAt =>
    obtain ⟨count, positive, steps⟩ := compiled_operation_opens_typed_future table operation capability payload bodies bindings
      attachment payloadValue bodyValues capabilityAt payloadAt bodiesAt outside
    exact ⟨count, _, positive, steps, .passthrough bindings (.requested operation attachment payloadValue bodyValues .done _)⟩
  | @handle effect mode bodyType context answer returned clauses body bindings attachment =>
    exact ⟨1, _, by omega, .single .attach,
      .passthrough bindings (.handler effect mode attachment returned clauses bindings (.evaluate _ _ _))⟩
  | fail => exact ⟨1, _, by omega, .single .fault, .failed _ _⟩
  | yield => exact ⟨1, _, by omega, .single .yield, .yielded (.evaluate _ _ _)⟩

/-- Structural source propagation can be silent on the target, whose stack
already contains the enclosing frame. Executable source reductions use the
positive runs above; return-frame drains are finite constructions. -/
theorem program_step_simulates (table : Source.Definitions signature algebra program)
    {source after : Source.Program signature algebra program input}
    (related : ProgramRelated source outside target)
    (step : Source.Step table source after) :
    ∃ count targetAfter, Target.CallSteps (definitions table) target count targetAfter ∧ ProgramRelated after outside targetAfter := by
  induction related with
  | evaluate body bindings future =>
    obtain ⟨count, targetAfter, _, steps, related⟩ := computation_step_simulates table step future
    exact ⟨count, targetAfter, steps, related⟩
  | returned | failed | requested | yielded => cases step
  | passthrough bindings inner induction =>
    obtain ⟨count, targetAfter, steps, related⟩ := induction step
    exact ⟨count, targetAfter, steps, .passthrough bindings related⟩
  | bind body bindings inner induction =>
    cases step with
    | bindValue =>
      obtain ⟨count, steps⟩ := inner.returned_drains (definitions table) _ rfl
      exact ⟨count + 2, _, steps.trans (ordinary_return_preserves_caller (definitions table) _ _ _ .nil _), .evaluate _ _ _⟩
    | bindFault =>
      obtain ⟨count, steps⟩ := inner.failed_drains (definitions table) _ rfl
      exact ⟨count + 1, _, steps.trans (.single .callerFault), .failed _ _⟩
    | bindYield =>
      obtain ⟨targetNext, rfl, nextRelated⟩ := inner.yielded_view _ rfl
      exact ⟨0, _, .refl, .yielded (.bind body bindings nextRelated)⟩
    | bindRequest =>
      obtain ⟨future, saved, rfl⟩ := inner.requested_view _ _ _ _ _ rfl
      refine ⟨0, _, .refl, ?_⟩
      simpa only [Target.Stack.append_associative, Target.Stack.append, Source.Frame.bindAuthored] using
        ProgramRelated.requested _ _ _ _ (context_composition saved (.push (.bind body bindings) .done)) _
    | bindStep sourceStep =>
      obtain ⟨count, targetAfter, steps, related⟩ := induction sourceStep
      exact ⟨count, targetAfter, steps, .bind body bindings related⟩
  | handler effect mode attachment returned clauses bindings inner induction =>
    cases step with
    | handlerValue =>
      obtain ⟨count, steps⟩ := inner.returned_drains (definitions table) _ rfl
      exact ⟨count + 1, _, steps.trans (.single .handlerReturned), .evaluate _ _ _⟩
    | handlerFault =>
      obtain ⟨count, steps⟩ := inner.failed_drains (definitions table) _ rfl
      exact ⟨count + 1, _, steps.trans (.single .handlerFault), .failed _ _⟩
    | handlerYield =>
      obtain ⟨targetNext, rfl, nextRelated⟩ := inner.yielded_view _ rfl
      exact ⟨0, _, .refl, .yielded (.handler effect mode attachment returned clauses bindings nextRelated)⟩
    | handlerForward different | handlerUnhandled absent =>
      obtain ⟨future, saved, rfl⟩ := inner.requested_view _ _ _ _ _ rfl
      refine ⟨0, _, .refl, ?_⟩
      simpa only [Target.Stack.append_associative, Target.Stack.append] using
        ProgramRelated.requested _ _ _ _ (context_composition saved
          (.push (.handler effect mode attachment returned clauses bindings) .done)) _
    | handlerStep sourceStep =>
      obtain ⟨count, targetAfter, steps, related⟩ := induction sourceStep
      exact ⟨count, targetAfter, steps, .handler effect mode attachment returned clauses bindings related⟩
  | region identity inner induction =>
    cases step with
    | regionStep sourceStep =>
      obtain ⟨count, targetAfter, steps, related⟩ := induction sourceStep
      exact ⟨count, targetAfter, steps, .region identity related⟩
    | regionYield =>
      obtain ⟨targetNext, rfl, nextRelated⟩ := inner.yielded_view _ rfl
      exact ⟨0, _, .refl, .yielded (.region identity nextRelated)⟩
    | regionRequest =>
      obtain ⟨future, saved, rfl⟩ := inner.requested_view _ _ _ _ _ rfl
      refine ⟨0, _, .refl, ?_⟩
      simpa only [Target.Stack.append_associative, Target.Stack.append] using
        ProgramRelated.requested _ _ _ _ (context_composition saved (.push (.region identity) .done)) _
  | cleaning identity original exit inner induction =>
    cases step with
    | cleaningReturn normal =>
      obtain ⟨count, steps⟩ := inner.returned_drains (definitions table) _ rfl
      exact ⟨count + 1, _, steps.trans (.single (.cleanupReturn normal)), .returned _ _⟩
    | cleaningStep sourceStep =>
      obtain ⟨count, targetAfter, steps, related⟩ := induction sourceStep
      exact ⟨count, targetAfter, steps, .cleaning identity original exit related⟩
    | cleaningYield =>
      obtain ⟨targetNext, rfl, nextRelated⟩ := inner.yielded_view _ rfl
      exact ⟨0, _, .refl, .yielded (.cleaning identity original exit nextRelated)⟩
    | cleaningRequest =>
      obtain ⟨future, saved, rfl⟩ := inner.requested_view _ _ _ _ _ rfl
      refine ⟨0, _, .refl, ?_⟩
      simpa only [Target.Stack.append_associative, Target.Stack.append] using
        ProgramRelated.requested _ _ _ _ (context_composition saved (.push (.cleanupReturn identity original exit) .done)) _
  | protection identity cleanup bindings inner induction =>
    cases step with
    | protectionReturn =>
      obtain ⟨count, steps⟩ := inner.returned_drains (definitions table) _ rfl
      exact ⟨count + 1, _, steps.trans (.single .protectionReturn),
        .cleaning identity _ _ (.evaluate cleanup (.cons (.exit ⟨.normal, [], none⟩) bindings) _)⟩
    | protectionStep sourceStep =>
      obtain ⟨count, targetAfter, steps, related⟩ := induction sourceStep
      exact ⟨count, targetAfter, steps, .protection identity cleanup bindings related⟩
    | protectionYield =>
      obtain ⟨targetNext, rfl, nextRelated⟩ := inner.yielded_view _ rfl
      exact ⟨0, _, .refl, .yielded (.protection identity cleanup bindings nextRelated)⟩
    | protectionRequest =>
      obtain ⟨future, saved, rfl⟩ := inner.requested_view _ _ _ _ _ rfl
      refine ⟨0, _, .refl, ?_⟩
      simpa only [Target.Stack.append_associative, Target.Stack.append] using
        ProgramRelated.requested _ _ _ _ (context_composition saved (.push (.protection identity cleanup bindings) .done)) _

theorem finite_program_steps_simulate (table : Source.Definitions signature algebra program)
    {source after : Source.Program signature algebra program input}
    (steps : Source.Steps table source sourceCount after)
    (related : ProgramRelated source outside target) :
    ∃ targetCount targetAfter, Target.CallSteps (definitions table) target targetCount targetAfter ∧
      ProgramRelated after outside targetAfter := by
  induction steps generalizing target with
  | refl => exact ⟨0, target, .refl, related⟩
  | cons step tail induction =>
    obtain ⟨firstCount, middle, firstSteps, middleRelated⟩ := program_step_simulates table related step
    obtain ⟨restCount, final, restSteps, finalRelated⟩ := induction middleRelated
    exact ⟨firstCount + restCount, final, firstSteps.trans restSteps, finalRelated⟩

theorem compiled_finite_return (table : Source.Definitions signature algebra program)
    (body : Source.Computation signature algebra program context result)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (returned : Source.RuntimeValue signature algebra program result)
    (steps : Source.Steps table (.evaluate body bindings) sourceCount (.returned returned)) :
    ∃ count, Target.CallSteps (definitions table)
      (.code (computation body) (environment bindings) .nil .done) count (.returned (value returned) .done) := by
  obtain ⟨count, target, initialSteps, related⟩ := finite_program_steps_simulate table steps (.evaluate body bindings .done)
  obtain ⟨rest, tail⟩ := related.returned_drains (definitions table) returned rfl
  exact ⟨count + rest, initialSteps.trans tail⟩

theorem compiled_finite_fault (table : Source.Definitions signature algebra program)
    (body : Source.Computation signature algebra program context result)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (fault : algebra.Fault)
    (steps : Source.Steps table (.evaluate body bindings) sourceCount (.failed fault)) :
    ∃ count, Target.CallSteps (definitions table)
      (.code (computation body) (environment bindings) .nil .done) count (.failed fault .done) := by
  obtain ⟨count, target, initialSteps, related⟩ := finite_program_steps_simulate table steps (.evaluate body bindings .done)
  obtain ⟨rest, tail⟩ := related.failed_drains (definitions table) fault rfl
  exact ⟨count + rest, initialSteps.trans tail⟩

theorem compiled_finite_yield (table : Source.Definitions signature algebra program)
    (body : Source.Computation signature algebra program context result)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (next : Source.Program signature algebra program result)
    (steps : Source.Steps table (.evaluate body bindings) sourceCount (.yielded next)) :
    ∃ count targetNext, Target.CallSteps (definitions table)
      (.code (computation body) (environment bindings) .nil .done) count (.yielded targetNext) ∧ ProgramRelated next .done targetNext := by
  obtain ⟨count, target, initialSteps, related⟩ := finite_program_steps_simulate table steps (.evaluate body bindings .done)
  obtain ⟨targetNext, rfl, nextRelated⟩ := related.yielded_view next rfl
  exact ⟨count, targetNext, initialSteps, nextRelated⟩

/-- The complete typed request and future are preserved. This is a statement
about the dispatch state; external visibility still requires the observation
rule's no-handling-delimiter condition. -/
theorem compiled_finite_request (table : Source.Definitions signature algebra program)
    (body : Source.Computation signature algebra program context result)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (operation : signature.operation effect) (attachment : Id .attachment)
    (payload : Source.RuntimeValue signature algebra program (signature.payload operation))
    (bodies : Source.RuntimeEnvironment signature algebra program ((signature.bodies operation).map BodyType.type))
    (future : Source.Context signature algebra program (signature.result operation) result)
    (steps : Source.Steps table (.evaluate body bindings) sourceCount (.request operation attachment payload bodies future)) :
    ∃ count targetFuture, Target.CallSteps (definitions table)
      (.code (computation body) (environment bindings) .nil .done) count
      (.requested operation attachment (value payload) (environment bodies) targetFuture) ∧
      ContextRelated signature algebra program future targetFuture := by
  obtain ⟨count, target, initialSteps, related⟩ := finite_program_steps_simulate table steps (.evaluate body bindings .done)
  obtain ⟨targetFuture, futureRelated, targetAt⟩ := related.requested_view operation attachment payload bodies future rfl
  simp only [Target.Stack.append_done] at targetAt
  exact ⟨count, targetFuture, targetAt ▸ initialSteps, futureRelated⟩

end BoundaryV2.Generalized.Defunctionalization
