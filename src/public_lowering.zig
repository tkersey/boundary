const effect_ir = @import("effect_ir");
const program_frontend = @import("program_frontend");
const program_plan = @import("internal_program_plan");
const source_lowering = @import("source_lowering");
const std = @import("std");

/// Public additive spec for one same-module lowering request.
pub const LowerSpec = struct {
    label: []const u8,
    entry_symbol: []const u8,
    row: effect_ir.Row,
    outputs: []const effect_ir.OutputSpec = &.{},
};

/// Public additive open-row program payload.
pub const OpenRowProgram = program_frontend.OpenRowProgram;
/// Public additive lowered open-row artifact.
pub const LoweredProgram = source_lowering.OpenRowGeneratedProgram;
/// Public additive validation error surface for file-backed same-module sources.
pub const ValidationError = error{
    EntryMissing,
    OutOfMemory,
    ParseError,
    SourceUnreadable,
    UnsupportedHelperGraph,
};
/// Public additive lowering error surface.
pub const LowerError = effect_ir.NormalizeError || ValidationError;
/// Public additive runtime plan over the retained open-row lowering path.
pub const ProgramPlan = program_plan.ProgramPlan;
/// Public additive compiled program marker.
pub const CompiledProgram = type;

/// Public additive constructors over the retained open-row frontend.
pub const open_rows = program_frontend.open_rows;

fn cloneBytes(comptime bytes: []const u8) []const u8 {
    return std.fmt.comptimePrint("{s}", .{bytes});
}

fn cloneOutputSpecs(comptime outputs: []const effect_ir.OutputSpec) []const effect_ir.OutputSpec {
    return comptime blk: {
        var buffer: [outputs.len]effect_ir.OutputSpec = undefined;
        for (outputs, 0..) |output, index| {
            buffer[index] = .{
                .label = cloneBytes(output.label),
                .OutputType = output.OutputType,
            };
        }
        break :blk &buffer;
    };
}

fn cloneRow(comptime row: effect_ir.Row) effect_ir.Row {
    const requirements = comptime blk: {
        var requirement_buffer: [row.requirements.len]effect_ir.Requirement = undefined;
        for (row.requirements, 0..) |requirement, requirement_index| {
            var op_buffer: [requirement.ops.len]effect_ir.OpSpec = undefined;
            for (requirement.ops, 0..) |op, op_index| {
                op_buffer[op_index] = .{
                    .requirement_label = cloneBytes(op.requirement_label),
                    .op_name = cloneBytes(op.op_name),
                    .mode = op.mode,
                    .PayloadType = op.PayloadType,
                    .ResumeType = op.ResumeType,
                };
            }
            requirement_buffer[requirement_index] = .{
                .label = cloneBytes(requirement.label),
                .ops = &op_buffer,
            };
        }
        break :blk requirement_buffer;
    };
    return .{ .requirements = &requirements };
}

fn cloneFunction(comptime function: effect_ir.Function) effect_ir.Function {
    return .{
        .symbol = .{
            .module_path = cloneBytes(function.symbol.module_path),
            .symbol_name = cloneBytes(function.symbol.symbol_name),
        },
        .row = cloneRow(function.row),
        .outputs = cloneOutputSpecs(function.outputs),
    };
}

fn cloneProgram(comptime program: effect_ir.Program) effect_ir.Program {
    const functions = comptime blk: {
        var buffer: [program.functions.len]effect_ir.Function = undefined;
        for (program.functions, 0..) |function, index| {
            buffer[index] = cloneFunction(function);
        }
        break :blk buffer;
    };
    return .{
        .functions = &functions,
        .call_edges = &.{},
    };
}

/// Build one public additive open-row payload with an explicit caller-visible source path.
pub fn openRowAt(comptime source_path: []const u8, comptime spec: LowerSpec) OpenRowProgram {
    return .{
        .label = spec.label,
        .function = .{
            .symbol = .{
                .module_path = source_path,
                .symbol_name = spec.entry_symbol,
            },
            .row = spec.row,
            .outputs = spec.outputs,
        },
        .call_edges = &.{},
    };
}

/// Build one public additive open-row payload from a same-module source location.
pub fn openRow(comptime source: std.builtin.SourceLocation, comptime spec: LowerSpec) OpenRowProgram {
    return openRowAt(source.file, spec);
}

/// Lower one public additive open-row payload into the retained effect-ir shell.
pub fn lowerOpenRowAt(comptime source_path: []const u8, comptime spec: LowerSpec) LowerError!LoweredProgram {
    return try source_lowering.lowerOpenRowProgram(openRowAt(source_path, spec));
}

/// Lower one public additive open-row payload from a same-module source location.
pub fn lowerOpenRow(comptime source: std.builtin.SourceLocation, comptime spec: LowerSpec) LowerError!LoweredProgram {
    return try lowerOpenRowAt(source.file, spec);
}

/// Rebuild the public effect-ir program view for one additive lowering request.
pub fn irProgramAt(comptime source_path: []const u8, comptime spec: LowerSpec) effect_ir.Program {
    const payload = openRowAt(source_path, spec);
    const functions = comptime [_]effect_ir.Function{payload.function};
    return .{
        .functions = &functions,
        .call_edges = &.{},
    };
}

/// Rebuild the public effect-ir program view from a same-module source location.
pub fn irProgram(comptime source: std.builtin.SourceLocation, comptime spec: LowerSpec) effect_ir.Program {
    return irProgramAt(source.file, spec);
}

fn readSourceAlloc(allocator: std.mem.Allocator, path: []const u8) ValidationError![]u8 {
    if (std.fs.path.isAbsolute(path)) {
        const file = std.fs.openFileAbsolute(path, .{}) catch return error.SourceUnreadable;
        defer file.close();
        var buffer: [4096]u8 = undefined;
        var reader = file.reader(&buffer);
        return reader.interface.allocRemaining(allocator, .limited(1 << 20)) catch return error.SourceUnreadable;
    }
    return std.fs.cwd().readFileAlloc(allocator, path, 1 << 20) catch return error.SourceUnreadable;
}

/// Validate one explicit-path source file and entry symbol for the additive lowerer.
pub fn validateFileBackedOpenRowAt(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    entry_symbol: []const u8,
) ValidationError!void {
    const source = try readSourceAlloc(allocator, source_path);
    defer allocator.free(source);

    var analysis = try source_lowering.analyzeSameModuleSourceText(allocator, source);
    defer analysis.deinit(allocator);

    if (!analysis.isParseClean()) return error.ParseError;
    if (!analysis.hasTopLevelFunctionNamed(entry_symbol)) return error.EntryMissing;
    for (analysis.helper_call_edges) |edge| {
        if (std.mem.eql(u8, edge.caller_name, entry_symbol)) return error.UnsupportedHelperGraph;
    }
}

/// Validate one additive lowering request from a same-module source location.
pub fn validateFileBackedOpenRow(
    allocator: std.mem.Allocator,
    comptime source: std.builtin.SourceLocation,
    comptime spec: LowerSpec,
) ValidationError!void {
    return try validateFileBackedOpenRowAt(allocator, source.file, spec.entry_symbol);
}

const ValidationSpec = struct {
    source_path: []const u8,
    entry_symbol: []const u8,
};

fn GeneratedProgramType(
    comptime label_value: []const u8,
    comptime source_path_value: []const u8,
    comptime entry_symbol_value: []const u8,
    comptime ir_program: effect_ir.Program,
    comptime validate_spec: ?ValidationSpec,
) type {
    const stable_ir_program = cloneProgram(ir_program);
    const compiled_plan = program_plan.planFromProgram(label_value, stable_ir_program) catch |err| switch (err) {
        error.DuplicateRequirementLabel => @compileError("public lowering rejected duplicate requirement labels"),
        error.DuplicateOpName => @compileError("public lowering rejected duplicate op names"),
        error.DuplicateOutputLabel => @compileError("public lowering rejected duplicate output labels"),
        error.EmptyProgram => @compileError("public lowering rejected an empty effect-ir program"),
        error.EmptyRequirementLabel => @compileError("public lowering rejected an empty requirement label"),
        error.EmptyOpName => @compileError("public lowering rejected an empty op name"),
        error.InvalidRequirementShape => @compileError("public lowering rejected an invalid requirement shape"),
        error.InvalidRowShape => @compileError("public lowering rejected an invalid row shape"),
        error.OutputWithoutRequirement => @compileError("public lowering rejected outputs without matching requirements"),
        error.DuplicateSymbol => @compileError("public lowering rejected duplicate function symbols"),
        error.UnknownSymbol => @compileError("public lowering rejected an unknown function symbol"),
        error.UnsupportedHelperCallEdge => @compileError("public lowering runtime plan rejected helper call edges outside the retained open-row shell"),
        error.UnsupportedCodecType => @compileError("public lowering runtime plan rejected a type outside the first-wave codec set"),
        error.OutOfMemory => @compileError("public lowering ran out of memory at comptime"),
    };

    return struct {
        /// Stable label for this compiled additive lowering request.
        pub const label = label_value;
        /// Caller-visible source path for this compiled additive lowering request.
        pub const source_path = source_path_value;
        /// Top-level entry symbol requested by this compiled additive lowering request.
        pub const entry_symbol = entry_symbol_value;
        /// Stable IR hash mirrored into the runtime-owned executable plan.
        pub const ir_hash = compiled_plan.ir_hash;
        /// Runtime-owned executable plan alias retained for the additive bridge.
        pub const runtime_plan = compiled_plan;

        /// Validate the named source file and entry symbol for this compiled additive lowering request.
        pub fn validate(allocator: std.mem.Allocator) ValidationError!void {
            const active_spec = validate_spec orelse return;
            return try validateFileBackedOpenRowAt(allocator, active_spec.source_path, active_spec.entry_symbol);
        }
    };
}

fn LowerAt(comptime source_path: []const u8, comptime spec: LowerSpec) type {
    comptime {
        @setEvalBranchQuota(20_000);
    }
    _ = source_lowering.lowerOpenRowProgram(openRowAt(source_path, spec)) catch |err| switch (err) {
        error.DuplicateRequirementLabel => @compileError("public lowering rejected duplicate requirement labels"),
        error.DuplicateOpName => @compileError("public lowering rejected duplicate op names"),
        error.DuplicateOutputLabel => @compileError("public lowering rejected duplicate output labels"),
        error.EmptyRequirementLabel => @compileError("public lowering rejected an empty requirement label"),
        error.EmptyOpName => @compileError("public lowering rejected an empty op name"),
        error.InvalidRequirementShape => @compileError("public lowering rejected an invalid requirement shape"),
        error.InvalidRowShape => @compileError("public lowering rejected an invalid row shape"),
        error.OutputWithoutRequirement => @compileError("public lowering rejected outputs without matching requirements"),
        error.DuplicateSymbol => @compileError("public lowering rejected duplicate function symbols"),
        error.UnknownSymbol => @compileError("public lowering rejected an unknown function symbol"),
        error.UnsupportedHelperCallEdge => @compileError("public lowering rejected helper call edges outside the retained open-row shell"),
        error.OutOfMemory => @compileError("public lowering ran out of memory at comptime"),
    };
    return GeneratedProgramType(spec.label, source_path, spec.entry_symbol, irProgramAt(source_path, spec), .{
        .source_path = source_path,
        .entry_symbol = spec.entry_symbol,
    });
}

/// Compile one additive lowering request into a generated type using an explicit source path.
pub const lowerAt = LowerAt;

/// Transitional alias while the additive lowering namespace settles.
pub const CompileOpenRow = LowerAt;
/// Compile one explicit-path additive lowerer request through the same runtime-plan bridge.
pub const CompileOpenRowAt = LowerAt;

fn CompileIrType(comptime label: []const u8, comptime program: effect_ir.Program) type {
    comptime {
        @setEvalBranchQuota(20_000);
    }
    if (program.functions.len == 0) @compileError("public lowering cannot compile an empty effect-ir program");
    return GeneratedProgramType(label, "<ir>", program.functions[0].symbol.symbol_name, program, null);
}

/// Compile one explicit public effect-ir program into the same runtime-owned plan shape.
pub const CompileIr = CompileIrType;

test "same-module lowerAt preserves caller-provided source ownership" {
    const ProgramType = lowerAt(@src().file, .{
        .label = "public_lowering.self",
        .entry_symbol = "openRowAt",
        .row = effect_ir.rowFromSpec(.{
            .state = .{
                .get = effect_ir.Transform(void, i32),
            },
        }),
    });

    try std.testing.expectEqualStrings(@src().file, ProgramType.source_path);
    try std.testing.expectEqualStrings("openRowAt", ProgramType.entry_symbol);
    try std.testing.expectEqual(@as(usize, 1), ProgramType.runtime_plan.functions.len);
}
