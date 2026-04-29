const ability = @import("ability");
const std = @import("std");

/// Generated transform family used by the custom workflow row.
pub const directory = ability.effect.Define(.{
    .state_type = void,
    .ops = .{
        ability.effect.ops.Transform("exists", []const u8, bool),
    },
});

/// Generated choice family used by the custom workflow row.
pub const approval = ability.effect.Define(.{
    .state_type = void,
    .ops = .{
        ability.effect.ops.Choice("request", []const u8, []const u8),
    },
});

/// Generated abort family used by the custom workflow row.
pub const guard = ability.effect.Define(.{
    .state_type = void,
    .ops = .{
        ability.effect.ops.Abort("invalid", []const u8),
    },
});

/// Observable workflow transcript for the approval example.
pub const Transcript = struct {
    lookups: usize = 0,
    choices: usize = 0,
    continuations: usize = 0,
    aborts: usize = 0,
    last_lookup: []const u8 = "",
    last_choice: []const u8 = "",
    last_abort: []const u8 = "",
};

const transcript = struct {
    threadlocal var current: Transcript = .{};
};

fn resetTranscript() void {
    transcript.current = .{};
}

fn currentTranscript() Transcript {
    return transcript.current;
}

const DirectoryHandler = struct {
    exists_value: bool,

    /// Record the directory lookup and return the configured presence bit.
    pub fn exists(self: *@This(), payload: []const u8) bool {
        transcript.current.lookups += 1;
        transcript.current.last_lookup = payload;
        return self.exists_value;
    }

    /// Preserve the workflow answer after the transform resumes.
    pub fn afterExists(_: *@This(), answer: []const u8) []const u8 {
        return answer;
    }
};

const ApprovalBranch = enum { approve, deny };

const ApprovalHandler = struct {
    branch: ApprovalBranch,

    /// Decide whether the approval request resumes or returns immediately.
    pub fn request(self: *@This(), payload: []const u8) ability.effect.choice.Decision([]const u8, []const u8) {
        transcript.current.choices += 1;
        transcript.current.last_choice = payload;
        return switch (self.branch) {
            .approve => ability.effect.choice.Decision([]const u8, []const u8).resumeWith("approved"),
            .deny => ability.effect.choice.Decision([]const u8, []const u8).returnNow("denied"),
        };
    }

    /// Record that the approval continuation resumed and preserve its answer.
    pub fn afterRequest(_: *@This(), answer: []const u8) []const u8 {
        transcript.current.continuations += 1;
        return answer;
    }
};

const guard_handler = struct {
    /// Record an invalid request and return the abort answer.
    pub fn invalid(_: *@This(), payload: []const u8) []const u8 {
        transcript.current.aborts += 1;
        transcript.current.last_abort = payload;
        return "invalid:missing";
    }
};

/// Source-lowered entry used by the maintainer ProgramPlan proof.
pub fn loweredWorkflowBody(_: anytype) anyerror![]const u8 {
    return "published:approved";
}

/// Source-backed named body for same-source lowering checks.
pub const approval_workflow_body = struct {
    fn sourceLocation() std.builtin.SourceLocation {
        return @src();
    }

    /// Embedded source used as the source-backed witness bytes.
    pub const source = @embedFile("custom_approval_workflow.zig");
    /// Stable hash for the embedded source witness.
    pub const source_hash = ability.sourceHash(source);
    /// Source location owned by this package-like example module.
    pub const source_location = sourceLocation();
    /// Basename required by the source-backed named-body verifier.
    pub const source_file = "custom_approval_workflow.zig";
    /// Stable identity for diagnostics and source-backed validation.
    pub const source_identity = "custom_approval_workflow.approval_workflow_body";

    /// Body mirrored by `loweredWorkflowBody` for the same-source plan proof.
    pub fn body(_: anytype) anyerror![]const u8 {
        return "published:approved";
    }
};

/// Result bundle returned by each runnable approval workflow case.
pub const RunResult = struct {
    value: []const u8,
    transcript: Transcript,
};

const DirectoryState = enum { missing, present };

fn approvalPresentRuntimeBody(eff: anytype) anyerror![]const u8 {
    _ = try eff.directory.exists.perform("request-7");
    return try eff.approval.request.perform("request-7", struct {
        /// Publish only after the approval handler resumes.
        pub fn apply(_: []const u8, _: anytype) anyerror![]const u8 {
            return "published:approved";
        }
    });
}

fn approvalInvalidRuntimeBody(eff: anytype) anyerror![]const u8 {
    _ = try eff.directory.exists.perform("request-7");
    try eff.guard.invalid.abort("missing");
}

const approval_present_body = struct {
    /// Source path for the named runtime carrier used by compiled workflow proof.
    pub const source_path = "examples/custom_approval_workflow.zig";
    /// Entry symbol for the named runtime carrier used by compiled workflow proof.
    pub const body_symbol = "approvalPresentRuntimeBody";

    /// Exercise the generated transform and choice families through `ability.with`.
    pub fn body(eff: anytype) anyerror![]const u8 {
        return approvalPresentRuntimeBody(eff);
    }
};

const approval_invalid_body = struct {
    /// Source path for the named runtime carrier used by compiled workflow proof.
    pub const source_path = "examples/custom_approval_workflow.zig";
    /// Entry symbol for the named runtime carrier used by compiled workflow proof.
    pub const body_symbol = "approvalInvalidRuntimeBody";

    /// Exercise the generated transform and abort families through `ability.with`.
    pub fn body(eff: anytype) anyerror![]const u8 {
        return approvalInvalidRuntimeBody(eff);
    }
};

fn runCase(
    runtime: *ability.Runtime,
    state: DirectoryState,
    branch: ApprovalBranch,
) anyerror!RunResult {
    resetTranscript();
    const exists_value = switch (state) {
        .present => true,
        .missing => false,
    };
    return switch (state) {
        .present => blk: {
            const result = try ability.with(runtime, .{
                .directory = directory.use(.{ .handler = DirectoryHandler{ .exists_value = exists_value } }),
                .guard = guard.use(.{ .handler = guard_handler{} }),
                .approval = approval.use(.{ .handler = ApprovalHandler{ .branch = branch } }),
            }, approval_present_body);
            break :blk .{
                .value = result.value,
                .transcript = currentTranscript(),
            };
        },
        .missing => blk: {
            const result = try ability.with(runtime, .{
                .directory = directory.use(.{ .handler = DirectoryHandler{ .exists_value = exists_value } }),
                .guard = guard.use(.{ .handler = guard_handler{} }),
                .approval = approval.use(.{ .handler = ApprovalHandler{ .branch = branch } }),
            }, approval_invalid_body);
            break :blk .{
                .value = result.value,
                .transcript = currentTranscript(),
            };
        },
    };
}

/// Run the approving workflow branch.
pub fn runApprove(runtime: *ability.Runtime) anyerror!RunResult {
    return runCase(runtime, .present, .approve);
}

/// Run the denying workflow branch.
pub fn runDeny(runtime: *ability.Runtime) anyerror!RunResult {
    return runCase(runtime, .present, .deny);
}

/// Run the invalid-request workflow branch.
pub fn runInvalid(runtime: *ability.Runtime) anyerror!RunResult {
    return runCase(runtime, .missing, .approve);
}

/// Write the approval workflow transcript for all three branches.
pub fn run(writer: anytype) anyerror!void {
    var runtime = ability.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    const approved = try runApprove(&runtime);
    try writer.print("approve={s} lookups={d} choices={d} continuations={d} aborts={d}\n", .{
        approved.value,
        approved.transcript.lookups,
        approved.transcript.choices,
        approved.transcript.continuations,
        approved.transcript.aborts,
    });

    const denied = try runDeny(&runtime);
    try writer.print("deny={s} lookups={d} choices={d} continuations={d} aborts={d}\n", .{
        denied.value,
        denied.transcript.lookups,
        denied.transcript.choices,
        denied.transcript.continuations,
        denied.transcript.aborts,
    });

    const invalid = try runInvalid(&runtime);
    try writer.print("invalid={s} lookups={d} choices={d} continuations={d} aborts={d}\n", .{
        invalid.value,
        invalid.transcript.lookups,
        invalid.transcript.choices,
        invalid.transcript.continuations,
        invalid.transcript.aborts,
    });
}

/// Run the custom approval workflow example.
pub fn main(init: std.process.Init) anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
