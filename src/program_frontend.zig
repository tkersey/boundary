const source_path_compat_mode = @hasDecl(@import("root"), "source_path_compat_mode");
const effect_ir = @import("./effect_ir.zig");
const helper_body_ir = @import("./internal/helper_body_ir.zig");
const parity_scenarios = @import("./parity_scenarios.zig");
const std = @import("std");

/// One lowered helper-body basic block carried by the internal front end.
pub const BodyBlock = helper_body_ir.Block;
/// One lowered helper-body instruction carried by the internal front end.
pub const BodyInstruction = helper_body_ir.Instruction;
/// One lowered helper-body local codec carried by the internal front end.
pub const BodyLocalCodec = helper_body_ir.LocalCodec;
/// One lowered helper-body terminator carried by the internal front end.
pub const BodyTerminator = helper_body_ir.Terminator;
/// One lowered helper-body terminator kind carried by the internal front end.
pub const BodyTerminatorKind = helper_body_ir.TerminatorKind;
/// One lowered helper-body payload aligned to one front-end function.
pub const FunctionBody = helper_body_ir.FunctionBody;

/// Witness programs exposed through the internal structured-program front end.
pub const WitnessProgram = enum {
    atm_resume_transform,
    direct_return,
    multi_prompt,
    resume_or_return_resume,
    resume_or_return_return_now,
    static_redelim,
};

/// Example programs exposed through the internal structured-program front end.
pub const ExampleProgram = enum {
    early_exit,
    nested_workflow_publish,
    resume_or_return,
};

/// Effect programs exposed through the internal structured-program front end.
pub const EffectProgram = enum {
    exception_basic,
    optional_basic,
    reader_basic,
    state_basic,
};

/// Internal structured-program sum type that lowers into the canonical scenario IR.
pub const Program = union(enum) {
    effect: EffectProgram,
    example: ExampleProgram,
    witness: WitnessProgram,
};

/// One lowered internal program paired with its canonical scenario entry.
pub const LoweredProgram = struct {
    label: []const u8,
    scenario: *const parity_scenarios.Scenario,
};

/// One open-row program payload lowered through the new Effect IR semantic center.
pub const OpenRowProgram = struct {
    label: []const u8,
    entry_symbol: []const u8,
    entry_module_path: ?[]const u8 = null,
    functions: []const effect_ir.Function,
    call_edges: []const effect_ir.CallEdge = &.{},
    function_bodies: []const FunctionBody = &.{},
};

/// One lowered open-row program that owns its function storage.
pub const LoweredOpenRowProgram = struct {
    entry_index: usize,
    functions: []const effect_ir.Function,
    call_edges: []const effect_ir.CallEdge = &.{},
    function_bodies: []const FunctionBody = &.{},

    /// Project the owned function storage back into the generic Effect IR view.
    pub fn asEffectProgram(self: *const @This()) effect_ir.Program {
        return .{
            .entry_index = @intCast(self.entry_index),
            .functions = self.functions,
            .call_edges = self.call_edges,
            .function_bodies = self.function_bodies,
        };
    }
};

/// Open-row frontend constructors for the new lowering path.
pub const open_rows = struct {
    /// Lower one state-plus-writer workflow through the open-row frontend.
    pub fn stateWriterWorkflow() OpenRowProgram {
        const row = comptime effect_ir.mergeRows(.{
            effect_ir.rowFromSpec(.{
                .state = .{
                    .get = effect_ir.Transform(void, i32),
                    .set = effect_ir.Transform(i32, void),
                },
            }),
            effect_ir.rowFromSpec(.{
                .writer = .{
                    .tell = effect_ir.Transform([]const u8, void),
                },
            }),
        });
        return .{
            .label = "example.open_row_state_writer",
            .entry_symbol = "runBody",
            .functions = &.{.{
                .symbol = .{
                    .module_path = "examples/open_row_state_writer.zig",
                    .symbol_name = "runBody",
                },
                .row = row,
                .outputs = &.{
                    .{ .label = "state", .OutputType = i32 },
                    .{ .label = "writer", .OutputType = [][]const u8 },
                },
            }},
        };
    }
};

/// Structured-program constructors for witness cases.
pub const witnesses = struct {
    /// Lower the ATM resume-then-transform witness through the internal front end.
    pub fn atmResumeTransform() Program {
        return .{ .witness = .atm_resume_transform };
    }

    /// Lower the direct-return witness through the internal front end.
    pub fn directReturn() Program {
        return .{ .witness = .direct_return };
    }

    /// Lower the prompt-separation witness through the internal front end.
    pub fn multiPrompt() Program {
        return .{ .witness = .multi_prompt };
    }

    /// Lower the resumptive optional witness through the internal front end.
    pub fn resumeOrReturnResume() Program {
        return .{ .witness = .resume_or_return_resume };
    }

    /// Lower the return-now optional witness through the internal front end.
    pub fn resumeOrReturnReturnNow() Program {
        return .{ .witness = .resume_or_return_return_now };
    }

    /// Lower the static re-delimitation witness through the internal front end.
    pub fn staticRedelim() Program {
        return .{ .witness = .static_redelim };
    }
};

/// Structured-program constructors for practical examples.
pub const examples = struct {
    /// Lower the early-exit example through the internal front end.
    pub fn earlyExit() Program {
        return .{ .example = .early_exit };
    }

    /// Lower the publish-path workflow example through the internal front end.
    pub fn nestedWorkflowPublish() Program {
        return .{ .example = .nested_workflow_publish };
    }

    /// Lower the optional-resumption example through the internal front end.
    pub fn resumeOrReturn() Program {
        return .{ .example = .resume_or_return };
    }
};

/// Structured-program constructors for key effect paths.
pub const effects = struct {
    /// Lower the exception example through the internal front end.
    pub fn exceptionBasic() Program {
        return .{ .effect = .exception_basic };
    }

    /// Lower the optional effect example through the internal front end.
    pub fn optionalBasic() Program {
        return .{ .effect = .optional_basic };
    }

    /// Lower the reader effect example through the internal front end.
    pub fn readerBasic() Program {
        return .{ .effect = .reader_basic };
    }

    /// Lower the state effect example through the internal front end.
    pub fn stateBasic() Program {
        return .{ .effect = .state_basic };
    }
};

/// The structured-program corpus retained as internal scaffolding for the surface-truth campaign.
pub const corpus = [_]Program{
    witnesses.atmResumeTransform(),
    witnesses.directReturn(),
    witnesses.multiPrompt(),
    witnesses.resumeOrReturnResume(),
    witnesses.resumeOrReturnReturnNow(),
    witnesses.staticRedelim(),
    examples.earlyExit(),
    examples.resumeOrReturn(),
    examples.nestedWorkflowPublish(),
    effects.stateBasic(),
    effects.readerBasic(),
    effects.optionalBasic(),
    effects.exceptionBasic(),
};

/// Return the stable label for one structured program.
pub fn label(program: Program) []const u8 {
    return switch (program) {
        .witness => |witness| switch (witness) {
            .atm_resume_transform => "witness.atm_resume_transform",
            .direct_return => "witness.direct_return",
            .multi_prompt => "witness.multi_prompt",
            .resume_or_return_resume => "witness.resume_or_return_resume",
            .resume_or_return_return_now => "witness.resume_or_return_return_now",
            .static_redelim => "witness.static_redelim",
        },
        .example => |example| switch (example) {
            .early_exit => "example.early_exit",
            .nested_workflow_publish => "example.nested_workflow_publish",
            .resume_or_return => "example.resume_or_return",
        },
        .effect => |effect| switch (effect) {
            .exception_basic => "effect.exception_basic",
            .optional_basic => "effect.optional_basic",
            .reader_basic => "effect.reader_basic",
            .state_basic => "effect.state_basic",
        },
    };
}

/// Lower one structured program into the canonical scenario registry.
pub fn lower(program: Program) LoweredProgram {
    return .{
        .label = label(program),
        .scenario = switch (program) {
            .witness => |witness| parity_scenarios.byId(switch (witness) {
                .atm_resume_transform => .atm_resume_transform,
                .direct_return => .direct_return,
                .multi_prompt => .multi_prompt,
                .resume_or_return_resume => .resume_or_return_resume,
                .resume_or_return_return_now => .resume_or_return_return_now,
                .static_redelim => .static_redelim,
            }),
            .example => |example| parity_scenarios.byId(switch (example) {
                .early_exit => .early_exit,
                .nested_workflow_publish => .nested_workflow_publish,
                .resume_or_return => .resume_or_return,
            }),
            .effect => |effect| parity_scenarios.byId(switch (effect) {
                .exception_basic => .exception_basic,
                .optional_basic => .optional_basic,
                .reader_basic => .reader_basic,
                .state_basic => .state_basic,
            }),
        },
    };
}

fn cloneBytes(comptime bytes: []const u8) []const u8 {
    return std.fmt.comptimePrint("{s}", .{bytes});
}

fn cloneSymbolRef(comptime symbol: effect_ir.SymbolRef) effect_ir.SymbolRef {
    return .{
        .module_path = cloneBytes(symbol.module_path),
        .symbol_name = cloneBytes(symbol.symbol_name),
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
        const exact = buffer;
        break :blk exact[0..];
    };
}

fn cloneOps(comptime ops: []const effect_ir.OpSpec) []const effect_ir.OpSpec {
    return comptime blk: {
        var buffer: [ops.len]effect_ir.OpSpec = undefined;
        for (ops, 0..) |op, index| {
            buffer[index] = .{
                .requirement_label = cloneBytes(op.requirement_label),
                .op_name = cloneBytes(op.op_name),
                .mode = op.mode,
                .PayloadType = op.PayloadType,
                .ResumeType = op.ResumeType,
                .has_after = op.has_after,
            };
        }
        const exact = buffer;
        break :blk exact[0..];
    };
}

fn cloneRequirements(comptime requirements: []const effect_ir.Requirement) []const effect_ir.Requirement {
    return comptime blk: {
        var buffer: [requirements.len]effect_ir.Requirement = undefined;
        for (requirements, 0..) |requirement, index| {
            buffer[index] = .{
                .label = cloneBytes(requirement.label),
                .ops = cloneOps(requirement.ops),
            };
        }
        const exact = buffer;
        break :blk exact[0..];
    };
}

fn cloneRow(comptime row: effect_ir.Row) effect_ir.Row {
    return .{
        .requirements = cloneRequirements(row.requirements),
    };
}

fn cloneCallEdges(comptime call_edges: []const effect_ir.CallEdge) []const effect_ir.CallEdge {
    return comptime blk: {
        var buffer: [call_edges.len]effect_ir.CallEdge = undefined;
        for (call_edges, 0..) |edge, index| {
            buffer[index] = .{
                .caller = cloneSymbolRef(edge.caller),
                .callee = cloneSymbolRef(edge.callee),
            };
        }
        const exact = buffer;
        break :blk exact[0..];
    };
}

fn cloneBodyInstructions(comptime instructions: []const helper_body_ir.Instruction) []const helper_body_ir.Instruction {
    return comptime blk: {
        var buffer: [instructions.len]helper_body_ir.Instruction = undefined;
        for (instructions, 0..) |instruction, index| {
            buffer[index] = instruction;
        }
        const exact = buffer;
        break :blk exact[0..];
    };
}

fn cloneBodyBlocks(comptime blocks: []const helper_body_ir.Block) []const helper_body_ir.Block {
    return comptime blk: {
        var buffer: [blocks.len]helper_body_ir.Block = undefined;
        for (blocks, 0..) |block, index| {
            buffer[index] = .{
                .instructions = cloneBodyInstructions(block.instructions),
                .terminator = block.terminator,
            };
        }
        const exact = buffer;
        break :blk exact[0..];
    };
}

fn cloneLocalCodecs(comptime codecs: []const helper_body_ir.LocalCodec) []const helper_body_ir.LocalCodec {
    return comptime blk: {
        var buffer: [codecs.len]helper_body_ir.LocalCodec = undefined;
        for (codecs, 0..) |codec, index| {
            buffer[index] = codec;
        }
        const exact = buffer;
        break :blk exact[0..];
    };
}

fn cloneLocalIds(comptime local_ids: []const helper_body_ir.LocalId) []const helper_body_ir.LocalId {
    return comptime blk: {
        var buffer: [local_ids.len]helper_body_ir.LocalId = undefined;
        for (local_ids, 0..) |local_id, index| {
            buffer[index] = local_id;
        }
        const exact = buffer;
        break :blk exact[0..];
    };
}

fn cloneFunctionBodies(comptime function_bodies: []const helper_body_ir.FunctionBody) []const helper_body_ir.FunctionBody {
    return comptime blk: {
        var buffer: [function_bodies.len]helper_body_ir.FunctionBody = undefined;
        for (function_bodies, 0..) |body, index| {
            buffer[index] = .{
                .local_codecs = cloneLocalCodecs(body.local_codecs),
                .call_arg_locals = cloneLocalIds(body.call_arg_locals),
                .entry_block = body.entry_block,
                .blocks = cloneBodyBlocks(body.blocks),
            };
        }
        const exact = buffer;
        break :blk exact[0..];
    };
}

fn cloneFunction(comptime function: effect_ir.Function) effect_ir.Function {
    return .{
        .symbol = cloneSymbolRef(function.symbol),
        .row = cloneRow(function.row),
        .parameter_codecs = cloneLocalCodecs(function.parameter_codecs),
        .ValueType = function.ValueType,
        .outputs = cloneOutputSpecs(function.outputs),
    };
}

fn cloneFunctions(comptime functions: []const effect_ir.Function) []const effect_ir.Function {
    return comptime blk: {
        var buffer: [functions.len]effect_ir.Function = undefined;
        for (functions, 0..) |function, index| {
            buffer[index] = cloneFunction(function);
        }
        const exact = buffer;
        break :blk exact[0..];
    };
}

fn validateOpenRowGraph(
    comptime functions: []const effect_ir.Function,
    comptime call_edges: []const effect_ir.CallEdge,
) effect_ir.NormalizeError!void {
    const symbols = comptime blk: {
        var buffer: [functions.len]effect_ir.SymbolRef = undefined;
        for (functions, 0..) |function, index| {
            buffer[index] = function.symbol;
        }
        break :blk buffer;
    };
    try effect_ir.validateGraph(.{
        .symbols = &symbols,
        .edges = call_edges,
    });
}

fn entryIndex(
    comptime functions: []const effect_ir.Function,
    comptime entry_symbol: []const u8,
    comptime entry_module_path: ?[]const u8,
) effect_ir.NormalizeError!usize {
    comptime var found_index: ?usize = null;
    inline for (functions, 0..) |function, index| {
        const symbol_matches = comptime std.mem.eql(u8, function.symbol.symbol_name, entry_symbol);
        const module_matches = if (entry_module_path) |module_path|
            comptime std.mem.eql(u8, function.symbol.module_path, module_path)
        else
            true;
        if (symbol_matches and module_matches) {
            if (found_index != null) return error.DuplicateSymbol;
            found_index = index;
        }
    }
    return found_index orelse error.UnknownSymbol;
}

/// Lower one open-row frontend payload into stable function storage.
pub fn lowerOpenRow(comptime program: OpenRowProgram) effect_ir.NormalizeError!LoweredOpenRowProgram {
    try validateOpenRowGraph(program.functions, program.call_edges);
    if (program.function_bodies.len != 0 and program.function_bodies.len != program.functions.len) {
        return error.UnsupportedHelperCallEdge;
    }
    return .{
        .entry_index = try entryIndex(program.functions, program.entry_symbol, program.entry_module_path),
        .functions = cloneFunctions(program.functions),
        .call_edges = cloneCallEdges(program.call_edges),
        .function_bodies = if (program.function_bodies.len == 0)
            &.{}
        else
            cloneFunctionBodies(program.function_bodies),
    };
}

const source_path_compat_excluded_tests = if (source_path_compat_mode) struct {} else struct {
    fn expectLowerOpenRowPreservesFunctionPayload() !void {
        const row = comptime effect_ir.rowFromSpec(.{
            .state = .{
                .get = effect_ir.Transform(void, i32),
                .set = effect_ir.Transform(i32, void),
            },
        });
        const function = comptime effect_ir.Function{
            .symbol = .{
                .module_path = "examples/open_row.zig",
                .symbol_name = "workflow",
            },
            .row = row,
            .outputs = &.{
                .{ .label = "state", .OutputType = i32 },
            },
        };
        const program = try lowerOpenRow(.{
            .label = "example.open_row.workflow",
            .entry_symbol = "workflow",
            .functions = &.{function},
        });
        const digest = try effect_ir.rowDigest(row, function.outputs);

        try std.testing.expectEqual(@as(usize, 1), program.functions.len);
        try std.testing.expectEqual(@as(usize, 0), program.entry_index);
        try std.testing.expectEqual(@as(usize, 0), program.function_bodies.len);
        try std.testing.expectEqualStrings("workflow", program.functions[0].symbol.symbol_name);
        try std.testing.expectEqual(@as(usize, 1), digest.requirement_count);
        try std.testing.expectEqual(@as(usize, 2), digest.op_count);
        try std.testing.expectEqual(@as(usize, 1), digest.output_count);
    }

    test "lowerOpenRow preserves the function payload" {
        try expectLowerOpenRowPreservesFunctionPayload();
    }

    fn expectOpenRowStateWriterWorkflowCarriesBothRequirementsAndOutputs() !void {
        const workflow = comptime open_rows.stateWriterWorkflow();
        const program = try lowerOpenRow(workflow);
        const digest = try effect_ir.rowDigest(workflow.functions[0].row, workflow.functions[0].outputs);
        try std.testing.expectEqual(@as(usize, 1), program.functions.len);
        try std.testing.expectEqual(@as(usize, 0), program.function_bodies.len);
        try std.testing.expectEqualStrings("runBody", program.functions[0].symbol.symbol_name);
        try std.testing.expectEqual(@as(usize, 2), digest.requirement_count);
        try std.testing.expectEqual(@as(usize, 3), digest.op_count);
        try std.testing.expectEqual(@as(usize, 2), digest.output_count);
    }

    test "open row state-writer workflow carries both requirements and outputs" {
        try expectOpenRowStateWriterWorkflowCarriesBothRequirementsAndOutputs();
    }
};
comptime {
    _ = source_path_compat_excluded_tests;
}

test "lowerOpenRow preserves row-only helper-call metadata without synthesizing body storage" {
    const helper_symbol = effect_ir.SymbolRef{
        .module_path = "examples/synth.zig",
        .symbol_name = "helper",
    };
    const root_symbol = effect_ir.SymbolRef{
        .module_path = "examples/synth.zig",
        .symbol_name = "root",
    };
    const row = comptime effect_ir.rowFromSpec(.{
        .state = .{
            .get = effect_ir.Transform(void, i32),
        },
    });
    const program = try lowerOpenRow(.{
        .label = "example.synth",
        .entry_symbol = "root",
        .functions = &.{
            .{ .symbol = root_symbol, .row = row, .outputs = &.{.{ .label = "state", .OutputType = i32 }} },
            .{ .symbol = helper_symbol, .row = row, .outputs = &.{} },
        },
        .call_edges = &.{.{
            .caller = root_symbol,
            .callee = helper_symbol,
        }},
    });

    try @import("std").testing.expectEqual(@as(usize, 0), program.function_bodies.len);
    try @import("std").testing.expectEqual(@as(usize, 1), program.call_edges.len);
    try @import("std").testing.expect(program.call_edges[0].caller.eql(root_symbol));
    try @import("std").testing.expect(program.call_edges[0].callee.eql(helper_symbol));
}

test "lowerOpenRow preserves helper-call metadata even when helpers carry parameters" {
    const helper_symbol = effect_ir.SymbolRef{
        .module_path = "examples/synth_args.zig",
        .symbol_name = "helper",
    };
    const root_symbol = effect_ir.SymbolRef{
        .module_path = "examples/synth_args.zig",
        .symbol_name = "root",
    };

    const program = try lowerOpenRow(.{
        .label = "example.synth_args",
        .entry_symbol = "root",
        .functions = &.{
            .{
                .symbol = root_symbol,
                .row = effect_ir.rowFromSpec(.{}),
            },
            .{
                .symbol = helper_symbol,
                .row = effect_ir.rowFromSpec(.{}),
                .parameter_codecs = &.{.i32},
            },
        },
        .call_edges = &.{.{
            .caller = root_symbol,
            .callee = helper_symbol,
        }},
    });

    try @import("std").testing.expectEqual(@as(usize, 0), program.function_bodies.len);
    try @import("std").testing.expectEqual(@as(usize, 1), program.call_edges.len);
}

const source_path_compat_excluded_value_tests = if (source_path_compat_mode) struct {} else struct {
    fn expectLowerOpenRowPreservesValueReturningPayloads() !void {
        const program = try lowerOpenRow(.{
            .label = "example.synth_value",
            .entry_symbol = "root",
            .functions = &.{.{
                .symbol = .{
                    .module_path = "examples/synth_value.zig",
                    .symbol_name = "root",
                },
                .row = effect_ir.rowFromSpec(.{}),
                .ValueType = i32,
            }},
        });

        try std.testing.expectEqual(@as(usize, 0), program.function_bodies.len);
        try std.testing.expectEqualStrings("root", program.functions[0].symbol.symbol_name);
    }

    test "lowerOpenRow preserves row-only value-returning payloads without inventing bodies" {
        try expectLowerOpenRowPreservesValueReturningPayloads();
    }
};
comptime {
    _ = source_path_compat_excluded_value_tests;
}

test "lowerOpenRow preserves attached helper body storage" {
    const program = try lowerOpenRow(.{
        .label = "example.body_storage",
        .entry_symbol = "runBody",
        .functions = &.{.{
            .symbol = .{
                .module_path = "examples/body_storage.zig",
                .symbol_name = "runBody",
            },
            .row = effect_ir.rowFromSpec(.{
                .state = .{
                    .get = effect_ir.Transform(void, i32),
                },
            }),
        }},
        .function_bodies = &.{.{
            .local_codecs = &.{},
            .call_arg_locals = &.{},
            .entry_block = 0,
            .blocks = &.{.{
                .instructions = &.{},
                .terminator = .{ .kind = .return_unit },
            }},
        }},
    });

    try @import("std").testing.expectEqual(@as(usize, 1), program.function_bodies.len);
    try @import("std").testing.expectEqual(@as(usize, 1), program.function_bodies[0].blocks.len);
    try @import("std").testing.expectEqual(@as(helper_body_ir.BlockId, 0), program.function_bodies[0].entry_block);
}

test "lowerOpenRow keeps prior lowered functions stable across later calls" {
    const alpha = try lowerOpenRow(.{
        .label = "example.alpha",
        .entry_symbol = "alpha",
        .functions = &.{.{
            .symbol = .{
                .module_path = "examples/alpha.zig",
                .symbol_name = "alpha",
            },
            .row = effect_ir.rowFromSpec(.{
                .state = .{
                    .get = effect_ir.Transform(void, i32),
                },
            }),
        }},
    });
    const beta = try lowerOpenRow(.{
        .label = "example.beta",
        .entry_symbol = "beta",
        .functions = &.{.{
            .symbol = .{
                .module_path = "examples/beta.zig",
                .symbol_name = "beta",
            },
            .row = effect_ir.rowFromSpec(.{
                .writer = .{
                    .tell = effect_ir.Transform([]const u8, void),
                },
            }),
        }},
    });

    try @import("std").testing.expectEqualStrings("alpha", alpha.functions[0].symbol.symbol_name);
    try @import("std").testing.expectEqualStrings("beta", beta.functions[0].symbol.symbol_name);
    try @import("std").testing.expectEqualStrings("alpha", alpha.asEffectProgram().functions[0].symbol.symbol_name);
}

const source_path_compat_excluded_error_tests = if (source_path_compat_mode) struct {} else struct {
    test "lowerOpenRow rejects helper call edges with unknown callee symbols" {
        try std.testing.expectError(error.UnknownSymbol, lowerOpenRow(.{
            .label = "example.helper_edge",
            .entry_symbol = "workflow",
            .functions = &.{.{
                .symbol = .{
                    .module_path = "examples/open_row.zig",
                    .symbol_name = "workflow",
                },
                .row = effect_ir.rowFromSpec(.{
                    .state = .{
                        .get = effect_ir.Transform(void, i32),
                    },
                }),
            }},
            .call_edges = &.{.{
                .caller = .{
                    .module_path = "examples/open_row.zig",
                    .symbol_name = "workflow",
                },
                .callee = .{
                    .module_path = "examples/helper.zig",
                    .symbol_name = "helper",
                },
            }},
        }));
    }
};
comptime {
    _ = source_path_compat_excluded_error_tests;
}
