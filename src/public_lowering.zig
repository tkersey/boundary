const effect_ir = @import("effect_ir");
const program_frontend = @import("program_frontend");
const program_plan = @import("internal_program_plan");
const source_graph_embed = @import("source_graph_embed");
const source_graph_comptime = @import("source_graph_comptime");
const source_graph_engine = @import("source_graph_engine");
const source_lowering = @import("source_lowering");
const std = @import("std");

/// Public additive spec for one same-module lowering request.
pub const LowerSpec = struct {
    label: []const u8,
    entry_symbol: []const u8,
    row: effect_ir.Row,
    outputs: []const effect_ir.OutputSpec = &.{},
};

/// Public caller-supplied provenance witness for one lowering request.
pub const SourceRef = struct {
    repo_path: []const u8,
    caller_file: []const u8,
};

/// Public additive validation error surface for file-backed same-module sources.
pub const ValidationError = error{
    EntryMissing,
    OutOfMemory,
    ParseError,
    SourceUnreadable,
    UnsupportedHelperGraph,
    UnsupportedEffectAccess,
};
/// Public additive lowering error surface.
pub const LowerError = effect_ir.NormalizeError || ValidationError;

fn cloneBytes(comptime bytes: []const u8) []const u8 {
    return std.fmt.comptimePrint("{s}", .{bytes});
}

/// Build one caller-owned lowering provenance witness from an explicit repo path plus `@src()`.
pub fn source(comptime repo_path: []const u8, comptime caller: std.builtin.SourceLocation) SourceRef {
    if (repo_path.len == 0) @compileError("public lowering source helper requires a non-empty repo-relative path");
    if (caller.file.len == 0) @compileError("public lowering source helper requires a non-empty caller source file");
    return .{
        .repo_path = cloneBytes(repo_path),
        .caller_file = cloneBytes(caller.file),
    };
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
        .call_edges = cloneCallEdges(program.call_edges),
    };
}

fn cloneCallEdges(comptime call_edges: []const effect_ir.CallEdge) []const effect_ir.CallEdge {
    return comptime blk: {
        var buffer: [call_edges.len]effect_ir.CallEdge = undefined;
        for (call_edges, 0..) |edge, index| {
            buffer[index] = .{
                .caller = .{
                    .module_path = cloneBytes(edge.caller.module_path),
                    .symbol_name = cloneBytes(edge.caller.symbol_name),
                },
                .callee = .{
                    .module_path = cloneBytes(edge.callee.module_path),
                    .symbol_name = cloneBytes(edge.callee.symbol_name),
                },
            };
        }
        break :blk &buffer;
    };
}

const FlatOp = struct {
    requirement_label: []const u8,
    op_name: []const u8,
    mode: effect_ir.ControlMode,
    PayloadType: type,
    ResumeType: type,
};

fn flatOpsForRow(comptime row: effect_ir.Row) []const FlatOp {
    return comptime blk: {
        const total = count: {
            var count_ops: usize = 0;
            for (row.requirements) |requirement| count_ops += requirement.ops.len;
            break :count count_ops;
        };
        var buffer: [total]FlatOp = undefined;
        var index: usize = 0;
        for (row.requirements) |requirement| {
            for (requirement.ops) |op| {
                buffer[index] = .{
                    .requirement_label = cloneBytes(requirement.label),
                    .op_name = cloneBytes(op.op_name),
                    .mode = op.mode,
                    .PayloadType = op.PayloadType,
                    .ResumeType = op.ResumeType,
                };
                index += 1;
            }
        }
        break :blk &buffer;
    };
}

fn reachableFunctions(comptime graph: source_graph_embed.ProgramGraph) [graph.functions.len]bool {
    var reachable = [_]bool{false} ** graph.functions.len;
    reachable[graph.entry_index] = true;

    var changed = true;
    while (changed) {
        changed = false;
        for (graph.helper_edges) |edge| {
            if (!reachable[edge.caller_index] or reachable[edge.callee_index]) continue;
            reachable[edge.callee_index] = true;
            changed = true;
        }
    }

    return reachable;
}

fn inferUsedOps(
    comptime graph: source_graph_embed.ProgramGraph,
    comptime flat_ops: []const FlatOp,
) [graph.functions.len][flat_ops.len]bool {
    var used = [_][flat_ops.len]bool{[_]bool{false} ** flat_ops.len} ** graph.functions.len;

    for (graph.direct_op_uses) |direct_use| {
        for (flat_ops, 0..) |op, op_index| {
            if (!std.mem.eql(u8, op.requirement_label, direct_use.requirement_label)) continue;
            if (!std.mem.eql(u8, op.op_name, direct_use.op_name)) continue;
            used[direct_use.function_index][op_index] = true;
        }
    }

    var changed = true;
    while (changed) {
        changed = false;
        for (graph.helper_edges) |edge| {
            for (flat_ops, 0..) |_, op_index| {
                if (used[edge.caller_index][op_index] or !used[edge.callee_index][op_index]) continue;
                used[edge.caller_index][op_index] = true;
                changed = true;
            }
        }
    }

    return used;
}

fn helperRowFromUsage(
    comptime row: effect_ir.Row,
    comptime flat_ops: []const FlatOp,
    comptime used_ops: []const bool,
) effect_ir.Row {
    return comptime blk: {
        var requirement_buffer: [row.requirements.len]effect_ir.Requirement = undefined;
        var requirement_count: usize = 0;
        var flat_index: usize = 0;

        for (row.requirements) |requirement| {
            var op_buffer: [requirement.ops.len]effect_ir.OpSpec = undefined;
            var op_count: usize = 0;
            for (requirement.ops) |_| {
                if (used_ops[flat_index]) {
                    const flat_op = flat_ops[flat_index];
                    op_buffer[op_count] = .{
                        .requirement_label = flat_op.requirement_label,
                        .op_name = flat_op.op_name,
                        .mode = flat_op.mode,
                        .PayloadType = flat_op.PayloadType,
                        .ResumeType = flat_op.ResumeType,
                    };
                    op_count += 1;
                }
                flat_index += 1;
            }

            if (op_count != 0) {
                const exact_ops = exact: {
                    var exact_buffer: [op_count]effect_ir.OpSpec = undefined;
                    for (0..op_count) |index| exact_buffer[index] = op_buffer[index];
                    break :exact exact_buffer;
                };
                requirement_buffer[requirement_count] = .{
                    .label = cloneBytes(requirement.label),
                    .ops = &exact_ops,
                };
                requirement_count += 1;
            }
        }

        const exact_requirements = exact: {
            var exact_buffer: [requirement_count]effect_ir.Requirement = undefined;
            for (0..requirement_count) |index| exact_buffer[index] = requirement_buffer[index];
            break :exact exact_buffer;
        };
        break :blk .{ .requirements = &exact_requirements };
    };
}

fn buildFunctionsAt(comptime source_path: []const u8, comptime spec: LowerSpec) []const effect_ir.Function {
    const graph = source_graph_embed.analyzeProgramAt(source_path, spec.entry_symbol) catch |err| switch (err) {
        error.EntryMissing => @compileError("public lowering could not find the requested entry symbol in the embedded source"),
        error.MissingImport => @compileError("public lowering could not resolve one imported helper module or helper symbol"),
        error.RecursiveHelpers => @compileError("public lowering does not support recursive helper graphs"),
        error.TooManyFunctions => @compileError("public lowering source graph exceeded the supported function limit"),
        error.TooManyImports => @compileError("public lowering source graph exceeded the supported import limit"),
        error.TooManyHelperUses => @compileError("public lowering source graph exceeded the supported helper-use limit"),
        error.TooManyHelperEdges => @compileError("public lowering source graph exceeded the supported helper-edge limit"),
        error.TooManyOpUses => @compileError("public lowering source graph exceeded the supported op-use limit"),
        error.UnsupportedEffectAccess => @compileError("public lowering helper inference supports only the retained direct and alias-based effect access patterns"),
        error.UnsupportedImportPath => @compileError("public lowering supports only repo-relative .zig imports for cross-file helpers"),
    };
    const reachable = reachableFunctions(graph);
    const flat_ops = flatOpsForRow(spec.row);
    const used_ops = inferUsedOps(graph, flat_ops);

    const function_count = count: {
        var count_functions: usize = 0;
        for (reachable) |is_reachable| {
            if (is_reachable) count_functions += 1;
        }
        break :count count_functions;
    };

    return comptime blk: {
        var buffer: [function_count]effect_ir.Function = undefined;
        var index: usize = 0;

        const entry_function = graph.functions[graph.entry_index];
        buffer[index] = .{
            .symbol = .{
                .module_path = cloneBytes(entry_function.module_path),
                .symbol_name = cloneBytes(entry_function.name),
            },
            .row = cloneRow(spec.row),
            .outputs = cloneOutputSpecs(spec.outputs),
        };
        index += 1;

        for (graph.functions, 0..) |function, function_index| {
            if (!reachable[function_index] or function_index == graph.entry_index) continue;
            buffer[index] = .{
                .symbol = .{
                    .module_path = cloneBytes(function.module_path),
                    .symbol_name = cloneBytes(function.name),
                },
                .row = helperRowFromUsage(spec.row, flat_ops, &used_ops[function_index]),
                .outputs = &.{},
            };
            index += 1;
        }

        break :blk &buffer;
    };
}

fn buildCallEdgesAt(comptime source_path: []const u8, comptime spec: LowerSpec) []const effect_ir.CallEdge {
    const graph = source_graph_embed.analyzeProgramAt(source_path, spec.entry_symbol) catch |err| switch (err) {
        error.EntryMissing => @compileError("public lowering could not find the requested entry symbol in the embedded source"),
        error.MissingImport => @compileError("public lowering could not resolve one imported helper module or helper symbol"),
        error.RecursiveHelpers => @compileError("public lowering does not support recursive helper graphs"),
        error.TooManyFunctions => @compileError("public lowering source graph exceeded the supported function limit"),
        error.TooManyImports => @compileError("public lowering source graph exceeded the supported import limit"),
        error.TooManyHelperUses => @compileError("public lowering source graph exceeded the supported helper-use limit"),
        error.TooManyHelperEdges => @compileError("public lowering source graph exceeded the supported helper-edge limit"),
        error.TooManyOpUses => @compileError("public lowering source graph exceeded the supported op-use limit"),
        error.UnsupportedEffectAccess => @compileError("public lowering helper inference supports only the retained direct and alias-based effect access patterns"),
        error.UnsupportedImportPath => @compileError("public lowering supports only repo-relative .zig imports for cross-file helpers"),
    };
    const reachable = reachableFunctions(graph);
    const edge_count = comptime count: {
        var count_edges: usize = 0;
        for (graph.helper_edges) |edge| {
            if (reachable[edge.caller_index] and reachable[edge.callee_index]) count_edges += 1;
        }
        break :count count_edges;
    };

    return comptime blk: {
        var buffer: [edge_count]effect_ir.CallEdge = undefined;
        var index: usize = 0;
        for (graph.helper_edges) |edge| {
            if (!reachable[edge.caller_index] or !reachable[edge.callee_index]) continue;
            buffer[index] = .{
                .caller = .{
                    .module_path = cloneBytes(graph.functions[edge.caller_index].module_path),
                    .symbol_name = cloneBytes(graph.functions[edge.caller_index].name),
                },
                .callee = .{
                    .module_path = cloneBytes(graph.functions[edge.callee_index].module_path),
                    .symbol_name = cloneBytes(graph.functions[edge.callee_index].name),
                },
            };
            index += 1;
        }
        break :blk &buffer;
    };
}

/// Build one explicit-path open-row payload with a caller-visible source path.
fn openRowAt(comptime source_path: []const u8, comptime spec: LowerSpec) program_frontend.OpenRowProgram {
    return .{
        .label = spec.label,
        .entry_symbol = spec.entry_symbol,
        .functions = buildFunctionsAt(source_path, spec),
        .call_edges = buildCallEdgesAt(source_path, spec),
    };
}

/// Lower one explicit-path open-row payload into the retained effect-ir shell.
pub fn lowerOpenRowAt(comptime source_path: []const u8, comptime spec: LowerSpec) LowerError!source_lowering.OpenRowGeneratedProgram {
    return try source_lowering.lowerOpenRowProgram(openRowAt(source_path, spec));
}

/// Rebuild the public effect-ir program view for one additive lowering request.
pub fn irProgramAt(comptime source_path: []const u8, comptime spec: LowerSpec) effect_ir.Program {
    const payload = openRowAt(source_path, spec);
    return .{
        .functions = payload.functions,
        .call_edges = payload.call_edges,
    };
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
    const source_text = try readSourceAlloc(allocator, source_path);
    defer allocator.free(source_text);

    var analysis = try source_lowering.analyzeSameModuleSourceText(allocator, source_text);
    defer analysis.deinit(allocator);

    if (!analysis.isParseClean()) return error.ParseError;
    const graph = source_graph_engine.analyzeRuntime(allocator, analysis.parsed.source_z, .{
        .entry_symbol = entry_symbol,
        .reject_recursive_helpers = true,
        .reject_indirect_effect_access = true,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.EntryMissing => return error.EntryMissing,
        error.MissingImport => return error.UnsupportedHelperGraph,
        error.RecursiveHelpers => return error.UnsupportedHelperGraph,
        error.TooManyFunctions => return error.UnsupportedHelperGraph,
        error.TooManyImports => return error.UnsupportedHelperGraph,
        error.TooManyHelperUses => return error.UnsupportedHelperGraph,
        error.TooManyHelperEdges => return error.UnsupportedHelperGraph,
        error.TooManyOpUses => return error.UnsupportedHelperGraph,
        error.UnsupportedEffectAccess => return error.UnsupportedEffectAccess,
        error.UnsupportedImportPath => return error.UnsupportedHelperGraph,
    };
    defer allocator.free(graph.functions);
    defer allocator.free(graph.helper_edges);
    defer allocator.free(graph.direct_op_uses);
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

fn Lower(comptime source_ref: SourceRef, comptime spec: LowerSpec) type {
    return LowerAt(source_ref.repo_path, spec);
}

/// Compile one lowering request from an explicit caller-owned provenance witness.
pub const lower = Lower;

/// Compile one explicit-path lowering request into a generated type using a caller-visible source path.
pub const lowerAt = LowerAt;

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
    const ProgramType = lowerAt("examples/open_row_state_writer.zig", .{
        .label = "public_lowering.self",
        .entry_symbol = "runBody",
        .row = effect_ir.rowFromSpec(.{
            .state = .{
                .get = effect_ir.Transform(void, i32),
            },
        }),
    });

    try std.testing.expectEqualStrings("examples/open_row_state_writer.zig", ProgramType.source_path);
    try std.testing.expectEqualStrings("runBody", ProgramType.entry_symbol);
    try std.testing.expectEqual(@as(usize, 3), ProgramType.runtime_plan.functions.len);
}
