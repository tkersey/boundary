const root = @import("root.zig");
const with_api = @import("with_api.zig");

/// Generalized algebraic-effect builders over the canonical shift root.
pub const algebraic = root.algebraic;
/// Additive algebraic-effect families over the canonical shift root.
pub const effect = root.effect;
/// Reset-time error union for a user-provided error set.
pub const ResetError = root.ResetError;
/// Canonical lexical result type returned from `shift.with(...)`.
pub const WithResult = root.WithResult;
/// Canonical lexical execution entrypoint with internal runtime management.
pub fn with(
    handlers: anytype,
    comptime Body: type,
) with_api.WithFnReturnType(@TypeOf(handlers), Body) {
    return with_api.withManaged(handlers, Body);
}

test {
    _ = root;
}
