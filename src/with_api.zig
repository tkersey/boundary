const anonymous_body_synthesis = @import("internal/anonymous_body_synthesis.zig");
const builtin = @import("builtin");
const family = @import("effect/family.zig");
const frontend = @import("frontend_support");
const lexical_manifest = @import("internal/lexical_manifest.zig");
const lowered_machine = @import("lowered_machine");
const lowering_api = @import("lowering_api");
const prompt_contract = @import("prompt_contract_support");
const source_graph_embed = @import("source_graph_embed");
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

/// Canonical lexical outputs plus body answer returned from `shift.with(...)`.
pub fn WithResult(comptime HandlersType: type, comptime Answer: type) type {
    return struct {
        outputs: OutputBundleType(HandlersType),
        value: Answer,
    };
}

/// Explicit lexical rebinding packet threaded through lexical continuations.
pub fn LexicalState(comptime HandlersType: type, comptime EffType: type, comptime caller_source_value: anytype) type {
    return struct {
        /// Original caller source location threaded through this lexical rebinding packet.
        pub const caller_source = caller_source_value;
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
    var field_names = [_][:0]const u8{""} ** handler_fields.len;
    var field_types = [_]type{void} ** handler_fields.len;
    var field_attrs = [_]std.builtin.Type.StructField.Attributes{.{}} ** handler_fields.len;
    var field_count: usize = 0;
    inline for (handler_fields) |field| {
        comptime assertClosedFinishShape(field.type);
        const OutputType = ClosedOutputType(field.type);
        if (OutputType == void) continue;
        field_names[field_count] = field.name;
        field_types[field_count] = OutputType;
        field_attrs[field_count] = .{ .@"align" = @alignOf(OutputType) };
        field_count += 1;
    }
    return @Struct(.auto, null, field_names[0..field_count], field_types[0..field_count], field_attrs[0..field_count]);
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

fn bodyDeclSemanticErrorSet(comptime Body: type) ?type {
    if (hasDeclSafe(Body, "SemanticErrorSet")) return Body.SemanticErrorSet;
    return null;
}

fn bodyDeclSourcePath(comptime Body: type) ?[]const u8 {
    if (hasDeclSafe(Body, "source_path")) return Body.source_path;
    return null;
}

fn bodyDeclBodySymbol(comptime Body: type) ?[]const u8 {
    if (hasDeclSafe(Body, "body_symbol")) return Body.body_symbol;
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

fn callBody(comptime Body: type, eff: anytype) BodyReturnType(Body, @TypeOf(eff)) {
    if (@hasDecl(Body, "body")) return Body.body(eff);
    if (@hasDecl(Body, "run")) {
        const params = @typeInfo(BodyRunFnType(Body)).@"fn".params;
        if (params.len == 1) return Body.run(eff);
        const FirstParam = params[0].type orelse @compileError("shift.with body run must type every parameter");
        if (FirstParam == type) return Body.run(Body, eff);
        if (FirstParam == Body) return Body.run(bodyRunSelfValue(Body), eff);
        if (FirstParam == *Body or FirstParam == *const Body) {
            var self = bodyRunSelfValue(Body);
            return Body.run(&self, eff);
        }
        @compileError("shift.with body run must accept either (eff), (self, eff), (*self, eff), or (BodyType, eff)");
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
    if (pointer.size == .slice) {
        return blk: {
            const base = std.mem.alignForward(usize, 1, @alignOf(Child));
            if (pointer.sentinel_ptr) |sentinel_ptr| {
                const sentinel = @as(*const Child, @ptrCast(@alignCast(sentinel_ptr))).*;
                const many = @as([*:sentinel]Child, @ptrFromInt(base));
                const slice = many[0..0];
                if (pointer.is_const) break :blk @as(PtrType, slice);
                break :blk @as(PtrType, @constCast(slice));
            }
            const many = @as([*]Child, @ptrFromInt(base));
            const slice = many[0..1];
            if (pointer.is_const) break :blk @as(PtrType, slice);
            break :blk @as(PtrType, @constCast(slice));
        };
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

fn exactContextCallerSource(comptime ContextPtrType: type) @TypeOf(family.contextCallerSource(ContextPtrType)) {
    return family.contextCallerSource(ContextPtrType);
}

fn ChoiceRunState(comptime HandlersType: type, comptime EffType: type, comptime caller: anytype) type {
    return LexicalState(HandlersType, EffType, caller);
}

fn descriptorRunContext(
    comptime caller: anytype,
    runtime: *lowered_machine.Runtime,
    lexical_state: anytype,
) struct {
    /// Caller-owned source location for this descriptor run context.
    pub const caller_source = caller;
    runtime: *lowered_machine.Runtime,
    lexical_state: @TypeOf(lexical_state),
} {
    return .{
        .runtime = runtime,
        .lexical_state = lexical_state,
    };
}

/// Recover the active lexical rebinding packet from the exact context capability.
pub fn activeLexicalState(
    ctx: anytype,
    comptime HandlersType: type,
    comptime EffType: type,
) *LexicalState(HandlersType, EffType, exactContextCallerSource(@TypeOf(ctx))) {
    return @ptrCast(@alignCast(ctx._cap.lexical_state.?));
}

fn runChoiceChain(
    comptime HandlersType: type,
    comptime index: usize,
    comptime EffType: type,
    comptime caller: anytype,
    state: ChoiceRunState(HandlersType, EffType, caller),
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
            return try runChoiceChain(HandlersType, index + 1, @TypeOf(next_eff), caller, .{
                .runtime = lexical_state.runtime,
                .handlers_ptr = lexical_state.handlers_ptr,
                .eff_value = next_eff,
                .outputs_ptr = lexical_state.outputs_ptr,
            }, Continuation, resume_value);
        }
    };

    const result = blk: {
        const RunFn = @TypeOf(DescriptorType.run);
        const params = @typeInfo(RunFn).@"fn".params;
        switch (params.len) {
            5 => break :blk desc_value.run(ChoiceAnswerTypeFor(Continuation, @TypeOf(resume_value), EffType), ErrorSet, descriptorRunContext(caller, state.runtime, &state), step_ctx),
            6 => break :blk desc_value.run(ChoiceAnswerTypeFor(Continuation, @TypeOf(resume_value), EffType), ErrorSet, state.runtime, &state, step_ctx),
            else => @compileError("shift.with descriptor run must accept either (self, AnswerType, RunErrorSetType, run_ctx, Body) or the legacy runtime/lexical_state form"),
        }
    } catch |err| return @errorCast(err);
    if (DescriptorType.Output != void) {
        @field(state.outputs_ptr.*, field.name) = result.output;
    }
    return result.value;
}

fn runBodyChain(
    comptime HandlersType: type,
    comptime index: usize,
    comptime EffType: type,
    comptime caller: anytype,
    state: ChoiceRunState(HandlersType, EffType, caller),
    comptime Body: type,
) lowered_machine.ResetError(HandlerErrorSet(HandlersType) || BodyErrorSet(Body, PreviewBodyEffType(HandlersType)))!BodyAnswerType(Body, PreviewBodyEffType(HandlersType)) {
    const ErrorSet = HandlerErrorSet(HandlersType) || BodyErrorSet(Body, PreviewBodyEffType(HandlersType));
    const AnswerType = BodyAnswerType(Body, PreviewBodyEffType(HandlersType));
    const fields = @typeInfo(HandlersType).@"struct".fields;

    if (index == fields.len) {
        const ReturnType = BodyReturnType(Body, EffType);
        if (@typeInfo(ReturnType) == .error_union) {
            return callBody(Body, state.eff_value) catch |err| return @errorCast(err);
        }
        return callBody(Body, state.eff_value);
    }

    const field = fields[index];
    const DescriptorType = field.type;
    const desc_value: DescriptorType = @field(state.handlers_ptr.*, field.name);

    const step_ctx = struct {
        /// Extend the lexical bundle for the initial body entry and continue inward.
        pub fn body(comptime Cap: type, ctx: anytype) lowered_machine.ResetError(ErrorSet)!AnswerType {
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
            return try runBodyChain(HandlersType, index + 1, @TypeOf(next_eff), caller, .{
                .runtime = lexical_state.runtime,
                .handlers_ptr = lexical_state.handlers_ptr,
                .eff_value = next_eff,
                .outputs_ptr = lexical_state.outputs_ptr,
            }, Body);
        }
    };

    const result = blk: {
        const RunFn = @TypeOf(DescriptorType.run);
        const params = @typeInfo(RunFn).@"fn".params;
        switch (params.len) {
            5 => break :blk desc_value.run(AnswerType, ErrorSet, descriptorRunContext(caller, state.runtime, &state), step_ctx),
            6 => break :blk desc_value.run(AnswerType, ErrorSet, state.runtime, &state, step_ctx),
            else => @compileError("shift.with descriptor run must accept either (self, AnswerType, RunErrorSetType, run_ctx, Body) or the legacy runtime/lexical_state form"),
        }
    } catch |err| return @errorCast(err);
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
    const caller = @TypeOf(frame).caller_source;
    const field = @typeInfo(HandlersType).@"struct".fields[index];
    const current_eff = extendBundle(@TypeOf(frame.previous_eff), frame.previous_eff, field.name, frame.current_handle);
    return try runChoiceChain(HandlersType, index + 1, @TypeOf(current_eff), caller, .{
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
    if (bodyDeclSemanticErrorSet(Body)) |BodySet| return HandlerSet || BodySet;
    const PreviewEff = PreviewBodyEffType(HandlersType);
    const BodySet = BodyErrorSet(Body, PreviewEff);
    return HandlerSet || BodySet;
}

fn syntheticLoweringSourcePath(
    comptime entry_symbol: []const u8,
) []const u8 {
    return std.fmt.comptimePrint("/tmp/shift_with/{s}.zig", .{entry_symbol});
}

fn syntheticSourceLocation(
    comptime synthetic_path: []const u8,
    comptime entry_symbol: []const u8,
) std.builtin.SourceLocation {
    const source_path_z = std.fmt.comptimePrint("{s}\x00", .{synthetic_path});
    const entry_symbol_z = std.fmt.comptimePrint("{s}\x00", .{entry_symbol});
    return .{
        .module = @src().module,
        .file = source_path_z[0..synthetic_path.len :0],
        .line = 1,
        .column = 1,
        .fn_name = entry_symbol_z[0..entry_symbol.len :0],
    };
}

fn namedBodySyntheticSource(
    comptime body_symbol: []const u8,
    comptime caller_source: []const u8,
    comptime generated_entry_name: []const u8,
    comptime return_syntax: ?[]const u8,
) [:0]const u8 {
    const normalized_caller_source = comptime anonymous_body_synthesis.normalizedSyntheticCallerSource(caller_source);
    const return_clause = if (return_syntax) |syntax|
        std.fmt.comptimePrint(" {s} ", .{syntax})
    else
        " ";
    return std.fmt.comptimePrint(
        "{s}\npub fn {s}(eff: anytype){s}{{\n    return {s}(eff);\n}}\n",
        .{
            normalized_caller_source,
            generated_entry_name,
            return_clause,
            body_symbol,
        },
    );
}

fn NestedSourceModuleForBody(comptime Body: type) type {
    return Body;
}

// zlinter-disable max_positional_args - compiled execution must carry exact body, runtime, handler, output, and plan witnesses across a comptime boundary.
fn runCompiledLexicalPlan(
    comptime HandlersType: type,
    comptime Body: type,
    runtime: *lowered_machine.Runtime,
    handlers_ptr: *HandlersType,
    outputs_ptr: *OutputBundleType(HandlersType),
    comptime compiled_plan: lowering_api.ProgramPlan,
) lowered_machine.ResetError(HandlerErrorSet(HandlersType) || BodyErrorSet(Body, PreviewBodyEffType(HandlersType)))!BodyAnswerType(Body, PreviewBodyEffType(HandlersType)) {
    if (builtin.is_test) compiled_plain_with_witness = true;
    lowering_api.assertExecutablePlanCodecSupport(compiled_plan);

    const lexical_state = struct {
        runtime: *lowered_machine.Runtime,
        handlers_ptr: *HandlersType,
    }{
        .runtime = runtime,
        .handlers_ptr = handlers_ptr,
    };

    var executable_bundle = lexical_manifest.Manifest(HandlersType).fromLexicalState(lexical_state);
    var run_error: ?lowered_machine.ResetError(HandlerErrorSet(HandlersType) || BodyErrorSet(Body, PreviewBodyEffType(HandlersType))) = null;
    const result = lowering_api.runExecutablePlanInSource(
        runtime,
        compiled_plan,
        NestedSourceModuleForBody(Body),
        &executable_bundle,
    ) catch |err| blk: {
        run_error = @errorCast(err);
        break :blk null;
    };

    var cleanup_error: ?lowered_machine.ResetError(HandlerErrorSet(HandlersType) || BodyErrorSet(Body, PreviewBodyEffType(HandlersType))) = null;
    lexical_manifest.Manifest(HandlersType).deinitBundle(&executable_bundle) catch |err| {
        cleanup_error = @errorCast(err);
    };

    if (run_error) |err| return err;
    if (cleanup_error) |err| return err;

    inline for (std.meta.fields(OutputBundleType(HandlersType))) |field| {
        if (@hasField(@TypeOf(result.?.outputs), field.name)) {
            @field(outputs_ptr.*, field.name) = @field(result.?.outputs, field.name);
        }
    }
    return result.?.value;
}

threadlocal var compiled_plain_with_witness = false;

fn runInterpretedLexicalWith(
    comptime HandlersType: type,
    comptime Body: type,
    runtime: *lowered_machine.Runtime,
    handlers_ptr: *HandlersType,
    outputs_ptr: *OutputBundleType(HandlersType),
) lowered_machine.ResetError(HandlerErrorSet(HandlersType) || BodyErrorSet(Body, PreviewBodyEffType(HandlersType)))!BodyAnswerType(Body, PreviewBodyEffType(HandlersType)) {
    return try runBodyChain(HandlersType, 0, struct {}, null, .{
        .runtime = runtime,
        .handlers_ptr = handlers_ptr,
        .eff_value = .{},
        .outputs_ptr = outputs_ptr,
    }, Body);
}

fn compiledBodyReturnSyntax(comptime HandlersType: type, comptime Body: type) ?[]const u8 {
    return anonymous_body_synthesis.canonicalReturnTypeSyntax(BodyReturnType(Body, PreviewBodyEffType(HandlersType)));
}

fn failRepoOwnedAnonymousSource(comptime Body: type) noreturn {
    @compileError(std.fmt.comptimePrint(
        "shift.with repo-owned anonymous body requires a unique synthetic source before compiled execution: body={s}",
        .{@typeName(Body)},
    ));
}

// zlinter-disable max_positional_args - caller-owned synthesis needs the exact caller source plus the same runtime state bundle as repo-owned compilation.
fn tryCallerOwnedAnonymousCompiledWith(
    comptime caller: std.builtin.SourceLocation,
    comptime caller_source: []const u8,
    comptime HandlersType: type,
    comptime Body: type,
    runtime: *lowered_machine.Runtime,
    handlers_ptr: *HandlersType,
    outputs_ptr: *OutputBundleType(HandlersType),
) ?lowered_machine.ResetError(HandlerErrorSet(HandlersType) || BodyErrorSet(Body, PreviewBodyEffType(HandlersType)))!BodyAnswerType(Body, PreviewBodyEffType(HandlersType)) {
    const entry_symbol = comptime anonymous_body_synthesis.callerEntryName(caller);
    const return_syntax = comptime compiledBodyReturnSyntax(HandlersType, Body);
    const maybe_synthetic = comptime anonymous_body_synthesis.syntheticSourceWithEntry(
        caller,
        Body,
        caller_source,
        .explicit_location,
        entry_symbol,
        return_syntax,
    );
    const synthetic = maybe_synthetic orelse @compileError(std.fmt.comptimePrint(
        "shift.with caller-owned syntheticSourceWithEntry failed: file={s} line={d} column={d} source_hash={d}",
        .{
            caller.file,
            caller.line,
            caller.column,
            std.hash.Wyhash.hash(0, caller_source),
        },
    ));
    const synthetic_path = comptime syntheticLoweringSourcePath(entry_symbol);
    const source_ref = comptime lowering_api.sourceWithContent(
        synthetic_path,
        syntheticSourceLocation(synthetic_path, entry_symbol),
        synthetic,
    );
    if (comptime anonymous_body_synthesis.maybeLowerSyntheticLexicalBody(
        HandlersType,
        BodyAnswerType(Body, PreviewBodyEffType(HandlersType)),
        synthetic_path,
        synthetic,
        entry_symbol,
    ) == null) {
        return null;
    }
    const lowered_program = comptime lowering_api.lower(
        source_ref,
        .{
            .label = "shift.with caller-owned lexical body",
            .entry_symbol = entry_symbol,
            .ValueType = BodyAnswerType(Body, PreviewBodyEffType(HandlersType)),
            .row = lexical_manifest.Manifest(HandlersType).row(),
            .outputs = lexical_manifest.Manifest(HandlersType).outputs(),
        },
    ).runtime_plan;
    return try runCompiledLexicalPlan(
        HandlersType,
        Body,
        runtime,
        handlers_ptr,
        outputs_ptr,
        lowered_program,
    );
}

fn tryRepoOwnedAnonymousCompiledWith(
    comptime HandlersType: type,
    comptime Body: type,
    runtime: *lowered_machine.Runtime,
    handlers_ptr: *HandlersType,
    outputs_ptr: *OutputBundleType(HandlersType),
) lowered_machine.ResetError(HandlerErrorSet(HandlersType) || BodyErrorSet(Body, PreviewBodyEffType(HandlersType)))!BodyAnswerType(Body, PreviewBodyEffType(HandlersType)) {
    const maybe_override = comptime anonymous_body_synthesis.uniqueRepoOwnedAnonymousSourceWithReturnSyntax(
        Body,
        .plain_with,
        compiledBodyReturnSyntax(HandlersType, Body),
    );
    const maybe_fallback = comptime anonymous_body_synthesis.uniqueRepoOwnedAnonymousSource(Body, .plain_with);
    const synthesized = if (maybe_override) |synthesized|
        synthesized
    else if (maybe_fallback) |fallback|
        fallback
    else
        failRepoOwnedAnonymousSource(Body);
    const synthetic_path = comptime syntheticLoweringSourcePath(synthesized.entry_symbol);
    const source_ref = comptime lowering_api.sourceWithContent(
        synthetic_path,
        syntheticSourceLocation(synthetic_path, synthesized.entry_symbol),
        synthesized.source,
    );
    if (comptime anonymous_body_synthesis.maybeLowerSyntheticLexicalBody(
        HandlersType,
        BodyAnswerType(Body, PreviewBodyEffType(HandlersType)),
        synthetic_path,
        synthesized.source,
        synthesized.entry_symbol,
    ) == null) {
        @compileError(std.fmt.comptimePrint(
            "shift.with repo-owned anonymous body must lower to ProgramPlan: source={s} entry={s}",
            .{ synthesized.source_path, synthesized.entry_symbol },
        ));
    }
    const lowered_program = comptime lowering_api.lower(
        source_ref,
        .{
            .label = "shift.with repo-owned lexical body",
            .entry_symbol = synthesized.entry_symbol,
            .ValueType = BodyAnswerType(Body, PreviewBodyEffType(HandlersType)),
            .row = lexical_manifest.Manifest(HandlersType).row(),
            .outputs = lexical_manifest.Manifest(HandlersType).outputs(),
        },
    ).runtime_plan;
    return try runCompiledLexicalPlan(
        HandlersType,
        Body,
        runtime,
        handlers_ptr,
        outputs_ptr,
        lowered_program,
    );
}

fn tryRepoOwnedNamedCompiledWith(
    comptime HandlersType: type,
    comptime Body: type,
    runtime: *lowered_machine.Runtime,
    handlers_ptr: *HandlersType,
    outputs_ptr: *OutputBundleType(HandlersType),
) lowered_machine.ResetError(HandlerErrorSet(HandlersType) || BodyErrorSet(Body, PreviewBodyEffType(HandlersType)))!BodyAnswerType(Body, PreviewBodyEffType(HandlersType)) {
    const source_path = comptime bodyDeclSourcePath(Body) orelse
        @compileError("shift.with named-body lowering requires Body.source_path");
    const body_symbol = comptime bodyDeclBodySymbol(Body) orelse
        @compileError("shift.with named-body lowering requires Body.body_symbol");
    const entry_symbol = comptime std.fmt.comptimePrint("__shift_with_named_{s}", .{body_symbol});
    const caller_source = comptime @import("source_graph_embed").embeddedSource(source_path);
    const synthetic_source = comptime namedBodySyntheticSource(
        body_symbol,
        caller_source,
        entry_symbol,
        compiledBodyReturnSyntax(HandlersType, Body),
    );
    const synthetic_path = comptime syntheticLoweringSourcePath(entry_symbol);
    const source_ref = comptime lowering_api.sourceWithContent(
        synthetic_path,
        syntheticSourceLocation(synthetic_path, entry_symbol),
        synthetic_source,
    );
    if (comptime anonymous_body_synthesis.maybeLowerSyntheticLexicalBody(
        HandlersType,
        BodyAnswerType(Body, PreviewBodyEffType(HandlersType)),
        synthetic_path,
        synthetic_source,
        entry_symbol,
    ) == null) {
        @compileError(std.fmt.comptimePrint(
            "shift.with repo-owned named body must lower to ProgramPlan: source={s} entry={s}",
            .{ source_path, entry_symbol },
        ));
    }
    const lowered_program = comptime lowering_api.lower(
        source_ref,
        .{
            .label = "shift.with repo-owned named body",
            .entry_symbol = entry_symbol,
            .ValueType = BodyAnswerType(Body, PreviewBodyEffType(HandlersType)),
            .row = lexical_manifest.Manifest(HandlersType).row(),
            .outputs = lexical_manifest.Manifest(HandlersType).outputs(),
        },
    ).runtime_plan;
    return try runCompiledLexicalPlan(
        HandlersType,
        Body,
        runtime,
        handlers_ptr,
        outputs_ptr,
        lowered_program,
    );
}

fn supportsNamedBodyLowering(comptime Body: type) bool {
    return comptime bodyDeclSourcePath(Body) != null and bodyDeclBodySymbol(Body) != null;
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
fn withImpl(
    runtime: *lowered_machine.Runtime,
    handlers: anytype,
    comptime Body: type,
) WithFnReturnType(@TypeOf(handlers), Body) {
    const HandlersType = @TypeOf(handlers);
    comptime assertHandlerBundleShape(HandlersType);

    var handler_state = handlers;
    var outputs = std.mem.zeroInit(OutputBundleType(HandlersType), .{});
    const compiled = if (comptime supportsNamedBodyLowering(Body))
        tryRepoOwnedNamedCompiledWith(HandlersType, Body, runtime, &handler_state, &outputs)
    else if (comptime anonymous_body_synthesis.hasRepoOwnedCandidate(Body))
        tryRepoOwnedAnonymousCompiledWith(HandlersType, Body, runtime, &handler_state, &outputs)
    else
        runInterpretedLexicalWith(HandlersType, Body, runtime, &handler_state, &outputs);
    const value = try compiled;
    return .{
        .outputs = outputs,
        .value = value,
    };
}

/// Run one lexical effect bundle and return descriptor outputs alongside the body answer.
pub fn with(
    runtime: *lowered_machine.Runtime,
    handlers: anytype,
    comptime Body: type,
) WithFnReturnType(@TypeOf(handlers), Body) {
    return withImpl(runtime, handlers, Body);
}

/// Run one lexical effect bundle using explicit caller provenance and source bytes.
pub fn withCallerSource(
    comptime caller: std.builtin.SourceLocation,
    comptime caller_source: []const u8,
    runtime: *lowered_machine.Runtime,
    handlers: anytype,
    comptime Body: type,
) WithFnReturnType(@TypeOf(handlers), Body) {
    const HandlersType = @TypeOf(handlers);
    comptime assertHandlerBundleShape(HandlersType);

    var handler_state = handlers;
    var outputs = std.mem.zeroInit(OutputBundleType(HandlersType), .{});
    const compiled = tryCallerOwnedAnonymousCompiledWith(caller, caller_source, HandlersType, Body, runtime, &handler_state, &outputs) orelse
        @compileError("shift.with caller-owned anonymous body did not lower to ProgramPlan");
    const value = try compiled;
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

test "plain repo-owned shift.with uses the compiled lexical fast path when the body is unique" {
    const state = @import("effect/state.zig");

    compiled_plain_with_witness = false;
    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try with(&runtime, .{
        .state = state.use(@as(i32, 5)),
    }, struct {
        /// Drive one unique repo-owned plain lexical body through the compiled fast path witness.
        pub fn body(eff: anytype) anyerror!i32 {
            const before = try eff.state.get();
            try eff.state.set(before + 1);
            return try eff.state.get();
        }
    });

    try std.testing.expect(compiled_plain_with_witness);
    try std.testing.expectEqual(@as(i32, 6), result.value);
    try std.testing.expectEqual(@as(i32, 6), result.outputs.state);
}

test "with_api module can lower the actual lexical_with_test synthetic packet through the shared helper" {
    const shift = @import("shift");
    const source = source_graph_embed.embeddedSource("test/lexical_with_test.zig");
    const test_block = comptime anonymous_body_synthesis.testBlockBounds(source, "shift.with accepts body run(self, eff)").?;
    const bounds = comptime anonymous_body_synthesis.uniqueBodyExpressionBoundsInRange(
        source,
        test_block.start,
        test_block.end,
        .plain_with,
    ).?;
    const body_type = struct {
        /// Keep the actual lexical_with_test witness body shape available to this module test.
        pub fn run(self: @This(), eff: anytype) anyerror!i32 {
            _ = self;
            return try eff.state.get();
        }
    };
    const entry_symbol = "__shift_with_entry_36363";
    const synthetic_path = "/tmp/shift_with/__shift_with_entry_36363.zig";
    const synthetic = comptime anonymous_body_synthesis.syntheticSourceForExpr(
        body_type,
        source[bounds.start..bounds.end],
        source,
        entry_symbol,
        null,
    ).?;
    const Handlers = @TypeOf(.{
        .state = shift.effect.state.use(@as(i32, 11)),
    });

    try std.testing.expect(anonymous_body_synthesis.maybeLowerSyntheticLexicalBody(
        Handlers,
        i32,
        synthetic_path,
        synthetic,
        entry_symbol,
    ) != null);
}
