const ability = @import("ability");

const Approval = ability.effect.Define(.{
    .state_type = void,
    .ops = .{
        ability.effect.ops.Choice("request", []const u8, []const u8),
    },
});

const bad_approval_handler = struct {
    /// Return a plain string instead of the required choice decision.
    pub fn request(_: *@This(), _: []const u8) []const u8 {
        return "not-a-decision";
    }
};

const body = struct {
    fn sourceLocation() std.builtin.SourceLocation {
        return @src();
    }

    /// Embedded source used by the negative source-backed body.
    pub const source = @embedFile("custom_effect_bad_choice_handler_negative.zig");
    /// Stable hash for the embedded source witness.
    pub const source_hash = ability.sourceHash(source);
    /// Source location owned by this compile-fail fixture.
    pub const source_location = sourceLocation();
    /// Basename required by the source-backed verifier.
    pub const source_file = "custom_effect_bad_choice_handler_negative.zig";
    /// Stable identity for the negative source-backed body.
    pub const source_identity = "custom_effect_bad_choice_handler_negative.body";

    /// Exercise a choice call whose handler has the wrong return contract.
    pub fn body(eff: anytype) anyerror![]const u8 {
        return try eff.approval.request.perform("request-7", struct {
            /// Continue with the approved string when the handler resumes.
            pub fn apply(_: []const u8, _: anytype) anyerror![]const u8 {
                return "published";
            }
        });
    }
};

test "malformed choice handler payload/resume contract fails" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    _ = try ability.with(&runtime, .{
        .approval = Approval.use(.{ .handler = bad_approval_handler{} }),
    }, body);
}

const std = @import("std");
