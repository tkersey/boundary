const ability = @import("ability");
const std = @import("std");

const Directory = ability.effect.Define(.{
    .state_type = void,
    .ops = .{
        ability.effect.ops.Transform("exists", []const u8, bool),
    },
});

const bad_directory_handler = struct {
    /// Return the transform answer with the correct type.
    pub fn exists(_: *@This(), _: []const u8) bool {
        return true;
    }

    /// Return the wrong final answer type from the transform after hook.
    pub fn afterExists(_: *@This(), _: []const u8) bool {
        return true;
    }
};

const body = struct {
    fn sourceLocation() std.builtin.SourceLocation {
        return @src();
    }

    /// Embedded source used by the negative source-backed body.
    pub const source = @embedFile("custom_effect_bad_after_negative.zig");
    /// Stable hash for the embedded source witness.
    pub const source_hash = ability.sourceHash(source);
    /// Source location owned by this compile-fail fixture.
    pub const source_location = sourceLocation();
    /// Basename required by the source-backed verifier.
    pub const source_file = "custom_effect_bad_after_negative.zig";
    /// Stable identity for the negative source-backed body.
    pub const source_identity = "custom_effect_bad_after_negative.body";

    /// Exercise a transform call whose after hook has the wrong return contract.
    pub fn body(eff: anytype) anyerror![]const u8 {
        _ = try eff.directory.exists.perform("request-7");
        return "ok";
    }
};

test "wrong after return type fails" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    _ = try ability.with(&runtime, .{
        .directory = Directory.use(.{ .handler = bad_directory_handler{} }),
    }, body);
}
