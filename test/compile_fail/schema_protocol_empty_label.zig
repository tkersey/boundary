// zlinter-disable declaration_naming require_doc_comment
const boundary = @import("boundary");

const EmptyLabel = boundary.ir.schema.Protocol(.{
    .label = "",
    .ops = .{
        boundary.ir.schema.transform("step", void, i32),
    },
});

test "custom protocol rejects empty label" {
    _ = EmptyLabel;
}
