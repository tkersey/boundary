const boundary = @import("boundary");

test "semantic builder rejects local type mismatch" {
    _ = comptime boundary.ir.builder.semantic.finish(.{
        .label = "semantic.local.mismatch",
        .ir_hash = 0,
        .entry = "run",
        .functions = .{.{
            .symbol_name = "run",
            .params = .{},
            .locals = .{
                boundary.ir.builder.semantic.local("result", i32),
            },
            .result = i32,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{
                    boundary.ir.builder.semantic.constString("result", "wrong"),
                },
                .terminator = boundary.ir.builder.semantic.returnValue("result"),
            }},
        }},
    });
}
