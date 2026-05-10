const ability = @import("ability");

const Protocol = ability.ir.schema.Protocol(.{
    .label = "semantic.protocol.mismatch.payload",
    .ops = .{
        ability.ir.schema.transform("exists", []const u8, i32),
    },
});
const Rows = Protocol.Rows(struct {}, .{ .requirement_index = 0, .first_op = 0 });
const Exists = Rows.op("exists");

test "semantic builder rejects protocol payload mismatch" {
    _ = comptime ability.ir.builder.semantic.finish(.{
        .label = "semantic.protocol.payload.mismatch",
        .ir_hash = 0,
        .entry = "run",
        .requirements = &.{Rows.requirement},
        .ops = &Rows.ops,
        .functions = .{.{
            .symbol_name = "run",
            .requirements = ability.ir.builder.semantic.span(0, 1),
            .params = .{},
            .locals = .{
                ability.ir.builder.semantic.local("payload", i32),
                ability.ir.builder.semantic.local("exists", i32),
            },
            .result = i32,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{
                    ability.ir.builder.semantic.constI32("payload", 1),
                    ability.ir.builder.semantic.call(Exists, .{ .dst = "exists", .payload = "payload" }),
                },
                .terminator = ability.ir.builder.semantic.returnValue("exists"),
            }},
        }},
    });
}
