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

test "guard and continuation surfaces are not public" {
    try std.testing.expect(!@hasDecl(shift, "NoShiftGuard"));
    try std.testing.expect(!@hasDecl(shift, "Continuation"));
    try std.testing.expect(!@hasDecl(shift, "parity_machine"));
    try std.testing.expect(!@hasDecl(shift, "ResumeOrReturn"));
    try std.testing.expect(@hasDecl(shift, "effect"));
    try std.testing.expect(@hasDecl(shift.effect, "Define"));
    try std.testing.expect(@hasDecl(shift.effect, "ops"));
    try std.testing.expect(!@hasDecl(shift.effect.state, "Continuation"));
}

test "public runtime error surface still exposes the current raw contract" {
    try std.testing.expect(hasErrorName(shift.RuntimeError, "MissingPrompt"));
    try std.testing.expect(hasErrorName(shift.RuntimeError, "CrossThread"));
    try std.testing.expect(hasErrorName(shift.RuntimeError, "RuntimeBusy"));
    try std.testing.expect(hasErrorName(shift.RuntimeError, "RuntimeDestroyed"));
    try std.testing.expect(hasErrorName(shift.RuntimeError, "NonDiagonalComplete"));
    try std.testing.expect(!hasErrorName(shift.RuntimeError, "AlreadyResolved"));
    try std.testing.expect(!hasErrorName(shift.RuntimeError, "NestedNonDiagonalCapture"));
}

test "algebraic descriptor and context shells stay compact" {
    const no_state = struct {};
    const search = shift.algebraic.TransformOp("search", void, usize);
    const stop = shift.algebraic.AbortOp("stop", []const u8);
    const program = shift.algebraic.Program(usize, .{ search, stop });
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

test "algebraic Program infers handler errors on the public wrapper" {
    const no_state = struct {};
    const ping = shift.algebraic.TransformOp("ping", void, i32);
    const program = shift.algebraic.Program(i32, .{ping});
    const configured = program.handlers(.{
        shift.algebraic.handleTransform(ping, no_state{}, struct {
            pub fn resumeValue(_: no_state, _: void) !i32 {
                return error.HandlerOops;
            }
            pub fn afterResume(_: no_state, answer: i32) i32 {
                return answer;
            }
        }),
    });

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const CallType = @TypeOf(configured.run(&runtime, struct {
        pub fn body(ctx: *@TypeOf(configured).Context) !i32 {
            return try ctx.perform(ping, {});
        }
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "HandlerOops"));
    try std.testing.expectError(error.HandlerOops, configured.run(&runtime, struct {
        pub fn body(ctx: *@TypeOf(configured).Context) !i32 {
            return try ctx.perform(ping, {});
        }
    }));
}

test "generated effect family shell stays compact and hides context" {
    const Counter = shift.effect.Define(.{
        .state_type = i32,
        .ops = .{
            shift.effect.ops.Transform("get", void, i32),
            shift.effect.ops.Transform("set", i32, void),
        },
    });

    try std.testing.expectEqual(@sizeOf(usize), @sizeOf(Counter.Instance));
    try std.testing.expect(!@hasDecl(Counter, "Context"));
    try std.testing.expect(@hasDecl(Counter, "definition"));
    try std.testing.expect(@hasDecl(Counter, "OpTag"));
}
