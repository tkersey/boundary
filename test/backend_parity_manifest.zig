const semantic_manifest = @import("semantic_manifest.zig");

/// One locked proof surface covered by the parity machine.
pub const Engine = enum {
    legacy,
    typed_kernel,
};

/// One locked proof surface covered by the parity machine.
pub const Surface = enum {
    algebraic,
    effect,
    example,
    witness,
};

/// One exact-output transcript case covered by `backend-parity`.
pub const TranscriptCase = struct {
    case_id: []const u8,
    engine: Engine,
    surface: Surface,
    expected: []const u8,
    state_trace_expected_id: ?[]const u8 = null,
};

/// One runtime-positive proof case covered by `backend-parity`.
pub const RuntimeCase = struct {
    case_id: []const u8,
};

/// The exact-output corpus shared by the stackful runtime and the parity machine.
pub const transcript_cases = [_]TranscriptCase{
    .{ .case_id = "atm_resume_transform", .engine = .typed_kernel, .surface = .witness, .expected = semantic_manifest.find("atm_resume_transform").?.required_transcript, .state_trace_expected_id = "atm_resume_transform" },
    .{ .case_id = "direct_return", .engine = .typed_kernel, .surface = .witness, .expected = semantic_manifest.find("direct_return").?.required_transcript, .state_trace_expected_id = "direct_return" },
    .{ .case_id = "resume_or_return_return_now", .engine = .typed_kernel, .surface = .witness, .expected = semantic_manifest.find("resume_or_return_return_now").?.required_transcript, .state_trace_expected_id = "resume_or_return_return_now" },
    .{ .case_id = "resume_or_return_resume", .engine = .typed_kernel, .surface = .witness, .expected = semantic_manifest.find("resume_or_return_resume").?.required_transcript, .state_trace_expected_id = "resume_or_return_resume" },
    .{ .case_id = "static_redelim", .engine = .typed_kernel, .surface = .witness, .expected = semantic_manifest.find("static_redelim").?.required_transcript, .state_trace_expected_id = "static_redelim" },
    .{ .case_id = "multi_prompt", .engine = .typed_kernel, .surface = .witness, .expected = semantic_manifest.find("multi_prompt").?.required_transcript, .state_trace_expected_id = "multi_prompt" },
    .{ .case_id = "generator", .engine = .legacy, .surface = .example, .expected = @embedFile("example_proof/fixtures/generator.txt") },
    .{ .case_id = "early_exit", .engine = .legacy, .surface = .example, .expected = @embedFile("example_proof/fixtures/early_exit.txt") },
    .{ .case_id = "resume_or_return", .engine = .legacy, .surface = .example, .expected = @embedFile("example_proof/fixtures/resume_or_return.txt") },
    .{ .case_id = "nested_workflow", .engine = .typed_kernel, .surface = .example, .expected = @embedFile("example_proof/fixtures/nested_workflow.txt"), .state_trace_expected_id = "nested_workflow_publish" },
    .{ .case_id = "reader_basic", .engine = .legacy, .surface = .effect, .expected = @embedFile("example_proof/fixtures/reader_basic.txt") },
    .{ .case_id = "exception_basic", .engine = .legacy, .surface = .effect, .expected = @embedFile("example_proof/fixtures/exception_basic.txt") },
    .{ .case_id = "optional_basic", .engine = .legacy, .surface = .effect, .expected = @embedFile("example_proof/fixtures/optional_basic.txt") },
    .{ .case_id = "resource_basic", .engine = .legacy, .surface = .effect, .expected = @embedFile("example_proof/fixtures/resource_basic.txt") },
    .{ .case_id = "writer_basic", .engine = .legacy, .surface = .effect, .expected = @embedFile("example_proof/fixtures/writer_basic.txt") },
    .{ .case_id = "state_basic", .engine = .legacy, .surface = .effect, .expected = @embedFile("example_proof/fixtures/state_basic.txt") },
    .{ .case_id = "algebraic_abortive_validation", .engine = .legacy, .surface = .algebraic, .expected = @embedFile("example_proof/fixtures/algebraic_abortive_validation.txt") },
    .{ .case_id = "algebraic_artifact_search", .engine = .legacy, .surface = .algebraic, .expected = @embedFile("example_proof/fixtures/algebraic_artifact_search.txt") },
};

/// Runtime-positive smoke cases that must succeed on both proof paths.
pub const runtime_cases = [_]RuntimeCase{
    .{ .case_id = "protocol_resume_transform_runtime" },
};
