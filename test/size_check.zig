const prompt_support = @import("prompt_support");
const shift = @import("shift");
const shift_compile = @import("shift_compile");
const shift_vm = @import("shift_vm");
const std = @import("std");

fn hasErrorName(comptime ErrorSet: type, comptime wanted: []const u8) bool {
    inline for (@typeInfo(ErrorSet).error_set.?) |field| {
        if (comptime std.mem.eql(u8, field.name, wanted)) return true;
    }
    return false;
}

test "prompt shell stays compact" {
    const NoError = error{};
    const DemoPrompt = prompt_support.Prompt(.resume_then_transform, void, void, NoError);
    try std.testing.expect(@sizeOf(DemoPrompt) <= @sizeOf(usize));
}

test "public root keeps only the lexical surface" {
    try std.testing.expect(@hasDecl(shift, "effect"));
    try std.testing.expect(@hasDecl(shift, "With"));
    try std.testing.expect(@hasDecl(shift, "with"));
    try std.testing.expect(@hasDecl(shift, "Runtime"));
    try std.testing.expect(@hasDecl(shift, "RuntimeError"));

    try std.testing.expect(!@hasDecl(shift, "compat"));
    try std.testing.expect(!@hasDecl(shift, "durable"));
    try std.testing.expect(!@hasDecl(shift, "interpreter"));
    try std.testing.expect(!@hasDecl(shift, "lowering"));
    try std.testing.expect(!@hasDecl(shift, "lower"));
    try std.testing.expect(!@hasDecl(shift, "ir"));
    try std.testing.expect(!@hasDecl(shift, "ErrorWitnessV1"));
    try std.testing.expect(!@hasDecl(shift, "Decl"));
    try std.testing.expect(!@hasDecl(shift, "Op"));
    try std.testing.expect(!@hasDecl(shift, "Decision"));
    try std.testing.expect(!@hasDecl(shift, "Program"));
    try std.testing.expect(!@hasDecl(shift, "run"));

    try std.testing.expect(!@hasDecl(shift, "Transform"));
    try std.testing.expect(!@hasDecl(shift, "Choice"));
    try std.testing.expect(!@hasDecl(shift, "Abort"));
    try std.testing.expect(!@hasDecl(shift, "RunResult"));
    try std.testing.expect(!@hasDecl(shift, "Row"));
    try std.testing.expect(!@hasDecl(shift, "mergeRows"));
    try std.testing.expect(!@hasDecl(shift, "effects"));
    try std.testing.expect(!@hasDecl(shift, "handlers"));
    try std.testing.expect(!@hasDecl(shift, "Uses"));
    try std.testing.expect(!@hasDecl(shift, "handle"));
    try std.testing.expect(!@hasDecl(shift, "bind"));
    try std.testing.expect(!@hasDecl(shift, "Ops"));
    try std.testing.expect(!@hasDecl(shift, "NoShiftGuard"));
    try std.testing.expect(!@hasDecl(shift, "Continuation"));
    try std.testing.expect(!@hasDecl(shift, "parity_machine"));
    try std.testing.expect(!@hasDecl(shift, "ResumeOrReturn"));
    try std.testing.expect(!@hasDecl(shift, "algebraic"));
    try std.testing.expect(!@hasDecl(shift, "ordinary"));

    try std.testing.expect(!@hasDecl(shift, "lowerAt"));
}

test "shift_compile keeps the explicit compile surface" {
    try std.testing.expect(@hasDecl(shift_compile, "ir"));
    try std.testing.expect(@hasDecl(shift_compile, "lowering"));
    try std.testing.expect(@hasDecl(shift_compile, "lower"));
    try std.testing.expect(@hasDecl(shift_compile.ir, "compile"));
    try std.testing.expect(!@hasDecl(shift_compile, "effect"));
    try std.testing.expect(!@hasDecl(shift_compile, "Runtime"));
    try std.testing.expect(!@hasDecl(shift_compile, "RuntimeError"));
    try std.testing.expect(!@hasDecl(shift_compile, "With"));
    try std.testing.expect(!@hasDecl(shift_compile, "with"));
    try std.testing.expect(!@hasDecl(shift_compile, "durable"));
    try std.testing.expect(!@hasDecl(shift_compile, "interpreter"));
    try std.testing.expect(!@hasDecl(shift_compile, "Program"));
    try std.testing.expect(!@hasDecl(shift_compile, "run"));

    try std.testing.expect(!@hasDecl(shift_compile.lowering, "openRow"));
    try std.testing.expect(!@hasDecl(shift_compile.lowering, "OpenRowProgram"));
    try std.testing.expect(!@hasDecl(shift_compile.lowering, "LoweredProgram"));
    try std.testing.expect(!@hasDecl(shift_compile.lowering, "ProgramPlan"));
    try std.testing.expect(!@hasDecl(shift_compile.lowering, "lowerOpenRow"));
    try std.testing.expect(!@hasDecl(shift_compile.lowering, "irProgram"));
    try std.testing.expect(!@hasDecl(shift_compile.lowering, "validateFileBackedOpenRow"));
    try std.testing.expect(!@hasDecl(shift_compile.lowering, "CompileOpenRow"));
    try std.testing.expect(!@hasDecl(shift_compile.lowering, "CompileOpenRowAt"));
    try std.testing.expect(@hasDecl(shift_compile.lowering, "source"));
}

test "shift_vm keeps runtime and compatibility surfaces" {
    try std.testing.expect(@hasDecl(shift_vm, "compat"));
    try std.testing.expect(@hasDecl(shift_vm, "durable"));
    try std.testing.expect(@hasDecl(shift_vm, "interpreter"));
    try std.testing.expect(@hasDecl(shift_vm, "ErrorWitnessV1"));
    try std.testing.expect(@hasDecl(shift_vm, "Runtime"));
    try std.testing.expect(@hasDecl(shift_vm, "RuntimeError"));
    try std.testing.expect(@hasDecl(shift_vm, "Decl"));
    try std.testing.expect(@hasDecl(shift_vm, "Op"));
    try std.testing.expect(@hasDecl(shift_vm, "Decision"));
    try std.testing.expect(@hasDecl(shift_vm, "Program"));
    try std.testing.expect(@hasDecl(shift_vm, "run"));

    try std.testing.expect(!@hasDecl(shift_vm, "effect"));
    try std.testing.expect(!@hasDecl(shift_vm, "With"));
    try std.testing.expect(!@hasDecl(shift_vm, "with"));
    try std.testing.expect(!@hasDecl(shift_vm, "ir"));
    try std.testing.expect(!@hasDecl(shift_vm, "lowering"));
    try std.testing.expect(!@hasDecl(shift_vm, "lower"));
}

test "shift.ir preserves the prior effect_ir compatibility surface" {
    try std.testing.expect(@hasDecl(shift_compile.ir, "Program"));
    try std.testing.expect(@hasDecl(shift_compile.ir, "compile"));
    try std.testing.expect(@hasDecl(shift_compile.ir, "ControlMode"));
    try std.testing.expect(@hasDecl(shift_compile.ir, "OpSpec"));
    try std.testing.expect(@hasDecl(shift_compile.ir, "Requirement"));
    try std.testing.expect(@hasDecl(shift_compile.ir, "NormalizeError"));

    try std.testing.expect(hasErrorName(shift_compile.ir.NormalizeError, "DuplicateRequirementLabel"));
    try std.testing.expect(hasErrorName(shift_compile.ir.NormalizeError, "OutputWithoutRequirement"));
}

test "public interpreter runs pure step data without host runtime ownership" {
    const state = shift_vm.interpreter.runSteps(&.{
        .{ .set_active_prompt = .primary },
        .{ .emit = .{ .note = "queued" } },
        .{ .set_final = .{ .string = "done" } },
    });

    try std.testing.expectEqual(@as(usize, 1), shift_vm.interpreter.events(&state).len);
    try std.testing.expectEqual(@as(usize, 0), shift_vm.interpreter.checkpoints(&state).len);
    try std.testing.expectEqual(@as(?shift_vm.interpreter.PromptId, .primary), state.active_prompt);
}

test "public additive lowering exposes the retained runtime-owned plan" {
    const spec: shift_compile.lowering.LowerSpec = .{
        .label = "example.open_row_state_writer",
        .entry_symbol = "runBody",
        .row = shift_compile.ir.mergeRows(.{
            shift_compile.ir.rowFromSpec(.{
                .state = .{
                    .get = shift_compile.ir.Transform(void, i32),
                    .set = shift_compile.ir.Transform(i32, void),
                },
            }),
            shift_compile.ir.rowFromSpec(.{
                .writer = .{
                    .tell = shift_compile.ir.Transform([]const u8, void),
                },
            }),
        }),
        .ValueType = []const u8,
        .outputs = &.{
            .{ .label = "state", .OutputType = i32 },
            .{ .label = "writer", .OutputType = [][]const u8 },
        },
    };

    const lowered = shift_compile.lowering.lowerAt("examples/open_row_state_writer.zig", spec);
    const explicit = shift_compile.ir.compile(spec.label, shift_compile.lowering.irProgramAt("examples/open_row_state_writer.zig", spec));

    try std.testing.expectEqualStrings("example.open_row_state_writer", lowered.label);
    try std.testing.expectEqualStrings("runBody", lowered.entry_symbol);
    try std.testing.expectEqualStrings("examples/open_row_state_writer.zig", lowered.source_path);
    try std.testing.expectEqual(@as(usize, 3), lowered.runtime_plan.functions.len);
    try std.testing.expectEqual(@as(usize, 5), lowered.runtime_plan.requirements.len);
    try std.testing.expectEqual(@as(usize, 7), lowered.runtime_plan.ops.len);

    try std.testing.expectEqual(lowered.ir_hash, explicit.ir_hash);
    try std.testing.expectEqual(@as(usize, lowered.runtime_plan.functions.len), explicit.runtime_plan.functions.len);
    try std.testing.expectEqual(@as(usize, lowered.runtime_plan.requirements.len), explicit.runtime_plan.requirements.len);
    try std.testing.expectEqual(@as(usize, lowered.runtime_plan.ops.len), explicit.runtime_plan.ops.len);
}

test "public runtime error surface still exposes the current contract" {
    try std.testing.expect(hasErrorName(shift.RuntimeError, "MissingPrompt"));
    try std.testing.expect(hasErrorName(shift.RuntimeError, "CrossThread"));
    try std.testing.expect(hasErrorName(shift.RuntimeError, "RuntimeBusy"));
    try std.testing.expect(hasErrorName(shift.RuntimeError, "RuntimeDestroyed"));
    try std.testing.expect(hasErrorName(shift.RuntimeError, "NonDiagonalComplete"));
    try std.testing.expect(hasErrorName(shift.RuntimeError, "FrontendSuspend"));
    try std.testing.expect(hasErrorName(shift.RuntimeError, "ProgramContractViolation"));
    try std.testing.expect(!hasErrorName(shift.RuntimeError, "AlreadyResolved"));
    try std.testing.expect(!hasErrorName(shift.RuntimeError, "NestedNonDiagonalCapture"));
}

test "front-door op shells stay compact" {
    const Transform = shift_vm.Op.Transform("get", void, i32);
    const Choice = shift_vm.Op.Choice("pick", bool, []const u8);
    const Abort = shift_vm.Op.Abort("fail", []const u8);

    try std.testing.expectEqual(@as(usize, 0), @sizeOf(Transform));
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(Choice));
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(Abort));
}

test "lexical root stays executable through shift.effect plus shift.with" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .state = shift.effect.state.use(@as(i32, 3)),
        .writer = shift.effect.writer.use([]const u8, std.testing.allocator),
    }, struct {
        /// Execute the size-check workflow through the public lexical surface.
        pub fn body(eff: anytype) anyerror![]const u8 {
            const before = try eff.state.get();
            try eff.state.set(before + 1);
            try eff.writer.tell("queued");
            return "done";
        }
    });
    defer std.testing.allocator.free(result.outputs.writer);

    try std.testing.expectEqual(@as(i32, 4), result.outputs.state);
    try std.testing.expectEqual(@as(usize, 1), result.outputs.writer.len);
    try std.testing.expectEqualStrings("queued", result.outputs.writer[0]);
    try std.testing.expectEqualStrings("done", result.value);
}

test "compat kernel stays executable through shift.compat.Program plus shift.compat.run" {
    const WorkflowProgram = shift_vm.Program(.{
        .state = shift_vm.Decl.state(i32),
        .writer = shift_vm.Decl.writer([]const u8),
    }, struct {
        /// Execute the size-check workflow through the compatibility kernel surface.
        pub fn body(eff: anytype) anyerror![]const u8 {
            const before = try eff.state.get();
            try eff.state.set(before + 1);
            try eff.writer.tell("queued");
            return "done";
        }
    });

    var runtime = shift_vm.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift_vm.run(&runtime, WorkflowProgram, .{ .state = 3 });
    defer std.testing.allocator.free(result.outputs.writer);

    try std.testing.expectEqual(@as(i32, 4), result.outputs.state);
    try std.testing.expectEqual(@as(usize, 1), result.outputs.writer.len);
    try std.testing.expectEqualStrings("queued", result.outputs.writer[0]);
    try std.testing.expectEqualStrings("done", result.value);
}
