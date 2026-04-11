const shift_compile = @import("shift_compile");
const std = @import("std");

comptime {
    const symbol: shift_compile.ir.SymbolRef = .{
        .module_path = "test/compile_fail/public_ir_value_dst_fails.zig",
        .symbol_name = "entry",
    };
    const Program: shift_compile.ir.Program = .{
        .entry_index = 0,
        .functions = &.{.{
            .symbol = symbol,
            .row = shift_compile.ir.rowFromSpec(.{
                .counter = .{
                    .get = shift_compile.ir.Transform(void, i32),
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

    _ = shift_compile.ir.compile("compile_fail.public_ir_value_dst", Program);
}
