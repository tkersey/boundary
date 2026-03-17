const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const ResourceInstance = shift.effect.resource.Instance(i32);
const bad_manager = struct {
    /// Deliberately provide only the release half of the resource manager.
    pub fn release(_: i32) void {
        // Intentionally empty for this malformed manager.
    }
};

/// Attempt to handle a resource effect with a malformed manager type.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    var instance = ResourceInstance.init();
    _ = try shift.effect.resource.handle(i32, &runtime, &instance, bad_manager, struct {
        /// Force the handler to instantiate the malformed manager.
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(shift.effect.resource.computeProgram(Cap, ctx, struct {
            /// Attempt one resource acquire under the malformed manager.
            pub fn run(comptime ProgramCap: type, program_ctx: anytype) !i32 {
                _ = try shift.effect.resource.acquire(ProgramCap, program_ctx);
                return 0;
            }
        })) {
            return shift.effect.resource.computeProgram(Cap, ctx, struct {
                /// Attempt one resource acquire under the malformed manager.
                pub fn run(comptime ProgramCap: type, program_ctx: anytype) !i32 {
                    _ = try shift.effect.resource.acquire(ProgramCap, program_ctx);
                    return 0;
                }
            });
        }
    });
}
