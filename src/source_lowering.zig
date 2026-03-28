const authoring_lowerer = @import("authoring_lowerer");
const effect_ir = @import("effect_ir");
const error_witness = @import("error_witness");
const lowered_machine = @import("lowered_machine");
const parity_scenarios = @import("parity_scenarios");
const program_frontend = @import("program_frontend");
const shipped_open_row_corpus = @import("shipped_open_row_corpus_registry");
const source_registry = @import("source_lowering_registry");
const std = @import("std");

/// Source classification for one restricted source-lowering request.
pub const SurfaceKind = enum {
    effect,
    example,
    source_case,
    user_defined_effect,
    witness,
};

/// Progress state for one source-lowering result.
pub const LowerStatus = authoring_lowerer.LowerStatus;

/// One source-lowering diagnostic with source location.
pub const Diagnostic = authoring_lowerer.Diagnostic;

/// One lowered-machine step emitted through the source-lowering surface.
pub const Step = lowered_machine.Step;

/// Input specification for one restricted source-lowering request.
pub const Spec = struct {
    case_id: []const u8,
    source_path: []const u8,
    entry_symbol: []const u8,
    surface_kind: SurfaceKind,
    expected_status: LowerStatus = .canonical,
};

/// Generated lowered program plus diagnostics for one restricted source-lowering input.
pub const GeneratedProgram = struct {
    case_id: []const u8,
    label: []const u8,
    source_path: []const u8,
    surface_kind: SurfaceKind,
    status: LowerStatus,
    canonical_scenario_id: ?parity_scenarios.ScenarioId,
    expected_transcript: []const u8,
    steps: []const lowered_machine.Step,
    feature_flags: []const []const u8,
    diagnostics: []const Diagnostic,
    error_witness: error_witness.ErrorWitnessV1,

    /// Release dynamically allocated slices owned by this generated program.
    pub fn deinit(self: *GeneratedProgram, allocator: std.mem.Allocator) void {
        allocator.free(self.source_path);
        allocator.free(self.steps);
        allocator.free(self.feature_flags);
        allocator.free(self.diagnostics);
        if (self.error_witness.diagnostics.len != 0) allocator.free(self.error_witness.diagnostics);
        self.* = undefined;
    }

    /// Return whether the source was accepted by the restricted lowerer.
    pub fn isAccepted(self: GeneratedProgram) bool {
        return self.status != .rejected;
    }
};

/// One open-row lowering record that keeps the resolved Effect IR plus its normalization proof.
pub const OpenRowGeneratedProgram = struct {
    label: []const u8,
    normalization: effect_ir.NormalizationDigest,
    program: effect_ir.Program,
};

/// Lower one open-row frontend payload into the Effect IR shell and capture its normalization digest.
pub fn lowerOpenRowProgram(program: program_frontend.OpenRowProgram) effect_ir.NormalizeError!OpenRowGeneratedProgram {
    const lowered = try authoring_lowerer.lowerOpenRowProgram(program);
    return .{
        .label = lowered.label,
        .normalization = lowered.normalization,
        .program = lowered.program,
    };
}

/// Error surface for source-lowering entrypoints.
pub const LowerError = anyerror;

const Match = struct {
    required_snippets: []const []const u8,
    entry_required_snippets: []const []const u8 = &.{},
    feature_flags: []const []const u8,
};

test "lowerOpenRowProgram preserves label and normalization digest" {
    const row = effect_ir.rowFromSpec(.{
        .state = .{
            .get = effect_ir.Transform(void, i32),
            .set = effect_ir.Transform(i32, void),
        },
        .writer = .{
            .tell = effect_ir.Transform([]const u8, void),
        },
    });
    const program = try lowerOpenRowProgram(.{
        .label = "example.open_row_state_writer",
        .function = .{
            .symbol = .{
                .module_path = "examples/open_row_state_writer.zig",
                .symbol_name = "Workflow",
            },
            .row = row,
            .outputs = &.{
                .{ .label = "state", .OutputType = i32 },
                .{ .label = "writer", .OutputType = []const []const u8 },
            },
        },
        .call_edges = &.{},
    });

    try std.testing.expectEqualStrings("example.open_row_state_writer", program.label);
    try std.testing.expectEqual(@as(usize, 2), program.normalization.requirement_count);
    try std.testing.expectEqual(@as(usize, 3), program.normalization.op_count);
    try std.testing.expectEqual(@as(usize, 2), program.normalization.output_count);
    try std.testing.expectEqual(@as(usize, 1), program.program.functions.len);
    _ = program_frontend;
}

const local_mutation_match = Match{
    .required_snippets = &.{
        "pub fn run(writer: anytype) anyerror!void {",
        "var local: i32 = 1;",
        "const resumed: i32 = 41;",
        "local += resumed;",
    },
    .entry_required_snippets = &.{
        "local += resumed;",
        "try writer.print(\"final={d}\\n\", .{local});",
    },
    .feature_flags = &.{ "locals", "mutation", "resume_value" },
};

const branch_match = Match{
    .required_snippets = &.{
        "pub fn run(writer: anytype) anyerror!void {",
        "const take_branch = true;",
        "if (take_branch) {",
        "answer = resumed + 1;",
    },
    .entry_required_snippets = &.{
        "answer = resumed + 1;",
        "try writer.print(\"final={d}\\n\", .{answer});",
    },
    .feature_flags = &.{ "if_else", "locals", "resume_value" },
};

const loop_match = Match{
    .required_snippets = &.{
        "pub fn run(writer: anytype) anyerror!void {",
        "while (i < 2) : (i += 1) {",
        "const resumed: i32 = 41;",
        "try writer.writeAll(\"loop=done\\n\");",
    },
    .entry_required_snippets = &.{
        "try writer.writeAll(\"loop=done\\n\");",
        "try writer.print(\"final={d}\\n\", .{resumed + 1});",
    },
    .feature_flags = &.{ "while_loop", "locals", "resume_value" },
};

const helper_match = Match{
    .required_snippets = &.{
        "fn helper(writer: anytype) anyerror!i32 {",
        "try writer.writeAll(\"helper=enter\\n\");",
        "try writer.writeAll(\"helper=exit\\n\");",
        "const answer = try helper(writer);",
    },
    .entry_required_snippets = &.{
        "const answer = try helper(writer);",
        "try writer.print(\"final={d}\\n\", .{answer});",
    },
    .feature_flags = &.{ "same_module_helper", "resume_value", "calls" },
};

const nested_match = Match{
    .required_snippets = &.{
        "fn inner(writer: anytype) anyerror!i32 {",
        "fn outer(writer: anytype) anyerror!i32 {",
        "const inner_value = try inner(writer);",
        "const answer = try outer(writer);",
    },
    .entry_required_snippets = &.{
        "const answer = try outer(writer);",
        "try writer.print(\"final={d}\\n\", .{answer});",
    },
    .feature_flags = &.{ "nested_helpers", "static_redelim_shape", "calls" },
};

const typed_error_match = Match{
    .required_snippets = &.{
        "const DemoError = error{Boom};",
        "const value = try succeed();",
        "_ = fail() catch |err| switch (err) {",
        "error.Boom => {",
    },
    .entry_required_snippets = &.{
        "const value = try succeed();",
        "try writer.writeAll(\"final=error=boom\\n\");",
    },
    .feature_flags = &.{ "typed_error", "try", "catch" },
};

const defer_match = Match{
    .required_snippets = &.{
        "defer writeCleanup(writer, \"defer=cleanup\\n\");",
        "fn body(writer: anytype) anyerror!i32 {",
        "const answer = try body(writer);",
    },
    .entry_required_snippets = &.{
        "const answer = try body(writer);",
        "try writer.print(\"final={d}\\n\", .{answer});",
    },
    .feature_flags = &.{ "defer", "resume_value", "helper_body" },
};

const errdefer_match = Match{
    .required_snippets = &.{
        "errdefer writeCleanup(writer, \"errdefer=cleanup\\n\");",
        "fn body(writer: anytype) anyerror!void {",
        "body(writer) catch |err| switch (err) {",
    },
    .entry_required_snippets = &.{
        "body(writer) catch |err| switch (err) {",
        "try writer.writeAll(\"final=error=boom\\n\");",
    },
    .feature_flags = &.{ "errdefer", "error_path", "helper_body" },
};

const early_exit_match = Match{
    .required_snippets = &.{
        "const EarlyExitRow = shift.effects.exception([]const u8);",
        "pub const Uses = shift.Uses(EarlyExitRow);",
        "try eff.exception.throw(\"result=early\");",
        "transcript.handler_line = \"handler-direct-return\";",
    },
    .entry_required_snippets = &.{
        "const closed = shift.bind(EarlyExitWorkflow, .{",
        "const result = try shift.run(&runtime, closed);",
        "try writer.print(\"final={s}\\n\", .{result.value});",
    },
    .feature_flags = &.{ "lexical_exception", "direct_return", "promoted_example" },
};

const resume_or_return_example_match = Match{
    .required_snippets = &.{
        "branch=return_now",
        "branch=resume_with",
        "handler-decide-resume",
        "body-after-shift",
    },
    .entry_required_snippets = &.{
        "try writer.writeAll(\"branch=return_now\\n\");",
        "const return_now_closed = shift.bind(ReturnNowWorkflow, .{",
        "const early = try shift.run(&runtime, return_now_closed);",
        "const resume_closed = shift.bind(ResumeWorkflow, .{",
        "const resumed = try shift.run(&runtime, resume_closed);",
    },
    .feature_flags = &.{ "lexical_optional", "return_now", "resume_with", "promoted_example" },
};

const nested_workflow_match = Match{
    .required_snippets = &.{
        "const ApprovalRow = shift.effects.optional([]const u8);",
        "const approved = try eff.optional.request(struct {",
        "approval=publish",
    },
    .entry_required_snippets = &.{
        "const closed = shift.bind(Workflow, .{",
        "const result = try shift.run(&runtime, closed);",
        "try writer.print(\"result={s}\\n\", .{result.value});",
    },
    .feature_flags = &.{ "lexical_optional", "nested_workflow", "promoted_example" },
};

const state_example_match = Match{
    .required_snippets = &.{
        "const StateRow = shift.effects.state(i32);",
        "pub const Uses = shift.Uses(StateRow);",
        "const before = try eff.state.get();",
        "try eff.state.set(before + 1);",
    },
    .entry_required_snippets = &.{
        "const closed = shift.bind(StateWorkflow, .{",
        "const result = try shift.run(&runtime, closed);",
        "try writer.print(\"before=5\\nafter=6\\nfinal_state={d}\\nvalue={d}\\n\", .{ result.outputs.state, result.value });",
    },
    .feature_flags = &.{ "state_effect", "lexical_effect", "promoted_cohort_a" },
};

const reader_example_match = Match{
    .required_snippets = &.{
        "const ReaderRow = shift.effects.reader(i32);",
        "pub const Uses = shift.Uses(ReaderRow);",
        "const env = try eff.reader.ask();",
        "return env * 2;",
    },
    .entry_required_snippets = &.{
        "const closed = shift.bind(ReaderWorkflow, .{",
        "const result = try shift.run(&runtime, closed);",
        "try writer.print(\"env=21\\nvalue={d}\\n\", .{result.value});",
    },
    .feature_flags = &.{ "reader_effect", "lexical_effect", "promoted_cohort_a" },
};

const optional_example_match = Match{
    .required_snippets = &.{
        "policy-return-now",
        "policy-resume",
        "body-after-request",
        "const OptionalRow = shift.effects.optional(i32);",
    },
    .entry_required_snippets = &.{
        "const return_now_closed = shift.bind(ReturnNowWorkflow, .{",
        "const early_result = try shift.run(&runtime, return_now_closed);",
        "const resume_closed = shift.bind(ResumeWorkflow, .{",
        "const resumed = try shift.run(&runtime, resume_closed);",
    },
    .feature_flags = &.{ "optional_effect", "lexical_effect", "promoted_cohort_a" },
};

const exception_example_match = Match{
    .required_snippets = &.{
        "branch=throw",
        "const ExceptionRow = shift.effects.exception([]const u8);",
        "try eff.exception.throw(\"result=boom\");",
        "catch={s}",
    },
    .entry_required_snippets = &.{
        "const pass_closed = shift.bind(ExceptionPassWorkflow, .{",
        "const ok = try shift.run(&runtime, pass_closed);",
        "const throw_closed = shift.bind(ExceptionWorkflow, .{",
        "const thrown = try shift.run(&runtime, throw_closed);",
        "try writer.print(\"catch={s}\\n\", .{transcript.caught_payload});",
        "try writer.print(\"final={s}\\n\", .{thrown.value});",
    },
    .feature_flags = &.{ "exception_effect", "lexical_effect", "promoted_cohort_a" },
};

const open_row_transform_match = Match{
    .required_snippets = &.{
        "const counter_row = shift.Row(.{",
        "shift.Transform(void, i32)",
        "eff.counter.get.perform()",
        "eff.counter.set.perform(before + 1)",
        "counter={d}",
    },
    .entry_required_snippets = &.{
        "try writer.print(\"counter={d}\\n\", .{try runCounter(&runtime)});",
    },
    .feature_flags = &.{ "generated_transform", "user_defined_effect", "open_row", "source_canonical" },
};

const open_row_choice_match = Match{
    .required_snippets = &.{
        "const picker_row = shift.Row(.{",
        "shift.Choice(i32, i32)",
        "eff.picker.pick.perform(41",
        "body-after-pick",
        "policy-after-resume",
    },
    .entry_required_snippets = &.{
        "const return_now_closed = shift.bind(picker_workflow, .{",
        "const early = try shift.run(&runtime, return_now_closed);",
        "const resume_closed = shift.bind(picker_workflow, .{",
        "const resumed = try shift.run(&runtime, resume_closed);",
    },
    .feature_flags = &.{ "generated_choice", "user_defined_effect", "open_row", "source_canonical" },
};

const open_row_abort_match = Match{
    .required_snippets = &.{
        "const guard_row = shift.Row(.{",
        "shift.Abort([]const u8)",
        "eff.guard.fail.abort(\"missing-name\")",
        "abort={s}",
    },
    .entry_required_snippets = &.{
        "const closed = shift.bind(guard_workflow, .{",
        "const result = try shift.run(&runtime, closed);",
        "try writer.writeAll(\"validate=name\\n\");",
        "try writer.print(\"abort={s}\\n\", .{transcript.abort_line});",
    },
    .feature_flags = &.{ "generated_abort", "user_defined_effect", "open_row", "source_canonical" },
};

const resource_example_match = Match{
    .required_snippets = &.{
        "const ResourceRow = shift.effects.resource([]const u8);",
        "pub const Uses = shift.Uses(ResourceRow);",
        ".resource = shift.handlers.resource([]const u8, resource_manager),",
        "const result = try shift.run(&runtime, shift.bind(ResourceProgram, .{",
        "const first = try eff.resource.acquire();",
        "const second = try eff.resource.acquire();",
        "release=a",
    },
    .entry_required_snippets = &.{
        "const result = try shift.run(&runtime, shift.bind(ResourceProgram, .{",
        "try writer.print(\"final={s}\\n\", .{result.value});",
    },
    .feature_flags = &.{ "resource_effect", "lexical_effect", "source_canonical" },
};

const writer_example_match = Match{
    .required_snippets = &.{
        "const WriterRow = shift.effects.writer([]const u8);",
        "pub const Uses = shift.Uses(WriterRow);",
        "try eff.writer.tell(\"a\")",
        "try eff.writer.tell(\"b\")",
        "const closed = shift.bind(WriterWorkflow, .{",
        "const result = try shift.run(&runtime, closed);",
        "value={s}",
    },
    .entry_required_snippets = &.{
        "try runWithAllocator(writer, std.heap.page_allocator);",
    },
    .feature_flags = &.{ "writer_effect", "lexical_effect", "source_canonical" },
};

const open_row_abortive_match = Match{
    .required_snippets = &.{
        "const validation_row = shift.Row(.{",
        "shift.Abort([]const u8)",
        "try eff.guard.fail.abort(\"missing-name\")",
        "abort={s}",
    },
    .entry_required_snippets = &.{
        "const closed = shift.bind(validation_workflow, .{",
        "const result = try shift.run(&runtime, closed);",
        "try writer.writeAll(\"validate=name\\n\");",
        "try writer.print(\"abort={s}\\n\", .{transcript.abort_line});",
    },
    .feature_flags = &.{ "generated_abort", "user_defined_effect", "open_row", "source_canonical" },
};

const open_row_artifact_match = Match{
    .required_snippets = &.{
        "const search_row = shift.Row(.{",
        "shift.Transform([]const u8, i32)",
        "const total = try eff.search.search.perform(\"artifact-search\");",
        "opencode_source=jsonl",
    },
    .entry_required_snippets = &.{
        "const closed = shift.bind(artifact_search_workflow, .{",
        "const result = try shift.run(&runtime, closed);",
        "try writer.print(\"total={d}\\n\", .{result.value});",
    },
    .feature_flags = &.{ "generated_transform", "user_defined_effect", "open_row", "source_canonical" },
};

const open_row_workflow_match = Match{
    .required_snippets = &.{
        "const workflow_row = shift.mergeRows(.{",
        "shift.effects.state(i32)",
        "shift.effects.writer([]const u8)",
        "const total = try eff.search.search.perform(\"artifact-search\");",
        "return try eff.approval.publish.perform(struct {",
    },
    .entry_required_snippets = &.{
        "try run_with_allocator(writer, std.heap.page_allocator);",
    },
    .feature_flags = &.{ "generated_transform", "generated_choice", "open_row", "source_canonical" },
};

const open_row_generator_match = Match{
    .required_snippets = &.{
        "const generator_row = shift.mergeRows(.{",
        "shift.effects.state(i32)",
        "shift.effects.writer([]const u8)",
        "try eff.writer.tell(line);",
        "done={d}",
    },
    .entry_required_snippets = &.{
        "try run_with_allocator(writer, std.heap.page_allocator);",
    },
    .feature_flags = &.{ "state_effect", "writer_effect", "open_row", "source_canonical" },
};

const witness_atm_match = Match{
    .required_snippets = &.{
        "pub fn runAtmResumeTransform(writer: anytype)",
        "transcript.note(\"handler-enter\")",
        "transcript.note(\"body-after-shift\")",
        "return \"answer=42\";",
    },
    .entry_required_snippets = &.{
        "pub fn runAtmResumeTransform(writer: anytype)",
        "_ = try eff.atm.step.perform();",
        "return \"answer=42\";",
    },
    .feature_flags = &.{ "witness", "transform", "source_canonical" },
};

const witness_direct_match = Match{
    .required_snippets = &.{
        "pub fn runDirectReturn(writer: anytype)",
        "transcript.handler_line = \"handler-direct-return\"",
        "try eff.exception.throw(\"result=early\")",
    },
    .entry_required_snippets = &.{
        "pub fn runDirectReturn(writer: anytype)",
        "try eff.exception.throw(\"result=early\")",
    },
    .feature_flags = &.{ "witness", "abort", "source_canonical" },
};

const witness_ror_return_match = Match{
    .required_snippets = &.{
        "pub fn runResumeOrReturnReturnNow(writer: anytype)",
        "transcript.note(\"handler-return-now\")",
        "return try eff.optional.request",
    },
    .entry_required_snippets = &.{
        "pub fn runResumeOrReturnReturnNow(writer: anytype)",
        "transcript.note(\"handler-return-now\")",
        "return try eff.optional.request",
    },
    .feature_flags = &.{ "witness", "choice_return_now", "source_canonical" },
};

const witness_ror_resume_match = Match{
    .required_snippets = &.{
        "pub fn runResumeOrReturnResume(writer: anytype)",
        "transcript.note(\"handler-decide-resume\")",
        "transcript.note(\"body-after-shift\")",
        "return \"answer=42\";",
    },
    .entry_required_snippets = &.{
        "pub fn runResumeOrReturnResume(writer: anytype)",
        "transcript.note(\"handler-decide-resume\")",
        "transcript.note(\"body-after-shift\")",
        "return \"answer=42\";",
    },
    .feature_flags = &.{ "witness", "choice_resume", "source_canonical" },
};

const witness_static_redelim_match = Match{
    .required_snippets = &.{
        "pub fn runStaticRedelim(writer: anytype)",
        "transcript.note(\"outer-handler-enter\")",
        "transcript.note(\"inner-handler-enter\")",
        "return inner_value + 9 + transcript.outer_value;",
    },
    .entry_required_snippets = &.{
        "pub fn runStaticRedelim(writer: anytype)",
        "transcript.outer_value = try outer_eff.outer.step.perform();",
        "return nested.value;",
    },
    .feature_flags = &.{ "witness", "static_redelim", "source_canonical" },
};

const witness_multi_prompt_match = Match{
    .required_snippets = &.{
        "pub fn runMultiPrompt(writer: anytype)",
        "transcript.note(\"outer-before-inner\")",
        "_ = eff.inner;",
        "_ = try eff.outer.step.perform();",
        "return 42;",
    },
    .entry_required_snippets = &.{
        "pub fn runMultiPrompt(writer: anytype)",
        "_ = eff.inner;",
        "return 42;",
    },
    .feature_flags = &.{ "witness", "multi_prompt", "source_canonical" },
};

const witness_generator_match = Match{
    .required_snippets = &.{
        "pub fn runGenerator(writer: anytype)",
        "lexical_runtime.with(&runtime, .{",
        "try eff.writer.tell(switch (next)",
        "\"yield=3\"",
        "done={d}",
    },
    .entry_required_snippets = &.{
        "pub fn runGenerator(writer: anytype)",
        "const result = try lexical_runtime.with(&runtime, .{",
        "while (true) {",
        "return current;",
    },
    .feature_flags = &.{ "witness", "generator", "source_canonical" },
};

fn customScenarioId(kind: shipped_open_row_corpus.CustomExampleKind) parity_scenarios.ScenarioId {
    return switch (kind) {
        .transform_basic => .define_basic,
        .choice_basic => .define_choice_basic,
        .abort_basic => .define_abort_basic,
        .workflow => .front_door_workflow,
        .abortive_validation => .algebraic_abortive_validation,
        .artifact_search => .algebraic_artifact_search,
        .generator => .generator,
    };
}

fn customMatch(kind: shipped_open_row_corpus.CustomExampleKind) Match {
    return switch (kind) {
        .transform_basic => open_row_transform_match,
        .choice_basic => open_row_choice_match,
        .abort_basic => open_row_abort_match,
        .workflow => open_row_workflow_match,
        .abortive_validation => open_row_abortive_match,
        .artifact_search => open_row_artifact_match,
        .generator => open_row_generator_match,
    };
}

fn customLabel(comptime row: shipped_open_row_corpus.CustomExample) []const u8 {
    return std.fmt.comptimePrint("source.{s}", .{row.example_case_id});
}

const SupportedCase = struct {
    case_id: []const u8,
    label: []const u8,
    source_path: []const u8,
    scenario_id: parity_scenarios.ScenarioId,
    status: LowerStatus,
    entry_symbol: []const u8 = "run",
    compare_scope: authoring_lowerer.CompareScope = .file,
    match: Match,
};

const boom_error_names = [_][]const u8{"Boom"};
const typed_error_contributors = [_]error_witness.Contributor{
    .{
        .kind = .body,
        .surface = .ordinary,
        .symbol = "fail",
        .error_names = boom_error_names[0..],
    },
};

const errdefer_error_contributors = [_]error_witness.Contributor{
    .{
        .kind = .body,
        .surface = .ordinary,
        .symbol = "body",
        .error_names = boom_error_names[0..],
    },
};

const WitnessTemplate = struct {
    setup_error_names: []const []const u8,
    semantic_error_names: []const []const u8,
    contributors: []const error_witness.Contributor,
};

fn matchForCaseId(case_id: []const u8) Match {
    if (std.mem.eql(u8, case_id, "source.local_mutation_resume")) return local_mutation_match;
    if (std.mem.eql(u8, case_id, "source.branch_resume")) return branch_match;
    if (std.mem.eql(u8, case_id, "source.loop_resume")) return loop_match;
    if (std.mem.eql(u8, case_id, "source.helper_call_resume")) return helper_match;
    if (std.mem.eql(u8, case_id, "source.nested_prompt_static_redelim")) return nested_match;
    if (std.mem.eql(u8, case_id, "source.typed_error_try")) return typed_error_match;
    if (std.mem.eql(u8, case_id, "source.defer_resume")) return defer_match;
    if (std.mem.eql(u8, case_id, "source.errdefer_error")) return errdefer_match;
    unreachable;
}

fn sourceSupportedCase(case: *const source_registry.Case) SupportedCase {
    return .{
        .case_id = case.case_id,
        .label = case.label,
        .source_path = case.fixture_path,
        .scenario_id = case.scenario_id,
        .status = switch (case.status) {
            .candidate_green => .candidate_green,
            .parity_green => .parity_green,
            .canonical => .canonical,
        },
        .match = matchForCaseId(case.case_id),
    };
}

fn setupHasOutOfMemory(surface_kind: SurfaceKind) bool {
    return switch (surface_kind) {
        .source_case => false,
        .example, .effect, .user_defined_effect, .witness => true,
    };
}

fn witnessTemplate(spec: Spec, case: SupportedCase) WitnessTemplate {
    if (std.mem.eql(u8, case.case_id, "source.typed_error_try")) return .{
        .setup_error_names = error_witness.setupErrorNames(setupHasOutOfMemory(spec.surface_kind)),
        .semantic_error_names = boom_error_names[0..],
        .contributors = typed_error_contributors[0..],
    };
    if (std.mem.eql(u8, case.case_id, "source.errdefer_error")) return .{
        .setup_error_names = error_witness.setupErrorNames(setupHasOutOfMemory(spec.surface_kind)),
        .semantic_error_names = boom_error_names[0..],
        .contributors = errdefer_error_contributors[0..],
    };
    return .{
        .setup_error_names = error_witness.setupErrorNames(setupHasOutOfMemory(spec.surface_kind)),
        .semantic_error_names = error_witness.no_error_names[0..],
        .contributors = error_witness.no_contributors[0..],
    };
}

fn rejectedWitnessTemplate(spec: Spec) WitnessTemplate {
    _ = spec;
    return .{
        .setup_error_names = error_witness.no_error_names[0..],
        .semantic_error_names = error_witness.no_error_names[0..],
        .contributors = error_witness.no_contributors[0..],
    };
}

fn promotedSupportedCase(case_id: []const u8, surface_kind: SurfaceKind) ?SupportedCase {
    if (surface_kind == .example) {
        inline for (shipped_open_row_corpus.custom_examples) |row| {
            if (std.mem.eql(u8, case_id, row.example_case_id)) return .{
                .case_id = case_id,
                .label = customLabel(row),
                .source_path = row.source_path,
                .scenario_id = customScenarioId(row.kind),
                .status = .canonical,
                .match = customMatch(row.kind),
            };
        }
        if (std.mem.eql(u8, case_id, "example.early_exit")) return .{
            .case_id = case_id,
            .label = "source.example.early_exit",
            .source_path = "examples/early_exit.zig",
            .scenario_id = .early_exit,
            .status = .canonical,
            .match = early_exit_match,
        };
        if (std.mem.eql(u8, case_id, "example.resume_or_return")) return .{
            .case_id = case_id,
            .label = "source.example.resume_or_return",
            .source_path = "examples/resume_or_return.zig",
            .scenario_id = .resume_or_return,
            .status = .canonical,
            .match = resume_or_return_example_match,
        };
        if (std.mem.eql(u8, case_id, "example.nested_workflow")) return .{
            .case_id = case_id,
            .label = "source.example.nested_workflow",
            .source_path = "examples/nested_workflow.zig",
            .scenario_id = .nested_workflow_publish,
            .status = .canonical,
            .match = nested_workflow_match,
        };
        if (std.mem.eql(u8, case_id, "example.state_basic")) return .{
            .case_id = case_id,
            .label = "source.example.state_basic",
            .source_path = "examples/state_basic.zig",
            .scenario_id = .state_basic,
            .status = .canonical,
            .match = state_example_match,
        };
        if (std.mem.eql(u8, case_id, "example.reader_basic")) return .{
            .case_id = case_id,
            .label = "source.example.reader_basic",
            .source_path = "examples/reader_basic.zig",
            .scenario_id = .reader_basic,
            .status = .canonical,
            .match = reader_example_match,
        };
        if (std.mem.eql(u8, case_id, "example.optional_basic")) return .{
            .case_id = case_id,
            .label = "source.example.optional_basic",
            .source_path = "examples/optional_basic.zig",
            .scenario_id = .optional_basic,
            .status = .canonical,
            .match = optional_example_match,
        };
        if (std.mem.eql(u8, case_id, "example.exception_basic")) return .{
            .case_id = case_id,
            .label = "source.example.exception_basic",
            .source_path = "examples/exception_basic.zig",
            .scenario_id = .exception_basic,
            .status = .canonical,
            .match = exception_example_match,
        };
        if (std.mem.eql(u8, case_id, "example.resource_basic")) return .{
            .case_id = case_id,
            .label = "source.example.resource_basic",
            .source_path = "examples/resource_basic.zig",
            .scenario_id = .resource_basic,
            .status = .canonical,
            .match = resource_example_match,
        };
        if (std.mem.eql(u8, case_id, "example.writer_basic")) return .{
            .case_id = case_id,
            .label = "source.example.writer_basic",
            .source_path = "examples/writer_basic.zig",
            .scenario_id = .writer_basic,
            .status = .canonical,
            .match = writer_example_match,
        };
    }
    if (surface_kind == .effect) {
        if (std.mem.eql(u8, case_id, "effect.state_basic")) return .{
            .case_id = case_id,
            .label = "source.effect.state_basic",
            .source_path = "examples/state_basic.zig",
            .scenario_id = .state_basic,
            .status = .canonical,
            .match = state_example_match,
        };
        if (std.mem.eql(u8, case_id, "effect.reader_basic")) return .{
            .case_id = case_id,
            .label = "source.effect.reader_basic",
            .source_path = "examples/reader_basic.zig",
            .scenario_id = .reader_basic,
            .status = .canonical,
            .match = reader_example_match,
        };
        if (std.mem.eql(u8, case_id, "effect.optional_basic")) return .{
            .case_id = case_id,
            .label = "source.effect.optional_basic",
            .source_path = "examples/optional_basic.zig",
            .scenario_id = .optional_basic,
            .status = .canonical,
            .match = optional_example_match,
        };
        if (std.mem.eql(u8, case_id, "effect.exception_basic")) return .{
            .case_id = case_id,
            .label = "source.effect.exception_basic",
            .source_path = "examples/exception_basic.zig",
            .scenario_id = .exception_basic,
            .status = .canonical,
            .match = exception_example_match,
        };
        if (std.mem.eql(u8, case_id, "effect.resource_basic")) return .{
            .case_id = case_id,
            .label = "source.effect.resource_basic",
            .source_path = "examples/resource_basic.zig",
            .scenario_id = .resource_basic,
            .status = .canonical,
            .match = resource_example_match,
        };
        if (std.mem.eql(u8, case_id, "effect.writer_basic")) return .{
            .case_id = case_id,
            .label = "source.effect.writer_basic",
            .source_path = "examples/writer_basic.zig",
            .scenario_id = .writer_basic,
            .status = .canonical,
            .match = writer_example_match,
        };
    }
    if (surface_kind == .user_defined_effect) {
        inline for (shipped_open_row_corpus.custom_examples) |row| {
            const user_defined_case_id = row.user_defined_case_id orelse continue;
            if (std.mem.eql(u8, case_id, user_defined_case_id)) return .{
                .case_id = case_id,
                .label = std.fmt.comptimePrint("source.{s}", .{user_defined_case_id}),
                .source_path = row.source_path,
                .scenario_id = customScenarioId(row.kind),
                .status = .canonical,
                .match = customMatch(row.kind),
            };
        }
    }
    if (surface_kind == .witness) {
        if (std.mem.eql(u8, case_id, "witness.atm_resume_transform")) return .{
            .case_id = case_id,
            .label = "source.witness.atm_resume_transform",
            .source_path = "src/witness_sources.zig",
            .scenario_id = .atm_resume_transform,
            .status = .canonical,
            .entry_symbol = "runAtmResumeTransform",
            .compare_scope = .entry,
            .match = witness_atm_match,
        };
        if (std.mem.eql(u8, case_id, "witness.direct_return")) return .{
            .case_id = case_id,
            .label = "source.witness.direct_return",
            .source_path = "src/witness_sources.zig",
            .scenario_id = .direct_return,
            .status = .canonical,
            .entry_symbol = "runDirectReturn",
            .compare_scope = .entry,
            .match = witness_direct_match,
        };
        if (std.mem.eql(u8, case_id, "witness.resume_or_return_return_now")) return .{
            .case_id = case_id,
            .label = "source.witness.resume_or_return_return_now",
            .source_path = "src/witness_sources.zig",
            .scenario_id = .resume_or_return_return_now,
            .status = .canonical,
            .entry_symbol = "runResumeOrReturnReturnNow",
            .compare_scope = .entry,
            .match = witness_ror_return_match,
        };
        if (std.mem.eql(u8, case_id, "witness.resume_or_return_resume")) return .{
            .case_id = case_id,
            .label = "source.witness.resume_or_return_resume",
            .source_path = "src/witness_sources.zig",
            .scenario_id = .resume_or_return_resume,
            .status = .canonical,
            .entry_symbol = "runResumeOrReturnResume",
            .compare_scope = .entry,
            .match = witness_ror_resume_match,
        };
        if (std.mem.eql(u8, case_id, "witness.static_redelim")) return .{
            .case_id = case_id,
            .label = "source.witness.static_redelim",
            .source_path = "src/witness_sources.zig",
            .scenario_id = .static_redelim,
            .status = .canonical,
            .entry_symbol = "runStaticRedelim",
            .compare_scope = .entry,
            .match = witness_static_redelim_match,
        };
        if (std.mem.eql(u8, case_id, "witness.multi_prompt")) return .{
            .case_id = case_id,
            .label = "source.witness.multi_prompt",
            .source_path = "src/witness_sources.zig",
            .scenario_id = .multi_prompt,
            .status = .canonical,
            .entry_symbol = "runMultiPrompt",
            .compare_scope = .entry,
            .match = witness_multi_prompt_match,
        };
        if (std.mem.eql(u8, case_id, "witness.generator")) return .{
            .case_id = case_id,
            .label = "source.witness.generator",
            .source_path = "src/witness_sources.zig",
            .scenario_id = .generator,
            .status = .canonical,
            .entry_symbol = "runGenerator",
            .compare_scope = .entry,
            .match = witness_generator_match,
        };
    }
    return null;
}

fn loweringSurfaceKind(surface_kind: SurfaceKind) authoring_lowerer.SurfaceKind {
    return switch (surface_kind) {
        .effect => .effect,
        .example => .example,
        .source_case => .source_case,
        .user_defined_effect => .user_defined_effect,
        .witness => .witness,
    };
}

fn loweringCase(spec: Spec, case: SupportedCase) authoring_lowerer.CanonicalCase {
    return .{
        .case_id = case.case_id,
        .label = case.label,
        .source_path = case.source_path,
        .entry_symbol = case.entry_symbol,
        .compare_scope = case.compare_scope,
        .surface_kind = loweringSurfaceKind(spec.surface_kind),
        .status = case.status,
        .scenario_id = case.scenario_id,
        .feature_flags = case.match.feature_flags,
    };
}

fn duplicateFeatureFlags(allocator: std.mem.Allocator, flags: []const []const u8) std.mem.Allocator.Error![]const []const u8 {
    const duped = try allocator.alloc([]const u8, flags.len);
    for (flags, 0..) |flag, idx| duped[idx] = flag;
    return duped;
}

fn duplicateWitnessDiagnostics(
    allocator: std.mem.Allocator,
    diagnostics: []const Diagnostic,
) std.mem.Allocator.Error![]const error_witness.WitnessDiagnostic {
    const duped = try allocator.alloc(error_witness.WitnessDiagnostic, diagnostics.len);
    for (diagnostics, 0..) |diag, idx| {
        duped[idx] = .{
            .code = diag.code,
            .message = diag.message,
            .path = diag.path,
            .line = diag.line,
            .column = diag.column,
        };
    }
    return duped;
}

fn duplicateSourcePath(allocator: std.mem.Allocator, path: []const u8) std.mem.Allocator.Error![]const u8 {
    return try allocator.dupe(u8, path);
}

fn resolvedRepoSourcePathAlloc(allocator: std.mem.Allocator, source_path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(source_path)) {
        return try std.fs.path.resolve(allocator, &.{source_path});
    }

    const repo_relative = try authoring_lowerer.resolveRepoSourcePathAlloc(allocator, source_path);
    if (std.fs.cwd().access(repo_relative, .{})) {
        return repo_relative;
    } else |_| {
        allocator.free(repo_relative);
    }

    const cwd_path = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd_path);
    return try std.fs.path.resolve(allocator, &.{ cwd_path, source_path });
}

fn stripLineCommentsAlloc(allocator: std.mem.Allocator, source: []const u8) std.mem.Allocator.Error![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var in_string = false;
    var escaped = false;
    var idx: usize = 0;
    while (idx < source.len) : (idx += 1) {
        const byte = source[idx];
        if (in_string) {
            try out.append(allocator, byte);
            if (escaped) {
                escaped = false;
            } else if (byte == '\\') {
                escaped = true;
            } else if (byte == '"') {
                in_string = false;
            }
            continue;
        }

        if (byte == '"') {
            in_string = true;
            try out.append(allocator, byte);
            continue;
        }
        if (byte == '/' and idx + 1 < source.len and source[idx + 1] == '/') {
            idx += 2;
            while (idx < source.len and source[idx] != '\n') : (idx += 1) {}
            if (idx < source.len and source[idx] == '\n') try out.append(allocator, '\n');
            continue;
        }
        try out.append(allocator, byte);
    }

    return try out.toOwnedSlice(allocator);
}

fn entryFunctionSourceSlice(tree: std.zig.Ast, source: []const u8, name: []const u8) ?[]const u8 {
    var container_buffer: [2]std.zig.Ast.Node.Index = undefined;
    const root = tree.fullContainerDecl(&container_buffer, .root) orelse return null;
    for (root.ast.members) |member| {
        var fn_buffer: [1]std.zig.Ast.Node.Index = undefined;
        const fn_proto = tree.fullFnProto(&fn_buffer, member) orelse continue;
        const name_token = fn_proto.name_token orelse continue;
        if (!std.mem.eql(u8, tree.tokenSlice(name_token), name)) continue;
        const start = tree.tokenStart(fn_proto.firstToken());
        const last = tree.lastToken(member);
        const end = tree.tokenStart(last) + @as(u32, @intCast(tree.tokenSlice(last).len));
        return source[start..end];
    }
    return null;
}

fn containsAllInScopes(
    full_source: []const u8,
    entry_source: []const u8,
    required_snippets: []const []const u8,
    entry_required_snippets: []const []const u8,
) bool {
    for (required_snippets) |snippet| {
        if (std.mem.indexOf(u8, full_source, snippet) == null) return false;
    }

    if (entry_required_snippets.len == 0) {
        for (required_snippets) |snippet| {
            if (std.mem.indexOf(u8, entry_source, snippet) == null) return false;
        }
        return true;
    }

    for (entry_required_snippets) |snippet| {
        if (std.mem.indexOf(u8, entry_source, snippet) == null) return false;
    }
    return true;
}

fn sourceMatchesDeclaredShape(
    allocator: std.mem.Allocator,
    case: SupportedCase,
    source_text: []const u8,
) !bool {
    const source_z = try allocator.dupeZ(u8, source_text);
    defer allocator.free(source_z);

    var tree = try std.zig.Ast.parse(allocator, source_z, .zig);
    defer tree.deinit(allocator);
    if (tree.errors.len != 0) return false;

    const stripped_source = try stripLineCommentsAlloc(allocator, source_z);
    defer allocator.free(stripped_source);
    const entry_source = entryFunctionSourceSlice(tree, source_z, case.entry_symbol) orelse return false;
    const stripped_entry_source = try stripLineCommentsAlloc(allocator, entry_source);
    defer allocator.free(stripped_entry_source);

    return containsAllInScopes(
        stripped_source,
        stripped_entry_source,
        case.match.required_snippets,
        case.match.entry_required_snippets,
    );
}

fn generatedProgramFromLowered(
    allocator: std.mem.Allocator,
    spec: Spec,
    case: SupportedCase,
    lowered: authoring_lowerer.LoweredAuthoring,
) std.mem.Allocator.Error!GeneratedProgram {
    const diagnostics = blk: {
        if (lowered.status != .rejected) break :blk lowered.diagnostics;
        const translated = try allocator.dupe(Diagnostic, lowered.diagnostics);
        allocator.free(lowered.diagnostics);
        for (translated) |*diag| {
            if (std.mem.eql(u8, diag.code, "structural_mismatch") or
                std.mem.eql(u8, diag.code, "canonical_source_drift") or
                std.mem.eql(u8, diag.code, "expected_status_mismatch") or
                std.mem.eql(u8, diag.code, "entry_missing"))
            {
                diag.code = "unsupported_shape";
            }
        }
        break :blk translated;
    };

    const witness = blk: {
        if (lowered.status == .rejected) {
            const template = rejectedWitnessTemplate(spec);
            const witness_diagnostics = try duplicateWitnessDiagnostics(allocator, diagnostics);
            errdefer allocator.free(witness_diagnostics);
            break :blk error_witness.ErrorWitnessV1{
                .surface = .ordinary,
                .support_status = .unsupported,
                .public_runtime_errors = error_witness.no_runtime_error_tags[0..],
                .setup_error_names = template.setup_error_names,
                .semantic_error_names = template.semantic_error_names,
                .contributors = template.contributors,
                .diagnostics = witness_diagnostics,
            };
        }

        const template = witnessTemplate(spec, case);
        break :blk error_witness.ErrorWitnessV1{
            .surface = .ordinary,
            .support_status = .supported,
            .public_runtime_errors = error_witness.no_runtime_error_tags[0..],
            .setup_error_names = template.setup_error_names,
            .semantic_error_names = template.semantic_error_names,
            .contributors = template.contributors,
            .diagnostics = error_witness.no_diagnostics[0..],
        };
    };

    return .{
        .case_id = lowered.case_id,
        .label = lowered.label,
        .source_path = lowered.source_path,
        .surface_kind = spec.surface_kind,
        .status = lowered.status,
        .canonical_scenario_id = lowered.canonical_scenario_id,
        .expected_transcript = lowered.expected_transcript,
        .steps = lowered.steps,
        .feature_flags = lowered.feature_flags,
        .diagnostics = diagnostics,
        .error_witness = witness,
    };
}

fn generatedRejectedProgram(
    allocator: std.mem.Allocator,
    spec: Spec,
    case: SupportedCase,
    message: []const u8,
) std.mem.Allocator.Error!GeneratedProgram {
    const source_path = try duplicateSourcePath(allocator, spec.source_path);
    errdefer allocator.free(source_path);
    const diagnostics = try allocator.alloc(Diagnostic, 1);
    errdefer allocator.free(diagnostics);
    diagnostics[0] = .{
        .code = "unsupported_shape",
        .message = message,
        .path = source_path,
        .line = 1,
        .column = 1,
    };
    const steps = try allocator.alloc(lowered_machine.Step, 0);
    errdefer allocator.free(steps);
    const feature_flags = try duplicateFeatureFlags(allocator, case.match.feature_flags);
    errdefer allocator.free(feature_flags);
    const template = rejectedWitnessTemplate(spec);
    const witness_diagnostics = try duplicateWitnessDiagnostics(allocator, diagnostics);
    errdefer allocator.free(witness_diagnostics);
    return .{
        .case_id = case.case_id,
        .label = case.label,
        .source_path = source_path,
        .surface_kind = spec.surface_kind,
        .status = .rejected,
        .canonical_scenario_id = case.scenario_id,
        .expected_transcript = "",
        .steps = steps,
        .feature_flags = feature_flags,
        .diagnostics = diagnostics,
        .error_witness = .{
            .surface = .ordinary,
            .support_status = .unsupported,
            .public_runtime_errors = error_witness.no_runtime_error_tags[0..],
            .setup_error_names = template.setup_error_names,
            .semantic_error_names = template.semantic_error_names,
            .contributors = template.contributors,
            .diagnostics = witness_diagnostics,
        },
    };
}

fn inspectSourceText(
    allocator: std.mem.Allocator,
    spec: Spec,
    case: SupportedCase,
    source_text: []const u8,
) !GeneratedProgram {
    if (!std.mem.eql(u8, spec.entry_symbol, case.entry_symbol)) {
        return generatedRejectedProgram(allocator, spec, case, "entry function does not match the supported source-lowering shape for this case");
    }
    if (spec.expected_status != case.status) {
        return generatedRejectedProgram(allocator, spec, case, "requested expected_status does not match the supported status for this case");
    }

    const resolved_source_path = resolvedRepoSourcePathAlloc(allocator, spec.source_path) catch try allocator.dupe(u8, spec.source_path);
    defer allocator.free(resolved_source_path);

    var lowered = try authoring_lowerer.lowerSourceText(
        allocator,
        loweringCase(spec, case),
        .{
            .display_path = spec.source_path,
            .actual_path = resolved_source_path,
            .source_text = source_text,
            .expected_status = spec.expected_status,
        },
    );
    var lowered_owned = true;
    errdefer if (lowered_owned) lowered.deinit(allocator);
    if (lowered.status != .rejected and !(try sourceMatchesDeclaredShape(allocator, case, source_text))) {
        lowered.deinit(allocator);
        lowered_owned = false;
        return generatedRejectedProgram(allocator, spec, case, "source does not match the currently supported restricted source-lowering shape");
    }
    const program = try generatedProgramFromLowered(allocator, spec, case, lowered);
    lowered_owned = false;
    return program;
}

fn inspectFileBackedSourceText(
    allocator: std.mem.Allocator,
    spec: Spec,
    case: SupportedCase,
    actual_path: []const u8,
    source_text: []const u8,
) !GeneratedProgram {
    if (!std.mem.eql(u8, spec.entry_symbol, case.entry_symbol)) {
        return generatedRejectedProgram(allocator, spec, case, "entry function does not match the supported source-lowering shape for this case");
    }
    if (spec.expected_status != case.status) {
        return generatedRejectedProgram(allocator, spec, case, "requested expected_status does not match the supported status for this case");
    }

    var lowered = try authoring_lowerer.lowerFileBackedSourceText(.{
        .allocator = allocator,
        .case = loweringCase(spec, case),
        .display_path = spec.source_path,
        .actual_path = actual_path,
        .source_text = source_text,
        .expected_status = spec.expected_status,
    });
    var lowered_owned = true;
    errdefer if (lowered_owned) lowered.deinit(allocator);
    if (lowered.status != .rejected and !(try sourceMatchesDeclaredShape(allocator, case, source_text))) {
        lowered.deinit(allocator);
        lowered_owned = false;
        return generatedRejectedProgram(allocator, spec, case, "source does not match the currently supported restricted source-lowering shape");
    }
    const program = try generatedProgramFromLowered(allocator, spec, case, lowered);
    lowered_owned = false;
    return program;
}

/// Inspect and lower one restricted source-lowering source file.
pub fn inspectSource(allocator: std.mem.Allocator, spec: Spec) LowerError!GeneratedProgram {
    const case = switch (spec.surface_kind) {
        .source_case => sourceSupportedCase(source_registry.find(spec.case_id) orelse return error.UnsupportedSourceCase),
        .example, .effect, .user_defined_effect, .witness => promotedSupportedCase(spec.case_id, spec.surface_kind) orelse return error.UnsupportedSourceCase,
    };
    if (!std.mem.eql(u8, spec.entry_symbol, case.entry_symbol)) {
        return generatedRejectedProgram(allocator, spec, case, "entry function does not match the supported source-lowering shape for this case");
    }
    if (spec.expected_status != case.status) {
        return generatedRejectedProgram(allocator, spec, case, "requested expected_status does not match the supported status for this case");
    }
    const resolved_source_path = resolvedRepoSourcePathAlloc(allocator, spec.source_path) catch try allocator.dupe(u8, spec.source_path);
    defer allocator.free(resolved_source_path);
    const source = std.fs.cwd().readFileAlloc(allocator, resolved_source_path, 1 << 20) catch {
        return generatedRejectedProgram(allocator, spec, case, "source file could not be read");
    };
    defer allocator.free(source);
    return inspectFileBackedSourceText(allocator, spec, case, resolved_source_path, source);
}

/// Inspect and lower one inline source body against a supported source-lowering case.
pub fn inspectInlineSource(allocator: std.mem.Allocator, spec: Spec, source_text: []const u8) LowerError!GeneratedProgram {
    const case = switch (spec.surface_kind) {
        .source_case => sourceSupportedCase(source_registry.find(spec.case_id) orelse return error.UnsupportedSourceCase),
        .example, .effect, .user_defined_effect, .witness => promotedSupportedCase(spec.case_id, spec.surface_kind) orelse return error.UnsupportedSourceCase,
    };
    return inspectSourceText(allocator, spec, case, source_text);
}

/// Inspect file-backed source text against the canonical file-backed lowering path without mutating the fixture on disk.
pub fn inspectFileBackedInlineSource(
    allocator: std.mem.Allocator,
    spec: Spec,
    source_text: []const u8,
) LowerError!GeneratedProgram {
    const case = switch (spec.surface_kind) {
        .source_case => sourceSupportedCase(source_registry.find(spec.case_id) orelse return error.UnsupportedSourceCase),
        .example, .effect, .user_defined_effect, .witness => promotedSupportedCase(spec.case_id, spec.surface_kind) orelse return error.UnsupportedSourceCase,
    };
    const resolved_source_path = resolvedRepoSourcePathAlloc(allocator, spec.source_path) catch try allocator.dupe(u8, spec.source_path);
    defer allocator.free(resolved_source_path);
    return inspectFileBackedSourceText(allocator, spec, case, resolved_source_path, source_text);
}

/// Lower one supported source-lowering fixture through the source-validated path.
pub fn lowerFixture(allocator: std.mem.Allocator, comptime Fixture: type) LowerError!GeneratedProgram {
    if (!@hasDecl(Fixture, "source_case_id")) {
        @compileError(@typeName(Fixture) ++ " must declare source_case_id");
    }
    const case = source_registry.find(Fixture.source_case_id) orelse return error.UnsupportedSourceCase;
    if (!@hasDecl(Fixture, "source")) {
        return error.UnsupportedSourceCase;
    }
    const supported = sourceSupportedCase(case);
    return inspectSourceText(allocator, .{
        .case_id = case.case_id,
        .source_path = case.fixture_path,
        .entry_symbol = "run",
        .surface_kind = .source_case,
        .expected_status = supported.status,
    }, supported, Fixture.source);
}

/// Execute one accepted generated program and render its transcript.
pub fn runLowered(writer: anytype, program: *const GeneratedProgram) anyerror!void {
    if (!program.isAccepted()) return error.RejectedGeneratedProgram;
    const state = lowered_machine.runSteps(program.steps);
    try lowered_machine.writeTranscript(writer, &state);
}
