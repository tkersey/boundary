// zlinter-disable declaration_naming require_doc_comment
const boundary = @import("boundary");

const UnsupportedRefs = boundary.ir.schema.SchemaRefs(.{
    boundary.ir.schema.ref(*const i32, 0),
});

test "schema refs reject unsupported entry types" {
    _ = UnsupportedRefs;
}
