const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const StateInstance = shift.effect.state.Instance(i32, NoError);

const demo = struct {
    var runtime_ptr: ?*shift.Runtime = null;
    var inner_ptr: ?*const StateInstance = null;

    /// Start a nested handle and try to treat its context as the outer one.
    pub fn outer(comptime OuterCap: type, _: anytype) shift.ResetError(NoError)!i32 {
        const result = try shift.effect.state.handle(i32, runtime_ptr.?, inner_ptr.?, 0, struct {
            /// Attempt to coerce the inner capability to the outer capability type.
            pub fn program(comptime InnerCap: type, inner_ctx: anytype) @TypeOf(shift.effect.state.computeProgram(InnerCap, inner_ctx, struct {
                /// Attempt to read state with the wrong capability type.
                pub fn run(_: type, program_ctx: anytype) shift.ResetError(NoError)!i32 {
                    _ = try shift.effect.state.get(OuterCap, program_ctx);
                    return 0;
                }
            })) {
                return shift.effect.state.computeProgram(InnerCap, inner_ctx, struct {
                    /// Attempt to read state with the wrong capability type.
                    pub fn run(_: type, program_ctx: anytype) shift.ResetError(NoError)!i32 {
                        _ = try shift.effect.state.get(OuterCap, program_ctx);
                        return 0;
                    }
                });
            }
        });
        return result.value;
    }
};

/// Attempt to treat one instance capability as though it belonged to another.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    var outer_instance = StateInstance.init();
    var inner_instance = StateInstance.init();
    demo.runtime_ptr = &runtime;
    demo.inner_ptr = &inner_instance;
    _ = try shift.effect.state.handle(i32, &runtime, &outer_instance, 0, struct {
        /// Invoke the outer body with the fresh outer capability.
        pub fn program(comptime OuterCap: type, ctx: anytype) @TypeOf(shift.effect.state.computeProgram(OuterCap, ctx, struct {
            /// Re-enter the nested state compile-fail witness.
            pub fn run(_: type, _: anytype) shift.ResetError(NoError)!i32 {
                return try demo.outer(OuterCap, {});
            }
        })) {
            return shift.effect.state.computeProgram(OuterCap, ctx, struct {
                /// Re-enter the nested state compile-fail witness.
                pub fn run(_: type, _: anytype) shift.ResetError(NoError)!i32 {
                    return try demo.outer(OuterCap, {});
                }
            });
        }
    });
}
