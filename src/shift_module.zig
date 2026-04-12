const root = @import("root.zig");

/// Public lexical effect namespace.
pub const effect = root.effect;
/// Canonical runtime handle.
pub const Runtime = root.Runtime;
/// Public runtime error surface.
pub const RuntimeError = root.RuntimeError;
/// Canonical lexical execution entrypoint.
pub const with = root.with;

test {
    _ = Runtime;
    _ = RuntimeError;
    _ = effect;
    _ = with;
    _ = root;
}
