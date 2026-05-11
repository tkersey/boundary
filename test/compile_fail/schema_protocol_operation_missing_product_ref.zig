const ability = @import("ability");

const ProductPayload = struct {
    value: i32,
};

const Protocol = ability.ir.schema.Protocol(.{
    .label = "descriptor-missing-ref",
    .ops = .{
        ability.ir.schema.transform("check", ProductPayload, i32),
    },
});

const Check = Protocol.operation("check", .{});

test "protocol operation descriptors require product refs" {
    _ = Check;
}
