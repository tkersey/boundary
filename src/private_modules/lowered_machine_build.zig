const kernel = @import("internal_kernel");
const portable_core = @import("portable_core");
const std = @import("std");

/// Public runtime misuse and semantic-contract errors surfaced by `ability`.
pub const RuntimeError = error{
    MissingPrompt,
    CrossThread,
    RuntimeBusy,
    RuntimeDestroyed,
    NonDiagonalComplete,
    FrontendSuspend,
    ProgramContractViolation,
};

/// Internal protocol/runtime errors used beneath the public root surface.
pub const ProtocolError = error{
    FrontendSuspend,
    ProgramContractViolation,
};

/// Internal runtime-visible error union used beneath the public root surface.
pub const Error = RuntimeError;

/// Internal runtime-visible error union for user-provided errors.
pub fn InternalControlError(comptime ErrorSet: type) type {
    return Error || ErrorSet;
}

/// Internal reset-time error union for user-provided errors on the lowered runtime path.
pub fn InternalResetError(comptime ErrorSet: type) type {
    return InternalControlError(ErrorSet) || SetupError;
}

/// Runtime-visible error union for user-provided errors.
pub fn ControlError(comptime ErrorSet: type) type {
    return Error || ErrorSet;
}

/// Allocation failure that can still arise on the lowered runtime path.
pub const SetupError = error{OutOfMemory};

/// Reset-time error union for user-provided errors on the lowered runtime path.
pub fn ResetError(comptime ErrorSet: type) type {
    return ControlError(ErrorSet) || SetupError;
}

/// Canonical thread-affine runtime backed by the lowered execution backend.
pub const Runtime = struct {
    allocator: std.mem.Allocator,
    core: portable_core.ExecutionCore,
    thread_id: std.Thread.Id,

    /// Initialize a runtime on the current thread.
    pub fn init(allocator: std.mem.Allocator) Runtime {
        return .{
            .allocator = allocator,
            .core = portable_core.ExecutionCore.init(allocator),
            .thread_id = std.Thread.getCurrentId(),
        };
    }

    /// Release runtime resources.
    pub fn deinit(self: *Runtime) void {
        self.deinitChecked() catch |err| switch (err) {
            error.CrossThread, error.RuntimeBusy => unreachable,
            else => unreachable,
        };
    }

    /// Release runtime resources, returning an error on misuse.
    pub fn deinitChecked(self: *Runtime) RuntimeError!void {
        try self.ensureThread();
        if (self.core.active_reset_count != 0) return error.RuntimeBusy;
        self.core.state = .destroyed;
        self.core.deinit();
        portable_core.compatFrameDeinitIfIdle();
    }

    /// Confirm the runtime is live and accessed from the owning thread.
    pub fn ensureThread(self: *Runtime) RuntimeError!void {
        if (self.thread_id != std.Thread.getCurrentId()) return error.CrossThread;
        if (self.core.state == .destroyed) return error.RuntimeDestroyed;
    }
};

/// Return the allocator owned by the host runtime.
pub fn runtimeAllocator(runtime: *const Runtime) std.mem.Allocator {
    return runtime.core.allocator;
}

const ActiveRuntimeOverflowEntry = struct {
    runtime: *Runtime,
    previous: ?*@This(),
};

threadlocal var active_runtime_stack: [256]?*Runtime = [_]?*Runtime{null} ** 256;
threadlocal var active_runtime_stack_len: usize = 0;
threadlocal var active_runtime_overflow: ?*ActiveRuntimeOverflowEntry = null;

/// Return the currently active runtime on this thread, if one is executing.
pub fn activeRuntime() ?*Runtime {
    if (active_runtime_overflow) |entry| return entry.runtime;
    if (active_runtime_stack_len == 0) return null;
    return active_runtime_stack[active_runtime_stack_len - 1];
}

/// Enter one frontend execution against the host runtime.
pub fn beginExecution(runtime: *Runtime) (RuntimeError || SetupError)!void {
    try runtime.ensureThread();
    if (active_runtime_stack_len < active_runtime_stack.len) {
        active_runtime_stack[active_runtime_stack_len] = runtime;
        active_runtime_stack_len += 1;
    } else {
        // Keep overflow bookkeeping off the runtime allocator so perf probes stay comparable.
        // zlinter-disable-next-line no_hidden_allocations - overflow bookkeeping must stay off the runtime allocator
        const entry = try std.heap.page_allocator.create(ActiveRuntimeOverflowEntry);
        // zlinter-disable-next-line no_hidden_allocations - overflow bookkeeping must unwind through the same non-runtime allocator
        errdefer std.heap.page_allocator.destroy(entry);
        entry.* = .{
            .runtime = runtime,
            .previous = active_runtime_overflow,
        };
        active_runtime_overflow = entry;
    }
    runtime.core.active_reset_count += 1;
}

/// Leave one frontend execution against the host runtime.
pub fn endExecution(runtime: *Runtime) void {
    endExecutionChecked(runtime) catch |err| std.debug.panic("runtime execution teardown misuse: {s}", .{@errorName(err)});
}

/// Leave one frontend execution against the host runtime, returning an error on misuse.
pub fn endExecutionChecked(runtime: *Runtime) RuntimeError!void {
    try runtime.ensureThread();
    if (runtime.core.active_reset_count == 0) return error.RuntimeBusy;
    if (active_runtime_overflow) |entry| {
        if (entry.runtime != runtime) return error.RuntimeBusy;
        active_runtime_overflow = entry.previous;
        // zlinter-disable-next-line no_hidden_allocations - overflow bookkeeping must unwind through the same non-runtime allocator
        std.heap.page_allocator.destroy(entry);
        runtime.core.active_reset_count -= 1;
        return;
    }
    if (active_runtime_stack_len == 0) return error.RuntimeBusy;
    if (active_runtime_stack[active_runtime_stack_len - 1] != runtime) return error.RuntimeBusy;
    active_runtime_stack_len -= 1;
    active_runtime_stack[active_runtime_stack_len] = null;
    runtime.core.active_reset_count -= 1;
}

test "endExecutionChecked rejects mismatched nested runtime shutdown without corrupting active runtime state" {
    var outer_runtime = Runtime.init(std.testing.allocator);
    defer outer_runtime.deinit();
    var inner_runtime = Runtime.init(std.testing.allocator);
    defer inner_runtime.deinit();

    var outer_active = false;
    var inner_active = false;
    defer if (inner_active) endExecution(&inner_runtime);
    defer if (outer_active) endExecution(&outer_runtime);

    try beginExecution(&outer_runtime);
    outer_active = true;
    try beginExecution(&inner_runtime);
    inner_active = true;

    try std.testing.expect(activeRuntime() == &inner_runtime);
    try std.testing.expectError(error.RuntimeBusy, endExecutionChecked(&outer_runtime));
    try std.testing.expect(activeRuntime() == &inner_runtime);

    try endExecutionChecked(&inner_runtime);
    inner_active = false;
    try std.testing.expect(activeRuntime() == &outer_runtime);

    try endExecutionChecked(&outer_runtime);
    outer_active = false;
    try std.testing.expect(activeRuntime() == null);
}

test "beginExecution spills beyond the fast runtime stack without changing nesting semantics" {
    var runtimes: [active_runtime_stack.len + 1]Runtime = undefined;
    for (&runtimes) |*runtime| runtime.* = Runtime.init(std.testing.allocator);
    defer for (&runtimes) |*runtime| runtime.deinit();

    var active_count: usize = 0;
    defer while (active_count > 0) {
        active_count -= 1;
        endExecution(&runtimes[active_count]);
    };

    for (&runtimes) |*runtime| {
        try beginExecution(runtime);
        active_count += 1;
    }

    try std.testing.expect(activeRuntime() == &runtimes[runtimes.len - 1]);
    try std.testing.expectError(error.RuntimeBusy, endExecutionChecked(&runtimes[0]));
    try std.testing.expect(activeRuntime() == &runtimes[runtimes.len - 1]);

    try endExecutionChecked(&runtimes[runtimes.len - 1]);
    active_count -= 1;
    try std.testing.expect(activeRuntime() == &runtimes[runtimes.len - 2]);
}

/// Stable scenario ids re-exported from the canonical scenario registry.
pub const ScenarioId = kernel.ScenarioId;
/// Stable prompt ids re-exported from the canonical scenario registry.
pub const PromptId = kernel.PromptId;
/// Pending continuation kinds re-exported from the canonical scenario registry.
pub const PendingKind = kernel.PendingKind;
/// Typed proof values re-exported from the canonical scenario registry.
pub const Value = kernel.Value;
/// Narrow typed program values used by the explicit canonical program path.
pub const ProgramValue = kernel.ProgramValue;
/// Transcript events re-exported from the canonical scenario registry.
pub const Event = kernel.Event;
/// Checkpoint tags re-exported from the canonical scenario registry.
pub const CheckpointTag = kernel.CheckpointTag;
/// Pending frames re-exported from the canonical scenario registry.
pub const PendingFrame = kernel.PendingFrame;
/// Trace checkpoints re-exported from the canonical scenario registry.
pub const TraceCheckpoint = kernel.TraceCheckpoint;
/// Lowered proof steps re-exported from the canonical scenario registry.
pub const Step = kernel.Step;
/// Full typed execution state for one lowered-machine execution.
pub const MachineState = kernel.State;
/// Pure interpreter state alias for new callers.
pub const InterpreterState = kernel.State;
/// Execute one sequence of lowered machine steps to completion.
pub const runSteps = kernel.runSteps;
/// Return the captured checkpoints for one machine execution.
pub const checkpoints = kernel.checkpoints;
/// Return the transcript-projection events for one machine execution.
pub const events = kernel.events;
/// Render the exact-output transcript for one machine execution.
pub const writeTranscript = kernel.writeTranscript;

/// Execute one explicit typed-value pure program to completion.
pub fn runExplicitPure(
    comptime PromptType: type,
    value: PromptType.InAnswer,
) anyerror!PromptType.OutAnswer {
    if (comptime PromptType.InAnswer == PromptType.OutAnswer) return value;
    return error.NonDiagonalComplete;
}

/// Execute one explicit typed-value transform program to completion.
pub fn runExplicitTransform(
    comptime PromptType: type,
    node: anytype,
) anyerror!PromptType.OutAnswer {
    const resume_value = try node.resumeValueFn(node.handler_ctx);
    const in_answer = try node.continueFn(resume_value);
    return try node.afterResumeFn(node.handler_ctx, in_answer);
}

/// Execute one explicit typed-value choice program to completion.
pub fn runExplicitChoice(
    comptime PromptType: type,
    node: anytype,
) anyerror!PromptType.OutAnswer {
    const decision = try node.decisionFn(node.handler_ctx);
    return switch (decision) {
        .resume_with => |resume_value| blk: {
            const in_answer = try node.continueFn(node.continue_ctx, resume_value);
            break :blk try node.afterResumeFn(node.handler_ctx, in_answer);
        },
        .return_now => |answer| answer,
    };
}

/// Execute one explicit typed-value abortive program to completion.
pub fn runExplicitAbort(
    comptime PromptType: type,
    node: anytype,
) anyerror!PromptType.OutAnswer {
    return try node.directReturnFn(node.handler_ctx);
}
