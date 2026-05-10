// zlinter-disable declaration_naming require_doc_comment
const ability = @import("ability");

const ProductPayload = struct {
    amount: i32,
};

const Approval = ability.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{
        ability.ir.schema.transform("exists", ProductPayload, i32),
    },
});

const Rows = Approval.Rows(void, .{
    .requirement_index = 0,
    .first_op = 0,
});

test "custom protocol rejects missing product schema ref" {
    _ = Rows;
}
