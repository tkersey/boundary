const ability = @import("ability");

const Protocol = ability.ir.schema.Protocol(.{
    .label = "semantic.empty.label",
    .ops = .{
        ability.ir.schema.transform("exists", []const u8, i32),
    },
});

const Rows = Protocol.Rows(void, .{ .requirement_index = 0, .first_op = 0 });

test "semantic builder rejects empty site label" {
    _ = comptime ability.ir.builder.semantic.finish(.{
        .label = "semantic.empty.label",
        .ir_hash = 1,
        .entry = "run",
        .requirements = &.{Rows.requirement},
        .ops = &Rows.ops,
        .functions = .{.{
            .symbol_name = "run",
            .requirements = ability.ir.builder.semantic.span(0, 1),
            .params = .{},
            .locals = .{
                ability.ir.builder.semantic.local("payload", []const u8),
                ability.ir.builder.semantic.local("exists", i32),
            },
            .result = i32,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{
                    ability.ir.builder.semantic.constString("payload", "request-7"),
                    ability.ir.builder.semantic.call(Rows.op("exists"), .{ .dst = "exists", .payload = "payload", .label = "" }),
                },
                .terminator = ability.ir.builder.semantic.returnValue("exists"),
            }},
        }},
    });
}
