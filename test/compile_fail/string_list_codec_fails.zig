const shift_compile = @import("shift_compile");

comptime {
    const symbol: shift_compile.ir.SymbolRef = .{
        .module_path = "test/compile_fail/string_list_codec_fails.zig",
        .symbol_name = "entry",
    };
    const Program: shift_compile.ir.Program = .{
        .entry_index = 0,
        .functions = &.{.{
            .symbol = symbol,
            .row = shift_compile.ir.rowFromSpec(.{}),
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

    _ = shift_compile.ir.compile("compile_fail.string_list_codec", Program);
}
