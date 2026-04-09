const shift_compile = @import("shift_compile");

comptime {
    const symbol: shift_compile.ir.SymbolRef = .{
        .module_path = "test/compile_fail/public_ir_terminator_precondition_fails.zig",
        .symbol_name = "entry",
    };
    const Program: shift_compile.ir.Program = .{
        .entry_index = 0,
        .functions = &.{.{
            .symbol = symbol,
            .row = shift_compile.ir.rowFromSpec(.{}),
            .ValueType = i32,
        }},
        .call_edges = &.{},
        .function_bodies = &.{.{
            .local_codecs = &.{.i32},
            .blocks = &.{.{
                .instructions = &.{.{
                    .kind = .const_i32,
                    .dst = 0,
                    .operand = 1,
                }},
                .terminator = .{ .kind = .return_value },
            }},
        }},
    };

    _ = shift_compile.ir.compile("compile_fail.public_ir_terminator_precondition", Program);
}
