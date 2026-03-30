const shift = @import("shift");

comptime {
    const symbol: shift.ir.SymbolRef = .{
        .module_path = "test/compile_fail/string_list_codec_fails.zig",
        .symbol_name = "entry",
    };
    const Program: shift.ir.Program = .{
        .entry_index = 0,
        .functions = &.{.{
            .symbol = symbol,
            .row = shift.ir.rowFromSpec(.{}),
            .ValueType = [][]const u8,
        }},
        .call_edges = &.{},
        .function_bodies = &.{.{
            .local_codecs = &.{.string_list},
            .blocks = &.{.{
                .instructions = &.{
                    .{ .kind = .return_value, .operand = 0 },
                },
                .terminator = .{ .kind = .return_value },
            }},
        }},
    };

    _ = shift.ir.compile("compile_fail.string_list_codec", Program);
}
