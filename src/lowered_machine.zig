const kernel = @import("internal_kernel");
const portable_core = @import("portable_core");
const std = @import("std");

const SpinLock = struct {
    state: u8 = 0,

    fn lock(self: *@This()) void {
        while (@cmpxchgWeak(u8, &self.state, 0, 1, .acquire, .monotonic) != null) {
            std.atomic.spinLoopHint();
        }
    }

    fn unlock(self: *@This()) void {
        @atomicStore(u8, &self.state, 0, .release);
    }
};

/// Public runtime misuse and semantic-contract errors surfaced by `shift`.
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

const ActiveRuntimeRegistry = struct {
    const Entry = struct {
        runtime: *Runtime,
        depth: usize,
    };

    lock_state: SpinLock = .{},
    map: std.AutoHashMapUnmanaged(std.Thread.Id, Entry) = .empty,

    fn begin(self: *@This(), runtime: *Runtime) (RuntimeError || SetupError)!void {
        self.lock_state.lock();
        defer self.lock_state.unlock();

        const entry = self.map.getPtr(runtime.thread_id);
        if (entry) |active| {
            if (active.runtime != runtime) return error.RuntimeBusy;
            active.depth += 1;
            return;
        }
        try self.map.put(std.heap.page_allocator, runtime.thread_id, .{ .runtime = runtime, .depth = 1 });
    }

    fn end(self: *@This(), runtime: *Runtime) void {
        self.lock_state.lock();
        defer self.lock_state.unlock();

        const entry = self.map.getPtr(runtime.thread_id).?;
        std.debug.assert(entry.runtime == runtime);
        if (entry.depth == 1) {
            _ = self.map.remove(runtime.thread_id);
            if (self.map.count() == 0) {
                self.map.deinit(std.heap.page_allocator);
                self.map = .empty;
            }
            return;
        }
        entry.depth -= 1;
    }

    fn current(self: *@This(), thread_id: std.Thread.Id) ?*Runtime {
        self.lock_state.lock();
        defer self.lock_state.unlock();
        return if (self.map.get(thread_id)) |entry| entry.runtime else null;
    }
};

var active_runtimes = ActiveRuntimeRegistry{};

/// Return the currently active runtime on this thread, if one is executing.
pub fn activeRuntime() ?*Runtime {
    return active_runtimes.current(std.Thread.getCurrentId());
}

/// Enter one frontend execution against the host runtime.
pub fn beginExecution(runtime: *Runtime) (RuntimeError || SetupError)!void {
    try runtime.ensureThread();
    try active_runtimes.begin(runtime);
    runtime.core.active_reset_count += 1;
}

/// Leave one frontend execution against the host runtime.
pub fn endExecution(runtime: *Runtime) void {
    runtime.core.active_reset_count -= 1;
    active_runtimes.end(runtime);
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
