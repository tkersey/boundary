// zlinter-disable declaration_naming require_doc_comment no_inferred_error_unions
const ability = @import("ability");
const std = @import("std");

const PlainHandlers = struct { base: i32 };
const PlainBody = struct {
    pub fn program(_: *ability.Runtime, handlers: PlainHandlers) !struct {
        value: i32,
        outputs: struct { total: i32 },
    } {
        return .{
            .value = handlers.base + 1,
            .outputs = .{ .total = handlers.base + 2 },
        };
    }
};

test "ability.program names and re-runs an explicit local body" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Program = ability.program("plain", PlainHandlers, PlainBody);
    var first = try Program.run(&runtime, .{ .base = 40 });
    defer first.deinit();
    try std.testing.expectEqual(@as(i32, 41), first.value);
    try std.testing.expectEqual(@as(i32, 42), first.outputs.total);

    var second = try Program.run(&runtime, .{ .base = 1 });
    defer second.deinit();
    try std.testing.expectEqual(@as(i32, 2), second.value);
    try std.testing.expectEqual(@as(i32, 3), second.outputs.total);
}

const StateHandlers = struct { initial: i32 };
const StateBody = struct {
    pub fn program(runtime: *ability.Runtime, handlers: StateHandlers) !struct {
        value: i32,
        outputs: struct { state: i32 },
    } {
        var instance = ability.effect.state.Instance(i32, error{}).init();
        const result = try ability.effect.state.handle(i32, runtime, &instance, handlers.initial, struct {
            pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(ability.effect.state.computeProgram(Cap, ctx, struct {
                pub fn run(comptime RunCap: type, run_ctx: anytype) !i32 {
                    const before = try ability.effect.state.get(RunCap, run_ctx);
                    try ability.effect.state.set(RunCap, run_ctx, before + 1);
                    const after = try ability.effect.state.get(RunCap, run_ctx);
                    return before + after;
                }
            })) {
                return ability.effect.state.computeProgram(Cap, ctx, struct {
                    pub fn run(comptime RunCap: type, run_ctx: anytype) !i32 {
                        const before = try ability.effect.state.get(RunCap, run_ctx);
                        try ability.effect.state.set(RunCap, run_ctx, before + 1);
                        const after = try ability.effect.state.get(RunCap, run_ctx);
                        return before + after;
                    }
                });
            }
        });
        return .{
            .value = result.value,
            .outputs = .{ .state = result.state },
        };
    }
};

test "ability.program composes with public effect handlers" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Program = ability.program("state", StateHandlers, StateBody);
    var result = try Program.run(&runtime, .{ .initial = 5 });
    defer result.deinit();

    try std.testing.expectEqual(@as(i32, 11), result.value);
    try std.testing.expectEqual(@as(i32, 6), result.outputs.state);
}
