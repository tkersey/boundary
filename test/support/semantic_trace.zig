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
    UnrecognizedTrace,
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

/// Reconstructs a canonical trace from the public/direct workflow summary.
pub fn traceFromCustomApprovalSummary(value: []const u8, transcript: anytype) SemanticTraceError!Snapshot {
    if (transcript.lookups == 2 and
        transcript.choices == 1 and
        transcript.continuations == 1 and
        transcript.aborts == 0 and
        std.mem.eql(u8, transcript.last_lookup, "publish-7") and
        std.mem.eql(u8, transcript.last_choice, "request-7") and
        std.mem.eql(u8, transcript.last_abort, "") and
        std.mem.eql(u8, value, "published:approved"))
    {
        return try expectedCustomApprovalTrace(.approve);
    }

    if (transcript.lookups == 1 and
        transcript.choices == 1 and
        transcript.continuations == 0 and
        transcript.aborts == 0 and
        std.mem.eql(u8, transcript.last_lookup, "request-7") and
        std.mem.eql(u8, transcript.last_choice, "request-7") and
        std.mem.eql(u8, transcript.last_abort, "") and
        std.mem.eql(u8, value, "denied"))
    {
        return try expectedCustomApprovalTrace(.deny);
    }

    if (transcript.lookups == 1 and
        transcript.choices == 0 and
        transcript.continuations == 0 and
        transcript.aborts == 1 and
        std.mem.eql(u8, transcript.last_lookup, "request-7") and
        std.mem.eql(u8, transcript.last_choice, "") and
        std.mem.eql(u8, transcript.last_abort, "missing") and
        std.mem.eql(u8, value, "invalid:missing"))
    {
        return try expectedCustomApprovalTrace(.invalid);
    }

    return error.UnrecognizedTrace;
}

/// Converts a boolean host answer into the trace's stable string form.
pub fn boolAnswer(value: bool) []const u8 {
    return if (value) "true" else "false";
}
