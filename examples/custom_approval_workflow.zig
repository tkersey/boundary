// zlinter-disable declaration_naming require_doc_comment no_inferred_error_unions
const ability = @import("ability");
const std = @import("std");

fn mustInstruction(result: anyerror!ability.ir.plan.Instruction) ability.ir.plan.Instruction {
    return result catch |err| std.debug.panic("invalid custom-approval instruction: {s}", .{@errorName(err)});
}

fn mustPlan(result: anyerror!ability.ir.ProgramPlan) ability.ir.ProgramPlan {
    return result catch |err| std.debug.panic("invalid custom-approval plan: {s}", .{@errorName(err)});
}

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

    pub fn dispatch(self: *const @This(), payload: []const u8) !i32 {
        transcript.current.lookups += 1;
        transcript.current.last_lookup = payload;
        return if (self.exists_value) 1 else 0;
    }
};

const ApprovalBranch = enum { approve, deny };

const ApprovalHandler = struct {
    branch: ApprovalBranch,

    pub fn dispatch(self: *const @This(), payload: []const u8) !ability.effect.choice.Decision(i32, []const u8) {
        transcript.current.choices += 1;
        transcript.current.last_choice = payload;
        return switch (self.branch) {
            .approve => ability.effect.choice.Decision(i32, []const u8).resumeWith(1),
            .deny => ability.effect.choice.Decision(i32, []const u8).returnNow("denied"),
        };
    }

    pub fn afterDispatch(_: *const @This(), answer: []const u8) ![]const u8 {
        transcript.current.continuations += 1;
        return answer;
    }
};

const GuardHandler = struct {
    pub fn dispatch(_: *const @This(), payload: []const u8) ![]const u8 {
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
    exists: DirectoryHandler,
    request: ApprovalHandler,
    invalid: GuardHandler,
};

fn workflowPlan() ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const request_payload = ability.ir.builder.local(root, 0);
    const exists_value = ability.ir.builder.local(root, 1);
    const approval_resume = ability.ir.builder.local(root, 2);
    const publish_payload = ability.ir.builder.local(root, 3);
    const final_value = ability.ir.builder.local(root, 4);
    const invalid_payload = ability.ir.builder.local(root, 5);
    const missing_value = ability.ir.builder.local(root, 6);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .const_string, .dst = request_payload.index, .string_literal = "request-7" },
        mustInstruction(ability.ir.builder.callOp(root, exists_value, ability.ir.builder.op(root, 0), request_payload)),
        .{ .kind = .compare_eq_zero, .dst = missing_value.index, .operand = exists_value.index },
        .{ .kind = .const_string, .dst = invalid_payload.index, .string_literal = "missing" },
        mustInstruction(ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 2), invalid_payload)),
        mustInstruction(ability.ir.builder.returnValue(root, invalid_payload)),
        mustInstruction(ability.ir.builder.callOp(root, approval_resume, ability.ir.builder.op(root, 1), request_payload)),
        .{ .kind = .const_string, .dst = publish_payload.index, .string_literal = "publish-7" },
        mustInstruction(ability.ir.builder.callOp(root, exists_value, ability.ir.builder.op(root, 0), publish_payload)),
        .{ .kind = .const_string, .dst = final_value.index, .string_literal = "published:approved" },
        mustInstruction(ability.ir.builder.returnValue(root, final_value)),
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .string,
        .result_codec = .string,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 7,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 3,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]ability.ir.plan.Requirement{.{ .label = "workflow", .first_op = 0, .op_count = 3 }};
    const ops = [_]ability.ir.plan.Op{
        .{ .requirement_index = 0, .op_name = "exists", .mode = .transform, .payload_codec = .string, .resume_codec = .i32 },
        .{ .requirement_index = 0, .op_name = "request", .mode = .choice, .payload_codec = .string, .resume_codec = .i32, .has_after = true },
        .{ .requirement_index = 0, .op_name = "invalid", .mode = .abort, .payload_codec = .string, .resume_codec = .unit },
    };
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 3, .terminator_index = 0 },
        .{ .first_instruction = 3, .instruction_count = 3, .terminator_index = 1 },
        .{ .first_instruction = 6, .instruction_count = 5, .terminator_index = 2 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 1, .secondary = 2 },
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return mustPlan(ability.ir.builder.finish(.{
        .label = "custom-approval",
        .ir_hash = 11,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{
            .{ .codec = .string },
            .{ .codec = .i32 },
            .{ .codec = .i32 },
            .{ .codec = .string },
            .{ .codec = .string },
            .{ .codec = .string },
            .{ .codec = .bool },
        },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }));
}

const WorkflowBody = struct {
    pub const compiled_plan = workflowPlan();
};

fn runCase(
    runtime: *ability.Runtime,
    state: DirectoryState,
    branch: ApprovalBranch,
) !RunResult {
    resetTranscript();
    const Program = ability.program("custom-approval", WorkflowHandlers, WorkflowBody);
    var result = try Program.run(runtime, .{
        .exists = .{ .exists_value = state == .present },
        .request = .{ .branch = branch },
        .invalid = .{},
    });
    defer result.deinit();
    return .{ .value = result.value, .transcript = currentTranscript() };
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
