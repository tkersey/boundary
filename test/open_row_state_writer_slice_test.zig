const shift = @import("shift");
const std = @import("std");

const WorkflowRow = shift.mergeRows(.{
    shift.effects.state(i32),
    shift.effects.writer([]const u8),
});

const workflow = struct {
    pub const Uses = shift.Uses(WorkflowRow);

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
