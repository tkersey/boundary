const parity_scenarios = @import("parity_scenarios");
const std = @import("std");

/// Fixed status for the wave-one source-lowering experimental corpus.
pub const Status = enum {
    candidate_green,
    canonical,
    parity_green,
};

/// One source-lowering experimental case proven by direct source execution and the lowered path.
pub const Case = struct {
    case_id: []const u8,
    label: []const u8,
    scenario_id: parity_scenarios.ScenarioId,
    fixture_path: []const u8,
    forbidden_transcript: ?[]const u8,
    note: []const u8,
    status: Status = .canonical,
};

/// Locked wave-one source-lowering cases.
pub const cases = [_]Case{
    .{
        .case_id = "source.local_mutation_resume",
        .label = "source.local_mutation_resume",
        .scenario_id = .source_local_mutation_resume,
        .fixture_path = "test/source_lowering_corpus/fixtures/local_mutation_resume.zig",
        .forbidden_transcript = "local=1\nlocal=42\nfinal=42\n",
        .note = "Local mutation around a resumed value now stays green through direct source execution and source-validated lowered generation.",
    },
    .{
        .case_id = "source.branch_resume",
        .label = "source.branch_resume",
        .scenario_id = .source_branch_resume,
        .fixture_path = "test/source_lowering_corpus/fixtures/branch_resume.zig",
        .forbidden_transcript = "branch=before\nresume=41\nbranch=after\nfinal=42\n",
        .note = "Branching around a resumed value now stays green through direct source execution and source-validated lowered generation.",
    },
    .{
        .case_id = "source.loop_resume",
        .label = "source.loop_resume",
        .scenario_id = .source_loop_resume,
        .fixture_path = "test/source_lowering_corpus/fixtures/loop_resume.zig",
        .forbidden_transcript = "loop=0\nresume=41\nloop=done\nfinal=42\n",
        .note = "A simple while loop around a resumed value now stays green through direct source execution and source-validated lowered generation.",
    },
    .{
        .case_id = "source.helper_call_resume",
        .label = "source.helper_call_resume",
        .scenario_id = .source_helper_call_resume,
        .fixture_path = "test/source_lowering_corpus/fixtures/helper_call_resume.zig",
        .forbidden_transcript = "helper=enter\nhelper=exit\nfinal=42\n",
        .note = "A same-module helper call now stays green through direct source execution and source-validated lowered generation.",
    },
    .{
        .case_id = "source.nested_prompt_static_redelim",
        .label = "source.nested_prompt_static_redelim",
        .scenario_id = .source_static_redelim,
        .fixture_path = "test/source_lowering_corpus/fixtures/nested_prompt_static_redelim.zig",
        .forbidden_transcript = "outer=enter\nouter=exit\nfinal=12\n",
        .note = "Nested prompt ordering now stays green through direct source execution and source-validated lowered generation.",
    },
    .{
        .case_id = "source.typed_error_try",
        .label = "source.typed_error_try",
        .scenario_id = .source_typed_error_try,
        .fixture_path = "test/source_lowering_corpus/fixtures/typed_error_try.zig",
        .forbidden_transcript = "branch=ok\nvalue=42\nbranch=err\nfinal=error=boom\n",
        .note = "Typed error propagation through try/catch now stays green through direct source execution and source-validated lowered generation.",
    },
    .{
        .case_id = "source.defer_resume",
        .label = "source.defer_resume",
        .scenario_id = .source_defer_resume,
        .fixture_path = "test/source_lowering_corpus/fixtures/defer_resume.zig",
        .forbidden_transcript = "body=enter\nresume=41\nfinal=42\n",
        .note = "Defer cleanup now stays green through direct source execution and source-validated lowered generation.",
    },
    .{
        .case_id = "source.errdefer_error",
        .label = "source.errdefer_error",
        .scenario_id = .source_errdefer_error,
        .fixture_path = "test/source_lowering_corpus/fixtures/errdefer_error.zig",
        .forbidden_transcript = "body=enter\nerror=boom\nfinal=error=boom\n",
        .note = "Errdefer cleanup now stays green through direct source execution and source-validated lowered generation.",
    },
};

/// Find one source-lowering case by stable id.
pub fn find(case_id: []const u8) ?*const Case {
    for (&cases) |*case| {
        if (std.mem.eql(u8, case.case_id, case_id)) return case;
    }
    return null;
}
