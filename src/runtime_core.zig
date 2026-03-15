const std = @import("std");

/// Runtime errors surfaced by the canonical non-stackful runtime core.
pub const Error = error{
    CrossThread,
    FrontendSuspend,
    MissingPrompt,
    NonDiagonalComplete,
    ProgramContractViolation,
    RuntimeBusy,
    RuntimeDestroyed,
};

/// Setup failures retained in the canonical reset/control unions for compatibility.
pub const SetupError = error{OutOfMemory} || std.posix.MMapError || std.posix.MProtectError;

/// Runtime-visible error union for user-provided errors.
pub fn ControlError(comptime ErrorSet: type) type {
    return Error || ErrorSet;
}

/// Full reset-path error union including compatibility setup failures.
pub fn ResetError(comptime ErrorSet: type) type {
    return ControlError(ErrorSet) || SetupError;
}

/// Canonical thread-affine runtime for the lowered frontend path.
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

    /// Release runtime resources. The canonical lowered runtime owns no heap state directly.
    pub fn deinit(self: *Runtime) void {
        self.deinitChecked() catch |err| switch (err) {
            error.CrossThread, error.RuntimeBusy => unreachable,
            else => unreachable,
        };
    }

    /// Release runtime resources, returning an error on misuse.
    pub fn deinitChecked(self: *Runtime) Error!void {
        try self.ensureThread();
        if (self.active_reset_count != 0) return error.RuntimeBusy;
        self.state = .destroyed;
    }

    /// Confirm the runtime is live and accessed from the owning thread.
    pub fn ensureThread(self: *Runtime) Error!void {
        if (self.thread_id != std.Thread.getCurrentId()) return error.CrossThread;
        if (self.state == .destroyed) return error.RuntimeDestroyed;
    }
};
