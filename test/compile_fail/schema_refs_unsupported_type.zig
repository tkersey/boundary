// zlinter-disable declaration_naming require_doc_comment
const ability = @import("ability");

const UnsupportedRefs = ability.ir.schema.SchemaRefs(.{
    ability.ir.schema.ref(*const i32, 0),
});

test "schema refs reject unsupported entry types" {
    _ = UnsupportedRefs;
}
