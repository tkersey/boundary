const shift = @import("shift");
const std = @import("std");

test "prompt tokens remain zero-sized" {
    const spec_t = shift.ControlSpec(struct {
        /// Prompt marker for the size test family.
        pub const TagType = enum { token };
        /// Resume payload for the size test family.
        pub const ResumeValue = usize;
        /// Final answer for the size test family.
        pub const AnswerValue = usize;
        /// Operation payload for the size test family.
        pub const OperationValue = union(enum) {
            pause: void,
        };
    });

    try std.testing.expectEqual(@as(usize, 0), @sizeOf(spec_t.prompt_token));
}

test "continuation shells stay compact" {
    const spec_t = shift.ControlSpec(struct {
        /// Prompt marker for the continuation size test family.
        pub const TagType = enum { token };
        /// Resume payload for the continuation size test family.
        pub const ResumeValue = usize;
        /// Final answer for the continuation size test family.
        pub const AnswerValue = usize;
        /// Operation payload for the continuation size test family.
        pub const OperationValue = union(enum) {
            pause: void,
        };
    });

    const machine_t = struct {
        /// Suspend once so the continuation shell can be measured.
        pub fn step(_: *@This(), input: spec_t.ResumeInput) spec_t.StepResult {
            return switch (input) {
                .start => .{ .suspended = .{ .pause = {} } },
                .value => |value| .{ .done = value },
            };
        }
    };

    try std.testing.expect(@sizeOf(spec_t.Continuation(machine_t)) <= 5 * @sizeOf(usize));
    try std.testing.expect(@sizeOf(spec_t.ContinuationAlias(machine_t)) <= 5 * @sizeOf(usize));
}
