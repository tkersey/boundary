// zlinter-disable declaration_naming
const effect_root = @import("effect/root.zig");
const ir_api = @import("ir_api.zig");
const lowered_machine = @import("lowered_machine");
const program_api = @import("program_api.zig");

/// Public effect family and handler constructors.
pub const effect = effect_root;
/// Public ProgramPlan builder namespace.
pub const ir = ir_api;
/// Canonical lowered runtime retained at the root surface for repeated local execution.
pub const Runtime = lowered_machine.Runtime;
/// Declare one reusable explicit effect program.
pub const program = program_api.program;

test "shared public surface exposes only the local execution front door" {
    const std = @import("std");

    try std.testing.expect(@hasDecl(@This(), "effect"));
    try std.testing.expect(@hasDecl(@This(), "ir"));
    try std.testing.expect(@hasDecl(@This(), "Runtime"));
    try std.testing.expect(@hasDecl(@This(), "program"));
}
