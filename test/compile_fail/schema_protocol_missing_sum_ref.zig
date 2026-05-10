// zlinter-disable declaration_naming require_doc_comment
const ability = @import("ability");

const Decision = union(enum) {
    approve: i32,
    deny,
};

const Approval = ability.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{
        ability.ir.schema.choice("request", void, Decision),
    },
});

const Rows = Approval.Rows(void, .{
    .requirement_index = 0,
    .first_op = 0,
});

test "custom protocol rejects missing sum schema ref" {
    _ = Rows;
}
