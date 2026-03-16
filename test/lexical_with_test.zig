const shift = @import("shift");
const std = @import("std");

const NoError = error{};

fn expectFixtureTranscript(comptime fixture_path: []const u8, writer_fn: anytype) !void {
    var buffer: std.io.Writer.Allocating = .init(std.testing.allocator);
    defer buffer.deinit();
    try writer_fn(&buffer.writer);
    try std.testing.expectEqualStrings(@embedFile(fixture_path), buffer.written());
}

test "shift.with composes state and reader through lexical handles" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .state = shift.effect.state.use(NoError, @as(i32, 5)),
        .reader = shift.effect.reader.use(NoError, @as(i32, 21)),
    }, struct {
        /// Read from the lexical reader, update lexical state, and return the new state.
        pub fn body(eff: anytype) shift.ResetError(NoError)!i32 {
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
        fn run(writer: anytype) !void {
            var runtime = shift.Runtime.init(std.testing.allocator);
            defer runtime.deinit();

            const result = try shift.with(&runtime, .{
                .state = shift.effect.state.use(NoError, @as(i32, 5)),
            }, struct {
                /// Match the public state example transcript through lexical handles.
                pub fn body(eff: anytype) shift.ResetError(NoError)!i32 {
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
        fn run(writer: anytype) !void {
            var runtime = shift.Runtime.init(std.testing.allocator);
            defer runtime.deinit();

            const result = try shift.with(&runtime, .{
                .reader = shift.effect.reader.use(NoError, @as(i32, 21)),
            }, struct {
                /// Match the public reader example transcript through lexical handles.
                pub fn body(eff: anytype) shift.ResetError(NoError)!i32 {
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
        fn run(writer: anytype) !void {
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
                .optional = shift.effect.optional.use(i32, NoError, return_now_policy),
            }, struct {
                /// Trigger the lexical optional choice point and prove the resume continuation is skipped.
                pub fn body(eff: anytype) shift.ResetError(NoError)![]const u8 {
                    return try eff.optional.request(struct {
                        /// This continuation must never run in the return-now branch.
                        pub fn apply(_: i32, _: anytype) shift.ResetError(NoError)![]const u8 {
                            unreachable;
                        }
                    });
                }
            });
            try writer.print("final={s}\n", .{early.value});

            try writer.writeAll("branch=resume_with\n");
            const resumed = try shift.with(&runtime, .{
                .optional = shift.effect.optional.use(i32, NoError, resume_policy),
            }, struct {
                /// Trigger the lexical optional choice point and complete the resumed continuation explicitly.
                pub fn body(eff: anytype) shift.ResetError(NoError)![]const u8 {
                    return try eff.optional.request(struct {
                        /// Resume the lexical optional continuation with the canonical final answer.
                        pub fn apply(value: i32, _: anytype) shift.ResetError(NoError)![]const u8 {
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
        fn run(writer: anytype) !void {
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
                .exception = shift.effect.exception.use([]const u8, NoError, catch_policy),
            }, struct {
                /// Return normally through the lexical exception scope.
                pub fn body(_: anytype) shift.ResetError(NoError)![]const u8 {
                    return "result=ok";
                }
            });
            try writer.writeAll("body-pass\n");
            try writer.print("final={s}\n", .{ok.value});

            try writer.writeAll("branch=throw\n");
            const thrown = try shift.with(&runtime, .{
                .exception = shift.effect.exception.use([]const u8, NoError, catch_policy),
            }, struct {
                /// Throw once through the lexical exception scope.
                pub fn body(eff: anytype) shift.ResetError(NoError)![]const u8 {
                    transcript.note("body-before-throw\n");
                    try eff.exception.throw("result=boom");
                }
            });
            try writer.print("final={s}\n", .{thrown.value});
        }
    }.run);
}

test "shift.with matches the resource fixture transcript through lexical handles" {
    try expectFixtureTranscript("example_proof/fixtures/resource_basic.txt", struct {
        fn run(writer: anytype) !void {
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
                .resource = shift.effect.resource.use([]const u8, NoError, resource_manager),
            }, struct {
                /// Acquire and use two resources through the lexical scope.
                pub fn body(eff: anytype) shift.ResetError(NoError)![]const u8 {
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
        fn run(writer: anytype) !void {
            var runtime = shift.Runtime.init(std.testing.allocator);
            defer runtime.deinit();

            const result = try shift.with(&runtime, .{
                .writer = shift.effect.writer.use([]const u8, NoError, std.testing.allocator),
            }, struct {
                /// Append two items and return the canonical writer answer.
                pub fn body(eff: anytype) shift.ResetError(NoError)![]const u8 {
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
        .error_set_type = NoError,
        .ops = .{
            shift.effect.ops.Choice("pick", i32, i32),
        },
    });

    try expectFixtureTranscript("example_proof/fixtures/optional_basic.txt", struct {
        fn run(writer: anytype) !void {
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
                pub fn body(eff: anytype) shift.ResetError(NoError)![]const u8 {
                    return try eff.picker.pick.perform(41, struct {
                        /// This generated continuation must never run in the return-now branch.
                        pub fn apply(_: i32, _: anytype) shift.ResetError(NoError)![]const u8 {
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
                pub fn body(eff: anytype) shift.ResetError(NoError)![]const u8 {
                    return try eff.picker.pick.perform(41, struct {
                        /// Resume the generated lexical choice continuation with the canonical final answer.
                        pub fn apply(value: i32, _: anytype) shift.ResetError(NoError)![]const u8 {
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
        .error_set_type = NoError,
        .ops = .{
            shift.effect.ops.Abort("fail", []const u8),
        },
    });

    try expectFixtureTranscript("example_proof/fixtures/algebraic_abortive_validation.txt", struct {
        fn run(writer: anytype) !void {
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
            }, struct {
                /// Trigger the generated lexical abort point directly.
                pub fn body(eff: anytype) shift.ResetError(NoError)![]const u8 {
                    try eff.guard.fail.abort("missing-name");
                }
            });
            try writer.print("final={s}\n", .{result.value});
        }
    }.run);
}

test "generated zero-payload choice fields stay ergonomic" {
    const Ask = shift.effect.Define(.{
        .state_type = struct {},
        .error_set_type = NoError,
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
        pub fn body(eff: anytype) shift.ResetError(NoError)![]const u8 {
            return try eff.asker.ask.perform(struct {
                /// Convert the resumed generated answer into the final lexical result.
                pub fn apply(value: i32, _: anytype) shift.ResetError(NoError)![]const u8 {
                    if (value != 7) unreachable;
                    return "answer=7";
                }
            });
        }
    });

    try std.testing.expectEqualStrings("answer=7", result.value);
}
