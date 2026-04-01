const shift = @import("shift");
const std = @import("std");

comptime {
    const entry_symbol: shift.ir.SymbolRef = .{
        .module_path = "test/compile_fail/public_ir_foreign_row_call_op_fails.zig",
        .symbol_name = "entry",
    };
    const helper_symbol: shift.ir.SymbolRef = .{
        .module_path = "test/compile_fail/public_ir_foreign_row_call_op_fails.zig",
        .symbol_name = "helper",
    };
    const Program: shift.ir.Program = .{
        .entry_index = 0,
        .functions = &.{
            .{
                .symbol = entry_symbol,
                .row = shift.ir.rowFromSpec(.{
                    .state = .{
                        .get = shift.ir.Transform(void, i32),
                    },
                }),
            },
            .{
                .symbol = helper_symbol,
                .row = shift.ir.rowFromSpec(.{
                    .writer = .{
                        .tell = shift.ir.Transform([]const u8, void),
                    },
                }),
            },
        },
        .call_edges = &.{},
        .function_bodies = &.{
            .{
                .local_codecs = &.{},
                .blocks = &.{.{
                    .instructions = &.{},
                    .terminator = .{ .kind = .return_unit },
                }},
            },
            .{
                .local_codecs = &.{.i32},
                .blocks = &.{.{
                    .instructions = &.{.{
                        .kind = .call_op,
                        .dst = 0,
                        .operand = 0,
                        .aux = std.math.maxInt(u16),
                    }},
                    .terminator = .{ .kind = .return_unit },
                }},
            },
        },
    };

    _ = shift.ir.compile("compile_fail.public_ir_foreign_row_call_op", Program);
}
