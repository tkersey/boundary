import BoundaryV2.GeneralizedOperands

namespace BoundaryV2.Generalized.Defunctionalization

open Target

variable {signature : Signature} {algebra : LeafAlgebra signature.Data}
  {definitions : List (BodyType signature.Data signature.Effect)}

theorem selection_drains (captures : Selection context captured)
    (environment : Target.RuntimeEnvironment signature algebra definitions context)
    (next : Code signature algebra definitions context (captured.reverse ++ stack) result)
    (values : Target.RuntimeEnvironment signature algebra definitions stack) :
    ∃ count, OperandSteps environment ⟨_, selection captures next, values⟩ count
      ⟨_, next, (environment.select captures).pushReverse values⟩ := by
  induction captures generalizing stack with
  | nil => exact ⟨0, .refl⟩
  | cons reference rest induction =>
    obtain ⟨count, steps⟩ := induction (by
      simpa only [List.reverse_cons, List.append_assoc, List.singleton_append] using next)
      (.cons (environment.lookup reference) values)
    refine ⟨count + 1, ?_⟩
    have finish := Operands.reindex (by
      simp only [List.reverse_cons, List.append_assoc, List.singleton_append]) next
      ((environment.select rest).pushReverse (.cons (environment.lookup reference) values))
    exact finish.symm ▸ OperandSteps.cons .load steps

/- The target's continuation code and pre-existing operand stack are arbitrary.
The source expression therefore composes with every receiving control operation,
including operation dispatch and calls with computation-valued arguments. -/
mutual
  private theorem expression_drains_bounded (bound : Nat) (source : Source.Expression signature algebra definitions context type)
      (sized : sizeOf source < bound)
      (bindings : Source.RuntimeEnvironment signature algebra definitions context)
      (next : Code signature algebra definitions context (type :: stack) result)
      (values : Target.RuntimeEnvironment signature algebra definitions stack)
      (returned : Source.RuntimeValue signature algebra definitions type)
      (evaluated : source.evaluate bindings = .ok returned) :
      ∃ count, OperandSteps (environment bindings) ⟨_, expression source next, values⟩ count
        ⟨_, next, .cons (value returned) values⟩ := by
    cases bound with
    | zero => omega
    | succ bound =>
      cases source with
      | datum datum =>
        cases evaluated
        exact ⟨1, .single .push⟩
      | reference reference =>
        cases evaluated
        refine ⟨1, ?_⟩
        simpa only [expression, lexical_lookup_corresponds] using
          OperandSteps.single (OperandStep.load (environment := environment bindings) (reference := reference) (next := next) (values := values))
      | pair first second =>
        cases firstResult : first.evaluate bindings with
        | error fault => simp [Source.Expression.evaluate, firstResult] at evaluated
        | ok firstValue =>
          cases secondResult : second.evaluate bindings with
          | error fault => simp [Source.Expression.evaluate, firstResult, secondResult] at evaluated
          | ok secondValue =>
            have returnedEqual : Value.pair firstValue secondValue = returned := by
              simpa [Source.Expression.evaluate, firstResult, secondResult] using evaluated
            subst returned
            obtain ⟨firstCount, firstSteps⟩ := expression_drains_bounded bound first (by simp_all; omega) bindings (expression second (.pair next)) values firstValue firstResult
            obtain ⟨secondCount, secondSteps⟩ := expression_drains_bounded bound second (by simp_all; omega) bindings (.pair next)
              (.cons (value firstValue) values) secondValue secondResult
            exact ⟨firstCount + (secondCount + 1), firstSteps.trans (secondSteps.trans (.single .pair))⟩
      | first operand =>
        cases operandResult : operand.evaluate bindings with
        | error fault => simp [Source.Expression.evaluate, Except.map, operandResult] at evaluated
        | ok pairValue =>
          have returnedEqual : pairValue.first = returned := by simpa [Source.Expression.evaluate, Except.map, operandResult] using evaluated
          subst returned
          obtain ⟨count, steps⟩ := expression_drains_bounded bound operand (by simp_all; omega) bindings (.first next) values pairValue operandResult
          refine ⟨count + 1, steps.trans ?_⟩
          simpa only [value, Value.first_map] using OperandSteps.single
            (OperandStep.first (environment := environment bindings) (next := next) (value := value pairValue) (values := values))
      | second operand =>
        cases operandResult : operand.evaluate bindings with
        | error fault => simp [Source.Expression.evaluate, Except.map, operandResult] at evaluated
        | ok pairValue =>
          have returnedEqual : pairValue.second = returned := by simpa [Source.Expression.evaluate, Except.map, operandResult] using evaluated
          subst returned
          obtain ⟨count, steps⟩ := expression_drains_bounded bound operand (by simp_all; omega) bindings (.second next) values pairValue operandResult
          refine ⟨count + 1, steps.trans ?_⟩
          simpa only [value, Value.second_map] using OperandSteps.single
            (OperandStep.second (environment := environment bindings) (next := next) (value := value pairValue) (values := values))
      | left operand =>
        cases operandResult : operand.evaluate bindings with
        | error fault => simp [Source.Expression.evaluate, Except.map, operandResult] at evaluated
        | ok operandValue =>
          have returnedEqual : Value.left operandValue = returned := by simpa [Source.Expression.evaluate, Except.map, operandResult] using evaluated
          subst returned
          obtain ⟨count, steps⟩ := expression_drains_bounded bound operand (by simp_all; omega) bindings (.left next) values operandValue operandResult
          exact ⟨count + 1, steps.trans (.single .left)⟩
      | right operand =>
        cases operandResult : operand.evaluate bindings with
        | error fault => simp [Source.Expression.evaluate, Except.map, operandResult] at evaluated
        | ok operandValue =>
          have returnedEqual : Value.right operandValue = returned := by simpa [Source.Expression.evaluate, Except.map, operandResult] using evaluated
          subst returned
          obtain ⟨count, steps⟩ := expression_drains_bounded bound operand (by simp_all; omega) bindings (.right next) values operandValue operandResult
          exact ⟨count + 1, steps.trans (.single .right)⟩
      | primitive operation inputs =>
        cases inputsResult : inputs.evaluate bindings with
        | error fault => simp [Source.Expression.evaluate, inputsResult] at evaluated
        | ok argumentsValue =>
          cases primitiveResult : algebra.evaluate operation argumentsValue.leaves with
          | error fault => simp [Source.Expression.evaluate, Except.map, inputsResult, primitiveResult] at evaluated
          | ok primitiveValue =>
            have returnedEqual : Value.datum (Datum.leaf primitiveValue) = returned := by
              simpa [Source.Expression.evaluate, Except.map, inputsResult, primitiveResult] using evaluated
            subst returned
            obtain ⟨count, steps⟩ := arguments_drains_bounded bound inputs (by simp_all; omega) bindings (.primitive operation next) values argumentsValue inputsResult
            refine ⟨count + 1, steps.trans (.single (.primitive ?_))⟩
            simpa only [environment, Environment.leaves_map] using primitiveResult
      | lambda captures body =>
        cases evaluated
        obtain ⟨count, steps⟩ := selection_drains captures (environment bindings) (.close (computation body) next) values
        refine ⟨count + 1, steps.trans ?_⟩
        simpa only [value, environment, Value.map, Environment.select_map] using OperandSteps.single
          (OperandStep.close (environment := environment bindings) (body := computation body)
            (captured := (environment bindings).select captures) (next := next) (values := values))
  termination_by bound

  private theorem arguments_drains_bounded (bound : Nat) (source : Source.Arguments signature algebra definitions context types)
      (sized : sizeOf source < bound)
      (bindings : Source.RuntimeEnvironment signature algebra definitions context)
      (next : Code signature algebra definitions context (types.reverse ++ stack) result)
      (values : Target.RuntimeEnvironment signature algebra definitions stack)
      (returned : Source.RuntimeEnvironment signature algebra definitions types)
      (evaluated : source.evaluate bindings = .ok returned) :
      ∃ count, OperandSteps (environment bindings) ⟨_, arguments source next, values⟩ count
        ⟨_, next, (environment returned).pushReverse values⟩ := by
    cases bound with
    | zero => omega
    | succ bound =>
      cases source with
      | nil => cases evaluated; exact ⟨0, .refl⟩
      | cons first rest =>
        cases firstResult : first.evaluate bindings with
        | error fault => simp [Source.Arguments.evaluate, firstResult] at evaluated
        | ok firstValue =>
          cases restResult : rest.evaluate bindings with
          | error fault => simp [Source.Arguments.evaluate, firstResult, restResult] at evaluated
          | ok restValues =>
            have returnedEqual : Environment.cons firstValue restValues = returned := by
              simpa [Source.Arguments.evaluate, firstResult, restResult] using evaluated
            subst returned
            let nextRest : Code signature algebra definitions context (_ ++ _ :: stack) result := by
              simpa only [List.reverse_cons, List.append_assoc, List.singleton_append] using next
            obtain ⟨firstCount, firstSteps⟩ := expression_drains_bounded bound first (by simp_all; omega) bindings (arguments rest nextRest) values firstValue firstResult
            obtain ⟨restCount, restSteps⟩ := arguments_drains_bounded bound rest (by simp_all; omega) bindings nextRest (.cons (value firstValue) values) restValues restResult
            refine ⟨firstCount + restCount, ?_⟩
            have finish := Operands.reindex (by
              simp only [List.reverse_cons, List.append_assoc, List.singleton_append]) next
              ((environment restValues).pushReverse (.cons (value firstValue) values))
            exact finish.symm ▸ firstSteps.trans restSteps
  termination_by bound
end

theorem expression_drains (source : Source.Expression signature algebra definitions context type)
    (bindings : Source.RuntimeEnvironment signature algebra definitions context)
    (next : Code signature algebra definitions context (type :: stack) result)
    (values : Target.RuntimeEnvironment signature algebra definitions stack)
    (returned : Source.RuntimeValue signature algebra definitions type)
    (evaluated : source.evaluate bindings = .ok returned) :
    ∃ count, OperandSteps (environment bindings) ⟨_, expression source next, values⟩ count
      ⟨_, next, .cons (value returned) values⟩ :=
  expression_drains_bounded (sizeOf source + 1) source (Nat.lt_succ_self _) bindings next values returned evaluated

theorem arguments_drains (source : Source.Arguments signature algebra definitions context types)
    (bindings : Source.RuntimeEnvironment signature algebra definitions context)
    (next : Code signature algebra definitions context (types.reverse ++ stack) result)
    (values : Target.RuntimeEnvironment signature algebra definitions stack)
    (returned : Source.RuntimeEnvironment signature algebra definitions types)
    (evaluated : source.evaluate bindings = .ok returned) :
    ∃ count, OperandSteps (environment bindings) ⟨_, arguments source next, values⟩ count
      ⟨_, next, (environment returned).pushReverse values⟩ :=
  arguments_drains_bounded (sizeOf source + 1) source (Nat.lt_succ_self _) bindings next values returned evaluated

theorem expression_drains_positive (source : Source.Expression signature algebra definitions context type)
    (bindings : Source.RuntimeEnvironment signature algebra definitions context)
    (next : Code signature algebra definitions context (type :: stack) result)
    (values : Target.RuntimeEnvironment signature algebra definitions stack)
    (returned : Source.RuntimeValue signature algebra definitions type)
    (evaluated : source.evaluate bindings = .ok returned) :
    ∃ count, 0 < count ∧ OperandSteps (environment bindings) ⟨_, expression source next, values⟩ count
      ⟨_, next, .cons (value returned) values⟩ := by
  obtain ⟨count, steps⟩ := expression_drains source bindings next values returned evaluated
  refine ⟨count, ?_, steps⟩
  cases count with
  | zero =>
    have impossible := congrArg (fun state => state.types.length) (OperandSteps.zero_eq steps)
    simp at impossible
  | succ count => omega

/- The natural-number bound below is induction on finite expression syntax.
It is not part of either evaluator, code, or an execution horizon. -/
mutual
  private theorem expression_fault_bounded (bound : Nat)
      (source : Source.Expression signature algebra definitions context type) (sized : sizeOf source < bound)
      (bindings : Source.RuntimeEnvironment signature algebra definitions context)
      (next : Code signature algebra definitions context (type :: stack) result)
      (values : Target.RuntimeEnvironment signature algebra definitions stack) (fault : algebra.Fault)
      (failed : source.evaluate bindings = .error fault) :
      ReachesFault (environment bindings) ⟨_, expression source next, values⟩ fault := by
    cases bound with
    | zero => omega
    | succ bound =>
      cases source with
      | datum datum | reference reference | lambda captures body => simp [Source.Expression.evaluate] at failed
      | pair first second =>
        cases firstResult : first.evaluate bindings with
        | error priorFault =>
          have same : priorFault = fault := by simpa [Source.Expression.evaluate, firstResult] using failed
          subst fault
          exact expression_fault_bounded bound first (by simp_all; omega) bindings
            (expression second (.pair next)) values priorFault firstResult
        | ok firstValue =>
          cases secondResult : second.evaluate bindings with
          | ok secondValue => simp [Source.Expression.evaluate, firstResult, secondResult] at failed
          | error priorFault =>
            have same : priorFault = fault := by simpa [Source.Expression.evaluate, firstResult, secondResult] using failed
            subst fault
            obtain ⟨count, steps⟩ := expression_drains first bindings (expression second (.pair next)) values firstValue firstResult
            exact ReachesFault.prepend steps (expression_fault_bounded bound second (by simp_all; omega)
              bindings (.pair next) (.cons (value firstValue) values) priorFault secondResult)
      | first operand =>
        cases operandResult : operand.evaluate bindings with
        | ok operandValue => simp [Source.Expression.evaluate, Except.map, operandResult] at failed
        | error priorFault =>
          have same : priorFault = fault := by simpa [Source.Expression.evaluate, Except.map, operandResult] using failed
          subst fault
          exact expression_fault_bounded bound operand (by simp_all; omega) bindings (.first next) values priorFault operandResult
      | second operand =>
        cases operandResult : operand.evaluate bindings with
        | ok operandValue => simp [Source.Expression.evaluate, Except.map, operandResult] at failed
        | error priorFault =>
          have same : priorFault = fault := by simpa [Source.Expression.evaluate, Except.map, operandResult] using failed
          subst fault
          exact expression_fault_bounded bound operand (by simp_all; omega) bindings (.second next) values priorFault operandResult
      | left operand =>
        cases operandResult : operand.evaluate bindings with
        | ok operandValue => simp [Source.Expression.evaluate, Except.map, operandResult] at failed
        | error priorFault =>
          have same : priorFault = fault := by simpa [Source.Expression.evaluate, Except.map, operandResult] using failed
          subst fault
          exact expression_fault_bounded bound operand (by simp_all; omega) bindings (.left next) values priorFault operandResult
      | right operand =>
        cases operandResult : operand.evaluate bindings with
        | ok operandValue => simp [Source.Expression.evaluate, Except.map, operandResult] at failed
        | error priorFault =>
          have same : priorFault = fault := by simpa [Source.Expression.evaluate, Except.map, operandResult] using failed
          subst fault
          exact expression_fault_bounded bound operand (by simp_all; omega) bindings (.right next) values priorFault operandResult
      | primitive operation inputs =>
        cases inputsResult : inputs.evaluate bindings with
        | error priorFault =>
          have same : priorFault = fault := by simpa [Source.Expression.evaluate, inputsResult] using failed
          subst fault
          exact arguments_fault_bounded bound inputs (by simp_all; omega) bindings (.primitive operation next) values priorFault inputsResult
        | ok inputsValue =>
          cases primitiveResult : algebra.evaluate operation inputsValue.leaves with
          | ok primitiveValue => simp [Source.Expression.evaluate, Except.map, inputsResult, primitiveResult] at failed
          | error priorFault =>
            have same : priorFault = fault := by simpa [Source.Expression.evaluate, Except.map, inputsResult, primitiveResult] using failed
            subst fault
            obtain ⟨count, steps⟩ := arguments_drains inputs bindings (.primitive operation next) values inputsValue inputsResult
            apply ReachesFault.prepend steps
            refine ⟨1, _, .single (.primitiveFault ?_), .fault⟩
            simpa only [environment, Environment.leaves_map] using primitiveResult
  termination_by bound

  private theorem arguments_fault_bounded (bound : Nat)
      (source : Source.Arguments signature algebra definitions context types) (sized : sizeOf source < bound)
      (bindings : Source.RuntimeEnvironment signature algebra definitions context)
      (next : Code signature algebra definitions context (types.reverse ++ stack) result)
      (values : Target.RuntimeEnvironment signature algebra definitions stack) (fault : algebra.Fault)
      (failed : source.evaluate bindings = .error fault) :
      ReachesFault (environment bindings) ⟨_, arguments source next, values⟩ fault := by
    cases bound with
    | zero => omega
    | succ bound =>
      cases source with
      | nil => simp [Source.Arguments.evaluate] at failed
      | cons first rest =>
        let nextRest : Code signature algebra definitions context (_ ++ _ :: stack) result := by
          simpa only [List.reverse_cons, List.append_assoc, List.singleton_append] using next
        cases firstResult : first.evaluate bindings with
        | error priorFault =>
          have same : priorFault = fault := by simpa [Source.Arguments.evaluate, firstResult] using failed
          subst fault
          exact expression_fault_bounded bound first (by simp_all; omega) bindings (arguments rest nextRest) values priorFault firstResult
        | ok firstValue =>
          cases restResult : rest.evaluate bindings with
          | ok restValue => simp [Source.Arguments.evaluate, firstResult, restResult] at failed
          | error priorFault =>
            have same : priorFault = fault := by simpa [Source.Arguments.evaluate, firstResult, restResult] using failed
            subst fault
            obtain ⟨count, steps⟩ := expression_drains first bindings (arguments rest nextRest) values firstValue firstResult
            exact ReachesFault.prepend steps (arguments_fault_bounded bound rest (by simp_all; omega)
              bindings nextRest (.cons (value firstValue) values) priorFault restResult)
  termination_by bound
end

theorem expression_fault_drains (source : Source.Expression signature algebra definitions context type)
    (bindings : Source.RuntimeEnvironment signature algebra definitions context)
    (next : Code signature algebra definitions context (type :: stack) result)
    (values : Target.RuntimeEnvironment signature algebra definitions stack) (fault : algebra.Fault)
    (failed : source.evaluate bindings = .error fault) :
    ReachesFault (environment bindings) ⟨_, expression source next, values⟩ fault :=
  expression_fault_bounded (sizeOf source + 1) source (Nat.lt_succ_self _) bindings next values fault failed

theorem arguments_fault_drains (source : Source.Arguments signature algebra definitions context types)
    (bindings : Source.RuntimeEnvironment signature algebra definitions context)
    (next : Code signature algebra definitions context (types.reverse ++ stack) result)
    (values : Target.RuntimeEnvironment signature algebra definitions stack) (fault : algebra.Fault)
    (failed : source.evaluate bindings = .error fault) :
    ReachesFault (environment bindings) ⟨_, arguments source next, values⟩ fault :=
  arguments_fault_bounded (sizeOf source + 1) source (Nat.lt_succ_self _) bindings next values fault failed

/-- Preservation and reflection for expression results under the target's own
instruction relation, including exclusion of successful results after a fault. -/
theorem expression_result_iff (source : Source.Expression signature algebra definitions context type)
    (bindings : Source.RuntimeEnvironment signature algebra definitions context)
    (returned : Target.RuntimeValue signature algebra definitions type) :
    Target.ReturnsOperand (environment bindings) (expression source .ret) returned ↔
      ∃ value, source.evaluate bindings = .ok value ∧ Defunctionalization.value value = returned := by
  constructor
  · rintro ⟨targetCount, targetSteps⟩
    cases evaluated : source.evaluate bindings with
    | ok sourceValue =>
      obtain ⟨sourceCount, sourceSteps⟩ := expression_drains source bindings .ret .nil sourceValue evaluated
      have same := sourceSteps.normal_forms_unique rfl targetSteps rfl
      refine ⟨sourceValue, rfl, ?_⟩
      simpa only [Target.Operands.mk.injEq, heq_eq_eq, Environment.cons.injEq, and_true, true_and] using same
    | error fault =>
      obtain ⟨count, final, faultSteps, faulted⟩ := expression_fault_drains source bindings .ret .nil fault evaluated
      cases faulted with
      | fault =>
        have same := faultSteps.normal_forms_unique rfl targetSteps rfl
        have impossible := congrArg Target.Operands.isReturn same
        contradiction
  · rintro ⟨sourceValue, evaluated, rfl⟩
    exact expression_drains source bindings .ret .nil sourceValue evaluated

theorem expression_fault_iff (source : Source.Expression signature algebra definitions context type)
    (bindings : Source.RuntimeEnvironment signature algebra definitions context) (fault : algebra.Fault) :
    Target.ReachesFault (environment bindings) ⟨_, expression source .ret, .nil⟩ fault ↔
      source.evaluate bindings = .error fault := by
  constructor
  · rintro ⟨count, final, steps, faulted⟩
    cases faulted with
    | fault =>
      cases evaluated : source.evaluate bindings with
      | ok sourceValue =>
        obtain ⟨returnedCount, returnedSteps⟩ := expression_drains source bindings .ret .nil sourceValue evaluated
        have same := returnedSteps.normal_forms_unique rfl steps rfl
        have impossible := congrArg Target.Operands.isReturn same
        contradiction
      | error sourceFault =>
        obtain ⟨sourceCount, sourceFinal, sourceSteps, sourceFaulted⟩ := expression_fault_drains source bindings .ret .nil sourceFault evaluated
        cases sourceFaulted with
        | fault =>
          have same := sourceSteps.normal_forms_unique rfl steps rfl
          have faults := congrArg Target.Operands.faultValue same
          have equal : sourceFault = fault := Option.some.inj faults
          exact congrArg Except.error equal
  · exact expression_fault_drains source bindings .ret .nil fault

end BoundaryV2.Generalized.Defunctionalization
