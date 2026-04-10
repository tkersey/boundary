const shift = @import("shift_vm");
const std = @import("std");

const WorkflowProgram = shift.Program(.{
    .state = shift.Decl.state(i32),
    .writer = shift.Decl.writer([]const u8),
}, struct {
    /// Run the state-writer slice through the public program surface.
    pub fn body(eff: anytype) ![]const u8 {
        const before = try eff.state.get();
        try eff.state.set(before + 1);
        try eff.writer.tell("queued");
        return "done";
    }
});

test "open-row state plus writer workflow yields the canonical result shape" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.run(&runtime, WorkflowProgram, .{ .state = 5 });
    defer std.testing.allocator.free(result.outputs.writer);

    try std.testing.expectEqual(@as(i32, 6), result.outputs.state);
    try std.testing.expectEqual(@as(usize, 1), result.outputs.writer.len);
    try std.testing.expectEqualStrings("queued", result.outputs.writer[0]);
    try std.testing.expectEqualStrings("done", result.value);
}

test "README minimal example yields the canonical result shape" {
    const ReadmeProgram = shift.Program(.{
        .state = shift.Decl.state(i32),
        .writer = shift.Decl.writer([]const u8),
    }, struct {
        /// Mirror the README workflow exactly so the documented front door stays compiled.
        pub fn body(eff: anytype) ![]const u8 {
            const before = try eff.state.get();
            try eff.state.set(before + 1);
            try eff.writer.tell("queued");
            return "done";
        }
    });

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.run(&runtime, ReadmeProgram, .{ .state = 5 });
    defer std.testing.allocator.free(result.outputs.writer);

    try std.testing.expectEqual(@as(i32, 6), result.outputs.state);
    try std.testing.expectEqual(@as(usize, 1), result.outputs.writer.len);
    try std.testing.expectEqualStrings("queued", result.outputs.writer[0]);
    try std.testing.expectEqualStrings("done", result.value);
}

test "shift.run omits outputs for stateless transform handlers" {
    const search_handler = struct {
        /// Return the canonical stateless search total.
        pub fn query(_: *@This(), payload: []const u8) i32 {
            return if (std.mem.eql(u8, payload, "artifact-search")) 3 else 0;
        }
    };
    const SearchDecl = shift.Decl.family(.{
        .state_type = struct {},
        .ops = .{
            shift.Op.Transform("query", []const u8, i32),
        },
    }, search_handler);
    const SearchProgram = shift.Program(.{
        .search = SearchDecl,
    }, struct {
        /// Trigger the stateless search op once through the public root surface.
        pub fn body(eff: anytype) anyerror!i32 {
            return try eff.search.query.perform("artifact-search");
        }
    });

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.run(&runtime, SearchProgram, .{
        .search = search_handler{},
    });

    try std.testing.expect(!@hasField(@TypeOf(result.outputs), "search"));
    try std.testing.expectEqual(@as(i32, 3), result.value);
}
