const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const Picker = shift.effect.Define(.{
    .state_type = struct {},
    .error_set_type = NoError,
    .ops = .{
        shift.effect.ops.Choice("pick", i32, i32),
    },
});

/// Trigger the removed generated lexical choice tag-dispatch compile failure.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    _ = try shift.with(&runtime, .{
        .picker = Picker.use(.{ .handler = struct {
            /// Return now for the removed lexical choice surface fixture.
            pub fn pick(_: *@This(), _: i32) shift.effect.choice.Decision(i32, []const u8) {
                return shift.effect.choice.Decision(i32, []const u8).returnNow("result=early");
            }

            /// Preserve the early answer unchanged.
            pub fn afterPick(_: *@This(), answer: []const u8) []const u8 {
                return answer;
            }
        }{} }),
    }, struct {
        /// Attempt to use the removed generated lexical tag-dispatch choice surface.
        pub fn body(eff: anytype) ![]const u8 {
            return try eff.picker.perform(.pick, 41, struct {
                /// Provide the continuation for the removed lexical tag-dispatch choice surface.
                pub fn apply(_: i32, _: anytype) ![]const u8 {
                    return "answer";
                }
            });
        }
    });
}
