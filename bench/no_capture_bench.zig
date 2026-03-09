const shift = @import("shift");
const std = @import("std");

const NoCaptureSpec = shift.ControlSpec(struct {
    /// Prompt marker for the no-capture benchmark family.
    pub const TagType = enum { token };
    /// Resume payload for the no-capture benchmark family.
    pub const ResumeValue = void;
    /// Final answer for the no-capture benchmark family.
    pub const AnswerValue = usize;
    /// Operation payload for the no-capture benchmark family.
    pub const OperationValue = union(enum) {
        impossible: void,
    };
});

const Machine = struct {
    value: usize = 1,

    /// Complete without suspension to exercise the zero-allocation fast path.
    pub fn step(self: *@This(), input: NoCaptureSpec.ResumeInput) NoCaptureSpec.StepResult {
        return switch (input) {
            .start => .{ .done = self.value },
            .value => unreachable,
        };
    }
};

const CountingAllocator = struct {
    child: std.mem.Allocator,
    alloc_calls: u64 = 0,

    /// Wrap an allocator so allocation calls can be counted.
    pub fn init(child: std.mem.Allocator) CountingAllocator {
        return .{ .child = child };
    }

    /// Expose the counting allocator interface.
    pub fn allocator(self: *CountingAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.alloc_calls += 1;
        return self.child.rawAlloc(len, alignment, ret_addr);
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        return self.child.rawResize(memory, alignment, new_len, ret_addr);
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        return self.child.rawRemap(memory, alignment, new_len, ret_addr);
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.child.rawFree(memory, alignment, ret_addr);
    }
};

fn cleanupSession(session: *shift.raw.Session) void {
    session.close(.cancel) catch |err| switch (err) {
        error.SessionClosed => {},
        else => unreachable,
    };
    session.destroy() catch |err| switch (err) {
        error.SessionBusy, error.SessionOpen => {},
        else => unreachable,
    };
}

/// Run the no-capture benchmark.
pub fn main() anyerror!void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();

    var counting = CountingAllocator.init(gpa.allocator());
    const session = try shift.raw.Session.create(counting.allocator());
    var destroyed = false;
    defer if (!destroyed) cleanupSession(session);
    counting.alloc_calls = 0;

    const iterations: usize = 50_000;
    var timer = try std.time.Timer.start();
    var sum: usize = 0;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const state = try NoCaptureSpec.start(Machine, session, .{ .value = i });
        switch (state) {
            .done => |answer| sum += answer,
            .suspended => unreachable,
        }
    }

    const elapsed = timer.read();
    try session.close(.graceful);
    try session.destroy();
    destroyed = true;
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print(
        "iterations={d} ns={d} alloc_calls={d} checksum={d}\n",
        .{ iterations, elapsed, counting.alloc_calls, sum },
    );
    try stdout.flush();
}
