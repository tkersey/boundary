const raw = @import("raw.zig");

/// Runtime owner for fiber-backed one-shot `shift/reset`.
pub const Runtime = raw.Runtime;
/// Guard that forbids suspension in unsafe regions.
pub const NoShiftGuard = raw.NoShiftGuard;
/// Public runtime errors surfaced by `shift`.
pub const Error = raw.Error;
/// Internal runtime/setup failures that can appear before user code runs.
pub const SetupError = raw.SetupError;

/// Runtime error union for a user-provided error set.
pub fn ControlError(comptime ErrorSet: type) type {
    return raw.ControlError(ErrorSet);
}

/// Reset-time error union for a user-provided error set.
pub fn ResetError(comptime ErrorSet: type) type {
    return raw.ResetError(ErrorSet);
}

/// Run `body` under the nearest dynamic delimiter identified by `Tag`.
pub fn reset(
    comptime Tag: type,
    comptime Answer: type,
    comptime ErrorSet: type,
    runtime: *Runtime,
    body: *const fn () ResetError(ErrorSet)!Answer,
) ResetError(ErrorSet)!Answer {
    return raw.reset(Tag, Answer, ErrorSet, runtime, body);
}

/// Capture the computation up to the nearest active `reset(Tag, ...)`.
pub fn shift(
    comptime Resume: type,
    comptime Tag: type,
    comptime Answer: type,
    comptime ErrorSet: type,
    handler: *const fn (*raw.Continuation(Resume, Tag, Answer, ErrorSet)) ResetError(ErrorSet)!Answer,
) ControlError(ErrorSet)!Resume {
    return raw.shift(Resume, Tag, Answer, ErrorSet, handler);
}

/// One-shot continuation handle for `shift`.
pub fn Continuation(comptime Resume: type, comptime Tag: type, comptime Answer: type, comptime ErrorSet: type) type {
    return raw.Continuation(Resume, Tag, Answer, ErrorSet);
}

test {
    _ = Runtime;
    _ = NoShiftGuard;
}
