const std = @import("std");

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
    cross_thread,
    frontend_suspend,
    missing_prompt,
    non_diagonal_complete,
    program_contract_violation,
    runtime_busy,
    runtime_destroyed,
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
        .missing_prompt => "MissingPrompt",
        .cross_thread => "CrossThread",
        .runtime_busy => "RuntimeBusy",
        .runtime_destroyed => "RuntimeDestroyed",
        .non_diagonal_complete => "NonDiagonalComplete",
        .frontend_suspend => "FrontendSuspend",
        .program_contract_violation => "ProgramContractViolation",
    };
}

/// Return the public setup error names.
pub fn setupErrorNames(has_oom: bool) []const []const u8 {
    return if (has_oom) &.{"OutOfMemory"} else &no_error_names;
}
