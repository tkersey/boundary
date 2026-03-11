const reference_eval = @import("reference_eval");
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
        "static_redelim\tStatic re-delimitation against control/prompt\n" ++
            "multi_prompt\tMulti-prompt separation\n" ++
            "generator\tGenerator\n" ++
            "early_exit\tEarly exit\n" ++
            "nested_workflow\tNested workflow\n",
        writer.buffered(),
    );
}

test "static redelim witness stays locked" {
    try expectWitness(
        "static_redelim",
        "outer-handler-enter\n" ++
            "after-outer-shift\n" ++
            "inner-handler\n" ++
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

test "hard witnesses agree with the reference evaluator" {
    const ids = [_][]const u8{ "static_redelim", "multi_prompt" };
    for (ids) |id| {
        const entry = semantic_manifest.find(id).?;
        var runtime_buffer: [1024]u8 = undefined;
        var runtime_writer = std.Io.Writer.fixed(&runtime_buffer);
        try witnesses.runWitness(&runtime_writer, id);

        var reference_buffer: [1024]u8 = undefined;
        var reference_writer = std.Io.Writer.fixed(&reference_buffer);
        try reference_eval.runWitness(&reference_writer, id);

        try std.testing.expectEqualStrings(entry.required_transcript, reference_writer.buffered());
        try std.testing.expectEqualStrings(entry.required_transcript, runtime_writer.buffered());
        try std.testing.expect(!std.mem.eql(u8, entry.forbidden_transcript.?, runtime_writer.buffered()));
        try std.testing.expect(!std.mem.eql(u8, entry.forbidden_transcript.?, reference_writer.buffered()));
    }
}

test "generator witness stays locked" {
    try expectWitness("generator", semantic_manifest.find("generator").?.required_transcript);
}

test "early-exit witness stays locked" {
    try expectWitness("early_exit", "result=early\n");
}

test "nested-workflow witness stays locked" {
    try expectWitness(
        "nested_workflow",
        "workflow=queued\n" ++
            "audit=entered\n" ++
            "audit=after\n" ++
            "approval=publish\n" ++
            "workflow=done\n" ++
            "result=completed\n",
    );
}
