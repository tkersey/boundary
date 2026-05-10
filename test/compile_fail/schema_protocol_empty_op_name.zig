// zlinter-disable declaration_naming require_doc_comment
const ability = @import("ability");

const EmptyOpName = ability.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{
        ability.ir.schema.transform("", void, i32),
    },
});

test "custom protocol rejects empty op names" {
    _ = EmptyOpName;
}
