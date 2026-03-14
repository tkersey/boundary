const std = @import("std");

/// Type-erased cleanup frame used to unwind bracketed resource handles.
pub const Frame = struct {
    previous: ?*Frame = null,
    cleanupFn: *const fn (*Frame) anyerror!void,
};

threadlocal var active_frame: ?*Frame = null;

/// Return the current cleanup stack marker.
pub fn checkpoint() ?*Frame {
    return active_frame;
}

/// Push one cleanup frame onto the active unwind stack.
pub fn push(frame: *Frame) void {
    frame.previous = active_frame;
    active_frame = frame;
}

/// Unwind cleanup frames until `marker` becomes the active frame again.
pub fn unwindTo(marker: ?*Frame) anyerror!void {
    var first_err: ?anyerror = null;
    while (active_frame != marker) {
        const frame = active_frame orelse {
            std.debug.panic("cleanup stack underflow", .{});
        };
        active_frame = frame.previous;
        frame.cleanupFn(frame) catch |err| {
            if (first_err == null) first_err = err;
        };
    }
    if (first_err) |err| return err;
}
