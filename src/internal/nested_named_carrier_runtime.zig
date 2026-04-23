// zlinter-disable function_naming - internal type builders intentionally return comptime packet types.
// zlinter-disable require_doc_comment - this is internal nested lexical runtime glue, not a user-facing API.
// zlinter-disable max_positional_args - the carrier packet shape stays explicit to avoid hiding module-boundary constraints.
const effect_ir = @import("effect_ir");
const helper_body_lowering = @import("helper_body_lowering.zig");
const program_frontend = @import("program_frontend");
const program_plan = @import("internal_program_plan");
const source_graph_embed = @import("source_graph_embed");
const source_graph_engine = @import("source_graph_engine");
const source_lowering = @import("source_lowering");
const std = @import("std");

fn sentinelBytes(comptime bytes: []const u8) [:0]const u8 {
    const raw = std.fmt.comptimePrint("{s}\x00", .{bytes});
    return raw[0..bytes.len :0];
}

fn cloneBytes(comptime bytes: []const u8) []const u8 {
    return std.fmt.comptimePrint("{s}", .{bytes});
}

fn BindingSchemaFamily(comptime DescriptorType: type, comptime requirement_label: [:0]const u8) type {
    const BindingSchema = DescriptorType.BindingSchema(requirement_label);
    if (@hasDecl(BindingSchema, "Family")) return BindingSchema.Family;
    if (@hasDecl(BindingSchema, "family")) return BindingSchema.family;
    @compileError("nested lexical with binding schema must expose Family");
}

fn rowFromFamily(
    comptime requirement_label: []const u8,
    comptime Family: anytype,
) effect_ir.Row {
    const ops = comptime blk: {
        var buffer: [Family.ops.len]effect_ir.OpSpec = undefined;
        for (Family.ops, 0..) |op, index| {
            buffer[index] = .{
                .requirement_label = cloneBytes(requirement_label),
                .op_name = cloneBytes(op.name),
                .mode = switch (op.control_mode) {
                    .abort => .abort,
                    .choice => .choice,
                    .transform => .transform,
                },
                .PayloadType = op.Payload,
                .ResumeType = op.Resume,
                .has_after = true,
            };
        }
        const exact = buffer;
        break :blk exact[0..];
    };
    return .{
        .requirements = &[_]effect_ir.Requirement{.{
            .label = cloneBytes(requirement_label),
            .ops = ops,
        }},
    };
}

fn programGraphFromModuleGraph(
    comptime source_path: []const u8,
    comptime module_graph: source_graph_engine.ModuleGraph,
) source_graph_embed.ProgramGraph {
    const functions = comptime blk: {
        var buffer: [module_graph.functions.len]source_graph_embed.ProgramFunction = undefined;
        for (module_graph.functions, 0..) |function, index| {
            buffer[index] = .{
                .module_path = cloneBytes(source_path),
                .name = cloneBytes(function.name),
                .effect_param = function.effect_param,
                .value_param_names = function.value_param_names,
                .value_param_shapes = function.value_param_shapes,
                .value_param_count = function.value_param_count,
                .return_shape = function.return_shape,
                .body_lowering_supported = function.body_lowering_supported,
                .body_start_offset = function.body_start_offset,
                .body_end_offset = function.body_end_offset,
            };
        }
        const exact = buffer;
        break :blk exact[0..];
    };
    const helper_edges = comptime blk: {
        var buffer: [module_graph.helper_edges.len]source_graph_embed.ProgramHelperEdge = undefined;
        for (module_graph.helper_edges, 0..) |edge, index| {
            buffer[index] = .{
                .caller_index = edge.caller_index,
                .callee_index = edge.callee_index,
                .line = edge.line,
                .column = edge.column,
            };
        }
        const exact = buffer;
        break :blk exact[0..];
    };
    const direct_op_uses = comptime blk: {
        var buffer: [module_graph.direct_op_uses.len]source_graph_embed.ProgramDirectOpUse = undefined;
        for (module_graph.direct_op_uses, 0..) |use, index| {
            buffer[index] = .{
                .function_index = use.function_index,
                .requirement_label = cloneBytes(use.requirement_label),
                .op_name = cloneBytes(use.op_name),
                .line = use.line,
                .column = use.column,
            };
        }
        const exact = buffer;
        break :blk exact[0..];
    };
    return .{
        .entry_index = module_graph.entry_index orelse @compileError("nested lexical named carrier requires an entry function"),
        .functions = functions,
        .helper_edges = helper_edges,
        .direct_op_uses = direct_op_uses,
    };
}

fn reachableFunctions(comptime graph: source_graph_embed.ProgramGraph) [graph.functions.len]bool {
    var reachable = [_]bool{false} ** graph.functions.len;
    reachable[graph.entry_index] = true;

    var changed = true;
    while (changed) {
        changed = false;
        helper_edges: for (graph.helper_edges) |edge| {
            if (!reachable[edge.caller_index] or reachable[edge.callee_index]) continue :helper_edges;
            reachable[edge.callee_index] = true;
            changed = true;
        }
    }

    return reachable;
}

fn loweredFunctionIndexMap(comptime graph: source_graph_embed.ProgramGraph) [graph.functions.len]u16 {
    const reachable = reachableFunctions(graph);
    return comptime blk: {
        var buffer: [graph.functions.len]u16 = [_]u16{std.math.maxInt(u16)} ** graph.functions.len;
        var next_index: u16 = 0;
        buffer[graph.entry_index] = next_index;
        next_index += 1;
        for (graph.functions, 0..) |_, function_index| {
            if (!reachable[function_index] or function_index == graph.entry_index) continue;
            buffer[function_index] = next_index;
            next_index += 1;
        }
        break :blk buffer;
    };
}

fn parameterCodecs(function: source_graph_embed.ProgramFunction) []const effect_ir.LocalCodec {
    return comptime blk: {
        if (function.value_param_count == 0) break :blk &.{};
        var codec_buffer: [function.value_param_count]effect_ir.LocalCodec = undefined;
        for (0..function.value_param_count) |param_index| {
            codec_buffer[param_index] = switch (function.value_param_shapes[param_index]) {
                .bool => .bool,
                .i32 => .i32,
                .string => .string,
                .usize => .usize,
            };
        }
        const exact = codec_buffer;
        break :blk exact[0..];
    };
}

fn ValueTypeForShape(shape: ?source_graph_engine.ValueShape) type {
    return switch (shape orelse return void) {
        .bool => bool,
        .i32 => i32,
        .string => []const u8,
        .usize => usize,
    };
}

fn buildFunctionsForGraph(
    comptime graph: source_graph_embed.ProgramGraph,
    comptime row: effect_ir.Row,
) []const effect_ir.Function {
    const reachable = reachableFunctions(graph);
    const function_count = comptime blk: {
        var count: usize = 0;
        for (reachable) |is_reachable| {
            if (is_reachable) count += 1;
        }
        break :blk count;
    };

    return comptime blk: {
        var buffer: [function_count]effect_ir.Function = undefined;
        var index: usize = 0;
        for (graph.functions, 0..) |function, function_index| {
            if (!reachable[function_index]) continue;
            buffer[index] = .{
                .symbol = .{
                    .module_path = cloneBytes(function.module_path),
                    .symbol_name = cloneBytes(function.name),
                },
                .row = row,
                .parameter_codecs = parameterCodecs(function),
                .ValueType = ValueTypeForShape(function.return_shape),
                .outputs = &.{},
            };
            index += 1;
        }
        const exact = buffer;
        break :blk exact[0..];
    };
}

fn buildCallEdgesForGraph(comptime graph: source_graph_embed.ProgramGraph) []const effect_ir.CallEdge {
    const reachable = reachableFunctions(graph);
    const edge_count = comptime blk: {
        var count: usize = 0;
        for (graph.helper_edges) |edge| {
            if (reachable[edge.caller_index] and reachable[edge.callee_index]) count += 1;
        }
        break :blk count;
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
        const exact = buffer;
        break :blk exact[0..];
    };
}

pub fn NamedNestedCarrier(
    comptime SourceModule: type,
    comptime requirement_label: []const u8,
    comptime factory_name: []const u8,
    comptime container_name: []const u8,
    comptime handler_name: []const u8,
    comptime carrier_name: []const u8,
    comptime source_path: []const u8,
    comptime body_symbol: []const u8,
) type {
    const SourceModuleType = SourceModule;
    const factory = @field(SourceModuleType, factory_name);
    const handler_container = @field(SourceModuleType, container_name);
    const HandlerType = @field(handler_container, handler_name);
    const DescriptorType = @TypeOf(factory.use(.{ .handler = HandlerType{} }));
    const Family = BindingSchemaFamily(DescriptorType, sentinelBytes(requirement_label));
    const row = rowFromFamily(requirement_label, Family);
    const source = source_graph_embed.embeddedSource(source_path);
    const graph = source_graph_engine.analyzeComptime(source, .{
        .entry_symbol = body_symbol,
        .reject_recursive_helpers = false,
        .reject_indirect_effect_access = true,
        .reject_malformed_statements = true,
    }) catch |err| switch (err) {
        error.EntryMissing => @compileError("nested lexical named carrier body_symbol was not found in the source graph"),
        error.ParseError => @compileError("nested lexical named carrier source did not parse"),
        error.TooManyFunctions,
        error.TooManyFunctionParams,
        error.TooManyImports,
        error.TooManyHelperUses,
        error.TooManyHelperEdges,
        error.TooManyOpUses,
        error.UnsupportedEffectAccess,
        error.UnsupportedImportPath,
        error.MissingImport,
        error.RecursiveHelpers,
        => @compileError("nested lexical named carrier could not analyze the source graph"),
    };
    const program_graph = programGraphFromModuleGraph(source_path, graph);
    const functions = buildFunctionsForGraph(program_graph, row);
    const function_bodies = helper_body_lowering.buildFunctionBodiesForGraph(
        program_graph,
        functions,
        reachableFunctions(program_graph),
        loweredFunctionIndexMap(program_graph),
        .{
            .path = source_path,
            .content = source,
            .imported_sources = &.{},
        },
    );
    const payload: program_frontend.OpenRowProgram = .{
        .label = "nested lexical named carrier",
        .entry_symbol = body_symbol,
        .entry_module_path = program_graph.functions[program_graph.entry_index].module_path,
        .functions = functions,
        .call_edges = buildCallEdgesForGraph(program_graph),
        .function_bodies = function_bodies,
    };
    const lowered = source_lowering.lowerOpenRowProgram(payload) catch |err| switch (err) {
        error.DuplicateRequirementLabel => @compileError("nested lexical named carrier lowering rejected duplicate requirement labels"),
        error.DuplicateOpName => @compileError("nested lexical named carrier lowering rejected duplicate op names"),
        error.DuplicateOutputLabel => @compileError("nested lexical named carrier lowering rejected duplicate output labels"),
        error.EmptyRequirementLabel => @compileError("nested lexical named carrier lowering rejected an empty requirement label"),
        error.EmptyOpName => @compileError("nested lexical named carrier lowering rejected an empty op name"),
        error.InvalidProgramBodyShape => @compileError("nested lexical named carrier lowering rejected the helper-body payload shape"),
        error.InvalidRequirementShape => @compileError("nested lexical named carrier lowering rejected an invalid requirement shape"),
        error.InvalidRowShape => @compileError("nested lexical named carrier lowering rejected an invalid row shape"),
        error.OutputWithoutRequirement => @compileError("nested lexical named carrier lowering rejected outputs without matching requirements"),
        error.DuplicateSymbol => @compileError("nested lexical named carrier lowering rejected duplicate function symbols"),
        error.UnknownSymbol => @compileError("nested lexical named carrier lowering rejected an unknown function symbol"),
        error.UnsupportedHelperCallEdge => @compileError("nested lexical named carrier lowering rejected helper call edges"),
        error.OutOfMemory => @compileError("nested lexical named carrier lowering ran out of memory at comptime"),
    };
    const compiled_plan = program_plan.planFromOpenRowProgram(
        std.fmt.comptimePrint("nested lexical named carrier {s}", .{carrier_name}),
        lowered.program,
    ) catch |err| switch (err) {
        error.DuplicateRequirementLabel => @compileError("nested lexical named carrier runtime plan rejected duplicate requirement labels"),
        error.DuplicateOpName => @compileError("nested lexical named carrier runtime plan rejected duplicate op names"),
        error.DuplicateOutputLabel => @compileError("nested lexical named carrier runtime plan rejected duplicate output labels"),
        error.EmptyProgram => @compileError("nested lexical named carrier runtime plan rejected an empty effect-ir program"),
        error.EmptyRequirementLabel => @compileError("nested lexical named carrier runtime plan rejected an empty requirement label"),
        error.EmptyOpName => @compileError("nested lexical named carrier runtime plan rejected an empty op name"),
        error.InvalidProgramBodyShape => @compileError("nested lexical named carrier runtime plan rejected the helper-body payload shape"),
        error.InvalidRequirementShape => @compileError("nested lexical named carrier runtime plan rejected an invalid requirement shape"),
        error.InvalidRowShape => @compileError("nested lexical named carrier runtime plan rejected an invalid row shape"),
        error.OutputWithoutRequirement => @compileError("nested lexical named carrier runtime plan rejected outputs without matching requirements"),
        error.DuplicateSymbol => @compileError("nested lexical named carrier runtime plan rejected duplicate function symbols"),
        error.UnknownSymbol => @compileError("nested lexical named carrier runtime plan rejected an unknown function symbol"),
        error.UnsupportedHelperCallEdge => @compileError("nested lexical named carrier runtime plan rejected helper call edges"),
        error.UnsupportedCodecType => @compileError("nested lexical named carrier runtime plan rejected a type outside the executable codec set"),
        error.OutOfMemory => @compileError("nested lexical named carrier runtime plan ran out of memory at comptime"),
    };
    return struct {
        pub const descriptor_type = DescriptorType;
        pub const compiled_plan_value = compiled_plan;

        pub fn descriptor() DescriptorType {
            return factory.use(.{ .handler = HandlerType{} });
        }
    };
}
