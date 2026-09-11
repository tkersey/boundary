import BoundaryV2.BorrowGraph

namespace BoundaryV2.Profile.Target.Admission.Examples

private def program : Program := {
  roots := ⟨1, 0, 0, 0⟩
  schemas := [.unit, .boolean, .u8, .u16, .u32, .u64, .i8, .text, .bytes,
    .seq 5, .vector 5 3, .sum [0, 5], .u64, .vector 5 (2^32 - 1), .vector 5 (2^32)]
  constants := [⟨0, []⟩, ⟨2, [0]⟩]
  effects := []
  functions := [⟨0, [0], 0, [], []⟩]
  blocks := [⟨0, [0], [], .returnValue 0⟩] }

private def arithmetic (opcode : Opcode) : Instruction :=
  ⟨opcode, 5, [0, 1], 0, [⟨.arithmeticOverflow, 0⟩]⟩

theorem addition_admitted : instructionValid program 0 [5, 5] (arithmetic .integerAdd) = true := by decide +kernel

theorem same_shape_different_identity_rejected :
    instructionValid program 0 [5, 12] (arithmetic .integerAdd) = false := by decide +kernel

theorem missing_authored_fault_rejected :
    instructionValid program 0 [5, 5] { arithmetic .integerAdd with failures := [] } = false := by decide +kernel

theorem wrong_failure_constant_schema_rejected :
    instructionValid program 0 [5, 5]
      { arithmetic .integerAdd with failures := [⟨.arithmeticOverflow, 1⟩] } = false := by decide +kernel

theorem division_fault_order_admitted :
    instructionValid program 0 [5, 5] { arithmetic .integerDiv with
      failures := [⟨.arithmeticOverflow, 0⟩, ⟨.divisionByZero, 0⟩] } = true := by decide +kernel

theorem swapped_division_faults_rejected :
    instructionValid program 0 [5, 5] { arithmetic .integerDiv with
      failures := [⟨.divisionByZero, 0⟩, ⟨.arithmeticOverflow, 0⟩] } = false := by decide +kernel

theorem unsigned_widening_needs_no_fault :
    instructionValid program 0 [2] ⟨.integerConvert, 3, [0], 0, []⟩ = true := by decide +kernel

theorem same_width_unsigned_to_signed_needs_fault :
    instructionValid program 0 [2] ⟨.integerConvert, 6, [0], 0, []⟩ = false := by decide +kernel

theorem u32_sequence_length_boundary_admitted :
    instructionValid program 0 [13] ⟨.sequenceLength, 4, [0], 0, []⟩ = true := by decide +kernel

theorem u32_sequence_length_overflow_rejected :
    instructionValid program 0 [14] ⟨.sequenceLength, 4, [0], 0, []⟩ = false := by decide +kernel

theorem unbounded_sequence_append_no_capacity_fault :
    instructionValid program 0 [9, 5] ⟨.sequenceAppend, 9, [0, 1], 0, []⟩ = true := by decide +kernel

theorem bounded_sequence_append_requires_capacity_fault :
    instructionValid program 0 [10, 5] ⟨.sequenceAppend, 10, [0, 1], 0, []⟩ = false := by decide +kernel

theorem nonzero_move_immediate_rejected :
    instructionValid program 0 [5] ⟨.move, 5, [0], 1, []⟩ = false := by decide +kernel

private def ownedProgram : Program := { program with
  schemas := [.unit, .internal (.abstractResource 0)]
  scopes := { resources := [⟨0, [0], [0]⟩] }
  blocks := [⟨0, [1, 1], [], .fail 0⟩] }

theorem noncopy_operand_cannot_be_used_twice :
    consumeSlots ownedProgram [1] [] [0, 0] = none := by decide +kernel

theorem copy_operand_may_be_used_twice : consumeSlots program [5] [] [0, 0] = some [] := by decide +kernel

theorem returned_owned_value_cannot_be_duplicated :
    edgeUses ownedProgram [] [] ⟨0, [.returned, .returned]⟩ (some 1) = none := by decide +kernel

theorem owned_resource_cannot_be_silently_dropped : usesFinished ownedProgram [1] [] = false := by decide +kernel

theorem lexical_region_is_distinct_from_evidence :
    Borrow.mappedConstraintValid ⟨some .region, []⟩
      ⟨none, [.ambient 0 .evidence]⟩ = true := by decide +kernel

theorem fresh_region_cannot_outlive_ambient_region :
    Borrow.mappedConstraintValid ⟨some .region, []⟩
      ⟨none, [.ambient 0 .region]⟩ = false := by decide +kernel

theorem fresh_evidence_cannot_escape_unclassified_owner :
    Borrow.mappedConstraintValid ⟨some .evidence, []⟩
      ⟨none, [.slot 0 0 []]⟩ = false := by decide +kernel

end BoundaryV2.Profile.Target.Admission.Examples
