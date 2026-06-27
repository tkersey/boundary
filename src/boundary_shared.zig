// zlinter-disable declaration_naming
const effect_root = @import("effect/root.zig");
const ir_api = @import("ir_api.zig");
const lowered_machine = @import("lowered_machine");
const program_api = @import("program_api.zig");
const protocol = @import("protocol.zig");

/// Public effect family and handler constructors.
pub const effect = effect_root;
/// Public ProgramPlan builder namespace.
pub const ir = ir_api;
/// Canonical lowered runtime retained at the root surface for repeated local execution.
pub const Runtime = lowered_machine.Runtime;
/// Declare one reusable explicit effect program.
pub const program = program_api.program;
/// Canonical v0 protocol manifest namespace.
pub const Protocol = protocol.Protocol;
/// Boundary protocol manifest binary format version.
pub const boundary_protocol_manifest_format_version = protocol.boundary_protocol_manifest_format_version;
/// Boundary protocol manifest fingerprint version.
pub const boundary_protocol_manifest_fingerprint_version = protocol.boundary_protocol_manifest_fingerprint_version;

test "shared public surface exposes only the local execution front door" {
    const std = @import("std");

    try std.testing.expect(@hasDecl(@This(), "effect"));
    try std.testing.expect(@hasDecl(@This(), "ir"));
    try std.testing.expect(@hasDecl(@This(), "Runtime"));
    try std.testing.expect(@hasDecl(@This(), "program"));
    try std.testing.expect(@hasDecl(@This(), "Protocol"));
}
