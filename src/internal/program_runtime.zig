const lowered_machine = @import("lowered_machine");
const std = @import("std");
const with_api = @import("../with_api.zig");

/// Return the public run result type.
pub fn RunReturnType(comptime HandlersType: type, comptime Body: type) type {
    return with_api.WithFnReturnType(HandlersType, Body);
}

/// Return the closed-root run result type for explicit handler bundles.
pub fn ClosedRunResultType(comptime HandlersType: type, comptime Answer: type) type {
    return with_api.ClosedRunResult(HandlersType, Answer);
}

/// Finalize one closed-root answer with explicit handler outputs.
pub fn finalizeClosedResult(handlers_ptr: anytype, value: anytype) with_api.ClosedRunResult(std.meta.Child(@TypeOf(handlers_ptr)), @TypeOf(value)) {
    return .{
        .outputs = with_api.collectClosedOutputs(handlers_ptr),
        .value = value,
    };
}

/// Run this public entrypoint.
pub fn run(
    runtime: *lowered_machine.Runtime,
    handlers: anytype,
    comptime Body: type,
) with_api.WithFnReturnType(@TypeOf(handlers), Body) {
    return with_api.with(runtime, handlers, Body);
}

test "finalizeClosedResult mirrors explicit handler outputs" {
    var handlers = .{
        .state = struct {
            value: i32,
            pub const Output = i32;

            pub fn finish(self: *@This()) i32 {
                return self.value;
            }
        }{ .value = 5 },
        .writer = struct {
            pub const Output = usize;
            value: usize = 2,

            pub fn finish(self: *@This()) usize {
                return self.value;
            }
        }{},
    };

    const result = finalizeClosedResult(&handlers, @as([]const u8, "done"));
    try @import("std").testing.expectEqual(@as(i32, 5), result.outputs.state);
    try @import("std").testing.expectEqual(@as(usize, 2), result.outputs.writer);
    try @import("std").testing.expectEqualStrings("done", result.value);
}
