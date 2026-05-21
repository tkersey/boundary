// zlinter-disable declaration_naming require_doc_comment
const boundary = @import("boundary");

const DuplicateOps = boundary.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{
        boundary.ir.schema.transform("exists", void, i32),
        boundary.ir.schema.choice("exists", void, i32),
    },
});

test "custom protocol rejects duplicate op names" {
    _ = DuplicateOps;
}
