const probe = @import("source_ownership_probe_helper.zig");
const shift = @import("shift");
const shift_compile = @import("shift_compile");
const std = @import("std");

fn writeTmpFile(dir: std.Io.Dir, sub_path: []const u8, contents: []const u8) !void {
    try dir.writeFile(std.testing.io, .{
        .sub_path = sub_path,
        .data = contents,
        .flags = .{ .truncate = true },
    });
}

fn runChildAtPathExpectFailureContaining(
    cwd_path: []const u8,
    argv: []const []const u8,
    expected_stderr: []const u8,
) !void {
    const result = try std.process.run(std.testing.allocator, std.testing.io, .{
        .argv = argv,
        .cwd = .{ .path = cwd_path },
        .stderr_limit = .limited(1024 * 1024),
        .stdout_limit = .limited(1024 * 1024),
    });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| if (code != 0 and std.mem.find(u8, result.stderr, expected_stderr) != null) return,
        else => {},
    }
    std.debug.print("child command did not fail with expected stderr: {s}\n{s}\n", .{ argv[0], result.stderr });
    return error.UnexpectedChildCommandFailure;
}

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
    try std.testing.expect(!@hasDecl(shift, "debug_anonymous_body_synthesis"));
    try std.testing.expect(!@hasDecl(shift, "interpreter"));
    try std.testing.expect(!@hasDecl(shift, "ir"));
    try std.testing.expect(!@hasDecl(shift, "lowering"));
    try std.testing.expect(@hasDecl(shift_compile, "lower"));
    try std.testing.expect(@hasDecl(shift_compile, "effect_ir"));
    try std.testing.expect(@hasDecl(shift_compile, "lowering_api"));
    try std.testing.expect(@hasDecl(shift_compile.lowering_api, "lowerAt"));
}

test "plain shift.with anonymous downstream bodies fail closed without caller-owned source" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const consumer_root = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(consumer_root);

    const build_zig =
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\    const dep = b.dependency("shift", .{ .target = target, .optimize = optimize });
        \\
        \\    const root = b.createModule(.{
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\    root.addImport("shift", dep.module("shift"));
        \\
        \\    const exe = b.addExecutable(.{
        \\        .name = "downstream-shift-with",
        \\        .root_module = root,
        \\    });
        \\    const run = b.addRunArtifact(exe);
        \\    b.default_step.dependOn(&run.step);
        \\}
        \\
    ;
    try writeTmpFile(tmp.dir, "build.zig", build_zig);

    const build_zon =
        \\.{
        \\    .name = .downstream_shift_with,
        \\    .version = "0.0.0",
        \\    .minimum_zig_version = "0.16.0",
        \\    .dependencies = .{
        \\        .shift = .{ .path = "../../.." },
        \\    },
        \\    .paths = .{ "build.zig", "build.zig.zon", "main.zig" },
        \\    .fingerprint = 0xf5798bf9dbefd4d5,
        \\}
        \\
    ;
    try writeTmpFile(tmp.dir, "build.zig.zon", build_zon);

    const main_zig =
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\
        \\    const result = try shift.with(&runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 9)),
        \\    }, struct {
        \\        pub fn body(eff: anytype) anyerror!i32 {
        \\            return try eff.state.get();
        \\        }
        \\    });
        \\    if (result.value != 9) return error.UnexpectedValue;
        \\}
        \\
    ;
    try writeTmpFile(tmp.dir, "main.zig", main_zig);

    try runChildAtPathExpectFailureContaining(
        consumer_root,
        &.{
            "zig",
            "build",
            "--summary",
            "none",
            "--cache-dir",
            ".zig-cache",
            "--global-cache-dir",
            "zig-global-cache",
        },
        "shift.with requires a repo-owned body candidate for compiled execution",
    );
}
