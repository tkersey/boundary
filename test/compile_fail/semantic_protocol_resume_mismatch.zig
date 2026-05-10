const ability = @import("ability");

const Protocol = ability.ir.schema.Protocol(.{
    .label = "semantic.protocol.mismatch.resume",
    .ops = .{
        ability.ir.schema.transform("exists", []const u8, i32),
    },
});
const Rows = Protocol.Rows(struct {}, .{ .requirement_index = 0, .first_op = 0 });
const Exists = Rows.op("exists");

test "semantic builder rejects protocol resume mismatch" {
    _ = comptime ability.ir.builder.semantic.finish(.{
        .label = "semantic.protocol.resume.mismatch",
        .ir_hash = 0,
        .entry = "run",
        .requirements = &.{Rows.requirement},
        .ops = &Rows.ops,
        .functions = .{.{
            .symbol_name = "run",
            .requirements = ability.ir.builder.semantic.span(0, 1),
            .params = .{},
            .locals = .{
                ability.ir.builder.semantic.local("payload", []const u8),
                ability.ir.builder.semantic.local("exists", []const u8),
            },
            .result = []const u8,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{
                    ability.ir.builder.semantic.constString("payload", "request-7"),
                    ability.ir.builder.semantic.call(Exists, .{ .dst = "exists", .payload = "payload" }),
                },
                .terminator = ability.ir.builder.semantic.returnValue("exists"),
            }},
        }},
    });
}
