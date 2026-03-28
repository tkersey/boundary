const parity_scenarios = @import("parity_scenarios");
const std = @import("std");
const witness_admission = @import("witness_admission_registry");

/// Support state for one unchanged-body bridge case.
pub const Status = enum {
    blocked,
    supported,
};

/// Source category for one unchanged-body bridge case.
pub const SourceKind = enum {
    example,
    witness,
};

/// One direct-style bridge case tied to its canonical source module and scenario.
pub const Case = struct {
    case_id: []const u8,
    label: []const u8,
    source_kind: SourceKind,
    source_module: []const u8,
    fixture_module: []const u8,
    entry_symbol: []const u8,
    scenario_id: parity_scenarios.ScenarioId,
    status: Status,
    blocked_reason: ?[]const u8 = null,
};

fn fixtureModulePath(comptime case_id: []const u8) []const u8 {
    return "test/direct_style_bridge/" ++ case_id ++ ".zig";
}

fn resolvedWitnessStatus(witness_id: []const u8) Status {
    const entry = witness_admission.find(witness_id) orelse return .supported;
    return switch (entry.bridge_status) {
        .supported => .supported,
        .blocked, .unknown => .blocked,
    };
}

fn resolvedWitnessReason(witness_id: []const u8) ?[]const u8 {
    const entry = witness_admission.find(witness_id) orelse return null;
    return switch (entry.bridge_status) {
        .supported => null,
        .blocked => entry.note,
        .unknown => "Witness bridge admission is not resolved yet; treat this case as blocked until the admission matrix is updated.",
    };
}

/// Canonical bridge support registry for unchanged-body direct-style cases.
pub const cases = [_]Case{
    .{
        .case_id = "atm_resume_transform",
        .label = "bridge.atm_resume_transform",
        .source_kind = .witness,
        .source_module = "src/witness_sources.zig",
        .fixture_module = fixtureModulePath("atm_resume_transform"),
        .entry_symbol = "runAtmResumeTransform",
        .scenario_id = .atm_resume_transform,
        .status = resolvedWitnessStatus("atm_resume_transform"),
        .blocked_reason = resolvedWitnessReason("atm_resume_transform"),
    },
    .{
        .case_id = "direct_return",
        .label = "bridge.direct_return",
        .source_kind = .witness,
        .source_module = "src/witness_sources.zig",
        .fixture_module = fixtureModulePath("direct_return"),
        .entry_symbol = "runDirectReturn",
        .scenario_id = .direct_return,
        .status = resolvedWitnessStatus("direct_return"),
        .blocked_reason = resolvedWitnessReason("direct_return"),
    },
    .{
        .case_id = "multi_prompt",
        .label = "bridge.multi_prompt",
        .source_kind = .witness,
        .source_module = "src/witness_sources.zig",
        .fixture_module = fixtureModulePath("multi_prompt"),
        .entry_symbol = "runMultiPrompt",
        .scenario_id = .multi_prompt,
        .status = resolvedWitnessStatus("multi_prompt"),
        .blocked_reason = resolvedWitnessReason("multi_prompt"),
    },
    .{
        .case_id = "resume_or_return_resume",
        .label = "bridge.resume_or_return_resume",
        .source_kind = .witness,
        .source_module = "src/witness_sources.zig",
        .fixture_module = fixtureModulePath("resume_or_return_resume"),
        .entry_symbol = "runResumeOrReturnResume",
        .scenario_id = .resume_or_return_resume,
        .status = resolvedWitnessStatus("resume_or_return_resume"),
        .blocked_reason = resolvedWitnessReason("resume_or_return_resume"),
    },
    .{
        .case_id = "resume_or_return_return_now",
        .label = "bridge.resume_or_return_return_now",
        .source_kind = .witness,
        .source_module = "src/witness_sources.zig",
        .fixture_module = fixtureModulePath("resume_or_return_return_now"),
        .entry_symbol = "runResumeOrReturnReturnNow",
        .scenario_id = .resume_or_return_return_now,
        .status = resolvedWitnessStatus("resume_or_return_return_now"),
        .blocked_reason = resolvedWitnessReason("resume_or_return_return_now"),
    },
    .{
        .case_id = "static_redelim",
        .label = "bridge.static_redelim",
        .source_kind = .witness,
        .source_module = "src/witness_sources.zig",
        .fixture_module = fixtureModulePath("static_redelim"),
        .entry_symbol = "runStaticRedelim",
        .scenario_id = .static_redelim,
        .status = resolvedWitnessStatus("static_redelim"),
        .blocked_reason = resolvedWitnessReason("static_redelim"),
    },
    .{
        .case_id = "early_exit",
        .label = "bridge.early_exit",
        .source_kind = .example,
        .source_module = "examples/early_exit.zig",
        .fixture_module = fixtureModulePath("early_exit"),
        .entry_symbol = "run",
        .scenario_id = .early_exit,
        .status = .supported,
    },
    .{
        .case_id = "resume_or_return",
        .label = "bridge.resume_or_return",
        .source_kind = .example,
        .source_module = "examples/resume_or_return.zig",
        .fixture_module = fixtureModulePath("resume_or_return"),
        .entry_symbol = "run",
        .scenario_id = .resume_or_return,
        .status = .supported,
    },
    .{
        .case_id = "nested_workflow",
        .label = "bridge.nested_workflow",
        .source_kind = .example,
        .source_module = "examples/nested_workflow.zig",
        .fixture_module = fixtureModulePath("nested_workflow"),
        .entry_symbol = "run",
        .scenario_id = .nested_workflow_publish,
        .status = .supported,
    },
    .{
        .case_id = "open_row_generator",
        .label = "bridge.open_row_generator",
        .source_kind = .example,
        .source_module = "examples/open_row_generator.zig",
        .fixture_module = fixtureModulePath("open_row_generator"),
        .entry_symbol = "run",
        .scenario_id = .generator,
        .status = resolvedWitnessStatus("generator"),
        .blocked_reason = resolvedWitnessReason("generator"),
    },
    .{
        .case_id = "state_basic",
        .label = "bridge.state_basic",
        .source_kind = .example,
        .source_module = "examples/state_basic.zig",
        .fixture_module = fixtureModulePath("state_basic"),
        .entry_symbol = "run",
        .scenario_id = .state_basic,
        .status = .supported,
    },
    .{
        .case_id = "reader_basic",
        .label = "bridge.reader_basic",
        .source_kind = .example,
        .source_module = "examples/reader_basic.zig",
        .fixture_module = fixtureModulePath("reader_basic"),
        .entry_symbol = "run",
        .scenario_id = .reader_basic,
        .status = .supported,
    },
    .{
        .case_id = "optional_basic",
        .label = "bridge.optional_basic",
        .source_kind = .example,
        .source_module = "examples/optional_basic.zig",
        .fixture_module = fixtureModulePath("optional_basic"),
        .entry_symbol = "run",
        .scenario_id = .optional_basic,
        .status = .supported,
    },
    .{
        .case_id = "exception_basic",
        .label = "bridge.exception_basic",
        .source_kind = .example,
        .source_module = "examples/exception_basic.zig",
        .fixture_module = fixtureModulePath("exception_basic"),
        .entry_symbol = "run",
        .scenario_id = .exception_basic,
        .status = .supported,
    },
    .{
        .case_id = "resource_basic",
        .label = "bridge.resource_basic",
        .source_kind = .example,
        .source_module = "examples/resource_basic.zig",
        .fixture_module = fixtureModulePath("resource_basic"),
        .entry_symbol = "run",
        .scenario_id = .resource_basic,
        .status = .supported,
    },
    .{
        .case_id = "writer_basic",
        .label = "bridge.writer_basic",
        .source_kind = .example,
        .source_module = "examples/writer_basic.zig",
        .fixture_module = fixtureModulePath("writer_basic"),
        .entry_symbol = "run",
        .scenario_id = .writer_basic,
        .status = .supported,
    },
    .{
        .case_id = "open_row_abortive_validation",
        .label = "bridge.open_row_abortive_validation",
        .source_kind = .example,
        .source_module = "examples/open_row_abortive_validation.zig",
        .fixture_module = fixtureModulePath("open_row_abortive_validation"),
        .entry_symbol = "run",
        .scenario_id = .algebraic_abortive_validation,
        .status = .supported,
    },
    .{
        .case_id = "open_row_artifact_search",
        .label = "bridge.open_row_artifact_search",
        .source_kind = .example,
        .source_module = "examples/open_row_artifact_search.zig",
        .fixture_module = fixtureModulePath("open_row_artifact_search"),
        .entry_symbol = "run",
        .scenario_id = .algebraic_artifact_search,
        .status = .supported,
    },
};

/// Look up one bridge case by stable case id.
pub fn find(case_id: []const u8) ?*const Case {
    for (&cases) |*case| {
        if (std.mem.eql(u8, case.case_id, case_id)) return case;
    }
    return null;
}

/// Count blocked bridge cases in the current manifest.
pub fn blockedCount() usize {
    var count: usize = 0;
    for (cases) |case| {
        if (case.status == .blocked) count += 1;
    }
    return count;
}
