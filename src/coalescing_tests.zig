// Copyright (c) 2026 Boundary contributors. MIT license.
//! Independently emitted closures through the public typed authoring API.
const std = @import("std");
const testing = std.testing;
const source = @import("source.zig");
const authoring = @import("authoring.zig");
const data = @import("boundary_data");

pub fn closures(
    allocator: std.mem.Allocator,
    count: usize,
    options: data.coalescing.Options,
) !source.Compiled {
    return buildClosures(allocator, count, options, false);
}

fn buildClosures(
    allocator: std.mem.Allocator,
    count: usize,
    options: data.coalescing.Options,
    literal: bool,
) !source.Compiled {
    var raw = source.Builder.init(allocator);
    defer raw.deinit();
    const a = raw.arena.allocator();
    const context = try authoring.Context.init(&raw);
    const integer = try context.scalar(u64);
    const unit = try context.scalar(void);
    const fields = try a.alloc(authoring.Field, count);
    for (fields, 0..) |*field, id| field.* = .{
        .name = try std.fmt.allocPrint(a, "value-{d}", .{id}),
        .schema = integer,
    };
    const result_schema = try context.record(fields);
    const callable = try context.callable(
        &.{.{ .name = "x", .schema = integer }},
        integer,
        &.{},
        .{ .use = .reusable, .captures = &.{integer} },
    );
    const entry = try context.function("entry", if (literal) &.{} else fields, result_schema, &.{});
    const body = try context.body(entry);
    const failure = try context.literalFailure(void, {});
    const arguments = try a.alloc(authoring.Argument, count);
    for (fields, arguments, 0..) |field, *argument, id| {
        const captured = if (literal)
            try body.constant(u64, 3 + 4 * @as(u64, @intCast(id)))
        else
            try body.parameter(field.name);
        // Each invocation emits a fresh declaration, constructor and capture site.
        const helper = try context.functionFor(field.name, callable);
        const inner = try body.closureBody(helper);
        try context.define(
            helper,
            try inner.ret(try inner.checkedAdd(try inner.parameter("x"), captured, failure)),
        );
        const closure = try body.lambda(helper, callable);
        const x = try body.constant(u64, 10);
        argument.* = .{
            .name = field.name,
            .value = try body.apply(closure, &.{.{ .name = "x", .value = x }}),
        };
    }
    try context.define(entry, try body.ret(try body.product(result_schema, arguments)));
    return context.compileWithOptions(allocator, entry, unit, options);
}

test "coalescing typed authoring shares independently emitted captured closure family" {
    for ([_]usize{ 1, 2, 16, 64, 256 }) |count| {
        var off = try closures(testing.allocator, count, .{});
        defer off.deinit();
        var statistics: data.coalescing.Statistics = .{};
        var safe = try closures(
            testing.allocator,
            count,
            .{ .mode = .safe, .statistics = &statistics },
        );
        defer safe.deinit();
        try testing.expectEqual(count + 1, off.program.functions.len);
        try testing.expectEqual(count, off.program.constructors.len);
        try testing.expectEqual(@as(usize, 2), safe.program.functions.len);
        try testing.expectEqual(@as(usize, 1), safe.program.constructors.len);
        try testing.expectEqual(@as(usize, 1), safe.program.scopes.captures.len);
        const before = try data.program_image.encodedLength(off.program);
        const after = try data.program_image.encodedLength(safe.program);
        try testing.expect(after <= before);
        if (count >= 16) try testing.expect(after < before);
        var constructions: usize = 0;
        for (safe.program.blocks) |block| for (block.instructions) |operation|
            if (operation.opcode == .computation) {
                constructions += 1;
            };
        try testing.expectEqual(count, constructions);
    }
}

test "coalescing preserves distinct literals embedded by independent authoring" {
    var safe = try buildClosures(testing.allocator, 2, .{ .mode = .safe }, true);
    defer safe.deinit();
    try testing.expectEqual(@as(usize, 3), safe.program.functions.len);
    try testing.expectEqual(@as(usize, 2), safe.program.constructors.len);
    try testing.expectEqual(@as(usize, 1), safe.program.scopes.captures.len);
    try testing.expectEqual(@as(usize, 0), safe.program.scopes.captures[0].fields.len);
}

test "coalescing statistics and bounded round storage do not change typed output bytes" {
    var ordinary = try closures(testing.allocator, 2, .{ .mode = .safe });
    defer ordinary.deinit();
    var rounds: [1]data.coalescing.Round = undefined;
    var stats: data.coalescing.Statistics = .{ .rounds = &rounds };
    var observed = try closures(testing.allocator, 2, .{ .mode = .safe, .statistics = &stats });
    defer observed.deinit();
    try testing.expect(stats.round_count > stats.rounds_recorded);
    try testing.expectEqual(@as(usize, 1), stats.rounds_recorded);
    try testing.expectEqual(
        try data.program_image.identity(testing.allocator, ordinary.program),
        try data.program_image.identity(testing.allocator, observed.program),
    );
}

test "coalescing shares depth-eight helper chains through calls and constructed computations" {
    const trees = @import("coalescing_tree_cases.zig");
    inline for (.{ trees.Kind.tree, trees.Kind.tree_near }) |kind| {
        var off = try trees.compile(testing.allocator, kind, .{});
        defer off.deinit();
        var safe = try trees.compile(testing.allocator, kind, .{ .mode = .safe });
        defer safe.deinit();
        try testing.expectEqual(@as(usize, 19), off.program.functions.len);
        try testing.expectEqual(@as(usize, if (kind == .tree) 10 else 19), safe.program.functions.len);
        try testing.expectEqual(@as(usize, 8), off.program.constructors.len);
        try testing.expectEqual(@as(usize, if (kind == .tree) 4 else 8), safe.program.constructors.len);
        try testing.expect(try data.program_image.encodedLength(safe.program) <=
            try data.program_image.encodedLength(off.program));
    }
}

test "coalescing shares stateful code while retaining every dynamic allocation site" {
    const cases = @import("coalescing_state_cases.zig");
    for (std.enums.values(cases.Kind)) |kind| {
        var builder = source.Builder.init(testing.allocator);
        defer builder.deinit();
        const module = try cases.build(&builder, kind);
        var off = try source.lower(testing.allocator, module);
        defer off.deinit();
        var safe = try source.lowerObserved(testing.allocator, module, .{ .coalescing = .{ .mode = .safe } });
        defer safe.deinit();
        try testing.expectEqual(off.program.functions.len - 1, safe.program.functions.len);
        try testing.expectEqual(off.program.constructors.len - 1, safe.program.constructors.len);
        const expected: usize = switch (kind) {
            .cells_independent => 2,
            .cells_shared => 1,
            .memo_independent => 3,
            .memo_shared => 2,
        };
        for ([_]data.activation.Program{ off.program, safe.program }) |program| {
            var allocations: usize = 0;
            for (program.blocks) |block| for (block.instructions) |operation| {
                allocations += @intFromBool(operation.opcode == .cell_new);
            };
            try testing.expectEqual(expected, allocations);
        }
    }
}

test "coalescing handles whole-function slot renaming with simultaneous swaps and cycles" {
    const edges = @import("coalescing_edge_cases.zig");
    for (std.enums.values(edges.Kind)) |kind| {
        var off = try edges.compile(testing.allocator, kind, .{});
        defer off.deinit();
        var safe = try edges.compile(testing.allocator, kind, .{ .mode = .safe });
        defer safe.deinit();
        try testing.expectEqual(@as(usize, 3), off.program.functions.len);
        try testing.expectEqual(@as(usize, 2), safe.program.functions.len);
        try testing.expectEqualSlices(data.program.Id, &.{ 0, 1, 2 }, safe.program.functions[0].inputs);
        try testing.expectEqual(@as(usize, if (kind == .swap) 2 else 3), safe.program.blocks[0].terminator.jump.assignments.len);
    }
}

test "coalescing production generator covers all three-slot renamings and ordered mutations" {
    const cases = @import("coalescing_edge_cases.zig");
    for (0..36) |ordinal| for ([_]usize{ 0, 64 }) |mutation| {
        var result = try cases.generated(testing.allocator, ordinal + mutation, .{ .mode = .safe });
        defer result.deinit();
        try testing.expectEqual(@as(usize, if (mutation == 0) 2 else 3), result.program.functions.len);
    };
    for (0..36) |ordinal| for ([_]data.coalescing.Mode{ .off, .safe }) |mode| {
        try testing.expectError(error.InvalidReference, cases.generated(testing.allocator, ordinal + 128, .{ .mode = mode }));
    };
}

test "coalescing authored recursive groups preserve role distinctions and changed bases" {
    const cases = @import("coalescing_recursive_cases.zig");
    for (std.enums.values(cases.Kind)) |kind| {
        var off = try cases.compile(testing.allocator, kind, .{});
        defer off.deinit();
        var safe = try cases.compile(testing.allocator, kind, .{ .mode = .safe });
        defer safe.deinit();
        try testing.expectEqual(@as(usize, 5), off.program.functions.len);
        try testing.expectEqual(@as(usize, if (kind == .recursive_near) 5 else 3), safe.program.functions.len);
    }
}

const ConcurrentCompilation = struct {
    count: usize,
    expected: [2][32]u8,
    failure: ?anyerror = null,
    completed: usize = 0,

    fn run(self: *ConcurrentCompilation) void {
        var allocator: std.heap.DebugAllocator(.{}) = .init;
        defer if (allocator.deinit() != .ok) {
            self.failure = error.LeakedCompilationStorage;
        };
        self.check(allocator.allocator()) catch |err| {
            self.failure = err;
        };
    }

    fn check(self: *ConcurrentCompilation, allocator: std.mem.Allocator) !void {
        for (0..4) |iteration| {
            // Each thread alternates a discarded attempt, a selected quotient,
            // and the disabled control with independent observations and owners.
            var stats: data.coalescing.Statistics = .{};
            var diagnostic: data.coalescing.Diagnostic = .{};
            const limited = iteration % 3 == 0;
            const enabled = iteration % 3 != 2;
            var compiled = try closures(allocator, self.count, .{
                .mode = if (enabled) .safe else .off,
                .work_limit = if (limited) 0 else std.math.maxInt(u64),
                .statistics = &stats,
                .diagnostic = &diagnostic,
            });
            defer compiled.deinit();
            // closures has already destroyed the source builder at this point.
            const actual = try data.program_image.identity(allocator, compiled.program);
            const expected = self.expected[@intFromBool(enabled and !limited)];
            if (!std.mem.eql(u8, &expected, &actual)) return error.ConcurrentImageMismatch;
            if (limited and stats.outcome != .work_limit) return error.MissingWorkLimit;
            if (diagnostic.code != null) return error.StaleDiagnostic;
            self.completed += 1;
        }
    }
};

test "coalescing concurrent independent compilers preserve deterministic owners and observations" {
    var jobs: [4]ConcurrentCompilation = undefined;
    for (&jobs, [_]usize{ 2, 16, 32, 64 }) |*job, count| {
        job.* = .{ .count = count, .expected = undefined };
        for ([_]data.coalescing.Mode{ .off, .safe }, 0..) |mode, index| {
            var compiled = try closures(testing.allocator, count, .{ .mode = mode });
            defer compiled.deinit();
            job.expected[index] = try data.program_image.identity(testing.allocator, compiled.program);
        }
    }
    var threads: [jobs.len]std.Thread = undefined;
    var started: usize = 0;
    defer for (threads[0..started]) |thread| thread.join();
    for (&threads, &jobs) |*thread, *job| {
        thread.* = try std.Thread.spawn(.{}, ConcurrentCompilation.run, .{job});
        started += 1;
    }
    for (threads) |thread| thread.join();
    started = 0;
    for (jobs) |job| {
        if (job.failure) |err| return err;
        try testing.expectEqual(@as(usize, 4), job.completed);
    }
}
