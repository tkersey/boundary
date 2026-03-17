const parity_scenarios = @import("parity_scenarios");
const runners = @import("lexical_witness_support.zig");
const std = @import("std");

fn expectLexicalWitness(comptime witness_id: []const u8, runner: anytype) !void {
    const expected = parity_scenarios.findWitness(witness_id).?.expected_transcript;
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try runner(&writer);
    try std.testing.expectEqualStrings(expected, writer.buffered());
}

test "lexical witness transcripts stay aligned with the admitted parity subset" {
    try expectLexicalWitness("atm_resume_transform", runners.runAtmResumeTransform);
    try expectLexicalWitness("direct_return", runners.runDirectReturn);
    try expectLexicalWitness("multi_prompt", runners.runMultiPrompt);
    try expectLexicalWitness("resume_or_return_return_now", runners.runResumeOrReturnReturnNow);
    try expectLexicalWitness("resume_or_return_resume", runners.runResumeOrReturnResume);
    try expectLexicalWitness("static_redelim", runners.runStaticRedelim);
    try expectLexicalWitness("generator", runners.runGenerator);
}
