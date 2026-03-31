const shift = @import("src/root.zig");

test "compile invalid local ref" {
    const row = shift.ir.rowFromSpec(.{});
    const sym: shift.ir.SymbolRef = .{ .module_path = "x.zig", .symbol_name = "runBody" };
    const program_type = shift.ir.compile("bad.ir", .{
        .entry_index = 0,
        .functions = &.{.{
            .symbol = sym,
            .row = row,
            .ValueType = void,
        }},
        .call_edges = &.{},
        .function_bodies = &.{.{
            .local_codecs = &.{},
            .entry_block = 0,
            .blocks = &.{.{
                .instructions = &.{.{ .kind = .compare_eq_zero, .dst = 0, .operand = 0 }},
                .terminator = .{ .kind = .return_unit },
            }},
        }},
    });
    _ = program_type;
}
