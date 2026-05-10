// zlinter-disable declaration_naming require_doc_comment
const ability = @import("ability");

const DuplicateOps = ability.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{
        ability.ir.schema.transform("exists", void, i32),
        ability.ir.schema.choice("exists", void, i32),
    },
});

test "custom protocol rejects duplicate op names" {
    _ = DuplicateOps;
}
