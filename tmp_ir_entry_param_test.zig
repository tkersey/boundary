const shift = @import("src/root.zig");
const std = @import("std");

test "ir compile entry param run fails" {
    const root: shift.ir.SymbolRef = .{ .module_path = "x.zig", .symbol_name = "runBody" };
    const program_type = shift.ir.compile("x", .{
        .entry_index = 0,
        .functions = &.{.{
            .symbol = root,
            .row = shift.ir.rowFromSpec(.{}),
            .parameter_codecs = &.{.i32},
            .ValueType = i32,
        }},
        .call_edges = &.{},
    });
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try std.testing.expectError(error.ProgramContractViolation, program_type.run(&runtime, .{}));
}
