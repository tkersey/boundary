const anonymous_body_synthesis = @import("internal/anonymous_body_synthesis.zig");
const builtin = @import("builtin");
const family = @import("effect/family.zig");
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

/// Canonical lexical outputs plus body answer returned from `ability.with(...)`.
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
    if (info != .@"struct") @compileError("ability.with handlers must be a struct literal or struct value");
    if (info.@"struct".fields.len == 0) @compileError("ability.with handlers must declare at least one binding");
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

fn ExplicitProgramContinuationReturnTypeWithContext(
    comptime ContextPtrType: type,
    comptime Continuation: type,
    comptime ResumeType: type,
) type {
    return @TypeOf(Continuation.apply(dummyValue(ContextPtrType), dummyValue(ResumeType)));
}

fn ExplicitProgramContinuationAnswerTypeWithContext(
    comptime ContextPtrType: type,
    comptime Continuation: type,
    comptime ResumeType: type,
) type {
    const ReturnType = ExplicitProgramContinuationReturnTypeWithContext(ContextPtrType, Continuation, ResumeType);
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.payload,
        else => ReturnType,
    };
}

fn ExplicitProgramContinuationErrorSetWithContext(
    comptime ContextPtrType: type,
    comptime Continuation: type,
    comptime ResumeType: type,
) type {
    return ReturnTypeErrorSet(ExplicitProgramContinuationReturnTypeWithContext(ContextPtrType, Continuation, ResumeType));
}

fn PreviewCompiledProgram(
    comptime Op: type,
    comptime Continuation: anytype,
    comptime ErrorSet: type,
) type {
    const PromptType = prompt_contract.Prompt(
        Op.mode,
        Op.Resume,
        ExplicitProgramContinuationAnswerType(Continuation, Op.Resume),
        ErrorSet || ExplicitProgramContinuationErrorSet(Continuation, Op.Resume),
    );
    return struct {
        /// Preview witness that mirrors runtime authored carriers during type inference.
        pub const has_compiled_plan = true;
        prompt: *const PromptType,

        /// Type-only preview of compiled authored execution.
        pub fn runCompiled(_: @This(), _: *lowered_machine.Runtime) lowered_machine.ResetError(ErrorSet || ExplicitProgramContinuationErrorSet(Continuation, Op.Resume))!ExplicitProgramContinuationAnswerType(Continuation, Op.Resume) {
            unreachable;
        }
    };
}

fn PreviewCompiledProgramWithContext(
    comptime Op: type,
    comptime ContextPtrType: type,
    comptime Continuation: type,
    comptime ErrorSet: type,
) type {
    const PromptType = prompt_contract.Prompt(
        Op.mode,
        Op.Resume,
        ExplicitProgramContinuationAnswerTypeWithContext(ContextPtrType, Continuation, Op.Resume),
        ErrorSet || ExplicitProgramContinuationErrorSetWithContext(ContextPtrType, Continuation, Op.Resume),
    );
    return struct {
        /// Preview witness that mirrors runtime authored carriers during contextual type inference.
        pub const has_compiled_plan = true;
        prompt: *const PromptType,

        /// Type-only preview of compiled contextual authored execution.
        pub fn runCompiled(_: @This(), _: *lowered_machine.Runtime) lowered_machine.ResetError(ErrorSet || ExplicitProgramContinuationErrorSetWithContext(ContextPtrType, Continuation, Op.Resume))!ExplicitProgramContinuationAnswerTypeWithContext(ContextPtrType, Continuation, Op.Resume) {
            unreachable;
        }
    };
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
        ) PreviewCompiledProgram(Op, Continuation, ErrorSet) {
            unreachable;
        }

        /// Build this public explicit program with one runtime continuation context.
        pub fn performProgramWithContext(
            _: *@This(),
            comptime Op: type,
            _: Op.Payload,
            continuation_ctx: anytype,
            comptime Continuation: type,
        ) PreviewCompiledProgramWithContext(Op, @TypeOf(continuation_ctx), Continuation, ErrorSet) {
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
        else => @compileError("ability.with descriptor HandleType must accept either (Cap, ContextPtrType) or (Cap, ContextPtrType, HandlersType, PreviousEffType, index)"),
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

fn bodyDeclSource(comptime Body: type) ?[]const u8 {
    if (hasDeclSafe(Body, "source")) return Body.source;
    return null;
}

fn bodyDeclSourceHash(comptime Body: type) ?u64 {
    if (hasDeclSafe(Body, "source_hash")) return Body.source_hash;
    return null;
}

fn bodyDeclSourceIdentity(comptime Body: type) ?[]const u8 {
    if (hasDeclSafe(Body, "source_identity")) return Body.source_identity;
    return null;
}

fn bodyDeclSourceFile(comptime Body: type) ?[]const u8 {
    if (hasDeclSafe(Body, "source_file")) return Body.source_file;
    return null;
}

fn bodyDeclSourceLocation(comptime Body: type) ?std.builtin.SourceLocation {
    if (hasDeclSafe(Body, "source_location")) return Body.source_location;
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
        .pointer => |pointer| if (@typeInfo(pointer.child) == .@"fn") pointer.child else @compileError("ability.with body run must be callable"),
        .@"fn" => RunFn,
        else => @compileError("ability.with body run must be callable"),
    };
}

fn bodyRunSelfValue(comptime Body: type) Body {
    if (@sizeOf(Body) != 0) {
        @compileError("ability.with body run(self, eff) requires a zero-sized body type; use run(eff) for stateful bodies");
    }
    return .{};
}

fn BodyReturnType(comptime Body: type, comptime EffType: type) type {
    if (@hasDecl(Body, "body")) return @TypeOf(Body.body(dummyValue(EffType)));
    if (@hasDecl(Body, "run")) {
        const params = @typeInfo(BodyRunFnType(Body)).@"fn".params;
        if (params.len == 1) return @TypeOf(Body.run(dummyValue(EffType)));
        if (params.len == 2) {
            const FirstParam = params[0].type orelse @compileError("ability.with body run must type every parameter");
            if (FirstParam == type) return @TypeOf(Body.run(Body, dummyValue(EffType)));
            if (FirstParam == Body) return @TypeOf(Body.run(bodyRunSelfValue(Body), dummyValue(EffType)));
            if (FirstParam == *Body or FirstParam == *const Body) {
                var self = bodyRunSelfValue(Body);
                return @TypeOf(Body.run(&self, dummyValue(EffType)));
            }
        }
        @compileError("ability.with body run must accept either (eff), (self, eff), (*self, eff), or (BodyType, eff)");
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

fn ChoiceRunState(
    comptime HandlersType: type,
    comptime EffType: type,
    comptime caller_source_value: anytype,
    comptime ResumeType: type,
) type {
    return struct {
        /// Original caller source location threaded through this lexical choice packet.
        pub const caller_source = caller_source_value;
        resume_value: ResumeType,
        lexical_state: LexicalState(HandlersType, EffType, caller_source_value),
    };
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

fn activeChoiceState(
    ctx: anytype,
    comptime HandlersType: type,
    comptime EffType: type,
    comptime ResumeType: type,
) *ChoiceRunState(HandlersType, EffType, exactContextCallerSource(@TypeOf(ctx)), ResumeType) {
    // Choice descriptor contexts expose the embedded lexical packet; recover the
    // enclosing choice packet by field ownership instead of by prefix layout.
    const lexical_state = activeLexicalState(ctx, HandlersType, EffType);
    return @fieldParentPtr("lexical_state", lexical_state);
}

test "choice continuation state recovers from explicit lexical state field" {
    const Descriptor = struct {
        /// No output is needed for this local state-recovery fixture.
        pub const Output = void;
        marker: void = {},
    };
    const Handlers = struct {
        descriptor: Descriptor,
    };
    const Eff = struct {
        value: i32,
    };
    const Cap = struct {
        /// Match the no-provenance lexical state used by this fixture.
        pub const caller_source = null;
        lexical_state: ?*anyopaque = null,
    };
    const Context = family.Context(Cap, i32, i32, error{});
    const ChoiceState = ChoiceRunState(Handlers, Eff, null, i32);

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var handlers: Handlers = .{ .descriptor = .{} };
    var outputs: OutputBundleType(Handlers) = .{};
    var choice_state: ChoiceState = .{
        .resume_value = 41,
        .lexical_state = .{
            .runtime = &runtime,
            .handlers_ptr = &handlers,
            .eff_value = .{ .value = 7 },
            .outputs_ptr = &outputs,
        },
    };
    var cap: Cap = .{ .lexical_state = &choice_state.lexical_state };
    var ctx: Context = .{ ._cap = &cap };

    try std.testing.expect(activeLexicalState(&ctx, Handlers, Eff) == &choice_state.lexical_state);
    try std.testing.expect(activeChoiceState(&ctx, Handlers, Eff, i32) == &choice_state);
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
        /// Extend the lexical bundle during choice continuation re-entry and continue inward.
        pub fn body(comptime Cap: type, ctx: anytype) lowered_machine.ResetError(Spec.ErrorSet)!Spec.AnswerType {
            const choice_state = activeChoiceState(ctx, Spec.handlers_type, Spec.eff_type, Spec.resume_type);
            const current_desc: DescriptorType = @field(choice_state.lexical_state.handlers_ptr.*, field.name);
            const handle = blk: {
                const BindFn = @TypeOf(DescriptorType.bindLexical);
                const params = @typeInfo(BindFn).@"fn".params;
                switch (params.len) {
                    3 => break :blk current_desc.bindLexical(Cap, ctx),
                    6 => break :blk current_desc.bindLexical(Cap, ctx, Spec.handlers_type, Spec.eff_type, Spec.index),
                    else => @compileError("ability.with descriptor bindLexical must accept either (self, Cap, ctx) or (self, Cap, ctx, HandlersType, PreviousEffType, index)"),
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
            else => @compileError("ability.with descriptor run must accept either (self, AnswerType, RunErrorSetType, run_ctx, Body) or the legacy runtime/lexical_state form"),
        }
    } catch |err| return @errorCast(err);
    if (DescriptorType.Output != void) {
        @field(state.lexical_state.outputs_ptr.*, field.name) = result.output;
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

/// Return type for one lexical `ability.with(...)` instantiation.
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
    return std.fmt.comptimePrint("/tmp/ability_with/{s}.zig", .{entry_symbol});
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

fn CompiledLexicalProgram(
    comptime HandlersType: type,
    comptime Body: type,
    comptime source_ref: anytype,
    comptime label: []const u8,
    comptime entry_symbol: []const u8,
) type {
    comptime {
        @setEvalBranchQuota(10_000_000);
    }
    const raw_compiled_plan = comptime lowering_api.lower(
        source_ref,
        .{
            .label = label,
            .entry_symbol = entry_symbol,
            .ValueType = BodyAnswerType(Body, PreviewBodyEffType(HandlersType)),
            .row = lexical_manifest.Manifest(HandlersType).row(),
            .outputs = lexical_manifest.Manifest(HandlersType).outputs(),
        },
    ).runtime_plan;
    const compiled_plan = comptime lexical_manifest.Manifest(HandlersType).enrichPlan(raw_compiled_plan);
    comptime {
        lowering_api.assertExecutablePlanCodecSupport(compiled_plan);
    }
    const program_type = struct {
        fn run(
            runtime: *lowered_machine.Runtime,
            handlers_ptr: *HandlersType,
            outputs_ptr: *OutputBundleType(HandlersType),
        ) lowered_machine.ResetError(HandlerErrorSet(HandlersType) || BodyErrorSet(Body, PreviewBodyEffType(HandlersType)))!BodyAnswerType(Body, PreviewBodyEffType(HandlersType)) {
            if (builtin.is_test) compiled_token_witness = true;

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
    };
    comptime assertCompiledLexicalProgramHasNoStoredFields(program_type);
    return program_type;
}

fn assertCompiledLexicalProgramHasNoStoredFields(comptime Program: type) void {
    const info = @typeInfo(Program);
    if (info != .@"struct") {
        @compileError("compiled lexical program token must be a private struct namespace");
    }
    if (info.@"struct".fields.len != 0) {
        @compileError("compiled lexical program token must not expose stored plan fields");
    }
}

threadlocal var compiled_token_witness = false;

fn compiledBodyReturnSyntax(comptime HandlersType: type, comptime Body: type) ?[]const u8 {
    return anonymous_body_synthesis.canonicalReturnTypeSyntax(BodyReturnType(Body, PreviewBodyEffType(HandlersType)));
}

fn failRepoOwnedAnonymousSource(comptime Body: type) noreturn {
    @compileError(std.fmt.comptimePrint(
        "ability.with repo-owned anonymous body requires a unique synthetic source before compiled execution: body={s}",
        .{@typeName(Body)},
    ));
}

fn failUnsupportedBody(comptime Body: type) noreturn {
    @compileError(std.fmt.comptimePrint(
        "ability.with could not compile this body shape; external body types must declare source/source_hash/source_file/source_location/source_identity from their owning source bytes: body={s}",
        .{@typeName(Body)},
    ));
}

fn isAnonymousBodyType(comptime Body: type) bool {
    const name = @typeName(Body);
    return std.mem.find(u8, name, "__struct_") != null;
}

fn sourceBackedNamedBodySymbol(comptime Body: type) ?[]const u8 {
    if (isAnonymousBodyType(Body)) return null;
    const name = @typeName(Body);
    var start: usize = 0;
    for (name, 0..) |char, index| {
        if (char == '.') start = index + 1;
    }
    const symbol = name[start..];
    if (symbol.len == 0) return null;
    if (!(std.ascii.isAlphabetic(symbol[0]) or symbol[0] == '_')) return null;
    for (symbol[1..]) |char| {
        if (!(std.ascii.isAlphanumeric(char) or char == '_')) return null;
    }
    return symbol;
}

fn sourceBackedBodySource(comptime Body: type) []const u8 {
    return bodyDeclSource(Body) orelse @compileError(
        "ability.with external body types must declare pub const source containing embedded source bytes",
    );
}

fn sourceBackedBodySourceHash(comptime Body: type) u64 {
    return bodyDeclSourceHash(Body) orelse @compileError(
        "ability.with source-backed body must declare pub const source_hash matching the owning source bytes",
    );
}

/// Return the stable source-content hash used by source-backed `ability.with` bodies.
pub fn sourceHash(comptime source: []const u8) u64 {
    comptime {
        @setEvalBranchQuota(1_000_000);
    }
    return std.hash.Wyhash.hash(0, source);
}

fn sourceBackedBodySourceHashMatches(
    comptime source: []const u8,
    comptime source_hash: u64,
) bool {
    return sourceHash(source) == source_hash;
}

fn requireSourceBackedBodySourceHashMatch(
    comptime source: []const u8,
    comptime source_hash: u64,
) void {
    if (!comptime sourceBackedBodySourceHashMatches(source, source_hash)) {
        @compileError("ability.with source-backed body source/source_hash did not match the owning source bytes");
    }
}

fn sourceBackedNamedBodyIdentity(comptime Body: type) []const u8 {
    return bodyDeclSourceIdentity(Body) orelse @compileError(
        "ability.with source-backed named body must declare pub const source_identity matching the selected source declaration",
    );
}

fn sourceBackedBodyFile(comptime Body: type) []const u8 {
    return bodyDeclSourceFile(Body) orelse @compileError(
        "ability.with source-backed body must declare pub const source_file matching @src().file from the source owner",
    );
}

fn sourceBackedBodyLocation(comptime Body: type) std.builtin.SourceLocation {
    return bodyDeclSourceLocation(Body) orelse @compileError(
        "ability.with source-backed body must declare pub const source_location from a function inside the body declaration",
    );
}

fn sourceFileMatchesLocation(
    comptime source_file: []const u8,
    comptime source_location: std.builtin.SourceLocation,
) bool {
    if (source_file.len == 0 or source_location.file.len == 0) return false;
    if (source_file.len != source_location.file.len) return false;
    for (source_file, 0..) |char, index| {
        const location_char = source_location.file[index];
        if (char == location_char) continue;
        if ((char == '/' or char == '\\') and (location_char == '/' or location_char == '\\')) continue;
        return false;
    }
    return true;
}

fn sourceBackedTypeNameContainsIdentity(
    comptime type_name: []const u8,
    comptime source_identity: []const u8,
) bool {
    if (std.mem.eql(u8, type_name, source_identity)) return true;
    if (!std.mem.endsWith(u8, type_name, source_identity)) return false;
    const prefix_len = type_name.len - source_identity.len;
    return prefix_len > 0 and type_name[prefix_len - 1] == '.';
}

const SourceBackedBodyWitnessVerdict = enum {
    declaration_mismatch,
    hash_mismatch,
    identity_mismatch,
    location_mismatch,
    matches,
    source_file_location_mismatch,
};

const SourceBackedNamedAdmission = struct {
    source: []const u8,
    source_hash: u64,
    source_identity: []const u8,
    source_file: []const u8,
    source_location: std.builtin.SourceLocation,
    body_symbol: []const u8,
};

const SourceBackedAnonAdmission = struct {
    source: []const u8,
    source_hash: u64,
    source_file: []const u8,
    source_location: std.builtin.SourceLocation,
    selection: anonymous_body_synthesis.SourceBackedAnonymousSelection,
};

// zlinter-disable max_positional_args - source-backed witnesses must compare all source identity dimensions at one boundary.
fn sourceBackedNamedBodyWitnessVerdict(
    comptime Body: type,
    comptime source: []const u8,
    comptime body_symbol: []const u8,
    comptime source_hash: u64,
    comptime source_identity: []const u8,
    comptime source_file: []const u8,
    comptime source_location: std.builtin.SourceLocation,
) SourceBackedBodyWitnessVerdict {
    if (!comptime sourceBackedBodySourceHashMatches(source, source_hash)) return .hash_mismatch;
    if (!comptime sourceBackedTypeNameContainsIdentity(@typeName(Body), source_identity)) return .identity_mismatch;
    if (!comptime sourceFileMatchesLocation(source_file, source_location)) return .source_file_location_mismatch;
    if (!comptime anonymous_body_synthesis.namedStructSourceWitnessMatches(
        source,
        body_symbol,
        source_identity,
        source_file,
        source_location.line,
        source_location.column,
    )) return .declaration_mismatch;
    return .matches;
}

fn sourceBackedAnonymousBodyWitnessVerdict(
    comptime source: []const u8,
    comptime source_hash: u64,
    comptime source_file: []const u8,
    comptime source_location: std.builtin.SourceLocation,
    comptime body_bounds: anytype,
) SourceBackedBodyWitnessVerdict {
    if (!comptime sourceBackedBodySourceHashMatches(source, source_hash)) return .hash_mismatch;
    if (!comptime sourceFileMatchesLocation(source_file, source_location)) return .location_mismatch;
    if (!comptime anonymous_body_synthesis.bodyExpressionSourceWitnessMatches(
        source,
        body_bounds,
        source_file,
        source_location.line,
        source_location.column,
    )) return .location_mismatch;
    return .matches;
}

fn failSourceBackedNamedBodyWitness(comptime verdict: SourceBackedBodyWitnessVerdict) noreturn {
    switch (verdict) {
        .matches => unreachable,
        .hash_mismatch => @compileError("ability.with source-backed body source/source_hash did not match the owning source bytes"),
        .identity_mismatch => @compileError("ability.with source-backed named body source_identity did not match the selected top-level declaration"),
        .source_file_location_mismatch => @compileError("ability.with source-backed named body source_file did not match source_location.file"),
        .declaration_mismatch,
        .location_mismatch,
        => @compileError("ability.with source-backed named body source/source_identity/source_file/source_location did not identify the same top-level declaration"),
    }
}

fn failSourceBackedAnonymousBodyWitness(comptime verdict: SourceBackedBodyWitnessVerdict) noreturn {
    switch (verdict) {
        .matches => unreachable,
        .hash_mismatch => @compileError("ability.with source-backed body source/source_hash did not match the owning source bytes"),
        .declaration_mismatch,
        .identity_mismatch,
        .location_mismatch,
        .source_file_location_mismatch,
        => @compileError("ability.with source-backed body source_file/source_location did not match the selected source declaration"),
    }
}

fn sourceBackedNamedBodyAdmission(comptime Body: type) SourceBackedNamedAdmission {
    const body_symbol = comptime sourceBackedNamedBodySymbol(Body) orelse
        @compileError("ability.with source-backed named body must have a simple top-level type name");
    const source = comptime sourceBackedBodySource(Body);
    const source_hash = comptime sourceBackedBodySourceHash(Body);
    const source_identity = comptime sourceBackedNamedBodyIdentity(Body);
    const source_file = comptime sourceBackedBodyFile(Body);
    const source_location = comptime sourceBackedBodyLocation(Body);
    switch (comptime sourceBackedNamedBodyWitnessVerdict(
        Body,
        source,
        body_symbol,
        source_hash,
        source_identity,
        source_file,
        source_location,
    )) {
        .matches => {},
        .hash_mismatch,
        .declaration_mismatch,
        .identity_mismatch,
        .location_mismatch,
        .source_file_location_mismatch,
        => |verdict| failSourceBackedNamedBodyWitness(verdict),
    }
    return .{
        .source = source,
        .source_hash = source_hash,
        .source_identity = source_identity,
        .source_file = source_file,
        .source_location = source_location,
        .body_symbol = body_symbol,
    };
}

fn sourceBackedAnonymousBodyAdmission(
    comptime Body: type,
    comptime return_syntax: ?[]const u8,
) SourceBackedAnonAdmission {
    const source = comptime sourceBackedBodySource(Body);
    const source_hash = comptime sourceBackedBodySourceHash(Body);
    comptime requireSourceBackedBodySourceHashMatch(source, source_hash);
    const source_file = comptime sourceBackedBodyFile(Body);
    const source_location = comptime sourceBackedBodyLocation(Body);
    if (comptime sourceBackedBodyWitnessSelection(Body, source, source_file, source_location, return_syntax)) |selection| {
        switch (comptime sourceBackedAnonymousBodyWitnessVerdict(source, source_hash, source_file, source_location, selection.body_bounds)) {
            .matches => {},
            .hash_mismatch,
            .declaration_mismatch,
            .identity_mismatch,
            .location_mismatch,
            .source_file_location_mismatch,
            => |verdict| failSourceBackedAnonymousBodyWitness(verdict),
        }
        return .{
            .source = source,
            .source_hash = source_hash,
            .source_file = source_file,
            .source_location = source_location,
            .selection = selection,
        };
    }
    @compileError("ability.with source-backed anonymous body source did not contain a unique matching ability.with body");
}

fn sourceBackedBodyWitnessSelection(
    comptime Body: type,
    comptime source: []const u8,
    comptime source_file: []const u8,
    comptime source_location: std.builtin.SourceLocation,
    comptime return_syntax: ?[]const u8,
) ?anonymous_body_synthesis.SourceBackedAnonymousSelection {
    return anonymous_body_synthesis.uniqueSourceBackedAnonymousSelectionWithReturnSyntax(
        Body,
        source,
        .plain_with,
        source_file,
        source_location,
        return_syntax,
    );
}

// zlinter-disable max_positional_args - source-backed witnesses must compare all source identity dimensions at one boundary.
fn sourceBackedNamedBodyWitnessMatches(
    comptime Body: type,
    comptime source: []const u8,
    comptime body_symbol: []const u8,
    comptime source_hash: u64,
    comptime source_identity: []const u8,
    comptime source_file: []const u8,
    comptime source_location: std.builtin.SourceLocation,
) bool {
    return comptime sourceBackedNamedBodyWitnessVerdict(
        Body,
        source,
        body_symbol,
        source_hash,
        source_identity,
        source_file,
        source_location,
    ) == .matches;
}

fn sourceBackedAnonymousBodyWitnessMatches(
    comptime source: []const u8,
    comptime source_hash: u64,
    comptime source_file: []const u8,
    comptime source_location: std.builtin.SourceLocation,
    comptime body_bounds: anytype,
) bool {
    return comptime sourceBackedAnonymousBodyWitnessVerdict(
        source,
        source_hash,
        source_file,
        source_location,
        body_bounds,
    ) == .matches;
}

fn sourceBackedSyntheticCaller(
    comptime source_path: []const u8,
    comptime entry_symbol: []const u8,
) std.builtin.SourceLocation {
    const source_path_z = std.fmt.comptimePrint("{s}\x00", .{source_path});
    const entry_symbol_z = std.fmt.comptimePrint("{s}\x00", .{entry_symbol});
    return .{
        .module = @src().module,
        .file = source_path_z[0..source_path.len :0],
        .line = 1,
        .column = 1,
        .fn_name = entry_symbol_z[0..entry_symbol.len :0],
    };
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
            "ability.with could not compile this repo-owned anonymous body; use a supported lexical body shape or add an explicit source-backed named body: source={s} entry={s}",
            .{ synthesized.source_path, synthesized.entry_symbol },
        ));
    }
    const program_type = CompiledLexicalProgram(
        HandlersType,
        Body,
        source_ref,
        "ability.with repo-owned lexical body",
        synthesized.entry_symbol,
    );
    return try program_type.run(
        runtime,
        handlers_ptr,
        outputs_ptr,
    );
}

fn trySourceBackedAnonymousCompiledWith(
    comptime HandlersType: type,
    comptime Body: type,
    runtime: *lowered_machine.Runtime,
    handlers_ptr: *HandlersType,
    outputs_ptr: *OutputBundleType(HandlersType),
) lowered_machine.ResetError(HandlerErrorSet(HandlersType) || BodyErrorSet(Body, PreviewBodyEffType(HandlersType)))!BodyAnswerType(Body, PreviewBodyEffType(HandlersType)) {
    const return_syntax = compiledBodyReturnSyntax(HandlersType, Body);
    const admission = comptime sourceBackedAnonymousBodyAdmission(Body, return_syntax);
    const synthesized = comptime anonymous_body_synthesis.sourceBackedAnonymousSourceFromSelection(
        Body,
        admission.source,
        admission.selection,
        return_syntax,
    ) orelse @compileError("ability.with source-backed anonymous body source did not contain a unique matching ability.with body");
    const synthetic_path = comptime syntheticLoweringSourcePath(synthesized.entry_symbol);
    const source_ref = comptime lowering_api.sourceWithContent(
        synthetic_path,
        syntheticSourceLocation(synthetic_path, synthesized.entry_symbol),
        synthesized.source,
    );
    if (comptime anonymous_body_synthesis.entryBodyHasBareFunctionCall(synthesized.source, synthesized.entry_symbol)) {
        @compileError("ability.with source-backed anonymous body uses a helper-call pattern this lowering path cannot compile; inline the effect operation or use a supported source-backed helper shape");
    }
    if (comptime anonymous_body_synthesis.maybeLowerSyntheticLexicalBody(
        HandlersType,
        BodyAnswerType(Body, PreviewBodyEffType(HandlersType)),
        synthetic_path,
        synthesized.source,
        synthesized.entry_symbol,
    ) == null) {
        @compileError("ability.with source-backed anonymous body could not be compiled by the source-backed lowering path; simplify the body to supported effect operations, locals, branches, and helper shapes");
    }
    const program_type = CompiledLexicalProgram(
        HandlersType,
        Body,
        source_ref,
        "ability.with source-backed anonymous body",
        synthesized.entry_symbol,
    );
    return try program_type.run(
        runtime,
        handlers_ptr,
        outputs_ptr,
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
        @compileError("ability.with named-body lowering requires Body.source_path");
    const body_symbol = comptime bodyDeclBodySymbol(Body) orelse
        @compileError("ability.with named-body lowering requires Body.body_symbol");
    const entry_symbol = comptime std.fmt.comptimePrint("__ability_with_named_{s}", .{body_symbol});
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
            "ability.with could not lower source-backed named body entry={s} from source={s}; supported shapes are direct effect calls, locals, branches, and validated helper calls. Simplify the unsupported body/helper or verify source/source_hash/source_file/source_location/source_identity all point to this declaration.",
            .{ entry_symbol, source_path },
        ));
    }
    const program_type = CompiledLexicalProgram(
        HandlersType,
        Body,
        source_ref,
        "ability.with source-backed named body",
        entry_symbol,
    );
    return try program_type.run(
        runtime,
        handlers_ptr,
        outputs_ptr,
    );
}

fn trySourceBackedNamedCompiledWith(
    comptime HandlersType: type,
    comptime Body: type,
    runtime: *lowered_machine.Runtime,
    handlers_ptr: *HandlersType,
    outputs_ptr: *OutputBundleType(HandlersType),
) lowered_machine.ResetError(HandlerErrorSet(HandlersType) || BodyErrorSet(Body, PreviewBodyEffType(HandlersType)))!BodyAnswerType(Body, PreviewBodyEffType(HandlersType)) {
    const admission = comptime sourceBackedNamedBodyAdmission(Body);
    const entry_symbol = comptime std.fmt.comptimePrint("__ability_with_named_{s}", .{admission.body_symbol});
    const synthetic_path = comptime syntheticLoweringSourcePath(entry_symbol);
    const synthetic_source = comptime anonymous_body_synthesis.syntheticSourceForNamedTypeWithEntry(
        Body,
        sourceBackedSyntheticCaller(synthetic_path, entry_symbol),
        admission.source,
        admission.body_symbol,
        entry_symbol,
        compiledBodyReturnSyntax(HandlersType, Body),
    ) orelse @compileError("ability.with source-backed named body source did not contain a matching top-level struct declaration");
    const source_ref = comptime lowering_api.sourceWithContent(
        synthetic_path,
        syntheticSourceLocation(synthetic_path, entry_symbol),
        synthetic_source,
    );
    if (comptime anonymous_body_synthesis.entryBodyHasBareFunctionCall(synthetic_source, entry_symbol)) {
        @compileError("ability.with source-backed named body uses a helper-call pattern this lowering path cannot compile; inline the effect operation or use a supported source-backed helper shape");
    }
    if (comptime anonymous_body_synthesis.maybeLowerSyntheticLexicalBody(
        HandlersType,
        BodyAnswerType(Body, PreviewBodyEffType(HandlersType)),
        synthetic_path,
        synthetic_source,
        entry_symbol,
    ) == null) {
        @compileError("ability.with source-backed named body could not be compiled by the source-backed lowering path; simplify the body to supported effect operations, locals, branches, and helper shapes");
    }
    const program_type = CompiledLexicalProgram(
        HandlersType,
        Body,
        source_ref,
        "ability.with source-backed named body",
        entry_symbol,
    );
    return try program_type.run(
        runtime,
        handlers_ptr,
        outputs_ptr,
    );
}

fn supportsNamedBodyLowering(comptime Body: type) bool {
    return comptime bodyDeclSourcePath(Body) != null and bodyDeclBodySymbol(Body) != null;
}

fn supportsSourceBackedNamedBody(comptime Body: type) bool {
    return comptime bodyDeclSource(Body) != null and sourceBackedNamedBodySymbol(Body) != null;
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
    else if (comptime supportsSourceBackedNamedBody(Body))
        trySourceBackedNamedCompiledWith(HandlersType, Body, runtime, &handler_state, &outputs)
    else if (comptime bodyDeclSource(Body) != null)
        trySourceBackedAnonymousCompiledWith(HandlersType, Body, runtime, &handler_state, &outputs)
    else if (comptime anonymous_body_synthesis.hasRepoOwnedCandidate(Body))
        tryRepoOwnedAnonymousCompiledWith(HandlersType, Body, runtime, &handler_state, &outputs)
    else
        failUnsupportedBody(Body);
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

test "plain repo-owned ability.with uses the compiled lexical program token when the body is unique" {
    const state = @import("effect/state.zig");

    compiled_token_witness = false;
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

    try std.testing.expect(compiled_token_witness);
    try std.testing.expectEqual(@as(i32, 6), result.value);
    try std.testing.expectEqual(@as(i32, 6), result.outputs.state);
}

test "source-backed named body type identity admits import-root prefixes only at segment boundary" {
    try std.testing.expect(comptime sourceBackedTypeNameContainsIdentity(
        "foo.Body",
        "foo.Body",
    ));
    try std.testing.expect(comptime sourceBackedTypeNameContainsIdentity(
        "root.foo.Body",
        "foo.Body",
    ));
    try std.testing.expect(!comptime sourceBackedTypeNameContainsIdentity(
        "not_foo.Body",
        "foo.Body",
    ));
    try std.testing.expect(!comptime sourceBackedTypeNameContainsIdentity(
        "root.bar.Body",
        "foo.Body",
    ));
}

test "source-backed body hash witness rejects mismatched source bytes" {
    const source = @embedFile("with_api.zig");
    const correct_hash = sourceHash(source);

    try std.testing.expect(comptime sourceBackedBodySourceHashMatches(source, correct_hash));
    try std.testing.expect(!comptime sourceBackedBodySourceHashMatches(source, correct_hash + 1));
    comptime requireSourceBackedBodySourceHashMatch(source, correct_hash);
}

fn testSourceLocationForMarker(
    comptime source: []const u8,
    comptime file: [:0]const u8,
    comptime marker: []const u8,
) std.builtin.SourceLocation {
    const marker_offset = std.mem.find(u8, source, marker).?;
    comptime var line: u32 = 1;
    comptime var column: u32 = 1;
    inline for (source[0..marker_offset]) |char| {
        if (char == '\n') {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }
    return .{
        .module = @src().module,
        .file = file,
        .line = line,
        .column = column,
        .fn_name = "sourceLocation",
    };
}

test "source-backed anonymous body verifier rejects every mismatched witness dimension" {
    const source =
        \\const ability = @import("ability");
        \\
        \\test "first" {
        \\    _ = try ability.with(undefined, .{}, struct {
        \\        fn sourceLocation() @import("std").builtin.SourceLocation { return @src(); }
        \\        pub const source_file = "anon.zig";
        \\        pub const source_location = sourceLocation();
        \\        pub fn body(eff: anytype) anyerror!void { _ = eff; }
        \\    });
        \\}
        \\
        \\test "second" {
        \\    _ = try ability.with(undefined, .{}, struct {
        \\        fn sourceLocation() @import("std").builtin.SourceLocation { return @src(); }
        \\        pub const source_file = "anon.zig";
        \\        pub const source_location = sourceLocation();
        \\        pub fn body(eff: anytype) anyerror!void { _ = eff; }
        \\    });
        \\}
    ;
    const first_block = comptime anonymous_body_synthesis.testBlockBounds(source, "first").?;
    const second_block = comptime anonymous_body_synthesis.testBlockBounds(source, "second").?;
    const first_bounds = comptime anonymous_body_synthesis.uniqueBodyExpressionBoundsInRange(
        source,
        first_block.start,
        first_block.end,
        .plain_with,
    ).?;
    const second_bounds = comptime anonymous_body_synthesis.uniqueBodyExpressionBoundsInRange(
        source,
        second_block.start,
        second_block.end,
        .plain_with,
    ).?;
    const location = comptime testSourceLocationForMarker(source, "anon.zig", "@src()");
    const source_hash = comptime sourceHash(source);

    try std.testing.expect(comptime sourceBackedAnonymousBodyWitnessMatches(source, source_hash, "anon.zig", location, first_bounds));
    try std.testing.expect(!comptime sourceBackedAnonymousBodyWitnessMatches(source, source_hash + 1, "anon.zig", location, first_bounds));
    try std.testing.expect(!comptime sourceBackedAnonymousBodyWitnessMatches(source, source_hash, "wrong.zig", location, first_bounds));
    try std.testing.expect(!comptime sourceBackedAnonymousBodyWitnessMatches(source, source_hash, "anon.zig", .{
        .module = location.module,
        .file = location.file,
        .line = location.line,
        .column = location.column - 1,
        .fn_name = location.fn_name,
    }, first_bounds));
    try std.testing.expect(!comptime sourceBackedAnonymousBodyWitnessMatches(source, source_hash, "anon.zig", location, second_bounds));
}

test "source-backed named body verifier rejects every mismatched witness dimension" {
    const source = @embedFile("with_api.zig");
    const location = source_backed_witness_body.source_location;
    const correct_hash = sourceHash(source);

    try std.testing.expect(comptime sourceBackedNamedBodyWitnessMatches(
        source_backed_witness_body,
        source,
        "source_backed_witness_body",
        correct_hash,
        "with_api.source_backed_witness_body",
        "src/with_api.zig",
        location,
    ));
    try std.testing.expect(!comptime sourceBackedNamedBodyWitnessMatches(
        source_backed_witness_body,
        source,
        "source_backed_witness_body",
        correct_hash + 1,
        "with_api.source_backed_witness_body",
        "src/with_api.zig",
        location,
    ));
    try std.testing.expect(!comptime sourceBackedNamedBodyWitnessMatches(
        source_backed_witness_body,
        source,
        "source_backed_witness_body",
        correct_hash,
        "with_api.other_body",
        "src/with_api.zig",
        location,
    ));
    try std.testing.expect(!comptime sourceBackedNamedBodyWitnessMatches(
        source_backed_witness_body,
        source,
        "source_backed_witness_body",
        correct_hash,
        "with_api.source_backed_witness_body",
        "test/with_api.zig",
        location,
    ));
    try std.testing.expect(!comptime sourceBackedNamedBodyWitnessMatches(
        source_backed_witness_body,
        source,
        "source_backed_witness_body",
        correct_hash,
        "with_api.source_backed_witness_body",
        "src/with_api.zig",
        .{
            .module = location.module,
            .file = location.file,
            .line = location.line,
            .column = location.column - 1,
            .fn_name = location.fn_name,
        },
    ));
    try std.testing.expect(!comptime sourceBackedNamedBodyWitnessMatches(
        source_backed_witness_body,
        source,
        "missing_body",
        correct_hash,
        "with_api.source_backed_witness_body",
        "src/with_api.zig",
        location,
    ));
    try std.testing.expectEqual(.hash_mismatch, comptime sourceBackedNamedBodyWitnessVerdict(
        source_backed_witness_body,
        source,
        "source_backed_witness_body",
        correct_hash + 1,
        "with_api.source_backed_witness_body",
        "src/with_api.zig",
        location,
    ));
    try std.testing.expectEqual(.identity_mismatch, comptime sourceBackedNamedBodyWitnessVerdict(
        source_backed_witness_body,
        source,
        "source_backed_witness_body",
        correct_hash,
        "with_api.other_body",
        "src/with_api.zig",
        location,
    ));
    try std.testing.expectEqual(.source_file_location_mismatch, comptime sourceBackedNamedBodyWitnessVerdict(
        source_backed_witness_body,
        source,
        "source_backed_witness_body",
        correct_hash,
        "with_api.source_backed_witness_body",
        "test/with_api.zig",
        location,
    ));
    try std.testing.expectEqual(.declaration_mismatch, comptime sourceBackedNamedBodyWitnessVerdict(
        source_backed_witness_body,
        source,
        "missing_body",
        correct_hash,
        "with_api.source_backed_witness_body",
        "src/with_api.zig",
        location,
    ));
}

const source_backed_witness_body = struct {
    fn sourceLocation() std.builtin.SourceLocation {
        return @src();
    }

    /// Stable identity witness for the source-backed named-body test declaration.
    pub const source_identity = "with_api.source_backed_witness_body";
    /// Stable file witness for the source-backed named-body test declaration.
    pub const source_file = "src/with_api.zig";
    /// Compiler-owned location witness for the declaration that owns `source`.
    pub const source_location = sourceLocation();
    /// Authoritative source bytes for this named body witness.
    pub const source = @embedFile("with_api.zig");
    /// Hash witness for the owning source bytes.
    pub const source_hash = sourceHash(source);

    /// Source-backed body used by the compiled lexical fast path test.
    pub fn body(eff: anytype) anyerror!i32 {
        const before = try eff.state.get();
        try eff.state.set(before + 3);
        return try eff.state.get();
    }
};

test "source-backed ability.with uses the compiled lexical program token from Body.source" {
    const state = @import("effect/state.zig");

    compiled_token_witness = false;
    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try with(&runtime, .{
        .state = state.use(@as(i32, 5)),
    }, source_backed_witness_body);

    try std.testing.expect(compiled_token_witness);
    try std.testing.expectEqual(@as(i32, 8), result.value);
    try std.testing.expectEqual(@as(i32, 8), result.outputs.state);
}

test "with_api module can lower the actual lexical_with_test synthetic packet through the shared helper" {
    const ability = @import("ability");
    const source = source_graph_embed.embeddedSource("test/lexical_with_test.zig");
    const test_block = comptime anonymous_body_synthesis.testBlockBounds(source, "ability.with accepts body run(self, eff)").?;
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
    const entry_symbol = "__ability_with_entry_36363";
    const synthetic_path = "/tmp/ability_with/__ability_with_entry_36363.zig";
    const synthetic = comptime anonymous_body_synthesis.syntheticSourceForExpr(
        body_type,
        source[bounds.start..bounds.end],
        source,
        entry_symbol,
        null,
    ).?;
    const Handlers = @TypeOf(.{
        .state = ability.effect.state.use(@as(i32, 11)),
    });

    try std.testing.expect(anonymous_body_synthesis.maybeLowerSyntheticLexicalBody(
        Handlers,
        i32,
        synthetic_path,
        synthetic,
        entry_symbol,
    ) != null);
}
