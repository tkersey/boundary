const boundary = @import("boundary");

const ProductPayload = struct {
    amount: i32,
};

const Schemas = boundary.ir.schema.Registry(.{
    ProductPayload,
    ProductPayload,
});

test "schema registry rejects duplicate structured type entries" {
    _ = Schemas.value_schemas;
}
