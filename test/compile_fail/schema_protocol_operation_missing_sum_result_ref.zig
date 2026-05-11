const ability = @import("ability");

const Decision = enum {
    allow,
    deny,
};

const Protocol = ability.ir.schema.Protocol(.{
    .label = "descriptor-missing-sum-result-ref",
    .ops = .{
        ability.ir.schema.abort("reject", []const u8),
    },
});

const Reject = Protocol.operation("reject", .{ .Result = Decision });

test "protocol operation descriptors require sum result refs" {
    _ = Reject;
}
