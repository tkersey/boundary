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
    const DemoPrompt = shift.Prompt(.resume_then_transform, void, void, NoError);
    try std.testing.expect(@sizeOf(DemoPrompt) <= @sizeOf(usize));
}

test "guard and continuation surfaces are not public" {
    try std.testing.expect(!@hasDecl(shift, "NoShiftGuard"));
    try std.testing.expect(!@hasDecl(shift, "Continuation"));
    try std.testing.expect(!@hasDecl(shift, "parity_machine"));
    try std.testing.expect(@hasDecl(shift, "ResumeOrReturn"));
    try std.testing.expect(@hasDecl(shift, "effect"));
    try std.testing.expect(!@hasDecl(shift.effect.state, "Continuation"));
}

test "public runtime error surface still exposes the current raw contract" {
    try std.testing.expect(hasErrorName(shift.Error, "MissingPrompt"));
    try std.testing.expect(hasErrorName(shift.Error, "CrossThread"));
    try std.testing.expect(hasErrorName(shift.Error, "RuntimeBusy"));
    try std.testing.expect(hasErrorName(shift.Error, "RuntimeDestroyed"));
    try std.testing.expect(hasErrorName(shift.Error, "NonDiagonalComplete"));
    try std.testing.expect(!hasErrorName(shift.Error, "AlreadyResolved"));
    try std.testing.expect(!hasErrorName(shift.Error, "NestedNonDiagonalCapture"));
}

test "algebraic descriptor and context shells stay compact" {
    const NoError = error{};
    const no_state = struct {};
    const search = shift.algebraic.TransformOp("search", void, usize);
    const stop = shift.algebraic.AbortOp("stop", []const u8);
    const program = shift.algebraic.Program(usize, NoError, .{ search, stop });
    const Configured = @TypeOf(program.handlers(.{
        shift.algebraic.handleTransform(search, no_state{}, struct {
            /// Supply the compact transform witness value.
            pub fn resumeValue(_: no_state, _: void) usize {
                return 1;
            }
            /// Preserve the resumed answer unchanged.
            pub fn afterResume(_: no_state, answer: usize) usize {
                return answer;
            }
        }),
        shift.algebraic.handleAbort(stop, no_state{}, struct {
            /// Return a fixed abortive witness value.
            pub fn directReturn(_: no_state, _: []const u8) usize {
                return 0;
            }
        }),
    }));

    try std.testing.expectEqual(@as(usize, 0), @sizeOf(search));
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(stop));
    try std.testing.expectEqual(@sizeOf(usize), @sizeOf(Configured.Context));
}
