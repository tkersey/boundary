const std = @import("std");

/// Runtime errors enforced by the raw continuation core.
pub const Error = error{
    AlreadyResolved,
    CrossThread,
    SessionBusy,
    SessionClosed,
    SessionDestroyed,
    SessionOpen,
};

/// Shared one-shot state for a continuation handle.
pub const State = enum {
    discarded,
    fresh,
    resumed,
};

/// Lifetime state of a continuation relative to its owning session.
pub const OwnerState = enum {
    alive,
    session_closed,
    session_destroyed,
};

/// Public close modes for an owned session.
pub const CloseMode = enum {
    cancel,
    graceful,
};

/// Internal/public observable session state.
pub const CloseState = enum {
    cancel,
    graceful,
    open,
};

/// Lightweight diagnostic snapshot for tests and leak triage.
pub const SessionStats = struct {
    close_state: CloseState,
    active_count: usize,
    retired_count: usize,
};

/// Shared ownership root for managed-frame continuations.
pub const Session = struct {
    allocator: std.mem.Allocator,
    thread_id: std.Thread.Id,
    close_state: CloseState = .open,
    active_head: ?*ContinuationControl = null,
    retired_head: ?*ContinuationControl = null,
    active_count: usize = 0,
    retired_count: usize = 0,

    /// Allocate a new shared session control block.
    pub fn create(allocator: std.mem.Allocator) anyerror!*Session {
        const session = try allocator.create(Session);
        session.* = .{
            .allocator = allocator,
            .thread_id = std.Thread.getCurrentId(),
        };
        return session;
    }

    /// Reject session use from a different thread.
    pub fn ensureThread(self: *Session) Error!void {
        if (self.thread_id != std.Thread.getCurrentId()) return error.CrossThread;
    }

    /// Close the session in the requested mode.
    pub fn close(self: *Session, mode: CloseMode) Error!void {
        try self.ensureThread();
        if (self.close_state != .open) return error.SessionClosed;

        self.close_state = switch (mode) {
            .graceful => .graceful,
            .cancel => .cancel,
        };

        if (mode == .cancel) self.cancelAll();
    }

    /// Destroy the session after it has been closed. Active wrappers survive as tombstones.
    pub fn destroy(self: *Session) Error!void {
        try self.ensureThread();
        if (self.close_state == .open) return error.SessionOpen;

        var active = self.active_head;
        while (active) |control| {
            const next = control.active_next;
            self.unlinkActive(control);
            if (control.box_ptr != null) {
                control.owner_state = .session_destroyed;
                control.destroyBoxFn(control);
                control.box_ptr = null;
            }
            control.owner_session = null;
            if (control.ref_count == 0) {
                control.destroySelfFn(control);
            } else {
                control.retired_next = self.retired_head;
                self.retired_head = control;
                self.retired_count += 1;
            }
            active = next;
        }

        var retired = self.retired_head;
        while (retired) |control| {
            const next = control.retired_next;
            control.retired_next = null;
            control.owner_session = null;
            if (control.ref_count == 0) {
                control.destroySelfFn(control);
            }
            retired = next;
        }
        self.retired_head = null;

        const allocator = self.allocator;
        allocator.destroy(self);
    }

    /// Snapshot close mode and tracked continuation counts.
    pub fn snapshot(self: *const Session) Error!SessionStats {
        try @constCast(self).ensureThread();
        return .{
            .close_state = self.close_state,
            .active_count = self.active_count,
            .retired_count = self.retired_count,
        };
    }

    /// Reject new root starts after close.
    pub fn ensureCanStart(self: *Session) Error!void {
        try self.ensureThread();
        if (self.close_state != .open) return error.SessionClosed;
    }

    /// Track a newly suspended continuation.
    pub fn retainActive(self: *Session, control: *ContinuationControl) void {
        std.debug.assert(self.thread_id == std.Thread.getCurrentId());
        control.owner_session = self;
        control.owner_state = .alive;
        control.active_prev = null;
        control.active_next = self.active_head;
        if (self.active_head) |head| head.active_prev = control;
        self.active_head = control;
        self.active_count += 1;
    }

    /// Move a continuation from the active list into retired storage.
    pub fn retire(self: *Session, control: *ContinuationControl) void {
        std.debug.assert(self.thread_id == std.Thread.getCurrentId());
        self.unlinkActive(control);
        control.retired_next = self.retired_head;
        self.retired_head = control;
        self.retired_count += 1;
    }

    /// Remove a retired continuation once its last wrapper reference is gone.
    pub fn unlinkRetired(self: *Session, target: *ContinuationControl) void {
        var current = self.retired_head;
        var prev: ?*ContinuationControl = null;
        while (current) |control| {
            if (control == target) {
                if (prev) |p| {
                    p.retired_next = control.retired_next;
                } else {
                    self.retired_head = control.retired_next;
                }
                control.retired_next = null;
                self.retired_count -= 1;
                return;
            }
            prev = control;
            current = control.retired_next;
        }
    }

    fn unlinkActive(self: *Session, control: *ContinuationControl) void {
        if (control.active_prev) |prev| {
            prev.active_next = control.active_next;
        } else {
            self.active_head = control.active_next;
        }
        if (control.active_next) |next| next.active_prev = control.active_prev;
        control.active_prev = null;
        control.active_next = null;
        self.active_count -= 1;
    }

    fn cancelAll(self: *Session) void {
        var current = self.active_head;
        while (current) |control| {
            const next = control.active_next;
            control.owner_state = .session_closed;
            if (control.box_ptr != null) {
                control.discardFn(control);
                control.destroyBoxFn(control);
                control.box_ptr = null;
            }
            self.retire(control);
            current = next;
        }
    }
};

/// Refcounted control block for a suspended continuation.
pub const ContinuationControl = struct {
    allocator: std.mem.Allocator,
    thread_id: std.Thread.Id,
    owner_session: ?*Session,
    owner_state: OwnerState = .alive,
    state: State = .fresh,
    ref_count: usize = 1,
    active_prev: ?*ContinuationControl = null,
    active_next: ?*ContinuationControl = null,
    retired_next: ?*ContinuationControl = null,
    box_ptr: ?*anyopaque,
    discardFn: *const fn (*ContinuationControl) void,
    destroyBoxFn: *const fn (*ContinuationControl) void,
    destroySelfFn: *const fn (*ContinuationControl) void,

    /// Increment the number of live wrapper references.
    pub fn retain(self: *ContinuationControl) void {
        self.ref_count += 1;
    }

    /// Drop one wrapper reference and free the tombstone when possible.
    pub fn release(self: *ContinuationControl) void {
        std.debug.assert(self.ref_count > 0);
        self.ref_count -= 1;
        if (self.ref_count == 0 and self.box_ptr == null) {
            if (self.owner_session) |session| {
                session.unlinkRetired(self);
            }
            self.destroySelfFn(self);
        }
    }

    /// Enforce thread affinity and current usability of the continuation.
    pub fn consume(self: *ContinuationControl, next_state: State) Error!void {
        if (self.thread_id != std.Thread.getCurrentId()) return error.CrossThread;
        if (self.state != .fresh) return error.AlreadyResolved;
        switch (self.owner_state) {
            .alive => {},
            .session_closed => return error.SessionClosed,
            .session_destroyed => return error.SessionDestroyed,
        }
        self.state = next_state;
    }
};

/// Erased continuation core shared by typed shells.
pub const Core = struct {
    control: *ContinuationControl,
};

test "continuation control enforces single terminal action" {
    var control = ContinuationControl{
        .allocator = std.testing.allocator,
        .thread_id = std.Thread.getCurrentId(),
        .owner_session = null,
        .box_ptr = null,
        .discardFn = struct {
            fn call(_: *ContinuationControl) void {
                // Deliberately empty for the raw-core unit test.
            }
        }.call,
        .destroyBoxFn = struct {
            fn call(_: *ContinuationControl) void {
                // Deliberately empty for the raw-core unit test.
            }
        }.call,
        .destroySelfFn = struct {
            fn call(_: *ContinuationControl) void {
                // Deliberately empty for the raw-core unit test.
            }
        }.call,
    };

    try control.consume(.resumed);
    try std.testing.expectError(error.AlreadyResolved, control.consume(.discarded));
}
