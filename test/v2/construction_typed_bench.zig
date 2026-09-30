// Copyright (c) 2026 Boundary contributors. MIT license.
const std = @import("std");
const boundary = @import("boundary");
const fixture = @import("construction.zig");
const Stage = boundary.source.CompileStage;
const Stages = struct {
    io: std.Io,
    last: ?std.Io.Timestamp = null,
    previous: ?Stage = null,
    ns: [@typeInfo(Stage).@"enum".fields.len]u64 = @splat(0),
    fn enter(raw: *anyopaque, stage: Stage) void {
        const self: *@This() = @ptrCast(@alignCast(raw));
        const now = std.Io.Clock.awake.now(self.io);
        if (self.previous) |before| self.ns[@intFromEnum(before)] += @intCast(self.last.?.durationTo(now).nanoseconds);
        self.last = now;
        self.previous = stage;
    }
};
pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    for ([_]usize{ 128, 256, 512 }) |n| {
        const flags = try init.gpa.alloc(bool, n);
        defer init.gpa.free(flags);
        for (flags, 0..) |*flag, i| flag.* = i % 3 == 0;
        var samples: [9]u64 = undefined;
        var construction_allocated: usize = 0;
        var construction_allocations: usize = 0;
        var materialized_terms: usize = 0;
        var materialized_values: usize = 0;
        for (0..12) |window| {
            var counted = std.testing.FailingAllocator.init(init.gpa, .{});
            const start = std.Io.Clock.awake.now(init.io);
            {
                var b = boundary.source.Builder.init(counted.allocator());
                defer b.deinit();
                var trace: fixture.Trace = .{};
                const module = try fixture.typedChain(&b, flags, &trace);
                if (trace.calls != n) return error.EmitterCount;
                materialized_terms = module.terms.len;
                materialized_values = module.values.len;
            }
            if (window >= 3) samples[window - 3] = @intCast(start.durationTo(std.Io.Clock.awake.now(init.io)).nanoseconds);
            if (counted.allocated_bytes != counted.freed_bytes) return error.Leak;
            construction_allocated = counted.allocated_bytes;
            construction_allocations = counted.allocations;
        }
        var b = boundary.source.Builder.init(init.gpa);
        defer b.deinit();
        var trace: fixture.Trace = .{};
        const module = try fixture.typedChain(&b, flags, &trace);
        var observer: Stages = .{ .io = init.io };
        var counted = std.testing.FailingAllocator.init(init.gpa, .{});
        const compile_start = std.Io.Clock.awake.now(init.io);
        var compiled = try boundary.program.compileObserved(counted.allocator(), module, .{ .observer = .{ .context = &observer, .enter = Stages.enter } });
        const compile_ns: u64 = @intCast(compile_start.durationTo(std.Io.Clock.awake.now(init.io)).nanoseconds);
        const output_bytes = try @import("boundary_data").program_image.encodedLength(compiled.program);
        compiled.deinit();
        if (counted.allocated_bytes != counted.freed_bytes) return error.Leak;
        try std.json.Stringify.value(.{ .n = n, .construction_samples_ns = samples, .construction_allocations = construction_allocations, .construction_allocated_bytes = construction_allocated, .materialized_terms = materialized_terms, .materialized_values = materialized_values, .emitter_calls = trace.calls, .compile_stage_ns = observer.ns, .compile_total_ns = compile_ns, .compile_allocations = counted.allocations, .compile_allocated_bytes = counted.allocated_bytes, .image_bytes = output_bytes }, .{}, &out.interface);
        try out.interface.writeByte('\n');
        try out.interface.flush();
    }
}
