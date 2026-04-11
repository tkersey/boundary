const shift_compile = @import("shift_compile");
const std = @import("std");

comptime {
    const entry_symbol: shift_compile.ir.SymbolRef = .{
        .module_path = "test/compile_fail/public_ir_foreign_row_call_op_fails.zig",
        .symbol_name = "entry",
    };
    const helper_symbol: shift_compile.ir.SymbolRef = .{
        .module_path = "test/compile_fail/public_ir_foreign_row_call_op_fails.zig",
        .symbol_name = "helper",
    };
    const Program: shift_compile.ir.Program = .{
        .entry_index = 0,
        .functions = &.{
            .{
                .symbol = entry_symbol,
                .row = shift_compile.ir.rowFromSpec(.{
                    .state = .{
                        .get = shift_compile.ir.Transform(void, i32),
                    },
                }),
            },
            .{
                .symbol = helper_symbol,
                .row = shift_compile.ir.rowFromSpec(.{
                    .writer = .{
                        .tell = shift_compile.ir.Transform([]const u8, void),
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

    _ = shift_compile.ir.compile("compile_fail.public_ir_foreign_row_call_op", Program);
}
