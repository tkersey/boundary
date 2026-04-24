const ability = @import("ability");
const std = @import("std");
const zprof = @import("zprof");

const Zprof = zprof.Zprof;
const NoError = error{};
const profile_iterations: usize = 2_000;
const writer_items_per_body: usize = 64;
const resource_items_per_body: usize = 32;

const WriterInstance = ability.effect.writer.Instance(usize, NoError);
const ResourceInstance = ability.effect.resource.Instance(usize, NoError);

fn preserveValue(value: anytype) @TypeOf(value) {
    const preserved = value;
    std.mem.doNotOptimizeAway(preserved);
    return preserved;
}

fn printProfileLine(writer: anytype, label: []const u8, checksum: usize, profiler: anytype) !void {
    try writer.print(
        "lane={s} iterations={d} checksum={d} alloc_bytes={d} alloc_count={d} free_count={d} live_peak={d} live_bytes={d} leaks={}\n",
        .{
            label,
            profile_iterations,
            checksum,
            profiler.profiler.allocated.get(),
            profiler.profiler.alloc_count.get(),
            profiler.profiler.free_count.get(),
            profiler.profiler.peak_requested.get(),
            profiler.profiler.live_requested.get(),
            profiler.profiler.hasLeaks(),
        },
    );
}

fn runWriterRaw(allocator: std.mem.Allocator) !usize {
    var checksum: usize = 0;
    var iteration: usize = 0;
    while (iteration < profile_iterations) : (iteration += 1) {
        var items: std.ArrayList(usize) = .empty;
        defer items.deinit(allocator);

        var current: usize = 0;
        while (current < writer_items_per_body) : (current += 1) {
            try items.append(allocator, current + 1);
        }

        const owned = try items.toOwnedSlice(allocator);
        defer allocator.free(owned);
        std.mem.doNotOptimizeAway(owned.ptr);

        var lane_checksum: usize = owned.len;
        for (owned) |item| lane_checksum +%= item;
        checksum +%= lane_checksum;
    }
    return checksum;
}

fn runWriterEffect(runtime: *ability.Runtime, instance: *WriterInstance, profiler: *Zprof(.{})) !usize {
    const allocator = profiler.allocator();

    // Exclude one-time runtime/handler bootstrap from the steady-state profile.
    const warmup = preserveValue(try ability.effect.writer.handle(usize, usize, runtime, instance, allocator, struct {
        /// Append one fixed number of writer items.
        pub fn body(comptime Cap: type, ctx: anytype) ability.ResetError(NoError)!usize {
            var current: usize = 0;
            while (current < writer_items_per_body) : (current += 1) {
                try ability.effect.writer.tell(Cap, ctx, current + 1);
            }
            return 0;
        }
    }));
    allocator.free(warmup.items);
    profiler.profiler.reset();

    var checksum: usize = 0;
    var iteration: usize = 0;
    while (iteration < profile_iterations) : (iteration += 1) {
        const body = struct {
            /// Append one fixed number of writer items.
            pub fn body(comptime Cap: type, ctx: anytype) ability.ResetError(NoError)!usize {
                var current: usize = 0;
                while (current < writer_items_per_body) : (current += 1) {
                    try ability.effect.writer.tell(Cap, ctx, current + 1);
                }
                return 0;
            }
        };

        const result = preserveValue(try ability.effect.writer.handle(usize, usize, runtime, instance, allocator, body));
        defer allocator.free(result.items);
        std.mem.doNotOptimizeAway(result.items.ptr);

        var lane_checksum: usize = result.items.len + result.value;
        for (result.items) |item| lane_checksum +%= item;
        checksum +%= lane_checksum;
    }
    return checksum;
}

const resource_synth = struct {
    threadlocal var current_base: usize = 0;
    threadlocal var acquire_count: usize = 0;
    threadlocal var release_sink: usize = 0;

    fn acquire() usize {
        const value = current_base + acquire_count + 1;
        acquire_count += 1;
        return value;
    }

    fn release(resource: usize) void {
        release_sink +%= resource;
    }
};

fn runResourceRaw(allocator: std.mem.Allocator) !usize {
    var checksum: usize = 0;
    var iteration: usize = 0;
    while (iteration < profile_iterations) : (iteration += 1) {
        resource_synth.current_base = iteration * resource_items_per_body;
        resource_synth.acquire_count = 0;
        resource_synth.release_sink = 0;

        var resources: std.ArrayList(usize) = .empty;
        defer resources.deinit(allocator);

        var lane_checksum: usize = 0;
        var current: usize = 0;
        while (current < resource_items_per_body) : (current += 1) {
            const resource = resource_synth.acquire();
            try resources.append(allocator, resource);
            lane_checksum +%= resource;
        }
        while (resources.items.len != 0) {
            const resource = resources.items[resources.items.len - 1];
            resources.items.len -= 1;
            resource_synth.release(resource);
        }
        checksum +%= lane_checksum;
    }
    return checksum;
}

fn runResourceEffect(runtime: *ability.Runtime, instance: *ResourceInstance, profiler: *Zprof(.{})) !usize {
    resource_synth.current_base = profile_iterations * resource_items_per_body;
    resource_synth.acquire_count = 0;
    resource_synth.release_sink = 0;
    _ = preserveValue(try ability.effect.resource.handle(usize, runtime, instance, struct {
        /// Acquire one synthetic resource value.
        pub fn acquire() usize {
            return resource_synth.acquire();
        }

        /// Release one synthetic resource value.
        pub fn release(resource: usize) void {
            resource_synth.release(resource);
        }
    }, struct {
        /// Acquire a fixed number of resources under the effect handler.
        pub fn body(comptime Cap: type, ctx: anytype) ability.ResetError(NoError)!usize {
            var lane_checksum: usize = 0;
            var current: usize = 0;
            while (current < resource_items_per_body) : (current += 1) {
                lane_checksum +%= try ability.effect.resource.acquire(Cap, ctx);
            }
            return lane_checksum;
        }
    }));
    profiler.profiler.reset();

    var checksum: usize = 0;
    var iteration: usize = 0;
    while (iteration < profile_iterations) : (iteration += 1) {
        resource_synth.current_base = iteration * resource_items_per_body;
        resource_synth.acquire_count = 0;
        resource_synth.release_sink = 0;

        const manager = struct {
            /// Acquire one synthetic resource value.
            pub fn acquire() usize {
                return resource_synth.acquire();
            }

            /// Release one synthetic resource value.
            pub fn release(resource: usize) void {
                resource_synth.release(resource);
            }
        };

        const body = struct {
            /// Acquire a fixed number of resources under the effect handler.
            pub fn body(comptime Cap: type, ctx: anytype) ability.ResetError(NoError)!usize {
                var lane_checksum: usize = 0;
                var current: usize = 0;
                while (current < resource_items_per_body) : (current += 1) {
                    lane_checksum +%= try ability.effect.resource.acquire(Cap, ctx);
                }
                return lane_checksum;
            }
        };

        checksum +%= preserveValue(try ability.effect.resource.handle(usize, runtime, instance, manager, body));
    }
    return checksum;
}

/// Profile allocator traffic for the remaining writer/resource hotspot lanes.
pub fn main(init: std.process.Init) anyerror!void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var raw_writer_profiler: Zprof(.{}) = .init(std.heap.smp_allocator, stdout);
    try printProfileLine(stdout, "writer_raw_batch64", try runWriterRaw(raw_writer_profiler.allocator()), &raw_writer_profiler);

    var effect_writer_profiler: Zprof(.{}) = .init(std.heap.smp_allocator, stdout);
    var effect_writer_runtime = ability.Runtime.init(effect_writer_profiler.allocator());
    defer effect_writer_runtime.deinit();
    var effect_writer_instance = WriterInstance.init();
    try printProfileLine(stdout, "writer_effect_batch64", try runWriterEffect(&effect_writer_runtime, &effect_writer_instance, &effect_writer_profiler), &effect_writer_profiler);

    var raw_resource_profiler: Zprof(.{}) = .init(std.heap.smp_allocator, stdout);
    try printProfileLine(stdout, "resource_raw_32", try runResourceRaw(raw_resource_profiler.allocator()), &raw_resource_profiler);

    var effect_resource_profiler: Zprof(.{}) = .init(std.heap.smp_allocator, stdout);
    var effect_resource_runtime = ability.Runtime.init(effect_resource_profiler.allocator());
    defer effect_resource_runtime.deinit();
    var effect_resource_instance = ResourceInstance.init();
    try printProfileLine(stdout, "resource_effect_32", try runResourceEffect(&effect_resource_runtime, &effect_resource_instance, &effect_resource_profiler), &effect_resource_profiler);

    try stdout.flush();
}
