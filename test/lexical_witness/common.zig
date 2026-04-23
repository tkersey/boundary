const parity_scenarios = @import("parity_scenarios");
pub const lexical_runtime = @import("shift");
pub const std = @import("std");

pub const ResumeWitness = lexical_runtime.effect.Define(.{
    .state_type = void,
    .ops = .{
        lexical_runtime.effect.ops.Transform("step", void, i32),
    },
});

pub fn printTranscript(writer: anytype, lines: []const []const u8) anyerror!void {
    for (lines) |line| try writer.print("{s}\n", .{line});
}

pub fn expectLexicalWitness(comptime witness_id: []const u8, runner: anytype) !void {
    const expected = parity_scenarios.findWitness(witness_id).?.expected_transcript;
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try runner(&writer);
    try std.testing.expectEqualStrings(expected, writer.buffered());
}
