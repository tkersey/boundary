const builtin = @import("builtin");
const family = @import("effect/family.zig");
const frontend = @import("frontend_support");
const lexical_bundle_schema = @import("internal/lexical_bundle_schema.zig");
const lexical_executable_bundle = @import("internal/lexical_executable_bundle.zig");
const lowered_machine = @import("lowered_machine");
const prompt_contract = @import("prompt_contract_support");
const public_lowering = @import("public_lowering");
const source_graph_embed = @import("source_graph_embed");
const source_graph_engine = @import("source_graph_engine");
const std = @import("std");

/// One descriptor result: final descriptor output plus body answer.
pub fn DescriptorResult(comptime Output: type, comptime Answer: type) type {
    return struct {
        output: Output,
        value: Answer,
    };
}

fn NamedBodyFunctionType(comptime body_fn: anytype) type {
    const BodyFn = @TypeOf(body_fn);
    return switch (@typeInfo(BodyFn)) {
        .pointer => |pointer| if (@typeInfo(pointer.child) == .@"fn")
            pointer.child
        else
            @compileError("shift.NamedBody body_fn must be callable"),
        .@"fn" => BodyFn,
        else => @compileError("shift.NamedBody body_fn must be callable"),
    };
}

fn namedBodyFunctionProvenance(comptime body_fn: anytype) ?[]const u8 {
    comptime {
        @setEvalBranchQuota(4_000);
    }
    const normalized_body_fn = switch (@typeInfo(@TypeOf(body_fn))) {
        .pointer => body_fn.*,
        else => body_fn,
    };
    const wrapped_name = @typeName(@TypeOf(.{&normalized_body_fn}));
    const prefix = " = &";
    const start = std.mem.indexOf(u8, wrapped_name, prefix) orelse return null;
    const name_start = start + prefix.len;
    const end = std.mem.indexOfPos(u8, wrapped_name, name_start, " }") orelse return null;
    return wrapped_name[name_start..end];
}

fn namedBodyFunctionName(comptime body_fn: anytype) ?[]const u8 {
    const provenance = namedBodyFunctionProvenance(body_fn) orelse return null;
    const name_start = (std.mem.lastIndexOfScalar(u8, provenance, '.') orelse return null) + 1;
    return provenance[name_start..];
}

fn namedBodySourceModulePath(comptime source_path_value: []const u8) []const u8 {
    const without_ext = if (std.mem.endsWith(u8, source_path_value, ".zig"))
        source_path_value[0 .. source_path_value.len - ".zig".len]
    else
        source_path_value;
    const normalized = if (std.mem.startsWith(u8, without_ext, "./") or std.mem.startsWith(u8, without_ext, ".\\"))
        without_ext[2..]
    else
        without_ext;

    const dotted = comptime blk: {
        var buffer: [normalized.len]u8 = undefined;
        for (normalized, 0..) |char, idx| {
            buffer[idx] = switch (char) {
                '/', '\\' => '.',
                else => char,
            };
        }
        break :blk buffer;
    };
    return dotted[0..];
}

fn namedBodyModulePathMatchesSourcePath(
    comptime module_path: []const u8,
    comptime source_path_value: []const u8,
) bool {
    const full_module_path = namedBodySourceModulePath(source_path_value);
    const module_stem = std.fs.path.stem(source_path_value);
    if (std.mem.eql(u8, module_path, full_module_path)) return true;
    if (std.mem.eql(u8, module_path, module_stem)) return true;
    if (std.mem.indexOfScalar(u8, full_module_path, '.') == null) return false;
    return std.mem.endsWith(u8, module_path, "." ++ full_module_path);
}

fn validateNamedBodyRepoIdentity(
    comptime source_path_value: []const u8,
    comptime entry_symbol_value: []const u8,
    comptime body_fn: anytype,
) void {
    const provenance = namedBodyFunctionProvenance(body_fn) orelse
        @compileError("shift.NamedBody body_fn must be a named function");
    const last_dot = std.mem.lastIndexOfScalar(u8, provenance, '.') orelse
        @compileError("shift.NamedBody body_fn must be a named function");
    const module_path = provenance[0..last_dot];
    if (!namedBodyModulePathMatchesSourcePath(module_path, source_path_value)) {
        @compileError("shift.NamedBody source_path must match the supplied body function provenance");
    }

    const owned_repo_path = source_graph_embed.ownedRepoPath(source_path_value) orelse return;
    comptime {
        @setEvalBranchQuota(2_000_000);
    }
    const source = source_graph_embed.embeddedSource(owned_repo_path);
    const graph = source_graph_engine.analyzeComptime(source, .{
        .entry_symbol = null,
        .reject_recursive_helpers = false,
        .reject_indirect_effect_access = false,
        .reject_malformed_statements = false,
    }) catch @compileError("shift.NamedBody source_path must export the supplied entry_symbol");

    inline for (graph.functions) |function| {
        if (std.mem.eql(u8, function.name, entry_symbol_value)) break;
    } else {
        @compileError("shift.NamedBody source_path must export the supplied entry_symbol");
    }
}

fn namedCompiledLexicalPlan(comptime HandlersType: type, comptime Body: type) ?public_lowering.ProgramPlan {
    if (!isNamedBodyDescriptor(Body)) return null;
    const lowered_program = public_lowering.maybeLowerAt(Body.source_path, .{
        .label = "shift.with named lexical body",
        .entry_symbol = Body.entry_symbol,
        .ValueType = NamedBodyAnswerType(Body),
        .row = lexical_bundle_schema.rowForHandlers(HandlersType),
        .outputs = lexical_bundle_schema.outputsForHandlers(HandlersType),
    }) orelse return null;
    return comptime public_lowering.enrichOpenRowPlan(
        "shift.with named lexical body",
        lowered_program,
        lexicalBindingSchemasValue(HandlersType),
    );
}

fn namedBodyAllowsTestFallback(comptime Body: type) bool {
    const owned_repo_path = source_graph_embed.ownedRepoPath(Body.source_path) orelse return false;
    return std.mem.startsWith(u8, owned_repo_path, "test/");
}

fn validateNamedBodyDeclaration(
    comptime source_path_value: []const u8,
    comptime entry_symbol_value: []const u8,
    comptime ReturnTypeValue: type,
    comptime body_fn: anytype,
) void {
    const FnType = NamedBodyFunctionType(body_fn);
    const ActualReturnType = @typeInfo(FnType).@"fn".return_type.?;
    if (ActualReturnType != ReturnTypeValue) {
        @compileError("shift.NamedBody ReturnType must match the supplied body function");
    }
    const function_name = namedBodyFunctionName(body_fn) orelse
        @compileError("shift.NamedBody body_fn must be a named function");
    if (!std.mem.eql(u8, function_name, entry_symbol_value)) {
        @compileError("shift.NamedBody entry_symbol must match the supplied body function name");
    }
    validateNamedBodyRepoIdentity(source_path_value, entry_symbol_value, body_fn);
}

fn NamedBodyAnswerType(comptime Body: type) type {
    const ReturnType = Body.ReturnType;
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.payload,
        else => ReturnType,
    };
}

fn isNamedBodyDescriptor(comptime Body: type) bool {
    return switch (@typeInfo(Body)) {
        .pointer, .@"fn" => false,
        else => @hasDecl(Body, "is_named_body") and
            @hasDecl(Body, "source_path") and
            @hasDecl(Body, "entry_symbol") and
            @hasDecl(Body, "ReturnType"),
    };
}

/// Named lexical body reference used as the canonical compiled `shift.withAt(@src(), ...)` surface.
pub fn NamedBody(
    comptime source_path_value: []const u8,
    comptime entry_symbol_value: []const u8,
    comptime ReturnTypeValue: type,
    comptime body_fn: anytype,
) type {
    comptime validateNamedBodyDeclaration(source_path_value, entry_symbol_value, ReturnTypeValue, body_fn);
    return struct {
        /// Marker used to distinguish canonical NamedBody descriptors from ordinary inline bodies.
        pub const is_named_body = true;
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

/// Canonical lexical outputs plus body answer returned from `shift.withAt(@src(), ...)`.
pub fn WithResult(comptime HandlersType: type, comptime Answer: type) type {
    return struct {
        outputs: OutputBundleType(HandlersType),
        value: Answer,
    };
}

/// Explicit lexical rebinding packet threaded through `shift.withAt(@src(), ...)` continuations.
pub fn LexicalState(comptime HandlersType: type, comptime EffType: type, comptime caller_source_value: std.builtin.SourceLocation) type {
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
    if (comptime isNamedBodyDescriptor(Body)) return @TypeOf(Body.body_fn_ref);
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
    if (isNamedBodyDescriptor(Body)) return Body.ReturnType;
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
    if (caller_source_override) |caller_source| return caller_source;
    const canonical_caller = comptime source_graph_embed.canonicalCallerLocation(caller);
    if (source_graph_embed.ownedRepoPath(canonical_caller.file)) |repo_path| {
        return source_graph_embed.embeddedSource(repo_path);
    }
    return @embedFile(canonical_caller.file);
}

const CallerOwnedCompilationKind = enum {
    explicit_location,
    explicit_location_and_content,
    none,
    owned_source,
};

fn callerOwnedCallName(comptime kind: CallerOwnedCompilationKind) ?[]const u8 {
    return switch (kind) {
        .none => null,
        .explicit_location => "withCallerSource",
        .explicit_location_and_content => "withCallerSourceAndContent",
        .owned_source => "withOwnedSource",
    };
}

fn callerOwnedBodyArgIndex(comptime kind: CallerOwnedCompilationKind) ?usize {
    return switch (kind) {
        .none => null,
        .explicit_location => 3,
        .explicit_location_and_content => 4,
        .owned_source => 5,
    };
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
    comptime caller_owned_kind: CallerOwnedCompilationKind,
) ?struct { start: usize, end: usize } {
    comptime {
        @setEvalBranchQuota(2_000_000);
    }
    const call_name = comptime callerOwnedCallName(caller_owned_kind) orelse return null;
    const body_arg_index = comptime callerOwnedBodyArgIndex(caller_owned_kind).?;
    const source = comptime callerSourceBytes(caller, caller_source_override);
    const target_offset = comptime offsetForLineColumn(source, caller.line, caller.column) orelse return null;
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

fn anonymousBodyEntryName(caller: std.builtin.SourceLocation) [:0]const u8 {
    const entry_name = std.fmt.comptimePrint(
        "__shift_with_entry_l{d}_c{d}\x00",
        .{ caller.line, caller.column },
    );
    return entry_name[0 .. entry_name.len - 1 :0];
}

fn extractedAnonymousEntrySource(
    comptime expr_source: []const u8,
    comptime method_name: []const u8,
    comptime entry_name: []const u8,
) ?[]const u8 {
    comptime {
        @setEvalBranchQuota(2_000_000);
    }

    const expr_source_sentinel = std.fmt.comptimePrint("{s}\x00", .{expr_source});
    var tokenizer = std.zig.Tokenizer.init(expr_source_sentinel[0..expr_source.len :0]);
    var brace_depth: usize = 0;
    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) return null;
        if (isIgnorableCallsiteToken(token.tag)) continue;
        switch (token.tag) {
            .l_brace => {
                brace_depth += 1;
                continue;
            },
            .r_brace => {
                if (brace_depth == 0) return null;
                brace_depth -= 1;
                continue;
            },
            else => {},
        }
        if (token.tag != .keyword_fn or brace_depth != 1) continue;

        var name_token = tokenizer.next();
        while (isIgnorableCallsiteToken(name_token.tag)) : (name_token = tokenizer.next()) {}
        if (name_token.tag != .identifier) continue;
        if (!std.mem.eql(u8, expr_source[name_token.loc.start..name_token.loc.end], method_name)) continue;

        var body_depth: usize = 0;
        var function_end: ?usize = null;
        while (function_end == null) {
            const next = tokenizer.next();
            if (next.tag == .eof) return null;
            if (isIgnorableCallsiteToken(next.tag)) continue;
            switch (next.tag) {
                .l_brace => body_depth += 1,
                .r_brace => {
                    if (body_depth == 0) return null;
                    body_depth -= 1;
                    if (body_depth == 0) function_end = next.loc.end;
                },
                else => {},
            }
        }

        const function_source = expr_source[token.loc.start..function_end.?];
        const name_offset = name_token.loc.start - token.loc.start;
        const name_end = name_token.loc.end - token.loc.start;
        return std.fmt.comptimePrint(
            "{s}{s}{s}",
            .{
                function_source[0..name_offset],
                entry_name,
                function_source[name_end..],
            },
        );
    }
}

fn anonymousBodySyntheticSourceWithEntry(
    comptime caller: std.builtin.SourceLocation,
    comptime Body: type,
    comptime caller_source_override: ?[:0]const u8,
    comptime caller_owned_kind: CallerOwnedCompilationKind,
    comptime entry_name: []const u8,
) ?[:0]const u8 {
    const method_name = comptime anonymousBodyMethodName(Body) orelse return null;
    const expr_bounds = comptime anonymousBodyExprBounds(caller, caller_source_override, caller_owned_kind) orelse return null;
    const caller_source = comptime callerSourceBytes(caller, caller_source_override);
    const expr_len = comptime expr_bounds.end - expr_bounds.start;
    const expr_source = comptime blk: {
        var buffer: [expr_len]u8 = undefined;
        for (0..expr_len) |index| {
            buffer[index] = caller_source[expr_bounds.start + index];
        }
        break :blk buffer[0..];
    };
    const entry_source = comptime extractedAnonymousEntrySource(expr_source, method_name, entry_name) orelse return null;
    return std.fmt.comptimePrint(
        "{s}\n{s}\n",
        .{ caller_source, entry_source },
    );
}

fn anonymousBodySyntheticSource(
    comptime caller: std.builtin.SourceLocation,
    comptime Body: type,
    comptime caller_source_override: ?[:0]const u8,
    comptime caller_owned_kind: CallerOwnedCompilationKind,
) ?[:0]const u8 {
    return anonymousBodySyntheticSourceWithEntry(
        caller,
        Body,
        caller_source_override,
        caller_owned_kind,
        anonymousBodyEntryName(caller),
    );
}

fn witnessSyntheticSource(
    comptime caller_source: [:0]const u8,
    comptime witness: OwnedSourceWitness,
) ?[:0]const u8 {
    const body_source = witness.body_source orelse return null;
    return std.fmt.comptimePrint(
        "{s}\n{s}\n",
        .{ caller_source, body_source },
    );
}

fn ownedSourceSyntheticSource(
    comptime Body: type,
    comptime caller: std.builtin.SourceLocation,
    comptime caller_source: [:0]const u8,
    comptime witness: OwnedSourceWitness,
    comptime entry_symbol: []const u8,
) ?[:0]const u8 {
    if (isNamedBodyDescriptor(Body)) return null;
    if (witness.body_source != null) return witnessSyntheticSource(caller_source, witness);
    return anonymousBodySyntheticSourceWithEntry(caller, Body, caller_source, .owned_source, entry_symbol);
}

fn sourcePathAgreesWithCaller(
    comptime caller: std.builtin.SourceLocation,
    comptime source_path: []const u8,
) bool {
    if (std.mem.eql(u8, caller.file, source_path)) return true;

    const caller_repo_path = comptime source_graph_embed.ownedRepoPath(caller.file) orelse return false;
    const source_repo_path = comptime source_graph_embed.ownedRepoPath(source_path) orelse return false;
    return std.mem.eql(u8, caller_repo_path, source_repo_path);
}

fn rejectForgedOwnedSourceSyntheticPath(
    comptime Body: type,
    comptime caller: std.builtin.SourceLocation,
    comptime witness: OwnedSourceWitness,
) void {
    if (isNamedBodyDescriptor(Body)) return;
    if (@hasDecl(Body, "source_path")) {
        @compileError("shift.withOwnedSource anonymous bodies must not declare source_path; use witness.source_path or shift.NamedBody(...)");
    }
    if (@hasDecl(Body, "entry_symbol")) {
        @compileError("shift.withOwnedSource anonymous bodies must not declare entry_symbol; use witness.entry_symbol/body_method_name or shift.NamedBody(...)");
    }
    const source_path = witness.source_path orelse return;
    if (sourcePathAgreesWithCaller(caller, source_path)) return;
    @compileError("shift.withOwnedSource anonymous and body-source witnesses require witness.source_path to agree with the caller source");
}

fn ownedSourceLocation(
    comptime caller: std.builtin.SourceLocation,
    comptime source_path: []const u8,
) std.builtin.SourceLocation {
    if (std.mem.eql(u8, caller.file, source_path)) return caller;
    const source_path_sentinel = std.fmt.comptimePrint("{s}\x00", .{source_path});
    return .{
        .module = caller.module,
        .file = source_path_sentinel[0..source_path.len :0],
        .line = caller.line,
        .column = caller.column,
        .fn_name = caller.fn_name,
    };
}

test "owned source witness appended body stays visible to the source graph" {
    const synthetic_source = witnessSyntheticSource(
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    _ = shift;
        \\    _ = std;
        \\}
    ,
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

test "caller-owned anonymous body routing stays explicit for withCallerSource" {
    const caller = std.builtin.SourceLocation{
        .module = @src().module,
        .file = "/tmp/caller_owned_routing_probe.zig",
        .line = 7,
        .column = 6,
        .fn_name = "probe",
    };
    const caller_source =
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn probe() !void {
        \\    const caller = @src();
        \\    _ = try shift.withCallerSource(caller, undefined, .{}, struct {
        \\        pub fn body(eff: anytype) anyerror!void { _ = eff; }
        \\    });
        \\}
    ;
    const probe_body = struct {
        fn body(eff: anytype) anyerror!void {
            _ = eff;
        }
    };

    try std.testing.expect(comptime anonymousBodyCompilable(
        struct {},
        caller,
        probe_body,
        caller_source,
        .explicit_location,
    ));
    try std.testing.expect(!comptime anonymousBodyCompilable(
        struct {},
        caller,
        probe_body,
        caller_source,
        .none,
    ));
}

test "caller-owned anonymous body routing stays explicit for withOwnedSource" {
    const caller = std.builtin.SourceLocation{
        .module = @src().module,
        .file = "/tmp/owned_source_routing_probe.zig",
        .line = 7,
        .column = 6,
        .fn_name = "probe",
    };
    const caller_source =
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn probe() !void {
        \\    const caller = @src();
        \\    _ = try shift.withOwnedSource(caller, @embedFile(caller.file), .{}, undefined, .{}, struct {
        \\        pub fn body(eff: anytype) anyerror!void { _ = eff; }
        \\    });
        \\}
    ;
    const probe_body = struct {
        fn body(eff: anytype) anyerror!void {
            _ = eff;
        }
    };

    try std.testing.expect(comptime anonymousBodyCompilable(
        struct {},
        caller,
        probe_body,
        caller_source,
        .owned_source,
    ));
}

test "caller-owned stateful anonymous lowering stays explicit for withOwnedSource" {
    const state = @import("effect/state.zig");
    const caller = std.builtin.SourceLocation{
        .module = @src().module,
        .file = "/tmp/owned_source_state_probe.zig",
        .line = 7,
        .column = 6,
        .fn_name = "probe",
    };
    const caller_source =
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn probe() !void {
        \\    const caller = @src();
        \\    _ = try shift.withOwnedSource(caller, @embedFile(caller.file), .{}, undefined, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, struct {
        \\        pub fn body(eff: anytype) anyerror!i32 {
        \\            const before = try eff.state.get();
        \\            try eff.state.set(before + 1);
        \\            return try eff.state.get();
        \\        }
        \\    });
        \\}
    ;
    const probe_body = struct {
        fn body(eff: anytype) anyerror!i32 {
            const before = try eff.state.get();
            try eff.state.set(before + 1);
            return try eff.state.get();
        }
    };
    const Handlers = @TypeOf(.{
        .state = state.use(@as(i32, 0)),
    });

    try std.testing.expect(comptime anonymousBodyCompilable(
        Handlers,
        caller,
        probe_body,
        caller_source,
        .owned_source,
    ));
}

test "relative caller-owned stateful anonymous lowering stays explicit for withOwnedSource" {
    const state = @import("effect/state.zig");
    const caller = std.builtin.SourceLocation{
        .module = @src().module,
        .file = "main.zig",
        .line = 5,
        .column = 34,
        .fn_name = "probe",
    };
    const caller_source =
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn probe() !void {
        \\    _ = try shift.withOwnedSource(@src(), @embedFile(@src().file), .{}, undefined, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, struct {
        \\        pub fn body(eff: anytype) anyerror!i32 {
        \\            const before = try eff.state.get();
        \\            try eff.state.set(before + 1);
        \\            return try eff.state.get();
        \\        }
        \\    });
        \\}
    ;
    const probe_body = struct {
        fn body(eff: anytype) anyerror!i32 {
            const before = try eff.state.get();
            try eff.state.set(before + 1);
            return try eff.state.get();
        }
    };
    const Handlers = @TypeOf(.{
        .state = state.use(@as(i32, 0)),
    });

    try std.testing.expect(comptime anonymousBodyCompilable(
        Handlers,
        caller,
        probe_body,
        caller_source,
        .owned_source,
    ));
}

test "relative inline @src caller-owned lowering stays explicit for withOwnedSource" {
    const state = @import("effect/state.zig");
    const caller = std.builtin.SourceLocation{
        .module = @src().module,
        .file = "main.zig",
        .line = 7,
        .column = 46,
        .fn_name = "main",
    };
    const caller_source =
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    const result = try shift.withOwnedSource(@src(), @embedFile(@src().file), .{}, &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, struct {
        \\        pub fn body(eff: anytype) anyerror!i32 {
        \\            const before = try eff.state.get();
        \\            try eff.state.set(before + 1);
        \\            return try eff.state.get();
        \\        }
        \\    });
        \\    if (result.value != 1) return error.UnexpectedResult;
        \\}
    ;
    const probe_body = struct {
        fn body(eff: anytype) anyerror!i32 {
            const before = try eff.state.get();
            try eff.state.set(before + 1);
            return try eff.state.get();
        }
    };
    const Handlers = @TypeOf(.{
        .state = state.use(@as(i32, 0)),
    });

    try std.testing.expect(comptime anonymousBodyCompilable(
        Handlers,
        caller,
        probe_body,
        caller_source,
        .owned_source,
    ));
}

test "caller-owned anonymous lowering rejects unsupported retained-body shapes" {
    const caller = std.builtin.SourceLocation{
        .module = @src().module,
        .file = "/tmp/caller_owned_unsupported_probe.zig",
        .line = 7,
        .column = 6,
        .fn_name = "probe",
    };
    const caller_source =
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn probe() !void {
        \\    const caller = @src();
        \\    _ = try shift.withCallerSource(caller, undefined, .{}, struct {
        \\        pub fn body(_: anytype) anyerror!i32 {
        \\            var total: i32 = 0;
        \\            while (total < 1) : (total += 1) {}
        \\            return total;
        \\        }
        \\    });
        \\}
    ;
    const unsupported_body = struct {
        /// Keep this body outside the retained lowering subset via a `while` loop.
        pub fn body(_: anytype) anyerror!i32 {
            var total: i32 = 0;
            while (total < 1) : (total += 1) {}
            return total;
        }
    };

    try std.testing.expect(!comptime anonymousBodyCompilable(
        struct {},
        caller,
        unsupported_body,
        caller_source,
        .explicit_location,
    ));
}

fn namedBodyValidationExpected(_: anytype) anyerror!i32 {
    return 1;
}

fn namedBodyValidationOther(_: anytype) anyerror!i32 {
    return 2;
}

const named_body_duplicate_support = @import("named_body_duplicate_support.zig");

test "NamedBody extracts and validates the supplied function name" {
    try std.testing.expectEqualStrings(
        "with_api.namedBodyValidationExpected",
        namedBodyFunctionProvenance(namedBodyValidationExpected).?,
    );
    try std.testing.expectEqualStrings(
        "namedBodyValidationExpected",
        namedBodyFunctionName(namedBodyValidationExpected).?,
    );
    try std.testing.expectEqualStrings(
        "with_api.namedBodyValidationExpected",
        namedBodyFunctionProvenance(&namedBodyValidationExpected).?,
    );
    try std.testing.expectEqualStrings(
        "namedBodyValidationExpected",
        namedBodyFunctionName(&namedBodyValidationExpected).?,
    );
    try std.testing.expectEqualStrings(
        "namedBodyValidationOther",
        namedBodyFunctionName(namedBodyValidationOther).?,
    );
    _ = NamedBody(
        "src/with_api.zig",
        "namedBodyValidationExpected",
        anyerror!i32,
        namedBodyValidationExpected,
    );
    _ = NamedBody(
        "src/with_api.zig",
        "namedBodyValidationExpected",
        anyerror!i32,
        &namedBodyValidationExpected,
    );
}

test "NamedBody allows duplicate entry symbols in different repo files" {
    const descriptor = NamedBody(
        "src/named_body_duplicate_support.zig",
        "namedBodyValidationExpected",
        anyerror!i32,
        named_body_duplicate_support.namedBodyValidationExpected,
    );
    try std.testing.expectEqualStrings(
        "named_body_duplicate_support.namedBodyValidationExpected",
        namedBodyFunctionProvenance(named_body_duplicate_support.namedBodyValidationExpected).?,
    );
    try std.testing.expectEqualStrings("src/named_body_duplicate_support.zig", descriptor.source_path);
    try std.testing.expectEqualStrings("namedBodyValidationExpected", descriptor.entry_symbol);
}

test "NamedBody provenance matching keeps directory segments distinct" {
    try std.testing.expect(namedBodyModulePathMatchesSourcePath("a.entry", "a/entry.zig"));
    try std.testing.expect(!namedBodyModulePathMatchesSourcePath("b.entry", "a/entry.zig"));
    try std.testing.expect(namedBodyModulePathMatchesSourcePath("with_api", "src/with_api.zig"));
    try std.testing.expect(namedBodyModulePathMatchesSourcePath("pkg.src.with_api", "src/with_api.zig"));
    try std.testing.expect(namedBodyModulePathMatchesSourcePath("main", "main.zig"));
    try std.testing.expect(!namedBodyModulePathMatchesSourcePath("nested.main", "main.zig"));
}

test "withOwnedSource keeps repo-owned NamedBody identity when explicit witness disagrees" {
    const named_body_identity_primary = @import("named_body_identity_primary_support.zig");
    const state = @import("effect/state.zig");

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const named = NamedBody(
        "src/named_body_identity_primary_support.zig",
        "namedBodyIdentity",
        anyerror!i32,
        named_body_identity_primary.namedBodyIdentity,
    );
    const result = try withOwnedSource(@src(), @embedFile("named_body_identity_secondary_support.zig"), .{
        .source_path = "src/named_body_identity_secondary_support.zig",
        .entry_symbol = "witnessOverride",
    }, &runtime, .{
        .state = state.use(@as(i32, 0)),
    }, named);

    try std.testing.expectEqual(@as(i32, 1), result.value);
    try std.testing.expectEqual(@as(i32, 1), result.outputs.state);
}

test "withCallerSource runs anonymous lexical bodies through the public API" {
    const state = @import("effect/state.zig");

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try withCallerSource(@src(), &runtime, .{
        .state = state.use(@as(i32, 0)),
    }, struct {
        fn body(eff: anytype) anyerror!i32 {
            const before = try eff.state.get();
            try eff.state.set(before + 1);
            return try eff.state.get();
        }
    });

    try std.testing.expectEqual(@as(i32, 1), result.value);
    try std.testing.expectEqual(@as(i32, 1), result.outputs.state);
}

test "withOwnedSource runs anonymous lexical bodies through the public API" {
    const state = @import("effect/state.zig");

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try withOwnedSource(@src(), @embedFile(@src().file), .{}, &runtime, .{
        .state = state.use(@as(i32, 0)),
    }, struct {
        fn body(eff: anytype) anyerror!i32 {
            const before = try eff.state.get();
            try eff.state.set(before + 1);
            return try eff.state.get();
        }
    });

    try std.testing.expectEqual(@as(i32, 1), result.value);
    try std.testing.expectEqual(@as(i32, 1), result.outputs.state);
}

test "withOwnedSource runs pub anonymous lexical bodies through the public API" {
    const state = @import("effect/state.zig");

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try withOwnedSource(@src(), @embedFile(@src().file), .{}, &runtime, .{
        .state = state.use(@as(i32, 0)),
    }, struct {
        fn body(eff: anytype) anyerror!i32 {
            const before = try eff.state.get();
            try eff.state.set(before + 1);
            return try eff.state.get();
        }
    });

    try std.testing.expectEqual(@as(i32, 1), result.value);
    try std.testing.expectEqual(@as(i32, 1), result.outputs.state);
}

test "withOwnedSource chooses the top-level anonymous body over nested same-named helpers" {
    const state = @import("effect/state.zig");

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try withOwnedSource(@src(), @embedFile(@src().file), .{}, &runtime, .{
        .state = state.use(@as(i32, 0)),
    }, struct {
        const helper = struct {
            /// Prove nested same-named helpers do not steal the top-level anonymous body.
            pub fn body(_: anytype) anyerror!i32 {
                return 99;
            }
        };

        /// Use the top-level anonymous body even when a nested helper exports the same symbol name.
        pub fn body(eff: anytype) anyerror!i32 {
            const before = try eff.state.get();
            try eff.state.set(before + 1);
            return try eff.state.get();
        }
    });

    try std.testing.expectEqual(@as(i32, 1), result.value);
    try std.testing.expectEqual(@as(i32, 1), result.outputs.state);
}

test "withCallerSource ignores unrelated ReturnType decls on non-NamedBody bodies" {
    const state = @import("effect/state.zig");

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try withCallerSource(@src(), &runtime, .{
        .state = state.use(@as(i32, 0)),
    }, struct {
        /// Unrelated decl that must not affect ordinary body return inference.
        pub const ReturnType = []const u8;

        fn body(eff: anytype) anyerror!i32 {
            const before = try eff.state.get();
            try eff.state.set(before + 1);
            return try eff.state.get();
        }
    });

    try std.testing.expectEqual(@as(i32, 1), result.value);
    try std.testing.expectEqual(@as(i32, 1), result.outputs.state);
}

test "withCallerSource preserves lexical continuation caller provenance through optional resume" {
    const choice = @import("effect/choice.zig");
    const optional = @import("effect/optional.zig");

    const resume_policy = struct {
        /// Resume the optional continuation with the canonical witness value.
        pub fn resumeOrReturn() choice.Decision(i32, []const u8) {
            return choice.Decision(i32, []const u8).resumeWith(41);
        }

        /// Preserve the resumed answer after the optional continuation completes.
        pub fn afterResume(answer: []const u8) []const u8 {
            return answer;
        }
    };

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try withCallerSource(@src(), &runtime, .{
        .optional = optional.use(i32, resume_policy),
    }, struct {
        fn body(eff: anytype) anyerror![]const u8 {
            return try eff.optional.request(struct {
                /// Complete the resumed optional continuation with the expected final answer.
                pub fn apply(value: i32, _: anytype) anyerror![]const u8 {
                    if (value != 41) unreachable;
                    return "answer=42";
                }
            });
        }
    });

    try std.testing.expectEqualStrings("answer=42", result.value);
}

test "with preserves caller provenance through the legacy lexical path" {
    const state = @import("effect/state.zig");

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try with(&runtime, .{
        .state = state.use(@as(i32, 0)),
    }, struct {
        fn body(eff: anytype) anyerror![]const u8 {
            return @TypeOf(eff.state.ctx.?.*).caller_source.?.file;
        }
    });

    try std.testing.expectEqualStrings(@src().file, result.value);
}

test "with preserves caller provenance through optional continuation resume" {
    const choice = @import("effect/choice.zig");
    const optional = @import("effect/optional.zig");
    const state = @import("effect/state.zig");

    const resume_policy = struct {
        /// Resume the optional continuation with the canonical witness value.
        pub fn resumeOrReturn() choice.Decision(i32, []const u8) {
            return choice.Decision(i32, []const u8).resumeWith(41);
        }

        /// Preserve the resumed answer after the optional continuation completes.
        pub fn afterResume(answer: []const u8) []const u8 {
            return answer;
        }
    };

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try withAt(@src(), &runtime, .{
        .optional = optional.use(i32, resume_policy),
        .state = state.use(@as(i32, 0)),
    }, struct {
        fn body(eff: anytype) anyerror![]const u8 {
            return try eff.optional.request(struct {
                /// Return the caller-owned source file observed through the resumed continuation handle set.
                pub fn apply(value: i32, resumed_eff: anytype) anyerror![]const u8 {
                    if (value != 41) unreachable;
                    return @TypeOf(resumed_eff.state.ctx.?.*).caller_source.?.file;
                }
            });
        }
    });

    try std.testing.expectEqualStrings(@src().file, result.value);
}

// zlinter-disable max_positional_args - this rejection seam keeps caller provenance, compiled plan state, and ownership policy explicit at the fail-closed guard.
fn rejectUnsupportedShippedWith(
    comptime HandlersType: type,
    comptime Body: type,
    comptime named_compiled_plan: ?public_lowering.ProgramPlan,
    comptime caller: std.builtin.SourceLocation,
    comptime caller_source_override: ?[:0]const u8,
    comptime caller_owned_kind: CallerOwnedCompilationKind,
) void {
    if (isNamedBodyDescriptor(Body)) {
        if (named_compiled_plan != null) return;
        if (builtin.is_test and namedBodyAllowsTestFallback(Body)) return;
        @compileError("shift.NamedBody execution must stay within the retained compiled lexical subset");
    }
    if (builtin.is_test) return;
    if (caller_owned_kind == .none) return;
    if (callerOwnedCompilationSupported(HandlersType, Body, caller, caller_source_override, caller_owned_kind)) return;
    @compileError("shift.with shipped execution currently requires either shift.NamedBody(...) or a caller-owned lexical body shape that can be compiled from the callsite");
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

    if (comptime isNamedBodyDescriptor(Body)) {
        if (@typeInfo(ReturnType) == .error_union) {
            return Body.body_fn_ref(eff) catch |err| return @errorCast(err);
        }
        return Body.body_fn_ref(eff);
    }

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

fn exactContextCallerSource(comptime ContextPtrType: type) std.builtin.SourceLocation {
    return family.contextCallerSource(ContextPtrType);
}

fn CollectedRunState(comptime HandlersType: type, comptime EffType: type, comptime caller: std.builtin.SourceLocation) type {
    return LexicalState(HandlersType, EffType, caller);
}

fn ChoiceRunState(comptime HandlersType: type, comptime EffType: type, comptime caller: std.builtin.SourceLocation) type {
    return LexicalState(HandlersType, EffType, caller);
}

fn descriptorRunContext(
    comptime caller: std.builtin.SourceLocation,
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

// zlinter-disable max_positional_args - this compiled NamedBody seam keeps runtime, handler bundle, outputs, and the precomputed ProgramPlan explicit.
fn tryNamedCompiledWith(
    comptime HandlersType: type,
    comptime Body: type,
    runtime: *lowered_machine.Runtime,
    handlers_ptr: *HandlersType,
    outputs_ptr: *OutputBundleType(HandlersType),
    comptime compiled_plan: ?public_lowering.ProgramPlan,
) ?lowered_machine.ResetError(HandlerErrorSet(HandlersType) || BodyErrorSet(Body, PreviewBodyEffType(HandlersType)))!BodyAnswerType(Body, PreviewBodyEffType(HandlersType)) {
    const resolved_plan = compiled_plan orelse return null;
    return try runCompiledLexicalPlan(
        HandlersType,
        Body,
        runtime,
        handlers_ptr,
        outputs_ptr,
        resolved_plan,
    );
}

// zlinter-disable max_positional_args - this internal compiled caller-owned seam keeps provenance and lexical state explicit across the public-lowering handoff.
fn tryCallerOwnedCompiledWith(
    comptime HandlersType: type,
    comptime Body: type,
    comptime caller: std.builtin.SourceLocation,
    comptime caller_source_override: ?[:0]const u8,
    comptime caller_owned_kind: CallerOwnedCompilationKind,
    runtime: *lowered_machine.Runtime,
    handlers_ptr: *HandlersType,
    outputs_ptr: *OutputBundleType(HandlersType),
) ?lowered_machine.ResetError(HandlerErrorSet(HandlersType) || BodyErrorSet(Body, PreviewBodyEffType(HandlersType)))!BodyAnswerType(Body, PreviewBodyEffType(HandlersType)) {
    if (isNamedBodyDescriptor(Body)) return null;
    const maybe_lowered_program = comptime if (anonymousBodySyntheticSource(caller, Body, caller_source_override, caller_owned_kind)) |synthetic_source| blk: {
        const source_ref = public_lowering.sourceWithContent(caller.file, caller, synthetic_source);
        break :blk public_lowering.maybeLower(source_ref, .{
            .label = "shift.with caller-owned lexical body",
            .entry_symbol = anonymousBodyEntryName(caller),
            .ValueType = BodyAnswerType(Body, PreviewBodyEffType(HandlersType)),
            .row = lexical_bundle_schema.rowForHandlers(HandlersType),
            .outputs = lexical_bundle_schema.outputsForHandlers(HandlersType),
        });
    } else null;
    const lowered_program = maybe_lowered_program orelse return null;
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

fn callerOwnedCompilationSupported(
    comptime HandlersType: type,
    comptime Body: type,
    comptime caller: std.builtin.SourceLocation,
    comptime caller_source_override: ?[:0]const u8,
    comptime caller_owned_kind: CallerOwnedCompilationKind,
) bool {
    return comptime if (anonymousBodySyntheticSource(caller, Body, caller_source_override, caller_owned_kind)) |synthetic_source| blk: {
        const source_ref = public_lowering.sourceWithContent(caller.file, caller, synthetic_source);
        break :blk public_lowering.maybeLower(source_ref, .{
            .label = "shift.with caller-owned lexical body",
            .entry_symbol = anonymousBodyEntryName(caller),
            .ValueType = BodyAnswerType(Body, PreviewBodyEffType(HandlersType)),
            .row = lexical_bundle_schema.rowForHandlers(HandlersType),
            .outputs = lexical_bundle_schema.outputsForHandlers(HandlersType),
        }) != null;
    } else false;
}

fn ownedSourceUsesAnonymousCallerCompilation(comptime Body: type, comptime witness: OwnedSourceWitness) bool {
    if (isNamedBodyDescriptor(Body)) return false;
    if (witness.source_path != null) return false;
    if (witness.entry_symbol != null) return false;
    if (witness.body_source != null) return false;
    if (witness.imported_sources.len != 0) return false;
    return !@hasDecl(Body, "entry_symbol");
}

fn ownedSourceUsesNamedEmbeddedCompilation(comptime Body: type) bool {
    if (!isNamedBodyDescriptor(Body)) return false;
    return source_graph_embed.ownedRepoPath(Body.source_path) != null;
}

fn ownedSourceNamedEmbeddedPlan(comptime HandlersType: type, comptime Body: type) ?public_lowering.ProgramPlan {
    if (!ownedSourceUsesNamedEmbeddedCompilation(Body)) return null;
    return namedCompiledLexicalPlan(HandlersType, Body);
}

fn ownedSourceCompilationSourcePath(
    comptime Body: type,
    comptime witness: OwnedSourceWitness,
    comptime caller: std.builtin.SourceLocation,
) []const u8 {
    if (isNamedBodyDescriptor(Body)) return Body.source_path;
    return witness.source_path orelse caller.file;
}

fn ownedSourceCompilationEntrySymbol(
    comptime Body: type,
    comptime witness: OwnedSourceWitness,
    comptime caller: std.builtin.SourceLocation,
) []const u8 {
    if (isNamedBodyDescriptor(Body)) return Body.entry_symbol;
    return witness.entry_symbol orelse if (witness.body_source != null)
        witness.body_method_name
    else
        anonymousBodyEntryName(caller);
}

fn rejectUnsupportedOwnedSourceWith(
    comptime HandlersType: type,
    comptime Body: type,
    comptime caller: std.builtin.SourceLocation,
    comptime root_source: [:0]const u8,
    comptime witness: OwnedSourceWitness,
) void {
    comptime rejectForgedOwnedSourceSyntheticPath(Body, caller, witness);
    if (ownedSourceUsesAnonymousCallerCompilation(Body, witness)) {
        if (callerOwnedCompilationSupported(HandlersType, Body, caller, root_source, .owned_source)) return;
    }
    if (comptime ownedSourceNamedEmbeddedPlan(HandlersType, Body)) |compiled_plan| {
        _ = compiled_plan;
        return;
    }
    const source_path = comptime ownedSourceCompilationSourcePath(Body, witness, caller);
    const source_owner = comptime ownedSourceLocation(caller, source_path);
    const entry_symbol = comptime ownedSourceCompilationEntrySymbol(Body, witness, caller);
    const synthetic_source = comptime ownedSourceSyntheticSource(Body, caller, root_source, witness, entry_symbol);
    const source_ref = comptime public_lowering.sourceWithContentAndImports(
        source_path,
        source_owner,
        synthetic_source orelse root_source,
        witness.imported_sources,
    );
    if (public_lowering.maybeLower(source_ref, .{
        .label = "shift.with owned lexical body",
        .entry_symbol = entry_symbol,
        .ValueType = BodyAnswerType(Body, PreviewBodyEffType(HandlersType)),
        .row = lexical_bundle_schema.rowForHandlers(HandlersType),
        .outputs = lexical_bundle_schema.outputsForHandlers(HandlersType),
    }) != null) return;
    @compileError("shift.withOwnedSource explicit source witnesses must stay within the retained compiled lexical subset");
}

// zlinter-disable max_positional_args - the explicit owned-source seam threads witness, caller bytes, and lexical state directly to keep ownership boundaries obvious.
fn tryOwnedSourceCompiledWith(
    comptime HandlersType: type,
    comptime Body: type,
    comptime caller: std.builtin.SourceLocation,
    comptime root_source: [:0]const u8,
    comptime witness: OwnedSourceWitness,
    runtime: *lowered_machine.Runtime,
    handlers_ptr: *HandlersType,
    outputs_ptr: *OutputBundleType(HandlersType),
) ?lowered_machine.ResetError(HandlerErrorSet(HandlersType) || BodyErrorSet(Body, PreviewBodyEffType(HandlersType)))!BodyAnswerType(Body, PreviewBodyEffType(HandlersType)) {
    if (ownedSourceUsesAnonymousCallerCompilation(Body, witness)) {
        return tryCallerOwnedCompiledWith(
            HandlersType,
            Body,
            caller,
            root_source,
            .owned_source,
            runtime,
            handlers_ptr,
            outputs_ptr,
        );
    }
    if (comptime ownedSourceNamedEmbeddedPlan(HandlersType, Body)) |compiled_plan| {
        return try runCompiledLexicalPlan(
            HandlersType,
            Body,
            runtime,
            handlers_ptr,
            outputs_ptr,
            compiled_plan,
        );
    }
    const source_path = comptime ownedSourceCompilationSourcePath(Body, witness, caller);
    const source_owner = comptime ownedSourceLocation(caller, source_path);
    const entry_symbol = comptime ownedSourceCompilationEntrySymbol(Body, witness, caller);
    const synthetic_source = comptime ownedSourceSyntheticSource(Body, caller, root_source, witness, entry_symbol);
    const source_ref = comptime public_lowering.sourceWithContentAndImports(
        source_path,
        source_owner,
        synthetic_source orelse root_source,
        witness.imported_sources,
    );
    const lowered_program = public_lowering.maybeLower(source_ref, .{
        .label = "shift.with owned lexical body",
        .entry_symbol = entry_symbol,
        .ValueType = BodyAnswerType(Body, PreviewBodyEffType(HandlersType)),
        .row = lexical_bundle_schema.rowForHandlers(HandlersType),
        .outputs = lexical_bundle_schema.outputsForHandlers(HandlersType),
    }) orelse return null;
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
    comptime HandlersType: type,
    comptime caller: std.builtin.SourceLocation,
    comptime Body: type,
    comptime caller_source_override: ?[:0]const u8,
    comptime caller_owned_kind: CallerOwnedCompilationKind,
) bool {
    return callerOwnedCompilationSupported(HandlersType, Body, caller, caller_source_override, caller_owned_kind);
}

/// Recover the active lexical rebinding packet from the exact context capability.
pub fn activeLexicalState(
    ctx: anytype,
    comptime HandlersType: type,
    comptime EffType: type,
) *LexicalState(HandlersType, EffType, exactContextCallerSource(@TypeOf(ctx))) {
    return @ptrCast(@alignCast(ctx._cap.lexical_state.?));
}

// zlinter-disable max_positional_args - threading the exact caller source through the recursive lexical runner is the minimal change that preserves the existing control flow.
fn runChainCollected(
    comptime HandlersType: type,
    comptime Body: type,
    comptime index: usize,
    comptime EffType: type,
    comptime caller: std.builtin.SourceLocation,
    state: CollectedRunState(HandlersType, EffType, caller),
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
    comptime caller: std.builtin.SourceLocation,
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

/// Return type for one lexical `shift.withAt(@src(), ...)` instantiation.
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
fn withImpl(
    runtime: *lowered_machine.Runtime,
    handlers: anytype,
    comptime Body: type,
    comptime caller: std.builtin.SourceLocation,
    comptime caller_source_override: ?[:0]const u8,
    comptime caller_owned_kind: CallerOwnedCompilationKind,
) WithFnReturnType(@TypeOf(handlers), Body) {
    const HandlersType = @TypeOf(handlers);
    const canonical_caller = comptime source_graph_embed.canonicalCallerLocation(caller);
    comptime assertHandlerBundleShape(HandlersType);
    const named_compiled_plan = comptime namedCompiledLexicalPlan(HandlersType, Body);
    comptime rejectUnsupportedShippedWith(HandlersType, Body, named_compiled_plan, canonical_caller, caller_source_override, caller_owned_kind);

    var handler_state = handlers;
    var outputs = std.mem.zeroInit(OutputBundleType(HandlersType), .{});
    if (comptime isNamedBodyDescriptor(Body)) {
        if (tryNamedCompiledWith(HandlersType, Body, runtime, &handler_state, &outputs, named_compiled_plan)) |compiled| {
            const value = try compiled;
            return .{
                .outputs = outputs,
                .value = value,
            };
        }
    }
    if (comptime anonymousBodyCompilable(HandlersType, canonical_caller, Body, caller_source_override, caller_owned_kind)) {
        if (tryCallerOwnedCompiledWith(HandlersType, Body, canonical_caller, caller_source_override, caller_owned_kind, runtime, &handler_state, &outputs)) |compiled| {
            const value = try compiled;
            return .{
                .outputs = outputs,
                .value = value,
            };
        }
    }
    const value = try runChainCollected(HandlersType, Body, 0, struct {}, canonical_caller, .{
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

/// Run one lexical effect bundle and return descriptor outputs alongside the body answer.
pub inline fn with(
    runtime: *lowered_machine.Runtime,
    handlers: anytype,
    comptime Body: type,
) WithFnReturnType(@TypeOf(handlers), Body) {
    return withAt(@src(), runtime, handlers, Body);
}

/// Run one lexical effect bundle with explicit caller provenance.
pub fn withAt(
    comptime caller: std.builtin.SourceLocation,
    runtime: *lowered_machine.Runtime,
    handlers: anytype,
    comptime Body: type,
) WithFnReturnType(@TypeOf(handlers), Body) {
    return withImpl(runtime, handlers, Body, caller, null, .none);
}

/// Run one lexical effect bundle while the caller explicitly supplies the source location used for caller-owned compilation.
pub fn withCallerSource(
    comptime caller: std.builtin.SourceLocation,
    runtime: *lowered_machine.Runtime,
    handlers: anytype,
    comptime Body: type,
) WithFnReturnType(@TypeOf(handlers), Body) {
    return withImpl(runtime, handlers, Body, caller, null, .explicit_location);
}

/// Run one lexical effect bundle while the caller explicitly supplies both source location and source bytes for caller-owned compilation.
pub fn withCallerSourceAndContent(
    comptime caller: std.builtin.SourceLocation,
    comptime caller_source: [:0]const u8,
    runtime: *lowered_machine.Runtime,
    handlers: anytype,
    comptime Body: type,
) WithFnReturnType(@TypeOf(handlers), Body) {
    return withImpl(runtime, handlers, Body, caller, caller_source, .explicit_location_and_content);
}

/// Run one lexical effect bundle through an explicit caller-owned source witness surface.
/// The `root_source` bytes must match the source file identified by `witness.source_path` or `shift.NamedBody(...).source_path`.
pub fn withOwnedSource(
    comptime caller: std.builtin.SourceLocation,
    comptime root_source: [:0]const u8,
    comptime witness: OwnedSourceWitness,
    runtime: *lowered_machine.Runtime,
    handlers: anytype,
    comptime Body: type,
) WithFnReturnType(@TypeOf(handlers), Body) {
    const HandlersType = @TypeOf(handlers);
    const canonical_caller = comptime source_graph_embed.canonicalCallerLocation(caller);
    comptime assertHandlerBundleShape(HandlersType);
    comptime rejectUnsupportedOwnedSourceWith(HandlersType, Body, canonical_caller, root_source, witness);

    var handler_state = handlers;
    var outputs = std.mem.zeroInit(OutputBundleType(HandlersType), .{});
    if (tryOwnedSourceCompiledWith(
        HandlersType,
        Body,
        canonical_caller,
        root_source,
        witness,
        runtime,
        &handler_state,
        &outputs,
    )) |compiled| {
        const value = try compiled;
        return .{
            .outputs = outputs,
            .value = value,
        };
    }
    unreachable;
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
