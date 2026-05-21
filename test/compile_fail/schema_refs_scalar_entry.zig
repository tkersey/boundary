// zlinter-disable declaration_naming require_doc_comment
const boundary = @import("boundary");

const ScalarRefs = boundary.ir.schema.SchemaRefs(.{
    boundary.ir.schema.ref(i32, 0),
});

test "schema refs reject scalar entries" {
    _ = ScalarRefs;
}
