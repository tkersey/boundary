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

fn namedStateBody(eff: anytype) ExecResult(i32) {
    const before = try eff.state.get();
    try eff.state.set(before + 1);
    const after = try eff.state.get();
    return before + after;
}

fn namedStateHelper(ctx: anytype) ExecResult(void) {
    _ = try ctx.state.get();
}

fn namedStateBodyWithRenamedEffectParam(ctx: anytype) ExecResult(i32) {
    try namedStateHelper(ctx);
    return 9;
}

fn namedReaderBody(eff: anytype) ExecResult(i32) {
    const env = try eff.reader.ask();
    return env + env;
}

fn namedWriterBody(eff: anytype) ExecResult([]const u8) {
    try eff.writer.tell("a");
    try eff.writer.tell("b");
    return "done";
}

fn namedBoolLiteralBody(_: anytype) ExecResult(bool) {
    return true;
}

fn namedUsizeLiteralBody(_: anytype) ExecResult(usize) {
    return 1;
}

fn namedBoolStateBody(eff: anytype) ExecResult(bool) {
    const enabled = true;
    try eff.state.set(enabled);
    return try eff.state.get();
}

fn namedOptionalReturnNowBody(eff: anytype) ExecResult([]const u8) {
    return try eff.optional.request(struct {
        /// This continuation stays unreachable in the return-now branch.
        pub fn apply(_: i32, _: anytype) ExecResult([]const u8) {
            return "unused";
        }
    });
}

fn namedOptionalResumeBody(eff: anytype) ExecResult([]const u8) {
    return try eff.optional.request(struct {
        /// Return the canonical resumed answer for this named-body test.
        pub fn apply(_: i32, _: anytype) ExecResult([]const u8) {
            return "answer=42";
        }
    });
}

fn namedOptionalResumeBoolBody(eff: anytype) ExecResult(bool) {
    return try eff.optional.request(struct {
        /// Return the canonical resumed bool answer for this named-body test.
        pub fn apply(_: i32, _: anytype) ExecResult(bool) {
            return true;
        }
    });
}

fn namedOptionalResumeUsizeBody(eff: anytype) ExecResult(usize) {
    return try eff.optional.request(struct {
        /// Return the canonical resumed usize answer for this named-body test.
        pub fn apply(_: i32, _: anytype) ExecResult(usize) {
            return 1;
        }
    });
}

fn namedGeneratedChoiceBody(eff: anytype) ExecResult([]const u8) {
    return try eff.picker.pick.perform(41, struct {
        /// Return the canonical resumed answer for this generated-choice test.
        pub fn apply(_: i32, _: anytype) ExecResult([]const u8) {
            return "answer=42";
        }
    });
}

fn namedGeneratedChoiceUnderscoreBody(eff: anytype) ExecResult([]const u8) {
    return try eff.picker.pick_item.perform(41, struct {
        /// Return the canonical resumed answer for this underscored generated-choice test.
        pub fn apply(_: i32, _: anytype) ExecResult([]const u8) {
            return "answer=42";
        }
    });
}

fn namedExceptionPassBody(_: anytype) ExecResult([]const u8) {
    return "result=ok";
}

fn namedExceptionThrowBody(eff: anytype) ExecResult([]const u8) {
    try eff.exception.throw("result=boom");
}

fn namedGeneratedAbortBody(eff: anytype) ExecResult([]const u8) {
    try eff.guard.fail.abort("missing-name");
}

fn expectFixtureTranscript(comptime fixture_path: []const u8, writer_fn: anytype) anyerror!void {
    var buffer: std.io.Writer.Allocating = .init(std.testing.allocator);
    defer buffer.deinit();
    try writer_fn(&buffer.writer);
    try std.testing.expectEqualStrings(@embedFile(fixture_path), buffer.written());
}

test "shift.with retains explicit body errors in ExecutionError" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const CallType = @TypeOf(shift.with(&runtime, .{
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

    _ = shift.with(&runtime, .{
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
        /// Public `ErrorSet` declaration.
        pub const ErrorSet = error{};
        /// Public `State` declaration.
        pub const State = i32;
        /// Public `Output` declaration.
        pub const Output = void;
        const ProbeOp = shift.effect.ops.Choice("probe", void, i32);

        /// Return the public handle type.
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

                /// Perform this public operation.
                pub fn perform(_: @This(), comptime Continuation: type) ExecutionErrorSet(Continuation)!PromptType(Continuation).OutAnswer {
                    unreachable;
                }
            };
        }

        /// Public `bindLexical` helper.
        pub fn bindLexical(self: @This(), comptime Cap: type, ctx: anytype) HandleType(Cap, @TypeOf(ctx)) {
            _ = self;
            return .{};
        }

        /// Run this public entrypoint.
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

    const Handlers = @TypeOf(.{
        .probe = probe_descriptor{},
    });
    const body_spec = struct {
        /// Public `SemanticErrorSet` declaration.
        pub const SemanticErrorSet = error{ContinueOops};

        /// Execute this public body hook.
        pub fn body(eff: anytype) ExecResult(i32) {
            return try eff.probe.perform(struct {
                /// Apply this public continuation hook.
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
        /// Public `ErrorSet` declaration.
        pub const ErrorSet = error{};
        /// Public `State` declaration.
        pub const State = i32;
        /// Public `Output` declaration.
        pub const Output = void;
        const ProbeOp = shift.effect.ops.Choice("probe", void, i32);

        /// Return the public handle type.
        pub fn HandleType(comptime Cap: type, comptime ContextPtrType: type) type {
            _ = ContextPtrType;
            return struct {
                /// Return the public bound-program type.
                fn BoundProgramType(comptime Continuation: anytype) type {
                    return @TypeOf((@as(*Cap.EngineContextType(), undefined)).performProgram(ProbeOp, {}, Continuation));
                }

                /// Return the prompt type for one continuation.
                fn PromptType(comptime Continuation: anytype) type {
                    return @typeInfo(@FieldType(BoundProgramType(Continuation), "prompt")).pointer.child;
                }

                /// Perform this public operation.
                pub fn perform(_: @This(), comptime Continuation: anytype) (shift.RuntimeError || error{OutOfMemory} || PromptType(Continuation).ErrorSet)!PromptType(Continuation).OutAnswer {
                    unreachable;
                }
            };
        }

        /// Public `bindLexical` helper.
        pub fn bindLexical(self: @This(), comptime Cap: type, ctx: anytype) HandleType(Cap, @TypeOf(ctx)) {
            _ = self;
            return .{};
        }

        /// Run this public entrypoint.
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

    const Handlers = @TypeOf(.{
        .probe = probe_descriptor{},
    });
    const body_spec = struct {
        const genericResumeValue = struct {
            fn call(value: anytype) @TypeOf(value) {
                return value;
            }
        }.call;

        /// Execute this public body hook.
        pub fn body(eff: anytype) ExecResult(i32) {
            return try eff.probe.perform(genericResumeValue);
        }
    };
    const Meta = shift.With(Handlers, body_spec);

    try std.testing.expect(@FieldType(Meta.Result, "value") == i32);
}

test "lexical optional request retains explicit continuation errors" {
    const policy = struct {
        /// Decide whether this public hook resumes or returns.
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, i32) {
            return shift.effect.choice.Decision(i32, i32).resumeWith(41);
        }

        /// Finish this public resumed path.
        pub fn afterResume(answer: i32) i32 {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const CallType = @TypeOf(shift.with(&runtime, .{
        .optional = shift.effect.optional.use(i32, policy),
    }, struct {
        /// Execute this public body hook.
        pub fn body(eff: anytype) ExecResult(i32) {
            return try eff.optional.request(struct {
                /// Apply this public continuation hook.
                pub fn apply(value: i32, _: anytype) ExecResult(i32) {
                    _ = value;
                    return error.ContinueOops;
                }
            });
        }
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "ContinueOops"));

    _ = shift.with(&runtime, .{
        .optional = shift.effect.optional.use(i32, policy),
    }, struct {
        /// Execute this public body hook.
        pub fn body(eff: anytype) ExecResult(i32) {
            return try eff.optional.request(struct {
                /// Apply this public continuation hook.
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
        /// Decide whether this public hook resumes or returns.
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, i32) {
            return shift.effect.choice.Decision(i32, i32).resumeWith(41);
        }

        /// Finish this public resumed path.
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

    const result = try shift.with(&runtime, .{
        .optional = shift.effect.optional.use(i32, policy),
    }, struct {
        /// Execute this public body hook.
        pub fn body(eff: anytype) ExecResult(i32) {
            return try eff.optional.request(genericResume);
        }
    });

    try std.testing.expectEqual(@as(i32, 41), result.value);
}

test "lexical optional request keeps continuation inference value-agnostic for slices" {
    const policy = struct {
        /// Decide whether this public hook resumes or returns.
        pub fn resumeOrReturn() shift.effect.choice.Decision([]const u8, u8) {
            return shift.effect.choice.Decision([]const u8, u8).resumeWith("abc");
        }

        /// Finish this public resumed path.
        pub fn afterResume(answer: u8) u8 {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .optional = shift.effect.optional.use([]const u8, policy),
    }, struct {
        /// Execute this public body hook.
        pub fn body(eff: anytype) ExecResult(u8) {
            return try eff.optional.request(struct {
                /// Apply this public continuation hook.
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
        /// Public `pick` helper.
        pub fn pick(_: *@This(), value: i32) shift.effect.choice.Decision(i32, i32) {
            return shift.effect.choice.Decision(i32, i32).resumeWith(value);
        }

        /// Public `afterPick` helper.
        pub fn afterPick(_: *@This(), answer: i32) i32 {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const CallType = @TypeOf(shift.with(&runtime, .{
        .picker = Picker.use(.{ .handler = handler{} }),
    }, struct {
        /// Execute this public body hook.
        pub fn body(eff: anytype) ExecResult(i32) {
            return try eff.picker.pick.perform(41, struct {
                /// Apply this public continuation hook.
                pub fn apply(value: i32, _: anytype) ExecResult(i32) {
                    _ = value;
                    return error.ContinueOops;
                }
            });
        }
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "ContinueOops"));

    _ = shift.with(&runtime, .{
        .picker = Picker.use(.{ .handler = handler{} }),
    }, struct {
        /// Execute this public body hook.
        pub fn body(eff: anytype) ExecResult(i32) {
            return try eff.picker.pick.perform(41, struct {
                /// Apply this public continuation hook.
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
        /// Public `pick` helper.
        pub fn pick(_: *@This(), value: i32) ExecResult(shift.effect.choice.Decision(i32, i32)) {
            _ = value;
            return error.HandlerOops;
        }

        /// Public `afterPick` helper.
        pub fn afterPick(_: *@This(), answer: i32) i32 {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const CallType = @TypeOf(shift.with(&runtime, .{
        .picker = Picker.use(.{ .handler = handler{} }),
    }, struct {
        /// Execute this public body hook.
        pub fn body(eff: anytype) ExecResult(i32) {
            return try eff.picker.pick.perform(41, struct {
                /// Apply this public continuation hook.
                pub fn apply(value: i32, _: anytype) i32 {
                    return value;
                }
            });
        }
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "HandlerOops"));

    _ = shift.with(&runtime, .{
        .picker = Picker.use(.{ .handler = handler{} }),
    }, struct {
        /// Execute this public body hook.
        pub fn body(eff: anytype) ExecResult(i32) {
            return try eff.picker.pick.perform(41, struct {
                /// Apply this public continuation hook.
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

        /// Public `get` helper.
        pub fn get(self: *@This()) i32 {
            return self.state;
        }

        /// Public `afterGet` helper.
        pub fn afterGet(_: *@This(), _: i32) ExecResult(i32) {
            return error.AfterOops;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const CallType = @TypeOf(shift.with(&runtime, .{
        .counter = Counter.use(.{ .handler = Handler{} }),
    }, struct {
        /// Execute this public body hook.
        pub fn body(eff: anytype) ExecResult(i32) {
            return try eff.counter.get.perform();
        }
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "AfterOops"));
}

test "generated lexical transform handlers accept void state without a state field" {
    const Search = shift.effect.Define(.{
        .state_type = void,
        .ops = .{
            shift.effect.ops.Transform("query", []const u8, i32),
        },
    });

    const handler = struct {
        /// Return the canonical stateless search result.
        pub fn query(_: *@This(), payload: []const u8) i32 {
            return if (std.mem.eql(u8, payload, "artifact-search")) 3 else 0;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .search = Search.use(.{ .handler = handler{} }),
    }, struct {
        /// Execute one stateless generated transform through the lexical surface.
        pub fn body(eff: anytype) ExecResult(i32) {
            return try eff.search.query.perform("artifact-search");
        }
    });

    try std.testing.expectEqual(@as(i32, 3), result.value);
}

test "shift.with composes state and reader through lexical handles" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .state = shift.effect.state.use(@as(i32, 5)),
        .reader = shift.effect.reader.use(@as(i32, 21)),
    }, struct {
        /// Read from the lexical reader, update lexical state, and return the new state.
        pub fn body(eff: anytype) ExecResult(i32) {
            const env = try eff.reader.ask();
            const before = try eff.state.get();
            try eff.state.set(before + env);
            return try eff.state.get();
        }
    });

    try std.testing.expectEqual(@as(i32, 26), result.value);
    try std.testing.expectEqual(@as(i32, 26), result.outputs.state);
}

test "shift.with matches the state fixture transcript through lexical handles" {
    try expectFixtureTranscript("example_proof/fixtures/state_basic.txt", struct {
        fn run(writer: anytype) anyerror!void {
            var runtime = shift.Runtime.init(std.testing.allocator);
            defer runtime.deinit();

            const result = try shift.with(&runtime, .{
                .state = shift.effect.state.use(@as(i32, 5)),
            }, struct {
                /// Match the public state example transcript through lexical handles.
                pub fn body(eff: anytype) ExecResult(i32) {
                    const before = try eff.state.get();
                    try eff.state.set(before + 1);
                    return before + (try eff.state.get());
                }
            });

            try writer.print("before=5\nafter=6\nfinal_state={d}\nvalue={d}\n", .{ result.outputs.state, result.value });
        }
    }.run);
}

test "shift.with matches the reader fixture transcript through lexical handles" {
    try expectFixtureTranscript("example_proof/fixtures/reader_basic.txt", struct {
        fn run(writer: anytype) anyerror!void {
            var runtime = shift.Runtime.init(std.testing.allocator);
            defer runtime.deinit();

            const result = try shift.with(&runtime, .{
                .reader = shift.effect.reader.use(@as(i32, 21)),
            }, struct {
                /// Match the public reader example transcript through lexical handles.
                pub fn body(eff: anytype) ExecResult(i32) {
                    const env = try eff.reader.ask();
                    return env * 2;
                }
            });

            try writer.print("env=21\nvalue={d}\n", .{result.value});
        }
    }.run);
}

test "shift.with matches the optional fixture transcript through lexical handles" {
    try expectFixtureTranscript("example_proof/fixtures/optional_basic.txt", struct {
        fn run(writer: anytype) anyerror!void {
            const transcript = struct {
                threadlocal var active_writer: ?@TypeOf(writer) = null;

                fn note(message: []const u8) void {
                    active_writer.?.writeAll(message) catch unreachable;
                }
            };

            const return_now_policy = struct {
                /// Choose the direct-return branch for the lexical optional test.
                pub fn resumeOrReturn() shift.effect.choice.Decision(i32, []const u8) {
                    transcript.note("policy-return-now\n");
                    return shift.effect.choice.Decision(i32, []const u8).returnNow("result=early");
                }

                /// Preserve the early answer unchanged in the return-now branch.
                pub fn afterResume(answer: []const u8) []const u8 {
                    return answer;
                }
            };

            const resume_policy = struct {
                /// Resume the lexical optional request with the canonical value.
                pub fn resumeOrReturn() shift.effect.choice.Decision(i32, []const u8) {
                    transcript.note("policy-resume\n");
                    return shift.effect.choice.Decision(i32, []const u8).resumeWith(41);
                }

                /// Finalize the resumed lexical optional answer.
                pub fn afterResume(answer: []const u8) []const u8 {
                    transcript.note("policy-after-resume\n");
                    return answer;
                }
            };

            var runtime = shift.Runtime.init(std.testing.allocator);
            defer runtime.deinit();

            const previous_writer = transcript.active_writer;
            transcript.active_writer = writer;
            defer transcript.active_writer = previous_writer;

            try writer.writeAll("branch=return_now\n");
            const early = try shift.with(&runtime, .{
                .optional = shift.effect.optional.use(i32, return_now_policy),
            }, struct {
                /// Trigger the lexical optional choice point and prove the resume continuation is skipped.
                pub fn body(eff: anytype) ExecResult([]const u8) {
                    return try eff.optional.request(struct {
                        /// This continuation must never run in the return-now branch.
                        pub fn apply(_: i32, _: anytype) ExecResult([]const u8) {
                            unreachable;
                        }
                    });
                }
            });
            try writer.print("final={s}\n", .{early.value});

            try writer.writeAll("branch=resume_with\n");
            const resumed = try shift.with(&runtime, .{
                .optional = shift.effect.optional.use(i32, resume_policy),
            }, struct {
                /// Trigger the lexical optional choice point and complete the resumed continuation explicitly.
                pub fn body(eff: anytype) ExecResult([]const u8) {
                    return try eff.optional.request(struct {
                        /// Resume the lexical optional continuation with the canonical final answer.
                        pub fn apply(value: i32, _: anytype) ExecResult([]const u8) {
                            if (value != 41) unreachable;
                            transcript.note("body-after-request\n");
                            return "answer=42";
                        }
                    });
                }
            });
            try writer.print("final={s}\n", .{resumed.value});
        }
    }.run);
}

test "shift.with matches the exception fixture transcript through lexical handles" {
    try expectFixtureTranscript("example_proof/fixtures/exception_basic.txt", struct {
        fn run(writer: anytype) anyerror!void {
            const transcript = struct {
                threadlocal var active_writer: ?@TypeOf(writer) = null;

                fn note(message: []const u8) void {
                    active_writer.?.writeAll(message) catch unreachable;
                }
            };

            const catch_policy = struct {
                /// Recover one thrown payload into the final lexical answer.
                pub fn directReturn(payload: []const u8) []const u8 {
                    transcript.active_writer.?.print("catch={s}\n", .{payload}) catch unreachable;
                    return payload;
                }
            };

            var runtime = shift.Runtime.init(std.testing.allocator);
            defer runtime.deinit();

            const previous_writer = transcript.active_writer;
            transcript.active_writer = writer;
            defer transcript.active_writer = previous_writer;

            try writer.writeAll("branch=pass\n");
            const ok = try shift.with(&runtime, .{
                .exception = shift.effect.exception.use([]const u8, catch_policy),
            }, shift.NamedBody("test/lexical_with_test.zig", "namedExceptionPassBody", ExecResult([]const u8), namedExceptionPassBody));
            try writer.writeAll("body-pass\n");
            try writer.print("final={s}\n", .{ok.value});

            try writer.writeAll("branch=throw\n");
            try writer.writeAll("body-before-throw\n");
            const thrown = try shift.with(&runtime, .{
                .exception = shift.effect.exception.use([]const u8, catch_policy),
            }, shift.NamedBody("test/lexical_with_test.zig", "namedExceptionThrowBody", ExecResult([]const u8), namedExceptionThrowBody));
            try writer.print("final={s}\n", .{thrown.value});
        }
    }.run);
}

test "shift.with matches the resource fixture transcript through lexical handles" {
    try expectFixtureTranscript("example_proof/fixtures/resource_basic.txt", struct {
        fn run(writer: anytype) anyerror!void {
            const transcript = struct {
                threadlocal var active_writer: ?@TypeOf(writer) = null;

                fn note(message: []const u8) void {
                    active_writer.?.writeAll(message) catch unreachable;
                }
            };

            const resource_manager = struct {
                threadlocal var next_index: usize = 0;
                const resources = [_][]const u8{ "a", "b" };

                /// Acquire resources in the same order as the canonical example.
                pub fn acquire() []const u8 {
                    const resource = resources[next_index];
                    next_index += 1;
                    transcript.active_writer.?.print("acquire={s}\n", .{resource}) catch unreachable;
                    return resource;
                }

                /// Release resources in the canonical LIFO order.
                pub fn release(resource: []const u8) void {
                    transcript.active_writer.?.print("release={s}\n", .{resource}) catch unreachable;
                }
            };

            var runtime = shift.Runtime.init(std.testing.allocator);
            defer runtime.deinit();

            const previous_writer = transcript.active_writer;
            transcript.active_writer = writer;
            defer transcript.active_writer = previous_writer;
            resource_manager.next_index = 0;

            const result = try shift.with(&runtime, .{
                .resource = shift.effect.resource.use([]const u8, resource_manager),
            }, struct {
                /// Acquire and use two resources through the lexical scope.
                pub fn body(eff: anytype) ExecResult([]const u8) {
                    const first = try eff.resource.acquire();
                    transcript.note("use=");
                    transcript.note(first);
                    transcript.note("\n");

                    const second = try eff.resource.acquire();
                    transcript.note("use=");
                    transcript.note(second);
                    transcript.note("\n");

                    return "done";
                }
            });

            try writer.print("final={s}\n", .{result.value});
        }
    }.run);
}

test "shift.with matches the writer fixture transcript through lexical handles" {
    try expectFixtureTranscript("example_proof/fixtures/writer_basic.txt", struct {
        fn run(writer: anytype) anyerror!void {
            var runtime = shift.Runtime.init(std.testing.allocator);
            defer runtime.deinit();

            const result = try shift.with(&runtime, .{
                .writer = shift.effect.writer.use([]const u8, std.testing.allocator),
            }, struct {
                /// Append two items and return the canonical writer answer.
                pub fn body(eff: anytype) ExecResult([]const u8) {
                    try eff.writer.tell("a");
                    try eff.writer.tell("b");
                    return "done";
                }
            });
            defer std.testing.allocator.free(result.outputs.writer);

            for (result.outputs.writer) |item| {
                try writer.print("item={s}\n", .{item});
            }
            try writer.print("value={s}\n", .{result.value});
        }
    }.run);
}

test "generated choice families use the lexical choice form" {
    const Picker = shift.effect.Define(.{
        .state_type = struct {},
        .ops = .{
            shift.effect.ops.Choice("pick", i32, i32),
        },
    });

    try expectFixtureTranscript("example_proof/fixtures/optional_basic.txt", struct {
        fn run(writer: anytype) anyerror!void {
            const transcript = struct {
                threadlocal var active_writer: ?@TypeOf(writer) = null;

                fn note(message: []const u8) void {
                    active_writer.?.writeAll(message) catch unreachable;
                }
            };

            const return_now_handler = struct {
                /// Return now for the generated lexical choice family.
                pub fn pick(_: *@This(), _: i32) shift.effect.choice.Decision(i32, []const u8) {
                    transcript.note("policy-return-now\n");
                    return shift.effect.choice.Decision(i32, []const u8).returnNow("result=early");
                }

                /// Preserve the early answer unchanged.
                pub fn afterPick(_: *@This(), answer: []const u8) []const u8 {
                    return answer;
                }
            };

            const resume_handler = struct {
                /// Resume with the canonical generated choice value.
                pub fn pick(_: *@This(), payload: i32) shift.effect.choice.Decision(i32, []const u8) {
                    transcript.note("policy-resume\n");
                    return shift.effect.choice.Decision(i32, []const u8).resumeWith(payload);
                }

                /// Finalize the resumed generated choice answer.
                pub fn afterPick(_: *@This(), answer: []const u8) []const u8 {
                    transcript.note("policy-after-resume\n");
                    return answer;
                }
            };

            var runtime = shift.Runtime.init(std.testing.allocator);
            defer runtime.deinit();

            const previous_writer = transcript.active_writer;
            transcript.active_writer = writer;
            defer transcript.active_writer = previous_writer;

            try writer.writeAll("branch=return_now\n");
            const early = try shift.with(&runtime, .{
                .picker = Picker.use(.{ .handler = return_now_handler{} }),
            }, struct {
                /// Trigger the generated lexical choice point and prove the continuation is skipped.
                pub fn body(eff: anytype) ExecResult([]const u8) {
                    return try eff.picker.pick.perform(41, struct {
                        /// This generated continuation must never run in the return-now branch.
                        pub fn apply(_: i32, _: anytype) ExecResult([]const u8) {
                            unreachable;
                        }
                    });
                }
            });
            try writer.print("final={s}\n", .{early.value});

            try writer.writeAll("branch=resume_with\n");
            const resumed = try shift.with(&runtime, .{
                .picker = Picker.use(.{ .handler = resume_handler{} }),
            }, struct {
                /// Trigger the generated lexical choice point and complete the explicit continuation.
                pub fn body(eff: anytype) ExecResult([]const u8) {
                    return try eff.picker.pick.perform(41, struct {
                        /// Resume the generated lexical choice continuation with the canonical final answer.
                        pub fn apply(value: i32, _: anytype) ExecResult([]const u8) {
                            if (value != 41) unreachable;
                            transcript.note("body-after-request\n");
                            return "answer=42";
                        }
                    });
                }
            });
            try writer.print("final={s}\n", .{resumed.value});
        }
    }.run);
}

test "generated abort families use the lexical abort form" {
    const Guard = shift.effect.Define(.{
        .state_type = struct {},
        .ops = .{
            shift.effect.ops.Abort("fail", []const u8),
        },
    });

    try expectFixtureTranscript("example_proof/fixtures/open_row_abortive_validation.txt", struct {
        fn run(writer: anytype) anyerror!void {
            const transcript = struct {
                threadlocal var active_writer: ?@TypeOf(writer) = null;

                fn note(message: []const u8) void {
                    active_writer.?.writeAll(message) catch unreachable;
                }
            };

            const guard_handler = struct {
                /// Validate one missing name and return the canonical generated abort answer.
                pub fn fail(_: *@This(), payload: []const u8) []const u8 {
                    transcript.active_writer.?.print("abort={s}\n", .{payload}) catch unreachable;
                    return "error=missing-name";
                }
            };

            var runtime = shift.Runtime.init(std.testing.allocator);
            defer runtime.deinit();

            const previous_writer = transcript.active_writer;
            transcript.active_writer = writer;
            defer transcript.active_writer = previous_writer;

            try writer.writeAll("validate=name\n");
            const result = try shift.with(&runtime, .{
                .guard = Guard.use(.{ .handler = guard_handler{} }),
            }, shift.NamedBody("test/lexical_with_test.zig", "namedGeneratedAbortBody", ExecResult([]const u8), namedGeneratedAbortBody));
            try writer.print("final={s}\n", .{result.value});
        }
    }.run);
}

test "generated zero-payload choice fields stay ergonomic" {
    const Ask = shift.effect.Define(.{
        .state_type = struct {},
        .ops = .{
            shift.effect.ops.Choice("ask", void, i32),
        },
    });

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .asker = Ask.use(.{ .handler = struct {
            /// Resume a zero-payload generated choice with a fixed value.
            pub fn ask(_: *@This()) shift.effect.choice.Decision(i32, []const u8) {
                return shift.effect.choice.Decision(i32, []const u8).resumeWith(7);
            }

            /// Preserve the resumed answer unchanged.
            pub fn afterAsk(_: *@This(), answer: []const u8) []const u8 {
                return answer;
            }
        }{} }),
    }, struct {
        /// Trigger a zero-payload generated lexical choice op with no payload argument.
        pub fn body(eff: anytype) ExecResult([]const u8) {
            return try eff.asker.ask.perform(struct {
                /// Convert the resumed generated answer into the final lexical result.
                pub fn apply(value: i32, _: anytype) ExecResult([]const u8) {
                    if (value != 7) unreachable;
                    return "answer=7";
                }
            });
        }
    });

    try std.testing.expectEqualStrings("answer=7", result.value);
}

test "shift.with accepts body run(eff)" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .state = shift.effect.state.use(@as(i32, 9)),
    }, struct {
        /// Run the body through the declared one-argument `run` hook.
        pub fn run(eff: anytype) ExecResult(i32) {
            return try eff.state.get();
        }
    });

    try std.testing.expectEqual(@as(i32, 9), result.value);
}

test "shift.with accepts body run(self, eff)" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .state = shift.effect.state.use(@as(i32, 11)),
    }, struct {
        /// Run the body through the declared self-plus-eff `run` hook.
        pub fn run(self: @This(), eff: anytype) ExecResult(i32) {
            _ = self;
            return try eff.state.get();
        }
    });

    try std.testing.expectEqual(@as(i32, 11), result.value);
}

test "shift.with accepts NamedBody for state handlers" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .state = shift.effect.state.use(@as(i32, 9)),
    }, shift.NamedBody("test/lexical_with_test.zig", "namedStateBody", ExecResult(i32), namedStateBody));

    try std.testing.expectEqual(@as(i32, 19), result.value);
    try std.testing.expectEqual(@as(i32, 10), result.outputs.state);
}

test "shift.with accepts NamedBody helpers when the effect parameter is renamed" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .state = shift.effect.state.use(@as(i32, 9)),
    }, shift.NamedBody("test/lexical_with_test.zig", "namedStateBodyWithRenamedEffectParam", ExecResult(i32), namedStateBodyWithRenamedEffectParam));

    try std.testing.expectEqual(@as(i32, 9), result.value);
    try std.testing.expectEqual(@as(i32, 9), result.outputs.state);
}

test "shift.with accepts NamedBody for reader handlers" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .reader = shift.effect.reader.use(@as(i32, 21)),
    }, shift.NamedBody("test/lexical_with_test.zig", "namedReaderBody", ExecResult(i32), namedReaderBody));

    try std.testing.expectEqual(@as(i32, 42), result.value);
}

test "shift.with accepts NamedBody for writer handlers" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .writer = shift.effect.writer.use([]const u8, std.testing.allocator),
    }, shift.NamedBody("test/lexical_with_test.zig", "namedWriterBody", ExecResult([]const u8), namedWriterBody));
    defer std.testing.allocator.free(result.outputs.writer);

    try std.testing.expectEqual(@as(usize, 2), result.outputs.writer.len);
    try std.testing.expectEqualStrings("a", result.outputs.writer[0]);
    try std.testing.expectEqualStrings("b", result.outputs.writer[1]);
    try std.testing.expectEqualStrings("done", result.value);
}

test "shift.with accepts NamedBody bool literal returns" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .state = shift.effect.state.use(@as(i32, 0)),
    }, shift.NamedBody(
        "test/lexical_with_test.zig",
        "namedBoolLiteralBody",
        ExecResult(bool),
        namedBoolLiteralBody,
    ));

    try std.testing.expectEqual(true, result.value);
}

test "shift.with accepts NamedBody usize literal returns" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .state = shift.effect.state.use(@as(i32, 0)),
    }, shift.NamedBody(
        "test/lexical_with_test.zig",
        "namedUsizeLiteralBody",
        ExecResult(usize),
        namedUsizeLiteralBody,
    ));

    try std.testing.expectEqual(@as(usize, 1), result.value);
}

test "shift.with accepts NamedBody bool payload literals for state handlers" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .state = shift.effect.state.use(false),
    }, shift.NamedBody("test/lexical_with_test.zig", "namedBoolStateBody", ExecResult(bool), namedBoolStateBody));

    try std.testing.expectEqual(true, result.value);
    try std.testing.expectEqual(true, result.outputs.state);
}

test "shift.with accepts NamedBody for optional return-now continuations" {
    const return_now_policy = struct {
        /// Return immediately so the continuation stays dormant.
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, []const u8) {
            return shift.effect.choice.Decision(i32, []const u8).returnNow("result=early");
        }

        /// Preserve the early answer unchanged.
        pub fn afterResume(answer: []const u8) []const u8 {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .optional = shift.effect.optional.use(i32, return_now_policy),
    }, shift.NamedBody("test/lexical_with_test.zig", "namedOptionalReturnNowBody", ExecResult([]const u8), namedOptionalReturnNowBody));

    try std.testing.expectEqualStrings("result=early", result.value);
}

test "shift.with accepts NamedBody for optional resumed continuations" {
    const resume_policy = struct {
        /// Resume with the canonical test payload.
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, []const u8) {
            return shift.effect.choice.Decision(i32, []const u8).resumeWith(41);
        }

        /// Preserve the resumed answer unchanged.
        pub fn afterResume(answer: []const u8) []const u8 {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .optional = shift.effect.optional.use(i32, resume_policy),
    }, shift.NamedBody("test/lexical_with_test.zig", "namedOptionalResumeBody", ExecResult([]const u8), namedOptionalResumeBody));

    try std.testing.expectEqualStrings("answer=42", result.value);
}

test "shift.with accepts NamedBody bool literal continuation answers" {
    const resume_policy = struct {
        /// Resume with the canonical bool payload.
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, bool) {
            return shift.effect.choice.Decision(i32, bool).resumeWith(41);
        }

        /// Preserve the resumed bool answer unchanged.
        pub fn afterResume(answer: bool) bool {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .optional = shift.effect.optional.use(i32, resume_policy),
    }, shift.NamedBody("test/lexical_with_test.zig", "namedOptionalResumeBoolBody", ExecResult(bool), namedOptionalResumeBoolBody));

    try std.testing.expectEqual(true, result.value);
}

test "shift.with accepts NamedBody usize literal continuation answers" {
    const resume_policy = struct {
        /// Resume with the canonical usize payload.
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, usize) {
            return shift.effect.choice.Decision(i32, usize).resumeWith(41);
        }

        /// Preserve the resumed usize answer unchanged.
        pub fn afterResume(answer: usize) usize {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .optional = shift.effect.optional.use(i32, resume_policy),
    }, shift.NamedBody("test/lexical_with_test.zig", "namedOptionalResumeUsizeBody", ExecResult(usize), namedOptionalResumeUsizeBody));

    try std.testing.expectEqual(@as(usize, 1), result.value);
}

test "shift.with accepts NamedBody for generated choice continuations" {
    const Picker = shift.effect.Define(.{
        .state_type = void,
        .ops = .{
            shift.effect.ops.Choice("pick", i32, i32),
        },
    });

    const handler = struct {
        /// Resume the generated choice with the provided payload.
        pub fn pick(_: *@This(), value: i32) shift.effect.choice.Decision(i32, []const u8) {
            return shift.effect.choice.Decision(i32, []const u8).resumeWith(value);
        }

        /// Preserve the resumed choice answer unchanged.
        pub fn afterPick(_: *@This(), answer: []const u8) []const u8 {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .picker = Picker.use(.{ .handler = handler{} }),
    }, shift.NamedBody("test/lexical_with_test.zig", "namedGeneratedChoiceBody", ExecResult([]const u8), namedGeneratedChoiceBody));

    try std.testing.expectEqualStrings("answer=42", result.value);
}

test "shift.with accepts NamedBody for underscored generated choice after hooks" {
    const Picker = shift.effect.Define(.{
        .state_type = void,
        .ops = .{
            shift.effect.ops.Choice("pick_item", i32, i32),
        },
    });

    const transcript = struct {
        threadlocal var after_called = false;
    };

    const handler = struct {
        /// Resume the generated choice with the provided payload.
        pub fn pick_item(_: *@This(), value: i32) shift.effect.choice.Decision(i32, []const u8) {
            return shift.effect.choice.Decision(i32, []const u8).resumeWith(value);
        }

        /// Preserve the resumed choice answer unchanged.
        pub fn afterPickItem(_: *@This(), answer: []const u8) []const u8 {
            transcript.after_called = true;
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    transcript.after_called = false;

    const result = try shift.with(&runtime, .{
        .picker = Picker.use(.{ .handler = handler{} }),
    }, shift.NamedBody("test/lexical_with_test.zig", "namedGeneratedChoiceUnderscoreBody", ExecResult([]const u8), namedGeneratedChoiceUnderscoreBody));

    try std.testing.expect(transcript.after_called);
    try std.testing.expectEqualStrings("answer=42", result.value);
}
