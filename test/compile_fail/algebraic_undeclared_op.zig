const shift = @import("shift");
const shift_internal = @import("shift_internal");
const std = @import("std");

const NoError = error{};
const ping = shift.algebraic.TransformOp("ping", void, i32);
const pong = shift.algebraic.TransformOp("pong", void, i32);
const demo = shift.algebraic.Program(i32, .{ping});

const no_state = struct {};

const configured = demo.handlers(.{
    shift.algebraic.handleTransform(ping, no_state{}, struct {
        /// Supply the transform witness value.
        pub fn resumeValue(_: no_state, _: void) i32 {
            return 1;
        }

        /// Preserve the resumed answer unchanged.
        pub fn afterResume(_: no_state, answer: i32) i32 {
            return answer;
        }
    }),
});

const body = struct {
    /// Provide the compile-fail undeclared-op witness program.
    pub fn program(ctx: *@TypeOf(configured).Context) @TypeOf(ctx.performProgram(pong, {}, struct {
        /// Preserve the compile-fail pong witness value.
        pub fn apply(value: i32) i32 {
            return value;
        }
    })) {
        return ctx.performProgram(pong, {}, struct {
            /// Preserve the compile-fail pong witness value.
            pub fn apply(value: i32) i32 {
                return value;
            }
        });
    }
};

/// Trigger the compile-fail undeclared-op witness.
pub fn main() anyerror!void {
    var runtime = shift_internal.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    _ = try configured.run(&runtime, body);
}
