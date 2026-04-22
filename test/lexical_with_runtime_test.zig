// zlinter-disable require_doc_comment - this runtime witness file exposes public nested handlers and continuations to exercise comptime-facing lexical runtime seams.
const shift = @import("shift");
const std = @import("std");

fn ExecResult(comptime T: type) type {
    return (shift.RuntimeError || error{ OutOfMemory, BodyOops, ContinueOops, HandlerOops, AfterOops })!T;
}

test "shift.with composes state and reader through lexical handles" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .state = shift.effect.state.use(@as(i32, 5)),
        .reader = shift.effect.reader.use(@as(i32, 21)),
    }, struct {
        pub fn body(eff: anytype) ExecResult(i32) {
            const env = try eff.reader.ask();
            const before = try eff.state.get();
            try eff.state.set(before + env);
            return try eff.state.get();
        }
    });

    try std.testing.expectEqual(@as(i32, 26), result.value);
    try std.testing.expectEqual(@as(i32, 26), result.outputs.state);
}

test "generated choice families use the lexical choice form" {
    const Picker = shift.effect.Define(.{
        .state_type = struct {},
        .ops = .{
            shift.effect.ops.Choice("pick", i32, i32),
        },
    });

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const early = try shift.with(&runtime, .{
        .picker = Picker.use(.{ .handler = struct {
            pub fn pick(_: *@This(), _: i32) shift.effect.choice.Decision(i32, []const u8) {
                return shift.effect.choice.Decision(i32, []const u8).returnNow("result=early");
            }

            pub fn afterPick(_: *@This(), answer: []const u8) []const u8 {
                return answer;
            }
        }{} }),
    }, struct {
        pub fn body(eff: anytype) ExecResult([]const u8) {
            return try eff.picker.pick.perform(41, struct {
                pub fn apply(_: i32, _: anytype) ExecResult([]const u8) {
                    unreachable;
                }
            });
        }
    });
    try std.testing.expectEqualStrings("result=early", early.value);

    const resumed = try shift.with(&runtime, .{
        .picker = Picker.use(.{ .handler = struct {
            pub fn pick(_: *@This(), payload: i32) shift.effect.choice.Decision(i32, []const u8) {
                return shift.effect.choice.Decision(i32, []const u8).resumeWith(payload);
            }

            pub fn afterPick(_: *@This(), answer: []const u8) []const u8 {
                return answer;
            }
        }{} }),
    }, struct {
        pub fn body(eff: anytype) ExecResult([]const u8) {
            return try eff.picker.pick.perform(41, struct {
                pub fn apply(value: i32, _: anytype) ExecResult([]const u8) {
                    if (value != 41) unreachable;
                    return "answer=42";
                }
            });
        }
    });
    try std.testing.expectEqualStrings("answer=42", resumed.value);
}

test "generated abort families use the lexical abort form" {
    const Guard = shift.effect.Define(.{
        .state_type = struct {},
        .ops = .{
            shift.effect.ops.Abort("fail", []const u8),
        },
    });

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .guard = Guard.use(.{ .handler = struct {
            pub fn fail(_: *@This(), payload: []const u8) []const u8 {
                if (!std.mem.eql(u8, payload, "missing-name")) unreachable;
                return "error=missing-name";
            }
        }{} }),
    }, struct {
        pub fn body(eff: anytype) ExecResult([]const u8) {
            try eff.guard.fail.abort("missing-name");
        }
    });

    try std.testing.expectEqualStrings("error=missing-name", result.value);
}

test "generated zero-payload choice fields stay ergonomic" {
    const Ask = shift.effect.Define(.{
        .state_type = struct {},
        .ops = .{
            shift.effect.ops.Choice("ask", void, i32),
        },
    });

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.with(&runtime, .{
        .asker = Ask.use(.{ .handler = struct {
            pub fn ask(_: *@This()) shift.effect.choice.Decision(i32, []const u8) {
                return shift.effect.choice.Decision(i32, []const u8).resumeWith(7);
            }

            pub fn afterAsk(_: *@This(), answer: []const u8) []const u8 {
                return answer;
            }
        }{} }),
    }, struct {
        pub fn body(eff: anytype) ExecResult([]const u8) {
            return try eff.asker.ask.perform(struct {
                pub fn apply(value: i32, _: anytype) ExecResult([]const u8) {
                    if (value != 7) unreachable;
                    return "answer=7";
                }
            });
        }
    });

    try std.testing.expectEqualStrings("answer=7", result.value);
}
