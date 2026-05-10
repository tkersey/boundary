const ability = @import("ability");

test "semantic builder rejects local type mismatch" {
    _ = comptime ability.ir.builder.semantic.finish(.{
        .label = "semantic.local.mismatch",
        .ir_hash = 0,
        .entry = "run",
        .functions = .{.{
            .symbol_name = "run",
            .params = .{},
            .locals = .{
                ability.ir.builder.semantic.local("result", i32),
            },
            .result = i32,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{
                    ability.ir.builder.semantic.constString("result", "wrong"),
                },
                .terminator = ability.ir.builder.semantic.returnValue("result"),
            }},
        }},
    });
}
