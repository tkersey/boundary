// zlinter-disable require_doc_comment - this preview witness file exposes public nested declarations to exercise comptime-facing lexical metadata seams.
const shift = @import("lexical_runtime_internal");
const std = @import("std");

fn hasErrorName(comptime ErrorSet: type, comptime wanted: []const u8) bool {
    inline for (@typeInfo(ErrorSet).error_set.?) |field| {
        if (comptime std.mem.eql(u8, field.name, wanted)) return true;
    }
    return false;
}

fn ExecResult(comptime T: type) type {
    return (shift.RuntimeError || error{ OutOfMemory, BodyOops, ContinueOops, HandlerOops, AfterOops })!T;
}

test "shift.with retains explicit body errors in ExecutionError" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const CallType = @TypeOf(shift.withAt(@src(), &runtime, .{
        .state = shift.effect.state.use(@as(i32, 7)),
    }, struct {
        /// Execute this public body hook.
        pub fn body(eff: anytype) ExecResult(i32) {
            _ = try eff.state.get();
            return error.BodyOops;
        }
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "BodyOops"));

    _ = shift.withAt(@src(), &runtime, .{
        .state = shift.effect.state.use(@as(i32, 7)),
    }, struct {
        /// Execute this public body hook.
        pub fn body(eff: anytype) ExecResult(i32) {
            _ = try eff.state.get();
            return error.BodyOops;
        }
    }) catch |err| {
        try std.testing.expectEqual(error.BodyOops, err);
        return;
    };
    return error.TestExpectedError;
}

test "shift.With distinguishes semantic from execution error metadata" {
    const Handlers = @TypeOf(.{
        .state = shift.effect.state.use(@as(i32, 7)),
    });
    const body_spec = struct {
        /// Public `SemanticErrorSet` declaration.
        pub const SemanticErrorSet = error{BodyOops};

        /// Execute this public body hook.
        pub fn body(eff: anytype) ExecResult(i32) {
            _ = try eff.state.get();
            return error.BodyOops;
        }
    };
    const Meta = shift.With(Handlers, body_spec);

    try std.testing.expect(hasErrorName(Meta.SemanticErrorSet, "BodyOops"));
    try std.testing.expect(!hasErrorName(Meta.SemanticErrorSet, "MissingPrompt"));
    try std.testing.expect(!hasErrorName(Meta.SemanticErrorSet, "OutOfMemory"));

    try std.testing.expect(hasErrorName(Meta.ExecutionError, "BodyOops"));
    try std.testing.expect(hasErrorName(Meta.ExecutionError, "MissingPrompt"));
    try std.testing.expect(hasErrorName(Meta.ExecutionError, "OutOfMemory"));
}

test "shift.With preserves semantic body errors that collide with setup names" {
    const Handlers = @TypeOf(.{
        .state = shift.effect.state.use(@as(i32, 7)),
    });
    const body_spec = struct {
        /// Public `SemanticErrorSet` declaration.
        pub const SemanticErrorSet = error{OutOfMemory};

        /// Execute this public body hook.
        pub fn body(_: anytype) ExecResult(i32) {
            return error.OutOfMemory;
        }
    };
    const Meta = shift.With(Handlers, body_spec);

    try std.testing.expect(hasErrorName(Meta.SemanticErrorSet, "OutOfMemory"));
    try std.testing.expect(hasErrorName(Meta.ExecutionError, "OutOfMemory"));
}

test "shift.With preserves mixed collided body errors in SemanticErrorSet" {
    const Handlers = @TypeOf(.{
        .state = shift.effect.state.use(@as(i32, 7)),
    });
    const body_spec = struct {
        /// Public `SemanticErrorSet` declaration.
        pub const SemanticErrorSet = error{ BodyOops, OutOfMemory, MissingPrompt };

        /// Execute this public body hook.
        pub fn body(eff: anytype) ExecResult(i32) {
            _ = try eff.state.get();
            return error.OutOfMemory;
        }
    };
    const Meta = shift.With(Handlers, body_spec);

    try std.testing.expect(hasErrorName(Meta.SemanticErrorSet, "BodyOops"));
    try std.testing.expect(hasErrorName(Meta.SemanticErrorSet, "OutOfMemory"));
    try std.testing.expect(hasErrorName(Meta.SemanticErrorSet, "MissingPrompt"));
}

test "shift.With instantiates for effect-only bodies without SemanticErrorSet metadata" {
    const Handlers = @TypeOf(.{
        .state = shift.effect.state.use(@as(i32, 7)),
    });
    const body_spec = struct {
        /// Execute this public body hook.
        pub fn body(eff: anytype) ExecResult(i32) {
            _ = try eff.state.get();
            return 0;
        }
    };
    const Meta = shift.With(Handlers, body_spec);

    try std.testing.expect(@sizeOf(Meta.Result) > 0);
    try std.testing.expect(hasErrorName(Meta.SemanticErrorSet, "MissingPrompt"));
    try std.testing.expect(hasErrorName(Meta.ExecutionError, "MissingPrompt"));
    try std.testing.expect(hasErrorName(Meta.ExecutionError, "OutOfMemory"));
}

test "shift.With preview includes continuation errors from lexical explicit programs" {
    const probe_descriptor = struct {
        pub const ErrorSet = error{};
        pub const State = i32;
        pub const Output = void;
        const ProbeOp = shift.effect.ops.Choice("probe", void, i32);

        pub fn HandleType(comptime Cap: type, comptime ContextPtrType: type) type {
            _ = ContextPtrType;
            return struct {
                fn BoundProgramType(comptime Continuation: type) type {
                    return @TypeOf((@as(*Cap.EngineContextType(), undefined)).performProgram(ProbeOp, {}, Continuation));
                }

                fn PromptType(comptime Continuation: type) type {
                    return @typeInfo(@FieldType(BoundProgramType(Continuation), "prompt")).pointer.child;
                }

                fn ExecutionErrorSet(comptime Continuation: type) type {
                    return shift.RuntimeError || error{OutOfMemory} || PromptType(Continuation).ErrorSet;
                }

                pub fn perform(_: @This(), comptime Continuation: type) ExecutionErrorSet(Continuation)!PromptType(Continuation).OutAnswer {
                    unreachable;
                }
            };
        }

        pub fn bindLexical(self: @This(), comptime Cap: type, ctx: anytype) HandleType(Cap, @TypeOf(ctx)) {
            _ = self;
            return .{};
        }

        pub fn run(
            self: @This(),
            comptime AnswerType: type,
            comptime RunErrorSetType: type,
            runtime: *shift.Runtime,
            comptime Body: type,
        ) (shift.RuntimeError || error{OutOfMemory} || RunErrorSetType)!struct { output: void, value: AnswerType } {
            _ = self;
            _ = runtime;
            _ = Body;
            unreachable;
        }
    };

    const Handlers = @TypeOf(.{ .probe = probe_descriptor{} });
    const body_spec = struct {
        pub const SemanticErrorSet = error{ContinueOops};

        pub fn body(eff: anytype) ExecResult(i32) {
            return try eff.probe.perform(struct {
                pub fn apply(_: i32) ExecResult(i32) {
                    return error.ContinueOops;
                }
            });
        }
    };
    const Meta = shift.With(Handlers, body_spec);

    try std.testing.expect(hasErrorName(Meta.ExecutionError, "ContinueOops"));
    try std.testing.expect(hasErrorName(Meta.SemanticErrorSet, "ContinueOops"));
}

test "shift.With preview specializes generic lexical explicit continuations" {
    const probe_descriptor = struct {
        pub const ErrorSet = error{};
        pub const State = i32;
        pub const Output = void;
        const ProbeOp = shift.effect.ops.Choice("probe", void, i32);

        pub fn HandleType(comptime Cap: type, comptime ContextPtrType: type) type {
            _ = ContextPtrType;
            return struct {
                fn BoundProgramType(comptime Continuation: anytype) type {
                    return @TypeOf((@as(*Cap.EngineContextType(), undefined)).performProgram(ProbeOp, {}, Continuation));
                }

                fn PromptType(comptime Continuation: anytype) type {
                    return @typeInfo(@FieldType(BoundProgramType(Continuation), "prompt")).pointer.child;
                }

                pub fn perform(_: @This(), comptime Continuation: anytype) (shift.RuntimeError || error{OutOfMemory} || PromptType(Continuation).ErrorSet)!PromptType(Continuation).OutAnswer {
                    unreachable;
                }
            };
        }

        pub fn bindLexical(self: @This(), comptime Cap: type, ctx: anytype) HandleType(Cap, @TypeOf(ctx)) {
            _ = self;
            return .{};
        }

        pub fn run(
            self: @This(),
            comptime AnswerType: type,
            comptime RunErrorSetType: type,
            runtime: *shift.Runtime,
            comptime Body: type,
        ) (shift.RuntimeError || error{OutOfMemory} || RunErrorSetType)!struct { output: void, value: AnswerType } {
            _ = self;
            _ = runtime;
            _ = Body;
            unreachable;
        }
    };

    const Handlers = @TypeOf(.{ .probe = probe_descriptor{} });
    const body_spec = struct {
        const genericResumeValue = struct {
            fn call(value: anytype) @TypeOf(value) {
                return value;
            }
        }.call;

        pub fn body(eff: anytype) ExecResult(i32) {
            return try eff.probe.perform(genericResumeValue);
        }
    };
    const Meta = shift.With(Handlers, body_spec);

    try std.testing.expect(@FieldType(Meta.Result, "value") == i32);
}

test "lexical optional request retains explicit continuation errors" {
    const policy = struct {
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, i32) {
            return shift.effect.choice.Decision(i32, i32).resumeWith(41);
        }

        pub fn afterResume(answer: i32) i32 {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const CallType = @TypeOf(shift.withAt(@src(), &runtime, .{
        .optional = shift.effect.optional.use(i32, policy),
    }, struct {
        pub fn body(eff: anytype) ExecResult(i32) {
            return try eff.optional.request(struct {
                pub fn apply(value: i32, _: anytype) ExecResult(i32) {
                    _ = value;
                    return error.ContinueOops;
                }
            });
        }
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "ContinueOops"));

    _ = shift.withAt(@src(), &runtime, .{
        .optional = shift.effect.optional.use(i32, policy),
    }, struct {
        pub fn body(eff: anytype) ExecResult(i32) {
            return try eff.optional.request(struct {
                pub fn apply(value: i32, _: anytype) ExecResult(i32) {
                    _ = value;
                    return error.ContinueOops;
                }
            });
        }
    }) catch |err| {
        try std.testing.expectEqual(error.ContinueOops, err);
        return;
    };
    return error.TestExpectedError;
}

test "lexical optional request accepts generic callable continuations" {
    const policy = struct {
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, i32) {
            return shift.effect.choice.Decision(i32, i32).resumeWith(41);
        }

        pub fn afterResume(answer: i32) i32 {
            return answer;
        }
    };

    const genericResume = struct {
        fn call(value: anytype, _: anytype) @TypeOf(value) {
            return value;
        }
    }.call;

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .optional = shift.effect.optional.use(i32, policy),
    }, struct {
        pub fn body(eff: anytype) ExecResult(i32) {
            return try eff.optional.request(genericResume);
        }
    });

    try std.testing.expectEqual(@as(i32, 41), result.value);
}

test "lexical optional request keeps continuation inference value-agnostic for slices" {
    const policy = struct {
        pub fn resumeOrReturn() shift.effect.choice.Decision([]const u8, u8) {
            return shift.effect.choice.Decision([]const u8, u8).resumeWith("abc");
        }

        pub fn afterResume(answer: u8) u8 {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .optional = shift.effect.optional.use([]const u8, policy),
    }, struct {
        pub fn body(eff: anytype) ExecResult(u8) {
            return try eff.optional.request(struct {
                pub fn apply(value: []const u8, _: anytype) u8 {
                    return value[0];
                }
            });
        }
    });

    try std.testing.expectEqual(@as(u8, 'a'), result.value);
}

test "generated lexical choice retains explicit continuation errors" {
    const Picker = shift.effect.Define(.{
        .state_type = struct {},
        .ops = .{
            shift.effect.ops.Choice("pick", i32, i32),
        },
    });

    const handler = struct {
        pub fn pick(_: *@This(), value: i32) shift.effect.choice.Decision(i32, i32) {
            return shift.effect.choice.Decision(i32, i32).resumeWith(value);
        }

        pub fn afterPick(_: *@This(), answer: i32) i32 {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const CallType = @TypeOf(shift.withAt(@src(), &runtime, .{
        .picker = Picker.use(.{ .handler = handler{} }),
    }, struct {
        pub fn body(eff: anytype) ExecResult(i32) {
            return try eff.picker.pick.perform(41, struct {
                pub fn apply(value: i32, _: anytype) ExecResult(i32) {
                    _ = value;
                    return error.ContinueOops;
                }
            });
        }
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "ContinueOops"));

    _ = shift.withAt(@src(), &runtime, .{
        .picker = Picker.use(.{ .handler = handler{} }),
    }, struct {
        pub fn body(eff: anytype) ExecResult(i32) {
            return try eff.picker.pick.perform(41, struct {
                pub fn apply(value: i32, _: anytype) ExecResult(i32) {
                    _ = value;
                    return error.ContinueOops;
                }
            });
        }
    }) catch |err| {
        try std.testing.expectEqual(error.ContinueOops, err);
        return;
    };
    return error.TestExpectedError;
}

test "generated family infers handler errors when error_set_type is omitted" {
    const Picker = shift.effect.Define(.{
        .state_type = struct {},
        .ops = .{
            shift.effect.ops.Choice("pick", i32, i32),
        },
    });

    const handler = struct {
        pub fn pick(_: *@This(), value: i32) ExecResult(shift.effect.choice.Decision(i32, i32)) {
            _ = value;
            return error.HandlerOops;
        }

        pub fn afterPick(_: *@This(), answer: i32) i32 {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const CallType = @TypeOf(shift.withAt(@src(), &runtime, .{
        .picker = Picker.use(.{ .handler = handler{} }),
    }, struct {
        pub fn body(eff: anytype) ExecResult(i32) {
            return try eff.picker.pick.perform(41, struct {
                pub fn apply(value: i32, _: anytype) i32 {
                    return value;
                }
            });
        }
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "HandlerOops"));

    _ = shift.withAt(@src(), &runtime, .{
        .picker = Picker.use(.{ .handler = handler{} }),
    }, struct {
        pub fn body(eff: anytype) ExecResult(i32) {
            return try eff.picker.pick.perform(41, struct {
                pub fn apply(value: i32, _: anytype) i32 {
                    return value;
                }
            });
        }
    }) catch |err| {
        try std.testing.expectEqual(error.HandlerOops, err);
        return;
    };
    return error.TestExpectedError;
}

test "generated lexical handlers infer after-hook errors when error_set_type is omitted" {
    const Counter = shift.effect.Define(.{
        .state_type = i32,
        .ops = .{
            shift.effect.ops.Transform("get", void, i32),
        },
    });

    const Handler = struct {
        state: i32 = 7,

        pub fn get(self: *@This()) i32 {
            return self.state;
        }

        pub fn afterGet(_: *@This(), _: i32) ExecResult(i32) {
            return error.AfterOops;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const CallType = @TypeOf(shift.withAt(@src(), &runtime, .{
        .counter = Counter.use(.{ .handler = Handler{} }),
    }, struct {
        pub fn body(eff: anytype) ExecResult(i32) {
            return try eff.counter.get.perform();
        }
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "AfterOops"));
}

test "generated family handleWithErrorSet keeps source-compatible arity" {
    const NoError = error{};
    const Audit = shift.effect.Define(.{
        .state_type = void,
        .ops = .{
            shift.effect.ops.Transform("note", []const u8, void),
        },
    });

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = Audit.Instance.init();

    const result = try Audit.handleWithErrorSet([]const u8, NoError, &runtime, &instance, struct {
        pub fn note(_: *@This(), _: []const u8) void {
            // Intentionally empty witness hook.
        }
    }{}, struct {
        pub fn body(comptime Cap: type, ctx: anytype) NoError![]const u8 {
            _ = Cap;
            _ = ctx;
            return "ok";
        }
    });

    try std.testing.expectEqualStrings("ok", result.value);
}

test "generated family handle keeps source-compatible arity" {
    const NoError = error{};
    const Audit = shift.effect.Define(.{
        .state_type = void,
        .ops = .{
            shift.effect.ops.Transform("note", []const u8, void),
        },
    });

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = Audit.Instance.init();

    const result = try Audit.handle([]const u8, &runtime, &instance, struct {
        pub fn note(_: *@This(), _: []const u8) void {
            // Intentionally empty witness hook.
        }
    }{}, struct {
        pub fn body(comptime Cap: type, ctx: anytype) NoError![]const u8 {
            _ = Cap;
            _ = ctx;
            return "ok";
        }
    });

    try std.testing.expectEqualStrings("ok", result.value);
}

test "generated family handleWithErrorSetAt preserves caller provenance" {
    const NoError = error{};
    const Audit = shift.effect.Define(.{
        .state_type = void,
        .ops = .{
            shift.effect.ops.Transform("note", []const u8, void),
        },
    });

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = Audit.Instance.init();

    const result = try Audit.handleWithErrorSetAt(@src(), []const u8, NoError, &runtime, &instance, struct {
        pub fn note(_: *@This(), _: []const u8) void {
            // Intentionally empty witness hook.
        }
    }{}, struct {
        pub fn body(comptime Cap: type, ctx: anytype) NoError![]const u8 {
            _ = Cap;
            return switch (@typeInfo(@TypeOf(@TypeOf(ctx.*).caller_source))) {
                .optional => @TypeOf(ctx.*).caller_source.?.file,
                else => @TypeOf(ctx.*).caller_source.file,
            };
        }
    });

    try std.testing.expectEqualStrings(@src().file, result.value);
}

test "generated family handleAt preserves caller provenance" {
    const NoError = error{};
    const Audit = shift.effect.Define(.{
        .state_type = void,
        .ops = .{
            shift.effect.ops.Transform("note", []const u8, void),
        },
    });

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = Audit.Instance.init();

    const result = try Audit.handleAt(@src(), []const u8, &runtime, &instance, struct {
        pub fn note(_: *@This(), _: []const u8) void {
            // Intentionally empty witness hook.
        }
    }{}, struct {
        pub fn body(comptime Cap: type, ctx: anytype) NoError![]const u8 {
            _ = Cap;
            return switch (@typeInfo(@TypeOf(@TypeOf(ctx.*).caller_source))) {
                .optional => @TypeOf(ctx.*).caller_source.?.file,
                else => @TypeOf(ctx.*).caller_source.file,
            };
        }
    });

    try std.testing.expectEqualStrings(@src().file, result.value);
}

test "generated lexical transform handlers accept void state without a state field" {
    const Search = shift.effect.Define(.{
        .state_type = void,
        .ops = .{
            shift.effect.ops.Transform("query", []const u8, i32),
        },
    });

    const handler = struct {
        pub fn query(_: *@This(), payload: []const u8) i32 {
            return if (std.mem.eql(u8, payload, "artifact-search")) 3 else 0;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.withAt(@src(), &runtime, .{
        .search = Search.use(.{ .handler = handler{} }),
    }, struct {
        pub fn body(eff: anytype) ExecResult(i32) {
            return try eff.search.query.perform("artifact-search");
        }
    });

    try std.testing.expectEqual(@as(i32, 3), result.value);
}
