const effect_ir = @import("effect_ir");
const program_frontend = @import("program_frontend");
const std = @import("std");

test "program frontend stays explicit and does not pretend to lower raw bodies" {
    try std.testing.expect(@hasDecl(program_frontend, "Program"));
    try std.testing.expect(@hasDecl(program_frontend, "lower"));
    try std.testing.expect(!@hasDecl(program_frontend, "fromBody"));
    try std.testing.expect(!@hasDecl(program_frontend, "fromClosure"));
    try std.testing.expect(!@hasDecl(program_frontend, "lowerBody"));
}

test "program frontend lowers nested workflow publish to the canonical scenario" {
    const lowered = program_frontend.lower(program_frontend.examples.nestedWorkflowPublish());
    try std.testing.expectEqualStrings("nested_workflow", lowered.scenario.case_id);
}

test "open-row lowering rejects ambiguous entry symbols across modules" {
    try std.testing.expectError(error.DuplicateSymbol, program_frontend.lowerOpenRow(.{
        .label = "example.ambiguous_entry",
        .entry_symbol = "runBody",
        .functions = &.{
            .{
                .symbol = .{
                    .module_path = "examples/root.zig",
                    .symbol_name = "runBody",
                },
                .row = effect_ir.rowFromSpec(.{}),
            },
            .{
                .symbol = .{
                    .module_path = "examples/helper.zig",
                    .symbol_name = "runBody",
                },
                .row = effect_ir.rowFromSpec(.{}),
            },
        },
    }));
}
