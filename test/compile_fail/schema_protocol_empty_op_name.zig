// zlinter-disable declaration_naming require_doc_comment
const boundary = @import("boundary");

const EmptyOpName = boundary.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{
        boundary.ir.schema.transform("", void, i32),
    },
});

test "custom protocol rejects empty op names" {
    _ = EmptyOpName;
}
