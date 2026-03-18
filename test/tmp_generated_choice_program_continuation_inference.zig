const std = @import("std");
const shift = @import("shift");

const Picker = shift.effect.Define(.{
    .state_type = struct {},
    .ops = .{
        shift.effect.ops.Choice("pick", i32, i32),
    },
});

const handler = struct {
    pub fn pick(_: *@This(), payload: i32) shift.effect.choice.Decision(i32, i32) {
        return shift.effect.choice.Decision(i32, i32).resumeWith(payload);
    }
    pub fn afterPick(_: *@This(), answer: i32) i32 {
        return answer;
    }
};

test "generated family handle infers continuation errors in explicit program bodies" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = Picker.Instance.init();

    _ = Picker.handle(i32, &runtime, &instance, handler{}, struct {
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(Picker.Op(.pick).program(Cap, ctx, 41, struct {
            pub fn apply(_: i32) !i32 {
                return error.ContinueOops;
            }
        })) {
            return Picker.Op(.pick).program(Cap, ctx, 41, struct {
                pub fn apply(_: i32) !i32 {
                    return error.ContinueOops;
                }
            });
        }
    });
}
