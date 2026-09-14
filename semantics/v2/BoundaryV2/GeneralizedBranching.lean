import BoundaryV2.GeneralizedContextExecution

namespace BoundaryV2.Generalized.Target

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

def Code.isBranch : Code signature algebra program context operands result → Bool
  | .branch _ _ => true
  | _ => false

def Configuration.isBranch : Configuration signature algebra program result → Bool
  | .code body _ _ _ => body.isBranch
  | _ => false

def branchNextCode (body : Code signature algebra program context operands input)
    (bindings : RuntimeEnvironment signature algebra program context)
    (values : RuntimeEnvironment signature algebra program operands) (future : Stack signature algebra program input result) :
    Option (Configuration signature algebra program result) :=
  match body with
  | .branch left right =>
    match values with
    | .cons value operands => match value.asSum with
      | .inl payload => some (.code left (.cons payload bindings) operands future)
      | .inr payload => some (.code right (.cons payload bindings) operands future)
  | _ => none

def Configuration.branchNext : Configuration signature algebra program result → Option (Configuration signature algebra program result)
  | .code body bindings operands future => branchNextCode body bindings operands future
  | _ => none

theorem CallStep.branch_next {before after : Configuration signature algebra program result}
    (step : CallStep table before after) (branch : before.isBranch = true) : before.branchNext = some after := by
  cases step with
  | operand step => cases step <;> simp [Configuration.isBranch, Code.isBranch] at branch
  | branchLeft selected => simp only [Configuration.branchNext, branchNextCode, selected]
  | branchRight selected => simp only [Configuration.branchNext, branchNextCode, selected]
  | returned | enter | block | named | closure | dispatch | attach | handlerReturned | caller | protectionReturn | cleanupReturn | callerFault | handlerFault | fault | yield =>
    simp [Configuration.isBranch, Code.isBranch] at branch

end BoundaryV2.Generalized.Target

namespace BoundaryV2.Generalized.Defunctionalization

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)}

theorem sum_left_is_preserved_and_reflected
    (source : Source.RuntimeValue signature algebra program (.sum left right))
    (payload : Target.RuntimeValue signature algebra program left) :
    (value source).asSum = .inl payload ↔
      ∃ original, source.asSum = .inl original ∧ value original = payload := by
  simp only [value, Value.map_asSum]
  cases selected : source.asSum <;> simp

theorem sum_right_is_preserved_and_reflected
    (source : Source.RuntimeValue signature algebra program (.sum left right))
    (payload : Target.RuntimeValue signature algebra program right) :
    (value source).asSum = .inr payload ↔
      ∃ original, source.asSum = .inr original ∧ value original = payload := by
  simp only [value, Value.map_asSum]
  cases selected : source.asSum <;> simp

theorem compiled_match_left (table : Source.Definitions signature algebra program)
    (expression : Source.Expression signature algebra program context (.sum leftType rightType))
    (left : Source.Computation signature algebra program (leftType :: context) result)
    (right : Source.Computation signature algebra program (rightType :: context) result)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (sum : Source.RuntimeValue signature algebra program (.sum leftType rightType))
    (payload : Source.RuntimeValue signature algebra program leftType)
    (evaluated : expression.evaluate bindings = .ok sum) (selected : sum.asSum = .inl payload)
    (outside : Target.Stack signature algebra program result answer) :
    Source.Step table (.evaluate (.matchSum expression left right) bindings) (.evaluate left (.cons payload bindings)) ∧
      ∃ count, 0 < count ∧ Target.CallSteps (definitions table)
        (.code (computation (.matchSum expression left right)) (environment bindings) .nil outside) count
        (.code (computation left) (environment (.cons payload bindings)) .nil outside) := by
  refine ⟨.matchLeft evaluated selected, ?_⟩
  obtain ⟨count, steps⟩ := expression_drains expression bindings (.branch (computation left) (computation right)) .nil sum evaluated
  refine ⟨count + 1, by omega, (steps.in_context (definitions table) outside).trans (.single ?_)⟩
  apply Target.CallStep.branchLeft
  exact (sum_left_is_preserved_and_reflected sum (value payload)).mpr ⟨payload, selected, rfl⟩

theorem compiled_match_right (table : Source.Definitions signature algebra program)
    (expression : Source.Expression signature algebra program context (.sum leftType rightType))
    (left : Source.Computation signature algebra program (leftType :: context) result)
    (right : Source.Computation signature algebra program (rightType :: context) result)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (sum : Source.RuntimeValue signature algebra program (.sum leftType rightType))
    (payload : Source.RuntimeValue signature algebra program rightType)
    (evaluated : expression.evaluate bindings = .ok sum) (selected : sum.asSum = .inr payload)
    (outside : Target.Stack signature algebra program result answer) :
    Source.Step table (.evaluate (.matchSum expression left right) bindings) (.evaluate right (.cons payload bindings)) ∧
      ∃ count, 0 < count ∧ Target.CallSteps (definitions table)
        (.code (computation (.matchSum expression left right)) (environment bindings) .nil outside) count
        (.code (computation right) (environment (.cons payload bindings)) .nil outside) := by
  refine ⟨.matchRight evaluated selected, ?_⟩
  obtain ⟨count, steps⟩ := expression_drains expression bindings (.branch (computation left) (computation right)) .nil sum evaluated
  refine ⟨count + 1, by omega, (steps.in_context (definitions table) outside).trans (.single ?_)⟩
  apply Target.CallStep.branchRight
  exact (sum_right_is_preserved_and_reflected sum (value payload)).mpr ⟨payload, selected, rfl⟩

/-- The test expression's fault exits before either ordinary branch body is
entered. Earlier operand ownership still belongs to the exit/handoff contract. -/
theorem compiled_match_fault (table : Source.Definitions signature algebra program)
    (expression : Source.Expression signature algebra program context (.sum leftType rightType))
    (left : Source.Computation signature algebra program (leftType :: context) result)
    (right : Source.Computation signature algebra program (rightType :: context) result)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (failed : expression.evaluate bindings = .error fault)
    (outside : Target.Stack signature algebra program result answer) :
    Source.Step table (.evaluate (.matchSum expression left right) bindings) (.failed fault) ∧
      ∃ count, 0 < count ∧ Target.CallSteps (definitions table)
        (.code (computation (.matchSum expression left right)) (environment bindings) .nil outside) count (.failed fault outside) := by
  refine ⟨.matchFault failed, ?_⟩
  obtain ⟨count, final, steps, faulted⟩ := expression_fault_drains expression bindings
    (.branch (computation left) (computation right)) .nil fault failed
  cases faulted
  exact ⟨count + 1, by omega, (steps.in_context (definitions table) outside).trans (.single .fault)⟩

/-- Every typed sum test has a positive finite compiled execution in every
represented enclosing context. The evaluator's actual outcome selects the
case; the theorem does not require a successful test or a chosen branch. -/
theorem compiled_match_in_every_context (table : Source.Definitions signature algebra program)
    (expression : Source.Expression signature algebra program context (.sum leftType rightType))
    (left : Source.Computation signature algebra program (leftType :: context) result)
    (right : Source.Computation signature algebra program (rightType :: context) result)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    {sourceOutside : Source.Context signature algebra program result answer}
    {targetOutside : Target.Stack signature algebra program result answer}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside) :
    ∃ count sourceAfter targetAfter, 0 < count ∧
      Source.Step table (sourceOutside.plug (.evaluate (.matchSum expression left right) bindings)) sourceAfter ∧
      Target.CallSteps (definitions table)
        (.code (computation (.matchSum expression left right)) (environment bindings) .nil targetOutside) count targetAfter ∧
      EntryRelated sourceAfter targetAfter := by
  cases evaluated : expression.evaluate bindings with
  | error fault =>
    obtain ⟨sourceStep, count, positive, targetSteps⟩ := compiled_match_fault table expression left right bindings evaluated targetOutside
    exact ⟨count, _, _, positive, sourceStep.in_context sourceOutside, targetSteps, .failed fault outside⟩
  | ok sum =>
    cases selected : sum.asSum with
    | inl payload =>
      obtain ⟨sourceStep, count, positive, targetSteps⟩ := compiled_match_left table expression left right bindings sum payload evaluated selected targetOutside
      exact ⟨count, _, _, positive, sourceStep.in_context sourceOutside, targetSteps, .evaluate left (.cons payload bindings) outside⟩
    | inr payload =>
      obtain ⟨sourceStep, count, positive, targetSteps⟩ := compiled_match_right table expression left right bindings sum payload evaluated selected targetOutside
      exact ⟨count, _, _, positive, sourceStep.in_context sourceOutside, targetSteps, .evaluate right (.cons payload bindings) outside⟩

/-- Once the expression prelude has supplied its represented sum, an actual
target branch step cannot choose another tag or an unrelated payload. -/
theorem compiled_branch_step_reflects (table : Source.Definitions signature algebra program)
    (expression : Source.Expression signature algebra program context (.sum leftType rightType))
    (left : Source.Computation signature algebra program (leftType :: context) result)
    (right : Source.Computation signature algebra program (rightType :: context) result)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (sum : Source.RuntimeValue signature algebra program (.sum leftType rightType))
    (evaluated : expression.evaluate bindings = .ok sum)
    {sourceOutside : Source.Context signature algebra program result answer}
    {targetOutside : Target.Stack signature algebra program result answer}
    (outside : ContextRelated signature algebra program sourceOutside targetOutside)
    {targetAfter : Target.Configuration signature algebra program answer}
    (step : Target.CallStep (definitions table)
      (.code (.branch (computation left) (computation right)) (environment bindings) (.cons (value sum) .nil) targetOutside) targetAfter) :
    ∃ sourceAfter, Source.Step table
      (sourceOutside.plug (.evaluate (.matchSum expression left right) bindings)) sourceAfter ∧ EntryRelated sourceAfter targetAfter := by
  have destination := step.branch_next rfl
  have encoded := Value.map_asSum (fun _ _ body => computation body) sum
  cases selected : sum.asSum with
  | inl payload =>
    simp only [selected, Sum.map_inl] at encoded
    simp only [Target.Configuration.branchNext, Target.branchNextCode, value, encoded, Option.some.injEq] at destination
    subst targetAfter
    exact ⟨_, (Source.Step.matchLeft evaluated selected).in_context sourceOutside, .evaluate left (.cons payload bindings) outside⟩
  | inr payload =>
    simp only [selected, Sum.map_inr] at encoded
    simp only [Target.Configuration.branchNext, Target.branchNextCode, value, encoded, Option.some.injEq] at destination
    subst targetAfter
    exact ⟨_, (Source.Step.matchRight evaluated selected).in_context sourceOutside, .evaluate right (.cons payload bindings) outside⟩

end BoundaryV2.Generalized.Defunctionalization
