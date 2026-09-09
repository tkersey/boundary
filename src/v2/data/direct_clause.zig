// Copyright (c) 2026 Boundary contributors. MIT license.
//! Admission of capture-free clauses. These instructions have no authored
//! failure or control effect; allocation failure still aborts the invocation.
const p = @import("program.zig");

pub fn instruction(operation: p.Instruction) bool {
    if (operation.failures.len != 0) return false;
    return switch (operation.opcode) {
        .constant,
        .move,
        .equal,
        .less,
        .boolean_not,
        .product,
        .field,
        .variant,
        .variant_tag,
        .sequence,
        .sequence_length,
        .sequence_get,
        .sequence_append,
        .sequence_concat,
        .sequence_pop,
        .integer_bit_not,
        .integer_bit_and,
        .integer_bit_or,
        .integer_bit_xor,
        .integer_convert,
        .enum_tag,
        .blob_length,
        .blob_compare,
        .blob_byte,
        .text_integer,
        .blob_from_byte,
        .sequence_take,
        .sequence_pop_last,
        .select,
        .cell_get,
        .cell_set,
        => true,
        else => false,
    };
}

pub fn block(code: p.Block) bool {
    if (code.terminator != .return_value) return false;
    for (code.instructions) |operation| if (!instruction(operation)) return false;
    return true;
}
