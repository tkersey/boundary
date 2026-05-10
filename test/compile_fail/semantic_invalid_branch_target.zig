const ability = @import("ability");

test "semantic builder rejects invalid branch target" {
    _ = comptime ability.ir.builder.semantic.finish(.{
        .label = "semantic.invalid.branch",
        .ir_hash = 0,
        .entry = "run",
        .functions = .{.{
            .symbol_name = "run",
            .params = .{},
            .locals = .{
                ability.ir.builder.semantic.local("value", i32),
                ability.ir.builder.semantic.local("is_zero", bool),
            },
            .result = i32,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{
                    ability.ir.builder.semantic.constI32("value", 0),
                    ability.ir.builder.semantic.compareEqZero("is_zero", "value"),
                },
                .terminator = ability.ir.builder.semantic.branchIf("is_zero", .{
                    .then = "missing",
                    .@"else" = "entry",
                }),
            }},
        }},
    });
}
