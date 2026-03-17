const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const ReaderInstance = shift.effect.reader.Instance(i32);

const demo = struct {
    var runtime_ptr: ?*shift.Runtime = null;
    var inner_ptr: ?*const ReaderInstance = null;

    /// Start a nested handle and try to treat its context as the outer one.
    pub fn outer(comptime OuterCap: type, _: anytype) !i32 {
        return try shift.effect.reader.handle(i32, runtime_ptr.?, inner_ptr.?, 0, struct {
            /// Attempt to read with the wrong capability type.
            pub fn program(comptime InnerCap: type, inner_ctx: anytype) @TypeOf(shift.effect.reader.computeProgram(InnerCap, inner_ctx, struct {
                /// Attempt to read with the wrong capability type.
                pub fn run(_: type, program_ctx: anytype) !i32 {
                    return try shift.effect.reader.ask(OuterCap, program_ctx);
                }
            })) {
                return shift.effect.reader.computeProgram(InnerCap, inner_ctx, struct {
                    /// Attempt to read with the wrong capability type.
                    pub fn run(_: type, program_ctx: anytype) !i32 {
                        return try shift.effect.reader.ask(OuterCap, program_ctx);
                    }
                });
            }
        });
    }
};

/// Attempt to treat one reader capability as though it belonged to another.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    var outer_instance = ReaderInstance.init();
    var inner_instance = ReaderInstance.init();
    demo.runtime_ptr = &runtime;
    demo.inner_ptr = &inner_instance;
    _ = try shift.effect.reader.handle(i32, &runtime, &outer_instance, 0, struct {
        /// Invoke the outer body with the fresh outer capability.
        pub fn program(comptime OuterCap: type, ctx: anytype) @TypeOf(shift.effect.reader.computeProgram(OuterCap, ctx, struct {
            /// Re-enter the nested reader compile-fail witness.
            pub fn run(_: type, _: anytype) !i32 {
                return try demo.outer(OuterCap, {});
            }
        })) {
            return shift.effect.reader.computeProgram(OuterCap, ctx, struct {
                /// Re-enter the nested reader compile-fail witness.
                pub fn run(_: type, _: anytype) !i32 {
                    return try demo.outer(OuterCap, {});
                }
            });
        }
    });
}
