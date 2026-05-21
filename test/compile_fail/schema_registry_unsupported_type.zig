const boundary = @import("boundary");

const Schemas = boundary.ir.schema.Registry(.{
    *const i32,
});

test "schema registry rejects unsupported explicit types" {
    _ = Schemas.value_schemas;
}
