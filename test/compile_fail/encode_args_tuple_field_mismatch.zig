// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const ability = @import("ability");
const std = @import("std");

fn i32EntryPlan() ability.ir.ProgramPlan {
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 1,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = 0,
    }};
    const locals = [_]ability.ir.plan.Local{.{ .codec = .i32 }};
    const blocks = [_]ability.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_unit }};

    return ability.ir.builder.finish(.{
        .label = "encode-args-tuple-field-mismatch",
        .ir_hash = 3,
        .entry = ability.ir.builder.function(0),
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &locals,
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &.{},
    }) catch unreachable;
}

const Body = struct {
    pub const compiled_plan = i32EntryPlan();

    pub fn encodeArgs(_: anytype) @TypeOf(.{true}) {
        return .{true};
    }
};

const Program = ability.program("encode-args-tuple-field-mismatch", struct {}, Body);

test "entry tuple args must match parameters" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    _ = try Program.run(&runtime, .{});
}
