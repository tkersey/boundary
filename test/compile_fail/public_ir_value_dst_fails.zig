const shift = @import("shift");
const std = @import("std");

comptime {
    const symbol: shift.ir.SymbolRef = .{
        .module_path = "test/compile_fail/public_ir_value_dst_fails.zig",
        .symbol_name = "entry",
    };
    const Program: shift.ir.Program = .{
        .entry_index = 0,
        .functions = &.{.{
            .symbol = symbol,
            .row = shift.ir.rowFromSpec(.{
                .counter = .{
                    .get = shift.ir.Transform(void, i32),
                },
            }),
        }},
        .call_edges = &.{},
        .function_bodies = &.{.{
            .local_codecs = &.{},
            .blocks = &.{.{
                .instructions = &.{.{
                    .kind = .call_op,
                    .dst = 0,
                    .operand = 0,
                    .aux = std.math.maxInt(u16),
                }},
                .terminator = .{ .kind = .return_unit },
            }},
        }},
    };

    _ = shift.ir.compile("compile_fail.public_ir_value_dst", Program);
}
