const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const ResourceInstance = shift.effect.resource.Instance(i32, NoError);
const bad_manager = struct {
    /// Deliberately provide only the acquire half of the resource manager.
    pub fn acquire() i32 {
        return 0;
    }
};

/// Attempt to handle a resource effect with a malformed manager type.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
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
