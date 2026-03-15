const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const ping = shift.algebraic.TransformOp("ping", void, i32);
const demo = shift.algebraic.Program(i32, NoError, .{ping});

const no_state = struct {};

const configured = demo.handlers(.{
    shift.algebraic.handleTransform(ping, no_state{}, struct {
        /// Supply the transform witness value.
        pub fn resumeValue(_: no_state, _: void) i32 {
            return 41;
        }

        /// Trigger the wrong-afterResume-type compile failure.
        pub fn afterResume(_: no_state, _: i32) i64 {
            return 42;
        }
    }),
});

const body = struct {
    /// Provide the compile-fail wrong-afterResume-type witness program.
    pub fn program(ctx: *@TypeOf(configured).Context) @TypeOf(ctx.performProgram(ping, {}, struct {
        /// Increment the compile-fail ping witness value.
        pub fn apply(value: i32) i32 {
            return value + 1;
        }
    })) {
        return ctx.performProgram(ping, {}, struct {
            /// Increment the compile-fail ping witness value.
            pub fn apply(value: i32) i32 {
                return value + 1;
            }
        });
    }
};

/// Trigger the compile-fail wrong-afterResume-type witness.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    _ = try configured.run(&runtime, body);
}
