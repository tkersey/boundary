const boundary = @import("boundary");

const ProductPayload = struct {
    value: i32,
};

const Protocol = boundary.ir.schema.Protocol(.{
    .label = "descriptor-missing-ref",
    .ops = .{
        boundary.ir.schema.transform("check", ProductPayload, i32),
    },
});

const Check = Protocol.operation("check", .{});

test "protocol operation descriptors require product refs" {
    _ = Check;
}
