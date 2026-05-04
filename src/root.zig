const shared = @import("ability_shared");

/// Public effect namespace.
pub const effect = shared.effect;
/// Public ProgramPlan builder namespace.
pub const ir = shared.ir;
/// Canonical runtime handle for local program execution.
pub const Runtime = shared.Runtime;
/// Declare one reusable explicit effect program.
pub const program = shared.program;

test {
    _ = Runtime;
    _ = program;
    _ = effect;
    _ = ir;
}
