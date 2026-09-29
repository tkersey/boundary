// Copyright (c) 2026 Boundary contributors. MIT license.
const std = @import("std");
const boundary = @import("boundary");
const a = boundary.authoring;
const Plan = struct { context: *a.Context, entry: *const a.Function, failure: *const a.Schema };
fn construct(b: *boundary.source.Builder, n: usize) !Plan {
    const c = try a.Context.init(b);
    const boolean = try c.scalar(bool);
    const unit = try c.scalar(void);
    const sequence = try c.sequence(boolean);
    const entry = try c.function("capture driver", &.{.{ .name = "seed", .schema = boolean }}, sequence, &.{});
    const body = try c.body(entry);
    const values = try b.allocator().alloc(*const a.Value, n);
    const schemas = try b.allocator().alloc(*const a.Schema, n);
    @memset(schemas, boolean);
    var previous = try body.parameter("seed");
    const no = try body.constant(bool, false);
    for (values) |*value| {
        previous = try body.equal(previous, no);
        value.* = previous;
    }
    const callable = try c.callable(&.{}, sequence, &.{}, .{ .use = .reusable, .captures = schemas });
    const helper = try c.functionFor("materialize ordered captures", callable);
    const inner = try body.closureBody(helper);
    try c.define(helper, try inner.ret(try inner.sequenceValue(sequence, values)));
    try c.define(entry, try body.ret(try body.apply(try body.lambda(helper, callable), &.{})));
    return .{ .context = c, .entry = entry, .failure = unit };
}
pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    for ([_]usize{ 32, 64, 128 }) |n| {
        var samples: [9]u64 = undefined;
        var allocated: usize = 0;
        var calls: usize = 0;
        for (0..12) |window| {
            var counter = std.testing.FailingAllocator.init(init.gpa, .{});
            {
                var b = boundary.source.Builder.init(counter.allocator());
                defer b.deinit();
                const start = std.Io.Clock.awake.now(init.io);
                _ = try construct(&b, n);
                if (window >= 3) samples[window - 3] = @intCast(start.durationTo(std.Io.Clock.awake.now(init.io)).nanoseconds);
            }
            if (counter.allocated_bytes != counter.freed_bytes) return error.Leak;
            allocated = counter.allocated_bytes;
            calls = counter.allocations;
        }
        var b = boundary.source.Builder.init(init.gpa);
        defer b.deinit();
        const plan = try construct(&b, n);
        var counter = std.testing.FailingAllocator.init(init.gpa, .{});
        const start = std.Io.Clock.awake.now(init.io);
        var compiled = try plan.context.compile(counter.allocator(), plan.entry, plan.failure);
        const checked_materialization_ns: u64 = @intCast(start.durationTo(std.Io.Clock.awake.now(init.io)).nanoseconds);
        var captures: usize = 0;
        for (compiled.program.scopes.captures) |layout| captures += layout.fields.len;
        if (captures != n) return error.LostCapture;
        compiled.deinit();
        if (counter.allocated_bytes != counter.freed_bytes) return error.Leak;
        try std.json.Stringify.value(.{ .n = n, .authoring_samples_ns = samples, .authoring_allocated_bytes = allocated, .authoring_allocations = calls, .checked_materialization_ns = checked_materialization_ns, .checked_allocated_bytes = counter.allocated_bytes, .checked_capture_fields = captures, .source_capture_bound_fields = n, .source_sequence_operands = n }, .{}, &out.interface);
        try out.interface.writeByte('\n');
        try out.interface.flush();
    }
}
