const formal_core = @import("formal_core_registry");
const std = @import("std");

/// One proof-surface family represented in the canonical scenario registry.
pub const Surface = enum {
    algebraic,
    effect,
    example,
    source_lowering,
    witness,
};

/// Stable scenario ids for the canonical lowered proof registry.
pub const ScenarioId = enum {
    algebraic_abortive_validation,
    algebraic_artifact_search,
    atm_resume_transform,
    define_abort_basic,
    define_basic,
    define_choice_basic,
    direct_return,
    early_exit,
    exception_basic,
    front_door_workflow,
    generator,
    multi_prompt,
    nested_workflow_publish,
    optional_basic,
    reader_basic,
    resource_basic,
    resume_or_return,
    resume_or_return_resume,
    resume_or_return_return_now,
    source_branch_resume,
    source_defer_resume,
    source_errdefer_error,
    source_helper_call_resume,
    source_local_mutation_resume,
    source_loop_resume,
    source_static_redelim,
    source_typed_error_try,
    state_basic,
    static_redelim,
    writer_basic,
};

/// Prompt identities used by lowered proof scenarios.
pub const PromptId = enum {
    approval,
    audit,
    inner,
    outer,
    primary,
};

/// Pending continuation families represented in lowered proof scenarios.
pub const PendingKind = enum {
    direct_return,
    resume_or_return,
    resume_then_transform,
};

/// Typed values carried through lowered proof scenarios.
pub const Value = union(enum) {
    bool: bool,
    i32: i32,
    none,
    string: []const u8,
};

/// Transcript events projected from lowered proof scenarios.
pub const Event = union(enum) {
    final_i32: i32,
    final_string: []const u8,
    note: []const u8,
};

/// Stable checkpoint tags emitted by lowered proof scenarios.
pub const CheckpointTag = enum {
    atm_body_resumed,
    atm_resume_prepared,
    atm_terminal,
    direct_return_handler,
    direct_return_terminal,
    multi_prompt_outer_resume,
    multi_prompt_terminal,
    nested_workflow_approval,
    nested_workflow_audit_entered,
    nested_workflow_audit_resumed,
    nested_workflow_terminal,
    resume_or_return_resume_choice,
    ror_resume_body,
    ror_resume_terminal,
    ror_return_now_choice,
    ror_return_now_terminal,
    static_redelim_inner_resume,
    static_redelim_outer_resume,
    static_redelim_terminal,
};

/// One pending frame in a lowered proof scenario.
pub const PendingFrame = struct {
    kind: PendingKind,
    prompt: PromptId,
    resume_value: Value = .none,
};

/// One internal-state snapshot expected from the typed proof kernel.
pub const TraceCheckpoint = struct {
    tag: CheckpointTag,
    active_prompt: ?PromptId,
    pending_depth: usize,
    top_pending_kind: ?PendingKind,
    top_pending_prompt: ?PromptId,
    top_resume_value: Value = .none,
    final_result: Value = .none,
};

/// One lowered machine step in the canonical scenario registry.
pub const Step = union(enum) {
    checkpoint: CheckpointTag,
    emit: Event,
    pop_pending,
    push_pending: PendingFrame,
    set_active_prompt: ?PromptId,
    set_final: Value,
};

/// One witness-specific metadata bundle derived from the canonical registry.
pub const WitnessMeta = struct {
    evaluator_case: ?[]const u8,
    forbidden_transcript: ?[]const u8,
    law_anchor: []const u8,
    runtime_case: []const u8,
    title: []const u8,
    witness_id: []const u8,
};

/// One scenario entry in the canonical lowered semantics registry.
pub const Scenario = struct {
    case_id: []const u8,
    expected_transcript: []const u8,
    fixture_name: ?[]const u8 = null,
    scenario_id: ScenarioId,
    surface: Surface,
    steps: []const Step,
    trace_checkpoints: []const TraceCheckpoint = &.{},
    witness: ?WitnessMeta = null,
};

/// Runtime-positive proof cases that are not transcript-driven.
pub const RuntimeSmoke = struct {
    case_id: []const u8,
};

const atm_steps = [_]Step{
    .{ .set_active_prompt = .primary },
    .{ .push_pending = .{ .kind = .resume_then_transform, .prompt = .primary, .resume_value = .{ .i32 = 41 } } },
    .{ .emit = .{ .note = "handler-enter" } },
    .{ .checkpoint = .atm_resume_prepared },
    .{ .emit = .{ .note = "body-after-shift" } },
    .{ .checkpoint = .atm_body_resumed },
    .pop_pending,
    .{ .emit = .{ .note = "handler-after-resume" } },
    .{ .set_final = .{ .string = "answer=42" } },
    .{ .emit = .{ .final_string = "answer=42" } },
    .{ .checkpoint = .atm_terminal },
};

const atm_trace = [_]TraceCheckpoint{
    .{
        .tag = .atm_resume_prepared,
        .active_prompt = .primary,
        .pending_depth = 1,
        .top_pending_kind = .resume_then_transform,
        .top_pending_prompt = .primary,
        .top_resume_value = .{ .i32 = 41 },
        .final_result = .none,
    },
    .{
        .tag = .atm_body_resumed,
        .active_prompt = .primary,
        .pending_depth = 1,
        .top_pending_kind = .resume_then_transform,
        .top_pending_prompt = .primary,
        .top_resume_value = .{ .i32 = 41 },
        .final_result = .none,
    },
    .{
        .tag = .atm_terminal,
        .active_prompt = .primary,
        .pending_depth = 0,
        .top_pending_kind = null,
        .top_pending_prompt = null,
        .top_resume_value = .none,
        .final_result = .{ .string = "answer=42" },
    },
};

const direct_steps = [_]Step{
    .{ .set_active_prompt = .primary },
    .{ .push_pending = .{ .kind = .direct_return, .prompt = .primary } },
    .{ .emit = .{ .note = "handler-direct-return" } },
    .{ .checkpoint = .direct_return_handler },
    .pop_pending,
    .{ .set_final = .{ .string = "result=early" } },
    .{ .emit = .{ .final_string = "result=early" } },
    .{ .checkpoint = .direct_return_terminal },
};

const direct_trace = [_]TraceCheckpoint{
    .{
        .tag = .direct_return_handler,
        .active_prompt = .primary,
        .pending_depth = 1,
        .top_pending_kind = .direct_return,
        .top_pending_prompt = .primary,
        .top_resume_value = .none,
        .final_result = .none,
    },
    .{
        .tag = .direct_return_terminal,
        .active_prompt = .primary,
        .pending_depth = 0,
        .top_pending_kind = null,
        .top_pending_prompt = null,
        .top_resume_value = .none,
        .final_result = .{ .string = "result=early" },
    },
};

const ror_return_now_steps = [_]Step{
    .{ .set_active_prompt = .primary },
    .{ .push_pending = .{ .kind = .resume_or_return, .prompt = .primary } },
    .{ .emit = .{ .note = "handler-return-now" } },
    .{ .checkpoint = .ror_return_now_choice },
    .pop_pending,
    .{ .set_final = .{ .string = "result=early" } },
    .{ .emit = .{ .final_string = "result=early" } },
    .{ .checkpoint = .ror_return_now_terminal },
};

const ror_return_now_trace = [_]TraceCheckpoint{
    .{
        .tag = .ror_return_now_choice,
        .active_prompt = .primary,
        .pending_depth = 1,
        .top_pending_kind = .resume_or_return,
        .top_pending_prompt = .primary,
        .top_resume_value = .none,
        .final_result = .none,
    },
    .{
        .tag = .ror_return_now_terminal,
        .active_prompt = .primary,
        .pending_depth = 0,
        .top_pending_kind = null,
        .top_pending_prompt = null,
        .top_resume_value = .none,
        .final_result = .{ .string = "result=early" },
    },
};

const ror_resume_steps = [_]Step{
    .{ .set_active_prompt = .primary },
    .{ .push_pending = .{ .kind = .resume_or_return, .prompt = .primary, .resume_value = .{ .i32 = 41 } } },
    .{ .emit = .{ .note = "handler-decide-resume" } },
    .{ .checkpoint = .resume_or_return_resume_choice },
    .{ .emit = .{ .note = "body-after-shift" } },
    .{ .checkpoint = .ror_resume_body },
    .pop_pending,
    .{ .emit = .{ .note = "handler-after-resume" } },
    .{ .set_final = .{ .string = "answer=42" } },
    .{ .emit = .{ .final_string = "answer=42" } },
    .{ .checkpoint = .ror_resume_terminal },
};

const ror_resume_trace = [_]TraceCheckpoint{
    .{
        .tag = .resume_or_return_resume_choice,
        .active_prompt = .primary,
        .pending_depth = 1,
        .top_pending_kind = .resume_or_return,
        .top_pending_prompt = .primary,
        .top_resume_value = .{ .i32 = 41 },
        .final_result = .none,
    },
    .{
        .tag = .ror_resume_body,
        .active_prompt = .primary,
        .pending_depth = 1,
        .top_pending_kind = .resume_or_return,
        .top_pending_prompt = .primary,
        .top_resume_value = .{ .i32 = 41 },
        .final_result = .none,
    },
    .{
        .tag = .ror_resume_terminal,
        .active_prompt = .primary,
        .pending_depth = 0,
        .top_pending_kind = null,
        .top_pending_prompt = null,
        .top_resume_value = .none,
        .final_result = .{ .string = "answer=42" },
    },
};

const static_redelim_steps = [_]Step{
    .{ .set_active_prompt = .outer },
    .{ .push_pending = .{ .kind = .resume_then_transform, .prompt = .outer, .resume_value = .{ .i32 = 1 } } },
    .{ .emit = .{ .note = "outer-handler-enter" } },
    .{ .checkpoint = .static_redelim_outer_resume },
    .{ .emit = .{ .note = "after-outer-shift" } },
    .{ .set_active_prompt = .inner },
    .{ .push_pending = .{ .kind = .resume_then_transform, .prompt = .inner, .resume_value = .{ .i32 = 2 } } },
    .{ .emit = .{ .note = "inner-handler-enter" } },
    .{ .checkpoint = .static_redelim_inner_resume },
    .{ .emit = .{ .note = "after-inner-shift" } },
    .{ .emit = .{ .note = "inner-handler-exit" } },
    .pop_pending,
    .{ .set_active_prompt = .outer },
    .{ .emit = .{ .note = "outer-handler-exit" } },
    .pop_pending,
    .{ .set_final = .{ .i32 = 12 } },
    .{ .emit = .{ .final_i32 = 12 } },
    .{ .checkpoint = .static_redelim_terminal },
};

const static_redelim_trace = [_]TraceCheckpoint{
    .{
        .tag = .static_redelim_outer_resume,
        .active_prompt = .outer,
        .pending_depth = 1,
        .top_pending_kind = .resume_then_transform,
        .top_pending_prompt = .outer,
        .top_resume_value = .{ .i32 = 1 },
        .final_result = .none,
    },
    .{
        .tag = .static_redelim_inner_resume,
        .active_prompt = .inner,
        .pending_depth = 2,
        .top_pending_kind = .resume_then_transform,
        .top_pending_prompt = .inner,
        .top_resume_value = .{ .i32 = 2 },
        .final_result = .none,
    },
    .{
        .tag = .static_redelim_terminal,
        .active_prompt = .outer,
        .pending_depth = 0,
        .top_pending_kind = null,
        .top_pending_prompt = null,
        .top_resume_value = .none,
        .final_result = .{ .i32 = 12 },
    },
};

const multi_prompt_steps = [_]Step{
    .{ .set_active_prompt = .outer },
    .{ .emit = .{ .note = "outer-before-inner" } },
    .{ .set_active_prompt = .inner },
    .{ .emit = .{ .note = "inner-before" } },
    .{ .push_pending = .{ .kind = .resume_then_transform, .prompt = .outer, .resume_value = .{ .i32 = 41 } } },
    .{ .set_active_prompt = .outer },
    .{ .emit = .{ .note = "outer-handler" } },
    .{ .checkpoint = .multi_prompt_outer_resume },
    .pop_pending,
    .{ .set_active_prompt = .inner },
    .{ .emit = .{ .note = "inner-after" } },
    .{ .set_active_prompt = .outer },
    .{ .emit = .{ .note = "outer-after-inner" } },
    .{ .set_final = .{ .i32 = 42 } },
    .{ .emit = .{ .final_i32 = 42 } },
    .{ .checkpoint = .multi_prompt_terminal },
};

const multi_prompt_trace = [_]TraceCheckpoint{
    .{
        .tag = .multi_prompt_outer_resume,
        .active_prompt = .outer,
        .pending_depth = 1,
        .top_pending_kind = .resume_then_transform,
        .top_pending_prompt = .outer,
        .top_resume_value = .{ .i32 = 41 },
        .final_result = .none,
    },
    .{
        .tag = .multi_prompt_terminal,
        .active_prompt = .outer,
        .pending_depth = 0,
        .top_pending_kind = null,
        .top_pending_prompt = null,
        .top_resume_value = .none,
        .final_result = .{ .i32 = 42 },
    },
};

const nested_workflow_steps = [_]Step{
    .{ .set_active_prompt = .approval },
    .{ .emit = .{ .note = "workflow=queued" } },
    .{ .set_active_prompt = .audit },
    .{ .push_pending = .{ .kind = .resume_then_transform, .prompt = .audit } },
    .{ .emit = .{ .note = "audit=entered" } },
    .{ .checkpoint = .nested_workflow_audit_entered },
    .pop_pending,
    .{ .emit = .{ .note = "audit=after" } },
    .{ .checkpoint = .nested_workflow_audit_resumed },
    .{ .set_active_prompt = .approval },
    .{ .push_pending = .{ .kind = .resume_then_transform, .prompt = .approval, .resume_value = .{ .bool = true } } },
    .{ .emit = .{ .note = "approval=publish" } },
    .{ .checkpoint = .nested_workflow_approval },
    .pop_pending,
    .{ .emit = .{ .note = "workflow=done" } },
    .{ .set_final = .{ .string = "result=completed" } },
    .{ .emit = .{ .note = "result=completed" } },
    .{ .checkpoint = .nested_workflow_terminal },
};

const nested_workflow_trace = [_]TraceCheckpoint{
    .{
        .tag = .nested_workflow_audit_entered,
        .active_prompt = .audit,
        .pending_depth = 1,
        .top_pending_kind = .resume_then_transform,
        .top_pending_prompt = .audit,
        .top_resume_value = .none,
        .final_result = .none,
    },
    .{
        .tag = .nested_workflow_audit_resumed,
        .active_prompt = .audit,
        .pending_depth = 0,
        .top_pending_kind = null,
        .top_pending_prompt = null,
        .top_resume_value = .none,
        .final_result = .none,
    },
    .{
        .tag = .nested_workflow_approval,
        .active_prompt = .approval,
        .pending_depth = 1,
        .top_pending_kind = .resume_then_transform,
        .top_pending_prompt = .approval,
        .top_resume_value = .{ .bool = true },
        .final_result = .none,
    },
    .{
        .tag = .nested_workflow_terminal,
        .active_prompt = .approval,
        .pending_depth = 0,
        .top_pending_kind = null,
        .top_pending_prompt = null,
        .top_resume_value = .none,
        .final_result = .{ .string = "result=completed" },
    },
};

const generator_steps = [_]Step{
    .{ .emit = .{ .note = "yield=1" } },
    .{ .emit = .{ .note = "yield=2" } },
    .{ .emit = .{ .note = "yield=3" } },
    .{ .set_final = .{ .i32 = 3 } },
    .{ .emit = .{ .note = "done=3" } },
};

const early_exit_steps = [_]Step{
    .{ .emit = .{ .note = "handler-direct-return" } },
    .{ .set_final = .{ .string = "result=early" } },
    .{ .emit = .{ .final_string = "result=early" } },
};

const define_basic_steps = [_]Step{
    .{ .set_final = .{ .i32 = 6 } },
    .{ .emit = .{ .note = "counter=6" } },
};

const define_choice_steps = [_]Step{
    .{ .emit = .{ .note = "branch=return_now" } },
    .{ .emit = .{ .note = "policy-return-now" } },
    .{ .emit = .{ .note = "final=result=early" } },
    .{ .emit = .{ .note = "branch=resume_with" } },
    .{ .emit = .{ .note = "policy-resume" } },
    .{ .emit = .{ .note = "body-after-pick" } },
    .{ .emit = .{ .note = "policy-after-resume" } },
    .{ .set_final = .{ .string = "answer=42" } },
    .{ .emit = .{ .note = "final=answer=42" } },
};

const define_abort_steps = [_]Step{
    .{ .emit = .{ .note = "validate=name" } },
    .{ .emit = .{ .note = "abort=missing-name" } },
    .{ .set_final = .{ .string = "error=missing-name" } },
    .{ .emit = .{ .note = "final=error=missing-name" } },
};

const resume_or_return_steps = [_]Step{
    .{ .emit = .{ .note = "branch=return_now" } },
    .{ .emit = .{ .note = "handler-return-now" } },
    .{ .emit = .{ .final_string = "result=early" } },
    .{ .emit = .{ .note = "branch=resume_with" } },
    .{ .emit = .{ .note = "handler-decide-resume" } },
    .{ .emit = .{ .note = "body-after-shift" } },
    .{ .emit = .{ .note = "handler-after-resume" } },
    .{ .set_final = .{ .string = "answer=42" } },
    .{ .emit = .{ .final_string = "answer=42" } },
};

const front_door_workflow_steps = [_]Step{
    .{ .emit = .{ .note = "search=artifact-search" } },
    .{ .emit = .{ .note = "approval=publish" } },
    .{ .emit = .{ .note = "item=query=artifact-search" } },
    .{ .emit = .{ .note = "item=workflow=queued" } },
    .{ .emit = .{ .note = "final_state=3" } },
    .{ .emit = .{ .note = "total=3" } },
    .{ .set_final = .{ .string = "completed" } },
    .{ .emit = .{ .note = "result=completed" } },
};

const reader_basic_steps = [_]Step{
    .{ .emit = .{ .note = "env=21" } },
    .{ .set_final = .{ .i32 = 42 } },
    .{ .emit = .{ .note = "value=42" } },
};

const exception_basic_steps = [_]Step{
    .{ .emit = .{ .note = "branch=pass" } },
    .{ .emit = .{ .note = "body-pass" } },
    .{ .emit = .{ .note = "final=result=ok" } },
    .{ .emit = .{ .note = "branch=throw" } },
    .{ .emit = .{ .note = "body-before-throw" } },
    .{ .emit = .{ .note = "catch=result=boom" } },
    .{ .set_final = .{ .string = "result=boom" } },
    .{ .emit = .{ .note = "final=result=boom" } },
};

const optional_basic_steps = [_]Step{
    .{ .emit = .{ .note = "branch=return_now" } },
    .{ .emit = .{ .note = "policy-return-now" } },
    .{ .emit = .{ .note = "final=result=early" } },
    .{ .emit = .{ .note = "branch=resume_with" } },
    .{ .emit = .{ .note = "policy-resume" } },
    .{ .emit = .{ .note = "body-after-request" } },
    .{ .emit = .{ .note = "policy-after-resume" } },
    .{ .set_final = .{ .string = "answer=42" } },
    .{ .emit = .{ .note = "final=answer=42" } },
};

const resource_basic_steps = [_]Step{
    .{ .emit = .{ .note = "acquire=a" } },
    .{ .emit = .{ .note = "use=a" } },
    .{ .emit = .{ .note = "acquire=b" } },
    .{ .emit = .{ .note = "use=b" } },
    .{ .emit = .{ .note = "release=b" } },
    .{ .emit = .{ .note = "release=a" } },
    .{ .set_final = .{ .string = "done" } },
    .{ .emit = .{ .note = "final=done" } },
};

const writer_basic_steps = [_]Step{
    .{ .emit = .{ .note = "item=a" } },
    .{ .emit = .{ .note = "item=b" } },
    .{ .set_final = .{ .string = "done" } },
    .{ .emit = .{ .note = "value=done" } },
};

const state_basic_steps = [_]Step{
    .{ .emit = .{ .note = "before=5" } },
    .{ .emit = .{ .note = "after=6" } },
    .{ .emit = .{ .note = "final_state=6" } },
    .{ .set_final = .{ .i32 = 11 } },
    .{ .emit = .{ .note = "value=11" } },
};

const source_local_mutation_steps = [_]Step{
    .{ .emit = .{ .note = "local=1" } },
    .{ .emit = .{ .note = "resume=41" } },
    .{ .emit = .{ .note = "local=42" } },
    .{ .set_final = .{ .i32 = 42 } },
    .{ .emit = .{ .note = "final=42" } },
};

const source_branch_steps = [_]Step{
    .{ .emit = .{ .note = "branch=before" } },
    .{ .emit = .{ .note = "branch=taken" } },
    .{ .emit = .{ .note = "resume=41" } },
    .{ .emit = .{ .note = "branch=after" } },
    .{ .set_final = .{ .i32 = 42 } },
    .{ .emit = .{ .note = "final=42" } },
};

const source_loop_steps = [_]Step{
    .{ .emit = .{ .note = "loop=0" } },
    .{ .emit = .{ .note = "loop=1" } },
    .{ .emit = .{ .note = "resume=41" } },
    .{ .emit = .{ .note = "loop=done" } },
    .{ .set_final = .{ .i32 = 42 } },
    .{ .emit = .{ .note = "final=42" } },
};

const source_helper_steps = [_]Step{
    .{ .emit = .{ .note = "helper=enter" } },
    .{ .emit = .{ .note = "resume=41" } },
    .{ .emit = .{ .note = "helper=exit" } },
    .{ .set_final = .{ .i32 = 42 } },
    .{ .emit = .{ .note = "final=42" } },
};

const source_nested_steps = [_]Step{
    .{ .emit = .{ .note = "outer=enter" } },
    .{ .emit = .{ .note = "inner=enter" } },
    .{ .emit = .{ .note = "inner=exit" } },
    .{ .emit = .{ .note = "outer=exit" } },
    .{ .set_final = .{ .i32 = 12 } },
    .{ .emit = .{ .note = "final=12" } },
};

const source_typed_error_steps = [_]Step{
    .{ .emit = .{ .note = "branch=ok" } },
    .{ .emit = .{ .note = "value=42" } },
    .{ .emit = .{ .note = "branch=err" } },
    .{ .emit = .{ .note = "error=boom" } },
    .{ .set_final = .{ .string = "error=boom" } },
    .{ .emit = .{ .note = "final=error=boom" } },
};

const source_defer_steps = [_]Step{
    .{ .emit = .{ .note = "body=enter" } },
    .{ .emit = .{ .note = "resume=41" } },
    .{ .emit = .{ .note = "defer=cleanup" } },
    .{ .set_final = .{ .i32 = 42 } },
    .{ .emit = .{ .note = "final=42" } },
};

const source_errdefer_steps = [_]Step{
    .{ .emit = .{ .note = "body=enter" } },
    .{ .emit = .{ .note = "errdefer=cleanup" } },
    .{ .emit = .{ .note = "error=boom" } },
    .{ .set_final = .{ .string = "error=boom" } },
    .{ .emit = .{ .note = "final=error=boom" } },
};

const alg_abort_steps = [_]Step{
    .{ .emit = .{ .note = "validate=name" } },
    .{ .emit = .{ .note = "abort=missing-name" } },
    .{ .set_final = .{ .string = "error=missing-name" } },
    .{ .emit = .{ .note = "final=error=missing-name" } },
};

const alg_artifact_steps = [_]Step{
    .{ .emit = .{ .note = "query=artifact-search" } },
    .{ .emit = .{ .note = "messages=1" } },
    .{ .emit = .{ .note = "tool_calls=0" } },
    .{ .emit = .{ .note = "memory_blocks=1" } },
    .{ .emit = .{ .note = "opencode_source=jsonl" } },
    .{ .set_final = .{ .i32 = 3 } },
    .{ .emit = .{ .note = "total=3" } },
};

/// Canonical lowered scenarios for the full current parity corpus.
pub const scenarios = [_]Scenario{
    .{
        .case_id = "atm_resume_transform",
        .expected_transcript = "handler-enter\nbody-after-shift\nhandler-after-resume\nfinal=answer=42\n",
        .surface = .witness,
        .scenario_id = .atm_resume_transform,
        .steps = &atm_steps,
        .trace_checkpoints = &atm_trace,
        .witness = .{
            .evaluator_case = "reference_eval.atm_resume_transform",
            .forbidden_transcript = "handler-enter\nhandler-after-resume\nfinal=answer=42\n",
            .law_anchor = formal_core.anchorPath(.atm_resume_transform),
            .runtime_case = "witnesses.atm_resume_transform",
            .title = "ATM resume-then-transform",
            .witness_id = "atm_resume_transform",
        },
    },
    .{
        .case_id = "direct_return",
        .expected_transcript = "handler-direct-return\nfinal=result=early\n",
        .surface = .witness,
        .scenario_id = .direct_return,
        .steps = &direct_steps,
        .trace_checkpoints = &direct_trace,
        .witness = .{
            .evaluator_case = "reference_eval.direct_return",
            .forbidden_transcript = "final=result=early\n",
            .law_anchor = formal_core.anchorPath(.direct_return),
            .runtime_case = "witnesses.direct_return",
            .title = "Direct return without continuation exposure",
            .witness_id = "direct_return",
        },
    },
    .{
        .case_id = "resume_or_return_return_now",
        .expected_transcript = "handler-return-now\nfinal=result=early\n",
        .surface = .witness,
        .scenario_id = .resume_or_return_return_now,
        .steps = &ror_return_now_steps,
        .trace_checkpoints = &ror_return_now_trace,
        .witness = .{
            .evaluator_case = "reference_eval.resume_or_return_return_now",
            .forbidden_transcript = "final=result=early\n",
            .law_anchor = formal_core.anchorPath(.optional_resumption),
            .runtime_case = "witnesses.resume_or_return_return_now",
            .title = "Optional resumption chooses direct return",
            .witness_id = "resume_or_return_return_now",
        },
    },
    .{
        .case_id = "resume_or_return_resume",
        .expected_transcript = "handler-decide-resume\nbody-after-shift\nhandler-after-resume\nfinal=answer=42\n",
        .surface = .witness,
        .scenario_id = .resume_or_return_resume,
        .steps = &ror_resume_steps,
        .trace_checkpoints = &ror_resume_trace,
        .witness = .{
            .evaluator_case = "reference_eval.resume_or_return_resume",
            .forbidden_transcript = "handler-decide-resume\nhandler-after-resume\nfinal=answer=42\n",
            .law_anchor = formal_core.anchorPath(.optional_resumption),
            .runtime_case = "witnesses.resume_or_return_resume",
            .title = "Optional resumption chooses single resume",
            .witness_id = "resume_or_return_resume",
        },
    },
    .{
        .case_id = "static_redelim",
        .expected_transcript = "outer-handler-enter\nafter-outer-shift\ninner-handler-enter\nafter-inner-shift\ninner-handler-exit\nouter-handler-exit\nfinal=12\n",
        .surface = .witness,
        .scenario_id = .static_redelim,
        .steps = &static_redelim_steps,
        .trace_checkpoints = &static_redelim_trace,
        .witness = .{
            .evaluator_case = "reference_eval.static_redelim",
            .forbidden_transcript = "outer-handler-enter\nafter-outer-shift\nouter-handler-exit\nfinal=12\n",
            .law_anchor = formal_core.anchorPath(.static_redelim),
            .runtime_case = "witnesses.static_redelim",
            .title = "Static re-delimitation against control/prompt",
            .witness_id = "static_redelim",
        },
    },
    .{
        .case_id = "multi_prompt",
        .expected_transcript = "outer-before-inner\ninner-before\nouter-handler\ninner-after\nouter-after-inner\nfinal=42\n",
        .surface = .witness,
        .scenario_id = .multi_prompt,
        .steps = &multi_prompt_steps,
        .trace_checkpoints = &multi_prompt_trace,
        .witness = .{
            .evaluator_case = "reference_eval.multi_prompt",
            .forbidden_transcript = "outer-before-inner\ninner-before\ninner-after\nouter-after-inner\nfinal=42\n",
            .law_anchor = formal_core.anchorPath(.multi_prompt_separation),
            .runtime_case = "witnesses.multi_prompt",
            .title = "Prompt-value separation",
            .witness_id = "multi_prompt",
        },
    },
    .{
        .case_id = "open_row_generator",
        .expected_transcript = "yield=1\nyield=2\nyield=3\ndone=3\n",
        .fixture_name = "open_row_generator.txt",
        .scenario_id = .generator,
        .surface = .example,
        .steps = &generator_steps,
        .witness = .{
            .evaluator_case = null,
            .forbidden_transcript = null,
            .law_anchor = formal_core.anchorPath(.practical_witnesses),
            .runtime_case = "witnesses.generator",
            .title = "Generator",
            .witness_id = "generator",
        },
    },
    .{
        .case_id = "open_row_transform_basic",
        .expected_transcript = "counter=6\n",
        .fixture_name = "open_row_transform_basic.txt",
        .scenario_id = .define_basic,
        .surface = .example,
        .steps = &define_basic_steps,
    },
    .{
        .case_id = "open_row_choice_basic",
        .expected_transcript = "branch=return_now\npolicy-return-now\nfinal=result=early\nbranch=resume_with\npolicy-resume\nbody-after-pick\npolicy-after-resume\nfinal=answer=42\n",
        .fixture_name = "open_row_choice_basic.txt",
        .scenario_id = .define_choice_basic,
        .surface = .example,
        .steps = &define_choice_steps,
    },
    .{
        .case_id = "open_row_abort_basic",
        .expected_transcript = "validate=name\nabort=missing-name\nfinal=error=missing-name\n",
        .fixture_name = "open_row_abort_basic.txt",
        .scenario_id = .define_abort_basic,
        .surface = .example,
        .steps = &define_abort_steps,
    },
    .{
        .case_id = "early_exit",
        .expected_transcript = "handler-direct-return\nfinal=result=early\n",
        .fixture_name = "early_exit.txt",
        .scenario_id = .early_exit,
        .surface = .example,
        .steps = &early_exit_steps,
    },
    .{
        .case_id = "resume_or_return",
        .expected_transcript = "branch=return_now\nhandler-return-now\nfinal=result=early\nbranch=resume_with\nhandler-decide-resume\nbody-after-shift\nhandler-after-resume\nfinal=answer=42\n",
        .fixture_name = "resume_or_return.txt",
        .scenario_id = .resume_or_return,
        .surface = .example,
        .steps = &resume_or_return_steps,
    },
    .{
        .case_id = "open_row_workflow",
        .expected_transcript = "search=artifact-search\napproval=publish\nitem=query=artifact-search\nitem=workflow=queued\nfinal_state=3\ntotal=3\nresult=completed\n",
        .fixture_name = "open_row_workflow.txt",
        .scenario_id = .front_door_workflow,
        .surface = .example,
        .steps = &front_door_workflow_steps,
    },
    .{
        .case_id = "nested_workflow",
        .expected_transcript = "workflow=queued\naudit=entered\naudit=after\napproval=publish\nworkflow=done\nresult=completed\n",
        .fixture_name = "nested_workflow.txt",
        .scenario_id = .nested_workflow_publish,
        .surface = .example,
        .steps = &nested_workflow_steps,
        .trace_checkpoints = &nested_workflow_trace,
    },
    .{
        .case_id = "reader_basic",
        .expected_transcript = "env=21\nvalue=42\n",
        .fixture_name = "reader_basic.txt",
        .scenario_id = .reader_basic,
        .surface = .effect,
        .steps = &reader_basic_steps,
    },
    .{
        .case_id = "exception_basic",
        .expected_transcript = "branch=pass\nbody-pass\nfinal=result=ok\nbranch=throw\nbody-before-throw\ncatch=result=boom\nfinal=result=boom\n",
        .fixture_name = "exception_basic.txt",
        .scenario_id = .exception_basic,
        .surface = .effect,
        .steps = &exception_basic_steps,
    },
    .{
        .case_id = "optional_basic",
        .expected_transcript = "branch=return_now\npolicy-return-now\nfinal=result=early\nbranch=resume_with\npolicy-resume\nbody-after-request\npolicy-after-resume\nfinal=answer=42\n",
        .fixture_name = "optional_basic.txt",
        .scenario_id = .optional_basic,
        .surface = .effect,
        .steps = &optional_basic_steps,
    },
    .{
        .case_id = "resource_basic",
        .expected_transcript = "acquire=a\nuse=a\nacquire=b\nuse=b\nrelease=b\nrelease=a\nfinal=done\n",
        .fixture_name = "resource_basic.txt",
        .scenario_id = .resource_basic,
        .surface = .effect,
        .steps = &resource_basic_steps,
    },
    .{
        .case_id = "writer_basic",
        .expected_transcript = "item=a\nitem=b\nvalue=done\n",
        .fixture_name = "writer_basic.txt",
        .scenario_id = .writer_basic,
        .surface = .effect,
        .steps = &writer_basic_steps,
    },
    .{
        .case_id = "state_basic",
        .expected_transcript = "before=5\nafter=6\nfinal_state=6\nvalue=11\n",
        .fixture_name = "state_basic.txt",
        .scenario_id = .state_basic,
        .surface = .effect,
        .steps = &state_basic_steps,
    },
    .{
        .case_id = "source.local_mutation_resume",
        .expected_transcript = "local=1\nresume=41\nlocal=42\nfinal=42\n",
        .scenario_id = .source_local_mutation_resume,
        .surface = .source_lowering,
        .steps = &source_local_mutation_steps,
    },
    .{
        .case_id = "source.branch_resume",
        .expected_transcript = "branch=before\nbranch=taken\nresume=41\nbranch=after\nfinal=42\n",
        .scenario_id = .source_branch_resume,
        .surface = .source_lowering,
        .steps = &source_branch_steps,
    },
    .{
        .case_id = "source.loop_resume",
        .expected_transcript = "loop=0\nloop=1\nresume=41\nloop=done\nfinal=42\n",
        .scenario_id = .source_loop_resume,
        .surface = .source_lowering,
        .steps = &source_loop_steps,
    },
    .{
        .case_id = "source.helper_call_resume",
        .expected_transcript = "helper=enter\nresume=41\nhelper=exit\nfinal=42\n",
        .scenario_id = .source_helper_call_resume,
        .surface = .source_lowering,
        .steps = &source_helper_steps,
    },
    .{
        .case_id = "source.nested_prompt_static_redelim",
        .expected_transcript = "outer=enter\ninner=enter\ninner=exit\nouter=exit\nfinal=12\n",
        .scenario_id = .source_static_redelim,
        .surface = .source_lowering,
        .steps = &source_nested_steps,
    },
    .{
        .case_id = "source.typed_error_try",
        .expected_transcript = "branch=ok\nvalue=42\nbranch=err\nerror=boom\nfinal=error=boom\n",
        .scenario_id = .source_typed_error_try,
        .surface = .source_lowering,
        .steps = &source_typed_error_steps,
    },
    .{
        .case_id = "source.defer_resume",
        .expected_transcript = "body=enter\nresume=41\ndefer=cleanup\nfinal=42\n",
        .scenario_id = .source_defer_resume,
        .surface = .source_lowering,
        .steps = &source_defer_steps,
    },
    .{
        .case_id = "source.errdefer_error",
        .expected_transcript = "body=enter\nerrdefer=cleanup\nerror=boom\nfinal=error=boom\n",
        .scenario_id = .source_errdefer_error,
        .surface = .source_lowering,
        .steps = &source_errdefer_steps,
    },
    .{
        .case_id = "open_row_abortive_validation",
        .expected_transcript = "validate=name\nabort=missing-name\nfinal=error=missing-name\n",
        .fixture_name = "open_row_abortive_validation.txt",
        .scenario_id = .algebraic_abortive_validation,
        .surface = .algebraic,
        .steps = &alg_abort_steps,
    },
    .{
        .case_id = "open_row_artifact_search",
        .expected_transcript = "query=artifact-search\nmessages=1\ntool_calls=0\nmemory_blocks=1\nopencode_source=jsonl\ntotal=3\n",
        .fixture_name = "open_row_artifact_search.txt",
        .scenario_id = .algebraic_artifact_search,
        .surface = .algebraic,
        .steps = &alg_artifact_steps,
    },
};

/// Runtime-positive proof cases that are not transcript-driven.
pub const runtime_smokes = [_]RuntimeSmoke{
    .{ .case_id = "protocol_resume_transform_runtime" },
};

/// Find one canonical scenario by stable case id.
pub fn find(case_id: []const u8) ?*const Scenario {
    for (&scenarios) |*scenario| {
        if (std.mem.eql(u8, scenario.case_id, case_id)) return scenario;
    }
    return null;
}

/// Find one witness scenario by stable witness id.
pub fn findWitness(witness_id: []const u8) ?*const Scenario {
    for (&scenarios) |*scenario| {
        if (scenario.witness) |witness| {
            if (std.mem.eql(u8, witness.witness_id, witness_id)) return scenario;
        }
    }
    return null;
}

/// Find one canonical scenario by stable scenario id.
pub fn byId(id: ScenarioId) *const Scenario {
    for (&scenarios) |*scenario| {
        if (scenario.scenario_id == id) return scenario;
    }
    unreachable;
}
