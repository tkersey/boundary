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

fn ExplicitProgramContinuationFnType(comptime Continuation: type) type {
    if (hasDeclSafe(Continuation, "apply")) return @TypeOf(@field(Continuation, "apply"));
    return switch (@typeInfo(Continuation)) {
        .@"fn" => Continuation,
        .pointer => |pointer| if (@typeInfo(pointer.child) == .@"fn")
            Continuation
        else
            @compileError("lexical explicit-program continuation must declare apply(value) or be a callable function"),
        else => @compileError("lexical explicit-program continuation must declare apply(value) or be a callable function"),
    };
}

fn ExplicitProgramContinuationReturnType(comptime Continuation: type, comptime ResumeType: type) type {
    const ContinuationFn = ExplicitProgramContinuationFnType(Continuation);
    const params = @typeInfo(ContinuationFn).@"fn".params;
    if (params.len != 1) @compileError("lexical explicit-program continuation must accept exactly one resumed value");
    if (comptime hasDeclSafe(Continuation, "apply")) {
        return @TypeOf(@field(Continuation, "apply")(@as(ResumeType, undefined)));
    }
    return @TypeOf(Continuation(@as(ResumeType, undefined)));
}

fn ExplicitProgramContinuationAnswerType(comptime Continuation: type, comptime ResumeType: type) type {
    const ReturnType = ExplicitProgramContinuationReturnType(Continuation, ResumeType);
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.payload,
        else => ReturnType,
    };
}

fn ExplicitProgramContinuationErrorSet(comptime Continuation: type, comptime ResumeType: type) type {
    return ReturnTypeErrorSet(ExplicitProgramContinuationReturnType(Continuation, ResumeType));
}

fn PreviewEngineContext(comptime ErrorSet: type) type {
    return struct {
        pub fn perform(_: *@This(), comptime Op: type, _: Op.Payload) lowered_machine.ResetError(ErrorSet)!Op.Resume {
            unreachable;
        }

        pub fn performProgram(
            _: *@This(),
            comptime Op: type,
            _: Op.Payload,
            comptime Continuation: type,
        ) frontend.BoundProgram(prompt_contract.Prompt(
            Op.mode,
            Op.Resume,
            ExplicitProgramContinuationAnswerType(Continuation, Op.Resume),
            ErrorSet || ExplicitProgramContinuationErrorSet(Continuation, Op.Resume),
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
        pub fn EngineContextType() type {
            return PreviewEngineContext(ErrorSet);
        }

        pub fn GetOp() type {
            return struct {
                pub const mode = prompt_contract.PromptMode.resume_then_transform;
                pub const Payload = void;
                pub const Resume = StateType;
            };
        }

        pub fn SetOp() type {
            return struct {
                pub const mode = prompt_contract.PromptMode.resume_then_transform;
                pub const Payload = StateType;
                pub const Resume = void;
            };
        }

        pub fn AskOp() type {
            return struct {
                pub const mode = prompt_contract.PromptMode.resume_then_transform;
                pub const Payload = void;
                pub const Resume = StateType;
            };
        }

        pub fn TellOp() type {
            return struct {
                pub const mode = prompt_contract.PromptMode.resume_then_transform;
                pub const Payload = WriterItemType;
                pub const Resume = void;
            };
        }

        pub fn ThrowOp() type {
            return struct {
                pub const mode = prompt_contract.PromptMode.direct_return;
                pub const Payload = StateType;
                pub const Resume = noreturn;
            };
        }

        pub fn RequestOp() type {
            return struct {
                pub const mode = prompt_contract.PromptMode.resume_or_return;
                pub const Payload = void;
                pub const Resume = StateType;
            };
        }

        pub fn AcquireOp() type {
            return struct {
                pub const mode = prompt_contract.PromptMode.resume_then_transform;
                pub const Payload = void;
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

pub fn ContinuationEffType(
    comptime HandlersType: type,
    comptime index: usize,
    comptime PreviousEffType: type,
    comptime CurrentHandleType: type,
) type {
    const field = @typeInfo(HandlersType).@"struct".fields[index];
    const current_eff = ExtendBundleType(PreviousEffType, field.name, CurrentHandleType);
    return PreviewEffType(HandlersType, index + 1, current_eff, HandlerErrorSet(HandlersType));
}

fn BodyFunctionType(comptime Body: type) type {
    if (switch (@typeInfo(Body)) {
        .pointer => |pointer| @typeInfo(pointer.child) == .@"fn",
        .@"fn" => true,
        else => false,
    }) return Body;
    if (@hasDecl(Body, "body")) return @TypeOf(Body.body);
    @compileError("shift.with body must be a function or a type declaring body(eff)");
}

fn BodyReturnType(comptime Body: type, comptime EffType: type) type {
    if (@hasDecl(Body, "body")) return @TypeOf(Body.body(@as(EffType, undefined)));
    return @TypeOf(Body(@as(EffType, undefined)));
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

    if (@typeInfo(ReturnType) == .error_union) {
        return Body(eff) catch |err| return @errorCast(err);
    }
    return Body(eff);
}

fn ContinuationFnType(comptime Continuation: type) type {
    if (hasDeclSafe(Continuation, "apply")) return @TypeOf(@field(Continuation, "apply"));
    return switch (@typeInfo(Continuation)) {
        .@"fn" => Continuation,
        .pointer => |pointer| if (@typeInfo(pointer.child) == .@"fn") Continuation else @compileError("lexical choice continuation must declare apply(value, eff) or be a callable function"),
        else => @compileError("lexical choice continuation must declare apply(value, eff) or be a callable function"),
    };
}

fn ContinuationReturnType(
    comptime Continuation: type,
    comptime ResumeType: type,
    comptime EffType: type,
) type {
    const ResumeFn = ContinuationFnType(Continuation);
    const params = @typeInfo(ResumeFn).@"fn".params;
    if (params.len != 2) @compileError("lexical choice continuation apply must accept exactly (value, eff)");
    if (comptime hasDeclSafe(Continuation, "apply")) {
        return @TypeOf(@field(Continuation, "apply")(
            @as(ResumeType, undefined),
            @as(EffType, undefined),
        ));
    }
    return @TypeOf(Continuation(
        @as(ResumeType, undefined),
        @as(EffType, undefined),
    ));
}

/// Resolve the final answer type produced by one lexical choice continuation.
pub fn ChoiceAnswerType(comptime Continuation: type) type {
    const ResumeFn = ContinuationFnType(Continuation);
    const ReturnType = @typeInfo(ResumeFn).@"fn".return_type.?;
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.payload,
        else => ReturnType,
    };
}

pub fn ChoiceAnswerTypeFor(
    comptime Continuation: type,
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
    comptime Continuation: type,
    comptime ResumeType: type,
    comptime EffType: type,
) type {
    return ReturnTypeErrorSet(ContinuationReturnType(Continuation, ResumeType, EffType));
}

pub fn ChoiceExecutionErrorSet(
    comptime BaseErrorSet: type,
    comptime Continuation: type,
    comptime ResumeType: type,
    comptime EffType: type,
) type {
    return BaseErrorSet || ChoiceErrorSet(Continuation, ResumeType, EffType);
}

fn callChoiceContinuation(
    comptime Continuation: type,
    resume_value: anytype,
    eff: anytype,
    comptime ErrorSet: type,
) lowered_machine.ResetError(ErrorSet)!ChoiceAnswerTypeFor(Continuation, @TypeOf(resume_value), @TypeOf(eff)) {
    const ResumeFn = ContinuationFnType(Continuation);
    const params = @typeInfo(ResumeFn).@"fn".params;
    if (params.len != 2) @compileError("lexical choice continuation apply must accept exactly (value, eff)");
    const ReturnType = @typeInfo(ResumeFn).@"fn".return_type.?;
    if (comptime hasDeclSafe(Continuation, "apply")) {
        const invoke = @field(Continuation, "apply");
        if (@typeInfo(ReturnType) == .error_union) {
            return invoke(resume_value, eff) catch |err| return @errorCast(err);
        }
        return invoke(resume_value, eff);
    }
    if (@typeInfo(ReturnType) == .error_union) {
        return Continuation(resume_value, eff) catch |err| return @errorCast(err);
    }
    return Continuation(resume_value, eff);
}

fn CollectedRunState(comptime HandlersType: type, comptime EffType: type) type {
    return struct {
        runtime: *lowered_machine.Runtime,
        handlers_ptr: *HandlersType,
        eff_value: EffType,
        outputs_ptr: *OutputBundleType(HandlersType),
    };
}

fn ChoiceRunState(comptime HandlersType: type, comptime EffType: type) type {
    return struct {
        runtime: *lowered_machine.Runtime,
        handlers_ptr: *HandlersType,
        eff_value: EffType,
        outputs_ptr: *OutputBundleType(HandlersType),
    };
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
        threadlocal var active_handlers: ?*HandlersType = null;
        threadlocal var runtime_ptr: ?*lowered_machine.Runtime = null;
        threadlocal var previous_eff: ?EffType = null;
        threadlocal var outputs_ptr: ?*OutputBundleType(HandlersType) = null;

        /// Extend the lexical effect bundle with one bound handle, thread the shared outputs bundle, and continue inward.
        pub fn body(comptime Cap: type, ctx: anytype) lowered_machine.ResetError(ErrorSet)!Answer {
            const current_desc: DescriptorType = @field(active_handlers.?.*, field.name);
            const handle = blk: {
                const BindFn = @TypeOf(DescriptorType.bindLexical);
                const params = @typeInfo(BindFn).@"fn".params;
                switch (params.len) {
                    3 => break :blk current_desc.bindLexical(Cap, ctx),
                    8 => break :blk current_desc.bindLexical(Cap, ctx, runtime_ptr.?, active_handlers.?, previous_eff.?, outputs_ptr.?, index),
                    else => @compileError("shift.with descriptor bindLexical must accept either (self, Cap, ctx) or (self, Cap, ctx, runtime, handlers_ptr, previous_eff, outputs_ptr, index)"),
                }
            };
            const next_eff = extendBundle(EffType, previous_eff.?, field.name, handle);
            return try runChainCollected(HandlersType, Body, index + 1, @TypeOf(next_eff), .{
                .runtime = runtime_ptr.?,
                .handlers_ptr = active_handlers.?,
                .eff_value = next_eff,
                .outputs_ptr = outputs_ptr.?,
            });
        }
    };

    const previous_handlers = step_ctx.active_handlers;
    const previous_runtime = step_ctx.runtime_ptr;
    const previous_eff = step_ctx.previous_eff;
    const previous_outputs = step_ctx.outputs_ptr;
    step_ctx.active_handlers = state.handlers_ptr;
    step_ctx.runtime_ptr = state.runtime;
    step_ctx.previous_eff = state.eff_value;
    step_ctx.outputs_ptr = state.outputs_ptr;
    defer step_ctx.active_handlers = previous_handlers;
    defer step_ctx.runtime_ptr = previous_runtime;
    defer step_ctx.previous_eff = previous_eff;
    defer step_ctx.outputs_ptr = previous_outputs;

    const result = desc_value.run(Answer, ErrorSet, state.runtime, step_ctx) catch |err| return @errorCast(err);
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
    comptime Continuation: type,
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
        threadlocal var active_handlers: ?*HandlersType = null;
        threadlocal var runtime_ptr: ?*lowered_machine.Runtime = null;
        threadlocal var previous_eff: ?EffType = null;
        threadlocal var outputs_ptr: ?*OutputBundleType(HandlersType) = null;

        /// Extend the lexical bundle during choice continuation re-entry and continue inward.
        pub fn body(comptime Cap: type, ctx: anytype) lowered_machine.ResetError(ErrorSet)!ChoiceAnswerTypeFor(Continuation, @TypeOf(resume_value), EffType) {
            const current_desc: DescriptorType = @field(active_handlers.?.*, field.name);
            const handle = blk: {
                const BindFn = @TypeOf(DescriptorType.bindLexical);
                const params = @typeInfo(BindFn).@"fn".params;
                switch (params.len) {
                    3 => break :blk current_desc.bindLexical(Cap, ctx),
                    8 => break :blk current_desc.bindLexical(Cap, ctx, runtime_ptr.?, active_handlers.?, previous_eff.?, outputs_ptr.?, index),
                    else => @compileError("shift.with descriptor bindLexical must accept either (self, Cap, ctx) or (self, Cap, ctx, runtime, handlers_ptr, previous_eff, outputs_ptr, index)"),
                }
            };
            const next_eff = extendBundle(EffType, previous_eff.?, field.name, handle);
            return try runChoiceChain(HandlersType, index + 1, @TypeOf(next_eff), .{
                .runtime = runtime_ptr.?,
                .handlers_ptr = active_handlers.?,
                .eff_value = next_eff,
                .outputs_ptr = outputs_ptr.?,
            }, Continuation, resume_value);
        }
    };

    const previous_handlers = step_ctx.active_handlers;
    const previous_runtime = step_ctx.runtime_ptr;
    const previous_eff = step_ctx.previous_eff;
    const previous_outputs = step_ctx.outputs_ptr;
    step_ctx.active_handlers = state.handlers_ptr;
    step_ctx.runtime_ptr = state.runtime;
    step_ctx.previous_eff = state.eff_value;
    step_ctx.outputs_ptr = state.outputs_ptr;
    defer step_ctx.active_handlers = previous_handlers;
    defer step_ctx.runtime_ptr = previous_runtime;
    defer step_ctx.previous_eff = previous_eff;
    defer step_ctx.outputs_ptr = previous_outputs;

    const result = desc_value.run(ChoiceAnswerTypeFor(Continuation, @TypeOf(resume_value), EffType), ErrorSet, state.runtime, step_ctx) catch |err| return @errorCast(err);
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
    comptime Continuation: type,
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
    const fields = @typeInfo(BodySet).error_set.?;
    comptime var infra_count: usize = 0;
    inline for (fields) |field| {
        inline for (@typeInfo(lowered_machine.Error).error_set.?) |infra| {
            if (comptime std.mem.eql(u8, field.name, infra.name)) {
                infra_count += 1;
                break;
            }
        }
        inline for (@typeInfo(lowered_machine.SetupError).error_set.?) |infra| {
            if (comptime std.mem.eql(u8, field.name, infra.name)) {
                infra_count += 1;
                break;
            }
        }
    }
    comptime var total_infra_names: usize = 0;
    inline for (@typeInfo(lowered_machine.Error).error_set.?) |_| total_infra_names += 1;
    inline for (@typeInfo(lowered_machine.SetupError).error_set.?) |_| total_infra_names += 1;
    if (infra_count == total_infra_names) {
        @compileError("ambiguous shift.With(...).SemanticErrorSet: declare `pub const SemanticErrorSet = error{...};` on the body type to preserve semantic-only errors when the body also uses effectful operations");
    }
    return HandlerSet || BodySet;
}

pub fn With(comptime HandlersType: type, comptime Body: type) type {
    const ReturnType = WithFnReturnType(HandlersType, Body);
    return struct {
        pub const Result = switch (@typeInfo(ReturnType)) {
            .error_union => |err_union| err_union.payload,
            else => ReturnType,
        };
        pub const SemanticErrorSet = WithSemanticErrorSet(HandlersType, Body);
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
