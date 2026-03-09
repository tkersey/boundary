const shift = @import("shift");
const std = @import("std");

/// Fixed showcase scenarios for the advanced job-workflow example.
pub const Scenario = enum {
    approved,
    cancelled,
    rejected,
};

/// Final scenario status after the driver resolves a workflow.
pub const ScenarioResult = enum {
    cancelled,
    completed,
    recovered,
};

/// Requests emitted by the workflow body to the external driver.
pub const WorkflowRequest = union(enum) {
    approval: []const u8,
    log: []const u8,
};

/// Resume payloads sent back into the workflow body.
pub const WorkflowResume = union(enum) {
    ack: void,
    approved: bool,
};

const WorkflowError = error{ApprovalDenied};

const workflow_spec = struct {
    /// Prompt tag for the outer workflow driver.
    pub const tag = struct {};
    /// Requests emitted by the workflow body.
    pub const Request = WorkflowRequest;
    /// Resume payloads accepted by the workflow body.
    pub const Resume = WorkflowResume;
    /// Final scenario result returned by the workflow body.
    pub const Answer = ScenarioResult;
    /// User-controlled rejection path for approval denial.
    pub const ErrorSet = WorkflowError;
};

const audit_spec = struct {
    /// Prompt tag for the nested audit reset.
    pub const tag = struct {};
    /// The nested audit does not emit inner requests.
    pub const Request = void;
    /// The nested audit does not accept inner resume values.
    pub const Resume = void;
    /// The nested audit completes without a value.
    pub const Answer = void;
    /// The nested audit shares the workflow rejection surface.
    pub const ErrorSet = WorkflowError;
};

/// Run the full deterministic showcase through all three workflow branches.
pub fn runShowcase(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();

    const scenarios = [_]Scenario{ .approved, .rejected, .cancelled };
    for (scenarios, 0..) |scenario, index| {
        if (index != 0) try writer.writeAll("\n");
        try writer.print("scenario={s}\n", .{@tagName(scenario)});
        _ = try runScenario(&runtime, scenario, writer);
    }
}

/// Run one workflow scenario and render its trace to the provided writer.
pub fn runScenario(runtime: *shift.Runtime, scenario: Scenario, writer: anytype) anyerror!ScenarioResult {
    var driver = ScenarioDriver(@TypeOf(writer)){
        .runtime = runtime,
        .writer = writer,
        .scenario = scenario,
    };
    return try driver.run();
}

/// Prove that suspending under an active no-shift guard returns `error.ShiftForbidden`.
pub fn proveGuardRejectsSuspend(runtime: *shift.Runtime) shift.ResetError(error{})!void {
    const guard_spec = struct {
        /// Prompt tag for the guard rejection probe.
        pub const tag = struct {};
        /// The probe emits a unit request if the guard fails to block it.
        pub const Request = void;
        /// The probe never expects to resume.
        pub const Resume = void;
        /// The probe completes without a value.
        pub const Answer = void;
        /// The probe has no user-defined error surface.
        pub const ErrorSet = error{};
    };

    const guard_probe = struct {
        var runtime_ptr: ?*shift.Runtime = null;

        fn body() shift.ResetError(guard_spec.ErrorSet)!guard_spec.Answer {
            var guard: shift.NoShiftGuard = .{};
            try guard.enter(runtime_ptr.?);
            defer guard.leave();
            _ = try shift.shift(guard_spec, {});
        }
    };

    guard_probe.runtime_ptr = runtime;
    const outcome = try shift.reset(guard_spec, runtime, guard_probe.body);
    switch (outcome) {
        .complete => return,
        .token, .cancelled => unreachable,
    }
}

fn ScenarioDriver(comptime Writer: type) type {
    return struct {
        runtime: *shift.Runtime,
        writer: Writer,
        scenario: Scenario,
        critical_updates: usize = 0,

        var current: ?*@This() = null;

        fn run(self: *@This()) anyerror!ScenarioResult {
            current = self;
            defer current = null;

            var outcome = try shift.reset(workflow_spec, self.runtime, body);
            const result = while (true) switch (outcome) {
                .complete => |value| break value,
                .cancelled => break .cancelled,
                .token => |*token| switch (token.request) {
                    .log => |message| {
                        errdefer token.deinit();
                        try self.writer.print("log={s}\n", .{message});
                        outcome = try token.resumeWith(.{ .ack = {} });
                    },
                    .approval => |job| {
                        errdefer token.deinit();
                        try self.writer.print("approval={s}\n", .{job});
                        outcome = switch (self.scenario) {
                            .approved => try token.resumeWith(.{ .approved = true }),
                            .rejected => try token.discontinue(error.ApprovalDenied),
                            .cancelled => try token.cancel(),
                        };
                    },
                },
            };
            try self.writer.print("result={s}\n", .{@tagName(result)});
            return result;
        }

        fn body() shift.ResetError(workflow_spec.ErrorSet)!workflow_spec.Answer {
            const self = current.?;

            switch (self.scenario) {
                .approved => {
                    try self.logRequest("queued ingest");
                    try self.prepareCriticalMetadata();
                    try self.logRequest("nested audit started");
                    const audit_outcome = try shift.reset(audit_spec, self.runtime, auditBody);
                    switch (audit_outcome) {
                        .complete => {},
                        .token, .cancelled => unreachable,
                    }
                    try self.logRequest("nested audit finished");
                    return .completed;
                },
                .rejected => {
                    try self.logRequest("queued publish");
                    try self.prepareCriticalMetadata();
                    self.requestApproval("publish") catch |err| switch (err) {
                        error.ApprovalDenied => {
                            try self.logRequest("recovered publish skipped");
                            return .recovered;
                        },
                        else => return err,
                    };
                    unreachable;
                },
                .cancelled => {
                    try self.logRequest("queued cleanup");
                    try self.prepareCriticalMetadata();
                    try self.requestApproval("cleanup");
                    unreachable;
                },
            }
        }

        fn auditBody() shift.ResetError(audit_spec.ErrorSet)!audit_spec.Answer {
            const decision = try shift.shift(workflow_spec, .{ .approval = "ingest" });
            switch (decision) {
                .approved => |approved| {
                    if (!approved) return error.ApprovalDenied;
                },
                .ack => unreachable,
            }
        }

        fn logRequest(_: *@This(), message: []const u8) shift.ResetError(workflow_spec.ErrorSet)!void {
            const reply = try shift.shift(workflow_spec, .{ .log = message });
            switch (reply) {
                .ack => {},
                .approved => unreachable,
            }
        }

        fn requestApproval(self: *@This(), job: []const u8) shift.ResetError(workflow_spec.ErrorSet)!void {
            const decision = try shift.shift(workflow_spec, .{ .approval = job });
            switch (decision) {
                .approved => |approved| {
                    if (!approved) return error.ApprovalDenied;
                },
                .ack => unreachable,
            }
            _ = self;
        }

        fn prepareCriticalMetadata(self: *@This()) shift.ResetError(workflow_spec.ErrorSet)!void {
            var guard: shift.NoShiftGuard = .{};
            try guard.enter(self.runtime);
            self.critical_updates += 1;
            try guard.leaveChecked();
            try self.logRequest("critical metadata prepared");
        }
    };
}
