const raw = @import("raw.zig");

fn supportsDiscontinue(comptime Spec: type) bool {
    return switch (@typeInfo(Spec.ErrorSet)) {
        .error_set => |errors| errors != null and errors.?.len != 0,
        else => true,
    };
}

fn resumeIsVoid(comptime Spec: type) bool {
    return Spec.Resume == void;
}

/// The next action a workflow handler wants the driver to apply.
pub fn Decision(comptime Spec: type) type {
    return if (comptime supportsDiscontinue(Spec)) blk: {
        break :blk if (comptime resumeIsVoid(Spec)) blk_inner: {
            break :blk_inner union(enum) {
                cancel: void,
                discontinue: Spec.ErrorSet,
                proceed: void,
            };
        } else blk_inner: {
            break :blk_inner union(enum) {
                cancel: void,
                discontinue: Spec.ErrorSet,
                resume_value: Spec.Resume,
            };
        };
    } else if (comptime resumeIsVoid(Spec)) blk: {
        break :blk union(enum) {
            cancel: void,
            proceed: void,
        };
    } else blk: {
        break :blk union(enum) {
            cancel: void,
            resume_value: Spec.Resume,
        };
    };
}

/// The terminal states the public workflow driver can return.
pub fn TerminalOutcome(comptime Spec: type) type {
    return union(enum) {
        cancelled: void,
        complete: Spec.Answer,
    };
}

/// Run `body` under `reset` and resolve each yielded pending request through `handle`.
pub inline fn run(
    comptime Spec: type,
    runtime: *raw.Runtime,
    body: *const fn () raw.ResetError(Spec.ErrorSet)!Spec.Answer,
    context: anytype,
    comptime handle: fn (@TypeOf(context), Spec.Request) anyerror!Decision(Spec),
) anyerror!TerminalOutcome(Spec) {
    var outcome = try raw.reset(Spec, runtime, body);
    while (true) {
        switch (outcome) {
            .complete => |answer| return .{ .complete = answer },
            .cancelled => return .{ .cancelled = {} },
            .pending => |*pending| {
                const decision = handle(context, pending.request()) catch |err| {
                    var escaped = pending.escape() catch |escape_err| return escape_err;
                    escaped.deinit();
                    return err;
                };
                outcome = try applyDecision(Spec, pending, decision);
            },
        }
    }
}

inline fn applyDecision(
    comptime Spec: type,
    pending: *raw.Pending(Spec),
    decision: Decision(Spec),
) raw.ResetError(Spec.ErrorSet)!raw.Outcome(Spec) {
    return if (comptime supportsDiscontinue(Spec)) blk: {
        break :blk if (comptime resumeIsVoid(Spec)) blk_inner: {
            break :blk_inner switch (decision) {
                .cancel => try pending.cancel(),
                .discontinue => |err| try pending.discontinue(err),
                .proceed => try pending.proceed(),
            };
        } else switch (decision) {
            .cancel => try pending.cancel(),
            .discontinue => |err| try pending.discontinue(err),
            .resume_value => |value| try pending.resumeWith(value),
        };
    } else if (comptime resumeIsVoid(Spec)) blk: {
        break :blk switch (decision) {
            .cancel => try pending.cancel(),
            .proceed => try pending.proceed(),
        };
    } else blk: {
        break :blk switch (decision) {
            .cancel => try pending.cancel(),
            .resume_value => |value| try pending.resumeWith(value),
        };
    };
}
