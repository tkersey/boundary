// zlinter-disable declaration_naming require_doc_comment
const ability = @import("ability");

const EmptyLabel = ability.ir.schema.Protocol(.{
    .label = "",
    .ops = .{
        ability.ir.schema.transform("step", void, i32),
    },
});

test "custom protocol rejects empty label" {
    _ = EmptyLabel;
}
