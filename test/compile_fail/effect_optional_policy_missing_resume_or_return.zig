const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const OptionalInstance = shift.effect.optional.Instance(i32, error{});
const bad_policy = struct {
    /// Deliberately provide only the completion half of the optional policy.
    pub fn afterResume(value: i32) i32 {
        return value;
    }
};

/// Attempt to handle an optional effect with a malformed policy type.
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
