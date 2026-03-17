const frontend = @import("frontend_support");
const lowered_machine = @import("lowered_machine");
const prompt_contract = @import("prompt_contract_support");
const std = @import("std");

const BuilderKind = enum {
    abort,
    choice,
    direct_transform,
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
        const mode = prompt_contract.PromptMode.resume_then_transform;
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
        const mode = prompt_contract.PromptMode.resume_or_return;
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
        const mode = prompt_contract.PromptMode.direct_return;
        const Payload = PayloadType;
        const Resume = noreturn;
    };
}

/// Build a transform handler specification for a declared transform op.
pub fn handleTransform(comptime Op: type, state: anytype, comptime Impl: type) TransformSpec(Op, @TypeOf(state), Impl) {
    comptime assertOpMode(Op, .resume_then_transform, "transform");
    return .{ .state = state };
}

/// Build a direct transform handler specification for a declared transform op.
pub fn handleDirectTransform(comptime Op: type, state: anytype, comptime Impl: type) DirectTransformSpec(Op, @TypeOf(state), Impl) {
    comptime assertOpMode(Op, .resume_then_transform, "direct transform");
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
        pub const Operation = Op;
        pub const builder_kind = BuilderKind.transform;
        pub const State = StateType;
        pub const ImplType = Impl;

        state: StateType,
    };
}

fn DirectTransformSpec(comptime Op: type, comptime StateType: type, comptime Impl: type) type {
    return struct {
        pub const Operation = Op;
        pub const builder_kind = BuilderKind.direct_transform;
        pub const State = StateType;
        pub const ImplType = Impl;

        state: StateType,
    };
}

fn ChoiceSpec(comptime Op: type, comptime StateType: type, comptime Impl: type) type {
    return struct {
        pub const Operation = Op;
        pub const builder_kind = BuilderKind.choice;
        pub const State = StateType;
        pub const ImplType = Impl;

        state: StateType,
    };
}

fn AbortSpec(comptime Op: type, comptime StateType: type, comptime Impl: type) type {
    return struct {
        pub const Operation = Op;
        pub const builder_kind = BuilderKind.abort;
        pub const State = StateType;
        pub const ImplType = Impl;

        state: StateType,
    };
}

fn assertOpMode(comptime Op: type, comptime expected: prompt_contract.PromptMode, comptime label: []const u8) void {
    if (!@hasDecl(Op, "mode")) @compileError("algebraic op is missing mode");
    if (!@hasDecl(Op, "Payload")) @compileError("algebraic op is missing Payload");
    if (!@hasDecl(Op, "Resume")) @compileError("algebraic op is missing Resume");
    if (Op.mode != expected) {
        @compileError("algebraic " ++ label ++ " handler requires matching op mode");
    }
}

fn assertBodyType(comptime Body: type, comptime ContextType: type, comptime ErrorSet: type, comptime Answer: type) void {
    _ = ContextType;
    _ = ErrorSet;
    _ = Answer;
    if (!@hasDecl(Body, "program") and !@hasDecl(Body, "body")) @compileError("algebraic body must declare program or body");
}

fn assertTransformImplType(comptime TransformContract: type) void {
    const StateType = TransformContract.state_type;
    const Op = TransformContract.op_type;
    const Impl = TransformContract.impl_type;
    const ContinueAnswer = TransformContract.continue_answer_type;
    const ErrorSet = TransformContract.error_set_type;
    const Answer = TransformContract.answer_type;
    if (!@hasDecl(Impl, "resumeValue")) @compileError("transform handler must declare resumeValue");
    if (!@hasDecl(Impl, "afterResume")) @compileError("transform handler must declare afterResume");

    const ResumeFn = @TypeOf(Impl.resumeValue);
    if (ResumeFn != fn (StateType, Op.Payload) Op.Resume and ResumeFn != fn (StateType, Op.Payload) lowered_machine.ResetError(ErrorSet)!Op.Resume) {
        @compileError("transform handler resumeValue must have type fn (State, Payload) Resume or fn (State, Payload) ResetError(ErrorSet)!Resume");
    }

    const AfterFn = @TypeOf(Impl.afterResume);
    if (AfterFn != fn (StateType, ContinueAnswer) Answer and AfterFn != fn (StateType, ContinueAnswer) lowered_machine.ResetError(ErrorSet)!Answer) {
        @compileError("transform handler afterResume must have type fn (State, ContinueAnswer) Answer or fn (State, ContinueAnswer) ResetError(ErrorSet)!Answer");
    }
}

fn assertChoiceImplType(comptime ChoiceContract: type) void {
    const StateType = ChoiceContract.state_type;
    const Op = ChoiceContract.op_type;
    const Impl = ChoiceContract.impl_type;
    const ContinueAnswer = ChoiceContract.continue_answer_type;
    const ErrorSet = ChoiceContract.error_set_type;
    const Answer = ChoiceContract.answer_type;
    if (!@hasDecl(Impl, "resumeOrReturn")) @compileError("choice handler must declare resumeOrReturn");
    if (!@hasDecl(Impl, "afterResume")) @compileError("choice handler must declare afterResume");

    const DecisionType = prompt_contract.ResumeOrReturn(Op.Resume, Answer);
    const DecideFn = @TypeOf(Impl.resumeOrReturn);
    if (DecideFn != fn (StateType, Op.Payload) DecisionType and DecideFn != fn (StateType, Op.Payload) lowered_machine.ResetError(ErrorSet)!DecisionType) {
        @compileError("choice handler resumeOrReturn must have type fn (State, Payload) ResumeOrReturn or fn (State, Payload) ResetError(ErrorSet)!ResumeOrReturn");
    }

    const AfterFn = @TypeOf(Impl.afterResume);
    if (AfterFn != fn (StateType, ContinueAnswer) Answer and AfterFn != fn (StateType, ContinueAnswer) lowered_machine.ResetError(ErrorSet)!Answer) {
        @compileError("choice handler afterResume must have type fn (State, ContinueAnswer) Answer or fn (State, ContinueAnswer) ResetError(ErrorSet)!Answer");
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
    if (DirectFn != fn (StateType, Op.Payload) Answer and DirectFn != fn (StateType, Op.Payload) lowered_machine.ResetError(ErrorSet)!Answer) {
        @compileError("abort handler directReturn must have type fn (State, Payload) Answer or fn (State, Payload) ResetError(ErrorSet)!Answer");
    }
}

fn assertSpecType(comptime SpecType: type, comptime Op: type, comptime ContinueAnswer: type, comptime ErrorSet: type, comptime Answer: type) void {
    if (!@hasDecl(SpecType, "Operation")) @compileError("algebraic handler spec missing Operation");
    if (!@hasDecl(SpecType, "builder_kind")) @compileError("algebraic handler spec missing builder_kind");
    if (!@hasDecl(SpecType, "State")) @compileError("algebraic handler spec missing State");
    if (!@hasDecl(SpecType, "ImplType")) @compileError("algebraic handler spec missing ImplType");
    if (SpecType.Operation != Op) @compileError("algebraic handler spec order must match Program op order");

    switch (SpecType.builder_kind) {
        .direct_transform => {
            if (Op.mode != .resume_then_transform) @compileError("direct transform builder used with non-transform op");
            assertTransformImplType(struct {
                const state_type = SpecType.State;
                const op_type = Op;
                const impl_type = SpecType.ImplType;
                const continue_answer_type = ContinueAnswer;
                const error_set_type = ErrorSet;
                const answer_type = Answer;
            });
        },
        .transform => {
            if (Op.mode != .resume_then_transform) @compileError("transform builder used with non-transform op");
            assertTransformImplType(struct {
                const state_type = SpecType.State;
                const op_type = Op;
                const impl_type = SpecType.ImplType;
                const continue_answer_type = ContinueAnswer;
                const error_set_type = ErrorSet;
                const answer_type = Answer;
            });
        },
        .choice => {
            if (Op.mode != .resume_or_return) @compileError("choice builder used with non-choice op");
            assertChoiceImplType(struct {
                const state_type = SpecType.State;
                const op_type = Op;
                const impl_type = SpecType.ImplType;
                const continue_answer_type = ContinueAnswer;
                const error_set_type = ErrorSet;
                const answer_type = Answer;
            });
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

fn PromptTypeForOp(comptime Op: type, comptime ContinueAnswer: type, comptime Answer: type, comptime ErrorSet: type) type {
    return prompt_contract.Prompt(Op.mode, ContinueAnswer, Answer, ErrorSet);
}

fn Binding(
    comptime SpecType: type,
    comptime ContinueAnswer: type,
    comptime Answer: type,
    comptime ErrorSet: type,
) type {
    const Op = SpecType.Operation;
    const StateType = SpecType.State;
    const Impl = SpecType.ImplType;
    const PromptType = PromptTypeForOp(Op, ContinueAnswer, Answer, ErrorSet);
    return struct {
        const Prompt = PromptType;
        threadlocal var active_binding: ?*@This() = null;
        threadlocal var active_payload: ?Op.Payload = null;
        threadlocal var direct_binding: ?*@This() = null;
        threadlocal var direct_payload: ?Op.Payload = null;
        threadlocal var pending_binding: ?*@This() = null;
        threadlocal var pending_payload: ?Op.Payload = null;
        threadlocal var previous_active_binding: ?*@This() = null;
        threadlocal var previous_active_payload: ?Op.Payload = null;

        spec: SpecType,
        prompt: PromptType,

        /// Build one binding with a fresh prompt token.
        pub fn init(spec: SpecType) @This() {
            return .{
                .spec = spec,
                .prompt = PromptType.init(),
            };
        }

        /// Build one binding that reuses an externally supplied prompt token.
        pub fn initWithToken(spec: SpecType, token: prompt_contract.PromptToken) @This() {
            return .{
                .spec = spec,
                .prompt = .{ .token = token },
            };
        }

        fn currentPayload() Op.Payload {
            if (comptime Op.Payload == void) return {};
            return active_payload.?;
        }

        fn activatePending() void {
            previous_active_binding = active_binding;
            previous_active_payload = active_payload;
            active_binding = pending_binding;
            active_payload = pending_payload;
        }

        fn deactivatePending() void {
            active_binding = previous_active_binding;
            active_payload = previous_active_payload;
            pending_binding = null;
            pending_payload = null;
        }

        fn callResumeValue(spec: SpecType, payload: Op.Payload) lowered_machine.ResetError(ErrorSet)!Op.Resume {
            const ResumeFn = @TypeOf(Impl.resumeValue);
            if (ResumeFn == fn (StateType, Op.Payload) Op.Resume) return Impl.resumeValue(spec.state, payload);
            return try Impl.resumeValue(spec.state, payload);
        }

        fn callAfterResume(spec: SpecType, answer: ContinueAnswer) lowered_machine.ResetError(ErrorSet)!Answer {
            const AfterFn = @TypeOf(Impl.afterResume);
            if (AfterFn == fn (StateType, ContinueAnswer) Answer) return Impl.afterResume(spec.state, answer);
            return try Impl.afterResume(spec.state, answer);
        }

        fn callResumeOrReturn(spec: SpecType, payload: Op.Payload) lowered_machine.ResetError(ErrorSet)!prompt_contract.ResumeOrReturn(Op.Resume, Answer) {
            const DecideFn = @TypeOf(Impl.resumeOrReturn);
            if (DecideFn == fn (StateType, Op.Payload) prompt_contract.ResumeOrReturn(Op.Resume, Answer)) return Impl.resumeOrReturn(spec.state, payload);
            return try Impl.resumeOrReturn(spec.state, payload);
        }

        fn callDirectReturn(spec: SpecType, payload: Op.Payload) lowered_machine.ResetError(ErrorSet)!Answer {
            const DirectFn = @TypeOf(Impl.directReturn);
            if (DirectFn == fn (StateType, Op.Payload) Answer) return Impl.directReturn(spec.state, payload);
            return try Impl.directReturn(spec.state, payload);
        }

        /// Perform one bound operation under the binding's prompt.
        pub fn perform(self: *@This(), payload: Op.Payload) lowered_machine.ResetError(ErrorSet)!Op.Resume {
            const BindingType = @This();
            return switch (SpecType.builder_kind) {
                .direct_transform => try BindingType.callResumeValue(self.spec, payload),
                .transform => blk: {
                    const handler = struct {
                        /// Supply the resumptive transform value from the active binding.
                        pub fn resumeValue() lowered_machine.ResetError(ErrorSet)!Op.Resume {
                            return try BindingType.callResumeValue(BindingType.active_binding.?.spec, BindingType.currentPayload());
                        }

                        /// Complete the enclosing answer after one transform resume.
                        pub fn afterResume(answer: ContinueAnswer) lowered_machine.ResetError(ErrorSet)!Answer {
                            return try BindingType.callAfterResume(BindingType.active_binding.?.spec, answer);
                        }
                    };

                    const previous_binding = BindingType.active_binding;
                    const previous_payload = BindingType.active_payload;
                    BindingType.active_binding = self;
                    BindingType.active_payload = payload;
                    defer {
                        BindingType.active_binding = previous_binding;
                        BindingType.active_payload = previous_payload;
                    }
                    break :blk try frontend.transform(Op.Resume, &self.prompt, handler);
                },
                .choice => blk: {
                    const handler = struct {
                        /// Choose the next action for the active choice binding.
                        pub fn resumeOrReturn() lowered_machine.ResetError(ErrorSet)!prompt_contract.ResumeOrReturn(Op.Resume, Answer) {
                            return try BindingType.callResumeOrReturn(BindingType.active_binding.?.spec, BindingType.currentPayload());
                        }

                        /// Complete the enclosing answer after one choice resume.
                        pub fn afterResume(answer: ContinueAnswer) lowered_machine.ResetError(ErrorSet)!Answer {
                            return try BindingType.callAfterResume(BindingType.active_binding.?.spec, answer);
                        }
                    };

                    const previous_binding = BindingType.active_binding;
                    const previous_payload = BindingType.active_payload;
                    BindingType.active_binding = self;
                    BindingType.active_payload = payload;
                    defer {
                        BindingType.active_binding = previous_binding;
                        BindingType.active_payload = previous_payload;
                    }
                    break :blk try frontend.choice(Op.Resume, &self.prompt, handler);
                },
                .abort => {
                    const handler = struct {
                        /// Convert the active abort payload into the enclosing answer.
                        pub fn directReturn() lowered_machine.ResetError(ErrorSet)!Answer {
                            return try BindingType.callDirectReturn(BindingType.active_binding.?.spec, BindingType.currentPayload());
                        }
                    };

                    const previous_binding = BindingType.active_binding;
                    const previous_payload = BindingType.active_payload;
                    BindingType.active_binding = self;
                    BindingType.active_payload = payload;
                    defer {
                        BindingType.active_binding = previous_binding;
                        BindingType.active_payload = previous_payload;
                    }
                    return try frontend.abort(&self.prompt, handler);
                },
            };
        }

        /// Build one explicit frontend program for the bound operation and continuation.
        pub fn program(self: *@This(), payload: Op.Payload, comptime Continuation: type) frontend.Program(PromptType) {
            const BindingType = @This();
            return switch (SpecType.builder_kind) {
                .direct_transform => @compileError("direct transform bindings do not support explicit program construction"),
                .transform => blk: {
                    const handler = struct {
                        /// Supply the resumptive value for one explicit transform op.
                        pub fn resumeValue() lowered_machine.ResetError(ErrorSet)!Op.Resume {
                            return try BindingType.callResumeValue(BindingType.active_binding.?.spec, BindingType.currentPayload());
                        }

                        /// Complete the enclosing answer after one explicit transform resume.
                        pub fn afterResume(answer: ContinueAnswer) lowered_machine.ResetError(ErrorSet)!Answer {
                            return try BindingType.callAfterResume(BindingType.active_binding.?.spec, answer);
                        }
                    };

                    BindingType.pending_binding = self;
                    BindingType.pending_payload = payload;
                    break :blk frontend.transformProgram(PromptType, Op.Resume, handler, Continuation);
                },
                .choice => blk: {
                    const handler = struct {
                        /// Decide whether one explicit choice op resumes or returns now.
                        pub fn resumeOrReturn() lowered_machine.ResetError(ErrorSet)!prompt_contract.ResumeOrReturn(Op.Resume, Answer) {
                            return try BindingType.callResumeOrReturn(BindingType.active_binding.?.spec, BindingType.currentPayload());
                        }

                        /// Complete the enclosing answer after one explicit choice resume.
                        pub fn afterResume(answer: ContinueAnswer) lowered_machine.ResetError(ErrorSet)!Answer {
                            return try BindingType.callAfterResume(BindingType.active_binding.?.spec, answer);
                        }
                    };

                    BindingType.pending_binding = self;
                    BindingType.pending_payload = payload;
                    break :blk frontend.choiceProgram(PromptType, Op.Resume, handler, Continuation);
                },
                .abort => blk: {
                    const handler = struct {
                        /// Convert one explicit abort payload into the enclosing answer.
                        pub fn directReturn() lowered_machine.ResetError(ErrorSet)!Answer {
                            return try BindingType.callDirectReturn(BindingType.active_binding.?.spec, BindingType.currentPayload());
                        }
                    };

                    BindingType.pending_binding = self;
                    BindingType.pending_payload = payload;
                    break :blk frontend.abortProgram(PromptType, handler);
                },
            };
        }

        /// Build one explicit frontend program that closes over this binding directly.
        pub fn directProgram(self: *@This(), payload: Op.Payload, comptime Continuation: type) frontend.Program(PromptType) {
            const BindingType = @This();
            BindingType.direct_binding = self;
            BindingType.direct_payload = payload;
            return switch (SpecType.builder_kind) {
                .direct_transform => @compileError("direct transform bindings do not support explicit program construction"),
                .transform => blk: {
                    const handler = struct {
                        /// Supply the resumptive value for one direct explicit transform op.
                        pub fn resumeValue() lowered_machine.ResetError(ErrorSet)!Op.Resume {
                            return try BindingType.callResumeValue(BindingType.direct_binding.?.spec, BindingType.direct_payload.?);
                        }

                        /// Complete the enclosing answer after one direct explicit transform resume.
                        pub fn afterResume(answer: ContinueAnswer) lowered_machine.ResetError(ErrorSet)!Answer {
                            return try BindingType.callAfterResume(BindingType.direct_binding.?.spec, answer);
                        }
                    };

                    break :blk frontend.transformProgram(PromptType, Op.Resume, handler, Continuation);
                },
                .choice => blk: {
                    const handler = struct {
                        /// Decide whether one direct explicit choice op resumes or returns now.
                        pub fn resumeOrReturn() lowered_machine.ResetError(ErrorSet)!prompt_contract.ResumeOrReturn(Op.Resume, Answer) {
                            return try BindingType.callResumeOrReturn(BindingType.direct_binding.?.spec, BindingType.direct_payload.?);
                        }

                        /// Complete the enclosing answer after one direct explicit choice resume.
                        pub fn afterResume(answer: ContinueAnswer) lowered_machine.ResetError(ErrorSet)!Answer {
                            return try BindingType.callAfterResume(BindingType.direct_binding.?.spec, answer);
                        }
                    };

                    break :blk frontend.choiceProgram(PromptType, Op.Resume, handler, Continuation);
                },
                .abort => blk: {
                    const handler = struct {
                        /// Convert one direct explicit abort payload into the enclosing answer.
                        pub fn directReturn() lowered_machine.ResetError(ErrorSet)!Answer {
                            return try BindingType.callDirectReturn(BindingType.direct_binding.?.spec, BindingType.direct_payload.?);
                        }
                    };

                    break :blk frontend.abortProgram(PromptType, handler);
                },
            };
        }
    };
}

fn BindingAtType(
    comptime SpecsTupleType: type,
    comptime ContinueAnswer: type,
    comptime Answer: type,
    comptime ErrorSet: type,
    comptime index: usize,
) type {
    return Binding(TupleFieldType(SpecsTupleType, index), ContinueAnswer, Answer, ErrorSet);
}

fn BindingChainType(
    comptime SpecsTupleType: type,
    comptime ContinueAnswer: type,
    comptime Answer: type,
    comptime ErrorSet: type,
    comptime index: usize,
) type {
    if (index == tupleLen(SpecsTupleType)) {
        return struct {
            /// Build an empty binding chain terminator.
            pub fn init(_: SpecsTupleType) @This() {
                return .{};
            }

            /// Build an empty binding chain terminator for a reused prompt token.
            pub fn initWithToken(_: SpecsTupleType, _: prompt_contract.PromptToken) @This() {
                return .{};
            }

            /// Resolve one binding pointer from the empty chain terminator.
            pub fn bindingPtr(_: *@This(), comptime target: usize) *BindingAtType(SpecsTupleType, ContinueAnswer, Answer, ErrorSet, target) {
                @compileError("invalid algebraic binding index");
            }
        };
    }

    const CurrentBinding = BindingAtType(SpecsTupleType, ContinueAnswer, Answer, ErrorSet, index);
    const NextChain = BindingChainType(SpecsTupleType, ContinueAnswer, Answer, ErrorSet, index + 1);
    return struct {
        current: CurrentBinding,
        next: NextChain,

        /// Build one binding chain with fresh prompt tokens.
        pub fn init(specs: SpecsTupleType) @This() {
            return .{
                .current = CurrentBinding.init(specs[index]),
                .next = NextChain.init(specs),
            };
        }

        /// Build one binding chain whose bindings all share the supplied prompt token.
        pub fn initWithToken(specs: SpecsTupleType, token: prompt_contract.PromptToken) @This() {
            return .{
                .current = CurrentBinding.initWithToken(specs[index], token),
                .next = NextChain.initWithToken(specs, token),
            };
        }

        /// Resolve one binding pointer from the chain by compile-time index.
        pub fn bindingPtr(self: *@This(), comptime target: usize) *BindingAtType(SpecsTupleType, ContinueAnswer, Answer, ErrorSet, target) {
            if (target == index) return &self.current;
            return self.next.bindingPtr(target);
        }
    };
}

/// Resolve the internal binding type for one handler spec and answer/error contract.
pub fn BindingFor(
    comptime SpecType: type,
    comptime ContinueAnswer: type,
    comptime Answer: type,
    comptime ErrorSet: type,
) type {
    return Binding(SpecType, ContinueAnswer, Answer, ErrorSet);
}

/// Resolve the internal binding-chain type for one spec tuple and answer/error contract.
pub fn BindingChainFor(
    comptime SpecsTupleType: type,
    comptime ContinueAnswer: type,
    comptime Answer: type,
    comptime ErrorSet: type,
) type {
    return BindingChainType(SpecsTupleType, ContinueAnswer, Answer, ErrorSet, 0);
}

/// Build a closed-world algebraic program over the existing one-shot prompt runtime.
pub fn Program(
    comptime ContinueAnswer: type,
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

        fn BodyPromptType() type {
            if (OpCount == 0) return prompt_contract.Prompt(.resume_then_transform, Answer, Answer, ErrorSet);
            const first_mode = program_ops[0].mode;
            inline for (program_ops, 0..) |Op, index| {
                if (index == 0) continue;
                if (Op.mode != first_mode) {
                    @compileError("algebraic body(...) support requires zero ops or all declared ops to share one prompt mode");
                }
            }
            return prompt_contract.Prompt(first_mode, Answer, Answer, ErrorSet);
        }

        fn Configured(comptime SpecsTupleType: type) type {
            comptime {
                if (tupleLen(SpecsTupleType) != OpCount) {
                    @compileError("algebraic Program.handlers expects one spec per op in declaration order");
                }
                for (program_ops, 0..) |Op, index| {
                    assertSpecType(TupleFieldType(SpecsTupleType, index), Op, ContinueAnswer, ErrorSet, Answer);
                }
            }
            const BindingsType = BindingChainType(SpecsTupleType, ContinueAnswer, Answer, ErrorSet, 0);
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
                    ) lowered_machine.ResetError(ErrorSet)!Op.Resume {
                        const index = comptime findOpIndex(Op);
                        return try self.bindings.bindingPtr(index).perform(payload);
                    }

                    /// Build one explicit program for a declared operation and continuation.
                    pub fn performProgram(
                        self: *Context,
                        comptime Op: type,
                        payload: Op.Payload,
                        comptime Continuation: type,
                    ) frontend.BoundProgram(BindingAtType(SpecsTupleType, ContinueAnswer, Answer, ErrorSet, findOpIndex(Op)).Prompt) {
                        const index = comptime findOpIndex(Op);
                        const binding = self.bindings.bindingPtr(index);
                        return .{
                            .prompt = &binding.prompt,
                            .program = binding.program(payload, Continuation),
                            .activateFn = BindingAtType(SpecsTupleType, ContinueAnswer, Answer, ErrorSet, index).activatePending,
                            .deactivateFn = BindingAtType(SpecsTupleType, ContinueAnswer, Answer, ErrorSet, index).deactivatePending,
                        };
                    }
                };

                /// Run the configured program under the supplied runtime.
                pub fn run(
                    self: @This(),
                    runtime: anytype,
                    comptime Body: type,
                ) lowered_machine.ResetError(ErrorSet)!Answer {
                    comptime assertBodyType(Body, Context, ErrorSet, Answer);
                    var bindings = BindingsType.init(self.specs);
                    var ctx = Context{ .bindings = &bindings };
                    if (comptime @hasDecl(Body, "program")) {
                        const authored = Body.program(&ctx);
                        authored.activate();
                        defer authored.deactivate();
                        return try frontend.run(runtime, authored.prompt, authored.program);
                    }

                    const PromptType = BodyPromptType();
                    var prompt = PromptType.init();
                    if (OpCount != 0) {
                        bindings = BindingsType.initWithToken(self.specs, prompt.token);
                        ctx = .{ .bindings = &bindings };
                    }
                    const body_ctx_shim = struct {
                        threadlocal var active_ctx: ?*Context = null;
                    };
                    const previous_ctx = body_ctx_shim.active_ctx;
                    body_ctx_shim.active_ctx = &ctx;
                    defer body_ctx_shim.active_ctx = previous_ctx;
                    return try frontend.run(runtime, &prompt, frontend.computeProgram(PromptType, struct {
                        fn invoke() lowered_machine.ResetError(ErrorSet)!Answer {
                            const BodyFn = @TypeOf(Body.body);
                            const ReturnType = @typeInfo(BodyFn).@"fn".return_type.?;
                            if (@typeInfo(ReturnType) != .error_union) return Body.body(body_ctx_shim.active_ctx.?);
                            return try Body.body(body_ctx_shim.active_ctx.?);
                        }
                    }.invoke));
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
    const program = Program(i32, i32, error{}, .{ping});
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

test "configured binding chain stores direct bindings" {
    const ping = TransformOp("ping", void, i32);
    const no_state = struct {};
    const program = Program(i32, i32, error{}, .{ping});
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
    const context_info = @typeInfo(Configured.Context).@"struct";
    const BindingsPtrType = context_info.fields[0].type;
    const BindingsType = @typeInfo(BindingsPtrType).pointer.child;
    const FirstFieldType = @typeInfo(BindingsType).@"struct".fields[0].type;

    try std.testing.expect(@typeInfo(FirstFieldType) != .optional);
}

test "binding payload storage stays pointer-based" {
    const ping = TransformOp("ping", usize, usize);
    const no_state = struct {};
    const spec = handleTransform(ping, no_state{}, struct {
        /// Supply the transform witness value.
        pub fn resumeValue(_: no_state, payload: usize) usize {
            return payload;
        }

        /// Preserve the resumed answer unchanged.
        pub fn afterResume(_: no_state, answer: usize) usize {
            return answer;
        }
    });
    const BindingType = Binding(@TypeOf(spec), usize, usize, error{});

    try std.testing.expectEqual(?ping.Payload, @TypeOf(BindingType.active_payload));
}

test "transform program resumes and observes final answer" {
    const NoError = error{};
    const add = TransformOp("add", i32, i32);
    const demo = Program(i32, i32, NoError, .{add});
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
        /// Run the transform witness body through the explicit program path.
        pub fn program(ctx: *@TypeOf(configured).Context) @TypeOf(ctx.performProgram(add, 1, struct {
            /// Increment the transform resume value.
            pub fn apply(value: i32) i32 {
                return value + 1;
            }
        })) {
            return ctx.performProgram(add, 1, struct {
                /// Increment the transform resume value.
                pub fn apply(value: i32) i32 {
                    return value + 1;
                }
            });
        }
    };

    var runtime = @import("../root.zig").Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    const result = try configured.run(&runtime, body);
    try std.testing.expectEqual(@as(i32, 42), result);
}

test "choice program may return now" {
    const NoError = error{};
    const pick = ChoiceOp("pick", i32, i32);
    const demo = Program([]const u8, []const u8, NoError, .{pick});
    const no_state = struct {};
    const choice_handler = struct {
        /// Return immediately from the choice witness.
        pub fn resumeOrReturn(_: no_state, _: i32) prompt_contract.ResumeOrReturn(i32, []const u8) {
            return prompt_contract.ResumeOrReturn(i32, []const u8).returnNow("early");
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
        /// Run the choice witness body through the explicit program path.
        pub fn program(ctx: *@TypeOf(configured).Context) @TypeOf(ctx.performProgram(pick, 0, struct {
            /// Produce the late answer if the choice resumes.
            pub fn apply(_: i32) []const u8 {
                return "late";
            }
        })) {
            return ctx.performProgram(pick, 0, struct {
                /// Produce the late answer if the choice resumes.
                pub fn apply(_: i32) []const u8 {
                    return "late";
                }
            });
        }
    };

    var runtime = @import("../root.zig").Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    const result = try configured.run(&runtime, body);
    try std.testing.expectEqualStrings("early", result);
}

test "abort program never resumes body tail" {
    const NoError = error{};
    const fail = AbortOp("fail", []const u8);
    const demo = Program([]const u8, []const u8, NoError, .{fail});
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

        /// Run the abort witness body through the explicit program path.
        pub fn program(ctx: *@TypeOf(configured).Context) @TypeOf(ctx.performProgram(fail, "abort", struct {
            /// Mark that the abort continuation resumed unexpectedly.
            pub fn apply(_: noreturn) []const u8 {
                after_abort = true;
                return "late";
            }
        })) {
            return ctx.performProgram(fail, "abort", struct {
                /// Mark that the abort continuation resumed unexpectedly.
                pub fn apply(_: noreturn) []const u8 {
                    after_abort = true;
                    return "late";
                }
            });
        }
    };

    var runtime = @import("../root.zig").Runtime.init(std.testing.allocator);
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
    const demo = Program(i32, i32, NoError, .{add});
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
        /// Run the warmed no-allocation witness body through the explicit program path.
        pub fn program(ctx: *@TypeOf(configured).Context) @TypeOf(ctx.performProgram(add, 41, struct {
            /// Preserve the warmed transform answer unchanged.
            pub fn apply(value: i32) i32 {
                return value;
            }
        })) {
            return ctx.performProgram(add, 41, struct {
                /// Preserve the warmed transform answer unchanged.
                pub fn apply(value: i32) i32 {
                    return value;
                }
            });
        }
    };

    var counting = CountingAllocator.init(std.testing.allocator);
    var runtime = @import("../root.zig").Runtime.init(counting.allocator());
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
