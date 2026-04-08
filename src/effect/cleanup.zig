const lowered_machine = @import("lowered_machine");
const portable_core = @import("portable_core");
const std = @import("std");

/// Type-erased cleanup frame used to unwind bracketed resource handles.
pub const Frame = portable_core.CleanupFrame;
/// Explicit cleanup stack owner.
pub const Stack = portable_core.CleanupStack;

fn activeCleanupStack() *Stack {
    const runtime = lowered_machine.activeRuntime() orelse std.debug.panic("compat cleanup helpers require an active runtime", .{});
    return &runtime.core.cleanup;
}

/// Return the current cleanup stack marker.
pub fn checkpoint() ?*Frame {
    return activeCleanupStack().checkpoint();
}

/// Push one cleanup frame onto the active unwind stack.
pub fn push(frame: *Frame) void {
    activeCleanupStack().push(frame);
}

/// Unwind cleanup frames until `marker` becomes the active frame again.
pub fn unwindTo(marker: ?*Frame) anyerror!void {
    return activeCleanupStack().unwindTo(marker);
}

test "compat cleanup helpers stay isolated per active runtime thread" {
    const Probe = struct {
        frame: Frame = .{ .cleanupFn = cleanup },
        counter: *usize,

        fn cleanup(raw: *Frame) anyerror!void {
            const self: *@This() = @fieldParentPtr("frame", raw);
            self.counter.* += 1;
        }
    };

    const Shared = struct {
        stage: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),
        first_cleanup_calls: usize = 0,
        second_cleanup_calls: usize = 0,
    };

    const waitForStage = struct {
        fn until(stage: *std.atomic.Value(u8), expected: u8) void {
            while (stage.load(.acquire) < expected) {
                std.Thread.yield() catch {};
            }
        }
    }.until;

    var shared = Shared{};

    const first = try std.Thread.spawn(.{}, struct {
        fn run(state: *Shared) void {
            var runtime = lowered_machine.Runtime.init(std.testing.allocator);
            defer runtime.deinit();
            lowered_machine.beginExecution(&runtime) catch unreachable;
            defer lowered_machine.endExecution(&runtime);

            var probe = Probe{ .counter = &state.first_cleanup_calls };
            push(&probe.frame);
            state.stage.store(1, .release);
            waitForStage(&state.stage, 2);
            std.testing.expectEqual(@as(?*Frame, &probe.frame), checkpoint()) catch unreachable;
            unwindTo(null) catch unreachable;
            std.testing.expectEqual(@as(usize, 1), state.first_cleanup_calls) catch unreachable;
            std.testing.expectEqual(@as(usize, 1), state.second_cleanup_calls) catch unreachable;
        }
    }.run, .{&shared});

    const second = try std.Thread.spawn(.{}, struct {
        fn run(state: *Shared) void {
            waitForStage(&state.stage, 1);

            var runtime = lowered_machine.Runtime.init(std.testing.allocator);
            defer runtime.deinit();
            lowered_machine.beginExecution(&runtime) catch unreachable;
            defer lowered_machine.endExecution(&runtime);

            std.testing.expectEqual(@as(?*Frame, null), checkpoint()) catch unreachable;
            var probe = Probe{ .counter = &state.second_cleanup_calls };
            push(&probe.frame);
            std.testing.expectEqual(@as(?*Frame, &probe.frame), checkpoint()) catch unreachable;
            unwindTo(null) catch unreachable;
            std.testing.expectEqual(@as(usize, 0), state.first_cleanup_calls) catch unreachable;
            std.testing.expectEqual(@as(usize, 1), state.second_cleanup_calls) catch unreachable;
            state.stage.store(2, .release);
        }
    }.run, .{&shared});

    first.join();
    second.join();
}

test "compat cleanup helpers follow the innermost runtime on the same thread" {
    const Probe = struct {
        frame: Frame = .{ .cleanupFn = cleanup },
        counter: *usize,

        fn cleanup(raw: *Frame) anyerror!void {
            const self: *@This() = @fieldParentPtr("frame", raw);
            self.counter.* += 1;
        }
    };

    var outer_runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer outer_runtime.deinit();
    var inner_runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer inner_runtime.deinit();

    var outer_cleanup_calls: usize = 0;
    var inner_cleanup_calls: usize = 0;

    try lowered_machine.beginExecution(&outer_runtime);
    defer lowered_machine.endExecution(&outer_runtime);

    var outer_probe = Probe{ .counter = &outer_cleanup_calls };
    push(&outer_probe.frame);
    try std.testing.expectEqual(@as(?*Frame, &outer_probe.frame), checkpoint());

    try lowered_machine.beginExecution(&inner_runtime);
    try std.testing.expectEqual(@as(?*Frame, null), checkpoint());

    var inner_probe = Probe{ .counter = &inner_cleanup_calls };
    push(&inner_probe.frame);
    try std.testing.expectEqual(@as(?*Frame, &inner_probe.frame), checkpoint());
    try unwindTo(null);
    try std.testing.expectEqual(@as(usize, 1), inner_cleanup_calls);

    lowered_machine.endExecution(&inner_runtime);
    try std.testing.expectEqual(@as(?*Frame, &outer_probe.frame), checkpoint());

    try unwindTo(null);
    try std.testing.expectEqual(@as(usize, 1), outer_cleanup_calls);
}
