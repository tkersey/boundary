const shared = @import("shift_shared");

/// Public lexical effect namespace.
pub const effect = shared.effect;
/// Canonical runtime handle for lexical execution.
pub const Runtime = shared.Runtime;
/// Public runtime misuse and semantic-contract errors surfaced by `shift`.
pub const RuntimeError = shared.RuntimeError;
/// Build the public lexical metadata type.
pub const With = shared.With;
/// Run the public lexical handler entrypoint.
pub const with = shared.with;

test {
    _ = With;
    _ = Runtime;
    _ = RuntimeError;
    _ = effect;
    _ = with;
}
