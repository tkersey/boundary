const registry = @import("control_lab_registry");
const scenarios = @import("control_lab_scenarios");
const std = @import("std");

test "registry ids stay unique" {
    for (registry.witnesses, 0..) |left, left_index| {
        for (registry.witnesses[left_index + 1 ..]) |right| {
            try std.testing.expect(!std.mem.eql(u8, left.witness_id, right.witness_id));
        }
    }
}

test "control studio list stays stable" {
    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try scenarios.listWitnesses(&writer);

    try std.testing.expectEqualStrings(
        "pending_loop\tpending-owner\tOrdinary pending loop\n" ++
            "terminal_cancel\tpending-owner\tTerminal cancellation\n" ++
            "driver_discontinue\tadditive-driver\tAdditive driver discontinue\n" ++
            "escape_redelimit\tescaped-owner\tEscaped owner re-delimits resumed work\n",
        writer.buffered(),
    );
}

test "every witness transcript stays locked" {
    for (registry.witnesses) |witness| {
        var buffer: [512]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buffer);
        try scenarios.runWitness(&writer, witness.witness_id);
        try std.testing.expectEqualStrings(witness.expected_transcript, writer.buffered());
    }
}

test "docs cover every witness anchor" {
    const doc = try std.fs.cwd().readFileAlloc(std.testing.allocator, "docs/control_lab.md", 32 * 1024);
    defer std.testing.allocator.free(doc);
    for (registry.witnesses) |witness| {
        const anchor_id = if (std.mem.startsWith(u8, witness.docs_anchor, "#")) witness.docs_anchor[1..] else witness.docs_anchor;
        var needle_buffer: [64]u8 = undefined;
        const needle = try std.fmt.bufPrint(&needle_buffer, "id=\"{s}\"", .{anchor_id});
        try std.testing.expect(std.mem.indexOf(u8, doc, needle) != null);
    }
}
