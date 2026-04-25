const ability = @import("ability");
const std = @import("std");

test "open-row state plus writer workflow yields the canonical result shape" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try ability.with(&runtime, .{
        .state = ability.effect.state.use(@as(i32, 5)),
        .writer = ability.effect.writer.use([]const u8, std.testing.allocator),
    }, struct {
        /// Run the state-writer slice through the lexical public surface.
        pub fn body(eff: anytype) ![]const u8 {
            const before = try eff.state.get();
            try eff.state.set(before + 1);
            try eff.writer.tell("queued");
            return "done";
        }
    });
    defer std.testing.allocator.free(result.outputs.writer);

    try std.testing.expectEqual(@as(i32, 6), result.outputs.state);
    try std.testing.expectEqual(@as(usize, 1), result.outputs.writer.len);
    try std.testing.expectEqualStrings("queued", result.outputs.writer[0]);
    try std.testing.expectEqualStrings("done", result.value);
}

test "README minimal example yields the canonical result shape" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try ability.with(&runtime, .{
        .state = ability.effect.state.use(@as(i32, 5)),
        .writer = ability.effect.writer.use([]const u8, std.testing.allocator),
    }, struct {
        /// Mirror the README workflow exactly so the documented front door stays compiled.
        pub fn body(eff: anytype) ![]const u8 {
            const before = try eff.state.get();
            try eff.state.set(before + 1);
            try eff.writer.tell("queued");
            return "done";
        }
    });
    defer std.testing.allocator.free(result.outputs.writer);

    try std.testing.expectEqual(@as(i32, 6), result.outputs.state);
    try std.testing.expectEqual(@as(usize, 1), result.outputs.writer.len);
    try std.testing.expectEqualStrings("queued", result.outputs.writer[0]);
    try std.testing.expectEqualStrings("done", result.value);
}

test "ability.with omits outputs for stateless transform handlers" {
    const Search = ability.effect.Define(.{
        .state_type = struct {},
        .ops = .{
            ability.effect.ops.Transform("query", []const u8, i32),
        },
    });
    const search_handler = struct {
        /// Return the canonical stateless search total.
        pub fn query(_: *@This(), payload: []const u8) i32 {
            return if (std.mem.eql(u8, payload, "artifact-search")) 3 else 0;
        }
    };

    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try ability.with(&runtime, .{
        .search = Search.use(.{ .handler = search_handler{} }),
    }, struct {
        /// Trigger the stateless search op once through the public root surface.
        pub fn body(eff: anytype) anyerror!i32 {
            return try eff.search.query.perform("artifact-search");
        }
    });

    try std.testing.expect(!@hasField(@TypeOf(result.outputs), "search"));
    try std.testing.expectEqual(@as(i32, 3), result.value);
}
