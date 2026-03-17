const lowered_machine = @import("lowered_machine");

/// Internal explicit runtime handle for repo-owned proof/runtime callers.
pub const Runtime = lowered_machine.Runtime;
/// Internal explicit runtime error surface for repo-owned proof/runtime callers.
pub const Error = lowered_machine.Error;

/// Internal explicit runtime error union for a user-provided error set.
pub fn ControlError(comptime ErrorSet: type) type {
    return lowered_machine.ControlError(ErrorSet);
}

/// Internal reset-time error union for a user-provided error set.
pub fn ResetError(comptime ErrorSet: type) type {
    return lowered_machine.ResetError(ErrorSet);
}

test {
    _ = Runtime;
    _ = Error;
    _ = ControlError;
    _ = ResetError;
}
