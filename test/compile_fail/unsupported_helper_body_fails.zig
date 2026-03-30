const shift = @import("shift");

comptime {
    _ = shift.lowerAt("test/compile_fail_inputs/unsupported_helper_body_source.zig", .{
        .label = "compile_fail.unsupported_helper_body",
        .entry_symbol = "runBody",
        .row = shift.ir.rowFromSpec(.{}),
    });
}
