const shift = @import("shift");

comptime {
    const symbol: shift.ir.SymbolRef = .{
        .module_path = "test/compile_fail/public_ir_entry_value_run_fails.zig",
        .symbol_name = "entry",
    };
    const Program: shift.ir.Program = .{
        .entry_index = 0,
        .functions = &.{.{
            .symbol = symbol,
            .row = shift.ir.rowFromSpec(.{}),
            .parameter_codecs = &.{.i32},
            .ValueType = void,
        }},
        .call_edges = &.{},
    };
    const ProgramType = shift.ir.compile("compile_fail.public_ir_entry_value_run", Program);
    var runtime: shift.Runtime = undefined;
    _ = ProgramType.run(&runtime, .{});
}
