const std = @import("std");

/// Maximum event count for the custom approval workflow trace oracle.
pub const max_events = 5;

/// Branch selected by the custom approval workflow host.
pub const Branch = enum {
    approve,
    deny,
    invalid,
};

/// Canonical semantic event categories recorded by public and artifact paths.
pub const EventKind = enum {
    after_hook,
    operation,
    output,
};

/// Algebraic operation mode for a trace event.
pub const Mode = enum {
    abort,
    choice,
    transform,
};

/// Host decision represented by a trace event.
pub const Decision = enum {
    aborted,
    completed,
    resumed,
    return_now,
};

/// Whether a trace event terminates the workflow immediately.
pub const Terminal = enum {
    nonterminal,
    terminal,
};

/// One canonical semantic event in the custom approval workflow trace.
pub const Event = struct {
    kind: EventKind = .operation,
    requirement: []const u8 = "",
    op_name: []const u8 = "",
    mode: ?Mode = null,
    payload: []const u8 = "",
    decision: Decision = .resumed,
    answer: []const u8 = "",
    terminal: bool = false,
};

/// Fixed-size trace snapshot used by test-only semantic oracles.
pub const Snapshot = struct {
    events: [max_events]Event = [_]Event{.{}} ** max_events,
    len: usize = 0,

    /// Adds one event, failing closed if the workflow shape grows unexpectedly.
    pub fn append(self: *@This(), event: Event) SemanticTraceError!void {
        if (self.len >= self.events.len) return error.SemanticTraceOverflow;
        self.events[self.len] = event;
        self.len += 1;
    }

    /// Returns only the populated event prefix.
    pub fn slice(self: *const @This()) []const Event {
        return self.events[0..self.len];
    }
};

/// Errors raised by the semantic trace oracle itself.
pub const SemanticTraceError = error{
    SemanticTraceOverflow,
    UnexpectedWorkflowValue,
};

/// Expects two snapshots to contain the same canonical trace.
pub fn expectEqualSnapshot(actual: Snapshot, expected: Snapshot) anyerror!void {
    try expectEqualEvents(actual.slice(), expected.slice());
}

/// Expects two event slices to contain the same canonical trace.
pub fn expectEqualEvents(actual: []const Event, expected: []const Event) anyerror!void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (actual, expected) |actual_event, expected_event| {
        try std.testing.expectEqual(expected_event.kind, actual_event.kind);
        try std.testing.expectEqual(expected_event.mode, actual_event.mode);
        try std.testing.expectEqual(expected_event.decision, actual_event.decision);
        try std.testing.expectEqual(expected_event.terminal, actual_event.terminal);
        try std.testing.expectEqualStrings(expected_event.requirement, actual_event.requirement);
        try std.testing.expectEqualStrings(expected_event.op_name, actual_event.op_name);
        try std.testing.expectEqualStrings(expected_event.payload, actual_event.payload);
        try std.testing.expectEqualStrings(expected_event.answer, actual_event.answer);
    }
}

/// Builds the expected canonical trace for each custom approval workflow branch.
pub fn expectedCustomApprovalTrace(branch: Branch) SemanticTraceError!Snapshot {
    var snapshot: Snapshot = .{};
    try snapshot.append(.{
        .kind = .operation,
        .requirement = "directory",
        .op_name = "exists",
        .mode = .transform,
        .payload = "request-7",
        .decision = .resumed,
        .answer = if (branch == .invalid) "false" else "true",
    });

    switch (branch) {
        .approve => {
            try snapshot.append(.{
                .kind = .operation,
                .requirement = "approval",
                .op_name = "request",
                .mode = .choice,
                .payload = "request-7",
                .decision = .resumed,
                .answer = "approved",
            });
            try snapshot.append(.{
                .kind = .operation,
                .requirement = "directory",
                .op_name = "exists",
                .mode = .transform,
                .payload = "publish-7",
                .decision = .resumed,
                .answer = "true",
            });
            try snapshot.append(.{
                .kind = .after_hook,
                .requirement = "approval",
                .op_name = "afterRequest",
                .mode = .choice,
                .decision = .resumed,
                .answer = "published:approved",
            });
            try snapshot.append(.{
                .kind = .output,
                .decision = .completed,
                .answer = "published:approved",
                .terminal = true,
            });
        },
        .deny => {
            try snapshot.append(.{
                .kind = .operation,
                .requirement = "approval",
                .op_name = "request",
                .mode = .choice,
                .payload = "request-7",
                .decision = .return_now,
                .answer = "denied",
                .terminal = true,
            });
            try snapshot.append(.{
                .kind = .output,
                .decision = .completed,
                .answer = "denied",
                .terminal = true,
            });
        },
        .invalid => {
            try snapshot.append(.{
                .kind = .operation,
                .requirement = "guard",
                .op_name = "invalid",
                .mode = .abort,
                .payload = "missing",
                .decision = .aborted,
                .answer = "invalid:missing",
                .terminal = true,
            });
            try snapshot.append(.{
                .kind = .output,
                .decision = .completed,
                .answer = "invalid:missing",
                .terminal = true,
            });
        },
    }
    return snapshot;
}

/// Converts a boolean host answer into the trace's stable string form.
pub fn boolAnswer(value: bool) []const u8 {
    return if (value) "true" else "false";
}

/// Converts a workflow terminal value into its stable trace answer.
pub fn stableWorkflowValue(value: []const u8) SemanticTraceError![]const u8 {
    if (std.mem.eql(u8, value, "published:approved")) return "published:approved";
    if (std.mem.eql(u8, value, "denied")) return "denied";
    if (std.mem.eql(u8, value, "invalid:missing")) return "invalid:missing";
    return error.UnexpectedWorkflowValue;
}

/// Appends a test-only trace event and panics if the fixed oracle shape overflows.
pub fn appendAssumeCapacity(snapshot: *Snapshot, event: Event) void {
    snapshot.append(event) catch |err| std.debug.panic("semantic trace append failed: {s}", .{@errorName(err)});
}

/// Records an observed directory.exists transform event.
pub fn recordDirectoryExists(snapshot: *Snapshot, payload: []const u8, answer: bool) void {
    appendAssumeCapacity(snapshot, .{
        .kind = .operation,
        .requirement = "directory",
        .op_name = "exists",
        .mode = .transform,
        .payload = payload,
        .decision = .resumed,
        .answer = boolAnswer(answer),
    });
}

/// Records an observed approval.request choice event.
pub fn recordApprovalRequest(
    snapshot: *Snapshot,
    payload: []const u8,
    decision: Decision,
    answer: []const u8,
    terminal: Terminal,
) void {
    appendAssumeCapacity(snapshot, .{
        .kind = .operation,
        .requirement = "approval",
        .op_name = "request",
        .mode = .choice,
        .payload = payload,
        .decision = decision,
        .answer = answer,
        .terminal = terminal == .terminal,
    });
}

/// Records an observed guard.invalid abort event.
pub fn recordGuardInvalid(snapshot: *Snapshot, payload: []const u8, answer: []const u8) void {
    appendAssumeCapacity(snapshot, .{
        .kind = .operation,
        .requirement = "guard",
        .op_name = "invalid",
        .mode = .abort,
        .payload = payload,
        .decision = .aborted,
        .answer = answer,
        .terminal = true,
    });
}

/// Records an observed approval after hook event.
pub fn recordAfterRequest(snapshot: *Snapshot, answer: []const u8) void {
    appendAssumeCapacity(snapshot, .{
        .kind = .after_hook,
        .requirement = "approval",
        .op_name = "afterRequest",
        .mode = .choice,
        .decision = .resumed,
        .answer = answer,
    });
}

/// Records the terminal workflow output event.
pub fn recordOutput(snapshot: *Snapshot, value: []const u8) SemanticTraceError!void {
    appendAssumeCapacity(snapshot, .{
        .kind = .output,
        .decision = .completed,
        .answer = try stableWorkflowValue(value),
        .terminal = true,
    });
}
