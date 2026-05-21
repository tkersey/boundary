const boundary = @import("boundary");

const Decision = enum {
    allow,
    deny,
};

const Protocol = boundary.ir.schema.Protocol(.{
    .label = "descriptor-missing-sum-result-ref",
    .ops = .{
        boundary.ir.schema.abort("reject", []const u8),
    },
});

const Reject = Protocol.operation("reject", .{ .Result = Decision });

test "protocol operation descriptors require sum result refs" {
    _ = Reject;
}
