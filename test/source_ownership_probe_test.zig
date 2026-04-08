const probe = @import("source_ownership_probe_helper.zig");
const shift = @import("shift");
const std = @import("std");

test "wrapper-local source capture stays callee-owned across realistic zero-argument wrapper forms" {
    const caller_source = @src().file;
    const helper_source = probe.helperSourceFile();

    try std.testing.expectEqualStrings(helper_source, probe.directWrapperSourceFile());
    try std.testing.expectEqualStrings(helper_source, probe.inlineWrapperSourceFile());
    try std.testing.expectEqualStrings(helper_source, probe.namespacedWrapperSourceFile());

    try std.testing.expect(!std.mem.eql(u8, caller_source, probe.directWrapperSourceFile()));
    try std.testing.expect(!std.mem.eql(u8, caller_source, probe.inlineWrapperSourceFile()));
    try std.testing.expect(!std.mem.eql(u8, caller_source, probe.namespacedWrapperSourceFile()));
}

test "only explicit caller participation preserves truthful source ownership across modules" {
    try std.testing.expectEqualStrings(@src().file, probe.explicitCallerSourceFile(@src()));
}

test "source helper captures explicit repo path plus caller-owned participation" {
    const src = shift.lowering.sourceWithContent("test/source_ownership_probe_test.zig", @src(), @embedFile(@src().file));

    try std.testing.expectEqualStrings("test/source_ownership_probe_test.zig", src.repo_path);
    try std.testing.expectEqualStrings(std.fs.path.basename(@src().file), std.fs.path.basename(src.caller_file));
}

test "source helper stays callable from test modules" {
    const src = shift.lowering.source("test/source_ownership_probe_test.zig", @src());

    try std.testing.expectEqualStrings("test/source_ownership_probe_test.zig", src.repo_path);
    try std.testing.expectEqualStrings(std.fs.path.basename(@src().file), std.fs.path.basename(src.caller_file));
}

test "public root keeps provenance-bearing shift.lower while path-based lowering stays namespaced" {
    try std.testing.expect(!@hasDecl(shift, "lowerAt"));
    try std.testing.expect(@hasDecl(shift, "lower"));
    try std.testing.expect(@hasDecl(shift.lowering, "lowerAt"));
}
