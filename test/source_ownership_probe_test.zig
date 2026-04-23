const probe = @import("source_ownership_probe_helper.zig");
const shift = @import("shift");
const shift_compile = @import("shift_compile");
const std = @import("std");

fn callerSourceIsAbsent(comptime ContextType: type) bool {
    const caller_source = ContextType.caller_source;
    return switch (@typeInfo(@TypeOf(caller_source))) {
        .optional => caller_source == null,
        .null => true,
        else => false,
    };
}

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

test "source-compatible wrappers leave caller provenance absent by default" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    {
        const NoError = error{};

        var reader_instance = shift.effect.reader.Instance(i32, NoError).init();
        const reader_result = try shift.effect.reader.handleWithErrorSet([]const u8, NoError, &runtime, &reader_instance, @as(i32, 21), struct {
            /// Report whether the default reader wrapper leaves caller provenance absent.
            pub fn body(comptime Cap: type, ctx: anytype) NoError![]const u8 {
                _ = Cap;
                return if (callerSourceIsAbsent(@TypeOf(ctx.*))) "absent" else "present";
            }
        });
        try std.testing.expectEqualStrings("absent", reader_result);

        const Audit = shift.effect.Define(.{
            .state_type = void,
            .ops = .{
                shift.effect.ops.Transform("note", []const u8, void),
            },
        });
        var generated_instance = Audit.Instance.init();
        const generated_result = try Audit.handleWithErrorSet([]const u8, NoError, &runtime, &generated_instance, struct {
            /// Accept the generated probe payload without mutating any state.
            pub fn note(_: *@This(), _: []const u8) void {
                // No-op probe handler.
            }
        }{}, struct {
            /// Report whether the default generated wrapper leaves caller provenance absent.
            pub fn body(comptime Cap: type, ctx: anytype) NoError![]const u8 {
                _ = Cap;
                return if (callerSourceIsAbsent(@TypeOf(ctx.*))) "absent" else "present";
            }
        });
        try std.testing.expectEqualStrings("absent", generated_result.value);
    }
}

test "source helper captures explicit repo path plus caller-owned participation" {
    const src = shift_compile.lowering_api.sourceWithContent("test/source_ownership_probe_test.zig", @src(), @embedFile(@src().file));

    try std.testing.expectEqualStrings("test/source_ownership_probe_test.zig", src.repo_path);
    try std.testing.expectEqualStrings(std.Io.Dir.path.basename(@src().file), std.Io.Dir.path.basename(src.caller_file));
}

test "source helper stays callable from test modules" {
    const src = shift_compile.lowering_api.source("test/source_ownership_probe_test.zig", @src());

    try std.testing.expectEqualStrings("test/source_ownership_probe_test.zig", src.repo_path);
    try std.testing.expectEqualStrings(std.Io.Dir.path.basename(@src().file), std.Io.Dir.path.basename(src.caller_file));
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
    try std.testing.expect(!@hasDecl(shift, "lowering"));
    try std.testing.expect(@hasDecl(shift_compile, "lower"));
    try std.testing.expect(@hasDecl(shift_compile, "effect_ir"));
    try std.testing.expect(@hasDecl(shift_compile, "lowering_api"));
    try std.testing.expect(@hasDecl(shift_compile.lowering_api, "lowerAt"));
}
