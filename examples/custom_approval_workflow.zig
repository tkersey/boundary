// zlinter-disable declaration_naming require_doc_comment no_inferred_error_unions
const ability = @import("ability");
const std = @import("std");

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

    pub fn exists(self: @This(), payload: []const u8) bool {
        transcript.current.lookups += 1;
        transcript.current.last_lookup = payload;
        return self.exists_value;
    }
};

const ApprovalBranch = enum { approve, deny };

const ApprovalHandler = struct {
    branch: ApprovalBranch,

    pub fn request(self: @This(), payload: []const u8) []const u8 {
        transcript.current.choices += 1;
        transcript.current.last_choice = payload;
        return switch (self.branch) {
            .approve => "approved",
            .deny => "denied",
        };
    }

    pub fn afterRequest(_: @This(), answer: []const u8) []const u8 {
        transcript.current.continuations += 1;
        return answer;
    }
};

const GuardHandler = struct {
    pub fn invalid(_: @This(), payload: []const u8) []const u8 {
        transcript.current.aborts += 1;
        transcript.current.last_abort = payload;
        return "invalid:missing";
    }
};

pub const RunResult = struct {
    value: []const u8,
    transcript: Transcript,
};

const DirectoryState = enum { missing, present };

const WorkflowHandlers = struct {
    directory: DirectoryHandler,
    approval: ApprovalHandler,
    guard: GuardHandler,
};

const WorkflowBody = struct {
    pub fn program(_: *ability.Runtime, handlers: WorkflowHandlers) !struct { value: RunResult } {
        resetTranscript();
        if (!handlers.directory.exists("request-7")) {
            return .{
                .value = .{
                    .value = handlers.guard.invalid("missing"),
                    .transcript = currentTranscript(),
                },
            };
        }

        const decision = handlers.approval.request("request-7");
        if (std.mem.eql(u8, decision, "denied")) {
            return .{
                .value = .{
                    .value = decision,
                    .transcript = currentTranscript(),
                },
            };
        }

        _ = handlers.directory.exists("publish-7");
        return .{
            .value = .{
                .value = handlers.approval.afterRequest("published:approved"),
                .transcript = currentTranscript(),
            },
        };
    }
};

fn runCase(
    runtime: *ability.Runtime,
    state: DirectoryState,
    branch: ApprovalBranch,
) !RunResult {
    const Program = ability.program("custom-approval", WorkflowHandlers, WorkflowBody);
    var result = try Program.run(runtime, .{
        .directory = .{ .exists_value = state == .present },
        .approval = .{ .branch = branch },
        .guard = .{},
    });
    defer result.deinit();
    return result.value;
}

pub fn runApprove(runtime: *ability.Runtime) !RunResult {
    return runCase(runtime, .present, .approve);
}

pub fn runDeny(runtime: *ability.Runtime) !RunResult {
    return runCase(runtime, .present, .deny);
}

pub fn runInvalid(runtime: *ability.Runtime) !RunResult {
    return runCase(runtime, .missing, .approve);
}

pub fn run(writer: anytype) !void {
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

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
