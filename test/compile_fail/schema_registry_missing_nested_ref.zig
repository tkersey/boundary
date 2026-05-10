const ability = @import("ability");

const InnerPayload = struct {
    amount: i32,
};

const OuterPayload = struct {
    inner: InnerPayload,
};

const Schemas = ability.ir.schema.Registry(.{
    OuterPayload,
});

test "schema registry rejects missing nested structured refs" {
    _ = Schemas.value_schemas;
}
