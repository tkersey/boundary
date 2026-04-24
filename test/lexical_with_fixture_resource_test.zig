const std = @import("std");

test "resource fixture transcript remains archived outside the compiled lexical suite" {
    try std.testing.expect(@embedFile("example_proof/fixtures/resource_basic.txt").len != 0);
}
