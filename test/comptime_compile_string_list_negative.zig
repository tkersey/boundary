const ability = @import("ability");
const ability_compile = @import("ability_compile");
const std = @import("std");

const Plan = ability_compile.lowering_api.ProgramPlan{
    .label = "fixture.string_list.unsupported",
    .ir_hash = 0x5157,
    .entry_index = 0,
    .functions = &.{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 1,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = 1,
    }},
    .requirements = &.{.{
        .label = "unsupported",
        .first_op = 0,
        .op_count = 1,
    }},
    .ops = &.{.{
        .requirement_index = 0,
        .op_name = "list",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .string_list,
    }},
    .outputs = &.{},
    .locals = &.{.{ .codec = .string_list }},
    .call_args = &.{},
    .blocks = &.{.{
        .first_instruction = 0,
        .instruction_count = 1,
        .terminator_index = 0,
    }},
    .terminators = &.{.{ .kind = .return_unit }},
    .instructions = &.{.{
        .kind = .call_op,
        .dst = 0,
        .operand = 0,
        .aux = std.math.maxInt(u16),
    }},
};

const CompiledStringList = ability.compile(
    Plan.label,
    Plan,
    .{ .stable_build_fingerprint_seed = "ability-comptime-string-list-negative" },
);

test "compile rejects string_list executable plans" {
    _ = CompiledStringList;
}
