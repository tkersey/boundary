const authoring_lowerer = @import("authoring_lowerer");
const build_options = @import("build_options");
const error_witness = @import("error_witness");
const lowered_machine = @import("lowered_machine");
const parity_scenarios = @import("parity_scenarios");
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

/// Error surface for source-lowering entrypoints.
pub const LowerError = anyerror;

const Match = struct {
    required_snippets: []const []const u8,
    entry_required_snippets: []const []const u8 = &.{},
    feature_flags: []const []const u8,
};

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
        "const EarlyExitProgram = shift.Program(.{",
        "shift.Decl.exception([]const u8, catch_policy)",
        "try eff.exception.throw(\"result=early\");",
        "transcript.handler_line = \"handler-direct-return\";",
    },
    .entry_required_snippets = &.{
        "const result = try shift.run(&runtime, EarlyExitProgram, .{});",
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
        "const early = try shift.run(&runtime, ReturnNowProgram, .{});",
        "const resumed = try shift.run(&runtime, ResumeProgram, .{});",
    },
    .feature_flags = &.{ "lexical_optional", "return_now", "resume_with", "promoted_example" },
};

const nested_workflow_match = Match{
    .required_snippets = &.{
        "const Approval = shift.Decl.family",
        "eff.approval.publish.perform",
        "approval=publish",
    },
    .entry_required_snippets = &.{
        "const result = try shift.run(&runtime, WorkflowProgram, .{",
        "try writer.print(\"result={s}\\n\", .{result.value});",
    },
    .feature_flags = &.{ "generated_choice", "nested_workflow", "promoted_example" },
};

const front_door_workflow_match = Match{
    .required_snippets = &.{
        "shift.Op.Transform(\"search\", []const u8, i32)",
        "const total = try eff.search.search.perform(\"artifact-search\");",
        "try eff.writer.tell(\"workflow=queued\");",
        "return try eff.approval.publish.perform(struct {",
    },
    .entry_required_snippets = &.{
        "const result = try shift.run(&runtime, Workflow, .{",
        "try writer.print(\"final_state={d}\\n\", .{result.outputs.state});",
        "try writer.print(\"result={s}\\n\", .{result.value});",
    },
    .feature_flags = &.{ "generated_transform", "generated_choice", "promoted_example" },
};

const state_example_match = Match{
    .required_snippets = &.{
        "const StateProgram = shift.Program(.{",
        "shift.Decl.state(i32)",
        "const before = try eff.state.get();",
        "try eff.state.set(before + 1);",
    },
    .entry_required_snippets = &.{
        "const result = try shift.run(&runtime, StateProgram, .{",
        "try writer.print(\"before=5\\nafter=6\\nfinal_state={d}\\nvalue={d}\\n\", .{ result.outputs.state, result.value });",
    },
    .feature_flags = &.{ "state_effect", "lexical_effect", "promoted_cohort_a" },
};

const reader_example_match = Match{
    .required_snippets = &.{
        "const ReaderProgram = shift.Program(.{",
        "shift.Decl.reader(i32)",
        "const env = try eff.reader.ask();",
        "return env * 2;",
    },
    .entry_required_snippets = &.{
        "const result = try shift.run(&runtime, ReaderProgram, .{",
        "try writer.print(\"env=21\\nvalue={d}\\n\", .{result.value});",
    },
    .feature_flags = &.{ "reader_effect", "lexical_effect", "promoted_cohort_a" },
};

const optional_example_match = Match{
    .required_snippets = &.{
        "policy-return-now",
        "policy-resume",
        "body-after-request",
        "shift.Decl.optional(i32, resume_policy)",
    },
    .entry_required_snippets = &.{
        "const early_result = try shift.run(&runtime, ReturnNowProgram, .{});",
        "const resumed = try shift.run(&runtime, ResumeProgram, .{});",
    },
    .feature_flags = &.{ "optional_effect", "lexical_effect", "promoted_cohort_a" },
};

const exception_example_match = Match{
    .required_snippets = &.{
        "branch=throw",
        "shift.Decl.exception([]const u8, catch_policy)",
        "try eff.exception.throw(\"result=boom\");",
        "catch={s}",
    },
    .entry_required_snippets = &.{
        "const ok = try shift.run(&runtime, ExceptionPassProgram, .{});",
        "const thrown = try shift.run(&runtime, ExceptionProgram, .{});",
        "try writer.print(\"catch={s}\\n\", .{transcript.caught_payload});",
        "try writer.print(\"final={s}\\n\", .{thrown.value});",
    },
    .feature_flags = &.{ "exception_effect", "lexical_effect", "promoted_cohort_a" },
};

const define_basic_match = Match{
    .required_snippets = &.{
        "const Counter = shift.Decl.family",
        "shift.Op.Transform(\"get\", void, i32)",
        "eff.counter.get.perform()",
        "eff.counter.set.perform(before + 1)",
        "counter={d}",
    },
    .entry_required_snippets = &.{
        "try writer.print(\"counter={d}\\n\", .{try runCounter(&runtime)});",
    },
    .feature_flags = &.{ "generated_transform", "user_defined_effect", "source_canonical" },
};

const define_choice_match = Match{
    .required_snippets = &.{
        "const Picker = shift.Decl.family",
        "shift.Op.Choice(\"pick\", i32, i32)",
        "eff.picker.pick.perform(41",
        "body-after-pick",
        "policy-after-resume",
    },
    .entry_required_snippets = &.{
        "const early = try shift.run(&runtime, PickerProgram, .{",
        "const resumed = try shift.run(&runtime, PickerProgram, .{",
        "try writer.writeAll(\"branch=return_now\\n\");",
        "try writer.writeAll(\"branch=resume_with\\n\");",
    },
    .feature_flags = &.{ "generated_choice", "user_defined_effect", "source_canonical" },
};

const define_abort_match = Match{
    .required_snippets = &.{
        "const Guard = shift.Decl.family",
        "shift.Op.Abort(\"fail\", []const u8)",
        "eff.guard.fail.abort(\"missing-name\")",
        "abort={s}",
    },
    .entry_required_snippets = &.{
        "const result = try shift.run(&runtime, GuardProgram, .{",
        "try writer.writeAll(\"validate=name\\n\");",
        "try writer.print(\"abort={s}\\n\", .{transcript.abort_line});",
    },
    .feature_flags = &.{ "generated_abort", "user_defined_effect", "source_canonical" },
};

const resource_example_match = Match{
    .required_snippets = &.{
        "shift.Decl.resource([]const u8, resource_manager)",
        "const first = try eff.resource.acquire();",
        "const second = try eff.resource.acquire();",
        "release=a",
    },
    .entry_required_snippets = &.{
        "const result = try shift.run(&runtime, ResourceProgram, .{});",
        "try writer.print(\"final={s}\\n\", .{result.value});",
    },
    .feature_flags = &.{ "resource_effect", "lexical_effect", "source_canonical" },
};

const writer_example_match = Match{
    .required_snippets = &.{
        "const WriterProgram = shift.Program(.{",
        "shift.Decl.writer([]const u8)",
        "try eff.writer.tell(\"a\")",
        "try eff.writer.tell(\"b\")",
        "value={s}",
    },
    .entry_required_snippets = &.{
        "const result = try shift.run(&runtime, WriterProgram, .{});",
        "try writer.print(\"value={s}\\n\", .{result.value});",
    },
    .feature_flags = &.{ "writer_effect", "lexical_effect", "source_canonical" },
};

const algebraic_abort_match = Match{
    .required_snippets = &.{
        "shift.Decl.family(.{",
        "shift.Op.Abort(\"fail\", []const u8)",
        "try eff.guard.fail.abort(\"missing-name\")",
        "abort={s}",
    },
    .entry_required_snippets = &.{
        "const result = try shift.run(&runtime, Validation, .{",
        "try writer.writeAll(\"validate=name\\n\");",
        "try writer.print(\"abort={s}\\n\", .{transcript.abort_line});",
    },
    .feature_flags = &.{ "algebraic_abort", "source_canonical" },
};

const algebraic_artifact_match = Match{
    .required_snippets = &.{
        "const Search = shift.Decl.family(.{",
        "shift.Op.Transform(\"search\", []const u8, i32)",
        "const total = try eff.search.search.perform(\"artifact-search\");",
        "opencode_source=jsonl",
    },
    .entry_required_snippets = &.{
        "const result = try shift.run(&runtime, ArtifactSearch, .{",
        "try writer.print(\"total={d}\\n\", .{result.value});",
    },
    .feature_flags = &.{ "algebraic_transform", "source_canonical" },
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
        if (std.mem.eql(u8, case_id, "example.define_basic")) return .{
            .case_id = case_id,
            .label = "source.example.define_basic",
            .source_path = "examples/define_basic.zig",
            .scenario_id = .define_basic,
            .status = .canonical,
            .match = define_basic_match,
        };
        if (std.mem.eql(u8, case_id, "example.define_choice_basic")) return .{
            .case_id = case_id,
            .label = "source.example.define_choice_basic",
            .source_path = "examples/define_choice_basic.zig",
            .scenario_id = .define_choice_basic,
            .status = .canonical,
            .match = define_choice_match,
        };
        if (std.mem.eql(u8, case_id, "example.define_abort_basic")) return .{
            .case_id = case_id,
            .label = "source.example.define_abort_basic",
            .source_path = "examples/define_abort_basic.zig",
            .scenario_id = .define_abort_basic,
            .status = .canonical,
            .match = define_abort_match,
        };
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
        if (std.mem.eql(u8, case_id, "example.front_door_workflow")) return .{
            .case_id = case_id,
            .label = "source.example.front_door_workflow",
            .source_path = "examples/front_door_workflow.zig",
            .scenario_id = .front_door_workflow,
            .status = .canonical,
            .match = front_door_workflow_match,
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
        if (std.mem.eql(u8, case_id, "example.algebraic_abortive_validation")) return .{
            .case_id = case_id,
            .label = "source.example.algebraic_abortive_validation",
            .source_path = "examples/algebraic_abortive_validation.zig",
            .scenario_id = .algebraic_abortive_validation,
            .status = .canonical,
            .match = algebraic_abort_match,
        };
        if (std.mem.eql(u8, case_id, "example.algebraic_artifact_search")) return .{
            .case_id = case_id,
            .label = "source.example.algebraic_artifact_search",
            .source_path = "examples/algebraic_artifact_search.zig",
            .scenario_id = .algebraic_artifact_search,
            .status = .canonical,
            .match = algebraic_artifact_match,
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
        if (std.mem.eql(u8, case_id, "user_defined.transform")) return .{
            .case_id = case_id,
            .label = "source.user_defined.transform",
            .source_path = "examples/define_basic.zig",
            .scenario_id = .define_basic,
            .status = .canonical,
            .match = define_basic_match,
        };
        if (std.mem.eql(u8, case_id, "user_defined.choice")) return .{
            .case_id = case_id,
            .label = "source.user_defined.choice",
            .source_path = "examples/define_choice_basic.zig",
            .scenario_id = .define_choice_basic,
            .status = .canonical,
            .match = define_choice_match,
        };
        if (std.mem.eql(u8, case_id, "user_defined.abort")) return .{
            .case_id = case_id,
            .label = "source.user_defined.abort",
            .source_path = "examples/define_abort_basic.zig",
            .scenario_id = .define_abort_basic,
            .status = .canonical,
            .match = define_abort_match,
        };
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

fn resolvedSourcePathAlloc(allocator: std.mem.Allocator, source_path: []const u8) ![]u8 {
    _ = build_options;
    return try std.fs.cwd().realpathAlloc(allocator, source_path);
}

fn resolvedRepoSourcePathAlloc(allocator: std.mem.Allocator, source_path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(source_path)) {
        return try std.fs.cwd().realpathAlloc(allocator, source_path);
    }

    var repo_dir = try std.fs.openDirAbsolute(build_options.package_root, .{});
    defer repo_dir.close();
    return try repo_dir.realpathAlloc(allocator, source_path);
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

    const lowered = try authoring_lowerer.lowerSourceText(
        allocator,
        loweringCase(spec, case),
        .{
            .display_path = spec.source_path,
            .actual_path = resolved_source_path,
            .source_text = source_text,
            .expected_status = spec.expected_status,
        },
    );
    return generatedProgramFromLowered(allocator, spec, case, lowered);
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

    const lowered = try authoring_lowerer.lowerFileBackedSourceText(
        allocator,
        loweringCase(spec, case),
        spec.source_path,
        actual_path,
        source_text,
        spec.expected_status,
    );
    return generatedProgramFromLowered(allocator, spec, case, lowered);
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
    const resolved_source_path = resolvedSourcePathAlloc(allocator, spec.source_path) catch try allocator.dupe(u8, spec.source_path);
    defer allocator.free(resolved_source_path);

    const lowered = try authoring_lowerer.lowerSourceFile(
        allocator,
        loweringCase(spec, case),
        spec.source_path,
        resolved_source_path,
        spec.expected_status,
    );
    return generatedProgramFromLowered(allocator, spec, case, lowered);
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
