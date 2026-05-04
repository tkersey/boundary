const shared = @import("ability_shared");
// zlinter-disable require_doc_comment - synthetic ability root is an internal generated-packet shim.

/// Synthetic lexical-effect root used only by generated anonymous-body lowering packets.
pub const effect = shared.effect;
/// Synthetic runtime alias used by generated anonymous-body lowering packets.
pub const Runtime = shared.Runtime;
/// Synthetic explicit-program constructor used by generated anonymous-body lowering packets.
pub const program = shared.program;

test "synthetic root mirrors retained explicit public surface" {
    const std = @import("std");

    try std.testing.expect(@hasDecl(@This(), "effect"));
    try std.testing.expect(@hasDecl(@This(), "Runtime"));
    try std.testing.expect(@hasDecl(@This(), "program"));
    try std.testing.expect(!@hasDecl(@This(), "with"));
    try std.testing.expect(!@hasDecl(@This(), "RuntimeError"));
}
