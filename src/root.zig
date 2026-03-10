const raw = @import("raw.zig");

/// Public workflow driver helpers layered on top of the token API.
pub const driver = @import("driver.zig");
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

/// Result of driving a delimiter until completion, tokenization, or cancellation.
pub fn Outcome(comptime Spec: type) type {
    return raw.Outcome(Spec);
}

/// Linear one-shot token that owns the suspended computation.
pub fn Token(comptime Spec: type) type {
    return raw.Token(Spec);
}

/// Run `body` under the nearest dynamic delimiter identified by `Tag`.
pub fn reset(
    comptime Spec: type,
    runtime: *Runtime,
    body: *const fn () ResetError(Spec.ErrorSet)!Spec.Answer,
) ResetError(Spec.ErrorSet)!Outcome(Spec) {
    return raw.reset(Spec, runtime, body);
}

/// Suspend with `request` up to the nearest active `reset(Tag, ...)`.
pub fn shift(
    comptime Spec: type,
    request: Spec.Request,
) ControlError(Spec.ErrorSet)!Spec.Resume {
    return raw.shift(Spec, request);
}

test {
    _ = driver;
    _ = Runtime;
    _ = NoShiftGuard;
}
