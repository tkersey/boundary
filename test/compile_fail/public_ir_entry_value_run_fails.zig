const shift_compile = @import("shift_compile");
const shift_vm = @import("shift_vm");
const shift = shift_vm;

comptime {
    const symbol: shift_compile.ir.SymbolRef = .{
        .module_path = "test/compile_fail/public_ir_entry_value_run_fails.zig",
        .symbol_name = "entry",
    };
    const Program: shift_compile.ir.Program = .{
        .entry_index = 0,
        .functions = &.{.{
            .symbol = symbol,
            .row = shift_compile.ir.rowFromSpec(.{}),
            .parameter_codecs = &.{.i32},
            .ValueType = void,
        }},
        .call_edges = &.{},
    };
    const ProgramType = shift_compile.ir.compile("compile_fail.public_ir_entry_value_run", Program);
    // zlinter-disable-next-line no_undefined - compile-fail fixture rejects entry parameters before any runtime state is observed
    var runtime: shift.Runtime = undefined;
    _ = ProgramType.run(&runtime, .{});
}
