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
    try std.testing.expect(@hasDecl(shift, "Decision"));
    try std.testing.expect(@hasDecl(shift, "Decl"));
    try std.testing.expect(@hasDecl(shift, "Op"));
    try std.testing.expect(@hasDecl(shift, "Program"));
    try std.testing.expect(@hasDecl(shift, "run"));

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

test "front-door declaration and op shells stay compact" {
    const Transform = shift.Op.Transform("search", []const u8, i32);
    const Choice = shift.Op.Choice("publish", void, []const u8);
    const Abort = shift.Op.Abort("fail", []const u8);

    try std.testing.expectEqual(@as(usize, 0), @sizeOf(Transform));
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(Choice));
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(Abort));

    try std.testing.expectEqual(@as(usize, 0), @sizeOf(@TypeOf(shift.Decl.state(i32))));
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(@TypeOf(shift.Decl.reader(i32))));
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(@TypeOf(shift.Decl.optional(i32, struct {
        pub fn resumeOrReturn() shift.Decision(i32, i32) {
            return shift.Decision(i32, i32).resumeWith(1);
        }

        pub fn afterResume(answer: i32) i32 {
            return answer;
        }
    }))));
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(@TypeOf(shift.Decl.exception([]const u8, struct {
        pub fn directReturn(payload: []const u8) []const u8 {
            return payload;
        }
    }))));
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(@TypeOf(shift.Decl.resource([]const u8, struct {
        pub fn acquire() []const u8 {
            return "resource";
        }

        pub fn release(_: []const u8) void {
            // Deliberately empty for the compact-size witness.
        }
    }))));
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(@TypeOf(shift.Decl.writer([]const u8))));
}

test "family declarations stay compact and hide implementation context" {
    const Counter = shift.Decl.family(.{
        .state_type = i32,
        .ops = .{
            shift.Op.Transform("get", void, i32),
        },
    }, struct {
        state: i32 = 7,

        pub fn get(self: *@This()) i32 {
            return self.state;
        }

        pub fn afterGet(_: *@This(), answer: i32) i32 {
            return answer;
        }
    });
    const CounterType = @TypeOf(Counter);

    try std.testing.expectEqual(@as(usize, 0), @sizeOf(CounterType));
    try std.testing.expect(@hasDecl(CounterType, "generated"));
    try std.testing.expect(@hasDecl(CounterType, "Handler"));
    try std.testing.expect(!@hasDecl(CounterType, "Context"));
    try std.testing.expect(!@hasDecl(CounterType, "Continuation"));
}

test "front-door program preserves custom body errors" {
    const StateProgram = shift.Program(.{
        .state = shift.Decl.state(i32),
    }, struct {
        pub fn body(eff: anytype) !i32 {
            _ = try eff.state.get();
            return error.BodyOops;
        }
    });

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const CallType = @TypeOf(shift.run(&runtime, StateProgram, .{ .state = 1 }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "BodyOops"));
    try std.testing.expectError(error.BodyOops, shift.run(&runtime, StateProgram, .{ .state = 1 }));
}

test "front-door custom family infers handler errors" {
    const CounterHandler = struct {
        state: i32 = 7,

        pub fn get(_: *@This()) !i32 {
            return error.HandlerOops;
        }

        pub fn afterGet(_: *@This(), answer: i32) i32 {
            return answer;
        }
    };

    const Counter = shift.Decl.family(.{
        .state_type = i32,
        .ops = .{
            shift.Op.Transform("get", void, i32),
        },
    }, CounterHandler);

    const CounterProgram = shift.Program(.{
        .counter = Counter,
    }, struct {
        pub fn body(eff: anytype) !i32 {
            return try eff.counter.get.perform();
        }
    });

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const CallType = @TypeOf(shift.run(&runtime, CounterProgram, .{
        .counter = CounterHandler{},
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "HandlerOops"));
    try std.testing.expect(hasErrorName(ErrorSet, "FrontendSuspend"));
    try std.testing.expect(hasErrorName(ErrorSet, "ProgramContractViolation"));
    try std.testing.expectError(error.HandlerOops, shift.run(&runtime, CounterProgram, .{
        .counter = CounterHandler{},
    }));
}

test "front-door optional declarations infer continuation errors" {
    const policy = struct {
        pub fn resumeOrReturn() shift.Decision(i32, i32) {
            return shift.Decision(i32, i32).resumeWith(41);
        }

        pub fn afterResume(answer: i32) i32 {
            return answer;
        }
    };

    const OptionalProgram = shift.Program(.{
        .optional = shift.Decl.optional(i32, policy),
    }, struct {
        pub fn body(eff: anytype) !i32 {
            return try eff.optional.request(struct {
                pub fn apply(value: i32, _: anytype) !i32 {
                    _ = value;
                    return error.ContinueOops;
                }
            });
        }
    });

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const CallType = @TypeOf(shift.run(&runtime, OptionalProgram, .{}));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "ContinueOops"));
    try std.testing.expectError(error.ContinueOops, shift.run(&runtime, OptionalProgram, .{}));
}

test "front-door choice families infer continuation errors" {
    const picker_handler = struct {
        pub fn pick(_: *@This(), payload: i32) shift.Decision(i32, i32) {
            return shift.Decision(i32, i32).resumeWith(payload);
        }

        pub fn afterPick(_: *@This(), answer: i32) i32 {
            return answer;
        }
    };

    const Picker = shift.Decl.family(.{
        .state_type = struct {},
        .ops = .{
            shift.Op.Choice("pick", i32, i32),
        },
    }, picker_handler);

    const PickerProgram = shift.Program(.{
        .picker = Picker,
    }, struct {
        pub fn body(eff: anytype) !i32 {
            return try eff.picker.pick.perform(41, struct {
                pub fn apply(_: i32, _: anytype) !i32 {
                    return error.ContinueOops;
                }
            });
        }
    });

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const CallType = @TypeOf(shift.run(&runtime, PickerProgram, .{
        .picker = picker_handler{},
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "ContinueOops"));
    try std.testing.expectError(error.ContinueOops, shift.run(&runtime, PickerProgram, .{
        .picker = picker_handler{},
    }));
}
