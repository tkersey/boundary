const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const policy = struct {
    /// Choose the direct-return branch for the lexical optional compile-fail fixture.
    pub fn resumeOrReturn() shift.ResumeOrReturn(i32, []const u8) {
        return shift.ResumeOrReturn(i32, []const u8).returnNow("result=early");
    }

    /// Preserve the early answer unchanged in the compile-fail fixture.
    pub fn afterResume(answer: []const u8) []const u8 {
        return answer;
    }
};

/// Trigger the wrong lexical optional continuation arity compile failure.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    _ = try shift.with(&runtime, .{
        .optional = shift.effect.optional.use(i32, NoError, policy),
    }, struct {
        /// Attempt to call the lexical optional choice form with the wrong apply arity.
        pub fn body(eff: anytype) shift.ResetError(NoError)![]const u8 {
            return try eff.optional.request(struct {
                /// Deliberately omit the lexical effect bundle parameter.
                pub fn apply(_: i32) []const u8 {
                    return "bad";
                }
            });
        }
    });
}
