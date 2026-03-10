const kernel = @import("raw_kernel.zig");
const std = @import("std");
const ControlError = kernel.ControlError;
const Error = kernel.Error;
const ErrorSetOf = kernel.ErrorSetOf;
const RequestOf = kernel.RequestOf;
const ResetError = kernel.ResetError;
const ResetFrame = kernel.ResetFrame;
const ResumeOf = kernel.ResumeOf;
const Runtime = kernel.Runtime;
const SuspensionRecord = kernel.SuspensionRecord;
const TagOf = kernel.TagOf;
const AnswerOf = kernel.AnswerOf;
const promptToken = kernel.promptToken;
const resumeIsVoid = kernel.resumeIsVoid;
const supportsDiscontinue = kernel.supportsDiscontinue;
const suspensionCacheKey = kernel.suspensionCacheKey;
const shift_swap_context = kernel.shift_swap_context;
const testingHasCachedSuspensions = kernel.testingHasCachedSuspensions;

/// Result of driving a delimiter until completion, pending ownership, or cancellation.
pub fn Outcome(comptime Spec: type) type {
    return union(enum) {
        cancelled: void,
        complete: AnswerOf(Spec),
        pending: Pending(Spec),
    };
}

/// Explicit escaped owner for one-shot delayed resolution.
pub fn EscapedOwner(comptime Spec: type) type {
    const Record = SuspensionRecord(Spec);
    return if (comptime supportsDiscontinue(ErrorSetOf(Spec))) blk: {
        break :blk if (comptime resumeIsVoid(Spec)) blk_inner: {
            break :blk_inner struct {
                const Self = @This();

                request: RequestOf(Spec),
                record: ?*Record,
                generation: usize,

                fn prepare(self: *Self) Error!*Record {
                    const record = self.record orelse return error.AlreadyResolved;
                    try record.runtime.ensureThread();
                    if (record.generation != self.generation) return error.OwnerAliased;
                    if (record.owner_cookie == 0) {
                        record.owner_cookie = @intFromPtr(self);
                    } else if (record.owner_cookie != @intFromPtr(self)) {
                        return error.OwnerAliased;
                    }
                    if (record.resolution != .pending) return error.AlreadyResolved;
                    self.record = null;
                    return record;
                }

                /// Continue the escaped owner when the suspended site expects no payload.
                pub inline fn proceed(self: *Self) ResetError(ErrorSetOf(Spec))!Outcome(Spec) {
                    const record = try self.prepare();
                    record.resolution = .resumed;
                    record.resume_value = {};
                    record.runtime.active_suspension_count -= 1;
                    defer {
                        record.owner_cookie = 0;
                        record.resume_value = null;
                        record.discontinue_error = null;
                        record.generation += 1;
                        record.runtime.pushCachedSuspension(&record.cached);
                    }
                    return try driveDelimiter(Spec, record.target_frame);
                }

                /// Inject a user-owned `err` into the escaped owner.
                pub inline fn discontinue(self: *Self, err: ErrorSetOf(Spec)) ResetError(ErrorSetOf(Spec))!Outcome(Spec) {
                    const record = try self.prepare();
                    record.resolution = .discontinued;
                    record.discontinue_error = err;
                    record.runtime.active_suspension_count -= 1;
                    defer {
                        record.owner_cookie = 0;
                        record.resume_value = null;
                        record.discontinue_error = null;
                        record.generation += 1;
                        record.runtime.pushCachedSuspension(&record.cached);
                    }
                    return try driveDelimiter(Spec, record.target_frame);
                }

                /// Issue library-owned terminal cancellation for the escaped owner.
                pub inline fn cancel(self: *Self) ResetError(ErrorSetOf(Spec))!Outcome(Spec) {
                    const record = try self.prepare();
                    record.resolution = .cancelled;
                    record.target_frame.cancellation_required = true;
                    record.runtime.active_suspension_count -= 1;
                    defer {
                        record.owner_cookie = 0;
                        record.resume_value = null;
                        record.discontinue_error = null;
                        record.generation += 1;
                        record.runtime.pushCachedSuspension(&record.cached);
                    }
                    return try driveDelimiter(Spec, record.target_frame);
                }

                /// Auto-cancel unresolved escaped owners and ignore the terminal result.
                pub fn deinit(self: *Self) void {
                    self.deinitChecked() catch |err| switch (err) {
                        error.AlreadyResolved => return,
                        error.CrossThread, error.CancellationRecovered => unreachable,
                        else => unreachable,
                    };
                }

                /// Checked auto-cancel for unresolved escaped owners.
                pub fn deinitChecked(self: *Self) ResetError(ErrorSetOf(Spec))!void {
                    if (self.record == null) return error.AlreadyResolved;
                    const outcome = try self.cancel();
                    switch (outcome) {
                        .cancelled => return,
                        .complete, .pending => return error.CancellationRecovered,
                    }
                }
            };
        } else blk_inner: {
            break :blk_inner struct {
                const Self = @This();

                request: RequestOf(Spec),
                record: ?*Record,
                generation: usize,

                fn prepare(self: *Self) Error!*Record {
                    const record = self.record orelse return error.AlreadyResolved;
                    try record.runtime.ensureThread();
                    if (record.generation != self.generation) return error.OwnerAliased;
                    if (record.owner_cookie == 0) {
                        record.owner_cookie = @intFromPtr(self);
                    } else if (record.owner_cookie != @intFromPtr(self)) {
                        return error.OwnerAliased;
                    }
                    if (record.resolution != .pending) return error.AlreadyResolved;
                    self.record = null;
                    return record;
                }

                /// Resume the escaped owner with `value`.
                pub inline fn resumeWith(self: *Self, value: ResumeOf(Spec)) ResetError(ErrorSetOf(Spec))!Outcome(Spec) {
                    const record = try self.prepare();
                    record.resolution = .resumed;
                    record.resume_value = value;
                    record.runtime.active_suspension_count -= 1;
                    defer {
                        record.owner_cookie = 0;
                        record.resume_value = null;
                        record.discontinue_error = null;
                        record.generation += 1;
                        record.runtime.pushCachedSuspension(&record.cached);
                    }
                    return try driveDelimiter(Spec, record.target_frame);
                }

                /// Inject a user-owned `err` into the escaped owner.
                pub inline fn discontinue(self: *Self, err: ErrorSetOf(Spec)) ResetError(ErrorSetOf(Spec))!Outcome(Spec) {
                    const record = try self.prepare();
                    record.resolution = .discontinued;
                    record.discontinue_error = err;
                    record.runtime.active_suspension_count -= 1;
                    defer {
                        record.owner_cookie = 0;
                        record.resume_value = null;
                        record.discontinue_error = null;
                        record.generation += 1;
                        record.runtime.pushCachedSuspension(&record.cached);
                    }
                    return try driveDelimiter(Spec, record.target_frame);
                }

                /// Issue library-owned terminal cancellation for the escaped owner.
                pub inline fn cancel(self: *Self) ResetError(ErrorSetOf(Spec))!Outcome(Spec) {
                    const record = try self.prepare();
                    record.resolution = .cancelled;
                    record.target_frame.cancellation_required = true;
                    record.runtime.active_suspension_count -= 1;
                    defer {
                        record.owner_cookie = 0;
                        record.resume_value = null;
                        record.discontinue_error = null;
                        record.generation += 1;
                        record.runtime.pushCachedSuspension(&record.cached);
                    }
                    return try driveDelimiter(Spec, record.target_frame);
                }

                /// Auto-cancel unresolved escaped owners and ignore the terminal result.
                pub fn deinit(self: *Self) void {
                    self.deinitChecked() catch |err| switch (err) {
                        error.AlreadyResolved => return,
                        error.CrossThread, error.CancellationRecovered => unreachable,
                        else => unreachable,
                    };
                }

                /// Checked auto-cancel for unresolved escaped owners.
                pub fn deinitChecked(self: *Self) ResetError(ErrorSetOf(Spec))!void {
                    if (self.record == null) return error.AlreadyResolved;
                    const outcome = try self.cancel();
                    switch (outcome) {
                        .cancelled => return,
                        .complete, .pending => return error.CancellationRecovered,
                    }
                }
            };
        };
    } else blk: {
        break :blk if (comptime resumeIsVoid(Spec)) blk_inner: {
            break :blk_inner struct {
                const Self = @This();

                request: RequestOf(Spec),
                record: ?*Record,
                generation: usize,

                fn prepare(self: *Self) Error!*Record {
                    const record = self.record orelse return error.AlreadyResolved;
                    try record.runtime.ensureThread();
                    if (record.generation != self.generation) return error.OwnerAliased;
                    if (record.owner_cookie == 0) {
                        record.owner_cookie = @intFromPtr(self);
                    } else if (record.owner_cookie != @intFromPtr(self)) {
                        return error.OwnerAliased;
                    }
                    if (record.resolution != .pending) return error.AlreadyResolved;
                    self.record = null;
                    return record;
                }

                /// Continue the escaped owner when the suspended site expects no payload.
                pub inline fn proceed(self: *Self) ResetError(ErrorSetOf(Spec))!Outcome(Spec) {
                    const record = try self.prepare();
                    record.resolution = .resumed;
                    record.resume_value = {};
                    record.runtime.active_suspension_count -= 1;
                    defer {
                        record.owner_cookie = 0;
                        record.resume_value = null;
                        record.discontinue_error = null;
                        record.generation += 1;
                        record.runtime.pushCachedSuspension(&record.cached);
                    }
                    return try driveDelimiter(Spec, record.target_frame);
                }

                /// Issue library-owned terminal cancellation for the escaped owner.
                pub inline fn cancel(self: *Self) ResetError(ErrorSetOf(Spec))!Outcome(Spec) {
                    const record = try self.prepare();
                    record.resolution = .cancelled;
                    record.target_frame.cancellation_required = true;
                    record.runtime.active_suspension_count -= 1;
                    defer {
                        record.owner_cookie = 0;
                        record.resume_value = null;
                        record.discontinue_error = null;
                        record.generation += 1;
                        record.runtime.pushCachedSuspension(&record.cached);
                    }
                    return try driveDelimiter(Spec, record.target_frame);
                }

                /// Auto-cancel unresolved escaped owners and ignore the terminal result.
                pub fn deinit(self: *Self) void {
                    self.deinitChecked() catch |err| switch (err) {
                        error.AlreadyResolved => return,
                        error.CrossThread, error.CancellationRecovered => unreachable,
                        else => unreachable,
                    };
                }

                /// Checked auto-cancel for unresolved escaped owners.
                pub fn deinitChecked(self: *Self) ResetError(ErrorSetOf(Spec))!void {
                    if (self.record == null) return error.AlreadyResolved;
                    const outcome = try self.cancel();
                    switch (outcome) {
                        .cancelled => return,
                        .complete, .pending => return error.CancellationRecovered,
                    }
                }
            };
        } else blk_inner: {
            break :blk_inner struct {
                const Self = @This();

                request: RequestOf(Spec),
                record: ?*Record,
                generation: usize,

                fn prepare(self: *Self) Error!*Record {
                    const record = self.record orelse return error.AlreadyResolved;
                    try record.runtime.ensureThread();
                    if (record.generation != self.generation) return error.OwnerAliased;
                    if (record.owner_cookie == 0) {
                        record.owner_cookie = @intFromPtr(self);
                    } else if (record.owner_cookie != @intFromPtr(self)) {
                        return error.OwnerAliased;
                    }
                    if (record.resolution != .pending) return error.AlreadyResolved;
                    self.record = null;
                    return record;
                }

                /// Resume the escaped owner with `value`.
                pub inline fn resumeWith(self: *Self, value: ResumeOf(Spec)) ResetError(ErrorSetOf(Spec))!Outcome(Spec) {
                    const record = try self.prepare();
                    record.resolution = .resumed;
                    record.resume_value = value;
                    record.runtime.active_suspension_count -= 1;
                    defer {
                        record.owner_cookie = 0;
                        record.resume_value = null;
                        record.discontinue_error = null;
                        record.generation += 1;
                        record.runtime.pushCachedSuspension(&record.cached);
                    }
                    return try driveDelimiter(Spec, record.target_frame);
                }

                /// Issue library-owned terminal cancellation for the escaped owner.
                pub inline fn cancel(self: *Self) ResetError(ErrorSetOf(Spec))!Outcome(Spec) {
                    const record = try self.prepare();
                    record.resolution = .cancelled;
                    record.target_frame.cancellation_required = true;
                    record.runtime.active_suspension_count -= 1;
                    defer {
                        record.owner_cookie = 0;
                        record.resume_value = null;
                        record.discontinue_error = null;
                        record.generation += 1;
                        record.runtime.pushCachedSuspension(&record.cached);
                    }
                    return try driveDelimiter(Spec, record.target_frame);
                }

                /// Auto-cancel unresolved escaped owners and ignore the terminal result.
                pub fn deinit(self: *Self) void {
                    self.deinitChecked() catch |err| switch (err) {
                        error.AlreadyResolved => return,
                        error.CrossThread, error.CancellationRecovered => unreachable,
                        else => unreachable,
                    };
                }

                /// Checked auto-cancel for unresolved escaped owners.
                pub fn deinitChecked(self: *Self) ResetError(ErrorSetOf(Spec))!void {
                    if (self.record == null) return error.AlreadyResolved;
                    const outcome = try self.cancel();
                    switch (outcome) {
                        .cancelled => return,
                        .complete, .pending => return error.CancellationRecovered,
                    }
                }
            };
        };
    };
}

/// Primary one-shot pending owner used by the direct-style loop.
pub fn Pending(comptime Spec: type) type {
    const Escaped = EscapedOwner(Spec);
    return if (comptime supportsDiscontinue(ErrorSetOf(Spec))) blk: {
        break :blk if (comptime resumeIsVoid(Spec)) blk_inner: {
            break :blk_inner struct {
                const Self = @This();

                escaped: Escaped,

                /// Read the request carried by the pending owner.
                pub inline fn request(self: *const Self) RequestOf(Spec) {
                    return self.escaped.request;
                }

                /// Promote the pending owner into an explicit escaped owner.
                pub inline fn escape(self: *Self) Error!Escaped {
                    if (self.escaped.record == null) return error.AlreadyResolved;
                    const escaped = self.escaped;
                    self.escaped.record = null;
                    return escaped;
                }

                /// Continue the pending owner when the suspended site expects no payload.
                pub inline fn proceed(self: *Self) ResetError(ErrorSetOf(Spec))!Outcome(Spec) {
                    return self.escaped.proceed();
                }

                /// Inject a user-owned `err` through the pending owner.
                pub inline fn discontinue(self: *Self, err: ErrorSetOf(Spec)) ResetError(ErrorSetOf(Spec))!Outcome(Spec) {
                    return self.escaped.discontinue(err);
                }

                /// Issue library-owned terminal cancellation for the pending owner.
                pub inline fn cancel(self: *Self) ResetError(ErrorSetOf(Spec))!Outcome(Spec) {
                    return self.escaped.cancel();
                }
            };
        } else blk_inner: {
            break :blk_inner struct {
                const Self = @This();

                escaped: Escaped,

                /// Read the request carried by the pending owner.
                pub inline fn request(self: *const Self) RequestOf(Spec) {
                    return self.escaped.request;
                }

                /// Promote the pending owner into an explicit escaped owner.
                pub inline fn escape(self: *Self) Error!Escaped {
                    if (self.escaped.record == null) return error.AlreadyResolved;
                    const escaped = self.escaped;
                    self.escaped.record = null;
                    return escaped;
                }

                /// Resolve the pending owner with `value`.
                pub inline fn resumeWith(self: *Self, value: ResumeOf(Spec)) ResetError(ErrorSetOf(Spec))!Outcome(Spec) {
                    return self.escaped.resumeWith(value);
                }

                /// Inject a user-owned `err` through the pending owner.
                pub inline fn discontinue(self: *Self, err: ErrorSetOf(Spec)) ResetError(ErrorSetOf(Spec))!Outcome(Spec) {
                    return self.escaped.discontinue(err);
                }

                /// Issue library-owned terminal cancellation for the pending owner.
                pub inline fn cancel(self: *Self) ResetError(ErrorSetOf(Spec))!Outcome(Spec) {
                    return self.escaped.cancel();
                }
            };
        };
    } else blk: {
        break :blk if (comptime resumeIsVoid(Spec)) blk_inner: {
            break :blk_inner struct {
                const Self = @This();

                escaped: Escaped,

                /// Read the request carried by the pending owner.
                pub inline fn request(self: *const Self) RequestOf(Spec) {
                    return self.escaped.request;
                }

                /// Promote the pending owner into an explicit escaped owner.
                pub inline fn escape(self: *Self) Error!Escaped {
                    if (self.escaped.record == null) return error.AlreadyResolved;
                    const escaped = self.escaped;
                    self.escaped.record = null;
                    return escaped;
                }

                /// Continue the pending owner when the suspended site expects no payload.
                pub inline fn proceed(self: *Self) ResetError(ErrorSetOf(Spec))!Outcome(Spec) {
                    return self.escaped.proceed();
                }

                /// Issue library-owned terminal cancellation for the pending owner.
                pub inline fn cancel(self: *Self) ResetError(ErrorSetOf(Spec))!Outcome(Spec) {
                    return self.escaped.cancel();
                }
            };
        } else blk_inner: {
            break :blk_inner struct {
                const Self = @This();

                escaped: Escaped,

                /// Read the request carried by the pending owner.
                pub inline fn request(self: *const Self) RequestOf(Spec) {
                    return self.escaped.request;
                }

                /// Promote the pending owner into an explicit escaped owner.
                pub inline fn escape(self: *Self) Error!Escaped {
                    if (self.escaped.record == null) return error.AlreadyResolved;
                    const escaped = self.escaped;
                    self.escaped.record = null;
                    return escaped;
                }

                /// Resolve the pending owner with `value`.
                pub inline fn resumeWith(self: *Self, value: ResumeOf(Spec)) ResetError(ErrorSetOf(Spec))!Outcome(Spec) {
                    return self.escaped.resumeWith(value);
                }

                /// Issue library-owned terminal cancellation for the pending owner.
                pub inline fn cancel(self: *Self) ResetError(ErrorSetOf(Spec))!Outcome(Spec) {
                    return self.escaped.cancel();
                }
            };
        };
    };
}

/// Drive one delimiter frame until it completes, fails, or yields a pending edge.
fn driveDelimiter(comptime Spec: type, frame: *ResetFrame(TagOf(Spec), AnswerOf(Spec), ErrorSetOf(Spec))) ResetError(ErrorSetOf(Spec))!Outcome(Spec) {
    const runtime = frame.base.runtime;
    try runtime.ensureThread();
    runtime.active_reset_count += 1;
    defer runtime.active_reset_count -= 1;
    const previous_runtime = kernel.tls_runtime;
    const previous_fiber = kernel.tls_current_fiber;
    defer {
        kernel.tls_runtime = previous_runtime;
        kernel.tls_current_fiber = previous_fiber;
    }

    while (true) {
        kernel.tls_runtime = runtime;
        kernel.tls_current_fiber = &frame.base;
        shift_swap_context(frame.base.parent_context, &frame.base.context);
        switch (frame.base.machine_state) {
            .done => {
                const answer = switch (frame.result) {
                    .answer => |value| value,
                    else => unreachable,
                };
                frame.destroy();
                return .{ .complete = answer };
            },
            .failed => {
                const err = switch (frame.result) {
                    .err => |value| value,
                    else => unreachable,
                };
                frame.destroy();
                if (err == error.Cancelled) return .{ .cancelled = {} };
                return err;
            },
            .suspended => switch (frame.base.machine_signal) {
                .suspension => |base| {
                    if (base.target_fiber != &frame.base) {
                        const active_parent = kernel.tls_current_fiber.?;
                        active_parent.machine_state = .suspended;
                        active_parent.machine_signal = .{ .suspension = base };
                        kernel.tls_current_fiber = active_parent.parent_fiber;
                        shift_swap_context(&active_parent.context, active_parent.parent_context);
                        continue;
                    }
                    const record: *SuspensionRecord(Spec) = @fieldParentPtr("base", base);
                    return .{
                        .pending = .{
                            .escaped = .{
                                .request = record.request,
                                .record = record,
                                .generation = record.generation,
                            },
                        },
                    };
                },
                else => unreachable,
            },
            else => unreachable,
        }
    }
}

/// Run `body` under a fresh delimiter tagged by `Tag`.
pub fn reset(
    comptime Spec: type,
    runtime: *Runtime,
    body: *const fn () ResetError(ErrorSetOf(Spec))!AnswerOf(Spec),
) ResetError(ErrorSetOf(Spec))!Outcome(Spec) {
    try runtime.ensureThread();
    const frame = try ResetFrame(TagOf(Spec), AnswerOf(Spec), ErrorSetOf(Spec)).create(runtime, body);
    return try driveDelimiter(Spec, frame);
}

/// Capture the nearest active delimiter tagged by `Tag`.
pub fn shift(
    comptime Spec: type,
    request: RequestOf(Spec),
) ControlError(ErrorSetOf(Spec))!ResumeOf(Spec) {
    const runtime = kernel.tls_runtime orelse return error.MissingPrompt;
    try runtime.ensureThread();
    if (runtime.no_shift_depth != 0) return error.ShiftForbidden;

    const current_fiber = kernel.tls_current_fiber orelse return error.MissingPrompt;
    const wanted_prompt = promptToken(TagOf(Spec));
    var target_fiber = current_fiber;
    while (target_fiber.prompt_token != wanted_prompt) {
        target_fiber = target_fiber.parent_fiber orelse return error.MissingPrompt;
    }

    const frame: *ResetFrame(TagOf(Spec), AnswerOf(Spec), ErrorSetOf(Spec)) = @fieldParentPtr("base", target_fiber);
    if (frame.cancellation_required) return error.CancellationRecovered;
    const record, const generation = blk: {
        if (runtime.popCachedSuspension(SuspensionRecord(Spec), suspensionCacheKey(Spec))) |cached| {
            break :blk .{ cached, cached.generation };
        }
        const fresh = runtime.allocator.create(SuspensionRecord(Spec)) catch {
            return error.OutOfMemory;
        };
        break :blk .{ fresh, 1 };
    };
    record.* = .{
        .base = .{ .target_fiber = target_fiber },
        .cached = .{
            .key = suspensionCacheKey(Spec),
            .deinitFn = SuspensionRecord(Spec).deinitCached,
        },
        .runtime = runtime,
        .target_frame = frame,
        .request = request,
        .generation = generation,
    };
    runtime.active_suspension_count += 1;
    current_fiber.machine_state = .suspended;
    current_fiber.machine_signal = .{ .suspension = &record.base };
    kernel.tls_current_fiber = current_fiber.parent_fiber;
    shift_swap_context(&current_fiber.context, current_fiber.parent_context);
    switch (record.resolution) {
        .resumed => return record.resume_value.?,
        .discontinued => return record.discontinue_error.?,
        .cancelled => return error.Cancelled,
        .pending => unreachable,
    }
}

test "pending records are recycled after resolution" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const demo_spec = struct {
        /// Prompt tag.
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
        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            const resumed = try shift(demo_spec, 41);
            return resumed + 1;
        }
    };

    var first_outcome = try reset(demo_spec, &runtime, demo.body);
    const first_record = switch (first_outcome) {
        .complete, .cancelled => unreachable,
        .pending => |*pending| blk: {
            const record = pending.escaped.record.?;
            first_outcome = try pending.resumeWith(41);
            break :blk record;
        },
    };
    switch (first_outcome) {
        .complete => |answer| try std.testing.expectEqual(@as(usize, 42), answer),
        .pending, .cancelled => unreachable,
    }
    try std.testing.expect(testingHasCachedSuspensions(&runtime));

    var second_outcome = try reset(demo_spec, &runtime, demo.body);
    switch (second_outcome) {
        .complete, .cancelled => unreachable,
        .pending => |*pending| {
            try std.testing.expectEqual(first_record, pending.escaped.record.?);
            second_outcome = try pending.resumeWith(41);
        },
    }
    switch (second_outcome) {
        .complete => |answer| try std.testing.expectEqual(@as(usize, 42), answer),
        .pending, .cancelled => unreachable,
    }
}

test "no-capture reset returns complete outcome" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const demo_spec = struct {
        /// Prompt tag.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = void;
        /// Resume value type.
        pub const Resume = void;
        /// Final answer type.
        pub const Answer = usize;
        /// User error surface.
        pub const ErrorSet = error{};
    };

    const outcome = try reset(demo_spec, &runtime, struct {
        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            return 7;
        }
    }.body);

    switch (outcome) {
        .complete => |answer| try std.testing.expectEqual(@as(usize, 7), answer),
        .pending, .cancelled => unreachable,
    }
}

test "pending owner resume returns the next outcome" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const demo_spec = struct {
        /// Prompt tag.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = i32;
        /// Resume value type.
        pub const Resume = i32;
        /// Final answer type.
        pub const Answer = i32;
        /// User error surface.
        pub const ErrorSet = error{};
    };

    const demo = struct {
        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            const current = try shift(demo_spec, 41);
            return current + 1;
        }
    };

    var outcome = try reset(demo_spec, &runtime, demo.body);
    switch (outcome) {
        .complete, .cancelled => unreachable,
        .pending => |*pending| {
            try std.testing.expectEqual(@as(i32, 41), pending.request());
            outcome = try pending.resumeWith(41);
        },
    }
    switch (outcome) {
        .complete => |answer| try std.testing.expectEqual(@as(i32, 42), answer),
        .pending, .cancelled => unreachable,
    }
}

test "pending owner discontinue injects the supplied user error" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const demo_spec = struct {
        /// Prompt tag.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = void;
        /// Resume value type.
        pub const Resume = void;
        /// Final answer type.
        pub const Answer = usize;
        /// User error surface.
        pub const ErrorSet = error{Stop};
    };

    const demo = struct {
        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            _ = try shift(demo_spec, {});
            return 99;
        }
    };

    const outcome = try reset(demo_spec, &runtime, demo.body);
    switch (outcome) {
        .complete, .cancelled => unreachable,
        .pending => |pending| {
            var owned = pending;
            try std.testing.expectError(error.Stop, owned.discontinue(error.Stop));
        },
    }
}

test "user discontinue can be caught and continue into another pending owner" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const demo_spec = struct {
        /// Prompt tag.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = []const u8;
        /// Resume value type.
        pub const Resume = void;
        /// Final answer type.
        pub const Answer = usize;
        /// User error surface.
        pub const ErrorSet = error{Stop};
    };

    const demo = struct {
        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            _ = shift(demo_spec, "first") catch |err| switch (err) {
                error.Stop => {},
                else => return err,
            };
            _ = try shift(demo_spec, "after-stop");
            return 7;
        }
    };

    var outcome = try reset(demo_spec, &runtime, demo.body);
    switch (outcome) {
        .complete, .cancelled => unreachable,
        .pending => |*pending| {
            try std.testing.expectEqualStrings("first", pending.request());
            outcome = try pending.discontinue(error.Stop);
        },
    }
    switch (outcome) {
        .complete, .cancelled => unreachable,
        .pending => |*pending| {
            try std.testing.expectEqualStrings("after-stop", pending.request());
            outcome = try pending.proceed();
        },
    }
    switch (outcome) {
        .complete => |answer| try std.testing.expectEqual(@as(usize, 7), answer),
        .pending, .cancelled => unreachable,
    }
}

test "pending owner can escape reset and resume later" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const demo_spec = struct {
        /// Prompt tag.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = []const u8;
        /// Resume value type.
        pub const Resume = usize;
        /// Final answer type.
        pub const Answer = usize;
        /// User error surface.
        pub const ErrorSet = error{};
    };

    const demo = struct {
        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            const resumed = try shift(demo_spec, "later");
            return resumed + 1;
        }
    };

    var saved: ?EscapedOwner(demo_spec) = null;
    var outcome = try reset(demo_spec, &runtime, demo.body);
    switch (outcome) {
        .complete, .cancelled => unreachable,
        .pending => |*pending| {
            try std.testing.expectEqualStrings("later", pending.request());
            saved = try pending.escape();
        },
    }
    outcome = try saved.?.resumeWith(41);
    switch (outcome) {
        .complete => |answer| try std.testing.expectEqual(@as(usize, 42), answer),
        .pending, .cancelled => unreachable,
    }
}

test "payloadless escaped owner can proceed later" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const demo_spec = struct {
        /// Prompt tag.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = []const u8;
        /// Resume value type.
        pub const Resume = void;
        /// Final answer type.
        pub const Answer = usize;
        /// User error surface.
        pub const ErrorSet = error{};
    };

    const demo = struct {
        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            _ = try shift(demo_spec, "later");
            return 42;
        }
    };

    var saved: ?EscapedOwner(demo_spec) = null;
    var outcome = try reset(demo_spec, &runtime, demo.body);
    switch (outcome) {
        .complete, .cancelled => unreachable,
        .pending => |*pending| {
            try std.testing.expectEqualStrings("later", pending.request());
            saved = try pending.escape();
        },
    }
    outcome = try saved.?.proceed();
    switch (outcome) {
        .complete => |answer| try std.testing.expectEqual(@as(usize, 42), answer),
        .pending, .cancelled => unreachable,
    }
}

test "escaping consumes the pending owner and preserves delayed resolution" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const demo_spec = struct {
        /// Prompt tag.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = []const u8;
        /// Resume value type.
        pub const Resume = usize;
        /// Final answer type.
        pub const Answer = usize;
        /// User error surface.
        pub const ErrorSet = error{};
    };

    const demo = struct {
        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            const resumed = try shift(demo_spec, "later");
            return resumed + 1;
        }
    };

    var outcome = try reset(demo_spec, &runtime, demo.body);
    switch (outcome) {
        .complete, .cancelled => unreachable,
        .pending => |pending| {
            var owned = pending;
            var escaped = try owned.escape();
            try std.testing.expectEqualStrings("later", escaped.request);
            try std.testing.expectError(error.AlreadyResolved, owned.resumeWith(41));
            outcome = try escaped.resumeWith(41);
        },
    }
    switch (outcome) {
        .complete => |answer| try std.testing.expectEqual(@as(usize, 42), answer),
        .pending, .cancelled => unreachable,
    }
}

test "copied escaped-owner alias is rejected" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const demo_spec = struct {
        /// Prompt tag.
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
        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            const resumed = try shift(demo_spec, 41);
            return resumed + 1;
        }
    };

    var outcome = try reset(demo_spec, &runtime, demo.body);
    switch (outcome) {
        .complete, .cancelled => unreachable,
        .pending => |*pending| {
            var owner = try pending.escape();
            var alias = owner;
            outcome = try owner.resumeWith(41);
            try std.testing.expectError(error.OwnerAliased, alias.resumeWith(41));
        },
    }
    switch (outcome) {
        .complete => |answer| try std.testing.expectEqual(@as(usize, 42), answer),
        .pending, .cancelled => unreachable,
    }
}

test "pending owner cancel returns cancelled outcome" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const demo_spec = struct {
        /// Prompt tag.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = i32;
        /// Resume value type.
        pub const Resume = i32;
        /// Final answer type.
        pub const Answer = i32;
        /// User error surface.
        pub const ErrorSet = error{};
    };

    const demo = struct {
        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            const current = try shift(demo_spec, 41);
            return current + 1;
        }
    };

    const outcome = try reset(demo_spec, &runtime, demo.body);
    switch (outcome) {
        .complete, .cancelled => unreachable,
        .pending => |pending| {
            var owned = pending;
            switch (try owned.cancel()) {
                .cancelled => {},
                .complete, .pending => unreachable,
            }
        },
    }
}

test "escaped owner deinit auto-cancels unresolved token" {
    var runtime = Runtime.init(std.testing.allocator, .{});

    const demo_spec = struct {
        /// Prompt tag.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = i32;
        /// Resume value type.
        pub const Resume = i32;
        /// Final answer type.
        pub const Answer = i32;
        /// User error surface.
        pub const ErrorSet = error{};
    };

    const demo = struct {
        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            const current = try shift(demo_spec, 41);
            return current + 1;
        }
    };

    const outcome = try reset(demo_spec, &runtime, demo.body);
    switch (outcome) {
        .complete, .cancelled => unreachable,
        .pending => |pending| {
            var owned = pending;
            var escaped = try owned.escape();
            escaped.deinit();
        },
    }
    try runtime.deinitChecked();
}

test "cancellation cannot recover into another pending owner" {
    var runtime = Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();

    const demo_spec = struct {
        /// Prompt tag.
        pub const tag = struct {};
        /// Outbound request type.
        pub const Request = []const u8;
        /// Resume value type.
        pub const Resume = void;
        /// Final answer type.
        pub const Answer = usize;
        /// User error surface.
        pub const ErrorSet = error{};
    };

    const demo = struct {
        fn body() ResetError(demo_spec.ErrorSet)!demo_spec.Answer {
            _ = shift(demo_spec, "first") catch |err| switch (err) {
                error.Cancelled => {},
                else => return err,
            };
            _ = try shift(demo_spec, "should-not-happen");
            return 9;
        }
    };

    var outcome = try reset(demo_spec, &runtime, demo.body);
    switch (outcome) {
        .complete, .cancelled => unreachable,
        .pending => |*pending| try std.testing.expectError(error.CancellationRecovered, pending.cancel()),
    }
}
