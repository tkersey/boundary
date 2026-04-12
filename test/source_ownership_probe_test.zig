const probe = @import("source_ownership_probe_helper.zig");
const shift = @import("shift");
const shift_compile = @import("shift_compile");
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
    const src = shift_compile.lowering.sourceWithContent("test/source_ownership_probe_test.zig", @src(), @embedFile(@src().file));

    try std.testing.expectEqualStrings("test/source_ownership_probe_test.zig", src.repo_path);
    try std.testing.expectEqualStrings(std.fs.path.basename(@src().file), std.fs.path.basename(src.caller_file));
}

test "source helper stays callable from test modules" {
    const src = shift_compile.lowering.source("test/source_ownership_probe_test.zig", @src());

    try std.testing.expectEqualStrings("test/source_ownership_probe_test.zig", src.repo_path);
    try std.testing.expectEqualStrings(std.fs.path.basename(@src().file), std.fs.path.basename(src.caller_file));
}

test "public root drops compile entrypoints while shift_compile keeps provenance-bearing lowering" {
    try std.testing.expect(!@hasDecl(shift, "lowerAt"));
    try std.testing.expect(!@hasDecl(shift, "lower"));
    try std.testing.expect(!@hasDecl(shift, "lowering"));
    try std.testing.expect(!@hasDecl(shift, "compat"));
    try std.testing.expect(!@hasDecl(shift, "Decl"));
    try std.testing.expect(!@hasDecl(shift, "Op"));
    try std.testing.expect(!@hasDecl(shift, "Decision"));
    try std.testing.expect(!@hasDecl(shift, "Program"));
    try std.testing.expect(!@hasDecl(shift, "run"));
    try std.testing.expect(!@hasDecl(shift, "artifact"));
    try std.testing.expect(!@hasDecl(shift, "durable"));
    try std.testing.expect(!@hasDecl(shift, "interpreter"));
    try std.testing.expect(!@hasDecl(shift, "ir"));
    try std.testing.expect(@hasDecl(shift_compile, "lower"));
    try std.testing.expect(@hasDecl(shift_compile, "lowering"));
    try std.testing.expect(@hasDecl(shift_compile.lowering, "lowerAt"));
}
