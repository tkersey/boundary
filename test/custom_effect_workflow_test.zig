const ability = @import("ability");
const ability_compile = @import("ability_compile");
const example = @import("example_custom_approval_workflow");
const std = @import("std");

const ExpectedTranscript = struct {
    lookups: usize,
    choices: usize,
    continuations: usize,
    aborts: usize,
    last_lookup: []const u8,
    last_choice: []const u8,
    last_abort: []const u8,
};

fn expectTranscript(
    actual: example.Transcript,
    expected: ExpectedTranscript,
) !void {
    try std.testing.expectEqual(expected.lookups, actual.lookups);
    try std.testing.expectEqual(expected.choices, actual.choices);
    try std.testing.expectEqual(expected.continuations, actual.continuations);
    try std.testing.expectEqual(expected.aborts, actual.aborts);
    try std.testing.expectEqualStrings(expected.last_lookup, actual.last_lookup);
    try std.testing.expectEqualStrings(expected.last_choice, actual.last_choice);
    try std.testing.expectEqualStrings(expected.last_abort, actual.last_abort);
}

fn workflowLoweringSpec() ability_compile.lowering_api.LowerSpec {
    return .{
        .label = "example.custom_approval_workflow",
        .entry_symbol = "loweredWorkflowBody",
        .row = ability_compile.effect_ir.mergeRows(.{
            ability_compile.effect_ir.rowFromSpec(.{
                .directory = .{
                    .exists = ability_compile.effect_ir.Transform([]const u8, bool),
                },
            }),
            ability_compile.effect_ir.rowFromSpec(.{
                .approval = .{
                    .request = ability_compile.effect_ir.Choice([]const u8, []const u8),
                },
            }),
            ability_compile.effect_ir.rowFromSpec(.{
                .guard = .{
                    .invalid = ability_compile.effect_ir.Abort([]const u8),
                },
            }),
        }),
        .ValueType = []const u8,
    };
}

fn workflowSource() ability_compile.lowering_api.SourceRef {
    const caller = example.approval_workflow_body.source_location;
    return ability_compile.lowering_api.sourceWithContent(
        "examples/custom_approval_workflow.zig",
        .{
            .module = caller.module,
            .file = "examples/custom_approval_workflow.zig",
            .line = caller.line,
            .column = caller.column,
            .fn_name = caller.fn_name,
        },
        example.approval_workflow_body.source,
    );
}

const LoweredWorkflow = ability_compile.lower(workflowSource(), workflowLoweringSpec());

test "custom approval workflow approves through public custom-effect transcript" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try example.runApprove(&runtime);
    try std.testing.expectEqualStrings("published:approved", result.value);
    try expectTranscript(result.transcript, .{
        .lookups = 1,
        .choices = 1,
        .continuations = 1,
        .aborts = 0,
        .last_lookup = "request-7",
        .last_choice = "request-7",
        .last_abort = "",
    });
}

test "custom approval workflow denies without recording a continuation" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try example.runDeny(&runtime);
    try std.testing.expectEqualStrings("denied", result.value);
    try expectTranscript(result.transcript, .{
        .lookups = 1,
        .choices = 1,
        .continuations = 0,
        .aborts = 0,
        .last_lookup = "request-7",
        .last_choice = "request-7",
        .last_abort = "",
    });
}

test "custom approval workflow aborts invalid requests before choice" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try example.runInvalid(&runtime);
    try std.testing.expectEqualStrings("invalid:missing", result.value);
    try expectTranscript(result.transcript, .{
        .lookups = 1,
        .choices = 0,
        .continuations = 0,
        .aborts = 1,
        .last_lookup = "request-7",
        .last_choice = "",
        .last_abort = "missing",
    });
}

test "custom approval workflow source lowers to executable ProgramPlan" {
    comptime {
        const plan = LoweredWorkflow.runtime_plan;
        if (!std.mem.eql(u8, plan.label, "example.custom_approval_workflow")) @compileError("custom workflow plan label drifted");
        if (plan.requirements.len != 3) @compileError("custom workflow plan must keep transform, choice, and abort requirements");
        if (plan.ops.len != 3) @compileError("custom workflow plan must keep transform, choice, and abort ops");
        if (plan.functions.len == 0) @compileError("custom workflow plan must include lowered function rows");
        if (plan.blocks.len == 0) @compileError("custom workflow plan must include executable blocks");
        if (plan.terminators.len == 0) @compileError("custom workflow plan must include executable terminators");
        if (plan.instructions.len == 0) @compileError("custom workflow plan must include executable instructions");
        if (plan.functions[plan.entry_index].value_codec != .string) @compileError("custom workflow entry must return a string");
    }

    try LoweredWorkflow.runtime_plan.validate();
}
