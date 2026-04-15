const builtin = @import("builtin");
const family = @import("effect/family.zig");
const frontend = @import("frontend_support");
const lexical_bundle_schema = @import("internal/lexical_bundle_schema.zig");
const lexical_executable_bundle = @import("internal/lexical_executable_bundle.zig");
const lowered_machine = @import("lowered_machine");
const prompt_contract = @import("prompt_contract_support");
const public_lowering = @import("public_lowering");
const source_graph_engine = @import("source_graph_engine");
const std = @import("std");

/// One descriptor result: final descriptor output plus body answer.
pub fn DescriptorResult(comptime Output: type, comptime Answer: type) type {
    return struct {
        output: Output,
        value: Answer,
    };
}

fn NamedBodyAnswerType(comptime Body: type) type {
    const ReturnType = Body.ReturnType;
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.payload,
        else => ReturnType,
    };
}

/// Named lexical body reference used as the canonical compiled `shift.with(...)` surface.
pub fn NamedBody(
    comptime source_path_value: []const u8,
    comptime entry_symbol_value: []const u8,
    comptime ReturnTypeValue: type,
    comptime body_fn: anytype,
) type {
    return struct {
        /// Repo-visible source path for the named lexical body.
        pub const source_path = source_path_value;
        /// Top-level function symbol compiled for this named lexical body.
        pub const entry_symbol = entry_symbol_value;
        /// Declared return type for this named lexical body.
        pub const ReturnType = ReturnTypeValue;
        const body_fn_ref = body_fn;
    };
}

/// Explicit caller-owned source witness used to compile lexical bodies through the root package.
pub const OwnedSourceWitness = struct {
    source_path: ?[]const u8 = null,
    entry_symbol: ?[]const u8 = null,
    /// Raw Zig source bytes appended to the caller-owned root source before lowering.
    body_source: ?[]const u8 = null,
    body_method_name: []const u8 = "body",
    imported_sources: []const public_lowering.ImportedSource = &.{},
};

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
        caller_file: []const u8,
        caller_line: u32,
        caller_column: u32,
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
    if (@hasDecl(Body, "ReturnType")) return Body.ReturnType;
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

fn callerSourceBytes(
    comptime caller: std.builtin.SourceLocation,
    comptime caller_source_override: ?[:0]const u8,
) [:0]const u8 {
    return caller_source_override orelse @embedFile(caller.file);
}

fn offsetForLineColumn(
    comptime source: []const u8,
    comptime target_line: u32,
    comptime target_column: u32,
) ?usize {
    var line: u32 = 1;
    var column: u32 = 1;
    for (source, 0..) |byte, index| {
        if (line == target_line and column == target_column) return index;
        if (byte == '\n') {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }
    if (line == target_line and column == target_column) return source.len;
    return null;
}

fn isIgnorableCallsiteToken(tag: std.zig.Token.Tag) bool {
    return switch (tag) {
        .doc_comment,
        .container_doc_comment,
        => true,
        else => false,
    };
}

fn anonymousBodyExprBounds(
    comptime caller: std.builtin.SourceLocation,
    comptime caller_source_override: ?[:0]const u8,
) ?struct { start: usize, end: usize } {
    comptime {
        @setEvalBranchQuota(2_000_000);
    }
    const source = comptime callerSourceBytes(caller, caller_source_override);
    const target_offset = comptime offsetForLineColumn(source, caller.line, caller.column) orelse return null;
    const call_name = if (caller_source_override != null)
        "withCallerSourceAndContent"
    else
        "withCallerSource";
    const body_arg_index: usize = if (caller_source_override != null) 4 else 3;
    const call_offset = std.mem.lastIndexOf(u8, source[0..target_offset], call_name) orelse return null;
    var tokenizer = std.zig.Tokenizer.init(source);
    var seen_with_name = false;

    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) return null;
        if (isIgnorableCallsiteToken(token.tag)) continue;
        if (token.loc.start < call_offset) continue;
        if (!seen_with_name) {
            if (token.tag == .identifier and std.mem.eql(u8, source[token.loc.start..token.loc.end], call_name)) {
                seen_with_name = true;
            }
            continue;
        }
        if (token.tag != .l_paren) continue;

        var paren_depth: usize = 1;
        var brace_depth: usize = 0;
        var bracket_depth: usize = 0;
        var arg_index: usize = 0;
        var arg_start: ?usize = null;

        while (true) {
            const arg_token = tokenizer.next();
            if (arg_token.tag == .eof) return null;
            if (isIgnorableCallsiteToken(arg_token.tag)) continue;
            if (arg_start == null) arg_start = arg_token.loc.start;

            const is_delimiter = (arg_token.tag == .comma or arg_token.tag == .r_paren) and
                paren_depth == 1 and
                brace_depth == 0 and
                bracket_depth == 0;
            if (is_delimiter) {
                if (arg_index == body_arg_index) {
                    return .{ .start = arg_start.?, .end = arg_token.loc.start };
                }
                arg_index += 1;
                arg_start = null;
                if (arg_token.tag == .r_paren) return null;
                continue;
            }

            switch (arg_token.tag) {
                .l_paren => paren_depth += 1,
                .r_paren => {
                    if (paren_depth == 0) return null;
                    paren_depth -= 1;
                },
                .l_brace => brace_depth += 1,
                .r_brace => {
                    if (brace_depth == 0) return null;
                    brace_depth -= 1;
                },
                .l_bracket => bracket_depth += 1,
                .r_bracket => {
                    if (bracket_depth == 0) return null;
                    bracket_depth -= 1;
                },
                else => {},
            }
        }
    }
}

fn anonymousBodyMethodName(comptime Body: type) ?[]const u8 {
    if (@hasDecl(Body, "body")) return "body";
    if (@hasDecl(Body, "run")) return "run";
    return null;
}

fn anonymousBodyHolderName(_: std.builtin.SourceLocation) [:0]const u8 {
    return "__shift_with_body"[0.."__shift_with_body".len :0];
}

fn anonymousBodyEntryName(_: std.builtin.SourceLocation) [:0]const u8 {
    return "__shift_with_entry"[0.."__shift_with_entry".len :0];
}

fn anonymousBodySyntheticSource(
    comptime caller: std.builtin.SourceLocation,
    comptime Body: type,
    comptime caller_source_override: ?[:0]const u8,
) ?[:0]const u8 {
    const method_name = anonymousBodyMethodName(Body) orelse return null;
    const caller_source = comptime callerSourceBytes(caller, caller_source_override);
    const expr_bounds = comptime anonymousBodyExprBounds(caller, caller_source_override) orelse return null;
    const expr_len = comptime expr_bounds.end - expr_bounds.start;
    const expr_source = comptime blk: {
        var buffer: [expr_len]u8 = undefined;
        for (0..expr_len) |index| {
            buffer[index] = caller_source[expr_bounds.start + index];
        }
        break :blk buffer[0..];
    };
    const holder_name = anonymousBodyHolderName(caller);
    const entry_name = anonymousBodyEntryName(caller);
    return comptime blk: {
        var buffer: [caller_source.len + 4096:0]u8 = undefined;
        var index: usize = 0;

        const append = struct {
            fn bytes(buffer_ptr: []u8, index_ptr: *usize, comptime segment: []const u8) void {
                @memcpy(buffer_ptr[index_ptr.* .. index_ptr.* + segment.len], segment);
                index_ptr.* += segment.len;
            }
        }.bytes;

        append(buffer[0..], &index, caller_source);
        append(buffer[0..], &index, "\nconst ");
        append(buffer[0..], &index, holder_name);
        append(buffer[0..], &index, " = ");
        append(buffer[0..], &index, expr_source);
        append(buffer[0..], &index, ";\npub fn ");
        append(buffer[0..], &index, entry_name);
        append(buffer[0..], &index, "(eff: anytype) @TypeOf(");
        append(buffer[0..], &index, holder_name);
        append(buffer[0..], &index, ".");
        append(buffer[0..], &index, method_name);
        append(buffer[0..], &index, "(eff)) { return ");
        append(buffer[0..], &index, holder_name);
        append(buffer[0..], &index, ".");
        append(buffer[0..], &index, method_name);
        append(buffer[0..], &index, "(eff); }\n");

        if (index > buffer.len - 1) {
            @compileError("anonymous caller-owned lexical body wrapper exceeded the fixed synthetic source buffer");
        }
        buffer[index] = 0;
        break :blk buffer[0..index :0];
    };
}

fn witnessSyntheticSource(
    comptime caller_source: [:0]const u8,
    comptime caller: std.builtin.SourceLocation,
    comptime witness: OwnedSourceWitness,
) ?[:0]const u8 {
    _ = caller;
    const body_source = witness.body_source orelse return null;
    return std.fmt.comptimePrint(
        "{s}\n{s}\n",
        .{ caller_source, body_source },
    );
}

test "owned source witness appended body stays visible to the source graph" {
    const caller = std.builtin.SourceLocation{
        .module = @src().module,
        .file = "/tmp/owned_source_visibility_probe.zig",
        .line = 1,
        .column = 1,
        .fn_name = "probe",
    };
    const synthetic_source = witnessSyntheticSource(
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    _ = shift;
        \\    _ = std;
        \\}
    ,
        caller,
        .{
            .entry_symbol = "__owned_body",
            .body_source =
            \\pub fn __owned_body(eff: anytype) anyerror!i32 {
            \\    const before = try eff.state.get();
            \\    try eff.state.set(before + 1);
            \\    return try eff.state.get();
            \\}
            ,
        },
    ).?;
    const graph = try source_graph_engine.analyzeRuntime(std.testing.allocator, synthetic_source, .{
        .entry_symbol = "__owned_body",
        .reject_recursive_helpers = false,
        .reject_indirect_effect_access = true,
        .reject_malformed_statements = true,
    });
    defer std.testing.allocator.free(graph.functions);
    defer std.testing.allocator.free(graph.imports);
    defer std.testing.allocator.free(graph.helper_uses);
    defer std.testing.allocator.free(graph.helper_edges);
    defer std.testing.allocator.free(graph.direct_op_uses);

    try std.testing.expectEqual(@as(?usize, 1), graph.entry_index);
    try std.testing.expectEqualStrings("__owned_body", graph.functions[graph.entry_index.?].name);
}

fn rejectUnsupportedShippedWith(
    comptime Body: type,
    comptime caller: std.builtin.SourceLocation,
    comptime caller_source_override: ?[:0]const u8,
) void {
    if (builtin.is_test) return;
    if (@hasDecl(Body, "source_path") and @hasDecl(Body, "entry_symbol") and @hasDecl(Body, "ReturnType")) return;
    if (anonymousBodySyntheticSource(caller, Body, caller_source_override) != null) return;
    @compileError("shift.with shipped execution currently requires either shift.NamedBody(...) or a caller-owned lexical body shape that can be compiled from the callsite");
}

fn callBody(
    comptime Body: type,
    eff: anytype,
    comptime ErrorSet: type,
    comptime AnswerType: type,
) lowered_machine.ResetError(ErrorSet)!AnswerType {
    if (@hasDecl(Body, "ReturnType")) {
        @compileError("named lexical bodies must execute through shift.with compiled dispatch");
    }
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

fn descriptorRunContext(
    comptime caller: std.builtin.SourceLocation,
    runtime: *lowered_machine.Runtime,
    lexical_state: anytype,
) struct {
    /// Caller-owned source location for this `shift.with(...)` invocation.
    pub const caller_source = caller;
    runtime: *lowered_machine.Runtime,
    lexical_state: @TypeOf(lexical_state),
} {
    return .{
        .runtime = runtime,
        .lexical_state = lexical_state,
    };
}

fn tryNamedCompiledWith(
    comptime HandlersType: type,
    comptime Body: type,
    runtime: *lowered_machine.Runtime,
    handlers_ptr: *HandlersType,
    outputs_ptr: *OutputBundleType(HandlersType),
) ?lowered_machine.ResetError(HandlerErrorSet(HandlersType) || BodyErrorSet(Body, PreviewBodyEffType(HandlersType)))!BodyAnswerType(Body, PreviewBodyEffType(HandlersType)) {
    if (!@hasDecl(Body, "source_path") or !@hasDecl(Body, "entry_symbol") or !@hasDecl(Body, "ReturnType")) return null;
    const lowered_program = public_lowering.lowerOpenRowAt(Body.source_path, .{
        .label = "shift.with named lexical body",
        .entry_symbol = Body.entry_symbol,
        .ValueType = NamedBodyAnswerType(Body),
        .row = lexical_bundle_schema.rowForHandlers(HandlersType),
        .outputs = lexical_bundle_schema.outputsForHandlers(HandlersType),
    }) catch |err| invalidGeneratedPlan(err);
    return try runCompiledLexicalPlan(
        HandlersType,
        Body,
        runtime,
        handlers_ptr,
        outputs_ptr,
        comptime public_lowering.enrichOpenRowPlan(
            "shift.with named lexical body",
            lowered_program,
            lexicalBindingSchemasValue(HandlersType),
        ),
    );
}

// zlinter-disable max_positional_args - this internal compiled caller-owned seam keeps provenance and lexical state explicit across the public-lowering handoff.
fn tryCallerOwnedCompiledWith(
    comptime HandlersType: type,
    comptime Body: type,
    comptime caller: std.builtin.SourceLocation,
    comptime caller_source_override: ?[:0]const u8,
    runtime: *lowered_machine.Runtime,
    handlers_ptr: *HandlersType,
    outputs_ptr: *OutputBundleType(HandlersType),
) ?lowered_machine.ResetError(HandlerErrorSet(HandlersType) || BodyErrorSet(Body, PreviewBodyEffType(HandlersType)))!BodyAnswerType(Body, PreviewBodyEffType(HandlersType)) {
    if (@hasDecl(Body, "source_path") or @hasDecl(Body, "entry_symbol") or @hasDecl(Body, "ReturnType")) return null;
    const synthetic_source = anonymousBodySyntheticSource(caller, Body, caller_source_override) orelse return null;
    const source_ref = public_lowering.sourceWithContent(caller.file, caller, synthetic_source);
    const lowered_program = public_lowering.lowerOpenRow(source_ref, .{
        .label = "shift.with caller-owned lexical body",
        .entry_symbol = anonymousBodyEntryName(caller),
        .ValueType = BodyAnswerType(Body, PreviewBodyEffType(HandlersType)),
        .row = lexical_bundle_schema.rowForHandlers(HandlersType),
        .outputs = lexical_bundle_schema.outputsForHandlers(HandlersType),
    }) catch |err| invalidGeneratedPlan(err);
    return try runCompiledLexicalPlan(
        HandlersType,
        Body,
        runtime,
        handlers_ptr,
        outputs_ptr,
        comptime public_lowering.enrichOpenRowPlan(
            "shift.with caller-owned lexical body",
            lowered_program,
            lexicalBindingSchemasValue(HandlersType),
        ),
    );
}

// zlinter-disable max_positional_args - the explicit owned-source seam threads witness, caller bytes, and lexical state directly to keep ownership boundaries obvious.
fn tryOwnedSourceCompiledWith(
    comptime HandlersType: type,
    comptime Body: type,
    comptime caller: std.builtin.SourceLocation,
    comptime caller_source: [:0]const u8,
    comptime witness: OwnedSourceWitness,
    runtime: *lowered_machine.Runtime,
    handlers_ptr: *HandlersType,
    outputs_ptr: *OutputBundleType(HandlersType),
) lowered_machine.ResetError(HandlerErrorSet(HandlersType) || BodyErrorSet(Body, PreviewBodyEffType(HandlersType)))!BodyAnswerType(Body, PreviewBodyEffType(HandlersType)) {
    const source_path = witness.source_path orelse if (@hasDecl(Body, "source_path"))
        Body.source_path
    else
        caller.file;
    const entry_symbol = witness.entry_symbol orelse if (@hasDecl(Body, "entry_symbol"))
        Body.entry_symbol
    else
        anonymousBodyEntryName(caller);
    const source_ref = comptime if (witness.body_source != null) blk: {
        break :blk public_lowering.sourceWithContentAndImports(
            source_path,
            caller,
            witnessSyntheticSource(caller_source, caller, witness).?,
            witness.imported_sources,
        );
    } else blk: {
        break :blk public_lowering.sourceWithContentAndImports(
            source_path,
            caller,
            caller_source,
            witness.imported_sources,
        );
    };
    const lowered_program = public_lowering.lowerOpenRow(source_ref, .{
        .label = "shift.with owned lexical body",
        .entry_symbol = entry_symbol,
        .ValueType = BodyAnswerType(Body, PreviewBodyEffType(HandlersType)),
        .row = lexical_bundle_schema.rowForHandlers(HandlersType),
        .outputs = lexical_bundle_schema.outputsForHandlers(HandlersType),
    }) catch |err| invalidGeneratedPlan(err);
    return try runCompiledLexicalPlan(
        HandlersType,
        Body,
        runtime,
        handlers_ptr,
        outputs_ptr,
        comptime public_lowering.enrichOpenRowPlan(
            "shift.with owned lexical body",
            lowered_program,
            lexicalBindingSchemasValue(HandlersType),
        ),
    );
}

fn invalidGeneratedPlan(err: anytype) noreturn {
    @compileError(std.fmt.comptimePrint("lexical ProgramPlan generation failed: {s}", .{@errorName(err)}));
}

fn lexicalBindingSchemasValue(comptime HandlersType: type) lexical_bundle_schema.BindingSchemas(HandlersType) {
    return dummyValue(lexical_bundle_schema.BindingSchemas(HandlersType));
}

// zlinter-disable max_positional_args - this compiled lexical runner keeps runtime, handler bundle, and explicit ProgramPlan state visible at the call site.
fn runCompiledLexicalPlan(
    comptime HandlersType: type,
    comptime Body: type,
    runtime: *lowered_machine.Runtime,
    handlers_ptr: *HandlersType,
    outputs_ptr: *OutputBundleType(HandlersType),
    comptime compiled_plan: anytype,
) lowered_machine.ResetError(HandlerErrorSet(HandlersType) || BodyErrorSet(Body, PreviewBodyEffType(HandlersType)))!BodyAnswerType(Body, PreviewBodyEffType(HandlersType)) {
    public_lowering.assertExecutablePlanCodecSupport(compiled_plan);

    const lexical_state = struct {
        runtime: *lowered_machine.Runtime,
        handlers_ptr: *HandlersType,
    }{
        .runtime = runtime,
        .handlers_ptr = handlers_ptr,
    };

    var executable_bundle = lexical_executable_bundle.fromLexicalState(lexical_state);
    var run_error: ?lowered_machine.ResetError(HandlerErrorSet(HandlersType) || BodyErrorSet(Body, PreviewBodyEffType(HandlersType))) = null;
    const result = public_lowering.runExecutablePlan(runtime, compiled_plan, &executable_bundle) catch |err| blk: {
        run_error = @errorCast(err);
        break :blk null;
    };

    var cleanup_error: ?lowered_machine.ResetError(HandlerErrorSet(HandlersType) || BodyErrorSet(Body, PreviewBodyEffType(HandlersType))) = null;
    lexical_executable_bundle.deinit(&executable_bundle) catch |err| {
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

fn anonymousBodyCompilable(
    comptime caller: std.builtin.SourceLocation,
    comptime Body: type,
    comptime caller_source_override: ?[:0]const u8,
) bool {
    return anonymousBodySyntheticSource(caller, Body, caller_source_override) != null;
}

/// Recover the active lexical rebinding packet from the exact context capability.
pub fn activeLexicalState(
    ctx: anytype,
    comptime HandlersType: type,
    comptime EffType: type,
) *LexicalState(HandlersType, EffType) {
    return @ptrCast(@alignCast(ctx._cap.lexical_state.?));
}

// zlinter-disable max_positional_args - threading the exact caller source through the recursive lexical runner is the minimal change that preserves the existing control flow.
fn runChainCollected(
    comptime HandlersType: type,
    comptime Body: type,
    comptime index: usize,
    comptime EffType: type,
    comptime caller: std.builtin.SourceLocation,
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
            return try runChainCollected(HandlersType, Body, index + 1, @TypeOf(next_eff), caller, .{
                .runtime = lexical_state.runtime,
                .handlers_ptr = lexical_state.handlers_ptr,
                .eff_value = next_eff,
                .outputs_ptr = lexical_state.outputs_ptr,
                .caller_file = lexical_state.caller_file,
                .caller_line = lexical_state.caller_line,
                .caller_column = lexical_state.caller_column,
            });
        }
    };

    const result = blk: {
        const RunFn = @TypeOf(DescriptorType.run);
        const params = @typeInfo(RunFn).@"fn".params;
        switch (params.len) {
            5 => break :blk desc_value.run(Answer, ErrorSet, descriptorRunContext(caller, state.runtime, &state), step_ctx),
            6 => break :blk desc_value.run(Answer, ErrorSet, state.runtime, &state, step_ctx),
            else => @compileError("shift.with descriptor run must accept either (self, AnswerType, RunErrorSetType, run_ctx, Body) or the legacy runtime/lexical_state form"),
        }
    } catch |err| return @errorCast(err);
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
                .caller_file = lexical_state.caller_file,
                .caller_line = lexical_state.caller_line,
                .caller_column = lexical_state.caller_column,
            }, Continuation, resume_value);
        }
    };

    const result = blk: {
        const RunFn = @TypeOf(DescriptorType.run);
        const params = @typeInfo(RunFn).@"fn".params;
        switch (params.len) {
            5 => break :blk desc_value.run(ChoiceAnswerTypeFor(Continuation, @TypeOf(resume_value), EffType), ErrorSet, descriptorRunContext(@src(), state.runtime, &state), step_ctx),
            6 => break :blk desc_value.run(ChoiceAnswerTypeFor(Continuation, @TypeOf(resume_value), EffType), ErrorSet, state.runtime, &state, step_ctx),
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
    const field = @typeInfo(HandlersType).@"struct".fields[index];
    const current_eff = extendBundle(@TypeOf(frame.previous_eff), frame.previous_eff, field.name, frame.current_handle);
    return try runChoiceChain(HandlersType, index + 1, @TypeOf(current_eff), .{
        .runtime = frame.runtime,
        .handlers_ptr = frame.handlers_ptr,
        .eff_value = current_eff,
        .outputs_ptr = frame.outputs_ptr,
        .caller_file = frame.caller_file,
        .caller_line = frame.caller_line,
        .caller_column = frame.caller_column,
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
fn withAt(
    runtime: *lowered_machine.Runtime,
    handlers: anytype,
    comptime Body: type,
    comptime caller: std.builtin.SourceLocation,
    comptime caller_source_override: ?[:0]const u8,
) WithFnReturnType(@TypeOf(handlers), Body) {
    const HandlersType = @TypeOf(handlers);
    comptime assertHandlerBundleShape(HandlersType);
    comptime rejectUnsupportedShippedWith(Body, caller, caller_source_override);

    var handler_state = handlers;
    var outputs = std.mem.zeroInit(OutputBundleType(HandlersType), .{});
    if (comptime @hasDecl(Body, "source_path") and @hasDecl(Body, "entry_symbol") and @hasDecl(Body, "ReturnType")) {
        const compiled = tryNamedCompiledWith(HandlersType, Body, runtime, &handler_state, &outputs).?;
        const value = try compiled;
        return .{
            .outputs = outputs,
            .value = value,
        };
    }
    if (caller_source_override != null and comptime anonymousBodyCompilable(caller, Body, caller_source_override)) {
        const compiled = tryCallerOwnedCompiledWith(HandlersType, Body, caller, caller_source_override, runtime, &handler_state, &outputs).?;
        const value = try compiled;
        return .{
            .outputs = outputs,
            .value = value,
        };
    }
    const value = try runChainCollected(HandlersType, Body, 0, struct {}, caller, .{
        .runtime = runtime,
        .handlers_ptr = &handler_state,
        .eff_value = .{},
        .outputs_ptr = &outputs,
        .caller_file = caller.file,
        .caller_line = caller.line,
        .caller_column = caller.column,
    });
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
    return withAt(runtime, handlers, Body, @src(), null);
}

/// Run one lexical effect bundle while the caller explicitly supplies the source location used for caller-owned compilation.
pub fn withCallerSource(
    comptime caller: std.builtin.SourceLocation,
    runtime: *lowered_machine.Runtime,
    handlers: anytype,
    comptime Body: type,
) WithFnReturnType(@TypeOf(handlers), Body) {
    return withAt(runtime, handlers, Body, caller, null);
}

/// Run one lexical effect bundle while the caller explicitly supplies both source location and source bytes for caller-owned compilation.
pub fn withCallerSourceAndContent(
    comptime caller: std.builtin.SourceLocation,
    comptime caller_source: [:0]const u8,
    runtime: *lowered_machine.Runtime,
    handlers: anytype,
    comptime Body: type,
) WithFnReturnType(@TypeOf(handlers), Body) {
    return withAt(runtime, handlers, Body, caller, caller_source);
}

/// Run one lexical effect bundle through an explicit caller-owned source witness surface.
pub fn withOwnedSource(
    comptime caller: std.builtin.SourceLocation,
    comptime caller_source: [:0]const u8,
    comptime witness: OwnedSourceWitness,
    runtime: *lowered_machine.Runtime,
    handlers: anytype,
    comptime Body: type,
) WithFnReturnType(@TypeOf(handlers), Body) {
    const HandlersType = @TypeOf(handlers);
    comptime assertHandlerBundleShape(HandlersType);

    var handler_state = handlers;
    var outputs = std.mem.zeroInit(OutputBundleType(HandlersType), .{});
    const value = try tryOwnedSourceCompiledWith(
        HandlersType,
        Body,
        caller,
        caller_source,
        witness,
        runtime,
        &handler_state,
        &outputs,
    );
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

fn compiledPlanLifecycleProbeAdvance(eff: anytype) anyerror!void {
    const before = try eff.state.get();
    try eff.state.set(before + 1);
    try eff.writer.tell("queued");
}

/// Drive the compiled lexical lifecycle probe through one state increment and one writer output.
pub fn compiledPlanLifecycleProbeBody(eff: anytype) anyerror![]const u8 {
    try compiledPlanLifecycleProbeAdvance(eff);
    return "done";
}

test "compiled lexical plans preserve binding-schema lifecycle metadata in ProgramPlan" {
    const state = @import("effect/state.zig");
    const writer = @import("effect/writer.zig");

    const Handlers = struct {
        state: state.LexicalDescriptor(i32, error{}),
        writer: writer.LexicalDescriptor([]const u8, error{}),
    };

    const lowered_program = try public_lowering.lowerOpenRowAt(
        "src/with_api.zig",
        .{
            .label = "with_api.compiled_plan_lifecycle_probe",
            .entry_symbol = "compiledPlanLifecycleProbeBody",
            .ValueType = []const u8,
            .row = lexical_bundle_schema.rowForHandlers(Handlers),
            .outputs = lexical_bundle_schema.outputsForHandlers(Handlers),
        },
    );
    const enriched_plan = public_lowering.enrichOpenRowPlan(
        "with_api.compiled_plan_lifecycle_probe",
        lowered_program,
        lexicalBindingSchemasValue(Handlers),
    );

    try std.testing.expectEqual(.state_cell, enriched_plan.requirements[0].lifecycle_tag);
    try std.testing.expectEqual(.final_state, enriched_plan.requirements[0].output_tag);
    try std.testing.expectEqual(.writer_accumulator, enriched_plan.requirements[1].lifecycle_tag);
    try std.testing.expectEqual(.accumulator, enriched_plan.requirements[1].output_tag);
}
