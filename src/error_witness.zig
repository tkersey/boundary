// zlinter-disable field_naming - runtime error tags intentionally mirror Zig error names for stable diagnostics.
// zlinter-disable require_doc_comment - lower-case aliases are machine-readable mirrors of the public error tags.
/// Public witness surface enum.
pub const Surface = enum {
    algebraic,
    generated_family,
    lexical,
    ordinary,
};

/// Public witness support-status enum.
pub const SupportStatus = enum {
    supported,
    unsupported,
};

/// Public runtime error tag enum.
pub const RuntimeErrorTag = enum {
    CrossThread,
    ExecutionBudgetExceeded,
    FrontendSuspend,
    MissingPrompt,
    NonDiagonalComplete,
    ProgramContractViolation,
    RuntimeBusy,
    RuntimeDestroyed,

    pub const cross_thread = RuntimeErrorTag.CrossThread;
    pub const execution_budget_exceeded = RuntimeErrorTag.ExecutionBudgetExceeded;
    pub const frontend_suspend = RuntimeErrorTag.FrontendSuspend;
    pub const missing_prompt = RuntimeErrorTag.MissingPrompt;
    pub const non_diagonal_complete = RuntimeErrorTag.NonDiagonalComplete;
    pub const program_contract_violation = RuntimeErrorTag.ProgramContractViolation;
    pub const runtime_busy = RuntimeErrorTag.RuntimeBusy;
    pub const runtime_destroyed = RuntimeErrorTag.RuntimeDestroyed;
};

/// Public contributor-kind enum.
pub const ContributorKind = enum {
    body,
    cleanup,
    continuation,
    descriptor,
    handler,
    manager,
    policy,
};

/// Public contributor record.
pub const Contributor = struct {
    kind: ContributorKind,
    surface: Surface,
    symbol: []const u8,
    error_names: []const []const u8,
};

/// Public witness diagnostic record.
pub const WitnessDiagnostic = struct {
    code: []const u8,
    message: []const u8,
    path: []const u8,
    line: usize,
    column: usize,
};

/// Stable v1 error-witness schema used by public types and generated artifacts.
pub const ErrorWitnessV1 = struct {
    schema_version: u8 = 1,
    surface: Surface,
    support_status: SupportStatus,
    public_runtime_errors: []const RuntimeErrorTag,
    setup_error_names: []const []const u8,
    semantic_error_names: []const []const u8,
    contributors: []const Contributor,
    diagnostics: []const WitnessDiagnostic,

    /// Return the empty public value.
    pub fn empty(comptime surface: Surface) ErrorWitnessV1 {
        return .{
            .surface = surface,
            .support_status = .supported,
            .public_runtime_errors = &.{},
            .setup_error_names = &.{},
            .semantic_error_names = &.{},
            .contributors = &.{},
            .diagnostics = &.{},
        };
    }
};

/// Public empty error-name slice.
pub const no_error_names = [_][]const u8{};
/// Public empty runtime-error-tag slice.
pub const no_runtime_error_tags = [_]RuntimeErrorTag{};
/// Public empty contributor slice.
pub const no_contributors = [_]Contributor{};
/// Public empty diagnostic slice.
pub const no_diagnostics = [_]WitnessDiagnostic{};

/// Return the public runtime error tags.
pub fn runtimeErrorTags() []const RuntimeErrorTag {
    return &.{
        .missing_prompt,
        .cross_thread,
        .execution_budget_exceeded,
        .runtime_busy,
        .runtime_destroyed,
        .non_diagonal_complete,
        .frontend_suspend,
        .program_contract_violation,
    };
}

/// Return the public runtime error tag name.
pub fn runtimeErrorTagName(tag: RuntimeErrorTag) []const u8 {
    return switch (tag) {
        .MissingPrompt => "MissingPrompt",
        .CrossThread => "CrossThread",
        .ExecutionBudgetExceeded => "ExecutionBudgetExceeded",
        .RuntimeBusy => "RuntimeBusy",
        .RuntimeDestroyed => "RuntimeDestroyed",
        .NonDiagonalComplete => "NonDiagonalComplete",
        .FrontendSuspend => "FrontendSuspend",
        .ProgramContractViolation => "ProgramContractViolation",
    };
}

/// Return the public setup error names.
pub fn setupErrorNames(has_oom: bool) []const []const u8 {
    return if (has_oom) &.{"OutOfMemory"} else &no_error_names;
}

test "runtime error tag aliases stay source-compatible" {
    try @import("std").testing.expectEqual(RuntimeErrorTag.MissingPrompt, RuntimeErrorTag.missing_prompt);
    try @import("std").testing.expectEqual(RuntimeErrorTag.CrossThread, RuntimeErrorTag.cross_thread);
    try @import("std").testing.expectEqual(RuntimeErrorTag.ExecutionBudgetExceeded, RuntimeErrorTag.execution_budget_exceeded);
    try @import("std").testing.expectEqual(RuntimeErrorTag.RuntimeBusy, RuntimeErrorTag.runtime_busy);
    try @import("std").testing.expectEqual(RuntimeErrorTag.RuntimeDestroyed, RuntimeErrorTag.runtime_destroyed);
    try @import("std").testing.expectEqual(RuntimeErrorTag.NonDiagonalComplete, RuntimeErrorTag.non_diagonal_complete);
    try @import("std").testing.expectEqual(RuntimeErrorTag.FrontendSuspend, RuntimeErrorTag.frontend_suspend);
    try @import("std").testing.expectEqual(RuntimeErrorTag.ProgramContractViolation, RuntimeErrorTag.program_contract_violation);
    try @import("std").testing.expectEqualStrings("MissingPrompt", @tagName(RuntimeErrorTag.MissingPrompt));
}
