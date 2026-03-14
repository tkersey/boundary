const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const fake_cap = struct {};
const fake_value: fake_cap = .{};

const FakeWriterState = struct {
    allocator: std.mem.Allocator = std.heap.page_allocator,
    items: std.ArrayList([]const u8) = .empty,
};

const FakeContext = struct {
    /// Fake capability metadata that mimics the real context shape.
    pub const capability = fake_cap;
    /// Fake writer-state metadata that mimics the real context shape.
    pub const StateType = FakeWriterState;
    /// Fake answer metadata that mimics the real context shape.
    pub const AnswerType = []const u8;
    /// Fake error-set metadata that mimics the real context shape.
    pub const ErrorSetType = NoError;

    _cap: *const fake_cap = &fake_value,
};

/// Attempt to pass a forged writer context-shaped struct to the API.
pub fn main() anyerror!void {
    var ctx = FakeContext{};
    try shift.effect.writer.tell(fake_cap, &ctx, "bad");
}
