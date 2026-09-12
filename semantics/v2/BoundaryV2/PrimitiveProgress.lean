import BoundaryV2.PrimitiveEvaluatorTypes

namespace BoundaryV2.Profile.Primitives
namespace Progress

variable {space : Space}

theorem scalar_integer_valid (shape : Schema space) (kind : Scalars.IntegerType) (number : Int)
    (found : Scalars.integerType shape = some kind) (valid : Value.scalarValid shape number = true) :
    kind.Contains number := by
  cases shape <;> simp only [Scalars.integerType] at found <;> try contradiction
  all_goals cases found
  all_goals simpa only [Value.scalarValid, Scalars.integerType, decide_eq_true_eq] using valid

theorem integer_value (schemas : List (Schema space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (value : Value space) (shape : Schema space) (kind : Scalars.IntegerType)
    (typed : Value.Typed schemas references value)
    (found : schemas[value.schema.value]? = some shape) (kindAt : Scalars.integerType shape = some kind) :
    ∃ number : Scalars.Integer kind, value = .scalar value.schema number.value := by
  cases typed with
  | scalar declared valid =>
    simp only [Value.schema] at found
    have same := Option.some.inj (declared.symm.trans found)
    subst shape
    exact ⟨⟨_, scalar_integer_valid _ _ _ kindAt valid⟩, rfl⟩
  | blob declared valid =>
    rename_i originalShape bytes schema
    simp only [Value.schema] at found
    have same := Option.some.inj (declared.symm.trans found)
    subst shape
    cases originalShape <;> simp [Scalars.integerType, Value.blobValid, Value.blobMaximum] at kindAt valid
  | product declared _ _ =>
    simp only [Value.schema] at found
    rw [declared] at found
    cases found
    contradiction
  | variant declared _ _ _ =>
    simp only [Value.schema] at found
    rw [declared] at found
    cases found
    contradiction
  | sequence declared valid elements children =>
    rename_i originalShape fields schema
    simp only [Value.schema] at found
    have same := Option.some.inj (declared.symm.trans found)
    subst shape
    cases originalShape <;> simp [Scalars.integerType, Value.sequenceLengthValid] at kindAt valid
  | reference declared _ =>
    simp only [Value.schema] at found
    rw [declared] at found
    cases found
    contradiction

theorem integer_succeeds (schemas : List (Schema space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (value : Value space) (shape : Schema space) (kind : Scalars.IntegerType)
    (typed : Value.Typed schemas references value)
    (found : schemas[value.schema.value]? = some shape) (kindAt : Scalars.integerType shape = some kind) :
    ∃ number, integer kind value = .ok number := by
  obtain ⟨number, equation⟩ := integer_value schemas references value shape kind typed found kindAt
  rw [equation]
  exact ⟨number, by simp [integer, Primitives.number, number.valid, pure, Except.pure, bind, Except.bind]⟩

theorem arithmetic_succeeds (schemas : List (Schema space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (operation : Scalars.Arithmetic) (resultType : SchemaId space) (left right : Value space)
    (leftTyped : Value.Typed schemas references left) (rightTyped : Value.Typed schemas references right)
    (same : left.schema = right.schema) (resultSame : left.schema = resultType)
    (shape : Schema space) (kind : Scalars.IntegerType)
    (found : schemas[left.schema.value]? = some shape) (kindAt : Scalars.integerType shape = some kind) :
    ∃ result, arithmetic schemas operation resultType [left, right] = .ok result := by
  obtain ⟨first, firstOk⟩ := integer_succeeds schemas references left shape kind leftTyped found kindAt
  obtain ⟨second, secondOk⟩ := integer_succeeds schemas references right shape kind rightTyped (same ▸ found) kindAt
  refine ⟨integerResult resultType (Scalars.arithmetic operation first second), ?_⟩
  have guard : (left.schema == right.schema && left.schema == resultType) = true :=
    Bool.and_eq_true_iff.mpr ⟨beq_iff_eq.mpr same, beq_iff_eq.mpr resultSame⟩
  have integerTypeOk : integerType schemas left = .ok kind := by
    simp [integerType, lookup, found, kindAt, bind, Except.bind, pure, Except.pure]
  simp only [arithmetic, guard, integerTypeOk, firstOk, secondOk,
    require, ↓reduceIte, bind, Except.bind, pure, Except.pure]

/-- Type admission fixes the operand arity and schemas; value typing supplies
representable integers. Arithmetic faults remain successful semantic outcomes. -/
def arithmeticOpcode : Scalars.Arithmetic → Opcode
  | .add => .integerAdd | .sub => .integerSub | .mul => .integerMul
  | .div => .integerDiv | .rem => .integerRem

theorem admitted_arithmetic_inputs (program : PrimitiveAdmission.Context space) (owner : FunctionId space)
    (operation : Scalars.Arithmetic) (resultType : SchemaId space)
    (immediate : Nat) (failures : List (InstructionFailure space)) (operands : List (Value space))
    (accepted : PrimitiveAdmission.operationType program owner ⟨arithmeticOpcode operation, resultType, immediate, failures⟩
      (operands.map Value.schema) = true) :
    ∃ left right source kind, operands = [left, right] ∧ left.schema = right.schema ∧
      left.schema = resultType ∧ program.schemas[left.schema.value]? = some source ∧
      Scalars.integerType source = some kind := by
  cases resultAt : program.schemas[resultType.value]? with
  | none => cases operation <;> simp [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, arithmeticOpcode, resultAt] at accepted
  | some resultShape =>
    cases operands with
    | nil => cases operation <;> simp [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, arithmeticOpcode, resultAt] at accepted
    | cons left rest =>
      cases rest with
      | nil => cases operation <;> simp [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, arithmeticOpcode, resultAt] at accepted
      | cons right rest =>
        cases rest with
        | cons => cases operation <;> simp [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, arithmeticOpcode, resultAt] at accepted
        | nil =>
          cases sourceAt : program.schemas[left.schema.value]? with
          | none => cases operation <;> simp [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, arithmeticOpcode, resultAt, sourceAt] at accepted
          | some source =>
            have checks : immediate = 0 ∧ left.schema = right.schema ∧
                (Scalars.integerType source).isSome = true ∧ resultType = left.schema := by
              cases operation <;> simpa [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, arithmeticOpcode,
                resultAt, sourceAt, PrimitiveAdmission.integer, Bool.and_eq_true, and_assoc] using accepted
            obtain ⟨kind, kindAt⟩ := Option.isSome_iff_exists.mp checks.2.2.1
            exact ⟨left, right, source, kind, rfl, checks.2.1, checks.2.2.2.symm, sourceAt, kindAt⟩

theorem admitted_arithmetic_succeeds (program : PrimitiveAdmission.Context space) (owner : FunctionId space)
    (constants : List (Value space)) (operation : Scalars.Arithmetic) (resultType : SchemaId space)
    (immediate : Nat) (failures : List (InstructionFailure space)) (operands : List (Value space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (typed : ∀ value ∈ operands, Value.Typed program.schemas references value)
    (accepted : PrimitiveAdmission.operationType program owner ⟨arithmeticOpcode operation, resultType, immediate, failures⟩
      (operands.map Value.schema) = true) :
    ∃ result, evaluate program.schemas constants (arithmeticOpcode operation) resultType immediate operands = .ok result := by
  obtain ⟨left, right, source, kind, rfl, same, resultSame, sourceAt, kindAt⟩ :=
    admitted_arithmetic_inputs program owner operation resultType immediate failures operands accepted
  obtain ⟨result, evaluated⟩ := arithmetic_succeeds program.schemas references operation resultType left right
    (typed left (by simp)) (typed right (by simp)) same resultSame source kind sourceAt kindAt
  refine ⟨result, ?_⟩
  cases operation <;> simpa only [evaluate, arithmeticOpcode] using evaluated

private theorem except_bind_ok (value : Except Invalid α) (next : α → Except Invalid β) (result : β) :
    value.bind next = .ok result ↔ ∃ input, value = .ok input ∧ next input = .ok result := by
  cases value <;> simp [Except.bind]

theorem arithmetic_fault (operation : Scalars.Arithmetic) (left right : Scalars.Integer kind) (fault : Fault)
    (failed : Scalars.arithmetic operation left right = .error fault) :
    fault = .arithmeticOverflow ∨ ((operation = .div ∨ operation = .rem) ∧ fault = .divisionByZero) := by
  cases operation <;> simp only [Scalars.arithmetic, Scalars.checkInteger] at failed
  all_goals repeat' split at failed
  all_goals cases failed
  all_goals simp

theorem arithmetic_outcome (program : PrimitiveAdmission.Context space) (operation : Scalars.Arithmetic)
    (schema : SchemaId space) (operands : List (Value space)) (result : Result space)
    (accepted : arithmetic program.schemas operation schema operands = .ok result) :
    (∃ number, result = .value (.scalar schema number)) ∨
      ∃ fault, result = .fault fault ∧ fault ∈ PrimitiveAdmission.requiredFaults program
        (arithmeticOpcode operation) schema (operands.map Value.schema) := by
  unfold arithmetic at accepted
  split at accepted <;> try contradiction
  simp only [bind, except_bind_ok, pure, Except.pure, Except.ok.injEq] at accepted
  obtain ⟨_, _, kind, _, first, _, second, _, same⟩ := accepted
  cases calculated : Scalars.arithmetic operation first second with
  | ok value =>
    left
    simp only [calculated, integerResult] at same
    exact ⟨value.value, same.symm⟩
  | error fault =>
    right
    simp only [calculated, integerResult] at same
    refine ⟨fault, same.symm, ?_⟩
    have allowed := arithmetic_fault _ _ _ _ calculated
    cases operation <;> simpa [arithmeticOpcode, PrimitiveAdmission.requiredFaults] using allowed

theorem evaluated_arithmetic_outcome (program : PrimitiveAdmission.Context space) (constants : List (Value space))
    (operation : Scalars.Arithmetic) (schema : SchemaId space) (immediate : Nat)
    (operands : List (Value space)) (result : Result space)
    (accepted : evaluate program.schemas constants (arithmeticOpcode operation) schema immediate operands = .ok result) :
    (∃ number, result = .value (.scalar schema number)) ∨
      ∃ fault, result = .fault fault ∧ fault ∈ PrimitiveAdmission.requiredFaults program
        (arithmeticOpcode operation) schema (operands.map Value.schema) := by
  apply arithmetic_outcome program operation schema operands result
  cases operation <;> simpa only [evaluate, arithmeticOpcode] using accepted

end Progress
end BoundaryV2.Profile.Primitives
