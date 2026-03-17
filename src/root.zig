const lowered_machine = @import("lowered_machine");
const with_api = @import("with_api.zig");

/// Canonical lowered-first runtime handle.
pub const Runtime = lowered_machine.Runtime;
/// Public runtime errors surfaced by `shift`.
pub const Error = lowered_machine.Error;
/// Generalized algebraic-effect builders over the core shift/reset runtime.
pub const algebraic = @import("algebraic.zig");
/// Additive algebraic-effect families built on top of the core shift/reset runtime.
pub const effect = @import("effect/root.zig");
/// Canonical source-backed lowering surface for the repo-owned ordinary corpus.
pub const ordinary = @import("ordinary/root.zig");

/// Runtime error union for a user-provided error set.
pub fn ControlError(comptime ErrorSet: type) type {
    return lowered_machine.ControlError(ErrorSet);
}

/// Reset-time error union for a user-provided error set.
pub fn ResetError(comptime ErrorSet: type) type {
    return lowered_machine.ResetError(ErrorSet);
}

/// Canonical lexical result type returned from `shift.with(...)`.
pub fn WithResult(comptime HandlersType: type, comptime Answer: type) type {
    return with_api.WithResult(HandlersType, Answer);
}

/// Run one ordinary Zig body against a lexical effect-handle bundle.
pub fn with(
    runtime: *Runtime,
    handlers: anytype,
    comptime Body: type,
) with_api.WithFnReturnType(@TypeOf(handlers), Body) {
    return with_api.with(runtime, handlers, Body);
}

test {
    _ = Runtime;
    _ = WithResult;
    _ = effect;
    _ = algebraic;
    _ = ordinary;
    _ = with;
}
