const boundary = @import("boundary");

const Payload = struct {
    amount: i32,
};

const Schemas = boundary.ir.schema.Registry(.{Payload});

test "semantic builder rejects explicit schema tables when registry is present" {
    _ = comptime boundary.ir.builder.semantic.finish(.{
        .label = "semantic.duplicate.schema.tables",
        .ir_hash = 1,
        .entry = "run",
        .schemas = Schemas,
        .value_schemas = &Schemas.value_schemas,
        .functions = .{.{
            .symbol_name = "run",
            .params = .{
                boundary.ir.builder.semantic.param("payload", Payload),
            },
            .locals = .{},
            .result = Payload,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{},
                .terminator = boundary.ir.builder.semantic.returnValue("payload"),
            }},
        }},
    });
}
