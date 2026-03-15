const parity_scenarios = @import("parity_scenarios");
const std = @import("std");

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
    scenario_id: parity_scenarios.ScenarioId,
    status: Status,
    blocked_reason: ?[]const u8 = null,
};

/// Canonical bridge support registry for unchanged-body direct-style cases.
pub const cases = [_]Case{
    .{
        .case_id = "atm_resume_transform",
        .label = "bridge.atm_resume_transform",
        .source_kind = .witness,
        .source_module = "src/witnesses.zig",
        .scenario_id = .atm_resume_transform,
        .status = .supported,
    },
    .{
        .case_id = "direct_return",
        .label = "bridge.direct_return",
        .source_kind = .witness,
        .source_module = "src/witnesses.zig",
        .scenario_id = .direct_return,
        .status = .supported,
    },
    .{
        .case_id = "multi_prompt",
        .label = "bridge.multi_prompt",
        .source_kind = .witness,
        .source_module = "src/witnesses.zig",
        .scenario_id = .multi_prompt,
        .status = .supported,
    },
    .{
        .case_id = "resume_or_return_resume",
        .label = "bridge.resume_or_return_resume",
        .source_kind = .witness,
        .source_module = "src/witnesses.zig",
        .scenario_id = .resume_or_return_resume,
        .status = .supported,
    },
    .{
        .case_id = "resume_or_return_return_now",
        .label = "bridge.resume_or_return_return_now",
        .source_kind = .witness,
        .source_module = "src/witnesses.zig",
        .scenario_id = .resume_or_return_return_now,
        .status = .supported,
    },
    .{
        .case_id = "static_redelim",
        .label = "bridge.static_redelim",
        .source_kind = .witness,
        .source_module = "src/witnesses.zig",
        .scenario_id = .static_redelim,
        .status = .supported,
    },
    .{
        .case_id = "early_exit",
        .label = "bridge.early_exit",
        .source_kind = .example,
        .source_module = "examples/early_exit.zig",
        .scenario_id = .early_exit,
        .status = .supported,
    },
    .{
        .case_id = "resume_or_return",
        .label = "bridge.resume_or_return",
        .source_kind = .example,
        .source_module = "examples/resume_or_return.zig",
        .scenario_id = .resume_or_return,
        .status = .supported,
    },
    .{
        .case_id = "nested_workflow",
        .label = "bridge.nested_workflow",
        .source_kind = .example,
        .source_module = "examples/nested_workflow.zig",
        .scenario_id = .nested_workflow_publish,
        .status = .supported,
    },
    .{
        .case_id = "generator",
        .label = "bridge.generator",
        .source_kind = .example,
        .source_module = "examples/generator.zig",
        .scenario_id = .generator,
        .status = .supported,
    },
    .{
        .case_id = "state_basic",
        .label = "bridge.state_basic",
        .source_kind = .example,
        .source_module = "examples/state_basic.zig",
        .scenario_id = .state_basic,
        .status = .supported,
    },
    .{
        .case_id = "reader_basic",
        .label = "bridge.reader_basic",
        .source_kind = .example,
        .source_module = "examples/reader_basic.zig",
        .scenario_id = .reader_basic,
        .status = .supported,
    },
    .{
        .case_id = "optional_basic",
        .label = "bridge.optional_basic",
        .source_kind = .example,
        .source_module = "examples/optional_basic.zig",
        .scenario_id = .optional_basic,
        .status = .supported,
    },
    .{
        .case_id = "exception_basic",
        .label = "bridge.exception_basic",
        .source_kind = .example,
        .source_module = "examples/exception_basic.zig",
        .scenario_id = .exception_basic,
        .status = .supported,
    },
    .{
        .case_id = "resource_basic",
        .label = "bridge.resource_basic",
        .source_kind = .example,
        .source_module = "examples/resource_basic.zig",
        .scenario_id = .resource_basic,
        .status = .supported,
    },
    .{
        .case_id = "writer_basic",
        .label = "bridge.writer_basic",
        .source_kind = .example,
        .source_module = "examples/writer_basic.zig",
        .scenario_id = .writer_basic,
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
