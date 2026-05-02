const ability = @import("ability");
const ability_compile = @import("ability_compile");
const example = @import("example_custom_approval_workflow");
const semantic_trace = @import("support/semantic_trace.zig");
const std = @import("std");

const ExpectedTranscript = struct {
    lookups: usize,
    choices: usize,
    continuations: usize,
    aborts: usize,
    last_lookup: []const u8,
    last_choice: []const u8,
    last_abort: []const u8,
};

fn expectTranscript(
    actual: anytype,
    expected: ExpectedTranscript,
) !void {
    try std.testing.expectEqual(expected.lookups, actual.lookups);
    try std.testing.expectEqual(expected.choices, actual.choices);
    try std.testing.expectEqual(expected.continuations, actual.continuations);
    try std.testing.expectEqual(expected.aborts, actual.aborts);
    try std.testing.expectEqualStrings(expected.last_lookup, actual.last_lookup);
    try std.testing.expectEqualStrings(expected.last_choice, actual.last_choice);
    try std.testing.expectEqualStrings(expected.last_abort, actual.last_abort);
}

fn expectBranchTrace(actual: semantic_trace.Snapshot, branch: semantic_trace.Branch) !void {
    try semantic_trace.expectEqualSnapshot(actual, try semantic_trace.expectedCustomApprovalTrace(branch));
}

fn workflowLoweringSpec() ability_compile.lowering_api.LowerSpec {
    return .{
        .label = "example.custom_approval_workflow",
        .entry_symbol = "approvalRuntimeBody",
        .row = ability_compile.effect_ir.mergeRows(.{
            ability_compile.effect_ir.rowFromSpec(.{
                .directory = .{
                    .exists = ability_compile.effect_ir.Transform([]const u8, bool),
                },
            }),
            ability_compile.effect_ir.rowFromSpec(.{
                .approval = .{
                    .request = ability_compile.effect_ir.Choice([]const u8, []const u8),
                },
            }),
            ability_compile.effect_ir.rowFromSpec(.{
                .guard = .{
                    .invalid = ability_compile.effect_ir.Abort([]const u8),
                },
            }),
        }),
        .ValueType = []const u8,
    };
}

fn workflowSource() ability_compile.lowering_api.SourceRef {
    const caller = example.approval_workflow_body.source_location;
    return ability_compile.lowering_api.sourceWithContent(
        "examples/custom_approval_workflow.zig",
        .{
            .module = caller.module,
            .file = "examples/custom_approval_workflow.zig",
            .line = caller.line,
            .column = caller.column,
            .fn_name = caller.fn_name,
        },
        example.approval_workflow_body.source,
    );
}

const LoweredWorkflow = ability_compile.lower(workflowSource(), workflowLoweringSpec());
const CompiledWorkflowArtifact = ability.compile(
    "example.custom_approval_workflow",
    LoweredWorkflow.runtime_plan,
    .{ .stable_build_fingerprint_seed = "custom-approval-workflow-effectful-continuation" },
);
const DirectBranch = enum { approve, deny };

const DirectDirectoryHandler = struct {
    exists_value: bool,
    trace: *semantic_trace.Snapshot,
    lookups: usize = 0,
    last_lookup: []const u8 = "",

    /// Records a direct ProgramPlan directory lookup and returns the configured existence value.
    pub fn exists(self: *@This(), payload: []const u8) bool {
        self.lookups += 1;
        self.last_lookup = payload;
        semantic_trace.recordDirectoryExists(self.trace, payload, self.exists_value);
        return self.exists_value;
    }

    /// Mirrors the public runtime's directory after hook for transcript parity.
    pub fn afterExists(_: *@This(), answer: []const u8) []const u8 {
        return answer;
    }
};

const DirectApprovalHandler = struct {
    branch: DirectBranch,
    trace: *semantic_trace.Snapshot,
    choices: usize = 0,
    continuations: usize = 0,
    last_choice: []const u8 = "",

    const Decision = union(enum) {
        resume_with: []const u8,
        return_now: []const u8,

        fn resumeWith(value: []const u8) @This() {
            return .{ .resume_with = value };
        }

        fn returnNow(value: []const u8) @This() {
            return .{ .return_now = value };
        }
    };

    /// Records a direct ProgramPlan approval choice and selects the configured branch.
    pub fn request(self: *@This(), payload: []const u8) Decision {
        self.choices += 1;
        self.last_choice = payload;
        return switch (self.branch) {
            .approve => approve: {
                semantic_trace.recordApprovalRequest(self.trace, payload, .resumed, "approved", .nonterminal);
                break :approve Decision.resumeWith("approved");
            },
            .deny => deny: {
                semantic_trace.recordApprovalRequest(self.trace, payload, .return_now, "denied", .terminal);
                break :deny Decision.returnNow("denied");
            },
        };
    }

    /// Records approval continuation replay after a resumed choice.
    pub fn afterRequest(self: *@This(), answer: []const u8) []const u8 {
        self.continuations += 1;
        semantic_trace.recordAfterRequest(self.trace, answer);
        return answer;
    }
};

const DirectGuardHandler = struct {
    trace: *semantic_trace.Snapshot,
    aborts: usize = 0,
    last_abort: []const u8 = "",

    /// Records terminal guard aborts on the direct ProgramPlan path.
    pub fn invalid(self: *@This(), payload: []const u8) []const u8 {
        self.aborts += 1;
        self.last_abort = payload;
        semantic_trace.recordGuardInvalid(self.trace, payload, "invalid:missing");
        return "invalid:missing";
    }
};

const DirectHandlers = struct {
    directory: DirectDirectoryHandler,
    guard: DirectGuardHandler,
    approval: DirectApprovalHandler,
};

fn runLoweredWorkflowCase(
    runtime: *ability.Runtime,
    exists_value: bool,
    branch: DirectBranch,
) anyerror!struct {
    value: []const u8,
    transcript: ExpectedTranscript,
    trace: semantic_trace.Snapshot,
} {
    var trace: semantic_trace.Snapshot = .{};
    var handlers = DirectHandlers{
        .directory = .{ .exists_value = exists_value, .trace = &trace },
        .guard = .{ .trace = &trace },
        .approval = .{ .branch = branch, .trace = &trace },
    };
    const result = try LoweredWorkflow.run(runtime, &handlers);
    try semantic_trace.recordOutput(&trace, result.value);
    return .{
        .value = result.value,
        .transcript = .{
            .lookups = handlers.directory.lookups,
            .choices = handlers.approval.choices,
            .continuations = handlers.approval.continuations,
            .aborts = handlers.guard.aborts,
            .last_lookup = handlers.directory.last_lookup,
            .last_choice = handlers.approval.last_choice,
            .last_abort = handlers.guard.last_abort,
        },
        .trace = trace,
    };
}

const PublicContext = struct {
    exists_value: bool,
    branch: DirectBranch,
    transcript: ExpectedTranscript = .{
        .lookups = 0,
        .choices = 0,
        .continuations = 0,
        .aborts = 0,
        .last_lookup = "",
        .last_choice = "",
        .last_abort = "",
    },
    trace: semantic_trace.Snapshot = .{},
};

const PublicDirectoryHandler = struct {
    ctx: *PublicContext,

    /// Records the public runtime directory lookup and returns the configured existence value.
    pub fn exists(self: *@This(), payload: []const u8) bool {
        self.ctx.transcript.lookups += 1;
        self.ctx.transcript.last_lookup = payload;
        semantic_trace.recordDirectoryExists(&self.ctx.trace, payload, self.ctx.exists_value);
        return self.ctx.exists_value;
    }
};

const PublicApprovalHandler = struct {
    ctx: *PublicContext,

    /// Records the public runtime approval choice and selects the configured branch.
    pub fn request(self: *@This(), payload: []const u8) ability.effect.choice.Decision([]const u8, []const u8) {
        self.ctx.transcript.choices += 1;
        self.ctx.transcript.last_choice = payload;
        return switch (self.ctx.branch) {
            .approve => approve: {
                semantic_trace.recordApprovalRequest(&self.ctx.trace, payload, .resumed, "approved", .nonterminal);
                break :approve ability.effect.choice.Decision([]const u8, []const u8).resumeWith("approved");
            },
            .deny => deny: {
                semantic_trace.recordApprovalRequest(&self.ctx.trace, payload, .return_now, "denied", .terminal);
                break :deny ability.effect.choice.Decision([]const u8, []const u8).returnNow("denied");
            },
        };
    }

    /// Records the public runtime after hook replay after a resumed approval.
    pub fn afterRequest(self: *@This(), answer: []const u8) []const u8 {
        self.ctx.transcript.continuations += 1;
        semantic_trace.recordAfterRequest(&self.ctx.trace, answer);
        return answer;
    }
};

const PublicGuardHandler = struct {
    ctx: *PublicContext,

    /// Records the public runtime guard abort and returns its terminal answer.
    pub fn invalid(self: *@This(), payload: []const u8) []const u8 {
        self.ctx.transcript.aborts += 1;
        self.ctx.transcript.last_abort = payload;
        semantic_trace.recordGuardInvalid(&self.ctx.trace, payload, "invalid:missing");
        return "invalid:missing";
    }
};

const PublicHandlers = struct {
    directory: PublicDirectoryHandler,
    guard: PublicGuardHandler,
    approval: PublicApprovalHandler,
};

var public_descriptor_context = PublicContext{
    .exists_value = false,
    .branch = .deny,
};
const PublicDescriptorHandlers = @TypeOf(.{
    .directory = example.directory.use(.{ .handler = PublicDirectoryHandler{ .ctx = &public_descriptor_context } }),
    .guard = example.guard.use(.{ .handler = PublicGuardHandler{ .ctx = &public_descriptor_context } }),
    .approval = example.approval.use(.{ .handler = PublicApprovalHandler{ .ctx = &public_descriptor_context } }),
});
const PublicWorkflowProgram = ability.program(
    "example.custom_approval_workflow.public_program",
    PublicDescriptorHandlers,
    example.approval_runtime_body,
    .{ .stable_build_fingerprint_seed = "custom-approval-workflow-public-program" },
);

fn runPublicWorkflowCase(
    runtime: *ability.Runtime,
    exists_value: bool,
    branch: DirectBranch,
) anyerror!struct {
    value: []const u8,
    transcript: ExpectedTranscript,
    trace: semantic_trace.Snapshot,
} {
    var ctx = PublicContext{
        .exists_value = exists_value,
        .branch = branch,
    };
    const handlers = PublicHandlers{
        .directory = .{ .ctx = &ctx },
        .guard = .{ .ctx = &ctx },
        .approval = .{ .ctx = &ctx },
    };
    const result = try ability.with(runtime, .{
        .directory = example.directory.use(.{ .handler = handlers.directory }),
        .guard = example.guard.use(.{ .handler = handlers.guard }),
        .approval = example.approval.use(.{ .handler = handlers.approval }),
    }, example.approval_runtime_body);
    try semantic_trace.recordOutput(&ctx.trace, result.value);
    return .{
        .value = result.value,
        .transcript = ctx.transcript,
        .trace = ctx.trace,
    };
}

fn runProgramWorkflowCase(
    runtime: *ability.Runtime,
    exists_value: bool,
    branch: DirectBranch,
) anyerror!struct {
    value: []const u8,
    transcript: ExpectedTranscript,
    trace: semantic_trace.Snapshot,
} {
    var ctx = PublicContext{
        .exists_value = exists_value,
        .branch = branch,
    };
    const result = try PublicWorkflowProgram.run(runtime, .{
        .directory = example.directory.use(.{ .handler = PublicDirectoryHandler{ .ctx = &ctx } }),
        .guard = example.guard.use(.{ .handler = PublicGuardHandler{ .ctx = &ctx } }),
        .approval = example.approval.use(.{ .handler = PublicApprovalHandler{ .ctx = &ctx } }),
    });
    try semantic_trace.recordOutput(&ctx.trace, result.value);
    return .{
        .value = result.value,
        .transcript = ctx.transcript,
        .trace = ctx.trace,
    };
}

fn booleanBangBranchSpec() ability_compile.lowering_api.LowerSpec {
    return .{
        .label = "test.boolean_bang_branch",
        .entry_symbol = "runBody",
        .row = ability_compile.effect_ir.rowFromSpec(.{
            .flag = .{
                .check = ability_compile.effect_ir.Transform(void, bool),
                .mark = ability_compile.effect_ir.Transform(void, void),
            },
        }),
        .ValueType = void,
    };
}

fn numericBangBranchSpec() ability_compile.lowering_api.LowerSpec {
    return .{
        .label = "test.numeric_bang_branch",
        .entry_symbol = "runBody",
        .row = ability_compile.effect_ir.rowFromSpec(.{
            .counter = .{
                .remaining = ability_compile.effect_ir.Transform(void, i32),
                .done = ability_compile.effect_ir.Transform(void, void),
            },
        }),
        .ValueType = void,
    };
}

test "custom approval workflow approves through public custom-effect transcript" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try example.runApprove(&runtime);
    try std.testing.expectEqualStrings("published:approved", result.value);
    try expectTranscript(result.transcript, .{
        .lookups = 2,
        .choices = 1,
        .continuations = 1,
        .aborts = 0,
        .last_lookup = "publish-7",
        .last_choice = "request-7",
        .last_abort = "",
    });
}

test "custom approval workflow denies without recording a continuation" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try example.runDeny(&runtime);
    try std.testing.expectEqualStrings("denied", result.value);
    try expectTranscript(result.transcript, .{
        .lookups = 1,
        .choices = 1,
        .continuations = 0,
        .aborts = 0,
        .last_lookup = "request-7",
        .last_choice = "request-7",
        .last_abort = "",
    });
}

test "custom approval workflow source plan performs the resumed directory check only on approve" {
    comptime {
        const plan = LoweredWorkflow.runtime_plan;
        var directory_exists_op: ?u16 = null;
        for (plan.ops, 0..) |op, op_index| {
            const requirement = plan.requirements[op.requirement_index];
            if (std.mem.eql(u8, requirement.label, "directory") and std.mem.eql(u8, op.op_name, "exists")) {
                directory_exists_op = @intCast(op_index);
            }
        }
        const op_index = directory_exists_op orelse @compileError("custom workflow plan must keep directory.exists");
        var directory_call_count: usize = 0;
        for (plan.instructions) |instruction| {
            if (instruction.kind == .call_op and instruction.operand == op_index) directory_call_count += 1;
        }
        if (directory_call_count != 2) @compileError("approve continuation must preserve the second directory.exists call");
    }

    var approve_runtime = ability.Runtime.init(std.testing.allocator);
    defer approve_runtime.deinit();
    const approved = try runLoweredWorkflowCase(&approve_runtime, true, .approve);
    try std.testing.expectEqual(@as(usize, 2), approved.transcript.lookups);
    try std.testing.expectEqualStrings("publish-7", approved.transcript.last_lookup);

    var deny_runtime = ability.Runtime.init(std.testing.allocator);
    defer deny_runtime.deinit();
    const denied = try runLoweredWorkflowCase(&deny_runtime, true, .deny);
    try std.testing.expectEqual(@as(usize, 1), denied.transcript.lookups);
    try std.testing.expectEqualStrings("request-7", denied.transcript.last_lookup);

    var invalid_runtime = ability.Runtime.init(std.testing.allocator);
    defer invalid_runtime.deinit();
    const invalid = try runLoweredWorkflowCase(&invalid_runtime, false, .approve);
    try std.testing.expectEqual(@as(usize, 1), invalid.transcript.lookups);
    try std.testing.expectEqualStrings("request-7", invalid.transcript.last_lookup);
}

test "custom approval workflow aborts invalid requests before choice" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try example.runInvalid(&runtime);
    try std.testing.expectEqualStrings("invalid:missing", result.value);
    try expectTranscript(result.transcript, .{
        .lookups = 1,
        .choices = 0,
        .continuations = 0,
        .aborts = 1,
        .last_lookup = "request-7",
        .last_choice = "",
        .last_abort = "missing",
    });
}

test "custom approval workflow source lowers to executable ProgramPlan" {
    comptime {
        const plan = LoweredWorkflow.runtime_plan;
        if (!std.mem.eql(u8, plan.label, "example.custom_approval_workflow")) @compileError("custom workflow plan label drifted");
        var saw_directory_exists = false;
        var directory_exists_has_after = false;
        var saw_approval_request = false;
        var approval_request_has_after = false;
        var saw_guard_invalid = false;
        var guard_invalid_has_after = false;
        for (plan.ops) |op| {
            const requirement = plan.requirements[op.requirement_index];
            if (std.mem.eql(u8, requirement.label, "directory") and std.mem.eql(u8, op.op_name, "exists")) {
                saw_directory_exists = true;
                directory_exists_has_after = op.has_after;
            }
            if (std.mem.eql(u8, requirement.label, "approval") and std.mem.eql(u8, op.op_name, "request")) {
                saw_approval_request = true;
                approval_request_has_after = op.has_after;
            }
            if (std.mem.eql(u8, requirement.label, "guard") and std.mem.eql(u8, op.op_name, "invalid")) {
                saw_guard_invalid = true;
                guard_invalid_has_after = op.has_after;
            }
        }
        if (!saw_directory_exists) @compileError("custom workflow plan must keep the directory.exists transform op");
        if (!saw_approval_request) @compileError("custom workflow plan must keep the approval.request choice op");
        if (!saw_guard_invalid) @compileError("custom workflow plan must keep the guard.invalid abort op");
        if (directory_exists_has_after) @compileError("source-backed value-binding transform ops must not imply after hooks without a continuation witness");
        if (!approval_request_has_after) @compileError("source-backed choice ops with explicit continuations must preserve after-hook capability");
        if (guard_invalid_has_after) @compileError("source-backed abort ops must not enqueue after hooks");
        if (plan.functions.len == 0) @compileError("custom workflow plan must include lowered function rows");
        if (plan.blocks.len == 0) @compileError("custom workflow plan must include executable blocks");
        if (plan.terminators.len == 0) @compileError("custom workflow plan must include executable terminators");
        if (plan.instructions.len == 0) @compileError("custom workflow plan must include executable instructions");
        if (plan.functions[plan.entry_index].value_codec != .string) @compileError("custom workflow entry must return a string");
    }

    try LoweredWorkflow.runtime_plan.validate();
}

test "custom approval workflow public program exposes executable ProgramPlan and ArtifactV1" {
    comptime {
        const plan = PublicWorkflowProgram.runtime_plan;
        if (!std.mem.eql(u8, plan.label, "example.custom_approval_workflow.public_program")) @compileError("public workflow program label drifted");
        if (plan.functions.len == 0) @compileError("public workflow program must include lowered function rows");
        if (plan.blocks.len == 0) @compileError("public workflow program must include executable blocks");
        if (plan.terminators.len == 0) @compileError("public workflow program must include executable terminators");
        if (plan.instructions.len == 0) @compileError("public workflow program must include executable instructions");
        plan.validate() catch |err| @compileError(@errorName(err));
    }

    var public_runtime = ability.Runtime.init(std.testing.allocator);
    defer public_runtime.deinit();
    var program_runtime = ability.Runtime.init(std.testing.allocator);
    defer program_runtime.deinit();

    const public_result = try runPublicWorkflowCase(&public_runtime, true, .approve);
    const program_result = try runProgramWorkflowCase(&program_runtime, true, .approve);
    try std.testing.expectEqualStrings(public_result.value, program_result.value);
    try expectTranscript(public_result.transcript, program_result.transcript);
    try semantic_trace.expectEqualSnapshot(public_result.trace, program_result.trace);

    const bytes = try PublicWorkflowProgram.encode(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var decoded_with_plan = try ability_compile.artifact.decodeWithProgramPlan(std.testing.allocator, bytes);
    defer decoded_with_plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(PublicWorkflowProgram.ir_hash, decoded_with_plan.artifact.semantic_ir_hash64);
    try decoded_with_plan.plan.validate();
}

test "custom approval workflow agrees across public and direct ProgramPlan approval branches" {
    var public_runtime = ability.Runtime.init(std.testing.allocator);
    defer public_runtime.deinit();
    var lowered_runtime = ability.Runtime.init(std.testing.allocator);
    defer lowered_runtime.deinit();

    const public_result = try runPublicWorkflowCase(&public_runtime, true, .approve);
    const lowered_result = try runLoweredWorkflowCase(&lowered_runtime, true, .approve);

    try std.testing.expectEqualStrings(public_result.value, lowered_result.value);
    try expectTranscript(public_result.transcript, lowered_result.transcript);
    try expectBranchTrace(public_result.trace, .approve);
    try semantic_trace.expectEqualSnapshot(public_result.trace, lowered_result.trace);
}

test "custom approval workflow agrees across public and direct ProgramPlan terminal branches" {
    var public_runtime = ability.Runtime.init(std.testing.allocator);
    defer public_runtime.deinit();
    var lowered_runtime = ability.Runtime.init(std.testing.allocator);
    defer lowered_runtime.deinit();

    const public_denied = try runPublicWorkflowCase(&public_runtime, true, .deny);
    const lowered_denied = try runLoweredWorkflowCase(&lowered_runtime, true, .deny);
    try std.testing.expectEqualStrings(public_denied.value, lowered_denied.value);
    try expectTranscript(public_denied.transcript, lowered_denied.transcript);
    try expectBranchTrace(public_denied.trace, .deny);
    try semantic_trace.expectEqualSnapshot(public_denied.trace, lowered_denied.trace);

    const public_invalid = try runPublicWorkflowCase(&public_runtime, false, .approve);
    const lowered_invalid = try runLoweredWorkflowCase(&lowered_runtime, false, .approve);
    try std.testing.expectEqualStrings(public_invalid.value, lowered_invalid.value);
    try expectTranscript(public_invalid.transcript, lowered_invalid.transcript);
    try expectBranchTrace(public_invalid.trace, .invalid);
    try semantic_trace.expectEqualSnapshot(public_invalid.trace, lowered_invalid.trace);
}

test "custom approval workflow ArtifactV1 encode decode preserves custom capabilities" {
    const allocator = std.testing.allocator;
    const bytes = try CompiledWorkflowArtifact.encode(allocator);
    defer allocator.free(bytes);

    var decoded = try CompiledWorkflowArtifact.decode(allocator, bytes);
    defer decoded.deinit(allocator);
    try std.testing.expectEqual(CompiledWorkflowArtifact.ir_hash, decoded.semantic_ir_hash64);
    try std.testing.expectEqual(@as(usize, 4), decoded.capabilities.len);

    var decoded_with_plan = try ability_compile.artifact.decodeWithProgramPlan(allocator, bytes);
    defer decoded_with_plan.deinit(allocator);
    try decoded_with_plan.plan.validate();
}

test "custom workflow source lowering admits bang branches only for bool locals" {
    const BoolBang = comptime ability_compile.lowering_api.maybeLowerWithRootSourceAt(
        "test/boolean_bang_branch.zig",
        \\pub fn runBody(eff: anytype) anyerror!void {
        \\    const flag = try eff.flag.check();
        \\    if (!flag) try eff.flag.mark() else return;
        \\}
    ,
        &.{},
        booleanBangBranchSpec(),
    ) orelse @compileError("bool bang branch should stay in the source-backed subset");
    _ = BoolBang;

    const NumericBang = comptime ability_compile.lowering_api.maybeLowerWithRootSourceAt(
        "test/numeric_bang_branch.zig",
        \\pub fn runBody(eff: anytype) anyerror!void {
        \\    const count = try eff.counter.remaining();
        \\    if (!count) try eff.counter.done() else return;
        \\}
    ,
        &.{},
        numericBangBranchSpec(),
    );
    try std.testing.expect(NumericBang == null);

    const BoolEqZero = comptime ability_compile.lowering_api.maybeLowerWithRootSourceAt(
        "test/boolean_eq_zero_branch.zig",
        \\pub fn runBody(eff: anytype) anyerror!void {
        \\    const flag = try eff.flag.check();
        \\    if (flag == 0) try eff.flag.mark() else return;
        \\}
    ,
        &.{},
        booleanBangBranchSpec(),
    );
    try std.testing.expect(BoolEqZero == null);
}
