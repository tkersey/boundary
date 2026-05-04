const shared = @import("ability_shared");

/// Public effect namespace.
pub const effect = shared.effect;
/// Canonical runtime handle for local program execution.
pub const Runtime = shared.Runtime;
/// Declare one reusable explicit effect program.
pub const program = shared.program;

test {
    _ = Runtime;
    _ = program;
    _ = effect;
}
