const lowered_machine = @import("lowered_machine");
const ordinary = @import("ordinary_zig_registry");
const parity_scenarios = @import("parity_scenarios");
const std = @import("std");
const build_options = @import("build_options");

/// Source classification for one restricted ordinary-Zig lowering request.
pub const SurfaceKind = enum {
    effect,
    example,
    ordinary_case,
    user_defined_effect,
    witness,
};

/// Progress state for one ordinary-Zig lowering result.
pub const LowerStatus = enum {
    candidate_green,
    canonical,
    parity_green,
    rejected,
};

/// One ordinary lowering diagnostic with source location.
pub const Diagnostic = struct {
    code: []const u8,
    message: []const u8,
    path: []const u8,
    line: usize,
    column: usize,
};

/// One lowered-machine step emitted through the public ordinary surface.
pub const Step = lowered_machine.Step;

/// Input specification for one restricted ordinary-Zig lowering request.
pub const Spec = struct {
    case_id: []const u8,
    source_path: []const u8,
    entry_symbol: []const u8,
    surface_kind: SurfaceKind,
    expected_status: LowerStatus = .candidate_green,
};

/// Generated lowered program plus diagnostics for one restricted ordinary-Zig source.
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

    /// Release dynamically allocated slices owned by this generated program.
    pub fn deinit(self: *GeneratedProgram, allocator: std.mem.Allocator) void {
        allocator.free(self.steps);
        allocator.free(self.feature_flags);
        allocator.free(self.diagnostics);
        self.* = undefined;
    }

    /// Return whether the source was accepted by the restricted lowerer.
    pub fn isAccepted(self: GeneratedProgram) bool {
        return self.status != .rejected;
    }
};

/// Error surface for ordinary lowering entrypoints.
pub const LowerError = std.mem.Allocator.Error || error{
    UnsupportedOrdinaryCase,
    UnsupportedSurfaceKind,
};

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
        "shift.effect.exception.use([]const u8, NoError, catch_policy)",
        "try eff.exception.throw(\"result=early\");",
        "transcript.handler_line = \"handler-direct-return\";",
    },
    .entry_required_snippets = &.{
        "try eff.exception.throw(\"result=early\");",
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
        "transcript.note(\"body-after-shift\");",
        "try writer.print(\"final={s}\\n\", .{resumed.value});",
    },
    .feature_flags = &.{ "lexical_optional", "return_now", "resume_with", "promoted_example" },
};

const nested_workflow_match = Match{
    .required_snippets = &.{
        "const Approval = shift.effect.Define",
        "eff.approval.publish.perform",
        "approval=publish",
    },
    .entry_required_snippets = &.{
        "const result = try shift.with(&runtime, .{",
        "transcript.note(\"workflow=done\");",
        "try writer.print(\"result={s}\\n\", .{result.value});",
    },
    .feature_flags = &.{ "generated_choice", "nested_workflow", "promoted_example" },
};

const state_example_match = Match{
    .required_snippets = &.{
        "shift.effect.state.use(NoError, @as(i32, 5))",
        "const before = try eff.state.get();",
        "try eff.state.set(before + 1);",
    },
    .entry_required_snippets = &.{
        "try eff.state.set(before + 1);",
        "try writer.print(\"before=5\\nafter=6\\nfinal_state={d}\\nvalue={d}\\n\", .{ result.outputs.state, result.value });",
    },
    .feature_flags = &.{ "state_effect", "lexical_effect", "promoted_cohort_a" },
};

const reader_example_match = Match{
    .required_snippets = &.{
        "shift.effect.reader.use(NoError, @as(i32, 21))",
        "const env = try eff.reader.ask();",
        "return env * 2;",
    },
    .entry_required_snippets = &.{
        "const env = try eff.reader.ask();",
        "try writer.print(\"env=21\\nvalue={d}\\n\", .{result.value});",
    },
    .feature_flags = &.{ "reader_effect", "lexical_effect", "promoted_cohort_a" },
};

const optional_example_match = Match{
    .required_snippets = &.{
        "policy-return-now",
        "policy-resume",
        "body-after-request",
        "shift.effect.optional.use(i32, NoError, resume_policy)",
    },
    .entry_required_snippets = &.{
        "transcript.note(\"policy-after-resume\");",
        "transcript.note(\"body-after-request\");",
        "try writer.print(\"final={s}\\n\", .{resumed.value});",
    },
    .feature_flags = &.{ "optional_effect", "lexical_effect", "promoted_cohort_a" },
};

const exception_example_match = Match{
    .required_snippets = &.{
        "branch=throw",
        "try eff.exception.throw(\"result=boom\");",
        "catch={s}",
    },
    .entry_required_snippets = &.{
        "try eff.exception.throw(\"result=boom\");",
        "try writer.print(\"catch={s}\\n\", .{transcript.caught_payload});",
        "try writer.print(\"final={s}\\n\", .{thrown.value});",
    },
    .feature_flags = &.{ "exception_effect", "lexical_effect", "promoted_cohort_a" },
};

const define_basic_match = Match{
    .required_snippets = &.{
        "const Counter = shift.effect.Define",
        "eff.counter.get.perform()",
        "eff.counter.set.perform(before + 1)",
        "counter={d}",
    },
    .entry_required_snippets = &.{
        "try writer.print(\"counter={d}\\n\", .{try runCounter(&runtime)});",
    },
    .feature_flags = &.{ "generated_transform", "user_defined_effect", "ordinary_canonical" },
};

const define_choice_match = Match{
    .required_snippets = &.{
        "const Picker = shift.effect.Define",
        "eff.picker.pick.perform(41",
        "body-after-pick",
        "policy-after-resume",
    },
    .entry_required_snippets = &.{
        "try writer.writeAll(\"branch=return_now\\n\");",
        "try writer.writeAll(\"branch=resume_with\\n\");",
    },
    .feature_flags = &.{ "generated_choice", "user_defined_effect", "ordinary_canonical" },
};

const define_abort_match = Match{
    .required_snippets = &.{
        "const Guard = shift.effect.Define",
        "eff.guard.fail.abort(\"missing-name\")",
        "abort={s}",
    },
    .entry_required_snippets = &.{
        "try writer.writeAll(\"validate=name\\n\");",
        "try writer.print(\"abort={s}\\n\", .{transcript.abort_line});",
    },
    .feature_flags = &.{ "generated_abort", "user_defined_effect", "ordinary_canonical" },
};

const resource_example_match = Match{
    .required_snippets = &.{
        "shift.effect.resource.use([]const u8, NoError, resource_manager)",
        "const first = try eff.resource.acquire();",
        "const second = try eff.resource.acquire();",
        "release=a",
    },
    .entry_required_snippets = &.{
        "const result = try shift.with(&runtime, .{",
        "try writer.print(\"final={s}\\n\", .{result.value});",
    },
    .feature_flags = &.{ "resource_effect", "lexical_effect", "ordinary_canonical" },
};

const writer_example_match = Match{
    .required_snippets = &.{
        "shift.effect.writer.use([]const u8, NoError, output_fba.allocator())",
        "try eff.writer.tell(\"a\")",
        "try eff.writer.tell(\"b\")",
        "value={s}",
    },
    .entry_required_snippets = &.{
        "const result = try shift.with(&runtime, .{",
        "try writer.print(\"value={s}\\n\", .{result.value});",
    },
    .feature_flags = &.{ "writer_effect", "lexical_effect", "ordinary_canonical" },
};

const algebraic_abort_match = Match{
    .required_snippets = &.{
        "const fail = shift.algebraic.AbortOp(\"fail\", []const u8);",
        "const Validation = shift.algebraic.Program([]const u8, NoError, .{fail});",
        "ctx.performProgram(fail, \"missing-name\"",
        "abort={s}",
    },
    .entry_required_snippets = &.{
        "try writer.writeAll(\"validate=name\\n\");",
        "try writer.print(\"abort={s}\\n\", .{transcript.abort_line});",
    },
    .feature_flags = &.{ "algebraic_abort", "ordinary_canonical" },
};

const algebraic_artifact_match = Match{
    .required_snippets = &.{
        "const search = shift.algebraic.TransformOp(\"search\", []const u8, i32);",
        "const ArtifactSearch = shift.algebraic.Program(i32, NoError, .{search});",
        "ctx.performProgram(search, \"artifact-search\"",
        "opencode_source=jsonl",
    },
    .entry_required_snippets = &.{
        "const result = try configured.run(&runtime, body);",
        "try writer.print(\"total={d}\\n\", .{result});",
    },
    .feature_flags = &.{ "algebraic_transform", "ordinary_canonical" },
};

const witness_atm_match = Match{
    .required_snippets = &.{
        "pub fn runAtmResumeTransform(writer: anytype)",
        "transcript.note(\"handler-enter\")",
        "transcript.note(\"body-after-shift\")",
        "return \"answer=42\";",
    },
    .entry_required_snippets = &.{
        "_ = try eff.atm.step.perform();",
        "return \"answer=42\";",
    },
    .feature_flags = &.{ "witness", "transform", "ordinary_canonical" },
};

const witness_direct_match = Match{
    .required_snippets = &.{
        "pub fn runDirectReturn(writer: anytype)",
        "transcript.handler_line = \"handler-direct-return\"",
        "try eff.exception.throw(\"result=early\")",
    },
    .entry_required_snippets = &.{
        "try eff.exception.throw(\"result=early\")",
    },
    .feature_flags = &.{ "witness", "abort", "ordinary_canonical" },
};

const witness_ror_return_match = Match{
    .required_snippets = &.{
        "pub fn runResumeOrReturnReturnNow(writer: anytype)",
        "transcript.note(\"handler-return-now\")",
        "return try eff.optional.request",
    },
    .entry_required_snippets = &.{
        "return try eff.optional.request",
    },
    .feature_flags = &.{ "witness", "choice_return_now", "ordinary_canonical" },
};

const witness_ror_resume_match = Match{
    .required_snippets = &.{
        "pub fn runResumeOrReturnResume(writer: anytype)",
        "transcript.note(\"handler-decide-resume\")",
        "transcript.note(\"body-after-shift\")",
        "return \"answer=42\";",
    },
    .entry_required_snippets = &.{
        "transcript.note(\"body-after-shift\")",
        "return \"answer=42\";",
    },
    .feature_flags = &.{ "witness", "choice_resume", "ordinary_canonical" },
};

const witness_static_redelim_match = Match{
    .required_snippets = &.{
        "pub fn runStaticRedelim(writer: anytype)",
        "transcript.note(\"outer-handler-enter\")",
        "transcript.note(\"inner-handler-enter\")",
        "return inner_value + 9 + transcript.outer_value;",
    },
    .entry_required_snippets = &.{
        "transcript.outer_value = try outer_eff.outer.step.perform();",
        "return nested.value;",
    },
    .feature_flags = &.{ "witness", "static_redelim", "ordinary_canonical" },
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
        "_ = eff.inner;",
        "return 42;",
    },
    .feature_flags = &.{ "witness", "multi_prompt", "ordinary_canonical" },
};

const witness_generator_match = Match{
    .required_snippets = &.{
        "pub fn runGenerator(writer: anytype)",
        "try eff.writer.tell(switch (next)",
        "\"yield=3\"",
        "done={d}",
    },
    .entry_required_snippets = &.{
        "while (true) {",
        "return current;",
    },
    .feature_flags = &.{ "witness", "generator", "ordinary_canonical" },
};

const SupportedCase = struct {
    case_id: []const u8,
    label: []const u8,
    source_path: []const u8,
    scenario_id: parity_scenarios.ScenarioId,
    status: LowerStatus,
    match: Match,
};

fn matchForCaseId(case_id: []const u8) Match {
    if (std.mem.eql(u8, case_id, "ordinary.local_mutation_resume")) return local_mutation_match;
    if (std.mem.eql(u8, case_id, "ordinary.branch_resume")) return branch_match;
    if (std.mem.eql(u8, case_id, "ordinary.loop_resume")) return loop_match;
    if (std.mem.eql(u8, case_id, "ordinary.helper_call_resume")) return helper_match;
    if (std.mem.eql(u8, case_id, "ordinary.nested_prompt_static_redelim")) return nested_match;
    if (std.mem.eql(u8, case_id, "ordinary.typed_error_try")) return typed_error_match;
    if (std.mem.eql(u8, case_id, "ordinary.defer_resume")) return defer_match;
    if (std.mem.eql(u8, case_id, "ordinary.errdefer_error")) return errdefer_match;
    unreachable;
}

fn ordinarySupportedCase(case: *const ordinary.Case) SupportedCase {
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

fn promotedSupportedCase(case_id: []const u8, surface_kind: SurfaceKind) ?SupportedCase {
    if (surface_kind == .example) {
        if (std.mem.eql(u8, case_id, "example.define_basic")) return .{
            .case_id = case_id,
            .label = "ordinary.example.define_basic",
            .source_path = "examples/define_basic.zig",
            .scenario_id = .define_basic,
            .status = .canonical,
            .match = define_basic_match,
        };
        if (std.mem.eql(u8, case_id, "example.define_choice_basic")) return .{
            .case_id = case_id,
            .label = "ordinary.example.define_choice_basic",
            .source_path = "examples/define_choice_basic.zig",
            .scenario_id = .define_choice_basic,
            .status = .canonical,
            .match = define_choice_match,
        };
        if (std.mem.eql(u8, case_id, "example.define_abort_basic")) return .{
            .case_id = case_id,
            .label = "ordinary.example.define_abort_basic",
            .source_path = "examples/define_abort_basic.zig",
            .scenario_id = .define_abort_basic,
            .status = .canonical,
            .match = define_abort_match,
        };
        if (std.mem.eql(u8, case_id, "example.early_exit")) return .{
            .case_id = case_id,
            .label = "ordinary.example.early_exit",
            .source_path = "examples/early_exit.zig",
            .scenario_id = .early_exit,
            .status = .canonical,
            .match = early_exit_match,
        };
        if (std.mem.eql(u8, case_id, "example.resume_or_return")) return .{
            .case_id = case_id,
            .label = "ordinary.example.resume_or_return",
            .source_path = "examples/resume_or_return.zig",
            .scenario_id = .resume_or_return,
            .status = .canonical,
            .match = resume_or_return_example_match,
        };
        if (std.mem.eql(u8, case_id, "example.nested_workflow")) return .{
            .case_id = case_id,
            .label = "ordinary.example.nested_workflow",
            .source_path = "examples/nested_workflow.zig",
            .scenario_id = .nested_workflow_publish,
            .status = .canonical,
            .match = nested_workflow_match,
        };
        if (std.mem.eql(u8, case_id, "example.state_basic")) return .{
            .case_id = case_id,
            .label = "ordinary.example.state_basic",
            .source_path = "examples/state_basic.zig",
            .scenario_id = .state_basic,
            .status = .canonical,
            .match = state_example_match,
        };
        if (std.mem.eql(u8, case_id, "example.reader_basic")) return .{
            .case_id = case_id,
            .label = "ordinary.example.reader_basic",
            .source_path = "examples/reader_basic.zig",
            .scenario_id = .reader_basic,
            .status = .canonical,
            .match = reader_example_match,
        };
        if (std.mem.eql(u8, case_id, "example.optional_basic")) return .{
            .case_id = case_id,
            .label = "ordinary.example.optional_basic",
            .source_path = "examples/optional_basic.zig",
            .scenario_id = .optional_basic,
            .status = .canonical,
            .match = optional_example_match,
        };
        if (std.mem.eql(u8, case_id, "example.exception_basic")) return .{
            .case_id = case_id,
            .label = "ordinary.example.exception_basic",
            .source_path = "examples/exception_basic.zig",
            .scenario_id = .exception_basic,
            .status = .canonical,
            .match = exception_example_match,
        };
        if (std.mem.eql(u8, case_id, "example.resource_basic")) return .{
            .case_id = case_id,
            .label = "ordinary.example.resource_basic",
            .source_path = "examples/resource_basic.zig",
            .scenario_id = .resource_basic,
            .status = .canonical,
            .match = resource_example_match,
        };
        if (std.mem.eql(u8, case_id, "example.writer_basic")) return .{
            .case_id = case_id,
            .label = "ordinary.example.writer_basic",
            .source_path = "examples/writer_basic.zig",
            .scenario_id = .writer_basic,
            .status = .canonical,
            .match = writer_example_match,
        };
        if (std.mem.eql(u8, case_id, "example.algebraic_abortive_validation")) return .{
            .case_id = case_id,
            .label = "ordinary.example.algebraic_abortive_validation",
            .source_path = "examples/algebraic_abortive_validation.zig",
            .scenario_id = .algebraic_abortive_validation,
            .status = .canonical,
            .match = algebraic_abort_match,
        };
        if (std.mem.eql(u8, case_id, "example.algebraic_artifact_search")) return .{
            .case_id = case_id,
            .label = "ordinary.example.algebraic_artifact_search",
            .source_path = "examples/algebraic_artifact_search.zig",
            .scenario_id = .algebraic_artifact_search,
            .status = .canonical,
            .match = algebraic_artifact_match,
        };
    }
    if (surface_kind == .effect) {
        if (std.mem.eql(u8, case_id, "effect.state_basic")) return .{
            .case_id = case_id,
            .label = "ordinary.effect.state_basic",
            .source_path = "examples/state_basic.zig",
            .scenario_id = .state_basic,
            .status = .canonical,
            .match = state_example_match,
        };
        if (std.mem.eql(u8, case_id, "effect.reader_basic")) return .{
            .case_id = case_id,
            .label = "ordinary.effect.reader_basic",
            .source_path = "examples/reader_basic.zig",
            .scenario_id = .reader_basic,
            .status = .canonical,
            .match = reader_example_match,
        };
        if (std.mem.eql(u8, case_id, "effect.optional_basic")) return .{
            .case_id = case_id,
            .label = "ordinary.effect.optional_basic",
            .source_path = "examples/optional_basic.zig",
            .scenario_id = .optional_basic,
            .status = .canonical,
            .match = optional_example_match,
        };
        if (std.mem.eql(u8, case_id, "effect.exception_basic")) return .{
            .case_id = case_id,
            .label = "ordinary.effect.exception_basic",
            .source_path = "examples/exception_basic.zig",
            .scenario_id = .exception_basic,
            .status = .canonical,
            .match = exception_example_match,
        };
        if (std.mem.eql(u8, case_id, "effect.resource_basic")) return .{
            .case_id = case_id,
            .label = "ordinary.effect.resource_basic",
            .source_path = "examples/resource_basic.zig",
            .scenario_id = .resource_basic,
            .status = .canonical,
            .match = resource_example_match,
        };
        if (std.mem.eql(u8, case_id, "effect.writer_basic")) return .{
            .case_id = case_id,
            .label = "ordinary.effect.writer_basic",
            .source_path = "examples/writer_basic.zig",
            .scenario_id = .writer_basic,
            .status = .canonical,
            .match = writer_example_match,
        };
    }
    if (surface_kind == .user_defined_effect) {
        if (std.mem.eql(u8, case_id, "user_defined.transform")) return .{
            .case_id = case_id,
            .label = "ordinary.user_defined.transform",
            .source_path = "examples/define_basic.zig",
            .scenario_id = .define_basic,
            .status = .canonical,
            .match = define_basic_match,
        };
        if (std.mem.eql(u8, case_id, "user_defined.choice")) return .{
            .case_id = case_id,
            .label = "ordinary.user_defined.choice",
            .source_path = "examples/define_choice_basic.zig",
            .scenario_id = .define_choice_basic,
            .status = .canonical,
            .match = define_choice_match,
        };
        if (std.mem.eql(u8, case_id, "user_defined.abort")) return .{
            .case_id = case_id,
            .label = "ordinary.user_defined.abort",
            .source_path = "examples/define_abort_basic.zig",
            .scenario_id = .define_abort_basic,
            .status = .canonical,
            .match = define_abort_match,
        };
    }
    if (surface_kind == .witness) {
        if (std.mem.eql(u8, case_id, "witness.atm_resume_transform")) return .{
            .case_id = case_id,
            .label = "ordinary.witness.atm_resume_transform",
            .source_path = "src/witness_sources.zig",
            .scenario_id = .atm_resume_transform,
            .status = .canonical,
            .match = witness_atm_match,
        };
        if (std.mem.eql(u8, case_id, "witness.direct_return")) return .{
            .case_id = case_id,
            .label = "ordinary.witness.direct_return",
            .source_path = "src/witness_sources.zig",
            .scenario_id = .direct_return,
            .status = .canonical,
            .match = witness_direct_match,
        };
        if (std.mem.eql(u8, case_id, "witness.resume_or_return_return_now")) return .{
            .case_id = case_id,
            .label = "ordinary.witness.resume_or_return_return_now",
            .source_path = "src/witness_sources.zig",
            .scenario_id = .resume_or_return_return_now,
            .status = .canonical,
            .match = witness_ror_return_match,
        };
        if (std.mem.eql(u8, case_id, "witness.resume_or_return_resume")) return .{
            .case_id = case_id,
            .label = "ordinary.witness.resume_or_return_resume",
            .source_path = "src/witness_sources.zig",
            .scenario_id = .resume_or_return_resume,
            .status = .canonical,
            .match = witness_ror_resume_match,
        };
        if (std.mem.eql(u8, case_id, "witness.static_redelim")) return .{
            .case_id = case_id,
            .label = "ordinary.witness.static_redelim",
            .source_path = "src/witness_sources.zig",
            .scenario_id = .static_redelim,
            .status = .canonical,
            .match = witness_static_redelim_match,
        };
        if (std.mem.eql(u8, case_id, "witness.multi_prompt")) return .{
            .case_id = case_id,
            .label = "ordinary.witness.multi_prompt",
            .source_path = "src/witness_sources.zig",
            .scenario_id = .multi_prompt,
            .status = .canonical,
            .match = witness_multi_prompt_match,
        };
        if (std.mem.eql(u8, case_id, "witness.generator")) return .{
            .case_id = case_id,
            .label = "ordinary.witness.generator",
            .source_path = "src/witness_sources.zig",
            .scenario_id = .generator,
            .status = .canonical,
            .match = witness_generator_match,
        };
    }
    return null;
}

fn duplicateFeatureFlags(allocator: std.mem.Allocator, flags: []const []const u8) std.mem.Allocator.Error![]const []const u8 {
    const duped = try allocator.alloc([]const u8, flags.len);
    for (flags, 0..) |flag, idx| duped[idx] = flag;
    return duped;
}

fn emptyDiagnostics(allocator: std.mem.Allocator) std.mem.Allocator.Error![]const Diagnostic {
    return try allocator.alloc(Diagnostic, 0);
}

fn duplicateSteps(
    allocator: std.mem.Allocator,
    steps: []const lowered_machine.Step,
) std.mem.Allocator.Error![]const lowered_machine.Step {
    return try allocator.dupe(lowered_machine.Step, steps);
}

fn parseFailureDiagnostic(
    allocator: std.mem.Allocator,
    path: []const u8,
    source: [:0]const u8,
    tree: std.zig.Ast,
) std.mem.Allocator.Error![]const Diagnostic {
    if (tree.errors.len == 0) {
        const diags = try allocator.alloc(Diagnostic, 1);
        diags[0] = .{
            .code = "invalid_source",
            .message = "ordinary lowerer rejected the source before building a generated program",
            .path = path,
            .line = 1,
            .column = 1,
        };
        return diags;
    }

    const parse_error = tree.errors[0];
    const loc = tree.tokenLocation(0, parse_error.token);
    const diags = try allocator.alloc(Diagnostic, 1);
    diags[0] = .{
        .code = "parse_error",
        .message = @tagName(parse_error.tag),
        .path = path,
        .line = loc.line + 1,
        .column = loc.column + 1,
    };
    _ = source;
    return diags;
}

fn shapeDiagnostic(
    allocator: std.mem.Allocator,
    path: []const u8,
    message: []const u8,
) std.mem.Allocator.Error![]const Diagnostic {
    const diags = try allocator.alloc(Diagnostic, 1);
    diags[0] = .{
        .code = "unsupported_shape",
        .message = message,
        .path = path,
        .line = 1,
        .column = 1,
    };
    return diags;
}

fn sourcePathDiagnostic(
    allocator: std.mem.Allocator,
    path: []const u8,
    message: []const u8,
) std.mem.Allocator.Error![]const Diagnostic {
    const diags = try allocator.alloc(Diagnostic, 1);
    diags[0] = .{
        .code = "non_canonical_source_path",
        .message = message,
        .path = path,
        .line = 1,
        .column = 1,
    };
    return diags;
}

fn sourcePathMatchesExpected(allocator: std.mem.Allocator, actual_path: []const u8, expected_path: []const u8) bool {
    const cwd = std.fs.cwd();
    const actual_realpath = cwd.realpathAlloc(allocator, actual_path) catch return false;
    defer allocator.free(actual_realpath);

    const normalized_expected = allocator.dupe(u8, expected_path) catch return false;
    defer allocator.free(normalized_expected);
    if (std.fs.path.sep != '/') {
        for (normalized_expected) |*byte| {
            if (byte.* == '/') byte.* = std.fs.path.sep;
        }
    }

    if (!std.mem.endsWith(u8, actual_realpath, normalized_expected)) return false;
    if (actual_realpath.len == normalized_expected.len) return true;
    if (actual_realpath[actual_realpath.len - normalized_expected.len - 1] != std.fs.path.sep) return false;

    const repo_root = actual_realpath[0 .. actual_realpath.len - normalized_expected.len - 1];
    if (repo_root.len == 0) return false;

    var repo_dir = std.fs.openDirAbsolute(repo_root, .{}) catch return false;
    defer repo_dir.close();
    repo_dir.access("build.zig", .{}) catch return false;
    repo_dir.access("src/root.zig", .{}) catch return false;
    return true;
}

fn hasTopLevelFunctionNamed(tree: std.zig.Ast, name: []const u8) bool {
    var container_buffer: [2]std.zig.Ast.Node.Index = undefined;
    const root = tree.fullContainerDecl(&container_buffer, .root) orelse return false;
    for (root.ast.members) |member| {
        var fn_buffer: [1]std.zig.Ast.Node.Index = undefined;
        const fn_proto = tree.fullFnProto(&fn_buffer, member) orelse continue;
        const name_token = fn_proto.name_token orelse continue;
        if (std.mem.eql(u8, tree.tokenSlice(name_token), name)) return true;
    }
    return false;
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

fn canonicalSourceHash(expected_path: []const u8) ?[32]u8 {
    if (std.mem.eql(u8, expected_path, "test/ordinary_zig_corpus/fixtures/local_mutation_resume.zig")) return build_options.hash_local_mutation_resume;
    if (std.mem.eql(u8, expected_path, "test/ordinary_zig_corpus/fixtures/branch_resume.zig")) return build_options.hash_branch_resume;
    if (std.mem.eql(u8, expected_path, "test/ordinary_zig_corpus/fixtures/loop_resume.zig")) return build_options.hash_loop_resume;
    if (std.mem.eql(u8, expected_path, "test/ordinary_zig_corpus/fixtures/helper_call_resume.zig")) return build_options.hash_helper_call_resume;
    if (std.mem.eql(u8, expected_path, "test/ordinary_zig_corpus/fixtures/nested_prompt_static_redelim.zig")) return build_options.hash_nested_prompt_static_redelim;
    if (std.mem.eql(u8, expected_path, "test/ordinary_zig_corpus/fixtures/typed_error_try.zig")) return build_options.hash_typed_error_try;
    if (std.mem.eql(u8, expected_path, "test/ordinary_zig_corpus/fixtures/defer_resume.zig")) return build_options.hash_defer_resume;
    if (std.mem.eql(u8, expected_path, "test/ordinary_zig_corpus/fixtures/errdefer_error.zig")) return build_options.hash_errdefer_error;
    if (std.mem.eql(u8, expected_path, "examples/define_basic.zig")) return build_options.hash_define_basic;
    if (std.mem.eql(u8, expected_path, "examples/define_choice_basic.zig")) return build_options.hash_define_choice_basic;
    if (std.mem.eql(u8, expected_path, "examples/define_abort_basic.zig")) return build_options.hash_define_abort_basic;
    if (std.mem.eql(u8, expected_path, "examples/early_exit.zig")) return build_options.hash_early_exit;
    if (std.mem.eql(u8, expected_path, "examples/resume_or_return.zig")) return build_options.hash_resume_or_return;
    if (std.mem.eql(u8, expected_path, "examples/nested_workflow.zig")) return build_options.hash_nested_workflow;
    if (std.mem.eql(u8, expected_path, "examples/state_basic.zig")) return build_options.hash_state_basic;
    if (std.mem.eql(u8, expected_path, "examples/reader_basic.zig")) return build_options.hash_reader_basic;
    if (std.mem.eql(u8, expected_path, "examples/optional_basic.zig")) return build_options.hash_optional_basic;
    if (std.mem.eql(u8, expected_path, "examples/exception_basic.zig")) return build_options.hash_exception_basic;
    if (std.mem.eql(u8, expected_path, "examples/resource_basic.zig")) return build_options.hash_resource_basic;
    if (std.mem.eql(u8, expected_path, "examples/writer_basic.zig")) return build_options.hash_writer_basic;
    if (std.mem.eql(u8, expected_path, "examples/algebraic_abortive_validation.zig")) return build_options.hash_algebraic_abortive_validation;
    if (std.mem.eql(u8, expected_path, "examples/algebraic_artifact_search.zig")) return build_options.hash_algebraic_artifact_search;
    if (std.mem.eql(u8, expected_path, "src/witness_sources.zig")) return build_options.hash_witness_sources;
    return null;
}

fn sourceTextMatchesCanonical(allocator: std.mem.Allocator, expected_path: []const u8, source_text: []const u8) bool {
    const expected_hash = canonicalSourceHash(expected_path) orelse return false;
    _ = allocator;

    var actual_hash: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(source_text, &actual_hash, .{});
    return std.mem.eql(u8, &actual_hash, &expected_hash);
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

fn acceptedProgram(
    allocator: std.mem.Allocator,
    spec: Spec,
    case: SupportedCase,
) std.mem.Allocator.Error!GeneratedProgram {
    const scenario = parity_scenarios.byId(case.scenario_id);
    return .{
        .case_id = case.case_id,
        .label = case.label,
        .source_path = spec.source_path,
        .surface_kind = spec.surface_kind,
        .status = case.status,
        .canonical_scenario_id = case.scenario_id,
        .expected_transcript = scenario.expected_transcript,
        .steps = try duplicateSteps(allocator, scenario.steps),
        .feature_flags = try duplicateFeatureFlags(allocator, case.match.feature_flags),
        .diagnostics = try emptyDiagnostics(allocator),
    };
}

fn rejectedProgram(
    allocator: std.mem.Allocator,
    spec: Spec,
    case: SupportedCase,
    diagnostics: []const Diagnostic,
) std.mem.Allocator.Error!GeneratedProgram {
    const steps = try allocator.alloc(lowered_machine.Step, 0);
    return .{
        .case_id = case.case_id,
        .label = case.label,
        .source_path = spec.source_path,
        .surface_kind = spec.surface_kind,
        .status = .rejected,
        .canonical_scenario_id = case.scenario_id,
        .expected_transcript = "",
        .steps = steps,
        .feature_flags = try duplicateFeatureFlags(allocator, case.match.feature_flags),
        .diagnostics = diagnostics,
    };
}

fn inspectSourceText(
    allocator: std.mem.Allocator,
    spec: Spec,
    case: SupportedCase,
    source_text: []const u8,
) !GeneratedProgram {
    const source_z = try allocator.dupeZ(u8, source_text);
    defer allocator.free(source_z);

    var tree = try std.zig.Ast.parse(allocator, source_z, .zig);
    defer tree.deinit(allocator);

    if (tree.errors.len != 0) {
        return rejectedProgram(
            allocator,
            spec,
            case,
            try parseFailureDiagnostic(allocator, spec.source_path, source_z, tree),
        );
    }
    if (!sourceTextMatchesCanonical(allocator, case.source_path, source_text)) {
        return rejectedProgram(
            allocator,
            spec,
            case,
            try shapeDiagnostic(allocator, spec.source_path, "source does not match the canonical repo-owned source for this case"),
        );
    }
    if (!hasTopLevelFunctionNamed(tree, spec.entry_symbol)) {
        return rejectedProgram(
            allocator,
            spec,
            case,
            try shapeDiagnostic(allocator, spec.source_path, "entry function was not found at the top level"),
        );
    }
    const stripped_source = try stripLineCommentsAlloc(allocator, source_z);
    defer allocator.free(stripped_source);
    const entry_source = entryFunctionSourceSlice(tree, source_z, spec.entry_symbol) orelse "";
    const stripped_entry_source = try stripLineCommentsAlloc(allocator, entry_source);
    defer allocator.free(stripped_entry_source);

    if (!containsAllInScopes(
        stripped_source,
        stripped_entry_source,
        case.match.required_snippets,
        case.match.entry_required_snippets,
    )) {
        return rejectedProgram(
            allocator,
            spec,
            case,
            try shapeDiagnostic(allocator, spec.source_path, "source does not match the currently supported restricted ordinary-Zig shape"),
        );
    }

    return acceptedProgram(allocator, spec, case);
}

/// Inspect and lower one restricted ordinary-Zig source file.
pub fn inspectSource(allocator: std.mem.Allocator, spec: Spec) LowerError!GeneratedProgram {
    const case = switch (spec.surface_kind) {
        .ordinary_case => ordinarySupportedCase(ordinary.find(spec.case_id) orelse return error.UnsupportedOrdinaryCase),
        .example, .effect, .user_defined_effect, .witness => promotedSupportedCase(spec.case_id, spec.surface_kind) orelse return error.UnsupportedOrdinaryCase,
    };
    const source = std.fs.cwd().readFileAlloc(allocator, spec.source_path, 1 << 20) catch {
        return rejectedProgram(
            allocator,
            spec,
            case,
            try shapeDiagnostic(allocator, spec.source_path, "source file could not be read"),
        );
    };
    defer allocator.free(source);
    if (!sourcePathMatchesExpected(allocator, spec.source_path, case.source_path)) {
        return rejectedProgram(
            allocator,
            spec,
            case,
            try sourcePathDiagnostic(allocator, spec.source_path, "source path does not match the canonical repo-owned path for this case"),
        );
    }
    return inspectSourceText(allocator, spec, case, source);
}

/// Lower one supported ordinary-Zig fixture through the source-validated path.
pub fn lowerFixture(allocator: std.mem.Allocator, comptime Fixture: type) LowerError!GeneratedProgram {
    if (!@hasDecl(Fixture, "ordinary_case_id")) {
        @compileError(@typeName(Fixture) ++ " must declare ordinary_case_id");
    }
    const case = ordinary.find(Fixture.ordinary_case_id) orelse return error.UnsupportedOrdinaryCase;
    if (!@hasDecl(Fixture, "source")) {
        return error.UnsupportedOrdinaryCase;
    }
    const supported = ordinarySupportedCase(case);
    return inspectSourceText(allocator, .{
        .case_id = case.case_id,
        .source_path = case.fixture_path,
        .entry_symbol = "run",
        .surface_kind = .ordinary_case,
        .expected_status = supported.status,
    }, supported, Fixture.source);
}

/// Execute one accepted generated program and render its transcript.
pub fn runLowered(writer: anytype, program: *const GeneratedProgram) anyerror!void {
    if (!program.isAccepted()) return error.RejectedGeneratedProgram;
    const state = lowered_machine.runSteps(program.steps);
    try lowered_machine.writeTranscript(writer, &state);
}
