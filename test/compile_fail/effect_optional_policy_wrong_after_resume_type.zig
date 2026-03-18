const prompt_support = @import("prompt_support");
const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const OptionalInstance = shift.effect.optional.Instance(i32, error{});
const bad_policy = struct {
    /// Deliberately pick the resumptive optional branch.
    pub fn resumeOrReturn() prompt_support.ResumeOrReturn(i32, i32) {
        return prompt_support.ResumeOrReturn(i32, i32).resumeWith(1);
    }

    /// Deliberately use the wrong parameter type for optional afterResume.
    pub fn afterResume(_: []const u8) i32 {
        return 2;
    }
};

/// Attempt to handle an optional effect with an invalid afterResume shape.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    var instance = OptionalInstance.init();
    _ = try shift.effect.optional.handle(i32, &runtime, &instance, bad_policy, struct {
        /// Force the handler to instantiate the malformed optional policy.
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(shift.effect.optional.requestProgram(Cap, ctx, struct {
            /// Preserve the compile-fail optional witness value.
            pub fn apply(value: i32) i32 {
                return value;
            }
        })) {
            return shift.effect.optional.requestProgram(Cap, ctx, struct {
                /// Preserve the compile-fail optional witness value.
                pub fn apply(value: i32) i32 {
                    return value;
                }
            });
        }
    });
}
