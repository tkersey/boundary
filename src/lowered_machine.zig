const interpreter = @import("interpreter");
const std = @import("std");

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
    thread_id: std.Thread.Id,
    state: enum {
        alive,
        destroyed,
    } = .alive,
    active_reset_count: usize = 0,

    /// Initialize a runtime on the current thread.
    pub fn init(allocator: std.mem.Allocator) Runtime {
        return .{
            .allocator = allocator,
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
        if (self.active_reset_count != 0) return error.RuntimeBusy;
        self.state = .destroyed;
    }

    /// Confirm the runtime is live and accessed from the owning thread.
    pub fn ensureThread(self: *Runtime) RuntimeError!void {
        if (self.thread_id != std.Thread.getCurrentId()) return error.CrossThread;
        if (self.state == .destroyed) return error.RuntimeDestroyed;
    }
};

/// Return the allocator owned by the host runtime.
pub fn runtimeAllocator(runtime: *const Runtime) std.mem.Allocator {
    return runtime.allocator;
}

/// Enter one frontend execution against the host runtime.
pub fn beginExecution(runtime: *Runtime) RuntimeError!void {
    try runtime.ensureThread();
    runtime.active_reset_count += 1;
}

/// Leave one frontend execution against the host runtime.
pub fn endExecution(runtime: *Runtime) void {
    runtime.active_reset_count -= 1;
}

/// Stable scenario ids re-exported from the canonical scenario registry.
pub const ScenarioId = interpreter.ScenarioId;
/// Stable prompt ids re-exported from the canonical scenario registry.
pub const PromptId = interpreter.PromptId;
/// Pending continuation kinds re-exported from the canonical scenario registry.
pub const PendingKind = interpreter.PendingKind;
/// Typed proof values re-exported from the canonical scenario registry.
pub const Value = interpreter.Value;
/// Narrow typed program values used by the explicit canonical program path.
pub const ProgramValue = interpreter.ProgramValue;
/// Transcript events re-exported from the canonical scenario registry.
pub const Event = interpreter.Event;
/// Checkpoint tags re-exported from the canonical scenario registry.
pub const CheckpointTag = interpreter.CheckpointTag;
/// Pending frames re-exported from the canonical scenario registry.
pub const PendingFrame = interpreter.PendingFrame;
/// Trace checkpoints re-exported from the canonical scenario registry.
pub const TraceCheckpoint = interpreter.TraceCheckpoint;
/// Lowered proof steps re-exported from the canonical scenario registry.
pub const Step = interpreter.Step;
/// Full typed execution state for one lowered-machine execution.
pub const MachineState = interpreter.MachineState;
/// Pure interpreter state alias for new callers.
pub const InterpreterState = interpreter.State;
/// Execute one sequence of lowered machine steps to completion.
pub const runSteps = interpreter.runSteps;
/// Return the captured checkpoints for one machine execution.
pub const checkpoints = interpreter.checkpoints;
/// Return the transcript-projection events for one machine execution.
pub const events = interpreter.events;
/// Render the exact-output transcript for one machine execution.
pub const writeTranscript = interpreter.writeTranscript;

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
