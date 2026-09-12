import BoundaryV2.SourceOperandTypes
import BoundaryV2.SourceValueExecution

namespace BoundaryV2.Profile.Source.Machine
namespace FaultProgress

theorem constant_schemas (context : Context) (typed : context.typingValid = true) :
    context.constants.map Profile.Value.schema = context.source.constants.map Literal.schema := by
  simp only [Context.typingValid, Option.any_eq_true] at typed
  obtain ⟨results, _, admitted⟩ := typed
  have declarations := (Admission.typed_checks_all_declarations _ _ _ _ admitted).1
  simp only [Admission.declarationsValid, Bool.and_eq_true] at declarations
  obtain ⟨count, exactValues⟩ := Admission.constants_exact _ _ declarations.1.1.1.1.1.2
  apply List.ext_getElem?
  intro index
  by_cases bounded : index < context.constants.length
  · have literalBound : index < context.source.constants.length := count ▸ bounded
    have valueAt := List.getElem?_eq_getElem bounded
    have literalAt := List.getElem?_eq_getElem literalBound
    have same := (exactValues index _ _ literalAt valueAt).1
    simp [List.getElem?_map, valueAt, literalAt, same]
  · have valueAt := List.getElem?_eq_none (by omega : context.constants.length ≤ index)
    have literalAt := List.getElem?_eq_none (by omega : context.source.constants.length ≤ index)
    simp [List.getElem?_map, valueAt, literalAt]

/-- Proof-side implicit unit literals and runtime constants use the same
ordered schema inventory, including the disposal adapter's appended unit. -/
theorem execution_constant_schemas (context : Context) (typed : context.typingValid = true) :
    context.executionConstants.map Profile.Value.schema =
      (Admission.executionLiterals context.source).map Literal.schema := by
  have ordinary := constant_schemas context typed
  unfold Context.executionConstants Admission.executionLiterals Analysis.firstUnit
  cases found : context.source.schemas.findIdx? (· == .unit) with
  | none => exact ordinary
  | some index =>
    simp only [Option.map_some]
    have sameGuard : (context.source.constants.any fun literal => literal.schema.value == index && literal.bytes.isEmpty) =
        (context.source.constants.any fun literal => literal.schema == (⟨index⟩ : SchemaId .source) && literal.bytes.isEmpty) := by
      congr 1
      funext literal
      congr 1
      apply Bool.eq_iff_iff.mpr
      cases literal.schema
      simp
    rw [sameGuard]
    split <;> simpa [List.map_append, Profile.Value.schema, Literal.schema] using ordinary

theorem execution_constant_exists (context : Context) (typed : context.typingValid = true)
    (index : Nat) (literal : Literal .source)
    (found : (Admission.executionLiterals context.source)[index]? = some literal) :
    ∃ value, context.executionConstants[index]? = some value ∧ value.schema = literal.schema := by
  have same := congrArg (fun values => values[index]?) (execution_constant_schemas context typed)
  simp only [List.getElem?_map, found, Option.map_some] at same
  exact Option.map_eq_some_iff.mp same

/-- Every fault named by the admitted primitive has an actual source failure
constant. Producing its unwind step cannot fail on a missing schema or value. -/
theorem authored_failure_succeeds (machine : State) (context : Context) (schema : SchemaId .source) (opcode : Opcode)
    (immediate : Nat) (failures : List (InstructionFailure .source)) (types : OperandSchemas.Schemas)
    (fault : Fault) (typed : context.typingValid = true)
    (signature : OperandSchemas.Signature context.source (.primitive schema opcode immediate failures) types)
    (required : fault ∈ PrimitiveAdmission.requiredFaults (Admission.primitiveContext context.source context.captures) opcode schema types) :
    ∃ after, authoredFailure machine context failures fault = .ok after := by
  cases signature with
  | primitive member typesAt =>
    obtain ⟨index, valueAt⟩ := List.mem_iff_getElem?.mp member
    have admitted := checked_context_checks_value context ⟨index⟩ _ typed valueAt
    obtain ⟨expected, expectedAt, exactFaults, constants⟩ := Admission.primitive_faults_exact _ _ _ _ _ _ _ admitted
    have same : expected = types := Option.some.inj (expectedAt.symm.trans typesAt)
    subst expected
    rw [← exactFaults] at required
    cases found : failures.find? (fun entry => entry.kind == fault) with
    | none =>
      obtain ⟨entry, member, same⟩ := List.mem_map.mp required
      have absent := List.find?_eq_none.mp found entry member
      simp [same] at absent
    | some failure =>
      have member := List.mem_of_find?_eq_some found
      obtain ⟨literal, literalAt, literalType⟩ := constants failure member
      obtain ⟨value, valueAt, valueType⟩ := execution_constant_exists context typed failure.value.value literal literalAt
      refine ⟨{ state := { machine with control := .unwind ⟨.failure value, [], none⟩ } }, ?_⟩
      simp [authoredFailure, found, valueAt, valueType, literalType, fromOption, require, bind, Except.bind, pure, Except.pure]

end FaultProgress
end BoundaryV2.Profile.Source.Machine
