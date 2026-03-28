const effect_ir = @import("effect_ir");
const parity_scenarios = @import("parity_scenarios");

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
    function: effect_ir.Function,
    call_edges: []const effect_ir.CallEdge = &.{},
};

/// One lowered open-row program that owns its single-function storage.
pub const LoweredOpenRowProgram = struct {
    functions: [1]effect_ir.Function,
    call_edges: []const effect_ir.CallEdge = &.{},

    /// Project the owned single-function storage back into the generic Effect IR view.
    pub fn asEffectProgram(self: *const @This()) effect_ir.Program {
        return .{
            .functions = self.functions[0..],
            .call_edges = self.call_edges,
        };
    }
};

/// Open-row frontend constructors for the new lowering path.
pub const open_rows = struct {
    /// Lower one state-plus-writer workflow through the open-row frontend.
    pub fn stateWriterWorkflow() OpenRowProgram {
        const row = effect_ir.mergeRows(.{
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
            .label = "example.open_row.state_writer_workflow",
            .function = .{
                .symbol = .{
                    .module_path = "examples/open_row_state_writer.zig",
                    .symbol_name = "workflow",
                },
                .row = row,
                .outputs = &.{
                    .{ .label = "state", .OutputType = i32 },
                    .{ .label = "writer", .OutputType = [][]const u8 },
                },
            },
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

/// Lower one open-row frontend payload into stable single-function storage.
pub fn lowerOpenRow(program: OpenRowProgram) LoweredOpenRowProgram {
    return .{
        .functions = .{program.function},
        .call_edges = program.call_edges,
    };
}

test "lowerOpenRow preserves the function payload" {
    const row = effect_ir.rowFromSpec(.{
        .state = .{
            .get = effect_ir.Transform(void, i32),
            .set = effect_ir.Transform(i32, void),
        },
    });
    const function = effect_ir.Function{
        .symbol = .{
            .module_path = "examples/open_row.zig",
            .symbol_name = "workflow",
        },
        .row = row,
        .outputs = &.{
            .{ .label = "state", .OutputType = i32 },
        },
    };
    const program = lowerOpenRow(.{
        .label = "example.open_row.workflow",
        .function = function,
    });

    try @import("std").testing.expectEqual(@as(usize, 1), program.functions.len);
    try @import("std").testing.expectEqualStrings("workflow", program.functions[0].symbol.symbol_name);
    const digest = try effect_ir.rowDigest(program.functions[0].row, program.functions[0].outputs);
    try @import("std").testing.expectEqual(@as(usize, 1), digest.requirement_count);
    try @import("std").testing.expectEqual(@as(usize, 2), digest.op_count);
    try @import("std").testing.expectEqual(@as(usize, 1), digest.output_count);
}

test "open row state-writer workflow carries both requirements and outputs" {
    const program = lowerOpenRow(open_rows.stateWriterWorkflow());
    try @import("std").testing.expectEqual(@as(usize, 1), program.functions.len);
    try @import("std").testing.expectEqualStrings("workflow", program.functions[0].symbol.symbol_name);
    const digest = try effect_ir.rowDigest(program.functions[0].row, program.functions[0].outputs);
    try @import("std").testing.expectEqual(@as(usize, 2), digest.requirement_count);
    try @import("std").testing.expectEqual(@as(usize, 3), digest.op_count);
    try @import("std").testing.expectEqual(@as(usize, 2), digest.output_count);
}

test "lowerOpenRow keeps prior lowered functions stable across later calls" {
    const alpha = lowerOpenRow(.{
        .label = "example.alpha",
        .function = .{
            .symbol = .{
                .module_path = "examples/alpha.zig",
                .symbol_name = "alpha",
            },
            .row = effect_ir.rowFromSpec(.{
                .state = .{
                    .get = effect_ir.Transform(void, i32),
                },
            }),
        },
    });
    const beta = lowerOpenRow(.{
        .label = "example.beta",
        .function = .{
            .symbol = .{
                .module_path = "examples/beta.zig",
                .symbol_name = "beta",
            },
            .row = effect_ir.rowFromSpec(.{
                .writer = .{
                    .tell = effect_ir.Transform([]const u8, void),
                },
            }),
        },
    });

    try @import("std").testing.expectEqualStrings("alpha", alpha.functions[0].symbol.symbol_name);
    try @import("std").testing.expectEqualStrings("beta", beta.functions[0].symbol.symbol_name);
    try @import("std").testing.expectEqualStrings("alpha", alpha.asEffectProgram().functions[0].symbol.symbol_name);
}
