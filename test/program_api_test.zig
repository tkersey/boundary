// zlinter-disable declaration_naming require_doc_comment no_inferred_error_unions
const ability = @import("ability");
const std = @import("std");

const PlainHandlers = struct { base: i32 };
const PlainBody = struct {
    pub fn program(_: *ability.Runtime, handlers: PlainHandlers) !struct {
        pub const ability_result_envelope = true;
        value: i32,
        outputs: struct { total: i32 },
    } {
        return .{
            .value = handlers.base + 1,
            .outputs = .{ .total = handlers.base + 2 },
        };
    }
};

const SentinelHandlers = struct { label: [:0]const u8 };
const SentinelBody = struct {
    pub fn program(_: *ability.Runtime, handlers: SentinelHandlers) !usize {
        return handlers.label.len;
    }
};

const EmptyHandlers = struct {};

const PlainStructValue = struct {
    value: i32,
    label: []const u8,
};

const PlainValueOutputs = struct {
    value: i32,
    outputs: i32,
};

const MarkedValueOutputsExtra = struct {
    pub const ability_result_envelope = true;
    value: i32,
    outputs: i32,
    trace_id: usize,
};

const PlainStructBody = struct {
    pub fn program(_: *ability.Runtime, _: EmptyHandlers) PlainStructValue {
        return .{
            .value = 7,
            .label = "seven",
        };
    }
};

const PlainValueOutputsBody = struct {
    pub fn program(_: *ability.Runtime, _: EmptyHandlers) PlainValueOutputs {
        return .{
            .value = 7,
            .outputs = 9,
        };
    }
};

const MarkedValueOutputsExtraBody = struct {
    pub fn program(_: *ability.Runtime, _: EmptyHandlers) MarkedValueOutputsExtra {
        return .{
            .value = 7,
            .outputs = 9,
            .trace_id = 11,
        };
    }
};

const RuntimeGuardBody = struct {
    pub fn program(runtime: *ability.Runtime, _: EmptyHandlers) !bool {
        try std.testing.expectError(error.RuntimeBusy, runtime.deinitChecked());
        return true;
    }
};

const WriterOutputsBody = struct {
    pub fn program(runtime: *ability.Runtime, _: EmptyHandlers) !struct {
        pub const ability_result_envelope = true;
        value: usize,
        outputs: []const []const u8,
    } {
        var instance = ability.effect.writer.Instance([]const u8, error{}).init();
        const result = try ability.effect.writer.handle([]const u8, usize, runtime, &instance, std.testing.allocator, struct {
            pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(ability.effect.writer.computeProgram(Cap, ctx, struct {
                pub fn run(comptime RunCap: type, run_ctx: anytype) !usize {
                    try ability.effect.writer.tell(RunCap, run_ctx, "a");
                    try ability.effect.writer.tell(RunCap, run_ctx, "b");
                    return 2;
                }
            })) {
                return ability.effect.writer.computeProgram(Cap, ctx, struct {
                    pub fn run(comptime RunCap: type, run_ctx: anytype) !usize {
                        try ability.effect.writer.tell(RunCap, run_ctx, "a");
                        try ability.effect.writer.tell(RunCap, run_ctx, "b");
                        return 2;
                    }
                });
            }
        });
        return .{ .value = result.value, .outputs = result.items };
    }

    pub fn deinitResult(allocator: std.mem.Allocator, _: usize, outputs: []const []const u8) void {
        allocator.free(outputs);
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

test "ability.program enters runtime execution for plain bodies" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Program = ability.program("runtime-guard", EmptyHandlers, RuntimeGuardBody);
    var result = try Program.run(&runtime, .{});
    defer result.deinit();
    try std.testing.expect(result.value);
}

test "ability.program deinit releases body-owned outputs through hook" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Program = ability.program("writer-outputs", EmptyHandlers, WriterOutputsBody);
    var result = try Program.run(&runtime, .{});
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.value);
    try std.testing.expectEqual(@as(usize, 2), result.outputs.len);
    try std.testing.expectEqualStrings("a", result.outputs[0]);
    try std.testing.expectEqualStrings("b", result.outputs[1]);
}

test "ability.program infers return type for sentinel slice handlers" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Program = ability.program("sentinel-handler", SentinelHandlers, SentinelBody);
    var result = try Program.run(&runtime, .{ .label = "hello" });
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 5), result.value);
}

test "ability.program preserves plain structs with value fields" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Program = ability.program("plain-struct-value", EmptyHandlers, PlainStructBody);
    var result = try Program.run(&runtime, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 7), result.value.value);
    try std.testing.expectEqualStrings("seven", result.value.label);
}

test "ability.program preserves unmarked value outputs structs as domain values" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Program = ability.program("plain-value-outputs", EmptyHandlers, PlainValueOutputsBody);
    var result = try Program.run(&runtime, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 7), result.value.value);
    try std.testing.expectEqual(@as(i32, 9), result.value.outputs);
    try std.testing.expectEqual({}, result.outputs);
}

test "ability.program honors marked value outputs envelopes with bookkeeping fields" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Program = ability.program("marked-value-outputs-extra", EmptyHandlers, MarkedValueOutputsExtraBody);
    var result = try Program.run(&runtime, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 7), result.value);
    try std.testing.expectEqual(@as(i32, 9), result.outputs);
}

test "ability.program rejects destroyed runtime before plain body execution" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    try runtime.deinitChecked();

    const Program = ability.program("destroyed-runtime", PlainHandlers, PlainBody);
    try std.testing.expectError(error.RuntimeDestroyed, Program.run(&runtime, .{ .base = 1 }));
}

const StateHandlers = struct { initial: i32 };
const StateBody = struct {
    pub fn program(runtime: *ability.Runtime, handlers: StateHandlers) !struct {
        pub const ability_result_envelope = true;
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
