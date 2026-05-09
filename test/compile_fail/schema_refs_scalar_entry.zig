// zlinter-disable declaration_naming require_doc_comment
const ability = @import("ability");

const ScalarRefs = ability.ir.schema.SchemaRefs(.{
    ability.ir.schema.ref(i32, 0),
});

test "schema refs reject scalar entries" {
    _ = ScalarRefs;
}
