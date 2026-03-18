const std = @import("std");

pub const Surface = enum {
    source_lowering,
    lexical,
    algebraic,
    generated_family,
};

pub const SupportStatus = enum {
    supported,
    unsupported,
};

pub const RuntimeErrorTag = enum {
    MissingPrompt,
    CrossThread,
    RuntimeBusy,
    RuntimeDestroyed,
    NonDiagonalComplete,
    FrontendSuspend,
    ProgramContractViolation,
};

pub const ContributorKind = enum {
    body,
    continuation,
    descriptor,
    handler,
    policy,
    manager,
    cleanup,
};

pub const Contributor = struct {
    kind: ContributorKind,
    surface: Surface,
    symbol: []const u8,
    error_names: []const []const u8,
};

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

pub const no_error_names = [_][]const u8{};
pub const no_runtime_error_tags = [_]RuntimeErrorTag{};
pub const no_contributors = [_]Contributor{};
pub const no_diagnostics = [_]WitnessDiagnostic{};

pub fn runtimeErrorTags() []const RuntimeErrorTag {
    return &.{
        .MissingPrompt,
        .CrossThread,
        .RuntimeBusy,
        .RuntimeDestroyed,
        .NonDiagonalComplete,
        .FrontendSuspend,
        .ProgramContractViolation,
    };
}

pub fn setupErrorNames(has_oom: bool) []const []const u8 {
    return if (has_oom) &.{"OutOfMemory"} else &no_error_names;
}
