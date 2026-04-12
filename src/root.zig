const shared = @import("shift_shared");

/// Public lexical effect namespace.
pub const effect = shared.effect;
/// Canonical runtime handle for lexical execution.
pub const Runtime = shared.Runtime;
/// Public runtime misuse and semantic-contract errors surfaced by `shift`.
pub const RuntimeError = shared.RuntimeError;
/// Run the public lexical handler entrypoint.
pub const with = shared.with;

test {
    _ = Runtime;
    _ = RuntimeError;
    _ = effect;
    _ = with;
}
