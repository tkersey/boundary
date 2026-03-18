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
        pub fn body(ctx: anytype) !i32 {
            return try ctx.perform(ping, {});
        }
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "HandlerOops"));
    try std.testing.expectError(error.HandlerOops, configured.run(&runtime, struct {
        pub fn body(ctx: anytype) !i32 {
            return try ctx.perform(ping, {});
        }
    }));
}

test "algebraic Program retains generic body errors on the public wrapper" {
    const no_state = struct {};
    const ping = shift.algebraic.TransformOp("ping", void, i32);
    const program = shift.algebraic.Program(i32, .{ping});
    const configured = program.handlers(.{
        shift.algebraic.handleTransform(ping, no_state{}, struct {
            pub fn resumeValue(_: no_state, _: void) i32 {
                return 7;
            }
            pub fn afterResume(_: no_state, answer: i32) i32 {
                return answer;
            }
        }),
    });

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const CallType = @TypeOf(configured.run(&runtime, struct {
        pub fn body(_: anytype) !i32 {
            return error.BodyOops;
        }
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "BodyOops"));
    try std.testing.expectError(error.BodyOops, configured.run(&runtime, struct {
        pub fn body(_: anytype) !i32 {
            return error.BodyOops;
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

test "generated family handle retains generic body errors when error_set_type is omitted" {
    const Counter = shift.effect.Define(.{
        .state_type = i32,
        .ops = .{
            shift.effect.ops.Transform("get", void, i32),
        },
    });

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = Counter.Instance.init();

    const handler = struct {
        state: i32 = 7,

        pub fn get(self: *@This()) i32 {
            return self.state;
        }

        pub fn afterGet(_: *@This(), answer: i32) i32 {
            return answer;
        }
    };

    const CallType = @TypeOf(Counter.handle(i32, &runtime, &instance, handler{}, struct {
        pub fn body(comptime Cap: type, ctx: anytype) !i32 {
            _ = try Counter.Op(.get).perform(Cap, ctx);
            return error.BodyOops;
        }
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "BodyOops"));
    try std.testing.expectError(error.BodyOops, Counter.handle(i32, &runtime, &instance, handler{}, struct {
        pub fn body(comptime Cap: type, ctx: anytype) !i32 {
            _ = try Counter.Op(.get).perform(Cap, ctx);
            return error.BodyOops;
        }
    }));
}

test "generated family proof helper retains generic body errors when error_set_type is omitted" {
    const Counter = shift.effect.Define(.{
        .state_type = i32,
        .ops = .{
            shift.effect.ops.Transform("get", void, i32),
        },
    });

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = Counter.Instance.init();

    const handler = struct {
        state: i32 = 7,

        pub fn get(self: *@This()) i32 {
            return self.state;
        }

        pub fn afterGet(_: *@This(), answer: i32) i32 {
            return answer;
        }
    };

    const CallType = @TypeOf(Counter.proof.exampleHarness(i32, &runtime, &instance, handler{}, struct {
        pub fn body(comptime Cap: type, ctx: anytype) !i32 {
            _ = try Counter.Op(.get).perform(Cap, ctx);
            return error.BodyOops;
        }
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "BodyOops"));
    try std.testing.expectError(error.BodyOops, Counter.proof.exampleHarness(i32, &runtime, &instance, handler{}, struct {
        pub fn body(comptime Cap: type, ctx: anytype) !i32 {
            _ = try Counter.Op(.get).perform(Cap, ctx);
            return error.BodyOops;
        }
    }));
}

test "generated family proof helper retains handler errors when error_set_type is omitted" {
    const Counter = shift.effect.Define(.{
        .state_type = i32,
        .ops = .{
            shift.effect.ops.Transform("get", void, i32),
        },
    });

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = Counter.Instance.init();

    const handler = struct {
        state: i32 = 0,

        pub fn get(_: *@This()) !i32 {
            return error.HandlerOops;
        }

        pub fn afterGet(_: *@This(), answer: i32) i32 {
            return answer;
        }
    };

    const CallType = @TypeOf(Counter.proof.exampleHarness(i32, &runtime, &instance, handler{}, struct {
        pub fn body(comptime Cap: type, ctx: anytype) !i32 {
            return try Counter.Op(.get).perform(Cap, ctx);
        }
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "HandlerOops"));
    try std.testing.expectError(error.HandlerOops, Counter.proof.exampleHarness(i32, &runtime, &instance, handler{}, struct {
        pub fn body(comptime Cap: type, ctx: anytype) !i32 {
            return try Counter.Op(.get).perform(Cap, ctx);
        }
    }));
}

test "generated abort proof helper retains handler errors when error_set_type is omitted" {
    const Guard = shift.effect.Define(.{
        .state_type = struct {},
        .ops = .{
            shift.effect.ops.Abort("fail", []const u8),
        },
    });

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = Guard.Instance.init();

    const handler = struct {
        pub fn fail(_: *@This(), _: []const u8) !i32 {
            return error.HandlerOops;
        }
    };

    const CallType = @TypeOf(Guard.proof.exampleHarness(i32, &runtime, &instance, handler{}, struct {
        pub fn body(comptime Cap: type, ctx: anytype) !i32 {
            try Guard.Op(.fail).perform(Cap, ctx, "boom");
        }
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "HandlerOops"));
    try std.testing.expectError(error.HandlerOops, Guard.proof.exampleHarness(i32, &runtime, &instance, handler{}, struct {
        pub fn body(comptime Cap: type, ctx: anytype) !i32 {
            try Guard.Op(.fail).perform(Cap, ctx, "boom");
        }
    }));
}

test "state Instance plus handle preserves custom body errors" {
    const DemoError = error{BodyOops};

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = shift.effect.state.Instance(i32, DemoError).init();

    const CallType = @TypeOf(shift.effect.state.handle(i32, &runtime, &instance, 0, struct {
        pub fn body(_: type, _: anytype) DemoError!i32 {
            return error.BodyOops;
        }
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "BodyOops"));
    try std.testing.expectError(error.BodyOops, shift.effect.state.handle(i32, &runtime, &instance, 0, struct {
        pub fn body(_: type, _: anytype) DemoError!i32 {
            return error.BodyOops;
        }
    }));
}

test "reader Instance plus handle preserves custom body errors" {
    const DemoError = error{BodyOops};

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = shift.effect.reader.Instance(i32, DemoError).init();

    const CallType = @TypeOf(shift.effect.reader.handle(i32, &runtime, &instance, 7, struct {
        pub fn body(_: type, _: anytype) DemoError!i32 {
            return error.BodyOops;
        }
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "BodyOops"));
    try std.testing.expectError(error.BodyOops, shift.effect.reader.handle(i32, &runtime, &instance, 7, struct {
        pub fn body(_: type, _: anytype) DemoError!i32 {
            return error.BodyOops;
        }
    }));
}

test "optional Instance plus handle preserves custom body errors" {
    const DemoError = error{BodyOops};
    const policy = struct {
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, i32) {
            return shift.effect.choice.Decision(i32, i32).resumeWith(1);
        }

        pub fn afterResume(answer: i32) i32 {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = shift.effect.optional.Instance(i32, DemoError).init();

    const CallType = @TypeOf(shift.effect.optional.handle(i32, &runtime, &instance, policy, struct {
        pub fn body(_: type, _: anytype) DemoError!i32 {
            return error.BodyOops;
        }
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "BodyOops"));
    try std.testing.expectError(error.BodyOops, shift.effect.optional.handle(i32, &runtime, &instance, policy, struct {
        pub fn body(_: type, _: anytype) DemoError!i32 {
            return error.BodyOops;
        }
    }));
}

test "optional handleWithErrorSet widens explicit continuation errors for empty instances" {
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
    var instance = shift.effect.optional.Instance(i32, error{}).init();

    const CallType = @TypeOf(shift.effect.optional.handleWithErrorSet(i32, error{ContinueOops}, &runtime, &instance, policy, struct {
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(shift.effect.optional.requestProgram(Cap, ctx, struct {
            pub fn apply(_: i32) !i32 {
                return error.ContinueOops;
            }
        })) {
            return shift.effect.optional.requestProgram(Cap, ctx, struct {
                pub fn apply(_: i32) !i32 {
                    return error.ContinueOops;
                }
            });
        }
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "ContinueOops"));
    try std.testing.expectError(error.ContinueOops, shift.effect.optional.handleWithErrorSet(i32, error{ContinueOops}, &runtime, &instance, policy, struct {
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(shift.effect.optional.requestProgram(Cap, ctx, struct {
            pub fn apply(_: i32) !i32 {
                return error.ContinueOops;
            }
        })) {
            return shift.effect.optional.requestProgram(Cap, ctx, struct {
                pub fn apply(_: i32) !i32 {
                    return error.ContinueOops;
                }
            });
        }
    }));
}

test "optional handleWithErrorSet widens explicit body errors for empty instances" {
    const policy = struct {
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, i32) {
            return shift.effect.choice.Decision(i32, i32).resumeWith(1);
        }

        pub fn afterResume(answer: i32) i32 {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = shift.effect.optional.Instance(i32, error{}).init();

    const CallType = @TypeOf(shift.effect.optional.handleWithErrorSet(i32, error{BodyOops}, &runtime, &instance, policy, struct {
        pub fn body(_: type, _: anytype) !i32 {
            return error.BodyOops;
        }
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "BodyOops"));
    try std.testing.expectError(error.BodyOops, shift.effect.optional.handleWithErrorSet(i32, error{BodyOops}, &runtime, &instance, policy, struct {
        pub fn body(_: type, _: anytype) !i32 {
            return error.BodyOops;
        }
    }));
}

test "exception Instance plus handle preserves custom body errors" {
    const DemoError = error{BodyOops};
    const catcher = struct {
        pub fn directReturn(_: i32) i32 {
            return 0;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = shift.effect.exception.Instance(i32, DemoError).init();

    const CallType = @TypeOf(shift.effect.exception.handle(i32, &runtime, &instance, catcher, struct {
        pub fn body(_: type, _: anytype) DemoError!i32 {
            return error.BodyOops;
        }
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "BodyOops"));
    try std.testing.expectError(error.BodyOops, shift.effect.exception.handle(i32, &runtime, &instance, catcher, struct {
        pub fn body(_: type, _: anytype) DemoError!i32 {
            return error.BodyOops;
        }
    }));
}

test "writer Instance plus handle preserves custom body errors" {
    const DemoError = error{BodyOops};

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = shift.effect.writer.Instance([]const u8, DemoError).init();

    const CallType = @TypeOf(shift.effect.writer.handle([]const u8, i32, &runtime, &instance, std.testing.allocator, struct {
        pub fn body(_: type, _: anytype) DemoError!i32 {
            return error.BodyOops;
        }
    }));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "BodyOops"));
    try std.testing.expectError(error.BodyOops, shift.effect.writer.handle([]const u8, i32, &runtime, &instance, std.testing.allocator, struct {
        pub fn body(_: type, _: anytype) DemoError!i32 {
            return error.BodyOops;
        }
    }));
}

test "algebraic Program infers authored program errors on the public wrapper" {
    const no_state = struct {};
    const ping = shift.algebraic.TransformOp("ping", void, i32);
    const algebraic_builder = shift.algebraic.Program(i32, .{ping});
    const configured = algebraic_builder.handlers(.{
        shift.algebraic.handleTransform(ping, no_state{}, struct {
            pub fn resumeValue(_: no_state, _: void) i32 {
                return 7;
            }
            pub fn afterResume(_: no_state, answer: i32) i32 {
                return answer;
            }
        }),
    });

    const Body = struct {
        const PromptType = prompt_support.Prompt(.resume_then_transform, i32, i32, error{ProgramOops});
        const ProgramType = prompt_support.frontend.Program(PromptType);
        const ComputeReturn = @typeInfo(@typeInfo(@FieldType(ProgramType, "compute")).pointer.child).@"fn".return_type.?;
        threadlocal var prompt: PromptType = undefined;

        pub fn program(_: anytype) prompt_support.frontend.BoundProgram(PromptType) {
            prompt = PromptType.init();
            return .{
                .prompt = &prompt,
                .program = ProgramType{ .compute = struct {
                    pub fn invoke() ComputeReturn {
                        return error.ProgramOops;
                    }
                }.invoke },
            };
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const CallType = @TypeOf(configured.run(&runtime, Body));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "ProgramOops"));
    try std.testing.expectError(error.ProgramOops, configured.run(&runtime, Body));
}

test "algebraic Program infers continuation errors in explicit program bodies" {
    const no_state = struct {};
    const ping = shift.algebraic.TransformOp("ping", void, i32);
    const algebraic_builder = shift.algebraic.Program(i32, .{ping});
    const configured = algebraic_builder.handlers(.{
        shift.algebraic.handleTransform(ping, no_state{}, struct {
            pub fn resumeValue(_: no_state, _: void) i32 {
                return 7;
            }
            pub fn afterResume(_: no_state, answer: i32) i32 {
                return answer;
            }
        }),
    });

    const Body = struct {
        pub fn program(ctx: *@TypeOf(configured).Context) @TypeOf(ctx.performProgram(ping, {}, struct {
            pub fn apply(_: i32) !i32 {
                return error.ContinueOops;
            }
        })) {
            return ctx.performProgram(ping, {}, struct {
                pub fn apply(_: i32) !i32 {
                    return error.ContinueOops;
                }
            });
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const CallType = @TypeOf(configured.run(&runtime, Body));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "ContinueOops"));
    try std.testing.expectError(error.ContinueOops, configured.run(&runtime, Body));
}

test "generated family handle infers authored program errors" {
    const Counter = shift.effect.Define(.{
        .state_type = i32,
        .ops = .{
            shift.effect.ops.Transform("get", void, i32),
        },
    });

    const handler = struct {
        state: i32 = 7,

        pub fn get(self: *@This()) i32 {
            return self.state;
        }

        pub fn afterGet(_: *@This(), answer: i32) i32 {
            return answer;
        }
    };

    const Body = struct {
        const PromptType = prompt_support.Prompt(.resume_then_transform, i32, i32, error{ProgramOops});
        const ProgramType = prompt_support.frontend.Program(PromptType);
        const ComputeReturn = @typeInfo(@typeInfo(@FieldType(ProgramType, "compute")).pointer.child).@"fn".return_type.?;
        threadlocal var prompt: PromptType = undefined;

        pub fn program(_: type, _: anytype) prompt_support.frontend.BoundProgram(PromptType) {
            prompt = PromptType.init();
            return .{
                .prompt = &prompt,
                .program = ProgramType{ .compute = struct {
                    pub fn invoke() ComputeReturn {
                        return error.ProgramOops;
                    }
                }.invoke },
            };
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = Counter.Instance.init();

    const CallType = @TypeOf(Counter.handle(i32, &runtime, &instance, handler{}, Body));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "ProgramOops"));
    try std.testing.expectError(error.ProgramOops, Counter.handle(i32, &runtime, &instance, handler{}, Body));
}

test "generated family proof helper infers authored program errors" {
    const Counter = shift.effect.Define(.{
        .state_type = i32,
        .ops = .{
            shift.effect.ops.Transform("get", void, i32),
        },
    });

    const handler = struct {
        state: i32 = 7,

        pub fn get(self: *@This()) i32 {
            return self.state;
        }

        pub fn afterGet(_: *@This(), answer: i32) i32 {
            return answer;
        }
    };

    const Body = struct {
        const PromptType = prompt_support.Prompt(.resume_then_transform, i32, i32, error{ProgramOops});
        const ProgramType = prompt_support.frontend.Program(PromptType);
        const ComputeReturn = @typeInfo(@typeInfo(@FieldType(ProgramType, "compute")).pointer.child).@"fn".return_type.?;
        threadlocal var prompt: PromptType = undefined;

        pub fn program(_: type, _: anytype) prompt_support.frontend.BoundProgram(PromptType) {
            prompt = PromptType.init();
            return .{
                .prompt = &prompt,
                .program = ProgramType{ .compute = struct {
                    pub fn invoke() ComputeReturn {
                        return error.ProgramOops;
                    }
                }.invoke },
            };
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = Counter.Instance.init();

    const CallType = @TypeOf(Counter.proof.exampleHarness(i32, &runtime, &instance, handler{}, Body));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "ProgramOops"));
    try std.testing.expectError(error.ProgramOops, Counter.proof.exampleHarness(i32, &runtime, &instance, handler{}, Body));
}

test "generated family handle infers explicit program continuation errors" {
    const Picker = shift.effect.Define(.{
        .state_type = struct {},
        .ops = .{
            shift.effect.ops.Choice("pick", i32, i32),
        },
    });

    const handler = struct {
        pub fn pick(_: *@This(), payload: i32) shift.effect.choice.Decision(i32, i32) {
            return shift.effect.choice.Decision(i32, i32).resumeWith(payload);
        }

        pub fn afterPick(_: *@This(), answer: i32) i32 {
            return answer;
        }
    };

    const Body = struct {
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(Picker.Op(.pick).program(Cap, ctx, 41, struct {
            pub fn apply(_: i32) !i32 {
                return error.ContinueOops;
            }
        })) {
            return Picker.Op(.pick).program(Cap, ctx, 41, struct {
                pub fn apply(_: i32) !i32 {
                    return error.ContinueOops;
                }
            });
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = Picker.Instance.init();

    const CallType = @TypeOf(Picker.handle(i32, &runtime, &instance, handler{}, Body));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "ContinueOops"));
    try std.testing.expectError(error.ContinueOops, Picker.handle(i32, &runtime, &instance, handler{}, Body));
}

test "generated family proof helper infers explicit program continuation errors" {
    const Picker = shift.effect.Define(.{
        .state_type = struct {},
        .ops = .{
            shift.effect.ops.Choice("pick", i32, i32),
        },
    });

    const handler = struct {
        pub fn pick(_: *@This(), payload: i32) shift.effect.choice.Decision(i32, i32) {
            return shift.effect.choice.Decision(i32, i32).resumeWith(payload);
        }

        pub fn afterPick(_: *@This(), answer: i32) i32 {
            return answer;
        }
    };

    const Body = struct {
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(Picker.Op(.pick).program(Cap, ctx, 41, struct {
            pub fn apply(_: i32) !i32 {
                return error.ContinueOops;
            }
        })) {
            return Picker.Op(.pick).program(Cap, ctx, 41, struct {
                pub fn apply(_: i32) !i32 {
                    return error.ContinueOops;
                }
            });
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = Picker.Instance.init();

    const CallType = @TypeOf(Picker.proof.exampleHarness(i32, &runtime, &instance, handler{}, Body));
    const ErrorSet = @typeInfo(CallType).error_union.error_set;

    try std.testing.expect(hasErrorName(ErrorSet, "ContinueOops"));
    try std.testing.expectError(error.ContinueOops, Picker.proof.exampleHarness(i32, &runtime, &instance, handler{}, Body));
}
