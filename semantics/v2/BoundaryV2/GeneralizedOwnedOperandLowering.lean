import BoundaryV2.GeneralizedOwnedOperands
import BoundaryV2.GeneralizedOperandPrefix

namespace BoundaryV2.Generalized.Defunctionalization

open Target

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {program : List (BodyType signature.Data signature.Effect)} {SourceFuture TargetFuture : Type}

private theorem owned_results_bounded
    (related : SourceFuture → TargetFuture → Prop)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (reserved : List (Id .custody)) (bound : Nat) :
    (∀ {type} (source : Source.Expression signature algebra program context type), sizeOf source < bound →
      ∀ {sourceStore sourceAfter : UseScope.ControlStore SourceFuture} {targetStore : UseScope.ControlStore TargetFuture}
        (returned : Source.RuntimeValue signature algebra program type),
      Source.ExpressionEvaluation bindings reserved sourceStore source (.ok returned) sourceAfter →
      ∀ {stack result} (next : Code signature algebra program context (type :: stack) result)
        (values : Target.RuntimeEnvironment signature algebra program stack),
      UseScope.ControlStore.Related related sourceStore targetStore →
      ∃ count targetAfter, 0 < count ∧ OwnedOperandSteps (environment bindings) reserved targetStore
        ⟨_, expression source next, values⟩ count targetAfter ⟨_, next, .cons (value returned) values⟩ ∧
        UseScope.ControlStore.Related related sourceAfter targetAfter) ∧
    (∀ {types} (source : Source.Arguments signature algebra program context types), sizeOf source < bound →
      ∀ {sourceStore sourceAfter : UseScope.ControlStore SourceFuture} {targetStore : UseScope.ControlStore TargetFuture}
        (returned : Source.RuntimeEnvironment signature algebra program types),
      Source.ArgumentsEvaluation bindings reserved sourceStore source (.ok returned) sourceAfter →
      ∀ {stack result} (next : Code signature algebra program context (types.reverse ++ stack) result)
        (values : Target.RuntimeEnvironment signature algebra program stack),
      UseScope.ControlStore.Related related sourceStore targetStore →
      ∃ count targetAfter, OwnedOperandSteps (environment bindings) reserved targetStore
        ⟨_, arguments source next, values⟩ count targetAfter ⟨_, next, (environment returned).pushReverse values⟩ ∧
        UseScope.ControlStore.Related related sourceAfter targetAfter) := by
  cases bound with
  | zero => constructor <;> intro types source sized <;> omega
  | succ bound =>
    obtain ⟨expressions, argumentLists⟩ := owned_results_bounded related bindings reserved bound
    constructor
    · intro type source sized sourceStore sourceAfter targetStore returned evaluated stack result next values stores
      cases evaluated with
      | datum => exact ⟨1, targetStore, by omega, .single (.ordinary .push rfl), stores⟩
      | reference =>
        refine ⟨1, targetStore, by omega, ?_, stores⟩
        simpa only [expression, lexical_lookup_corresponds] using
          OwnedOperandSteps.single (OwnedOperandStep.ordinary (store := targetStore)
            (OperandStep.load (environment := environment bindings) (next := next) (values := values)) rfl)
      | closure evaluated => exact compiled_lambda_evaluation related bindings reserved _ _ evaluated next values stores
      | @pair before left first firstValue middle right second secondValue after firstStep secondStep =>
        obtain ⟨firstCount, middleTarget, _, firstSteps, middleRelated⟩ :=
          expressions first (by simp_all; omega) firstValue firstStep (expression second (.pair next)) values stores
        obtain ⟨secondCount, finalTarget, _, secondSteps, finalRelated⟩ :=
          expressions second (by simp_all; omega) secondValue secondStep (.pair next)
            (.cons (value firstValue) values) middleRelated
        exact ⟨firstCount + (secondCount + 1), finalTarget, by omega,
          firstSteps.trans (secondSteps.trans (.single (.ordinary .pair rfl))), finalRelated⟩
      | @first before left right operand pairValue after evaluated =>
        obtain ⟨count, finalTarget, _, steps, finalRelated⟩ :=
          expressions operand (by simp_all; omega) pairValue evaluated (.first next) values stores
        refine ⟨count + 1, finalTarget, by omega, steps.trans ?_, finalRelated⟩
        simpa only [value, Value.first_map] using OwnedOperandSteps.single
          (OwnedOperandStep.ordinary (store := finalTarget)
            (OperandStep.first (environment := environment bindings) (value := value pairValue) (next := next) (values := values)) rfl)
      | @second before left right operand pairValue after evaluated =>
        obtain ⟨count, finalTarget, _, steps, finalRelated⟩ :=
          expressions operand (by simp_all; omega) pairValue evaluated (.second next) values stores
        refine ⟨count + 1, finalTarget, by omega, steps.trans ?_, finalRelated⟩
        simpa only [value, Value.second_map] using OwnedOperandSteps.single
          (OwnedOperandStep.ordinary (store := finalTarget)
            (OperandStep.second (environment := environment bindings) (value := value pairValue) (next := next) (values := values)) rfl)
      | @left before left right operand operandValue after evaluated =>
        obtain ⟨count, finalTarget, _, steps, finalRelated⟩ :=
          expressions operand (by simp_all; omega) operandValue evaluated (.left next) values stores
        exact ⟨count + 1, finalTarget, by omega, steps.trans (.single (.ordinary .left rfl)), finalRelated⟩
      | @right before left right operand operandValue after evaluated =>
        obtain ⟨count, finalTarget, _, steps, finalRelated⟩ :=
          expressions operand (by simp_all; omega) operandValue evaluated (.right next) values stores
        exact ⟨count + 1, finalTarget, by omega, steps.trans (.single (.ordinary .right rfl)), finalRelated⟩
      | @primitive before after parameters answer operation inputs argumentsValue primitiveValue evaluated primitiveResult =>
        obtain ⟨count, finalTarget, steps, finalRelated⟩ :=
          argumentLists inputs (by simp_all; omega) argumentsValue evaluated (.primitive operation next) values stores
        refine ⟨count + 1, finalTarget, by omega, steps.trans (.single (.ordinary (.primitive ?_) rfl)), finalRelated⟩
        simpa only [environment, Environment.leaves_map] using primitiveResult
    · intro types source sized sourceStore sourceAfter targetStore returned evaluated stack result next values stores
      cases evaluated with
      | nil => exact ⟨0, targetStore, .refl, stores⟩
      | @cons before type first firstValue middle types rest restValues after firstStep restStep =>
        let nextRest : Code signature algebra program context (_ ++ _ :: stack) result := by
          simpa only [List.reverse_cons, List.append_assoc, List.singleton_append] using next
        obtain ⟨firstCount, middleTarget, _, firstSteps, middleRelated⟩ :=
          expressions first (by simp_all; omega) firstValue firstStep (arguments rest nextRest) values stores
        obtain ⟨restCount, finalTarget, restSteps, finalRelated⟩ :=
          argumentLists rest (by simp_all; omega) restValues restStep nextRest (.cons (value firstValue) values) middleRelated
        refine ⟨firstCount + restCount, finalTarget, ?_, finalRelated⟩
        have finish := Operands.reindex (by
          simp only [List.reverse_cons, List.append_assoc, List.singleton_append]) next
          ((environment restValues).pushReverse (.cons (value firstValue) values))
        exact finish.symm ▸ firstSteps.trans restSteps
  termination_by bound

theorem owned_expression_drains
    (related : SourceFuture → TargetFuture → Prop)
    (bindings : Source.RuntimeEnvironment signature algebra program context) (reserved : List (Id .custody))
    (source : Source.Expression signature algebra program context type)
    {sourceStore sourceAfter : UseScope.ControlStore SourceFuture} {targetStore : UseScope.ControlStore TargetFuture}
    (returned : Source.RuntimeValue signature algebra program type)
    (evaluated : Source.ExpressionEvaluation bindings reserved sourceStore source (.ok returned) sourceAfter)
    (next : Code signature algebra program context (type :: stack) result)
    (values : Target.RuntimeEnvironment signature algebra program stack)
    (stores : UseScope.ControlStore.Related related sourceStore targetStore) :
    ∃ count targetAfter, 0 < count ∧ OwnedOperandSteps (environment bindings) reserved targetStore
      ⟨_, expression source next, values⟩ count targetAfter ⟨_, next, .cons (value returned) values⟩ ∧
      UseScope.ControlStore.Related related sourceAfter targetAfter :=
  (owned_results_bounded related bindings reserved (sizeOf source + 1)).1
    source (Nat.lt_succ_self _) returned evaluated next values stores

theorem owned_arguments_drains
    (related : SourceFuture → TargetFuture → Prop)
    (bindings : Source.RuntimeEnvironment signature algebra program context) (reserved : List (Id .custody))
    (source : Source.Arguments signature algebra program context types)
    {sourceStore sourceAfter : UseScope.ControlStore SourceFuture} {targetStore : UseScope.ControlStore TargetFuture}
    (returned : Source.RuntimeEnvironment signature algebra program types)
    (evaluated : Source.ArgumentsEvaluation bindings reserved sourceStore source (.ok returned) sourceAfter)
    (next : Code signature algebra program context (types.reverse ++ stack) result)
    (values : Target.RuntimeEnvironment signature algebra program stack)
    (stores : UseScope.ControlStore.Related related sourceStore targetStore) :
    ∃ count targetAfter, OwnedOperandSteps (environment bindings) reserved targetStore
      ⟨_, arguments source next, values⟩ count targetAfter ⟨_, next, (environment returned).pushReverse values⟩ ∧
      UseScope.ControlStore.Related related sourceAfter targetAfter :=
  (owned_results_bounded related bindings reserved (sizeOf source + 1)).2
    source (Nat.lt_succ_self _) returned evaluated next values stores

theorem owned_two_operands_drains
    (related : SourceFuture → TargetFuture → Prop)
    (bindings : Source.RuntimeEnvironment signature algebra program context) (reserved : List (Id .custody))
    (first : Source.Expression signature algebra program context firstType)
    (second : Source.Expression signature algebra program context secondType)
    (firstValue : Source.RuntimeValue signature algebra program firstType)
    (secondValue : Source.RuntimeValue signature algebra program secondType)
    {sourceStore sourceAfter : UseScope.ControlStore SourceFuture} {targetStore : UseScope.ControlStore TargetFuture}
    (evaluated : Source.ArgumentsEvaluation bindings reserved sourceStore (.cons first (.cons second .nil))
      (.ok (.cons firstValue (.cons secondValue .nil))) sourceAfter)
    (next : Code signature algebra program context [secondType, firstType] result)
    (stores : UseScope.ControlStore.Related related sourceStore targetStore) :
    ∃ count targetAfter, OwnedOperandSteps (environment bindings) reserved targetStore
      ⟨_, expression first (expression second next), .nil⟩ count targetAfter
      ⟨_, next, .cons (value secondValue) (.cons (value firstValue) .nil)⟩ ∧
      UseScope.ControlStore.Related related sourceAfter targetAfter := by
  cases evaluated with
  | cons firstStep tail =>
    cases tail with
    | cons secondStep rest =>
      cases rest
      obtain ⟨firstCount, middle, _, firstSteps, middleRelated⟩ :=
        owned_expression_drains related bindings reserved first firstValue firstStep (expression second next) .nil stores
      obtain ⟨secondCount, after, _, secondSteps, afterRelated⟩ :=
        owned_expression_drains related bindings reserved second secondValue secondStep next
          (.cons (value firstValue) .nil) middleRelated
      exact ⟨firstCount + secondCount, after, firstSteps.trans secondSteps, afterRelated⟩

private theorem owned_faults_bounded
    (related : SourceFuture → TargetFuture → Prop)
    (bindings : Source.RuntimeEnvironment signature algebra program context)
    (reserved : List (Id .custody)) (bound : Nat) :
    (∀ {type} (source : Source.Expression signature algebra program context type), sizeOf source < bound →
      ∀ {sourceStore sourceAfter : UseScope.ControlStore SourceFuture} {targetStore : UseScope.ControlStore TargetFuture}
        (fault : algebra.Fault),
      Source.ExpressionEvaluation bindings reserved sourceStore source (.error fault) sourceAfter →
      ∀ {stack result} (next : Code signature algebra program context (type :: stack) result)
        (values : Target.RuntimeEnvironment signature algebra program stack),
      UseScope.ControlStore.Related related sourceStore targetStore →
      ∃ count targetAfter final, OwnedOperandSteps (environment bindings) reserved targetStore
        ⟨_, expression source next, values⟩ count targetAfter final ∧ Faulted fault final ∧
        UseScope.ControlStore.Related related sourceAfter targetAfter) ∧
    (∀ {types} (source : Source.Arguments signature algebra program context types), sizeOf source < bound →
      ∀ {sourceStore sourceAfter : UseScope.ControlStore SourceFuture} {targetStore : UseScope.ControlStore TargetFuture}
        (fault : algebra.Fault),
      Source.ArgumentsEvaluation bindings reserved sourceStore source (.error fault) sourceAfter →
      ∀ {stack result} (next : Code signature algebra program context (types.reverse ++ stack) result)
        (values : Target.RuntimeEnvironment signature algebra program stack),
      UseScope.ControlStore.Related related sourceStore targetStore →
      ∃ count targetAfter final, OwnedOperandSteps (environment bindings) reserved targetStore
        ⟨_, arguments source next, values⟩ count targetAfter final ∧ Faulted fault final ∧
        UseScope.ControlStore.Related related sourceAfter targetAfter) := by
  cases bound with
  | zero => constructor <;> intro types source sized <;> omega
  | succ bound =>
    obtain ⟨expressions, argumentLists⟩ := owned_faults_bounded related bindings reserved bound
    constructor
    · intro type source sized sourceStore sourceAfter targetStore fault evaluated stack result next values stores
      cases evaluated with
      | @pairFirstFault before left first fault after right second failed =>
        exact expressions first (by simp_all; omega) fault failed (expression second (.pair next)) values stores
      | @pairSecondFault before left first firstValue middle right second fault after firstStep failed =>
        obtain ⟨firstCount, middleTarget, _, firstSteps, middleRelated⟩ := owned_expression_drains
          related bindings reserved first firstValue firstStep (expression second (.pair next)) values stores
        obtain ⟨faultCount, finalTarget, final, failedSteps, faulted, finalRelated⟩ :=
          expressions second (by simp_all; omega) fault failed (.pair next) (.cons (value firstValue) values) middleRelated
        exact ⟨firstCount + faultCount, finalTarget, final, firstSteps.trans failedSteps, faulted, finalRelated⟩
      | @firstFault before left right operand fault after failed =>
        exact expressions operand (by simp_all; omega) fault failed (.first next) values stores
      | @secondFault before left right operand fault after failed =>
        exact expressions operand (by simp_all; omega) fault failed (.second next) values stores
      | @leftFault right before left operand fault after failed =>
        exact expressions operand (by simp_all; omega) fault failed (.left next) values stores
      | @rightFault left before right operand fault after failed =>
        exact expressions operand (by simp_all; omega) fault failed (.right next) values stores
      | @primitiveInputFault before fault after parameters answer operation inputs failed =>
        exact argumentLists inputs (by simp_all; omega) fault failed (.primitive operation next) values stores
      | @primitiveFault before after fault parameters answer operation inputs inputsValue evaluated primitiveResult =>
        obtain ⟨count, finalTarget, steps, finalRelated⟩ := owned_arguments_drains
          related bindings reserved inputs inputsValue evaluated (.primitive operation next) values stores
        refine ⟨count + 1, finalTarget, _, steps.trans (.single (.ordinary (.primitiveFault ?_) rfl)), .fault, finalRelated⟩
        simpa only [environment, Environment.leaves_map] using primitiveResult
    · intro types source sized sourceStore sourceAfter targetStore fault evaluated stack result next values stores
      cases evaluated with
      | @firstFault before type first fault after types rest failed =>
        let nextRest : Code signature algebra program context (_ ++ _ :: stack) result := by
          simpa only [List.reverse_cons, List.append_assoc, List.singleton_append] using next
        exact expressions first (by simp_all; omega) fault failed (arguments rest nextRest) values stores
      | @restFault before type first firstValue middle types rest fault after firstStep failed =>
        let nextRest : Code signature algebra program context (_ ++ _ :: stack) result := by
          simpa only [List.reverse_cons, List.append_assoc, List.singleton_append] using next
        obtain ⟨firstCount, middleTarget, _, firstSteps, middleRelated⟩ := owned_expression_drains
          related bindings reserved first firstValue firstStep (arguments rest nextRest) values stores
        obtain ⟨faultCount, finalTarget, final, failedSteps, faulted, finalRelated⟩ :=
          argumentLists rest (by simp_all; omega) fault failed nextRest (.cons (value firstValue) values) middleRelated
        exact ⟨firstCount + faultCount, finalTarget, final, firstSteps.trans failedSteps, faulted, finalRelated⟩
  termination_by bound

theorem owned_expression_fault_drains
    (related : SourceFuture → TargetFuture → Prop)
    (bindings : Source.RuntimeEnvironment signature algebra program context) (reserved : List (Id .custody))
    (source : Source.Expression signature algebra program context type)
    {sourceStore sourceAfter : UseScope.ControlStore SourceFuture} {targetStore : UseScope.ControlStore TargetFuture}
    (fault : algebra.Fault)
    (evaluated : Source.ExpressionEvaluation bindings reserved sourceStore source (.error fault) sourceAfter)
    (next : Code signature algebra program context (type :: stack) result)
    (values : Target.RuntimeEnvironment signature algebra program stack)
    (stores : UseScope.ControlStore.Related related sourceStore targetStore) :
    ∃ count targetAfter final, OwnedOperandSteps (environment bindings) reserved targetStore
      ⟨_, expression source next, values⟩ count targetAfter final ∧ Faulted fault final ∧
      UseScope.ControlStore.Related related sourceAfter targetAfter :=
  (owned_faults_bounded related bindings reserved (sizeOf source + 1)).1
    source (Nat.lt_succ_self _) fault evaluated next values stores

theorem owned_arguments_fault_drains
    (related : SourceFuture → TargetFuture → Prop)
    (bindings : Source.RuntimeEnvironment signature algebra program context) (reserved : List (Id .custody))
    (source : Source.Arguments signature algebra program context types)
    {sourceStore sourceAfter : UseScope.ControlStore SourceFuture} {targetStore : UseScope.ControlStore TargetFuture}
    (fault : algebra.Fault)
    (evaluated : Source.ArgumentsEvaluation bindings reserved sourceStore source (.error fault) sourceAfter)
    (next : Code signature algebra program context (types.reverse ++ stack) result)
    (values : Target.RuntimeEnvironment signature algebra program stack)
    (stores : UseScope.ControlStore.Related related sourceStore targetStore) :
    ∃ count targetAfter final, OwnedOperandSteps (environment bindings) reserved targetStore
      ⟨_, arguments source next, values⟩ count targetAfter final ∧ Faulted fault final ∧
      UseScope.ControlStore.Related related sourceAfter targetAfter :=
  (owned_faults_bounded related bindings reserved (sizeOf source + 1)).2
    source (Nat.lt_succ_self _) fault evaluated next values stores

/-- The same ownership-aware operand law reaches the receiving instruction of
every computation constructor, including scoped bodies and injected closures. -/
theorem owned_computation_operand_prefix_drains
    (related : SourceFuture → TargetFuture → Prop)
    (bindings : Source.RuntimeEnvironment signature algebra program context) (reserved : List (Id .custody))
    (source : Source.Computation signature algebra program context result)
    {sourceStore sourceAfter : UseScope.ControlStore SourceFuture} {targetStore : UseScope.ControlStore TargetFuture}
    (returned : Source.RuntimeEnvironment signature algebra program source.operandPrefix.types)
    (evaluated : Source.ArgumentsEvaluation bindings reserved sourceStore source.operandPrefix.arguments (.ok returned) sourceAfter)
    (stores : UseScope.ControlStore.Related related sourceStore targetStore) :
    ∃ count targetAfter, OwnedOperandSteps (environment bindings) reserved targetStore
      ⟨_, computation source, .nil⟩ count targetAfter
      ⟨_, operandTail source, (environment returned).pushReverse .nil⟩ ∧
      UseScope.ControlStore.Related related sourceAfter targetAfter := by
  simpa only [computation_operand_prefix] using
    owned_arguments_drains related bindings reserved source.operandPrefix.arguments returned evaluated (operandTail source) .nil stores

theorem owned_computation_operand_fault_drains
    (related : SourceFuture → TargetFuture → Prop)
    (bindings : Source.RuntimeEnvironment signature algebra program context) (reserved : List (Id .custody))
    (source : Source.Computation signature algebra program context result)
    {sourceStore sourceAfter : UseScope.ControlStore SourceFuture} {targetStore : UseScope.ControlStore TargetFuture}
    (fault : algebra.Fault)
    (evaluated : Source.ArgumentsEvaluation bindings reserved sourceStore source.operandPrefix.arguments (.error fault) sourceAfter)
    (stores : UseScope.ControlStore.Related related sourceStore targetStore) :
    ∃ count targetAfter final, OwnedOperandSteps (environment bindings) reserved targetStore
      ⟨_, computation source, .nil⟩ count targetAfter final ∧ Faulted fault final ∧
      UseScope.ControlStore.Related related sourceAfter targetAfter := by
  simpa only [computation_operand_prefix] using
    owned_arguments_fault_drains related bindings reserved source.operandPrefix.arguments fault evaluated (operandTail source) .nil stores

end BoundaryV2.Generalized.Defunctionalization
