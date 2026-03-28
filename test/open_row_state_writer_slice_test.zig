const shift = @import("shift");
const std = @import("std");

const WorkflowRow = shift.mergeRows(.{
    shift.effects.state(i32),
    shift.effects.writer([]const u8),
});

const workflow = struct {
    /// Capability bundle for the state-writer slice test.
    pub const Uses = shift.Uses(WorkflowRow);

    /// Run the state-writer slice through the public open-row surface.
    pub fn run(_: type, eff: anytype) ![]const u8 {
        const before = try eff.state.get();
        try eff.state.set(before + 1);
        try eff.writer.tell("queued");
        return "done";
    }
};

test "open-row state plus writer workflow yields the canonical result shape" {
    const handlers = .{
        .state = shift.handlers.state(@as(i32, 5)),
        .writer = shift.handlers.writer([]const u8, std.testing.allocator),
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const closed = shift.bind(workflow, handlers);
    const result = try shift.run(&runtime, closed);
    defer std.testing.allocator.free(result.outputs.writer);

    try std.testing.expectEqual(@as(i32, 6), result.outputs.state);
    try std.testing.expectEqual(@as(usize, 1), result.outputs.writer.len);
    try std.testing.expectEqualStrings("queued", result.outputs.writer[0]);
    try std.testing.expectEqualStrings("done", result.value);
}

test "README minimal example yields the canonical result shape" {
    const WorkflowRow = shift.mergeRows(.{
        shift.effects.state(i32),
        shift.effects.writer([]const u8),
    });
    const workflow = struct {
        /// Capability bundle for the README minimal example regression.
        pub const Uses = shift.Uses(WorkflowRow);

        /// Mirror the README workflow exactly so the documented front door stays compiled.
        pub fn body(eff: anytype) ![]const u8 {
            const before = try eff.state.get();
            try eff.state.set(before + 1);
            try eff.writer.tell("queued");
            return "done";
        }
    };

    const closed = shift.bind(workflow, .{
        .state = shift.handlers.state(@as(i32, 5)),
        .writer = shift.handlers.writer([]const u8, std.testing.allocator),
    });

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.run(&runtime, closed);
    defer std.testing.allocator.free(result.outputs.writer);

    try std.testing.expectEqual(@as(i32, 6), result.outputs.state);
    try std.testing.expectEqual(@as(usize, 1), result.outputs.writer.len);
    try std.testing.expectEqualStrings("queued", result.outputs.writer[0]);
    try std.testing.expectEqualStrings("done", result.value);
}

test "shift.run omits outputs for stateless transform handlers" {
    const SearchRow = shift.Row(.{
        .search = .{
            .query = shift.Transform([]const u8, i32),
        },
    });
    const workflow = struct {
        /// Capability bundle for the public stateless-transform regression.
        pub const Uses = shift.Uses(SearchRow);

        /// Trigger the stateless search op once through the public root surface.
        pub fn body(eff: anytype) anyerror!i32 {
            return try eff.search.query.perform("artifact-search");
        }
    };
    const search_handler = struct {
        /// Return the canonical stateless search total.
        pub fn query(_: *@This(), payload: []const u8) i32 {
            return if (std.mem.eql(u8, payload, "artifact-search")) 3 else 0;
        }
    };

    const closed = shift.bind(workflow, .{
        .search = search_handler{},
    });

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try shift.run(&runtime, closed);

    try std.testing.expect(!@hasField(@TypeOf(result.outputs), "search"));
    try std.testing.expectEqual(@as(i32, 3), result.value);
}
