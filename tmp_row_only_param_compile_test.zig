const shift = @import("src/root.zig");

test "compile row-only helper with params" {
    const root = shift.ir.SymbolRef{ .module_path = "x.zig", .symbol_name = "root" };
    const helper = shift.ir.SymbolRef{ .module_path = "x.zig", .symbol_name = "helper" };
    const program_type = shift.ir.compile("x", .{
        .entry_index = 0,
        .functions = &.{
            .{ .symbol = root, .row = shift.ir.rowFromSpec(.{}) },
            .{ .symbol = helper, .row = shift.ir.rowFromSpec(.{}), .parameter_codecs = &.{.i32} },
        },
        .call_edges = &.{.{ .caller = root, .callee = helper }},
    });
    _ = program_type;
}
