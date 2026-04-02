const shift = @import("shift");

comptime {
    const symbol: shift.ir.SymbolRef = .{
        .module_path = "test/compile_fail/public_ir_entry_value_param_fails.zig",
        .symbol_name = "entry",
    };
    const Program: shift.ir.Program = .{
        .entry_index = 0,
        .functions = &.{.{
            .symbol = symbol,
            .row = shift.ir.rowFromSpec(.{}),
            .parameter_codecs = &.{.i32},
            .ValueType = i32,
        }},
        .call_edges = &.{},
    };

    _ = shift.ir.compile("compile_fail.public_ir_entry_value_param", Program);
}
