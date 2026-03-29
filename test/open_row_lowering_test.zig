const example_open_row_state_writer = @import("example_open_row_state_writer");
const shift = @import("shift");
const std = @import("std");

const DynamicOpenRowSpec = struct {
    module_path: []const u8,
    symbol_name: []const u8,
    row: shift.ir.Row,
    outputs: []const shift.ir.OutputSpec,
    call_edges: []const shift.ir.CallEdge = &.{},
};

test "open-row state-writer workflow lowers through the public additive lowering path" {
    const lowered = try example_open_row_state_writer.loweredProgram();

    try std.testing.expectEqualStrings("example.open_row_state_writer", lowered.label);
    try std.testing.expectEqual(@as(usize, 1), lowered.program.functions.len);
    try std.testing.expectEqualStrings("body", lowered.program.functions[0].symbol.symbol_name);
    try std.testing.expectEqual(@as(usize, 2), lowered.normalization.requirement_count);
    try std.testing.expectEqual(@as(usize, 3), lowered.normalization.op_count);
    try std.testing.expectEqual(@as(usize, 2), lowered.normalization.output_count);
}

fn dynamicLowerSpec(comptime spec: DynamicOpenRowSpec) shift.lowering.LowerSpec {
    return .{
        .label = "example.dynamic_open_row",
        .module_path = spec.module_path,
        .symbol_name = spec.symbol_name,
        .row = spec.row,
        .outputs = spec.outputs,
        .call_edges = spec.call_edges,
    };
}

test "open-row lowering deep-copies caller-owned slices" {
    const alpha = try shift.lowering.lowerOpenRow(dynamicLowerSpec(.{
        .module_path = "examples/alpha.zig",
        .symbol_name = "alpha",
        .row = shift.ir.rowFromSpec(.{
            .state = .{
                .get = shift.ir.Transform(void, i32),
            },
        }),
        .outputs = &.{.{ .label = "state", .OutputType = i32 }},
        .call_edges = &.{.{
            .caller = .{ .module_path = "examples/alpha.zig", .symbol_name = "alpha" },
            .callee = .{ .module_path = "examples/alpha.zig", .symbol_name = "alpha" },
        }},
    }));
    const beta = try shift.lowering.lowerOpenRow(dynamicLowerSpec(.{
        .module_path = "examples/beta.zig",
        .symbol_name = "beta",
        .row = shift.ir.rowFromSpec(.{
            .writer = .{
                .tell = shift.ir.Transform(void, i32),
            },
        }),
        .outputs = &.{.{ .label = "writer", .OutputType = i32 }},
        .call_edges = &.{.{
            .caller = .{ .module_path = "examples/beta.zig", .symbol_name = "beta" },
            .callee = .{ .module_path = "examples/beta.zig", .symbol_name = "beta" },
        }},
    }));

    try std.testing.expectEqualStrings("examples/alpha.zig", alpha.program.functions[0].symbol.module_path);
    try std.testing.expectEqualStrings("alpha", alpha.program.functions[0].symbol.symbol_name);
    try std.testing.expectEqualStrings("state", alpha.program.functions[0].row.requirements[0].label);
    try std.testing.expectEqualStrings("get", alpha.program.functions[0].row.requirements[0].ops[0].op_name);
    try std.testing.expectEqualStrings("state", alpha.program.functions[0].outputs[0].label);
    try std.testing.expectEqualStrings("alpha", alpha.program.call_edges[0].callee.symbol_name);

    try std.testing.expectEqualStrings("examples/beta.zig", beta.program.functions[0].symbol.module_path);
    try std.testing.expectEqualStrings("beta", beta.program.functions[0].symbol.symbol_name);
    try std.testing.expectEqualStrings("writer", beta.program.functions[0].row.requirements[0].label);
    try std.testing.expectEqualStrings("tell", beta.program.functions[0].row.requirements[0].ops[0].op_name);
    try std.testing.expectEqualStrings("writer", beta.program.functions[0].outputs[0].label);
    try std.testing.expectEqualStrings("beta", beta.program.call_edges[0].callee.symbol_name);
}

test "open-row lowering rejects helper call edges that would leave dangling callees" {
    try std.testing.expectError(error.UnsupportedHelperCallEdge, shift.lowering.lowerOpenRow(dynamicLowerSpec(.{
        .module_path = "examples/alpha.zig",
        .symbol_name = "alpha",
        .row = shift.ir.rowFromSpec(.{
            .state = .{
                .get = shift.ir.Transform(void, i32),
            },
        }),
        .outputs = &.{.{ .label = "state", .OutputType = i32 }},
        .call_edges = &.{.{
            .caller = .{ .module_path = "examples/alpha.zig", .symbol_name = "alpha" },
            .callee = .{ .module_path = "helper_alpha.zig", .symbol_name = "helperAlpha" },
        }},
    })));
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
