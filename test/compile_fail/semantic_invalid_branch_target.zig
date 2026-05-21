const boundary = @import("boundary");

test "semantic builder rejects invalid branch target" {
    _ = comptime boundary.ir.builder.semantic.finish(.{
        .label = "semantic.invalid.branch",
        .ir_hash = 0,
        .entry = "run",
        .functions = .{.{
            .symbol_name = "run",
            .params = .{},
            .locals = .{
                boundary.ir.builder.semantic.local("value", i32),
                boundary.ir.builder.semantic.local("is_zero", bool),
            },
            .result = i32,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{
                    boundary.ir.builder.semantic.constI32("value", 0),
                    boundary.ir.builder.semantic.compareEqZero("is_zero", "value"),
                },
                .terminator = boundary.ir.builder.semantic.branchIf("is_zero", .{
                    .then = "missing",
                    .@"else" = "entry",
                }),
            }},
        }},
    });
}
