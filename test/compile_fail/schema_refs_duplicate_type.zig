// zlinter-disable declaration_naming require_doc_comment
const boundary = @import("boundary");

const ProductPayload = struct {
    amount: i32,
};

const DuplicateRefs = boundary.ir.schema.SchemaRefs(.{
    boundary.ir.schema.ref(ProductPayload, 0),
    boundary.ir.schema.ref(ProductPayload, 1),
});

test "schema refs reject duplicate type entries" {
    _ = DuplicateRefs;
}
