const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const policy = struct {
    /// Choose the direct-return branch for the lexical optional compile-fail fixture.
    pub fn resumeOrReturn() shift.effect.choice.Decision(i32, []const u8) {
        return shift.effect.choice.Decision(i32, []const u8).returnNow("result=early");
    }

    /// Preserve the early answer unchanged in the compile-fail fixture.
    pub fn afterResume(answer: []const u8) []const u8 {
        return answer;
    }
};

/// Trigger the missing lexical optional continuation apply hook compile failure.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    _ = try shift.with(&runtime, .{
        .optional = shift.effect.optional.use(i32, policy),
    }, struct {
        /// Attempt to call the lexical optional choice form with no apply hook.
        pub fn body(eff: anytype) ![]const u8 {
            return try eff.optional.request(struct {});
        }
    });
}
