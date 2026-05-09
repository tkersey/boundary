// zlinter-disable declaration_naming require_doc_comment
const ability = @import("ability");

const ProductPayload = struct {
    amount: i32,
};

const DuplicateRefs = ability.ir.schema.SchemaRefs(.{
    ability.ir.schema.ref(ProductPayload, 0),
    ability.ir.schema.ref(ProductPayload, 1),
});

test "schema refs reject duplicate type entries" {
    _ = DuplicateRefs;
}
