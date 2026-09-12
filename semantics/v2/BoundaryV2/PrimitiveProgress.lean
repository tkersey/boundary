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

def bitwiseOpcode : Scalars.Bitwise → Opcode
  | .and => .integerBitAnd | .or => .integerBitOr | .xor => .integerBitXor | .not => .integerBitNot

theorem admitted_bitwise_inputs (program : PrimitiveAdmission.Context space) (owner : FunctionId space)
    (operation : Scalars.Bitwise) (resultType : SchemaId space)
    (immediate : Nat) (failures : List (InstructionFailure space)) (operands : List (Value space))
    (binary : operation ≠ .not)
    (accepted : PrimitiveAdmission.operationType program owner ⟨bitwiseOpcode operation, resultType, immediate, failures⟩
      (operands.map Value.schema) = true) :
    ∃ left right source kind, operands = [left, right] ∧ left.schema = right.schema ∧
      left.schema = resultType ∧ program.schemas[left.schema.value]? = some source ∧
      Scalars.integerType source = some kind := by
  apply admitted_arithmetic_inputs program owner .add resultType immediate failures operands
  cases operation <;> try contradiction
  all_goals exact accepted

theorem admitted_bitwise_succeeds (program : PrimitiveAdmission.Context space) (owner : FunctionId space)
    (constants : List (Value space)) (operation : Scalars.Bitwise) (resultType : SchemaId space)
    (immediate : Nat) (failures : List (InstructionFailure space)) (operands : List (Value space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (typed : ∀ value ∈ operands, Value.Typed program.schemas references value)
    (binary : operation ≠ .not)
    (accepted : PrimitiveAdmission.operationType program owner ⟨bitwiseOpcode operation, resultType, immediate, failures⟩
      (operands.map Value.schema) = true) :
    ∃ number, evaluate program.schemas constants (bitwiseOpcode operation) resultType immediate operands =
      .ok (.value (.scalar resultType number)) := by
  obtain ⟨left, right, source, kind, rfl, same, resultSame, sourceAt, kindAt⟩ :=
    admitted_bitwise_inputs program owner operation resultType immediate failures operands binary accepted
  obtain ⟨first, firstOk⟩ := integer_succeeds program.schemas references left source kind (typed left (by simp)) sourceAt kindAt
  obtain ⟨second, secondOk⟩ := integer_succeeds program.schemas references right source kind (typed right (by simp)) (same ▸ sourceAt) kindAt
  have guard : (left.schema == right.schema && left.schema == resultType) = true :=
    Bool.and_eq_true_iff.mpr ⟨beq_iff_eq.mpr same, beq_iff_eq.mpr resultSame⟩
  have typeOk : integerType program.schemas left = .ok kind := by
    simp [integerType, lookup, sourceAt, kindAt, bind, Except.bind, pure, Except.pure]
  refine ⟨(Scalars.bitwise operation first second).value, ?_⟩
  cases operation <;> try contradiction
  all_goals simp only [evaluate, bitwiseOpcode, bitwise, guard, typeOk, firstOk, secondOk,
    require, ↓reduceIte, bind, Except.bind, pure, Except.pure]

theorem admitted_complement_input (program : PrimitiveAdmission.Context space) (owner : FunctionId space)
    (resultType : SchemaId space) (immediate : Nat) (failures : List (InstructionFailure space)) (operands : List (Value space))
    (accepted : PrimitiveAdmission.operationType program owner ⟨.integerBitNot, resultType, immediate, failures⟩
      (operands.map Value.schema) = true) :
    ∃ input source kind, operands = [input] ∧ input.schema = resultType ∧
      program.schemas[input.schema.value]? = some source ∧ Scalars.integerType source = some kind := by
  cases resultAt : program.schemas[resultType.value]? with
  | none => simp [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, resultAt] at accepted
  | some resultShape =>
    cases operands with
    | nil => simp [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, resultAt] at accepted
    | cons input rest =>
      cases rest with
      | cons => simp [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, resultAt] at accepted
      | nil =>
        cases sourceAt : program.schemas[input.schema.value]? with
        | none => simp [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, resultAt, sourceAt] at accepted
        | some source =>
          have checks : immediate = 0 ∧ (Scalars.integerType source).isSome = true ∧
              (Scalars.integerType resultShape).isSome = true ∧ input.schema = resultType := by
            simpa [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, resultAt, sourceAt,
              PrimitiveAdmission.integer, Bool.and_eq_true, and_assoc] using accepted
          obtain ⟨kind, kindAt⟩ := Option.isSome_iff_exists.mp checks.2.1
          exact ⟨input, source, kind, rfl, checks.2.2.2, sourceAt, kindAt⟩

theorem admitted_complement_succeeds (program : PrimitiveAdmission.Context space) (owner : FunctionId space)
    (constants : List (Value space)) (resultType : SchemaId space)
    (immediate : Nat) (failures : List (InstructionFailure space)) (operands : List (Value space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (typed : ∀ value ∈ operands, Value.Typed program.schemas references value)
    (accepted : PrimitiveAdmission.operationType program owner ⟨.integerBitNot, resultType, immediate, failures⟩
      (operands.map Value.schema) = true) :
    ∃ number, evaluate program.schemas constants .integerBitNot resultType immediate operands =
      .ok (.value (.scalar resultType number)) := by
  obtain ⟨input, source, kind, rfl, same, sourceAt, kindAt⟩ :=
    admitted_complement_input program owner resultType immediate failures operands accepted
  obtain ⟨number, numberOk⟩ := integer_succeeds program.schemas references input source kind (typed input (by simp)) sourceAt kindAt
  have typeOk : integerType program.schemas input = .ok kind := by
    simp [integerType, lookup, sourceAt, kindAt, bind, Except.bind, pure, Except.pure]
  exact ⟨(Scalars.complement number).value, by
    simp only [evaluate, beq_iff_eq.mpr same, typeOk, numberOk, require, ↓reduceIte,
      bind, Except.bind, pure, Except.pure]⟩

theorem boolean_value (schemas : List (Schema space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (value : Value space) (typed : Value.Typed schemas references value)
    (found : schemas[value.schema.value]? = some .boolean) :
    ∃ number, value = .scalar value.schema number ∧ (number = 0 ∨ number = 1) := by
  cases typed with
  | scalar declared valid =>
    simp only [Value.schema] at found
    rw [declared] at found
    cases found
    exact ⟨_, rfl, by simpa [Value.scalarValid] using valid⟩
  | blob declared valid =>
    simp only [Value.schema] at found
    rw [declared] at found
    cases found
    simp [Value.blobValid, Value.blobMaximum] at valid
  | product declared _ _ =>
    simp only [Value.schema] at found
    rw [declared] at found
    cases found
  | variant declared _ _ _ =>
    simp only [Value.schema] at found
    rw [declared] at found
    cases found
  | sequence declared valid _ _ =>
    simp only [Value.schema] at found
    rw [declared] at found
    cases found
    simp [Value.sequenceLengthValid] at valid
  | reference declared _ =>
    simp only [Value.schema] at found
    rw [declared] at found
    cases found

theorem comparable_value (schemas : List (Schema space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (value : Value space) (source : Schema space) (less : Bool)
    (typed : Value.Typed schemas references value)
    (found : schemas[value.schema.value]? = some source)
    (allowed : ((Scalars.integerType source).isSome || (!less && source == .boolean)) = true) :
    ∃ number, value = .scalar value.schema number ∧ Value.scalarValid source number = true := by
  simp only [Bool.or_eq_true, Bool.and_eq_true, beq_iff_eq] at allowed
  rcases allowed with integer | ⟨_, rfl⟩
  · obtain ⟨kind, kindAt⟩ := Option.isSome_iff_exists.mp integer
    obtain ⟨number, same⟩ := integer_value schemas references value source kind typed found kindAt
    exact ⟨number.value, same, integer_schema_scalar_valid source kind number.value kindAt number.valid⟩
  · obtain ⟨number, same, range⟩ := boolean_value schemas references value typed found
    exact ⟨number, same, by simpa [Value.scalarValid] using range⟩

def comparisonOpcode (less : Bool) : Opcode := if less then .less else .equal

theorem admitted_comparison_inputs (program : PrimitiveAdmission.Context space) (owner : FunctionId space)
    (less : Bool) (resultType : SchemaId space)
    (immediate : Nat) (failures : List (InstructionFailure space)) (operands : List (Value space))
    (accepted : PrimitiveAdmission.operationType program owner ⟨comparisonOpcode less, resultType, immediate, failures⟩
      (operands.map Value.schema) = true) :
    ∃ left right source, operands = [left, right] ∧ left.schema = right.schema ∧
      program.schemas[resultType.value]? = some .boolean ∧ program.schemas[left.schema.value]? = some source ∧
      ((Scalars.integerType source).isSome || (!less && source == .boolean)) = true := by
  cases resultAt : program.schemas[resultType.value]? with
  | none => cases less <;> simp [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, comparisonOpcode, resultAt] at accepted
  | some resultShape =>
    cases operands with
    | nil => cases less <;> simp [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, comparisonOpcode, resultAt] at accepted
    | cons left rest =>
      cases rest with
      | nil => cases less <;> simp [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, comparisonOpcode, resultAt] at accepted
      | cons right rest =>
        cases rest with
        | cons => cases less <;> simp [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, comparisonOpcode, resultAt] at accepted
        | nil =>
          cases sourceAt : program.schemas[left.schema.value]? with
          | none => cases less <;> simp [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, comparisonOpcode, resultAt, sourceAt] at accepted
          | some source =>
            have checks : immediate = 0 ∧ left.schema = right.schema ∧
                ((Scalars.integerType source).isSome || (!less && source == .boolean)) = true ∧ resultShape = .boolean := by
              cases less <;> simpa [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, comparisonOpcode,
                resultAt, sourceAt, PrimitiveAdmission.integer, Bool.and_eq_true, and_assoc] using accepted
            exact ⟨left, right, source, rfl, checks.2.1, (by simp [checks.2.2.2]), sourceAt, checks.2.2.1⟩

theorem admitted_comparison_succeeds (program : PrimitiveAdmission.Context space) (owner : FunctionId space)
    (constants : List (Value space)) (less : Bool) (resultType : SchemaId space)
    (immediate : Nat) (failures : List (InstructionFailure space)) (operands : List (Value space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (typed : ∀ value ∈ operands, Value.Typed program.schemas references value)
    (accepted : PrimitiveAdmission.operationType program owner ⟨comparisonOpcode less, resultType, immediate, failures⟩
      (operands.map Value.schema) = true) :
    ∃ number, evaluate program.schemas constants (comparisonOpcode less) resultType immediate operands =
      .ok (.value (.scalar resultType number)) := by
  obtain ⟨left, right, source, rfl, same, resultAt, sourceAt, allowed⟩ :=
    admitted_comparison_inputs program owner less resultType immediate failures operands accepted
  obtain ⟨first, firstShape, firstValid⟩ := comparable_value program.schemas references left source less
    (typed left (by simp)) sourceAt allowed
  obtain ⟨second, secondShape, secondValid⟩ := comparable_value program.schemas references right source less
    (typed right (by simp)) (same ▸ sourceAt) allowed
  have firstOk : number left = .ok first := by rw [firstShape]; rfl
  have secondOk : number right = .ok second := by rw [secondShape]; rfl
  refine ⟨if (if less then first < second else first == second) then 1 else 0, ?_⟩
  cases less <;> simp only [evaluate, comparisonOpcode, Bool.false_eq_true, ↓reduceIte, compare,
    beq_iff_eq.mpr same, lookup, resultAt, sourceAt, firstOk, secondOk, firstValid, secondValid,
    allowed, require, bind, Except.bind, pure, Except.pure] <;> rfl

theorem admitted_boolean_input (program : PrimitiveAdmission.Context space) (owner : FunctionId space)
    (resultType : SchemaId space) (immediate : Nat) (failures : List (InstructionFailure space)) (operands : List (Value space))
    (accepted : PrimitiveAdmission.operationType program owner ⟨.booleanNot, resultType, immediate, failures⟩
      (operands.map Value.schema) = true) :
    ∃ input, operands = [input] ∧ input.schema = resultType ∧ program.schemas[input.schema.value]? = some .boolean := by
  cases resultAt : program.schemas[resultType.value]? with
  | none => simp [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, resultAt] at accepted
  | some resultShape =>
    have checks : immediate = 0 ∧ resultShape = .boolean ∧ operands.map Value.schema = [resultType] := by
      simpa [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, resultAt, Bool.and_eq_true, and_assoc] using accepted
    cases operands with
    | nil => simp at checks
    | cons input rest =>
      cases rest with
      | cons => simp at checks
      | nil =>
        have same : input.schema = resultType := by simpa only [List.map_cons, List.map_nil, List.cons.injEq, and_true] using checks.2.2
        exact ⟨input, rfl, same, by simpa only [same, checks.2.1] using resultAt⟩

theorem admitted_boolean_succeeds (program : PrimitiveAdmission.Context space) (owner : FunctionId space)
    (constants : List (Value space)) (resultType : SchemaId space)
    (immediate : Nat) (failures : List (InstructionFailure space)) (operands : List (Value space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (typed : ∀ value ∈ operands, Value.Typed program.schemas references value)
    (accepted : PrimitiveAdmission.operationType program owner ⟨.booleanNot, resultType, immediate, failures⟩
      (operands.map Value.schema) = true) :
    ∃ number, evaluate program.schemas constants .booleanNot resultType immediate operands =
      .ok (.value (.scalar resultType number)) := by
  obtain ⟨input, rfl, same, sourceAt⟩ := admitted_boolean_input program owner resultType immediate failures operands accepted
  obtain ⟨number, shape, valid⟩ := boolean_value program.schemas references input (typed input (by simp)) sourceAt
  have resultAt : program.schemas[resultType.value]? = some .boolean := same ▸ sourceAt
  have shape : input = .scalar resultType number := by simpa only [same] using shape
  refine ⟨1 - number, ?_⟩
  rw [shape]
  simp [evaluate, lookup, resultAt, valid, require, bind, Except.bind, pure, Except.pure]

theorem admitted_conversion_input (program : PrimitiveAdmission.Context space) (owner : FunctionId space)
    (resultType : SchemaId space) (immediate : Nat) (failures : List (InstructionFailure space)) (operands : List (Value space))
    (accepted : PrimitiveAdmission.operationType program owner ⟨.integerConvert, resultType, immediate, failures⟩
      (operands.map Value.schema) = true) :
    ∃ input source sourceKind target targetKind, operands = [input] ∧
      program.schemas[input.schema.value]? = some source ∧ Scalars.integerType source = some sourceKind ∧
      program.schemas[resultType.value]? = some target ∧ Scalars.integerType target = some targetKind := by
  cases targetAt : program.schemas[resultType.value]? with
  | none => simp [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, targetAt] at accepted
  | some target =>
    cases operands with
    | nil => simp [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, targetAt] at accepted
    | cons input rest =>
      cases rest with
      | cons => simp [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, targetAt] at accepted
      | nil =>
        cases sourceAt : program.schemas[input.schema.value]? with
        | none => simp [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, targetAt, sourceAt] at accepted
        | some source =>
          have checks : immediate = 0 ∧ (Scalars.integerType source).isSome = true ∧
              (Scalars.integerType target).isSome = true := by
            simpa [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, targetAt, sourceAt,
              PrimitiveAdmission.integer, Bool.and_eq_true, and_assoc] using accepted
          obtain ⟨sourceKind, sourceKindAt⟩ := Option.isSome_iff_exists.mp checks.2.1
          obtain ⟨targetKind, targetKindAt⟩ := Option.isSome_iff_exists.mp checks.2.2
          exact ⟨input, source, sourceKind, target, targetKind, rfl, sourceAt, sourceKindAt, rfl, targetKindAt⟩

/-- Narrowing can produce only the admitted overflow fault. A conversion whose
failure interface is empty is proved total using its source and target bounds. -/
theorem admitted_conversion_succeeds (program : PrimitiveAdmission.Context space) (owner : FunctionId space)
    (constants : List (Value space)) (resultType : SchemaId space)
    (immediate : Nat) (failures : List (InstructionFailure space)) (operands : List (Value space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (typed : ∀ value ∈ operands, Value.Typed program.schemas references value)
    (accepted : PrimitiveAdmission.operationType program owner ⟨.integerConvert, resultType, immediate, failures⟩
      (operands.map Value.schema) = true) :
    ∃ result, evaluate program.schemas constants .integerConvert resultType immediate operands = .ok result ∧
      ((∃ number, result = .value (.scalar resultType number)) ∨
        ∃ fault, result = .fault fault ∧ fault ∈ PrimitiveAdmission.requiredFaults program
          .integerConvert resultType (operands.map Value.schema)) := by
  obtain ⟨input, source, sourceKind, target, targetKind, rfl, sourceAt, sourceKindAt, targetAt, targetKindAt⟩ :=
    admitted_conversion_input program owner resultType immediate failures operands accepted
  obtain ⟨number, numberOk⟩ := integer_succeeds program.schemas references input source sourceKind
    (typed input (by simp)) sourceAt sourceKindAt
  have typeOk : integerType program.schemas input = .ok sourceKind := by
    simp [integerType, lookup, sourceAt, sourceKindAt, bind, Except.bind, pure, Except.pure]
  have evaluated : evaluate program.schemas constants .integerConvert resultType immediate [input] =
      .ok (integerResult resultType (Scalars.convert targetKind number)) := by
    simp [evaluate, convert, lookup, typeOk, numberOk, targetAt, targetKindAt, bind, Except.bind, pure, Except.pure]
  refine ⟨integerResult resultType (Scalars.convert targetKind number), evaluated, ?_⟩
  cases converted : Scalars.convert targetKind number with
  | ok result => exact Or.inl ⟨result.value, rfl⟩
  | error fault =>
    have same : fault = .arithmeticOverflow := by
      unfold Scalars.convert Scalars.checkInteger at converted
      split at converted <;> cases converted
      rfl
    have canFail : Scalars.conversionCanFail sourceKind targetKind = true := by
      cases possible : Scalars.conversionCanFail sourceKind targetKind with
      | true => rfl
      | false =>
        obtain ⟨result, total, _⟩ := Scalars.widening_conversion_total sourceKind targetKind possible number
        rw [converted] at total
        contradiction
    have allowed : PrimitiveAdmission.conversionCanFail program input.schema resultType = true := by
      simp [PrimitiveAdmission.conversionCanFail, PrimitiveAdmission.shape, sourceAt, sourceKindAt,
        targetAt, targetKindAt, canFail]
    exact Or.inr ⟨fault, rfl, by simp [PrimitiveAdmission.requiredFaults, allowed, same]⟩

theorem enumeration_value (schemas : List (Schema space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (value : Value space) (tags : List Nat) (typed : Value.Typed schemas references value)
    (found : schemas[value.schema.value]? = some (.enumeration tags)) :
    ∃ number, value = .scalar value.schema number ∧ Value.scalarValid (space := space) (.enumeration tags) number = true := by
  cases typed with
  | scalar declared valid =>
    simp only [Value.schema] at found
    rw [declared] at found
    cases found
    exact ⟨_, rfl, valid⟩
  | blob declared valid =>
    simp only [Value.schema] at found
    rw [declared] at found
    cases found
    simp [Value.blobValid, Value.blobMaximum] at valid
  | product declared _ _ =>
    simp only [Value.schema] at found
    rw [declared] at found
    cases found
  | variant declared _ _ _ =>
    simp only [Value.schema] at found
    rw [declared] at found
    cases found
  | sequence declared valid _ _ =>
    simp only [Value.schema] at found
    rw [declared] at found
    cases found
    simp [Value.sequenceLengthValid] at valid
  | reference declared _ =>
    simp only [Value.schema] at found
    rw [declared] at found
    cases found

theorem admitted_enumeration_input (program : PrimitiveAdmission.Context space) (owner : FunctionId space)
    (resultType : SchemaId space) (immediate : Nat) (failures : List (InstructionFailure space)) (operands : List (Value space))
    (accepted : PrimitiveAdmission.operationType program owner ⟨.enumTag, resultType, immediate, failures⟩
      (operands.map Value.schema) = true) :
    ∃ input tags, operands = [input] ∧ program.schemas[input.schema.value]? = some (.enumeration tags) ∧
      program.schemas[resultType.value]? = some .u32 := by
  cases resultAt : program.schemas[resultType.value]? with
  | none => simp [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, resultAt] at accepted
  | some resultShape =>
    cases operands with
    | nil => simp [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, resultAt] at accepted
    | cons input rest =>
      cases rest with
      | cons => simp [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, resultAt] at accepted
      | nil =>
        cases sourceAt : program.schemas[input.schema.value]? with
        | none => simp [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, resultAt, sourceAt] at accepted
        | some source =>
          cases source <;> simp [PrimitiveAdmission.operationType, PrimitiveAdmission.shape, resultAt, sourceAt] at accepted
          rename_i tags
          exact ⟨input, tags, rfl, sourceAt, by simp [accepted.2]⟩

theorem admitted_enumeration_succeeds (program : PrimitiveAdmission.Context space) (owner : FunctionId space)
    (constants : List (Value space)) (resultType : SchemaId space)
    (immediate : Nat) (failures : List (InstructionFailure space)) (operands : List (Value space))
    (references : SchemaId space → Internal space → NodeId → Option CustodyToken → Prop)
    (typed : ∀ value ∈ operands, Value.Typed program.schemas references value)
    (accepted : PrimitiveAdmission.operationType program owner ⟨.enumTag, resultType, immediate, failures⟩
      (operands.map Value.schema) = true) :
    ∃ number, evaluate program.schemas constants .enumTag resultType immediate operands =
      .ok (.value (.scalar resultType number)) := by
  obtain ⟨input, tags, rfl, sourceAt, resultAt⟩ := admitted_enumeration_input program owner resultType immediate failures operands accepted
  obtain ⟨number, shape, valid⟩ := enumeration_value program.schemas references input tags (typed input (by simp)) sourceAt
  refine ⟨number, ?_⟩
  rw [shape]
  simp only [Value.scalarValid] at valid
  simp only [evaluate, lookup, sourceAt, resultAt, valid, require, ↓reduceIte, bind, Except.bind, pure, Except.pure]
  rfl

end Progress
end BoundaryV2.Profile.Primitives
