const std = @import("std");

test "optional fixture transcript remains archived outside the compiled lexical suite" {
    try std.testing.expect(@embedFile("example_proof/fixtures/optional_basic.txt").len != 0);
}
