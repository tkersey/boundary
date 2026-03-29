const parity_scenarios = @import("parity_scenarios");

/// Proof surface enum re-exported from the canonical scenario registry.
pub const Surface = parity_scenarios.Surface;
/// State checkpoint type re-exported from the canonical scenario registry.
pub const TraceCheckpoint = parity_scenarios.TraceCheckpoint;

/// One exact-output transcript case covered by `kernel-parity-check`.
pub const TranscriptCase = struct {
    case_id: []const u8,
    expected: []const u8,
    fixture_name: ?[]const u8,
    surface: Surface,
    state_trace_expected: []const TraceCheckpoint,
};

/// One runtime-positive proof case covered by `kernel-parity-check`.
pub const RuntimeCase = parity_scenarios.RuntimeSmoke;

fn makeTranscriptCase(scenario: *const parity_scenarios.Scenario) TranscriptCase {
    return .{
        .case_id = scenario.case_id,
        .expected = scenario.expected_transcript,
        .fixture_name = scenario.fixture_name,
        .surface = scenario.surface,
        .state_trace_expected = scenario.trace_checkpoints,
    };
}

fn makeTranscriptCaseByCaseId(case_id: []const u8) TranscriptCase {
    return makeTranscriptCase(parity_scenarios.find(case_id).?);
}

/// The exact-output corpus derived from the canonical scenario registry.
pub const transcript_cases = [_]TranscriptCase{
    makeTranscriptCase(parity_scenarios.byId(.atm_resume_transform)),
    makeTranscriptCase(parity_scenarios.byId(.direct_return)),
    makeTranscriptCase(parity_scenarios.byId(.resume_or_return_return_now)),
    makeTranscriptCase(parity_scenarios.byId(.resume_or_return_resume)),
    makeTranscriptCase(parity_scenarios.byId(.static_redelim)),
    makeTranscriptCase(parity_scenarios.byId(.multi_prompt)),
    makeTranscriptCase(parity_scenarios.byId(.generator)),
    makeTranscriptCaseByCaseId("open_row_transform_basic"),
    makeTranscriptCaseByCaseId("open_row_choice_basic"),
    makeTranscriptCaseByCaseId("open_row_abort_basic"),
    makeTranscriptCase(parity_scenarios.byId(.early_exit)),
    makeTranscriptCase(parity_scenarios.byId(.resume_or_return)),
    makeTranscriptCaseByCaseId("open_row_workflow"),
    makeTranscriptCase(parity_scenarios.byId(.nested_workflow_publish)),
    makeTranscriptCase(parity_scenarios.byId(.reader_basic)),
    makeTranscriptCase(parity_scenarios.byId(.exception_basic)),
    makeTranscriptCase(parity_scenarios.byId(.optional_basic)),
    makeTranscriptCase(parity_scenarios.byId(.resource_basic)),
    makeTranscriptCase(parity_scenarios.byId(.writer_basic)),
    makeTranscriptCase(parity_scenarios.byId(.state_basic)),
    makeTranscriptCase(parity_scenarios.byId(.algebraic_abortive_validation)),
    makeTranscriptCase(parity_scenarios.byId(.algebraic_artifact_search)),
};

/// Runtime-positive smoke cases derived from the canonical scenario registry.
pub const runtime_cases = parity_scenarios.runtime_smokes;
