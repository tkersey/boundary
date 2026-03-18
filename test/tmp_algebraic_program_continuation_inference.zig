const std = @import("std");
const shift = @import("shift");

const no_state = struct {};
const ping = shift.algebraic.TransformOp("ping", void, i32);
const configured = shift.algebraic.Program(i32, .{ping}).handlers(.{
    shift.algebraic.handleTransform(ping, no_state{}, struct {
        pub fn resumeValue(_: no_state, _: void) i32 {
            return 7;
        }
        pub fn afterResume(_: no_state, answer: i32) i32 {
            return answer;
        }
    }),
});

test "algebraic Program infers continuation errors in explicit program bodies" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    _ = configured.run(&runtime, struct {
        pub fn program(ctx: *@TypeOf(configured).Context) @TypeOf(ctx.performProgram(ping, {}, struct {
            pub fn apply(_: i32) !i32 {
                return error.ContinueOops;
            }
        })) {
            return ctx.performProgram(ping, {}, struct {
                pub fn apply(_: i32) !i32 {
                    return error.ContinueOops;
                }
            });
        }
    });
}
