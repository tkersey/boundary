const shift_compile = @import("shift_compile");

comptime {
    _ = shift_compile.lowering.lowerAt("test/compile_fail_inputs/entry_value_param_source.zig", .{
        .label = "compile_fail.entry_value_param_lower_at",
        .entry_symbol = "runBody",
        .row = shift_compile.ir.rowFromSpec(.{}),
    });
}
