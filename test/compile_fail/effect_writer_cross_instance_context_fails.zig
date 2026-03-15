const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const WriterInstance = shift.effect.writer.Instance([]const u8, NoError);

const demo = struct {
    var runtime_ptr: ?*shift.Runtime = null;
    var inner_ptr: ?*const WriterInstance = null;
    var arena_ptr: ?*std.heap.ArenaAllocator = null;

    /// Start a nested handle and try to treat its context as the outer one.
    pub fn outer(comptime OuterCap: type, _: anytype) shift.ResetError(NoError)![]const u8 {
        const result = try shift.effect.writer.handle([]const u8, []const u8, runtime_ptr.?, inner_ptr.?, arena_ptr.?.allocator(), struct {
            /// Attempt to append with the wrong capability type.
            pub fn program(comptime InnerCap: type, inner_ctx: anytype) @TypeOf(shift.effect.writer.computeProgram(InnerCap, inner_ctx, struct {
                /// Attempt to append with the wrong capability type.
                pub fn run(_: type, program_ctx: anytype) shift.ResetError(NoError)![]const u8 {
                    try shift.effect.writer.tell(OuterCap, program_ctx, "bad");
                    return "done";
                }
            })) {
                return shift.effect.writer.computeProgram(InnerCap, inner_ctx, struct {
                    /// Attempt to append with the wrong capability type.
                    pub fn run(_: type, program_ctx: anytype) shift.ResetError(NoError)![]const u8 {
                        try shift.effect.writer.tell(OuterCap, program_ctx, "bad");
                        return "done";
                    }
                });
            }
        });
        return result.value;
    }
};

/// Attempt to treat one writer capability as though it belonged to another.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var outer_instance = WriterInstance.init();
    var inner_instance = WriterInstance.init();
    demo.runtime_ptr = &runtime;
    demo.inner_ptr = &inner_instance;
    demo.arena_ptr = &arena;
    _ = try shift.effect.writer.handle([]const u8, []const u8, &runtime, &outer_instance, arena.allocator(), struct {
        /// Invoke the outer body with the fresh outer capability.
        pub fn program(comptime OuterCap: type, ctx: anytype) @TypeOf(shift.effect.writer.computeProgram(OuterCap, ctx, struct {
            /// Re-enter the nested writer compile-fail witness.
            pub fn run(_: type, _: anytype) shift.ResetError(NoError)![]const u8 {
                return try demo.outer(OuterCap, {});
            }
        })) {
            return shift.effect.writer.computeProgram(OuterCap, ctx, struct {
                /// Re-enter the nested writer compile-fail witness.
                pub fn run(_: type, _: anytype) shift.ResetError(NoError)![]const u8 {
                    return try demo.outer(OuterCap, {});
                }
            });
        }
    });
}
