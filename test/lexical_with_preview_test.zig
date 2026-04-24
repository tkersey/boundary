// zlinter-disable require_doc_comment - this preview witness file exposes public nested declarations to exercise comptime-facing lexical metadata seams.
const ability = @import("ability");
const ability_shared = @import("ability_shared");
const std = @import("std");

fn hasErrorName(comptime ErrorSet: type, comptime wanted: []const u8) bool {
    inline for (@typeInfo(ErrorSet).error_set.?) |field| {
        if (comptime std.mem.eql(u8, field.name, wanted)) return true;
    }
    return false;
}

fn ExecResult(comptime T: type) type {
    return (ability.RuntimeError || error{ OutOfMemory, BodyOops, ContinueOops, HandlerOops, AfterOops })!T;
}

test "ability.with retains explicit body errors in ExecutionError" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const CallType = @TypeOf(ability.with(&runtime, .{
        .state = ability.effect.state.use(@as(i32, 7)),
    }, struct {
        /// Execute this public body hook.
        pub fn body(eff: anytype) ExecResult(i32) {
            _ = try eff.state.get();
            return error.BodyOops;
        }
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "BodyOops"));

    _ = ability.with(&runtime, .{
        .state = ability.effect.state.use(@as(i32, 7)),
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

test "ability_shared.With distinguishes semantic from execution error metadata" {
    const Handlers = @TypeOf(.{
        .state = ability.effect.state.use(@as(i32, 7)),
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
    const Meta = ability_shared.With(Handlers, body_spec);

    try std.testing.expect(hasErrorName(Meta.SemanticErrorSet, "BodyOops"));
    try std.testing.expect(!hasErrorName(Meta.SemanticErrorSet, "MissingPrompt"));
    try std.testing.expect(!hasErrorName(Meta.SemanticErrorSet, "OutOfMemory"));

    try std.testing.expect(hasErrorName(Meta.ExecutionError, "BodyOops"));
    try std.testing.expect(hasErrorName(Meta.ExecutionError, "MissingPrompt"));
    try std.testing.expect(hasErrorName(Meta.ExecutionError, "OutOfMemory"));
}

test "ability_shared.With preserves semantic body errors that collide with setup names" {
    const Handlers = @TypeOf(.{
        .state = ability.effect.state.use(@as(i32, 7)),
    });
    const body_spec = struct {
        /// Public `SemanticErrorSet` declaration.
        pub const SemanticErrorSet = error{OutOfMemory};

        /// Execute this public body hook.
        pub fn body(_: anytype) ExecResult(i32) {
            return error.OutOfMemory;
        }
    };
    const Meta = ability_shared.With(Handlers, body_spec);

    try std.testing.expect(hasErrorName(Meta.SemanticErrorSet, "OutOfMemory"));
    try std.testing.expect(hasErrorName(Meta.ExecutionError, "OutOfMemory"));
}

test "ability_shared.With preserves mixed collided body errors in SemanticErrorSet" {
    const Handlers = @TypeOf(.{
        .state = ability.effect.state.use(@as(i32, 7)),
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
    const Meta = ability_shared.With(Handlers, body_spec);

    try std.testing.expect(hasErrorName(Meta.SemanticErrorSet, "BodyOops"));
    try std.testing.expect(hasErrorName(Meta.SemanticErrorSet, "OutOfMemory"));
    try std.testing.expect(hasErrorName(Meta.SemanticErrorSet, "MissingPrompt"));
}

test "ability_shared.With instantiates for effect-only bodies without SemanticErrorSet metadata" {
    const Handlers = @TypeOf(.{
        .state = ability.effect.state.use(@as(i32, 7)),
    });
    const body_spec = struct {
        /// Execute this public body hook.
        pub fn body(eff: anytype) ExecResult(i32) {
            _ = try eff.state.get();
            return 0;
        }
    };
    const Meta = ability_shared.With(Handlers, body_spec);

    try std.testing.expect(@sizeOf(Meta.Result) > 0);
    try std.testing.expect(hasErrorName(Meta.SemanticErrorSet, "MissingPrompt"));
    try std.testing.expect(hasErrorName(Meta.ExecutionError, "MissingPrompt"));
    try std.testing.expect(hasErrorName(Meta.ExecutionError, "OutOfMemory"));
}

test "ability_shared.With preview includes continuation errors from lexical explicit programs" {
    const probe_descriptor = struct {
        pub const ErrorSet = error{};
        pub const State = i32;
        pub const Output = void;
        const ProbeOp = ability.effect.ops.Choice("probe", void, i32);

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
                    return ability.RuntimeError || error{OutOfMemory} || PromptType(Continuation).ErrorSet;
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
            runtime: *ability.Runtime,
            comptime Body: type,
        ) (ability.RuntimeError || error{OutOfMemory} || RunErrorSetType)!struct { output: void, value: AnswerType } {
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
    const Meta = ability_shared.With(Handlers, body_spec);

    try std.testing.expect(hasErrorName(Meta.ExecutionError, "ContinueOops"));
    try std.testing.expect(hasErrorName(Meta.SemanticErrorSet, "ContinueOops"));
}

test "ability_shared.With preview specializes generic lexical explicit continuations" {
    const probe_descriptor = struct {
        pub const ErrorSet = error{};
        pub const State = i32;
        pub const Output = void;
        const ProbeOp = ability.effect.ops.Choice("probe", void, i32);

        pub fn HandleType(comptime Cap: type, comptime ContextPtrType: type) type {
            _ = ContextPtrType;
            return struct {
                fn BoundProgramType(comptime Continuation: anytype) type {
                    return @TypeOf((@as(*Cap.EngineContextType(), undefined)).performProgram(ProbeOp, {}, Continuation));
                }

                fn PromptType(comptime Continuation: anytype) type {
                    return @typeInfo(@FieldType(BoundProgramType(Continuation), "prompt")).pointer.child;
                }

                pub fn perform(_: @This(), comptime Continuation: anytype) (ability.RuntimeError || error{OutOfMemory} || PromptType(Continuation).ErrorSet)!PromptType(Continuation).OutAnswer {
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
            runtime: *ability.Runtime,
            comptime Body: type,
        ) (ability.RuntimeError || error{OutOfMemory} || RunErrorSetType)!struct { output: void, value: AnswerType } {
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
    const Meta = ability_shared.With(Handlers, body_spec);

    try std.testing.expect(@FieldType(Meta.Result, "value") == i32);
}

test "generated family infers handler errors when error_set_type is omitted" {
    const Picker = ability.effect.Define(.{
        .state_type = struct {},
        .ops = .{
            ability.effect.ops.Choice("pick", i32, i32),
        },
    });

    const handler = struct {
        pub fn pick(_: *@This(), value: i32) ExecResult(ability.effect.choice.Decision(i32, i32)) {
            _ = value;
            return error.HandlerOops;
        }

        pub fn afterPick(_: *@This(), answer: i32) i32 {
            return answer;
        }
    };

    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const CallType = @TypeOf(ability.with(&runtime, .{
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

    _ = ability.with(&runtime, .{
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
    const Counter = ability.effect.Define(.{
        .state_type = i32,
        .ops = .{
            ability.effect.ops.Transform("get", void, i32),
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

    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const CallType = @TypeOf(ability.with(&runtime, .{
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
    const Audit = ability.effect.Define(.{
        .state_type = void,
        .ops = .{
            ability.effect.ops.Transform("note", []const u8, void),
        },
    });

    var runtime = ability.Runtime.init(std.testing.allocator);
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
    const Audit = ability.effect.Define(.{
        .state_type = void,
        .ops = .{
            ability.effect.ops.Transform("note", []const u8, void),
        },
    });

    var runtime = ability.Runtime.init(std.testing.allocator);
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

test "generated family handleWithErrorSet leaves caller provenance absent" {
    const NoError = error{};
    const Audit = ability.effect.Define(.{
        .state_type = void,
        .ops = .{
            ability.effect.ops.Transform("note", []const u8, void),
        },
    });

    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = Audit.Instance.init();

    const result = try Audit.handleWithErrorSet([]const u8, NoError, &runtime, &instance, struct {
        pub fn note(_: *@This(), _: []const u8) void {
            // Intentionally empty witness hook.
        }
    }{}, struct {
        pub fn body(comptime Cap: type, ctx: anytype) NoError![]const u8 {
            _ = Cap;
            return switch (@typeInfo(@TypeOf(@TypeOf(ctx.*).caller_source))) {
                .optional => if (@TypeOf(ctx.*).caller_source == null) "absent" else @TypeOf(ctx.*).caller_source.?.file,
                .null => "absent",
                else => @TypeOf(ctx.*).caller_source.file,
            };
        }
    });

    try std.testing.expectEqualStrings("absent", result.value);
}

test "generated family handle leaves caller provenance absent" {
    const NoError = error{};
    const Audit = ability.effect.Define(.{
        .state_type = void,
        .ops = .{
            ability.effect.ops.Transform("note", []const u8, void),
        },
    });

    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = Audit.Instance.init();

    const result = try Audit.handle([]const u8, &runtime, &instance, struct {
        pub fn note(_: *@This(), _: []const u8) void {
            // Intentionally empty witness hook.
        }
    }{}, struct {
        pub fn body(comptime Cap: type, ctx: anytype) NoError![]const u8 {
            _ = Cap;
            return switch (@typeInfo(@TypeOf(@TypeOf(ctx.*).caller_source))) {
                .optional => if (@TypeOf(ctx.*).caller_source == null) "absent" else @TypeOf(ctx.*).caller_source.?.file,
                .null => "absent",
                else => @TypeOf(ctx.*).caller_source.file,
            };
        }
    });

    try std.testing.expectEqualStrings("absent", result.value);
}

test "generated lexical transform handlers accept void state without a state field" {
    const Search = ability.effect.Define(.{
        .state_type = void,
        .ops = .{
            ability.effect.ops.Transform("query", []const u8, i32),
        },
    });

    const handler = struct {
        pub fn query(_: *@This(), payload: []const u8) i32 {
            return if (std.mem.eql(u8, payload, "artifact-search")) 3 else 0;
        }
    };

    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try ability.with(&runtime, .{
        .search = Search.use(.{ .handler = handler{} }),
    }, struct {
        pub fn body(eff: anytype) ExecResult(i32) {
            return try eff.search.query.perform("artifact-search");
        }
    });

    try std.testing.expectEqual(@as(i32, 3), result.value);
}
