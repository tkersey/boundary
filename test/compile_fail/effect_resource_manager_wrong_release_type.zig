const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const ResourceInstance = shift.effect.resource.Instance(i32, NoError);
const bad_manager = struct {
    /// Deliberately acquire the correct resource type.
    pub fn acquire() i32 {
        return 0;
    }

    /// Deliberately use the wrong release parameter type.
    pub fn release(_: []const u8) void {
        // Intentionally empty for this malformed manager.
    }
};

/// Attempt to handle a resource effect with an invalid release shape.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    var instance = ResourceInstance.init();
    _ = try shift.effect.resource.handle(i32, &runtime, &instance, bad_manager, struct {
        /// Force the handler to instantiate the malformed manager.
        pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(NoError)!i32 {
            _ = try shift.effect.resource.acquire(Cap, ctx);
            return 0;
        }
    });
}
