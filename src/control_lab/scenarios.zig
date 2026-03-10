const registry = @import("control_lab_registry");
const shift = @import("shift");
const std = @import("std");

/// Errors surfaced by control-lab scenario dispatch.
pub const ControlStudioError = error{UnknownWitness};

/// Print the stable witness list for the control studio.
pub fn listWitnesses(writer: anytype) anyerror!void {
    for (registry.witnesses) |witness| {
        try writer.print("{s}\t{s}\t{s}\n", .{
            witness.witness_id,
            registry.surfaceLabel(witness.surface),
            witness.title,
        });
    }
}

/// Run one control-lab witness by id.
pub fn runWitness(writer: anytype, id: []const u8) anyerror!void {
    const witness = registry.findWitness(id) orelse return ControlStudioError.UnknownWitness;
    switch (witness.semantic_role) {
        .pending_loop => try runPendingLoop(writer),
        .terminal_cancel => try runTerminalCancel(writer),
        .driver_discontinue => try runDriverDiscontinue(writer),
        .escape_redelimit => try runEscapeRedelimit(writer),
    }
}

/// Render the ordinary pending-loop witness.
pub fn runPendingLoop(writer: anytype) anyerror!void {
    const generator_spec = struct {
        /// Prompt tag for the generator witness.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = i32;
        /// Resume value type.
        pub const Resume = void;
        /// Final answer type.
        pub const Answer = void;
        /// User error surface.
        pub const ErrorSet = error{};
    };

    const demo = struct {
        var yielded = [_]i32{ 0, 0, 0 };
        var yield_count: usize = 0;

        fn yieldValue(value: i32) shift.ResetError(generator_spec.ErrorSet)!void {
            _ = try shift.shift(generator_spec, value);
        }

        fn body() shift.ResetError(generator_spec.ErrorSet)!generator_spec.Answer {
            yield_count = 0;
            try yieldValue(1);
            try yieldValue(2);
            try yieldValue(3);
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();

    var outcome = try shift.reset(generator_spec, &runtime, demo.body);
    while (true) switch (outcome) {
        .complete => break,
        .cancelled => unreachable,
        .pending => |*pending| {
            demo.yielded[demo.yield_count] = pending.request();
            demo.yield_count += 1;
            outcome = try pending.proceed();
        },
    };

    var i: usize = 0;
    while (i < demo.yield_count) : (i += 1) {
        try writer.print("yield={d}\n", .{demo.yielded[i]});
    }
    try writer.print("done={d}\n", .{demo.yield_count});
}

/// Render the terminal-cancel witness.
pub fn runTerminalCancel(writer: anytype) anyerror!void {
    const state_spec = struct {
        /// Prompt tag for the terminal-cancel witness.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = void;
        /// Resume value type.
        pub const Resume = i32;
        /// Final answer type.
        pub const Answer = i32;
        /// User error surface.
        pub const ErrorSet = error{};
    };

    const demo = struct {
        var resumed: i32 = 0;

        fn body() shift.ResetError(state_spec.ErrorSet)!state_spec.Answer {
            const current = try shift.shift(state_spec, {});
            return current + 1;
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();

    var outcome = try shift.reset(state_spec, &runtime, demo.body);
    while (true) switch (outcome) {
        .complete => unreachable,
        .cancelled => break,
        .pending => |*pending| {
            demo.resumed = 0;
            outcome = try pending.cancel();
        },
    };

    try writer.print("cancelled=yes resumed={d}\n", .{demo.resumed});
}

/// Render the additive-driver discontinue witness.
pub fn runDriverDiscontinue(writer: anytype) anyerror!void {
    const handler_spec = struct {
        /// Prompt tag for the driver discontinue witness.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = union(enum) {
            abort: void,
            emit: []const u8,
        };
        /// Resume value type.
        pub const Resume = void;
        /// Final answer type.
        pub const Answer = []const u8;
        /// User error surface.
        pub const ErrorSet = error{Abort};
    };

    const demo = struct {
        var trace = [_][]const u8{ "", "", "" };
        var trace_count: usize = 0;

        fn emit(message: []const u8) shift.ResetError(handler_spec.ErrorSet)!void {
            _ = try shift.shift(handler_spec, .{ .emit = message });
        }

        fn failWithAbort() shift.ResetError(handler_spec.ErrorSet)!void {
            _ = try shift.shift(handler_spec, .{ .abort = {} });
        }

        fn body() shift.ResetError(handler_spec.ErrorSet)!handler_spec.Answer {
            trace_count = 0;
            try emit("enter");
            try emit("before-abort");
            try failWithAbort();
            try emit("unreachable");
            return "ok";
        }
    };

    const driver = struct {
        fn handle(_: *@This(), request: handler_spec.Request) anyerror!shift.driver.Decision(handler_spec) {
            return switch (request) {
                .emit => |message| blk: {
                    demo.trace[demo.trace_count] = message;
                    demo.trace_count += 1;
                    break :blk .{ .proceed = {} };
                },
                .abort => .{ .discontinue = error.Abort },
            };
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();

    var loop_driver: driver = .{};
    _ = shift.driver.run(handler_spec, &runtime, demo.body, &loop_driver, driver.handle) catch |err| switch (err) {
        error.Abort => {
            try writer.writeAll("aborted=yes trace=[");
            for (demo.trace[0..demo.trace_count], 0..) |entry, index| {
                if (index != 0) try writer.writeAll(", ");
                try writer.print("{s}", .{entry});
            }
            try writer.writeAll("]\n");
            return;
        },
        else => return err,
    };
    unreachable;
}

/// Render the escaped-owner re-delimitation witness.
pub fn runEscapeRedelimit(writer: anytype) anyerror!void {
    const demo_spec = struct {
        /// Prompt tag for the delayed-escape witness.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = usize;
        /// Resume value type.
        pub const Resume = usize;
        /// Final answer type.
        pub const Answer = usize;
        /// User error surface.
        pub const ErrorSet = error{};
    };

    const demo = struct {
        fn body() shift.ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            const first = try shift.shift(demo_spec, 41);
            const second = try shift.shift(demo_spec, first + 1);
            return second + 1;
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();

    var saved: ?shift.EscapedOwner(demo_spec) = null;
    var outcome = try shift.reset(demo_spec, &runtime, demo.body);
    switch (outcome) {
        .complete, .cancelled => unreachable,
        .pending => |*pending| {
            try writer.print("first_request={d}\n", .{pending.request()});
            saved = try pending.escape();
            try writer.writeAll("escaped=yes\n");
        },
    }

    outcome = try saved.?.resumeWith(41);
    switch (outcome) {
        .complete, .cancelled => unreachable,
        .pending => |*pending| {
            try writer.print("second_request={d}\n", .{pending.request()});
            outcome = try pending.resumeWith(pending.request());
        },
    }

    switch (outcome) {
        .complete => |answer| try writer.print("result={d}\n", .{answer}),
        .pending, .cancelled => unreachable,
    }
}
