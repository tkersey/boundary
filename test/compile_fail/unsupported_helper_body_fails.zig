const shift_compile = @import("shift_compile");

comptime {
    _ = shift_compile.lowering.lowerAt("test/compile_fail_inputs/unsupported_helper_body_source.zig", .{
        .label = "compile_fail.unsupported_helper_body",
        .entry_symbol = "runBody",
        .row = shift_compile.ir.rowFromSpec(.{}),
    });
}
