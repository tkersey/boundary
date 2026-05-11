// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const ability = @import("ability");

const Policy = ability.ir.schema.Protocol(.{
    .label = "policy",
    .ops = .{
        ability.ir.schema.transform("check", void, bool),
    },
});

comptime {
    _ = Policy.operation("check", .{ .Result = i32 });
}
