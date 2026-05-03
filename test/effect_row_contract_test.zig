const ability = @import("ability");
const ability_compile = @import("ability_compile");
const example = @import("example_custom_approval_workflow");
const semantic_trace = @import("support/semantic_trace.zig");
const std = @import("std");

const ExpectedOp = struct {
    requirement: []const u8,
    op_name: []const u8,
    mode: ability_compile.effect_ir.ControlMode,
    PayloadType: type,
    ResumeType: type,
    has_after: bool,
};

const directory_handler = struct {
    /// Handle the generated directory lookup transform.
    pub fn exists(_: *@This(), _: []const u8) bool {
        return true;
    }
};

const approval_handler = struct {
    /// Handle the generated approval choice.
    pub fn request(_: *@This(), _: []const u8) ability.effect.choice.Decision([]const u8, []const u8) {
        return ability.effect.choice.Decision([]const u8, []const u8).resumeWith("approved");
    }

    /// Preserve the workflow answer after approval continuation replay.
    pub fn afterRequest(_: *@This(), answer: []const u8) []const u8 {
        return answer;
    }
};

const guard_handler = struct {
    /// Handle the generated guard abort.
    pub fn invalid(_: *@This(), _: []const u8) []const u8 {
        return "invalid:missing";
    }
};

const DirectoryBinding = @TypeOf(example.directory.use(.{ .handler = directory_handler{} })).BindingSchema("directory");
const ApprovalBinding = @TypeOf(example.approval.use(.{ .handler = approval_handler{} })).BindingSchema("approval");
const GuardBinding = @TypeOf(example.guard.use(.{ .handler = guard_handler{} })).BindingSchema("guard");

const generated_effect_row = ability_compile.effect_ir.mergeRows(.{
    ability_compile.effect_schema.row(DirectoryBinding),
    ability_compile.effect_schema.row(ApprovalBinding),
    ability_compile.effect_schema.row(GuardBinding),
});

fn workflowLoweringSpec() ability_compile.lowering_api.LowerSpec {
    return .{
        .label = "example.custom_approval_workflow.effect_row_contract",
        .entry_symbol = "approvalRuntimeBody",
        .row = generated_effect_row,
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
const CompiledGeneratedRowArtifact = ability.compile(
    "example.custom_approval_workflow.effect_row_contract",
    LoweredWorkflow.runtime_plan,
    .{ .stable_build_fingerprint_seed = "effect-row-contract-generated-row" },
);
const DirectBranch = enum { approve, deny };

fn findRowOp(comptime requirement: []const u8, comptime op_name: []const u8) ability_compile.effect_ir.OpSpec {
    inline for (generated_effect_row.requirements) |row_requirement| {
        if (std.mem.eql(u8, row_requirement.label, requirement)) {
            inline for (row_requirement.ops) |op| {
                if (std.mem.eql(u8, op.op_name, op_name)) return op;
            }
        }
    }
    @compileError("missing expected generated effect row op: " ++ requirement ++ "." ++ op_name);
}

fn expectRowOp(comptime expected: ExpectedOp) void {
    const op = comptime findRowOp(expected.requirement, expected.op_name);
    if (op.mode != expected.mode) @compileError("generated effect row op mode drifted");
    if (op.PayloadType != expected.PayloadType) @compileError("generated effect row payload type drifted");
    if (op.ResumeType != expected.ResumeType) @compileError("generated effect row resume type drifted");
    if (op.has_after != expected.has_after) @compileError("generated effect row after-hook metadata drifted");
}

fn expectPlanOp(comptime plan: ability_compile.lowering_api.ProgramPlan, comptime expected: ExpectedOp) void {
    inline for (plan.ops) |op| {
        const requirement = plan.requirements[op.requirement_index];
        if (std.mem.eql(u8, requirement.label, expected.requirement) and std.mem.eql(u8, op.op_name, expected.op_name)) {
            switch (expected.mode) {
                .abort => if (op.mode != .abort) @compileError("ProgramPlan op mode drifted from generated effect row"),
                .choice => if (op.mode != .choice) @compileError("ProgramPlan op mode drifted from generated effect row"),
                .transform => if (op.mode != .transform) @compileError("ProgramPlan op mode drifted from generated effect row"),
            }
            if (op.has_after != expected.has_after) @compileError("ProgramPlan after-hook metadata drifted from generated effect row");
            return;
        }
    }
    @compileError("missing expected ProgramPlan op: " ++ expected.requirement ++ "." ++ expected.op_name);
}

const DirectDirectoryHandler = struct {
    exists_value: bool,
    trace: *semantic_trace.Snapshot,

    /// Records the row-derived direct ProgramPlan directory lookup.
    pub fn exists(self: *@This(), payload: []const u8) bool {
        semantic_trace.recordDirectoryExists(self.trace, payload, self.exists_value);
        return self.exists_value;
    }
};

const DirectApprovalHandler = struct {
    branch: DirectBranch,
    trace: *semantic_trace.Snapshot,

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

    /// Records the row-derived direct ProgramPlan approval choice.
    pub fn request(self: *@This(), payload: []const u8) Decision {
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

    /// Records the row-derived direct ProgramPlan approval after hook.
    pub fn afterRequest(self: *@This(), answer: []const u8) []const u8 {
        semantic_trace.recordAfterRequest(self.trace, answer);
        return answer;
    }
};

const DirectGuardHandler = struct {
    trace: *semantic_trace.Snapshot,

    /// Records the row-derived direct ProgramPlan guard abort.
    pub fn invalid(self: *@This(), payload: []const u8) []const u8 {
        semantic_trace.recordGuardInvalid(self.trace, payload, "invalid:missing");
        return "invalid:missing";
    }
};

fn runDirectGeneratedRowCase(
    runtime: *ability.Runtime,
    exists_value: bool,
    branch: DirectBranch,
) anyerror!struct {
    value: []const u8,
    trace: semantic_trace.Snapshot,
} {
    var trace: semantic_trace.Snapshot = .{};
    var handlers = .{
        .directory = DirectDirectoryHandler{ .exists_value = exists_value, .trace = &trace },
        .guard = DirectGuardHandler{ .trace = &trace },
        .approval = DirectApprovalHandler{ .branch = branch, .trace = &trace },
    };
    const result = try LoweredWorkflow.run(runtime, &handlers);
    const stable_value = try semantic_trace.stableWorkflowValue(result.value);
    try semantic_trace.recordOutput(&trace, stable_value);
    return .{ .value = stable_value, .trace = trace };
}

test "generated custom effects expose the expected explicit row contract" {
    comptime {
        if (generated_effect_row.requirements.len != 3) @compileError("custom effect row must keep directory, approval, and guard requirements");
        expectRowOp(.{
            .requirement = "directory",
            .op_name = "exists",
            .mode = .transform,
            .PayloadType = []const u8,
            .ResumeType = bool,
            .has_after = false,
        });
        expectRowOp(.{
            .requirement = "approval",
            .op_name = "request",
            .mode = .choice,
            .PayloadType = []const u8,
            .ResumeType = []const u8,
            .has_after = true,
        });
        expectRowOp(.{
            .requirement = "guard",
            .op_name = "invalid",
            .mode = .abort,
            .PayloadType = []const u8,
            .ResumeType = noreturn,
            .has_after = false,
        });
    }
}

test "generated effect row lowers to executable ProgramPlan shape" {
    comptime {
        const plan = LoweredWorkflow.runtime_plan;
        if (!std.mem.eql(u8, plan.label, "example.custom_approval_workflow.effect_row_contract")) @compileError("effect row contract plan label drifted");
        if (plan.functions.len == 0) @compileError("effect row contract plan must include lowered function rows");
        if (plan.blocks.len == 0) @compileError("effect row contract plan must include executable blocks");
        if (plan.terminators.len == 0) @compileError("effect row contract plan must include executable terminators");
        if (plan.instructions.len == 0) @compileError("effect row contract plan must include executable instructions");
        expectPlanOp(plan, .{
            .requirement = "directory",
            .op_name = "exists",
            .mode = .transform,
            .PayloadType = []const u8,
            .ResumeType = bool,
            .has_after = false,
        });
        expectPlanOp(plan, .{
            .requirement = "approval",
            .op_name = "request",
            .mode = .choice,
            .PayloadType = []const u8,
            .ResumeType = []const u8,
            .has_after = true,
        });
        expectPlanOp(plan, .{
            .requirement = "guard",
            .op_name = "invalid",
            .mode = .abort,
            .PayloadType = []const u8,
            .ResumeType = noreturn,
            .has_after = false,
        });
    }

    try LoweredWorkflow.runtime_plan.validate();
}

test "generated effect row ProgramPlan executes and decodes through ArtifactV1" {
    const allocator = std.testing.allocator;
    const bytes = try CompiledGeneratedRowArtifact.encode(allocator);
    defer allocator.free(bytes);

    var decoded_with_plan = try ability_compile.artifact.decodeWithProgramPlan(allocator, bytes);
    defer decoded_with_plan.deinit(allocator);
    try decoded_with_plan.plan.validate();

    var approve_runtime = ability.Runtime.init(allocator);
    defer approve_runtime.deinit();
    const direct_approve = try runDirectGeneratedRowCase(&approve_runtime, true, .approve);
    try std.testing.expectEqualStrings("published:approved", direct_approve.value);
    try semantic_trace.expectEqualSnapshot(direct_approve.trace, try semantic_trace.expectedCustomApprovalTrace(.approve));

    var deny_runtime = ability.Runtime.init(allocator);
    defer deny_runtime.deinit();
    const direct_deny = try runDirectGeneratedRowCase(&deny_runtime, true, .deny);
    try std.testing.expectEqualStrings("denied", direct_deny.value);
    try semantic_trace.expectEqualSnapshot(direct_deny.trace, try semantic_trace.expectedCustomApprovalTrace(.deny));

    var invalid_runtime = ability.Runtime.init(allocator);
    defer invalid_runtime.deinit();
    const direct_invalid = try runDirectGeneratedRowCase(&invalid_runtime, false, .approve);
    try std.testing.expectEqualStrings("invalid:missing", direct_invalid.value);
    try semantic_trace.expectEqualSnapshot(direct_invalid.trace, try semantic_trace.expectedCustomApprovalTrace(.invalid));
}
