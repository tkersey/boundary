const reference_eval = @import("reference_eval");
const reference_machine = @import("reference_machine");
const semantic_manifest = @import("semantic_manifest.zig");
const std = @import("std");
const witnesses = @import("witnesses");

fn expectWitness(id: []const u8, expected: []const u8) !void {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try witnesses.runWitness(&writer, id);
    try std.testing.expectEqualStrings(expected, writer.buffered());
}

test "witness list stays stable" {
    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try witnesses.listWitnesses(&writer);
    try std.testing.expectEqualStrings(
        "atm_resume_transform\tATM resume-then-transform\n" ++
            "direct_return\tDirect return without continuation exposure\n" ++
            "static_redelim\tStatic re-delimitation against control/prompt\n" ++
            "multi_prompt\tPrompt-value separation\n" ++
            "generator\tGenerator\n",
        writer.buffered(),
    );
}

test "direct return witness stays locked" {
    try expectWitness(
        "direct_return",
        "handler-direct-return\n" ++
            "final=result=early\n",
    );
}

test "atm resume transform witness stays locked" {
    try expectWitness(
        "atm_resume_transform",
        "handler-enter\n" ++
            "body-after-shift\n" ++
            "handler-after-resume\n" ++
            "final=answer=42\n",
    );
}

test "static redelim witness stays locked" {
    try expectWitness(
        "static_redelim",
        "outer-handler-enter\n" ++
            "after-outer-shift\n" ++
            "inner-handler-enter\n" ++
            "after-inner-shift\n" ++
            "inner-handler-exit\n" ++
            "outer-handler-exit\n" ++
            "final=12\n",
    );
}

test "multi-prompt witness stays locked" {
    try expectWitness(
        "multi_prompt",
        "outer-before-inner\n" ++
            "inner-before\n" ++
            "outer-handler\n" ++
            "inner-after\n" ++
            "outer-after-inner\n" ++
            "final=42\n",
    );
}

test "hard witnesses agree across evaluator, reference machine, and runtime" {
    const ids = [_][]const u8{ "atm_resume_transform", "direct_return", "static_redelim", "multi_prompt" };
    for (ids) |id| {
        const entry = semantic_manifest.find(id).?;
        var runtime_buffer: [1024]u8 = undefined;
        var runtime_writer = std.Io.Writer.fixed(&runtime_buffer);
        try witnesses.runWitness(&runtime_writer, id);

        var reference_buffer: [1024]u8 = undefined;
        var reference_writer = std.Io.Writer.fixed(&reference_buffer);
        try reference_eval.runWitness(&reference_writer, id);

        var machine_buffer: [1024]u8 = undefined;
        var machine_writer = std.Io.Writer.fixed(&machine_buffer);
        try reference_machine.runWitness(&machine_writer, id);

        try std.testing.expectEqualStrings(entry.required_transcript, reference_writer.buffered());
        try std.testing.expectEqualStrings(entry.required_transcript, machine_writer.buffered());
        try std.testing.expectEqualStrings(entry.required_transcript, runtime_writer.buffered());
        try std.testing.expect(!std.mem.eql(u8, entry.forbidden_transcript.?, runtime_writer.buffered()));
        try std.testing.expect(!std.mem.eql(u8, entry.forbidden_transcript.?, reference_writer.buffered()));
        try std.testing.expect(!std.mem.eql(u8, entry.forbidden_transcript.?, machine_writer.buffered()));
    }
}

test "generator witness stays locked" {
    try expectWitness("generator", semantic_manifest.find("generator").?.required_transcript);
}

test "practical witness scope stays generator-only" {
    try std.testing.expectEqual(@as(usize, 5), witnesses.witnesses.len);
    try std.testing.expect(semantic_manifest.find("early_exit") == null);
    try std.testing.expect(semantic_manifest.find("nested_workflow") == null);
}
