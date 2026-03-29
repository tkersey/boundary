const effect_ir = @import("effect_ir");
const example_open_row_state_writer = @import("example_open_row_state_writer");
const program_frontend = @import("program_frontend");
const source_lowering = @import("source_lowering");
const std = @import("std");

const DynamicOpenRowSpec = struct {
    module_path: []const u8,
    symbol_name: []const u8,
    requirement_label: []const u8,
    op_name: []const u8,
    output_label: []const u8,
    callee_module_path: []const u8,
    callee_symbol_name: []const u8,
};

test "open-row state-writer workflow lowers through the retained effect-ir path" {
    const program = program_frontend.open_rows.stateWriterWorkflow();
    const lowered = try source_lowering.lowerOpenRowProgram(program);

    try std.testing.expectEqualStrings("example.open_row_state_writer", lowered.label);
    try std.testing.expectEqual(@as(usize, 1), lowered.program.functions.len);
    try std.testing.expectEqualStrings("body", lowered.program.functions[0].symbol.symbol_name);
    try std.testing.expectEqual(@as(usize, 2), lowered.normalization.requirement_count);
    try std.testing.expectEqual(@as(usize, 3), lowered.normalization.op_count);
    try std.testing.expectEqual(@as(usize, 2), lowered.normalization.output_count);
}

fn dynamicOpenRowProgram(comptime spec: DynamicOpenRowSpec) program_frontend.OpenRowProgram {
    const ops = [_]effect_ir.OpSpec{.{
        .requirement_label = spec.requirement_label,
        .op_name = spec.op_name,
        .mode = .transform,
        .PayloadType = void,
        .ResumeType = i32,
    }};
    const requirements = [_]effect_ir.Requirement{.{
        .label = spec.requirement_label,
        .ops = ops[0..],
    }};
    const outputs = [_]effect_ir.OutputSpec{.{
        .label = spec.output_label,
        .OutputType = i32,
    }};
    const call_edges = [_]effect_ir.CallEdge{.{
        .caller = .{
            .module_path = spec.module_path,
            .symbol_name = spec.symbol_name,
        },
        .callee = .{
            .module_path = spec.callee_module_path,
            .symbol_name = spec.callee_symbol_name,
        },
    }};

    return .{
        .label = "example.dynamic_open_row",
        .function = .{
            .symbol = .{
                .module_path = spec.module_path,
                .symbol_name = spec.symbol_name,
            },
            .row = .{ .requirements = requirements[0..] },
            .outputs = outputs[0..],
        },
        .call_edges = call_edges[0..],
    };
}

test "open-row lowering deep-copies caller-owned slices" {
    const alpha = try source_lowering.lowerOpenRowProgram(dynamicOpenRowProgram(.{
        .module_path = "examples/alpha.zig",
        .symbol_name = "alpha",
        .requirement_label = "state",
        .op_name = "get",
        .output_label = "state",
        .callee_module_path = "helper_alpha.zig",
        .callee_symbol_name = "helperAlpha",
    }));
    const beta = try source_lowering.lowerOpenRowProgram(dynamicOpenRowProgram(.{
        .module_path = "examples/beta.zig",
        .symbol_name = "beta",
        .requirement_label = "writer",
        .op_name = "tell",
        .output_label = "writer",
        .callee_module_path = "helper_beta.zig",
        .callee_symbol_name = "helperBeta",
    }));

    try std.testing.expectEqualStrings("examples/alpha.zig", alpha.program.functions[0].symbol.module_path);
    try std.testing.expectEqualStrings("alpha", alpha.program.functions[0].symbol.symbol_name);
    try std.testing.expectEqualStrings("state", alpha.program.functions[0].row.requirements[0].label);
    try std.testing.expectEqualStrings("get", alpha.program.functions[0].row.requirements[0].ops[0].op_name);
    try std.testing.expectEqualStrings("state", alpha.program.functions[0].outputs[0].label);
    try std.testing.expectEqualStrings("helperAlpha", alpha.program.call_edges[0].callee.symbol_name);

    try std.testing.expectEqualStrings("examples/beta.zig", beta.program.functions[0].symbol.module_path);
    try std.testing.expectEqualStrings("beta", beta.program.functions[0].symbol.symbol_name);
    try std.testing.expectEqualStrings("writer", beta.program.functions[0].row.requirements[0].label);
    try std.testing.expectEqualStrings("tell", beta.program.functions[0].row.requirements[0].ops[0].op_name);
    try std.testing.expectEqualStrings("writer", beta.program.functions[0].outputs[0].label);
    try std.testing.expectEqualStrings("helperBeta", beta.program.call_edges[0].callee.symbol_name);
}

test "open-row state-writer example stays transcript-backed" {
    var writer_buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buffer);
    try example_open_row_state_writer.run(&writer);
    try std.testing.expectEqualStrings(
        "item=query=artifact-search\nitem=workflow=queued\nfinal_state=6\nvalue=done\n",
        writer.buffered(),
    );
}
