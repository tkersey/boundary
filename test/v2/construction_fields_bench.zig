const std = @import("std");
const boundary = @import("boundary");
const source = boundary.source;
const author = boundary.authoring;
pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    for ([_]usize{ 1, 2, 4, 8, 16, 128, 256, 512 }) |n| {
        var declarations: [9]u64 = undefined;
        var assemblies: [9]u64 = undefined;
        var allocations: usize = 0;
        var bytes: usize = 0;
        for (0..12) |window| {
            var counted = std.testing.FailingAllocator.init(init.gpa, .{});
            {
                var b = source.Builder.init(counted.allocator());
                defer b.deinit();
                const c = try author.Context.init(&b);
                const boolean = try c.scalar(bool);
                const unit = try c.scalar(void);
                const fields = try b.allocator().alloc(author.Field, n);
                for (fields, 0..) |*field, i| field.* = .{ .name = try b.allocator().print("field_{d}", .{i}), .schema = boolean };
                const ds = std.Io.Clock.awake.now(init.io);
                const record = try c.record(fields);
                const dn: u64 = @intCast(ds.durationTo(std.Io.Clock.awake.now(init.io)).nanoseconds);
                const entry = try c.function("wide", &.{}, record, &.{});
                const body = try c.body(entry);
                const yes = try body.constant(bool, true);
                const arguments = try b.allocator().alloc(author.Argument, n);
                for (arguments, 0..) |*arg, i| arg.* = .{ .name = fields[n - i - 1].name, .value = yes };
                const ps = std.Io.Clock.awake.now(init.io);
                const value = try body.product(record, arguments);
                const pn: u64 = @intCast(ps.durationTo(std.Io.Clock.awake.now(init.io)).nanoseconds);
                try c.define(entry, try body.ret(value));
                const module = try c.module(entry, unit);
                if (module.values.len < 2) return error.MissingMaterialization;
                if (window >= 3) {
                    declarations[window - 3] = dn;
                    assemblies[window - 3] = pn;
                }
            }
            if (counted.allocated_bytes != counted.freed_bytes) return error.Leak;
            allocations = counted.allocations;
            bytes = counted.allocated_bytes;
        }
        try std.json.Stringify.value(.{ .n = n, .declaration_ns = declarations, .assembly_ns = assemblies, .allocations = allocations, .allocated_bytes = bytes, .original_declaration_name_comparisons = n * (n - 1) / 2, .original_argument_name_comparisons = n * n }, .{}, &out.interface);
        try out.interface.writeByte('\n');
        try out.interface.flush();
    }
}
