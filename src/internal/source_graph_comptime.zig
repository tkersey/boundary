const shared = @import("source_graph_engine");
const std = @import("std");

/// Error surface for comptime helper/source graph extraction.
pub const Error = shared.Error;

/// One top-level function discovered by the shared source extractor.
pub const FunctionNode = shared.FunctionNode;
/// One helper-call edge between top-level functions in the same source file.
pub const HelperEdge = shared.HelperEdge;
/// One direct `eff.requirement.op(...)` use discovered inside a function body.
pub const DirectOpUse = shared.DirectOpUse;
/// Comptime-extracted same-file helper graph and direct op-use summary.
pub const ModuleGraph = shared.ModuleGraph;

/// Parse and analyze one same-module Zig source buffer at comptime.
pub fn analyzeModule(comptime source: [:0]const u8, comptime entry_symbol: []const u8) Error!ModuleGraph {
    return try shared.analyzeComptime(source, .{
        .entry_symbol = entry_symbol,
        .reject_recursive_helpers = true,
        .reject_indirect_effect_access = true,
        .reject_malformed_statements = true,
    });
}

test "analyzeModule finds helper edges and direct op uses" {
    const graph = try analyzeModule(
        \\fn helper(eff: anytype) void {
        \\    _ = eff.writer.tell("queued");
        \\}
        \\pub fn runBody(eff: anytype) void {
        \\    _ = eff.state.get();
        \\    helper(eff);
        \\}
    ,
        "runBody",
    );

    try std.testing.expectEqual(@as(usize, 2), graph.functions.len);
    try std.testing.expectEqual(@as(usize, 1), graph.entry_index.?);
    try std.testing.expectEqual(@as(usize, 1), graph.helper_edges.len);
    try std.testing.expectEqual(@as(usize, 2), graph.direct_op_uses.len);
    try std.testing.expectEqualStrings("writer", graph.direct_op_uses[0].requirement_label);
    try std.testing.expectEqualStrings("tell", graph.direct_op_uses[0].op_name);
}

test "analyzeModule rejects recursive helper graphs" {
    try std.testing.expectError(error.RecursiveHelpers, analyzeModule(
        \\fn helper() void { runBody(); }
        \\pub fn runBody() void { helper(); }
    ,
        "runBody",
    ));
}
