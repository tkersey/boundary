// zlinter-disable require_doc_comment
const family = @import("../effect/family.zig");
const lowered_machine = @import("lowered_machine");
const prompt_contract = @import("prompt_contract_support");
const std = @import("std");

pub fn DescriptorResult(comptime Output: type, comptime Answer: type) type {
    return struct {
        output: Output,
        value: Answer,
    };
}

pub fn OutputBundleType(comptime HandlersType: type) type {
    comptime assertHandlerBundleShape(HandlersType);
    const handler_fields = @typeInfo(HandlersType).@"struct".fields;
    var field_names = [_][:0]const u8{""} ** handler_fields.len;
    var field_types = [_]type{void} ** handler_fields.len;
    var field_attrs = [_]std.builtin.Type.StructField.Attributes{.{}} ** handler_fields.len;
    var field_count: usize = 0;
    inline for (handler_fields) |field| {
        const OutputType = field.type.Output;
        if (OutputType == void) continue;
        field_names[field_count] = field.name;
        field_types[field_count] = OutputType;
        field_attrs[field_count] = .{ .@"align" = @alignOf(OutputType) };
        field_count += 1;
    }
    return @Struct(.auto, null, field_names[0..field_count], field_types[0..field_count], field_attrs[0..field_count]);
}

pub fn LexicalState(comptime HandlersType: type, comptime EffType: type, comptime caller_source_value: anytype) type {
    return struct {
        pub const caller_source = caller_source_value;
        runtime: *lowered_machine.Runtime,
        handlers_ptr: *HandlersType,
        eff_value: EffType,
        outputs_ptr: *OutputBundleType(HandlersType),
    };
}

fn assertHandlerBundleShape(comptime HandlersType: type) void {
    const info = @typeInfo(HandlersType);
    if (info != .@"struct") @compileError("effect handlers must be a struct literal or struct value");
    if (info.@"struct".fields.len == 0) @compileError("effect handlers must declare at least one binding");
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

fn ReturnTypeErrorSet(comptime ReturnType: type) type {
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.error_set,
        else => error{},
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
    var field_names = [_][:0]const u8{""} ** (base_fields.len + 1);
    var field_types = [_]type{void} ** (base_fields.len + 1);
    var field_attrs = [_]std.builtin.Type.StructField.Attributes{.{}} ** (base_fields.len + 1);
    inline for (base_fields, 0..) |field, index| {
        field_names[index] = field.name;
        field_types[index] = field.type;
        field_attrs[index] = .{ .@"align" = field.alignment };
    }
    field_names[base_fields.len] = field_name;
    field_types[base_fields.len] = FieldType;
    field_attrs[base_fields.len] = .{ .@"align" = @alignOf(FieldType) };
    return @Struct(.auto, null, &field_names, &field_types, &field_attrs);
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

fn PreviewWriterItemType(comptime DescriptorType: type) type {
    return switch (@typeInfo(DescriptorType.Output)) {
        .pointer => |pointer| if (pointer.size == .slice) pointer.child else void,
        else => void,
    };
}

fn PreviewEngineContext(comptime ErrorSet: type) type {
    return struct {
        pub fn perform(_: *@This(), comptime Op: type, _: Op.Payload) lowered_machine.ResetError(ErrorSet)!Op.Resume {
            unreachable;
        }
    };
}

fn PreviewCapabilityType(comptime DescriptorType: type, comptime ErrorSet: type) type {
    const StateType = DescriptorType.State;
    const WriterItemType = PreviewWriterItemType(DescriptorType);
    return struct {
        engine_ctx: ?*anyopaque = null,

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
        else => @compileError("effect descriptor HandleType must accept either (Cap, ContextPtrType) or (Cap, ContextPtrType, HandlersType, PreviousEffType, index)"),
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

fn ContinuationCarrierType(comptime Continuation: anytype) type {
    return if (@TypeOf(Continuation) == type) Continuation else @TypeOf(Continuation);
}

fn continuationHasApply(comptime Continuation: anytype) bool {
    return hasDeclSafe(ContinuationCarrierType(Continuation), "apply");
}

fn ContinuationFnType(comptime Continuation: anytype) type {
    const Carrier = ContinuationCarrierType(Continuation);
    if (continuationHasApply(Continuation)) return @TypeOf(Continuation.apply);
    return switch (@typeInfo(Carrier)) {
        .@"fn" => Carrier,
        .pointer => |pointer| if (@typeInfo(pointer.child) == .@"fn")
            pointer.child
        else
            @compileError("choice continuation must declare apply(value, eff) or be a callable function"),
        else => @compileError("choice continuation must declare apply(value, eff) or be a callable function"),
    };
}

fn dummyPointer(comptime PtrType: type) PtrType {
    const pointer = @typeInfo(PtrType).pointer;
    const Child = std.meta.Child(PtrType);
    if (pointer.size == .slice) {
        const many = @as([*]Child, @ptrFromInt(std.mem.alignForward(usize, 1, @alignOf(Child))));
        const slice = many[0..1];
        if (pointer.is_const) return @as(PtrType, slice);
        return @as(PtrType, @constCast(slice));
    }
    return @as(PtrType, @ptrFromInt(std.mem.alignForward(usize, 1, @alignOf(Child))));
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

fn ContinuationReturnType(
    comptime Continuation: anytype,
    comptime ResumeType: type,
    comptime EffType: type,
) type {
    const ResumeFn = ContinuationFnType(Continuation);
    const params = @typeInfo(ResumeFn).@"fn".params;
    if (params.len != 2) @compileError("choice continuation apply must accept exactly (value, eff)");
    if (comptime continuationHasApply(Continuation)) {
        return @TypeOf(Continuation.apply(dummyValue(ResumeType), dummyValue(EffType)));
    }
    if (comptime @TypeOf(Continuation) == type) @compileError("choice continuations must be passed as callable values, not function types");
    return @TypeOf(Continuation(dummyValue(ResumeType), dummyValue(EffType)));
}

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

pub fn ChoiceFailureSet(
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
    const ReturnType = ContinuationReturnType(Continuation, @TypeOf(resume_value), @TypeOf(eff));
    if (comptime continuationHasApply(Continuation)) {
        if (@typeInfo(ReturnType) == .error_union) {
            return Continuation.apply(resume_value, eff) catch |err| return @errorCast(err);
        }
        return Continuation.apply(resume_value, eff);
    }
    if (comptime @TypeOf(Continuation) == type) @compileError("choice continuations must be passed as callable values, not function types");
    if (@typeInfo(ReturnType) == .error_union) {
        return Continuation(resume_value, eff) catch |err| return @errorCast(err);
    }
    return Continuation(resume_value, eff);
}

fn exactContextCallerSource(comptime ContextPtrType: type) @TypeOf(family.contextCallerSource(ContextPtrType)) {
    return family.contextCallerSource(ContextPtrType);
}

fn ChoiceRunState(
    comptime HandlersType: type,
    comptime EffType: type,
    comptime caller_value: anytype,
    comptime ResumeType: type,
) type {
    return struct {
        pub const caller_source = caller_value;
        resume_value: ResumeType,
        lexical_state: LexicalState(HandlersType, EffType, caller_value),
    };
}

fn descriptorRunContext(
    comptime caller: anytype,
    runtime: *lowered_machine.Runtime,
    lexical_state: anytype,
) struct {
    pub const caller_source = caller;
    runtime: *lowered_machine.Runtime,
    lexical_state: @TypeOf(lexical_state),
} {
    return .{
        .runtime = runtime,
        .lexical_state = lexical_state,
    };
}

pub fn activeLexicalState(
    ctx: anytype,
    comptime HandlersType: type,
    comptime EffType: type,
) *LexicalState(HandlersType, EffType, exactContextCallerSource(@TypeOf(ctx))) {
    return @ptrCast(@alignCast(ctx._cap.lexical_state.?));
}

fn activeChoiceState(
    ctx: anytype,
    comptime HandlersType: type,
    comptime EffType: type,
    comptime ResumeType: type,
) *ChoiceRunState(HandlersType, EffType, exactContextCallerSource(@TypeOf(ctx)), ResumeType) {
    const lexical_state = activeLexicalState(ctx, HandlersType, EffType);
    return @fieldParentPtr("lexical_state", lexical_state);
}

fn ChoiceChainSpec(
    comptime HandlersType: type,
    comptime index_value: usize,
    comptime EffType: type,
    comptime caller_value: anytype,
    comptime ResumeType: type,
    comptime Continuation: anytype,
) type {
    return struct {
        const handlers_type = HandlersType;
        const index = index_value;
        const eff_type = EffType;
        const caller = caller_value;
        const resume_type = ResumeType;
        const continuation = Continuation;
        const StateType = ChoiceRunState(HandlersType, EffType, caller_value, ResumeType);
        const ErrorSet = HandlerErrorSet(HandlersType) || ChoiceErrorSet(Continuation, ResumeType, EffType);
        const AnswerType = ChoiceAnswerTypeFor(Continuation, ResumeType, EffType);
    };
}

fn runChoiceChain(
    comptime Spec: type,
    state: Spec.StateType,
) lowered_machine.ResetError(Spec.ErrorSet)!Spec.AnswerType {
    const fields = @typeInfo(Spec.handlers_type).@"struct".fields;

    if (Spec.index == fields.len) {
        return try callChoiceContinuation(Spec.continuation, state.resume_value, state.lexical_state.eff_value, Spec.ErrorSet);
    }

    const field = fields[Spec.index];
    const DescriptorType = field.type;
    const desc_value: DescriptorType = @field(state.lexical_state.handlers_ptr.*, field.name);

    const step_ctx = struct {
        pub fn body(comptime Cap: type, ctx: anytype) lowered_machine.ResetError(Spec.ErrorSet)!Spec.AnswerType {
            const choice_state = activeChoiceState(ctx, Spec.handlers_type, Spec.eff_type, Spec.resume_type);
            const current_desc: DescriptorType = @field(choice_state.lexical_state.handlers_ptr.*, field.name);
            const handle = blk: {
                const BindFn = @TypeOf(DescriptorType.bindLexical);
                const params = @typeInfo(BindFn).@"fn".params;
                switch (params.len) {
                    3 => break :blk current_desc.bindLexical(Cap, ctx),
                    6 => break :blk current_desc.bindLexical(Cap, ctx, Spec.handlers_type, Spec.eff_type, Spec.index),
                    else => @compileError("effect descriptor bindLexical must accept either (self, Cap, ctx) or (self, Cap, ctx, HandlersType, PreviousEffType, index)"),
                }
            };
            const next_eff = extendBundle(Spec.eff_type, choice_state.lexical_state.eff_value, field.name, handle);
            const next_spec = ChoiceChainSpec(Spec.handlers_type, Spec.index + 1, @TypeOf(next_eff), Spec.caller, Spec.resume_type, Spec.continuation);
            return try runChoiceChain(next_spec, .{
                .resume_value = choice_state.resume_value,
                .lexical_state = .{
                    .runtime = choice_state.lexical_state.runtime,
                    .handlers_ptr = choice_state.lexical_state.handlers_ptr,
                    .eff_value = next_eff,
                    .outputs_ptr = choice_state.lexical_state.outputs_ptr,
                },
            });
        }
    };

    const result = blk: {
        const RunFn = @TypeOf(DescriptorType.run);
        const params = @typeInfo(RunFn).@"fn".params;
        switch (params.len) {
            5 => break :blk desc_value.run(Spec.AnswerType, Spec.ErrorSet, descriptorRunContext(Spec.caller, state.lexical_state.runtime, &state.lexical_state), step_ctx),
            6 => break :blk desc_value.run(Spec.AnswerType, Spec.ErrorSet, state.lexical_state.runtime, &state.lexical_state, step_ctx),
            else => @compileError("effect descriptor run must accept either (self, AnswerType, RunErrorSetType, run_ctx, Body) or the legacy runtime/lexical_state form"),
        }
    } catch |err| return @errorCast(err);
    if (DescriptorType.Output != void) {
        @field(state.lexical_state.outputs_ptr.*, field.name) = result.output;
    }
    return result.value;
}

pub fn continueChoice(
    comptime HandlersType: type,
    comptime index: usize,
    frame: anytype,
    comptime Continuation: anytype,
    resume_value: anytype,
) lowered_machine.ResetError(HandlerErrorSet(HandlersType) || ChoiceErrorSet(Continuation, @TypeOf(resume_value), ContinuationEffType(HandlersType, index, @TypeOf(frame.previous_eff), @TypeOf(frame.current_handle))))!ChoiceAnswerTypeFor(Continuation, @TypeOf(resume_value), ContinuationEffType(HandlersType, index, @TypeOf(frame.previous_eff), @TypeOf(frame.current_handle))) {
    const caller = @TypeOf(frame).caller_source;
    const field = @typeInfo(HandlersType).@"struct".fields[index];
    const current_eff = extendBundle(@TypeOf(frame.previous_eff), frame.previous_eff, field.name, frame.current_handle);
    const choice_spec = ChoiceChainSpec(HandlersType, index + 1, @TypeOf(current_eff), caller, @TypeOf(resume_value), Continuation);
    return try runChoiceChain(choice_spec, .{
        .resume_value = resume_value,
        .lexical_state = .{
            .runtime = frame.runtime,
            .handlers_ptr = frame.handlers_ptr,
            .eff_value = current_eff,
            .outputs_ptr = frame.outputs_ptr,
        },
    });
}
