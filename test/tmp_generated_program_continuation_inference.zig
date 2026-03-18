const std = @import("std");
const shift = @import("shift");

const Counter = shift.effect.Define(.{
    .state_type = i32,
    .ops = .{
        shift.effect.ops.Transform("get", void, i32),
    },
});

const handler = struct {
    state: i32 = 7,

    pub fn get(self: *@This()) i32 {
        return self.state;
    }

    pub fn afterGet(_: *@This(), answer: i32) i32 {
        return answer;
    }
};

test "generated family handle infers continuation errors in explicit program bodies" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = Counter.Instance.init();

    _ = Counter.handle(i32, &runtime, &instance, handler{}, struct {
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(Counter.Op(.get).program(Cap, ctx, struct {
            pub fn apply(_: i32) !i32 {
                return error.ContinueOops;
            }
        })) {
            return Counter.Op(.get).program(Cap, ctx, struct {
                pub fn apply(_: i32) !i32 {
                    return error.ContinueOops;
                }
            });
        }
    });
}
