const prompt_support = @import("prompt_support");
const shift = @import("shift");
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

test "public root keeps the lexical surface, additive lowering, and compatibility aliases" {
    try std.testing.expect(@hasDecl(shift, "compat"));
    try std.testing.expect(@hasDecl(shift, "durable"));
    try std.testing.expect(@hasDecl(shift, "effect"));
    try std.testing.expect(@hasDecl(shift, "interpreter"));
    try std.testing.expect(@hasDecl(shift, "lowering"));
    try std.testing.expect(@hasDecl(shift, "lower"));
    try std.testing.expect(@hasDecl(shift, "lowerAt"));
    try std.testing.expect(@hasDecl(shift, "With"));
    try std.testing.expect(@hasDecl(shift, "with"));
    try std.testing.expect(@hasDecl(shift, "ir"));
    try std.testing.expect(@hasDecl(shift.ir, "compile"));

    try std.testing.expect(@hasDecl(shift, "Runtime"));
    try std.testing.expect(@hasDecl(shift, "RuntimeError"));
    try std.testing.expect(@hasDecl(shift, "ErrorWitnessV1"));
    try std.testing.expect(@hasDecl(shift, "Decl"));
    try std.testing.expect(@hasDecl(shift, "Op"));
    try std.testing.expect(@hasDecl(shift, "Decision"));
    try std.testing.expect(@hasDecl(shift, "Program"));
    try std.testing.expect(@hasDecl(shift, "run"));

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

    try std.testing.expect(@hasDecl(shift.compat, "Runtime"));
    try std.testing.expect(@hasDecl(shift.compat, "RuntimeError"));
    try std.testing.expect(@hasDecl(shift.compat, "ErrorWitnessV1"));
    try std.testing.expect(@hasDecl(shift.compat, "Decl"));
    try std.testing.expect(@hasDecl(shift.compat, "Op"));
    try std.testing.expect(@hasDecl(shift.compat, "Decision"));
    try std.testing.expect(@hasDecl(shift.compat, "Program"));
    try std.testing.expect(@hasDecl(shift.compat, "run"));
    try std.testing.expect(!@hasDecl(shift.compat, "effect"));
    try std.testing.expect(!@hasDecl(shift.compat, "interpreter"));
    try std.testing.expect(!@hasDecl(shift.compat, "durable"));
    try std.testing.expect(!@hasDecl(shift.compat, "lower"));
    try std.testing.expect(!@hasDecl(shift.compat, "lowerAt"));
    try std.testing.expect(!@hasDecl(shift.compat, "lowering"));
    try std.testing.expect(!@hasDecl(shift.compat, "With"));
    try std.testing.expect(!@hasDecl(shift.compat, "with"));
    try std.testing.expect(!@hasDecl(shift.compat, "ir"));

    try std.testing.expect(!@hasDecl(shift.lowering, "openRow"));
    try std.testing.expect(!@hasDecl(shift.lowering, "OpenRowProgram"));
    try std.testing.expect(!@hasDecl(shift.lowering, "LoweredProgram"));
    try std.testing.expect(!@hasDecl(shift.lowering, "ProgramPlan"));
    try std.testing.expect(!@hasDecl(shift.lowering, "lowerOpenRow"));
    try std.testing.expect(!@hasDecl(shift.lowering, "irProgram"));
    try std.testing.expect(!@hasDecl(shift.lowering, "validateFileBackedOpenRow"));
    try std.testing.expect(!@hasDecl(shift.lowering, "CompileOpenRow"));
    try std.testing.expect(!@hasDecl(shift.lowering, "CompileOpenRowAt"));
    try std.testing.expect(@hasDecl(shift.lowering, "source"));
}

test "public interpreter runs pure step data without host runtime ownership" {
    const state = shift.interpreter.runSteps(&.{
        .{ .set_active_prompt = .primary },
        .{ .emit = .{ .note = "queued" } },
        .{ .set_final = .{ .string = "done" } },
    });

    try std.testing.expectEqual(@as(usize, 1), shift.interpreter.events(&state).len);
    try std.testing.expectEqual(@as(usize, 0), shift.interpreter.checkpoints(&state).len);
    try std.testing.expectEqual(@as(?shift.interpreter.PromptId, .primary), state.active_prompt);
}

test "public additive lowering exposes the retained runtime-owned plan" {
    const spec: shift.lowering.LowerSpec = .{
        .label = "example.open_row_state_writer",
        .entry_symbol = "runBody",
        .row = shift.ir.mergeRows(.{
            shift.ir.rowFromSpec(.{
                .state = .{
                    .get = shift.ir.Transform(void, i32),
                    .set = shift.ir.Transform(i32, void),
                },
            }),
            shift.ir.rowFromSpec(.{
                .writer = .{
                    .tell = shift.ir.Transform([]const u8, void),
                },
            }),
        }),
        .ValueType = []const u8,
        .outputs = &.{
            .{ .label = "state", .OutputType = i32 },
            .{ .label = "writer", .OutputType = [][]const u8 },
        },
    };

    const lowered = shift.lowerAt("examples/open_row_state_writer.zig", spec);
    const explicit = shift.ir.compile(spec.label, shift.lowering.irProgramAt("examples/open_row_state_writer.zig", spec));

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
    const Transform = shift.Op.Transform("get", void, i32);
    const Choice = shift.Op.Choice("pick", bool, []const u8);
    const Abort = shift.Op.Abort("fail", []const u8);

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
    const WorkflowProgram = shift.compat.Program(.{
        .state = shift.compat.Decl.state(i32),
        .writer = shift.compat.Decl.writer([]const u8),
    }, struct {
        /// Execute the size-check workflow through the compatibility kernel surface.
        pub fn body(eff: anytype) anyerror![]const u8 {
            const before = try eff.state.get();
            try eff.state.set(before + 1);
            try eff.writer.tell("queued");
            return "done";
        }
    });

    var runtime = shift.compat.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.compat.run(&runtime, WorkflowProgram, .{ .state = 3 });
    defer std.testing.allocator.free(result.outputs.writer);

    try std.testing.expectEqual(@as(i32, 4), result.outputs.state);
    try std.testing.expectEqual(@as(usize, 1), result.outputs.writer.len);
    try std.testing.expectEqualStrings("queued", result.outputs.writer[0]);
    try std.testing.expectEqualStrings("done", result.value);
}
