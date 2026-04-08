const shift = @import("shift");

comptime {
    const symbol: shift.ir.SymbolRef = .{
        .module_path = "test/compile_fail/public_ir_blockless_entry_fails.zig",
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
            .local_codecs = &.{},
            .blocks = &.{},
        }},
    };

    _ = shift.ir.compile("compile_fail.public_ir_blockless_entry", Program);
}
