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

test "open-row lowering disambiguates same-named entry symbols by module path" {
    const lowered = comptime try program_frontend.lowerOpenRow(.{
        .label = "example.ambiguous_entry",
        .entry_symbol = "runBody",
        .entry_module_path = "examples/root.zig",
        .functions = &.{
            .{
                .symbol = .{
                    .module_path = "examples/helper.zig",
                    .symbol_name = "runBody",
                },
                .row = effect_ir.rowFromSpec(.{}),
            },
            .{
                .symbol = .{
                    .module_path = "examples/root.zig",
                    .symbol_name = "runBody",
                },
                .row = effect_ir.rowFromSpec(.{}),
            },
        },
    });

    try std.testing.expectEqual(@as(usize, 1), lowered.entry_index);
    try std.testing.expectEqualStrings("examples/root.zig", lowered.functions[lowered.entry_index].symbol.module_path);
}

test "open-row lowering rejects ambiguous entry symbols when the entry module is absent" {
    const saw_duplicate_symbol = comptime blk: {
        const result = program_frontend.lowerOpenRow(.{
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
        });
        break :blk if (result) |_| false else |err| err == error.DuplicateSymbol;
    };
    try std.testing.expect(saw_duplicate_symbol);
}
