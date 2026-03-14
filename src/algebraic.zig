const raw = @import("raw.zig");
const std = @import("std");

const BuilderKind = enum {
    abort,
    choice,
    transform,
};

/// Define one closed-world resumptive transform operation.
pub fn TransformOp(
    comptime name: []const u8,
    comptime PayloadType: type,
    comptime ResumeType: type,
) type {
    return struct {
        const op_name = name;
        const mode = raw.PromptMode.resume_then_transform;
        const Payload = PayloadType;
        const Resume = ResumeType;
    };
}

/// Define one closed-world zero-or-one-resume choice operation.
pub fn ChoiceOp(
    comptime name: []const u8,
    comptime PayloadType: type,
    comptime ResumeType: type,
) type {
    return struct {
        const op_name = name;
        const mode = raw.PromptMode.resume_or_return;
        const Payload = PayloadType;
        const Resume = ResumeType;
    };
}

/// Define one closed-world abortive operation.
pub fn AbortOp(
    comptime name: []const u8,
    comptime PayloadType: type,
) type {
    return struct {
        const op_name = name;
        const mode = raw.PromptMode.direct_return;
        const Payload = PayloadType;
        const Resume = noreturn;
    };
}

/// Build a transform handler specification for a declared transform op.
pub fn handleTransform(comptime Op: type, state: anytype, comptime Impl: type) TransformSpec(Op, @TypeOf(state), Impl) {
    comptime assertOpMode(Op, .resume_then_transform, "transform");
    return .{ .state = state };
}

/// Build a choice handler specification for a declared choice op.
pub fn handleChoice(comptime Op: type, state: anytype, comptime Impl: type) ChoiceSpec(Op, @TypeOf(state), Impl) {
    comptime assertOpMode(Op, .resume_or_return, "choice");
    return .{ .state = state };
}

/// Build an abort handler specification for a declared abort op.
pub fn handleAbort(comptime Op: type, state: anytype, comptime Impl: type) AbortSpec(Op, @TypeOf(state), Impl) {
    comptime assertOpMode(Op, .direct_return, "abort");
    return .{ .state = state };
}

fn TransformSpec(comptime Op: type, comptime StateType: type, comptime Impl: type) type {
    return struct {
        const Operation = Op;
        const builder_kind = BuilderKind.transform;
        const State = StateType;
        const ImplType = Impl;

        state: StateType,
    };
}

fn ChoiceSpec(comptime Op: type, comptime StateType: type, comptime Impl: type) type {
    return struct {
        const Operation = Op;
        const builder_kind = BuilderKind.choice;
        const State = StateType;
        const ImplType = Impl;

        state: StateType,
    };
}

fn AbortSpec(comptime Op: type, comptime StateType: type, comptime Impl: type) type {
    return struct {
        const Operation = Op;
        const builder_kind = BuilderKind.abort;
        const State = StateType;
        const ImplType = Impl;

        state: StateType,
    };
}

fn assertOpMode(comptime Op: type, comptime expected: raw.PromptMode, comptime label: []const u8) void {
    if (!@hasDecl(Op, "mode")) @compileError("algebraic op is missing mode");
    if (!@hasDecl(Op, "Payload")) @compileError("algebraic op is missing Payload");
    if (!@hasDecl(Op, "Resume")) @compileError("algebraic op is missing Resume");
    if (Op.mode != expected) {
        @compileError("algebraic " ++ label ++ " handler requires matching op mode");
    }
}

fn assertBodyType(comptime Body: type, comptime ContextType: type, comptime ErrorSet: type, comptime Answer: type) void {
    if (!@hasDecl(Body, "body")) @compileError("algebraic body must declare body");
    const BodyFn = @TypeOf(Body.body);
    if (BodyFn != fn (*ContextType) raw.ResetError(ErrorSet)!Answer) {
        @compileError("algebraic body must have type fn (*Context) ResetError(ErrorSet)!Answer");
    }
}

fn assertTransformImplType(
    comptime StateType: type,
    comptime Op: type,
    comptime Impl: type,
    comptime ErrorSet: type,
    comptime Answer: type,
) void {
    if (!@hasDecl(Impl, "resumeValue")) @compileError("transform handler must declare resumeValue");
    if (!@hasDecl(Impl, "afterResume")) @compileError("transform handler must declare afterResume");

    const ResumeFn = @TypeOf(Impl.resumeValue);
    if (ResumeFn != fn (StateType, Op.Payload) Op.Resume and ResumeFn != fn (StateType, Op.Payload) raw.ResetError(ErrorSet)!Op.Resume) {
        @compileError("transform handler resumeValue must have type fn (State, Payload) Resume or fn (State, Payload) ResetError(ErrorSet)!Resume");
    }

    const AfterFn = @TypeOf(Impl.afterResume);
    if (AfterFn != fn (StateType, Answer) Answer and AfterFn != fn (StateType, Answer) raw.ResetError(ErrorSet)!Answer) {
        @compileError("transform handler afterResume must have type fn (State, Answer) Answer or fn (State, Answer) ResetError(ErrorSet)!Answer");
    }
}

fn assertChoiceImplType(
    comptime StateType: type,
    comptime Op: type,
    comptime Impl: type,
    comptime ErrorSet: type,
    comptime Answer: type,
) void {
    if (!@hasDecl(Impl, "resumeOrReturn")) @compileError("choice handler must declare resumeOrReturn");
    if (!@hasDecl(Impl, "afterResume")) @compileError("choice handler must declare afterResume");

    const DecisionType = raw.ResumeOrReturn(Op.Resume, Answer);
    const DecideFn = @TypeOf(Impl.resumeOrReturn);
    if (DecideFn != fn (StateType, Op.Payload) DecisionType and DecideFn != fn (StateType, Op.Payload) raw.ResetError(ErrorSet)!DecisionType) {
        @compileError("choice handler resumeOrReturn must have type fn (State, Payload) ResumeOrReturn or fn (State, Payload) ResetError(ErrorSet)!ResumeOrReturn");
    }

    const AfterFn = @TypeOf(Impl.afterResume);
    if (AfterFn != fn (StateType, Answer) Answer and AfterFn != fn (StateType, Answer) raw.ResetError(ErrorSet)!Answer) {
        @compileError("choice handler afterResume must have type fn (State, Answer) Answer or fn (State, Answer) ResetError(ErrorSet)!Answer");
    }
}

fn assertAbortImplType(
    comptime StateType: type,
    comptime Op: type,
    comptime Impl: type,
    comptime ErrorSet: type,
    comptime Answer: type,
) void {
    if (!@hasDecl(Impl, "directReturn")) @compileError("abort handler must declare directReturn");
    const DirectFn = @TypeOf(Impl.directReturn);
    if (DirectFn != fn (StateType, Op.Payload) Answer and DirectFn != fn (StateType, Op.Payload) raw.ResetError(ErrorSet)!Answer) {
        @compileError("abort handler directReturn must have type fn (State, Payload) Answer or fn (State, Payload) ResetError(ErrorSet)!Answer");
    }
}

fn assertSpecType(comptime SpecType: type, comptime Op: type, comptime ErrorSet: type, comptime Answer: type) void {
    if (!@hasDecl(SpecType, "Operation")) @compileError("algebraic handler spec missing Operation");
    if (!@hasDecl(SpecType, "builder_kind")) @compileError("algebraic handler spec missing builder_kind");
    if (!@hasDecl(SpecType, "State")) @compileError("algebraic handler spec missing State");
    if (!@hasDecl(SpecType, "ImplType")) @compileError("algebraic handler spec missing ImplType");
    if (SpecType.Operation != Op) @compileError("algebraic handler spec order must match Program op order");

    switch (SpecType.builder_kind) {
        .transform => {
            if (Op.mode != .resume_then_transform) @compileError("transform builder used with non-transform op");
            assertTransformImplType(SpecType.State, Op, SpecType.ImplType, ErrorSet, Answer);
        },
        .choice => {
            if (Op.mode != .resume_or_return) @compileError("choice builder used with non-choice op");
            assertChoiceImplType(SpecType.State, Op, SpecType.ImplType, ErrorSet, Answer);
        },
        .abort => {
            if (Op.mode != .direct_return) @compileError("abort builder used with non-abort op");
            assertAbortImplType(SpecType.State, Op, SpecType.ImplType, ErrorSet, Answer);
        },
    }
}

fn TupleFieldType(comptime TupleType: type, comptime index: usize) type {
    return @typeInfo(TupleType).@"struct".fields[index].type;
}

fn tupleLen(comptime TupleType: type) usize {
    return @typeInfo(TupleType).@"struct".fields.len;
}

fn PromptTypeForOp(comptime Op: type, comptime Answer: type, comptime ErrorSet: type) type {
    return raw.Prompt(Op.mode, Answer, Answer, ErrorSet);
}

fn Binding(
    comptime SpecType: type,
    comptime Answer: type,
    comptime ErrorSet: type,
) type {
    const Op = SpecType.Operation;
    const StateType = SpecType.State;
    const Impl = SpecType.ImplType;
    const PromptType = PromptTypeForOp(Op, Answer, ErrorSet);
    return struct {
        const Prompt = PromptType;
        threadlocal var active_binding: ?*@This() = null;
        threadlocal var active_payload: ?Op.Payload = null;

        spec: SpecType,
        prompt: PromptType,

        fn init(spec: SpecType) @This() {
            return .{
                .spec = spec,
                .prompt = PromptType.init(),
            };
        }

        fn callResumeValue(spec: SpecType, payload: Op.Payload) raw.ResetError(ErrorSet)!Op.Resume {
            const ResumeFn = @TypeOf(Impl.resumeValue);
            if (ResumeFn == fn (StateType, Op.Payload) Op.Resume) return Impl.resumeValue(spec.state, payload);
            return try Impl.resumeValue(spec.state, payload);
        }

        fn callAfterResume(spec: SpecType, answer: Answer) raw.ResetError(ErrorSet)!Answer {
            const AfterFn = @TypeOf(Impl.afterResume);
            if (AfterFn == fn (StateType, Answer) Answer) return Impl.afterResume(spec.state, answer);
            return try Impl.afterResume(spec.state, answer);
        }

        fn callResumeOrReturn(spec: SpecType, payload: Op.Payload) raw.ResetError(ErrorSet)!raw.ResumeOrReturn(Op.Resume, Answer) {
            const DecideFn = @TypeOf(Impl.resumeOrReturn);
            if (DecideFn == fn (StateType, Op.Payload) raw.ResumeOrReturn(Op.Resume, Answer)) return Impl.resumeOrReturn(spec.state, payload);
            return try Impl.resumeOrReturn(spec.state, payload);
        }

        fn callDirectReturn(spec: SpecType, payload: Op.Payload) raw.ResetError(ErrorSet)!Answer {
            const DirectFn = @TypeOf(Impl.directReturn);
            if (DirectFn == fn (StateType, Op.Payload) Answer) return Impl.directReturn(spec.state, payload);
            return try Impl.directReturn(spec.state, payload);
        }

        fn perform(self: *@This(), payload: Op.Payload) raw.ResetError(ErrorSet)!Op.Resume {
            const BindingType = @This();
            return switch (SpecType.builder_kind) {
                .transform => blk: {
                    const handler = struct {
                        /// Supply the resumptive transform value from the active binding.
                        pub fn resumeValue() raw.ResetError(ErrorSet)!Op.Resume {
                            return try BindingType.callResumeValue(BindingType.active_binding.?.spec, BindingType.active_payload.?);
                        }

                        /// Complete the enclosing answer after one transform resume.
                        pub fn afterResume(answer: Answer) raw.ResetError(ErrorSet)!Answer {
                            return try BindingType.callAfterResume(BindingType.active_binding.?.spec, answer);
                        }
                    };

                    const previous_payload = BindingType.active_payload;
                    BindingType.active_payload = payload;
                    defer {
                        BindingType.active_payload = previous_payload;
                    }
                    break :blk try raw.shift(Op.Resume, PromptType, &self.prompt, handler);
                },
                .choice => blk: {
                    const handler = struct {
                        /// Choose the next action for the active choice binding.
                        pub fn resumeOrReturn() raw.ResetError(ErrorSet)!raw.ResumeOrReturn(Op.Resume, Answer) {
                            return try BindingType.callResumeOrReturn(BindingType.active_binding.?.spec, BindingType.active_payload.?);
                        }

                        /// Complete the enclosing answer after one choice resume.
                        pub fn afterResume(answer: Answer) raw.ResetError(ErrorSet)!Answer {
                            return try BindingType.callAfterResume(BindingType.active_binding.?.spec, answer);
                        }
                    };

                    const previous_payload = BindingType.active_payload;
                    BindingType.active_payload = payload;
                    defer {
                        BindingType.active_payload = previous_payload;
                    }
                    break :blk try raw.shift(Op.Resume, PromptType, &self.prompt, handler);
                },
                .abort => {
                    const handler = struct {
                        /// Convert the active abort payload into the enclosing answer.
                        pub fn directReturn() raw.ResetError(ErrorSet)!Answer {
                            return try BindingType.callDirectReturn(BindingType.active_binding.?.spec, BindingType.active_payload.?);
                        }
                    };

                    const previous_payload = BindingType.active_payload;
                    BindingType.active_payload = payload;
                    defer {
                        BindingType.active_payload = previous_payload;
                    }
                    _ = try raw.shift(void, PromptType, &self.prompt, handler);
                    unreachable;
                },
            };
        }
    };
}

fn BindingTupleType(
    comptime SpecsTupleType: type,
    comptime ops: anytype,
    comptime Answer: type,
    comptime ErrorSet: type,
) type {
    const len = tupleLen(SpecsTupleType);
    var binding_types: [len]type = [_]type{void} ** len;
    inline for (ops, 0..) |_, index| {
        binding_types[index] = ?Binding(TupleFieldType(SpecsTupleType, index), Answer, ErrorSet);
    }
    return std.meta.Tuple(&binding_types);
}

/// Build a closed-world algebraic program over the existing one-shot prompt runtime.
pub fn Program(
    comptime Answer: type,
    comptime ErrorSet: type,
    comptime ops: anytype,
) type {
    return struct {
        const program_ops = ops;
        const OpCount = ops.len;

        fn findOpIndex(comptime Op: type) usize {
            inline for (program_ops, 0..) |candidate, index| {
                if (candidate == Op) return index;
            }
            @compileError("algebraic Program does not include the requested op");
        }

        fn Configured(comptime SpecsTupleType: type) type {
            comptime {
                if (tupleLen(SpecsTupleType) != OpCount) {
                    @compileError("algebraic Program.handlers expects one spec per op in declaration order");
                }
                for (program_ops, 0..) |Op, index| {
                    assertSpecType(TupleFieldType(SpecsTupleType, index), Op, ErrorSet, Answer);
                }
            }
            const BindingsType = BindingTupleType(SpecsTupleType, program_ops, Answer, ErrorSet);
            return struct {
                specs: SpecsTupleType,

                /// Pointer-sized execution context for one configured program instance.
                pub const Context = struct {
                    bindings: *BindingsType,

                    /// Perform one declared operation with its payload.
                    pub fn perform(
                        self: *Context,
                        comptime Op: type,
                        payload: Op.Payload,
                    ) raw.ResetError(ErrorSet)!Op.Resume {
                        const index = comptime findOpIndex(Op);
                        return try self.bindings[index].?.perform(payload);
                    }
                };

                /// Run the configured program under the supplied runtime.
                pub fn run(
                    self: @This(),
                    runtime: *raw.Runtime,
                    comptime Body: type,
                ) raw.ResetError(ErrorSet)!Answer {
                    comptime assertBodyType(Body, Context, ErrorSet, Answer);

                    var bindings: BindingsType = std.mem.zeroes(BindingsType);
                    inline for (program_ops, 0..) |_, index| {
                        const BindingType = @typeInfo(@TypeOf(bindings[index])).optional.child;
                        bindings[index] = BindingType.init(self.specs[index]);
                    }

                    var ctx = Context{ .bindings = &bindings };

                    const runner = struct {
                        threadlocal var active_bindings: ?*BindingsType = null;
                        threadlocal var active_ctx: ?*Context = null;
                        threadlocal var active_runtime: ?*raw.Runtime = null;

                        fn runLayer(comptime index: usize) raw.ResetError(ErrorSet)!Answer {
                            if (index == OpCount) {
                                return try Body.body(active_ctx.?);
                            }

                            const binding = &active_bindings.?[index].?;
                            const BindingType = @TypeOf(binding.*);
                            const runner = @This();
                            const next_index = index + 1;
                            const body_invoker = struct {
                                fn invoke() raw.ResetError(ErrorSet)!Answer {
                                    return try runner.runLayer(next_index);
                                }
                            };

                            const previous_binding = BindingType.active_binding;
                            BindingType.active_binding = binding;
                            defer BindingType.active_binding = previous_binding;
                            return try raw.reset(@TypeOf(binding.prompt), active_runtime.?, &binding.prompt, body_invoker.invoke);
                        }
                    };

                    const previous_bindings = runner.active_bindings;
                    const previous_ctx = runner.active_ctx;
                    const previous_runtime = runner.active_runtime;
                    runner.active_bindings = &bindings;
                    runner.active_ctx = &ctx;
                    runner.active_runtime = runtime;
                    defer {
                        runner.active_bindings = previous_bindings;
                        runner.active_ctx = previous_ctx;
                        runner.active_runtime = previous_runtime;
                    }

                    return try runner.runLayer(0);
                }
            };
        }

        /// Bind one handler specification per declared operation in declaration order.
        pub fn handlers(specs: anytype) Configured(@TypeOf(specs)) {
            return .{ .specs = specs };
        }
    };
}

test "descriptor shells stay zero-sized" {
    const transform_op = TransformOp("transform", i32, i32);
    const choice_op = ChoiceOp("choice", i32, i32);
    const abort_op = AbortOp("abort", []const u8);
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(transform_op));
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(choice_op));
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(abort_op));
}

test "stateless handler spec stays zero-sized" {
    const ping = TransformOp("ping", void, i32);
    const no_state = struct {};
    const spec = handleTransform(ping, no_state{}, struct {
        /// Supply the transform witness value.
        pub fn resumeValue(_: no_state, _: void) i32 {
            return 41;
        }

        /// Preserve the resumed answer unchanged.
        pub fn afterResume(_: no_state, answer: i32) i32 {
            return answer;
        }
    });
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(@TypeOf(spec)));
}

test "generated context stays pointer-sized" {
    const ping = TransformOp("ping", void, i32);
    const program = Program(i32, error{}, .{ping});
    const no_state = struct {};
    const Configured = @TypeOf(program.handlers(.{
        handleTransform(ping, no_state{}, struct {
            /// Supply the transform witness value.
            pub fn resumeValue(_: no_state, _: void) i32 {
                return 0;
            }

            /// Preserve the resumed answer unchanged.
            pub fn afterResume(_: no_state, answer: i32) i32 {
                return answer;
            }
        }),
    }));
    try std.testing.expectEqual(@sizeOf(usize), @sizeOf(Configured.Context));
}

test "transform program resumes and observes final answer" {
    const NoError = error{};
    const add = TransformOp("add", i32, i32);
    const demo = Program(i32, NoError, .{add});
    const no_state = struct {};
    const transform_handler = struct {
        /// Supply the resumptive transform value.
        pub fn resumeValue(_: no_state, payload: i32) i32 {
            return payload + 40;
        }

        /// Preserve the resumed answer unchanged.
        pub fn afterResume(_: no_state, answer: i32) i32 {
            return answer;
        }
    };
    const configured = demo.handlers(.{
        handleTransform(add, no_state{}, transform_handler),
    });

    const body = struct {
        /// Run the transform witness body.
        pub fn body(ctx: *@TypeOf(configured).Context) raw.ResetError(NoError)!i32 {
            const value = try ctx.perform(add, 1);
            return value + 1;
        }
    };

    var runtime = raw.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    const result = try configured.run(&runtime, body);
    try std.testing.expectEqual(@as(i32, 42), result);
}

test "choice program may return now" {
    const NoError = error{};
    const pick = ChoiceOp("pick", i32, i32);
    const demo = Program([]const u8, NoError, .{pick});
    const no_state = struct {};
    const choice_handler = struct {
        /// Return immediately from the choice witness.
        pub fn resumeOrReturn(_: no_state, _: i32) raw.ResumeOrReturn(i32, []const u8) {
            return raw.ResumeOrReturn(i32, []const u8).returnNow("early");
        }

        /// Preserve the resumed answer unchanged.
        pub fn afterResume(_: no_state, answer: []const u8) []const u8 {
            return answer;
        }
    };
    const configured = demo.handlers(.{
        handleChoice(pick, no_state{}, choice_handler),
    });

    const body = struct {
        /// Run the choice witness body.
        pub fn body(ctx: *@TypeOf(configured).Context) raw.ResetError(NoError)![]const u8 {
            _ = try ctx.perform(pick, 0);
            return "late";
        }
    };

    var runtime = raw.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    const result = try configured.run(&runtime, body);
    try std.testing.expectEqualStrings("early", result);
}

test "abort program never resumes body tail" {
    const NoError = error{};
    const fail = AbortOp("fail", []const u8);
    const demo = Program([]const u8, NoError, .{fail});
    const no_state = struct {};
    const abort_handler = struct {
        /// Return the abort payload unchanged.
        pub fn directReturn(_: no_state, payload: []const u8) []const u8 {
            return payload;
        }
    };
    const configured = demo.handlers(.{
        handleAbort(fail, no_state{}, abort_handler),
    });

    const body = struct {
        var after_abort = false;

        /// Run the abort witness body.
        pub fn body(ctx: *@TypeOf(configured).Context) raw.ResetError(NoError)![]const u8 {
            try ctx.perform(fail, "abort");
            after_abort = true;
            return "late";
        }
    };

    var runtime = raw.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    body.after_abort = false;
    const result = try configured.run(&runtime, body);
    try std.testing.expectEqualStrings("abort", result);
    try std.testing.expect(!body.after_abort);
}

test "warmed algebraic perform path adds no allocator traffic" {
    const CountingAllocator = struct {
        child: std.mem.Allocator,
        alloc_calls: usize = 0,
        resize_calls: usize = 0,
        remap_calls: usize = 0,
        free_calls: usize = 0,

        fn init(child: std.mem.Allocator) @This() {
            return .{ .child = child };
        }

        fn allocator(self: *@This()) std.mem.Allocator {
            return .{
                .ptr = self,
                .vtable = &.{
                    .alloc = alloc,
                    .resize = resize,
                    .remap = remap,
                    .free = free,
                },
            };
        }

        fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.alloc_calls += 1;
            return self.child.rawAlloc(len, alignment, ret_addr);
        }

        fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.resize_calls += 1;
            return self.child.rawResize(memory, alignment, new_len, ret_addr);
        }

        fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.remap_calls += 1;
            return self.child.rawRemap(memory, alignment, new_len, ret_addr);
        }

        fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.free_calls += 1;
            self.child.rawFree(memory, alignment, ret_addr);
        }
    };

    const NoError = error{};
    const add = TransformOp("warm_add", i32, i32);
    const demo = Program(i32, NoError, .{add});
    const no_state = struct {};
    const add_handler = struct {
        /// Supply the warmed transform value.
        pub fn resumeValue(_: no_state, payload: i32) i32 {
            return payload + 1;
        }

        /// Preserve the resumed answer unchanged.
        pub fn afterResume(_: no_state, answer: i32) i32 {
            return answer;
        }
    };
    const configured = demo.handlers(.{
        handleTransform(add, no_state{}, add_handler),
    });

    const body = struct {
        /// Run the warmed no-allocation witness body.
        pub fn body(ctx: *@TypeOf(configured).Context) raw.ResetError(NoError)!i32 {
            const value = try ctx.perform(add, 41);
            return value;
        }
    };

    var counting = CountingAllocator.init(std.testing.allocator);
    var runtime = raw.Runtime.init(counting.allocator(), .{});
    defer runtime.deinit();

    const warm = try configured.run(&runtime, body);
    try std.testing.expectEqual(@as(i32, 42), warm);

    const alloc_calls = counting.alloc_calls;
    const resize_calls = counting.resize_calls;
    const remap_calls = counting.remap_calls;
    const free_calls = counting.free_calls;

    const second = try configured.run(&runtime, body);
    try std.testing.expectEqual(@as(i32, 42), second);
    try std.testing.expectEqual(alloc_calls, counting.alloc_calls);
    try std.testing.expectEqual(resize_calls, counting.resize_calls);
    try std.testing.expectEqual(remap_calls, counting.remap_calls);
    try std.testing.expectEqual(free_calls, counting.free_calls);
}
