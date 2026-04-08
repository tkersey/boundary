const shift = @import("shift");

comptime {
    const entry_symbol: shift.ir.SymbolRef = .{
        .module_path = "test/compile_fail/public_ir_invalid_call_helper_target_fails.zig",
        .symbol_name = "entry",
    };
    const Program: shift.ir.Program = .{
        .entry_index = 0,
        .functions = &.{.{
            .symbol = entry_symbol,
            .row = shift.ir.rowFromSpec(.{}),
        }},
        .call_edges = &.{},
        .function_bodies = &.{.{
            .local_codecs = &.{},
            .call_arg_locals = &.{},
            .entry_block = 0,
            .blocks = &.{.{
                .instructions = &.{.{
                    .kind = .call_helper,
                    .dst = 0,
                    .operand = 1,
                    .aux = 0,
                }},
                .terminator = .{ .kind = .return_unit },
            }},
        }},
    };

    _ = shift.ir.compile("compile_fail.public_ir_invalid_call_helper_target", Program);
}
