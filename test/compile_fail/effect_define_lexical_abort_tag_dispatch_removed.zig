const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const Guard = shift.effect.Define(.{
    .state_type = struct {},
    .error_set_type = NoError,
    .ops = .{
        shift.effect.ops.Abort("fail", []const u8),
    },
});

/// Trigger the removed generated lexical abort tag-dispatch compile failure.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    _ = try shift.with(&runtime, .{
        .guard = Guard.use(.{ .handler = struct {
            /// Return the canonical abort answer.
            pub fn fail(_: *@This(), _: []const u8) []const u8 {
                return "error";
            }
        }{} }),
    }, struct {
        /// Attempt to use the removed generated lexical tag-dispatch abort surface.
        pub fn body(eff: anytype) shift.ResetError(NoError)![]const u8 {
            try eff.guard.abort(.fail, "boom");
        }
    });
}
