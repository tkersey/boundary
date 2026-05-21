// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");

const Policy = boundary.ir.schema.Protocol(.{
    .label = "policy",
    .ops = .{
        boundary.ir.schema.transform("check", void, bool),
    },
});

comptime {
    _ = Policy.operation("check", .{ .Result = i32 });
}
