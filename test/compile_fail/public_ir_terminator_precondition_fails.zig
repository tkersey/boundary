const shift = @import("shift");

comptime {
    const symbol: shift.ir.SymbolRef = .{
        .module_path = "test/compile_fail/public_ir_terminator_precondition_fails.zig",
        .symbol_name = "entry",
    };
    const Program: shift.ir.Program = .{
        .entry_index = 0,
        .functions = &.{.{
            .symbol = symbol,
            .row = shift.ir.rowFromSpec(.{}),
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

    _ = shift.ir.compile("compile_fail.public_ir_terminator_precondition", Program);
}
