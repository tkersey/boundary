const boundary = @import("boundary");

const InnerPayload = struct {
    amount: i32,
};

const OuterPayload = struct {
    inner: InnerPayload,
};

const Schemas = boundary.ir.schema.Registry(.{
    OuterPayload,
});

test "schema registry rejects missing nested structured refs" {
    _ = Schemas.value_schemas;
}
