// Copyright (c) 2026 Boundary contributors. MIT license.
//! Translate raw admission locations without inventing a unique capture producer.
const std = @import("std");
const data = @import("boundary_data");
const p = data.program;
const Diagnostic = @import("diagnostic.zig").Diagnostic;

fn origin(function: p.Id, origins: ?[]const p.Id, count: usize) ?p.Id {
    const mapped = if (origins) |map|
        (if (function < map.len) map[@intCast(function)] else return null)
    else
        function;
    return if (mapped < count) mapped else null;
}

/// Non-allocating error translation, including allocation failures. Capture sets
/// are borrowed only for this call; the diagnostic retains IDs in inline storage.
pub fn translate(
    diagnostic: *Diagnostic,
    program: data.activation.Program,
    origins: ?[]const p.Id,
    captures: []const std.ArrayList(p.Id),
) void {
    diagnostic.origins = .{};
    diagnostic.variable = null;
    diagnostic.function = if (diagnostic.target.function) |function|
        origin(function, origins, captures.len)
    else
        null;
    const capture = diagnostic.target.capture orelse return;
    for (program.constructors) |constructor| {
        if (constructor.capture != capture) continue;
        // A constructor diagnostic names its actual function. Other users of
        // shared capture metadata cannot replace that authoritative occurrence.
        if (diagnostic.target.function) |actual|
            if (constructor.function != actual) continue;
        const source = origin(constructor.function, origins, captures.len) orelse continue;
        diagnostic.origins.add(source);
    }
    if (diagnostic.origins.count == 0) return;
    diagnostic.function = diagnostic.origins.functions[0];
    if (diagnostic.origins.ambiguous) return;
    if (diagnostic.target.field) |field| {
        const variables = captures[@intCast(diagnostic.function.?)].items;
        if (field < variables.len) diagnostic.variable = variables[@intCast(field)];
    }
}

test "capture diagnostics prefer the actual producer over an earlier metadata user" {
    var first = [_]p.Id{17};
    var second = [_]p.Id{29};
    const captures = [_]std.ArrayList(p.Id){
        .{ .items = &first, .capacity = 1 }, .{ .items = &second, .capacity = 1 },
    };
    const program: data.activation.Program = .{
        .roots = .{ .entry = 0, .result = 0, .failure = 0 },
        .schemas = &.{.unit},
        .constants = &.{},
        .effects = &.{},
        .functions = &.{},
        .blocks = &.{},
        .constructors = &.{
            .{ .function = 0, .capture = 0, .schema = 0 },
            .{ .function = 1, .capture = 0, .schema = 0 },
        },
    };
    var diagnostic: Diagnostic = .{
        .target = .{ .phase = .constructor, .function = 1, .capture = 0, .field = 0 },
    };
    translate(&diagnostic, program, null, &captures);
    try std.testing.expectEqual(@as(?p.Id, 1), diagnostic.function);
    try std.testing.expectEqual(@as(?p.Id, 29), diagnostic.variable);
    try std.testing.expect(!diagnostic.origins.ambiguous);

    diagnostic.target = .{ .phase = .capture, .capture = 0, .field = 0 };
    translate(&diagnostic, program, null, &captures);
    try std.testing.expectEqual(@as(?p.Id, 0), diagnostic.function);
    try std.testing.expectEqual(@as(?p.Id, null), diagnostic.variable);
    try std.testing.expect(diagnostic.origins.ambiguous);
    try std.testing.expectEqualSlices(p.Id, &.{ 0, 1 }, diagnostic.origins.items());

    diagnostic.target = .{ .phase = .constructor, .function = 0, .capture = 0, .field = 0 };
    translate(&diagnostic, program, &.{ 1, 0 }, &captures);
    try std.testing.expectEqual(@as(?p.Id, 1), diagnostic.function);
    try std.testing.expectEqual(@as(?p.Id, 29), diagnostic.variable);
}

test "origin presentation reports truncation and never turns many origins into unique" {
    var origins: @import("diagnostic.zig").Origins = .{};
    for (0..20) |id| origins.add(id);
    try std.testing.expectEqual(@as(usize, 8), origins.items().len);
    try std.testing.expect(origins.truncated and origins.ambiguous);
    origins.add(0);
    try std.testing.expectEqual(@as(usize, 8), origins.items().len);
}
