const family = @import("effect/family.zig");
const frontend = @import("frontend_support");
const lowered_machine = @import("lowered_machine");
const prompt_contract = @import("prompt_contract_support");
const std = @import("std");

/// One descriptor result: final descriptor output plus body answer.
pub fn DescriptorResult(comptime Output: type, comptime Answer: type) type {
    return struct {
        output: Output,
        value: Answer,
    };
}

/// Output bundle that mirrors only the non-void lexical handler outputs.
pub fn OutputBundleType(comptime HandlersType: type) type {
    comptime assertHandlerBundleShape(HandlersType);
    const handler_fields = @typeInfo(HandlersType).@"struct".fields;
    var fields = [_]std.builtin.Type.StructField{.{
        .name = "",
        .type = void,
        .default_value_ptr = null,
        .is_comptime = false,
        .alignment = @alignOf(void),
    }} ** handler_fields.len;
    var field_count: usize = 0;
    inline for (handler_fields) |field| {
        const OutputType = field.type.Output;
        if (OutputType == void) continue;
        fields[field_count] = .{
            .name = field.name,
            .type = OutputType,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(OutputType),
        };
        field_count += 1;
    }
    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = fields[0..field_count],
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

/// Canonical lexical outputs plus body answer returned from `shift.with(...)`.
pub fn WithResult(comptime HandlersType: type, comptime Answer: type) type {
    return struct {
        outputs: OutputBundleType(HandlersType),
        value: Answer,
    };
}

/// Explicit lexical rebinding packet threaded through `shift.with(...)` continuations.
pub fn LexicalState(comptime HandlersType: type, comptime EffType: type) type {
    return struct {
        runtime: *lowered_machine.Runtime,
        handlers_ptr: *HandlersType,
        eff_value: EffType,
        outputs_ptr: *OutputBundleType(HandlersType),
    };
}

fn hasClosedOutputDecl(comptime HandlerType: type) bool {
    return hasDeclSafe(HandlerType, "Output");
}

fn ClosedOutputType(comptime HandlerType: type) type {
    if (!hasClosedOutputDecl(HandlerType)) return void;
    return HandlerType.Output;
}

fn assertClosedFinishShape(comptime HandlerType: type) void {
    if (ClosedOutputType(HandlerType) == void) return;
    if (!hasDeclSafe(HandlerType, "finish")) {
        @compileError(@typeName(HandlerType) ++ " must declare finish(self) when Output is non-void");
    }
    const FinishFn = @TypeOf(HandlerType.finish);
    const FnType = switch (@typeInfo(FinishFn)) {
        .@"fn" => FinishFn,
        .pointer => |pointer| if (@typeInfo(pointer.child) == .@"fn") pointer.child else @compileError(@typeName(HandlerType) ++ ".finish must be callable"),
        else => @compileError(@typeName(HandlerType) ++ ".finish must be callable"),
    };
    const params = @typeInfo(FnType).@"fn".params;
    if (params.len != 1) {
        @compileError(@typeName(HandlerType) ++ ".finish must have exactly one self parameter");
    }
    const SelfParam = params[0].type orelse @compileError(@typeName(HandlerType) ++ ".finish must type its self parameter");
    if (SelfParam != *HandlerType and SelfParam != *const HandlerType) {
        @compileError(@typeName(HandlerType) ++ ".finish must accept *Self or *const Self");
    }
    const ReturnType = @typeInfo(FnType).@"fn".return_type orelse @compileError(@typeName(HandlerType) ++ ".finish must return Output");
    if (ReturnType != ClosedOutputType(HandlerType)) {
        @compileError(@typeName(HandlerType) ++ ".finish must return Output exactly");
    }
}

/// Output bundle that mirrors only the non-void outputs on a closed root handler bundle.
pub fn ClosedOutputBundleType(comptime HandlersType: type) type {
    const info = @typeInfo(HandlersType);
    if (info != .@"struct") @compileError("closed-root handlers must be a struct literal or struct value");
    const handler_fields = info.@"struct".fields;
    var fields = [_]std.builtin.Type.StructField{.{
        .name = "",
        .type = void,
        .default_value_ptr = null,
        .is_comptime = false,
        .alignment = @alignOf(void),
    }} ** handler_fields.len;
    var field_count: usize = 0;
    inline for (handler_fields) |field| {
        comptime assertClosedFinishShape(field.type);
        const OutputType = ClosedOutputType(field.type);
        if (OutputType == void) continue;
        fields[field_count] = .{
            .name = field.name,
            .type = OutputType,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(OutputType),
        };
        field_count += 1;
    }
    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = fields[0..field_count],
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

/// Canonical closed-root result: final outputs plus answer.
pub fn ClosedRunResult(comptime HandlersType: type, comptime Answer: type) type {
    return struct {
        outputs: ClosedOutputBundleType(HandlersType),
        value: Answer,
    };
}

/// Extract outputs from one closed handler bundle after the root has run.
pub fn collectClosedOutputs(handlers_ptr: anytype) ClosedOutputBundleType(std.meta.Child(@TypeOf(handlers_ptr))) {
    const HandlersType = std.meta.Child(@TypeOf(handlers_ptr));
    const OutputsType = ClosedOutputBundleType(HandlersType);
    var outputs = std.mem.zeroInit(OutputsType, .{});
    inline for (@typeInfo(HandlersType).@"struct".fields) |field| {
        const HandlerType = field.type;
        if (ClosedOutputType(HandlerType) == void) continue;
        const handler_ptr = &@field(handlers_ptr.*, field.name);
        @field(outputs, field.name) = handler_ptr.finish();
    }
    return outputs;
}

fn ReturnTypeErrorSet(comptime ReturnType: type) type {
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.error_set,
        else => error{},
    };
}

fn assertHandlerBundleShape(comptime HandlersType: type) void {
    const info = @typeInfo(HandlersType);
    if (info != .@"struct") @compileError("shift.with handlers must be a struct literal or struct value");
    if (info.@"struct".fields.len == 0) @compileError("shift.with handlers must declare at least one binding");
    inline for (info.@"struct".fields) |field| {
        const DescriptorType = field.type;
        if (!@hasDecl(DescriptorType, "ErrorSet")) @compileError(@typeName(DescriptorType) ++ " must declare ErrorSet");
        if (!@hasDecl(DescriptorType, "Output")) @compileError(@typeName(DescriptorType) ++ " must declare Output");
        if (!@hasDecl(DescriptorType, "HandleType")) @compileError(@typeName(DescriptorType) ++ " must declare HandleType");
        if (!@hasDecl(DescriptorType, "bindLexical")) @compileError(@typeName(DescriptorType) ++ " must declare bindLexical");
        if (!@hasDecl(DescriptorType, "run")) @compileError(@typeName(DescriptorType) ++ " must declare run");
    }
}

fn hasDeclSafe(comptime T: type, comptime name: []const u8) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, name),
        else => false,
    };
}

fn ContinuationCarrierType(comptime Continuation: anytype) type {
    return if (@TypeOf(Continuation) == type) Continuation else @TypeOf(Continuation);
}

fn continuationHasApply(comptime Continuation: anytype) bool {
    return hasDeclSafe(ContinuationCarrierType(Continuation), "apply");
}

fn HandlerErrorSet(comptime HandlersType: type) type {
    comptime assertHandlerBundleShape(HandlersType);
    const fields = @typeInfo(HandlersType).@"struct".fields;
    var ErrorSet = fields[0].type.ErrorSet;
    inline for (fields[1..]) |field| {
        ErrorSet = ErrorSet || field.type.ErrorSet;
    }
    return ErrorSet;
}

fn ExtendBundleType(comptime Base: type, comptime field_name: [:0]const u8, comptime FieldType: type) type {
    const base_fields = @typeInfo(Base).@"struct".fields;
    var fields = [_]std.builtin.Type.StructField{.{
        .name = "",
        .type = void,
        .default_value_ptr = null,
        .is_comptime = false,
        .alignment = @alignOf(void),
    }} ** (base_fields.len + 1);
    inline for (base_fields, 0..) |field, index| {
        fields[index] = .{
            .name = field.name,
            .type = field.type,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = field.alignment,
        };
    }
    fields[base_fields.len] = .{
        .name = field_name,
        .type = FieldType,
        .default_value_ptr = null,
        .is_comptime = false,
        .alignment = @alignOf(FieldType),
    };
    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

fn extendBundle(comptime Base: type, base: Base, comptime field_name: [:0]const u8, value: anytype) ExtendBundleType(Base, field_name, @TypeOf(value)) {
    const Extended = ExtendBundleType(Base, field_name, @TypeOf(value));
    var result: Extended = std.mem.zeroInit(Extended, .{});
    inline for (@typeInfo(Base).@"struct".fields) |field| {
        @field(result, field.name) = @field(base, field.name);
    }
    @field(result, field_name) = value;
    return result;
}

fn ExplicitProgramContinuationFnType(comptime Continuation: anytype) type {
    const Carrier = ContinuationCarrierType(Continuation);
    if (continuationHasApply(Continuation)) return @TypeOf(Continuation.apply);
    return switch (@typeInfo(Carrier)) {
        .@"fn" => Carrier,
        .pointer => |pointer| if (@typeInfo(pointer.child) == .@"fn")
            pointer.child
        else
            @compileError("lexical explicit-program continuation must declare apply(value) or be a callable function"),
        else => @compileError("lexical explicit-program continuation must declare apply(value) or be a callable function"),
    };
}

fn ExplicitProgramContinuationReturnType(comptime Continuation: anytype, comptime ResumeType: type) type {
    const ContinuationFn = ExplicitProgramContinuationFnType(Continuation);
    const params = @typeInfo(ContinuationFn).@"fn".params;
    if (params.len != 1) @compileError("lexical explicit-program continuation must accept exactly one resumed value");
    if (comptime continuationHasApply(Continuation)) {
        return @TypeOf(Continuation.apply(dummyValue(ResumeType)));
    }
    if (comptime @TypeOf(Continuation) == type) @compileError("lexical explicit-program continuations must be passed as callable values, not function types");
    return @TypeOf(Continuation(dummyValue(ResumeType)));
}

fn ExplicitProgramContinuationAnswerType(comptime Continuation: anytype, comptime ResumeType: type) type {
    const ReturnType = ExplicitProgramContinuationReturnType(Continuation, ResumeType);
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.payload,
        else => ReturnType,
    };
}

fn ExplicitProgramContinuationErrorSet(comptime Continuation: anytype, comptime ResumeType: type) type {
    return ReturnTypeErrorSet(ExplicitProgramContinuationReturnType(Continuation, ResumeType));
}

fn PreviewEngineContext(comptime ErrorSet: type) type {
    return struct {
        /// Perform this public operation.
        pub fn perform(_: *@This(), comptime Op: type, _: Op.Payload) lowered_machine.ResetError(ErrorSet)!Op.Resume {
            unreachable;
        }

        /// Build this public explicit program.
        pub fn performProgram(
            _: *@This(),
            comptime Op: type,
            _: Op.Payload,
            comptime Continuation: anytype,
        ) frontend.BoundProgram(prompt_contract.Prompt(
            Op.mode,
            Op.Resume,
            ExplicitProgramContinuationAnswerType(Continuation, Op.Resume),
            ErrorSet || ExplicitProgramContinuationErrorSet(Continuation, Op.Resume),
        )) {
            unreachable;
        }

        /// Build this public explicit program with one runtime continuation context.
        pub fn performProgramWithContext(
            _: *@This(),
            comptime Op: type,
            _: Op.Payload,
            _: anytype,
            comptime Continuation: type,
        ) frontend.BoundProgram(prompt_contract.Prompt(
            Op.mode,
            Op.Resume,
            switch (@typeInfo(@TypeOf(Continuation.apply(dummyValue(@typeInfo(@TypeOf(Continuation.apply)).@"fn".params[0].type.?), dummyValue(Op.Resume))))) {
                .error_union => |err_union| err_union.payload,
                else => @TypeOf(Continuation.apply(dummyValue(@typeInfo(@TypeOf(Continuation.apply)).@"fn".params[0].type.?), dummyValue(Op.Resume))),
            },
            ErrorSet || ReturnTypeErrorSet(@TypeOf(Continuation.apply(dummyValue(@typeInfo(@TypeOf(Continuation.apply)).@"fn".params[0].type.?), dummyValue(Op.Resume)))),
        )) {
            unreachable;
        }
    };
}

fn PreviewWriterItemType(comptime DescriptorType: type) type {
    return switch (@typeInfo(DescriptorType.Output)) {
        .pointer => |pointer| if (pointer.size == .slice) pointer.child else void,
        else => void,
    };
}

fn PreviewCapabilityType(comptime DescriptorType: type, comptime ErrorSet: type) type {
    const StateType = DescriptorType.State;
    const WriterItemType = PreviewWriterItemType(DescriptorType);
    return struct {
        engine_ctx: ?*anyopaque = null,

        /// Return the engine context type for this public helper.
        pub fn EngineContextType() type {
            return PreviewEngineContext(ErrorSet);
        }

        /// Return the public get operation type.
        pub fn GetOp() type {
            return struct {
                /// Public `mode` declaration.
                pub const mode = prompt_contract.PromptMode.resume_then_transform;
                /// Public `Payload` declaration.
                pub const Payload = void;
                /// Public `Resume` declaration.
                pub const Resume = StateType;
            };
        }

        /// Return the public set operation type.
        pub fn SetOp() type {
            return struct {
                /// Public `mode` declaration.
                pub const mode = prompt_contract.PromptMode.resume_then_transform;
                /// Public `Payload` declaration.
                pub const Payload = StateType;
                /// Public `Resume` declaration.
                pub const Resume = void;
            };
        }

        /// Return the public ask operation type.
        pub fn AskOp() type {
            return struct {
                /// Public `mode` declaration.
                pub const mode = prompt_contract.PromptMode.resume_then_transform;
                /// Public `Payload` declaration.
                pub const Payload = void;
                /// Public `Resume` declaration.
                pub const Resume = StateType;
            };
        }

        /// Return the public tell operation type.
        pub fn TellOp() type {
            return struct {
                /// Public `mode` declaration.
                pub const mode = prompt_contract.PromptMode.resume_then_transform;
                /// Public `Payload` declaration.
                pub const Payload = WriterItemType;
                /// Public `Resume` declaration.
                pub const Resume = void;
            };
        }

        /// Return the public throw operation type.
        pub fn ThrowOp() type {
            return struct {
                /// Public `mode` declaration.
                pub const mode = prompt_contract.PromptMode.direct_return;
                /// Public `Payload` declaration.
                pub const Payload = StateType;
                /// Public `Resume` declaration.
                pub const Resume = noreturn;
            };
        }

        /// Return the public request operation type.
        pub fn RequestOp() type {
            return struct {
                /// Public `mode` declaration.
                pub const mode = prompt_contract.PromptMode.resume_or_return;
                /// Public `Payload` declaration.
                pub const Payload = void;
                /// Public `Resume` declaration.
                pub const Resume = StateType;
            };
        }

        /// Return the public acquire operation type.
        pub fn AcquireOp() type {
            return struct {
                /// Public `mode` declaration.
                pub const mode = prompt_contract.PromptMode.resume_then_transform;
                /// Public `Payload` declaration.
                pub const Payload = void;
                /// Public `Resume` declaration.
                pub const Resume = StateType;
            };
        }
    };
}

fn PreviewContextPtrType(comptime DescriptorType: type, comptime ErrorSet: type) type {
    const PreviewCapability = PreviewCapabilityType(DescriptorType, ErrorSet);
    return *family.Context(PreviewCapability, DescriptorType.State, void, ErrorSet);
}

fn PreviewHandleType(
    comptime DescriptorType: type,
    comptime HandlersType: type,
    comptime PreviousEffType: type,
    comptime index: usize,
    comptime ErrorSet: type,
) type {
    const HandleFn = @TypeOf(DescriptorType.HandleType);
    const params = @typeInfo(HandleFn).@"fn".params;
    const PreviewCapability = PreviewCapabilityType(DescriptorType, ErrorSet);
    return switch (params.len) {
        2 => DescriptorType.HandleType(
            PreviewCapability,
            PreviewContextPtrType(DescriptorType, ErrorSet),
        ),
        5 => DescriptorType.HandleType(
            PreviewCapability,
            PreviewContextPtrType(DescriptorType, ErrorSet),
            HandlersType,
            PreviousEffType,
            index,
        ),
        else => @compileError("shift.with descriptor HandleType must accept either (Cap, ContextPtrType) or (Cap, ContextPtrType, HandlersType, PreviousEffType, index)"),
    };
}

fn PreviewEffType(
    comptime HandlersType: type,
    comptime index: usize,
    comptime EffType: type,
    comptime ErrorSet: type,
) type {
    const fields = @typeInfo(HandlersType).@"struct".fields;
    if (index == fields.len) return EffType;

    const field = fields[index];
    const HandleType = PreviewHandleType(field.type, HandlersType, EffType, index, ErrorSet);
    const NextEffType = ExtendBundleType(EffType, field.name, HandleType);
    return PreviewEffType(HandlersType, index + 1, NextEffType, ErrorSet);
}

fn PreviewBodyEffType(comptime HandlersType: type) type {
    const ErrorSet = HandlerErrorSet(HandlersType);
    return PreviewEffType(HandlersType, 0, struct {}, ErrorSet);
}

fn BodyDeclSemanticErrorSet(comptime Body: type) ?type {
    if (hasDeclSafe(Body, "SemanticErrorSet")) return Body.SemanticErrorSet;
    return null;
}

/// Return the public continuation effect type.
pub fn ContinuationEffType(
    comptime HandlersType: type,
    comptime index: usize,
    comptime PreviousEffType: type,
    comptime CurrentHandleType: type,
) type {
    const field = @typeInfo(HandlersType).@"struct".fields[index];
    const CurrentEff = ExtendBundleType(PreviousEffType, field.name, CurrentHandleType);
    return PreviewEffType(HandlersType, index + 1, CurrentEff, HandlerErrorSet(HandlersType));
}

fn BodyFunctionType(comptime Body: type) type {
    if (switch (@typeInfo(Body)) {
        .pointer => |pointer| @typeInfo(pointer.child) == .@"fn",
        .@"fn" => true,
        else => false,
    }) return Body;
    if (@hasDecl(Body, "body")) return @TypeOf(Body.body);
    if (@hasDecl(Body, "run")) return @TypeOf(Body.run);
    @compileError("shift.with body must be a function or a type declaring body(eff)");
}

fn BodyRunFnType(comptime Body: type) type {
    const RunFn = @TypeOf(Body.run);
    return switch (@typeInfo(RunFn)) {
        .pointer => |pointer| if (@typeInfo(pointer.child) == .@"fn") pointer.child else @compileError("shift.with body run must be callable"),
        .@"fn" => RunFn,
        else => @compileError("shift.with body run must be callable"),
    };
}

fn bodyRunSelfValue(comptime Body: type) Body {
    if (@sizeOf(Body) != 0) {
        @compileError("shift.with body run(self, eff) requires a zero-sized body type; use run(eff) for stateful bodies");
    }
    return .{};
}

fn BodyReturnType(comptime Body: type, comptime EffType: type) type {
    if (@hasDecl(Body, "body")) return @TypeOf(Body.body(dummyValue(EffType)));
    if (@hasDecl(Body, "run")) {
        const params = @typeInfo(BodyRunFnType(Body)).@"fn".params;
        if (params.len == 1) return @TypeOf(Body.run(dummyValue(EffType)));
        if (params.len == 2) {
            const FirstParam = params[0].type orelse @compileError("shift.with body run must type every parameter");
            if (FirstParam == type) return @TypeOf(Body.run(Body, dummyValue(EffType)));
            if (FirstParam == Body) return @TypeOf(Body.run(bodyRunSelfValue(Body), dummyValue(EffType)));
            if (FirstParam == *Body or FirstParam == *const Body) {
                var self = bodyRunSelfValue(Body);
                return @TypeOf(Body.run(&self, dummyValue(EffType)));
            }
        }
        @compileError("shift.with body run must accept either (eff), (self, eff), (*self, eff), or (BodyType, eff)");
    }
    return @TypeOf(Body(dummyValue(EffType)));
}

fn BodyAnswerType(comptime Body: type, comptime EffType: type) type {
    const ReturnType = BodyReturnType(Body, EffType);
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.payload,
        else => ReturnType,
    };
}

fn BodyErrorSet(comptime Body: type, comptime EffType: type) type {
    return ReturnTypeErrorSet(BodyReturnType(Body, EffType));
}

fn callBody(
    comptime Body: type,
    eff: anytype,
    comptime ErrorSet: type,
    comptime AnswerType: type,
) lowered_machine.ResetError(ErrorSet)!AnswerType {
    const BodyFn = BodyFunctionType(Body);
    const FnType = switch (@typeInfo(BodyFn)) {
        .pointer => |pointer| pointer.child,
        .@"fn" => BodyFn,
        else => unreachable,
    };
    const ReturnType = @typeInfo(FnType).@"fn".return_type.?;

    if (@hasDecl(Body, "body")) {
        if (@typeInfo(ReturnType) == .error_union) {
            return Body.body(eff) catch |err| return @errorCast(err);
        }
        return Body.body(eff);
    }

    if (@hasDecl(Body, "run")) {
        const params = @typeInfo(BodyRunFnType(Body)).@"fn".params;
        if (params.len == 1) {
            if (@typeInfo(ReturnType) == .error_union) {
                return Body.run(eff) catch |err| return @errorCast(err);
            }
            return Body.run(eff);
        }
        if (params.len == 2) {
            const FirstParam = params[0].type orelse @compileError("shift.with body run must type every parameter");
            if (FirstParam == type) {
                if (@typeInfo(ReturnType) == .error_union) {
                    return Body.run(Body, eff) catch |err| return @errorCast(err);
                }
                return Body.run(Body, eff);
            }
            if (FirstParam == Body) {
                const self = bodyRunSelfValue(Body);
                if (@typeInfo(ReturnType) == .error_union) {
                    return Body.run(self, eff) catch |err| return @errorCast(err);
                }
                return Body.run(self, eff);
            }
            if (FirstParam == *Body or FirstParam == *const Body) {
                var self = bodyRunSelfValue(Body);
                if (@typeInfo(ReturnType) == .error_union) {
                    return Body.run(&self, eff) catch |err| return @errorCast(err);
                }
                return Body.run(&self, eff);
            }
        }
        @compileError("shift.with body run must accept either (eff), (self, eff), (*self, eff), or (BodyType, eff)");
    }

    if (@typeInfo(ReturnType) == .error_union) {
        return Body(eff) catch |err| return @errorCast(err);
    }
    return Body(eff);
}

fn ContinuationFnType(comptime Continuation: anytype) type {
    const Carrier = ContinuationCarrierType(Continuation);
    if (continuationHasApply(Continuation)) return @TypeOf(Continuation.apply);
    return switch (@typeInfo(Carrier)) {
        .@"fn" => Carrier,
        .pointer => |pointer| if (@typeInfo(pointer.child) == .@"fn")
            pointer.child
        else
            @compileError("lexical choice continuation must declare apply(value, eff) or be a callable function"),
        else => @compileError("lexical choice continuation must declare apply(value, eff) or be a callable function"),
    };
}

fn ContinuationReturnType(
    comptime Continuation: anytype,
    comptime ResumeType: type,
    comptime EffType: type,
) type {
    const ResumeFn = ContinuationFnType(Continuation);
    const params = @typeInfo(ResumeFn).@"fn".params;
    if (params.len != 2) @compileError("lexical choice continuation apply must accept exactly (value, eff)");
    if (comptime continuationHasApply(Continuation)) {
        return @TypeOf(Continuation.apply(dummyValue(ResumeType), dummyValue(EffType)));
    }
    if (comptime @TypeOf(Continuation) == type) @compileError("lexical choice continuations must be passed as callable values, not function types");
    return @TypeOf(Continuation(dummyValue(ResumeType), dummyValue(EffType)));
}

fn dummyPointer(comptime PtrType: type) PtrType {
    const pointer = @typeInfo(PtrType).pointer;
    const Child = std.meta.Child(PtrType);
    return switch (pointer.size) {
        .slice => blk: {
            const base = std.mem.alignForward(usize, 1, @alignOf(Child));
            const many = @as([*]Child, @ptrFromInt(base));
            const slice = many[0..1];
            if (pointer.is_const) break :blk @as(PtrType, slice);
            break :blk @as(PtrType, @constCast(slice));
        },
        else => @as(PtrType, @ptrFromInt(std.mem.alignForward(usize, 1, @alignOf(Child)))),
    };
}

fn dummyValue(comptime T: type) T {
    return switch (@typeInfo(T)) {
        .pointer => dummyPointer(T),
        .optional => |optional| dummyValue(optional.child),
        .@"struct" => |info| blk: {
            var value_buffer: T = undefined;
            inline for (info.fields) |field| {
                @field(value_buffer, field.name) = dummyValue(field.type);
            }
            break :blk value_buffer;
        },
        .void => {},
        else => dummyPointer(*T).*,
    };
}

/// Resolve the final answer type produced by one lexical choice continuation.
pub fn ChoiceAnswerType(comptime Continuation: anytype) type {
    const ResumeFn = ContinuationFnType(Continuation);
    const ReturnType = @typeInfo(ResumeFn).@"fn".return_type.?;
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.payload,
        else => ReturnType,
    };
}

/// Return the public choice answer type for one continuation.
pub fn ChoiceAnswerTypeFor(
    comptime Continuation: anytype,
    comptime ResumeType: type,
    comptime EffType: type,
) type {
    const ReturnType = ContinuationReturnType(Continuation, ResumeType, EffType);
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.payload,
        else => ReturnType,
    };
}

fn ChoiceErrorSet(
    comptime Continuation: anytype,
    comptime ResumeType: type,
    comptime EffType: type,
) type {
    return ReturnTypeErrorSet(ContinuationReturnType(Continuation, ResumeType, EffType));
}

/// Return the public choice execution error set.
pub fn ChoiceExecutionErrorSet(
    comptime BaseErrorSet: type,
    comptime Continuation: anytype,
    comptime ResumeType: type,
    comptime EffType: type,
) type {
    return BaseErrorSet || ChoiceErrorSet(Continuation, ResumeType, EffType);
}

fn callChoiceContinuation(
    comptime Continuation: anytype,
    resume_value: anytype,
    eff: anytype,
    comptime ErrorSet: type,
) lowered_machine.ResetError(ErrorSet)!ChoiceAnswerTypeFor(Continuation, @TypeOf(resume_value), @TypeOf(eff)) {
    const ResumeFn = ContinuationFnType(Continuation);
    const params = @typeInfo(ResumeFn).@"fn".params;
    if (params.len != 2) @compileError("lexical choice continuation apply must accept exactly (value, eff)");
    const ReturnType = ContinuationReturnType(Continuation, @TypeOf(resume_value), @TypeOf(eff));
    if (comptime continuationHasApply(Continuation)) {
        if (@typeInfo(ReturnType) == .error_union) {
            return Continuation.apply(resume_value, eff) catch |err| return @errorCast(err);
        }
        return Continuation.apply(resume_value, eff);
    }
    if (comptime @TypeOf(Continuation) == type) @compileError("lexical choice continuations must be passed as callable values, not function types");
    if (@typeInfo(ReturnType) == .error_union) {
        return Continuation(resume_value, eff) catch |err| return @errorCast(err);
    }
    return Continuation(resume_value, eff);
}

fn CollectedRunState(comptime HandlersType: type, comptime EffType: type) type {
    return LexicalState(HandlersType, EffType);
}

fn ChoiceRunState(comptime HandlersType: type, comptime EffType: type) type {
    return LexicalState(HandlersType, EffType);
}

/// Recover the active lexical rebinding packet from the exact context capability.
pub fn activeLexicalState(
    ctx: anytype,
    comptime HandlersType: type,
    comptime EffType: type,
) *LexicalState(HandlersType, EffType) {
    return @ptrCast(@alignCast(ctx._cap.lexical_state.?));
}

fn runChainCollected(
    comptime HandlersType: type,
    comptime Body: type,
    comptime index: usize,
    comptime EffType: type,
    state: CollectedRunState(HandlersType, EffType),
) lowered_machine.ResetError(HandlerErrorSet(HandlersType) || BodyErrorSet(Body, PreviewBodyEffType(HandlersType)))!BodyAnswerType(Body, PreviewBodyEffType(HandlersType)) {
    const ErrorSet = HandlerErrorSet(HandlersType) || BodyErrorSet(Body, PreviewBodyEffType(HandlersType));
    const Answer = BodyAnswerType(Body, PreviewBodyEffType(HandlersType));
    const fields = @typeInfo(HandlersType).@"struct".fields;

    if (index == fields.len) {
        return try callBody(Body, state.eff_value, ErrorSet, Answer);
    }

    const field = fields[index];
    const DescriptorType = field.type;
    const desc_value: DescriptorType = @field(state.handlers_ptr.*, field.name);

    const step_ctx = struct {
        /// Extend the lexical effect bundle with one bound handle, thread the shared outputs bundle, and continue inward.
        pub fn body(comptime Cap: type, ctx: anytype) lowered_machine.ResetError(ErrorSet)!Answer {
            const lexical_state = activeLexicalState(ctx, HandlersType, EffType);
            const current_desc: DescriptorType = @field(lexical_state.handlers_ptr.*, field.name);
            const handle = blk: {
                const BindFn = @TypeOf(DescriptorType.bindLexical);
                const params = @typeInfo(BindFn).@"fn".params;
                switch (params.len) {
                    3 => break :blk current_desc.bindLexical(Cap, ctx),
                    6 => break :blk current_desc.bindLexical(Cap, ctx, HandlersType, EffType, index),
                    else => @compileError("shift.with descriptor bindLexical must accept either (self, Cap, ctx) or (self, Cap, ctx, HandlersType, PreviousEffType, index)"),
                }
            };
            const next_eff = extendBundle(EffType, lexical_state.eff_value, field.name, handle);
            return try runChainCollected(HandlersType, Body, index + 1, @TypeOf(next_eff), .{
                .runtime = lexical_state.runtime,
                .handlers_ptr = lexical_state.handlers_ptr,
                .eff_value = next_eff,
                .outputs_ptr = lexical_state.outputs_ptr,
            });
        }
    };

    const result = desc_value.run(Answer, ErrorSet, state.runtime, &state, step_ctx) catch |err| return @errorCast(err);
    if (DescriptorType.Output != void) {
        @field(state.outputs_ptr.*, field.name) = result.output;
    }
    return result.value;
}

fn runChoiceChain(
    comptime HandlersType: type,
    comptime index: usize,
    comptime EffType: type,
    state: ChoiceRunState(HandlersType, EffType),
    comptime Continuation: anytype,
    resume_value: anytype,
) lowered_machine.ResetError(HandlerErrorSet(HandlersType) || ChoiceErrorSet(Continuation, @TypeOf(resume_value), EffType))!ChoiceAnswerTypeFor(Continuation, @TypeOf(resume_value), EffType) {
    const ErrorSet = HandlerErrorSet(HandlersType) || ChoiceErrorSet(Continuation, @TypeOf(resume_value), EffType);
    const fields = @typeInfo(HandlersType).@"struct".fields;

    if (index == fields.len) {
        return try callChoiceContinuation(Continuation, resume_value, state.eff_value, ErrorSet);
    }

    const field = fields[index];
    const DescriptorType = field.type;
    const desc_value: DescriptorType = @field(state.handlers_ptr.*, field.name);

    const step_ctx = struct {
        /// Extend the lexical bundle during choice continuation re-entry and continue inward.
        pub fn body(comptime Cap: type, ctx: anytype) lowered_machine.ResetError(ErrorSet)!ChoiceAnswerTypeFor(Continuation, @TypeOf(resume_value), EffType) {
            const lexical_state = activeLexicalState(ctx, HandlersType, EffType);
            const current_desc: DescriptorType = @field(lexical_state.handlers_ptr.*, field.name);
            const handle = blk: {
                const BindFn = @TypeOf(DescriptorType.bindLexical);
                const params = @typeInfo(BindFn).@"fn".params;
                switch (params.len) {
                    3 => break :blk current_desc.bindLexical(Cap, ctx),
                    6 => break :blk current_desc.bindLexical(Cap, ctx, HandlersType, EffType, index),
                    else => @compileError("shift.with descriptor bindLexical must accept either (self, Cap, ctx) or (self, Cap, ctx, HandlersType, PreviousEffType, index)"),
                }
            };
            const next_eff = extendBundle(EffType, lexical_state.eff_value, field.name, handle);
            return try runChoiceChain(HandlersType, index + 1, @TypeOf(next_eff), .{
                .runtime = lexical_state.runtime,
                .handlers_ptr = lexical_state.handlers_ptr,
                .eff_value = next_eff,
                .outputs_ptr = lexical_state.outputs_ptr,
            }, Continuation, resume_value);
        }
    };

    const result = desc_value.run(ChoiceAnswerTypeFor(Continuation, @TypeOf(resume_value), EffType), ErrorSet, state.runtime, &state, step_ctx) catch |err| return @errorCast(err);
    if (DescriptorType.Output != void) {
        @field(state.outputs_ptr.*, field.name) = result.output;
    }
    return result.value;
}

/// Continue one lexical choice continuation by rebuilding the remaining `eff` bundle from the current handler slot onward.
pub fn continueChoice(
    comptime HandlersType: type,
    comptime index: usize,
    frame: anytype,
    comptime Continuation: anytype,
    resume_value: anytype,
) lowered_machine.ResetError(HandlerErrorSet(HandlersType) || ChoiceErrorSet(Continuation, @TypeOf(resume_value), ContinuationEffType(HandlersType, index, @TypeOf(frame.previous_eff), @TypeOf(frame.current_handle))))!ChoiceAnswerTypeFor(Continuation, @TypeOf(resume_value), ContinuationEffType(HandlersType, index, @TypeOf(frame.previous_eff), @TypeOf(frame.current_handle))) {
    const field = @typeInfo(HandlersType).@"struct".fields[index];
    const current_eff = extendBundle(@TypeOf(frame.previous_eff), frame.previous_eff, field.name, frame.current_handle);
    return try runChoiceChain(HandlersType, index + 1, @TypeOf(current_eff), .{
        .runtime = frame.runtime,
        .handlers_ptr = frame.handlers_ptr,
        .eff_value = current_eff,
        .outputs_ptr = frame.outputs_ptr,
    }, Continuation, resume_value);
}

/// Return type for one lexical `shift.with(...)` instantiation.
pub fn WithFnReturnType(comptime HandlersType: type, comptime Body: type) type {
    const HandlerSet = HandlerErrorSet(HandlersType);
    const PreviewEff = PreviewBodyEffType(HandlersType);
    return lowered_machine.ResetError(HandlerSet || BodyErrorSet(Body, PreviewEff))!WithResult(HandlersType, BodyAnswerType(Body, PreviewEff));
}

fn WithSemanticErrorSet(comptime HandlersType: type, comptime Body: type) type {
    const HandlerSet = HandlerErrorSet(HandlersType);
    if (BodyDeclSemanticErrorSet(Body)) |BodySet| return HandlerSet || BodySet;
    const PreviewEff = PreviewBodyEffType(HandlersType);
    const BodySet = BodyErrorSet(Body, PreviewEff);
    return HandlerSet || BodySet;
}

/// Build the public With metadata type.
pub fn With(comptime HandlersType: type, comptime Body: type) type {
    const ReturnType = WithFnReturnType(HandlersType, Body);
    return struct {
        /// Public `Result` declaration.
        pub const Result = switch (@typeInfo(ReturnType)) {
            .error_union => |err_union| err_union.payload,
            else => ReturnType,
        };
        /// Public `SemanticErrorSet` declaration.
        pub const SemanticErrorSet = WithSemanticErrorSet(HandlersType, Body);
        /// Public `ExecutionError` declaration.
        pub const ExecutionError = switch (@typeInfo(ReturnType)) {
            .error_union => |err_union| err_union.error_set,
            else => error{},
        };
    };
}

/// Run one lexical effect bundle and return descriptor outputs alongside the body answer.
pub fn with(
    runtime: *lowered_machine.Runtime,
    handlers: anytype,
    comptime Body: type,
) WithFnReturnType(@TypeOf(handlers), Body) {
    const HandlersType = @TypeOf(handlers);
    comptime assertHandlerBundleShape(HandlersType);

    var handler_state = handlers;
    var outputs = std.mem.zeroInit(OutputBundleType(HandlersType), .{});
    const value = try runChainCollected(HandlersType, Body, 0, struct {}, .{
        .runtime = runtime,
        .handlers_ptr = &handler_state,
        .eff_value = .{},
        .outputs_ptr = &outputs,
    });
    return .{
        .outputs = outputs,
        .value = value,
    };
}

test "closed output bundle keeps only handlers with Output" {
    const Handlers = struct {
        state: struct {
            /// Explicit output type used by this test state handler.
            pub const Output = i32;

            /// Finalize the test state handler output.
            pub fn finish(_: *@This()) i32 {
                return 7;
            }
        },
        reader: struct {},
        writer: struct {
            /// Explicit output type used by this test writer handler.
            pub const Output = [4]u8;

            /// Finalize the test writer handler output.
            pub fn finish(_: *@This()) [4]u8 {
                return .{ 'd', 'o', 'n', 'e' };
            }
        },
    };

    const Outputs = ClosedOutputBundleType(Handlers);
    try std.testing.expect(@hasField(Outputs, "state"));
    try std.testing.expect(!@hasField(Outputs, "reader"));
    try std.testing.expect(@hasField(Outputs, "writer"));
}

test "collectClosedOutputs mirrors finish results" {
    const StateHandler = struct {
        value: i32,
        /// Explicit output type carried by this test state handler.
        pub const Output = i32;

        /// Finalize the test state handler output.
        pub fn finish(self: *@This()) i32 {
            return self.value;
        }
    };
    const reader_handler = struct {};
    const writer_handler = struct {
        /// Explicit output type carried by this test writer handler.
        pub const Output = [4]u8;

        /// Finalize the test writer handler output.
        pub fn finish(_: *@This()) [4]u8 {
            return .{ 'd', 'o', 'n', 'e' };
        }
    };
    const Handlers = struct {
        state: StateHandler,
        reader: reader_handler,
        writer: writer_handler,
    };
    var handlers: Handlers = .{
        .state = .{ .value = 9 },
        .reader = .{},
        .writer = .{},
    };

    const outputs = collectClosedOutputs(&handlers);
    try std.testing.expectEqual(@as(i32, 9), outputs.state);
    try std.testing.expectEqualSlices(u8, "done", outputs.writer[0..]);
}

test "collectClosedOutputs finalizes the owned handler fields" {
    const WriterHandler = struct {
        finished: bool = false,
        storage: [4]u8 = .{ 'd', 'o', 'n', 'e' },
        /// Explicit output type carried by this owned writer handler.
        pub const Output = []const u8;

        /// Finalize the owned writer handler output.
        pub fn finish(self: *@This()) []const u8 {
            self.finished = true;
            return self.storage[0..];
        }
    };
    const Handlers = struct {
        writer: WriterHandler,
    };
    var handlers: Handlers = .{
        .writer = WriterHandler{},
    };

    const outputs = collectClosedOutputs(&handlers);
    try std.testing.expect(handlers.writer.finished);
    try std.testing.expectEqualSlices(u8, "done", outputs.writer);
    handlers.writer.storage[0] = 't';
    try std.testing.expectEqual(@as(u8, 't'), outputs.writer[0]);
}

test "collectClosedOutputs preserves const handler pointers for const-safe finish" {
    const ReaderHandler = struct {
        value: i32,
        /// Explicit output type carried by this read-only state handler.
        pub const Output = i32;

        /// Finalize through a const pointer when the handler state is immutable.
        pub fn finish(self: *const @This()) i32 {
            return self.value;
        }
    };
    const Handlers = struct {
        reader: ReaderHandler,
    };
    const handlers: Handlers = .{
        .reader = .{ .value = 9 },
    };

    const outputs = collectClosedOutputs(&handlers);
    try std.testing.expectEqual(@as(i32, 9), outputs.reader);
}
