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

test "public root exposes only the current front door" {
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
    try std.testing.expect(!@hasDecl(shift, "effect"));
    try std.testing.expect(!@hasDecl(shift, "algebraic"));
    try std.testing.expect(!@hasDecl(shift, "ordinary"));
    try std.testing.expect(!@hasDecl(shift, "with"));
    try std.testing.expect(!@hasDecl(shift, "With"));
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

test "program root stays executable through Program plus run" {
    const WorkflowProgram = shift.Program(.{
        .state = shift.Decl.state(i32),
        .writer = shift.Decl.writer([]const u8),
    }, struct {
        /// Execute the size-check workflow through the public program surface.
        pub fn body(eff: anytype) anyerror![]const u8 {
            const before = try eff.state.get();
            try eff.state.set(before + 1);
            try eff.writer.tell("queued");
            return "done";
        }
    });

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.run(&runtime, WorkflowProgram, .{ .state = 3 });
    defer std.testing.allocator.free(result.outputs.writer);

    try std.testing.expectEqual(@as(i32, 4), result.outputs.state);
    try std.testing.expectEqual(@as(usize, 1), result.outputs.writer.len);
    try std.testing.expectEqualStrings("queued", result.outputs.writer[0]);
    try std.testing.expectEqualStrings("done", result.value);
}
