const ability = @import("ability");
const ability_compile = @import("ability_compile");
const probe = @import("source_ownership_probe_helper.zig");
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
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const NoError = error{};

    var reader_instance = ability.effect.reader.Instance(i32, NoError).init();
    const reader_result = try ability.effect.reader.handleWithErrorSet([]const u8, NoError, &runtime, &reader_instance, @as(i32, 21), struct {
        /// Report whether the default reader wrapper leaves caller provenance absent.
        pub fn body(comptime Cap: type, ctx: anytype) NoError![]const u8 {
            _ = Cap;
            return if (callerSourceIsAbsent(@TypeOf(ctx.*))) "absent" else "present";
        }
    });
    try std.testing.expectEqualStrings("absent", reader_result);

    const Audit = ability.effect.Define(.{
        .state_type = void,
        .ops = .{
            ability.effect.ops.Transform("note", []const u8, void),
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

test "source helper captures explicit repo path plus caller-owned participation" {
    const src = ability_compile.lowering_api.sourceWithContent(
        "test/source_ownership_probe_test.zig",
        @src(),
        @embedFile(std.Io.Dir.path.basename(@src().file)),
    );

    try std.testing.expectEqualStrings("test/source_ownership_probe_test.zig", src.repo_path);
    try std.testing.expectEqualStrings(std.Io.Dir.path.basename(@src().file), std.Io.Dir.path.basename(src.caller_file));
}

test "source helper stays callable from test modules" {
    const src = ability_compile.lowering_api.source("test/source_ownership_probe_test.zig", @src());

    try std.testing.expectEqualStrings("test/source_ownership_probe_test.zig", src.repo_path);
    try std.testing.expectEqualStrings(std.Io.Dir.path.basename(@src().file), std.Io.Dir.path.basename(src.caller_file));
}

test "public root drops compile entrypoints while ability_compile keeps provenance-bearing lowering" {
    const expected_root_decl_names = [_][]const u8{
        "Runtime",
        "RuntimeError",
        "effect",
        "sourceHash",
        "with",
    };
    const root_decls = @typeInfo(ability).@"struct".decls;

    try std.testing.expectEqual(expected_root_decl_names.len, root_decls.len);
    inline for (expected_root_decl_names) |name| {
        try std.testing.expect(@hasDecl(ability, name));
    }
    inline for (root_decls) |decl| {
        var allowed = false;
        inline for (expected_root_decl_names) |name| {
            if (std.mem.eql(u8, decl.name, name)) allowed = true;
        }
        try std.testing.expect(allowed);
    }

    try std.testing.expect(!@hasDecl(ability, "lowerAt"));
    try std.testing.expect(!@hasDecl(ability, "lower"));
    try std.testing.expect(!@hasDecl(ability, "lowering"));
    try std.testing.expect(!@hasDecl(ability, "compat"));
    try std.testing.expect(!@hasDecl(ability, "Decl"));
    try std.testing.expect(!@hasDecl(ability, "Op"));
    try std.testing.expect(!@hasDecl(ability, "Decision"));
    try std.testing.expect(!@hasDecl(ability, "Program"));
    try std.testing.expect(!@hasDecl(ability, "run"));
    try std.testing.expect(!@hasDecl(ability, "artifact"));
    try std.testing.expect(!@hasDecl(ability, "durable"));
    try std.testing.expect(!@hasDecl(ability, "debug_anonymous_body_synthesis"));
    try std.testing.expect(!@hasDecl(ability, "interpreter"));
    try std.testing.expect(!@hasDecl(ability, "ir"));
    try std.testing.expect(!@hasDecl(ability, "lowering"));
    try std.testing.expect(!@hasDecl(ability, "with" ++ "Caller" ++ "Source"));
    try std.testing.expect(@hasDecl(ability_compile, "lower"));
    try std.testing.expect(@hasDecl(ability_compile, "effect_ir"));
    try std.testing.expect(@hasDecl(ability_compile, "lowering_api"));
    try std.testing.expect(@hasDecl(ability_compile.lowering_api, "lowerAt"));
}

const fast_source_backed_body = struct {
    fn sourceLocation() std.builtin.SourceLocation {
        return @src();
    }

    /// In-process equivalent of the former downstream source-backed named body.
    pub const source = @embedFile("source_ownership_probe_test.zig");
    /// Hash witness for the owner source bytes.
    pub const source_hash = ability.sourceHash(source);
    /// File witness for this declaration.
    pub const source_file = "source_ownership_probe_test.zig";
    /// Location witness from inside this declaration.
    pub const source_location = sourceLocation();
    /// Stable named-body identity witness for the selected top-level declaration.
    pub const source_identity = "source_ownership_probe_test.fast_source_backed_body";

    /// Body used to prove the source-backed public entrypoint still runs.
    pub fn body(eff: anytype) anyerror!i32 {
        const before = try eff.state.get();
        try eff.state.set(before + 1);
        return try eff.state.get();
    }
};

test "ability.with admits one fast source-backed named body witness" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const result = try ability.with(&runtime, .{
        .state = ability.effect.state.use(@as(i32, 9)),
    }, fast_source_backed_body);

    try std.testing.expectEqual(@as(i32, 10), result.value);
    try std.testing.expectEqual(@as(i32, 10), result.outputs.state);
}
