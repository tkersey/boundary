const ability = @import("ability");
const ability_compile = @import("ability_compile");
const probe = @import("source_ownership_probe_helper.zig");
const std = @import("std");

fn writeTmpFile(dir: std.Io.Dir, sub_path: []const u8, contents: []const u8) !void {
    if (std.Io.Dir.path.dirname(sub_path)) |dir_path| {
        try dir.createDirPath(std.testing.io, dir_path);
    }
    try dir.writeFile(std.testing.io, .{
        .sub_path = sub_path,
        .data = contents,
        .flags = .{ .truncate = true },
    });
}

fn runChildAtPathExpectFailureContains(
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
    std.debug.print("child command did not fail as expected: {s}\n{s}\n", .{ argv[0], result.stderr });
    return error.UnexpectedChildCommandFailure;
}

fn runChildAtPathExpectSuccess(
    cwd_path: []const u8,
    argv: []const []const u8,
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
        .exited => |code| if (code == 0) return,
        else => {},
    }
    std.debug.print("child command failed unexpectedly: {s}\n{s}\n", .{ argv[0], result.stderr });
    return error.UnexpectedChildCommandFailure;
}

fn suggestedFingerprint(stderr: []const u8) ?[]const u8 {
    const marker = "suggested value: ";
    const marker_start = std.mem.find(u8, stderr, marker) orelse return null;
    const value_start = marker_start + marker.len;
    var value_end = value_start;
    while (value_end < stderr.len) : (value_end += 1) {
        switch (stderr[value_end]) {
            '0'...'9', 'a'...'f', 'A'...'F', 'x' => {},
            else => break,
        }
    }
    return if (value_end > value_start) stderr[value_start..value_end] else null;
}

fn writeDownstreamBuildZon(dir: std.Io.Dir, fingerprint: ?[]const u8) !void {
    const fingerprint_line = if (fingerprint) |value|
        try std.fmt.allocPrint(std.testing.allocator, "    .fingerprint = {s},\n", .{value})
    else
        try std.testing.allocator.dupe(u8, "");
    defer std.testing.allocator.free(fingerprint_line);

    const build_zon = try std.fmt.allocPrint(
        std.testing.allocator,
        \\.{{
        \\    .name = .downstream_ability_with,
        \\    .version = "0.0.0",
        \\    .minimum_zig_version = "0.16.0",
        \\{s}    .dependencies = .{{
        \\        .ability = .{{ .path = "../../.." }},
        \\    }},
        \\    .paths = .{{ "build.zig", "build.zig.zon", "main.zig" }},
        \\}}
        \\
    ,
        .{fingerprint_line},
    );
    defer std.testing.allocator.free(build_zon);

    try writeTmpFile(dir, "build.zig.zon", build_zon);
}

fn callerSourceIsAbsent(comptime ContextType: type) bool {
    const caller_source = ContextType.caller_source;
    return switch (@typeInfo(@TypeOf(caller_source))) {
        .optional => caller_source == null,
        .null => true,
        else => false,
    };
}

fn runDownstreamAbilityWithMainExpectFailure(
    comptime main_zig: []const u8,
    expected_stderr: []const u8,
) !void {
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
        \\    const dep = b.dependency("ability", .{ .target = target, .optimize = optimize });
        \\
        \\    const root = b.createModule(.{
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\    root.addImport("ability", dep.module("ability"));
        \\
        \\    const exe = b.addExecutable(.{
        \\        .name = "downstream-ability-with",
        \\        .root_module = root,
        \\    });
        \\    const run = b.addRunArtifact(exe);
        \\    b.default_step.dependOn(&run.step);
        \\}
        \\
    ;
    try writeTmpFile(tmp.dir, "build.zig", build_zig);
    try writeDownstreamBuildZon(tmp.dir, null);
    try writeTmpFile(tmp.dir, "main.zig", main_zig);

    const build_args = &.{
        "zig",
        "build",
        "--summary",
        "none",
        "--cache-dir",
        ".zig-cache",
    };
    const fingerprint_probe = try std.process.run(std.testing.allocator, std.testing.io, .{
        .argv = build_args,
        .cwd = .{ .path = consumer_root },
        .stderr_limit = .limited(1024 * 1024),
        .stdout_limit = .limited(1024 * 1024),
    });
    defer std.testing.allocator.free(fingerprint_probe.stdout);
    defer std.testing.allocator.free(fingerprint_probe.stderr);

    switch (fingerprint_probe.term) {
        .exited => |code| if (code != 0 and std.mem.find(u8, fingerprint_probe.stderr, expected_stderr) != null) return,
        else => {},
    }
    const fingerprint = suggestedFingerprint(fingerprint_probe.stderr) orelse {
        std.debug.print("downstream fingerprint probe failed unexpectedly:\n{s}\n", .{fingerprint_probe.stderr});
        return error.UnexpectedChildCommandFailure;
    };
    try writeDownstreamBuildZon(tmp.dir, fingerprint);
    try runChildAtPathExpectFailureContains(consumer_root, build_args, expected_stderr);
}

fn runDownstreamAbilityWithMainAndImportExpectFailure(
    comptime main_zig: []const u8,
    comptime imported_zig: []const u8,
    expected_stderr: []const u8,
) !void {
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
        \\    const dep = b.dependency("ability", .{ .target = target, .optimize = optimize });
        \\
        \\    const root = b.createModule(.{
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\    root.addImport("ability", dep.module("ability"));
        \\
        \\    const exe = b.addExecutable(.{
        \\        .name = "downstream-ability-with",
        \\        .root_module = root,
        \\    });
        \\    const run = b.addRunArtifact(exe);
        \\    b.default_step.dependOn(&run.step);
        \\}
        \\
    ;
    try writeTmpFile(tmp.dir, "build.zig", build_zig);
    try writeDownstreamBuildZon(tmp.dir, null);
    try writeTmpFile(tmp.dir, "main.zig", main_zig);
    try writeTmpFile(tmp.dir, "imported.zig", imported_zig);

    const build_args = &.{
        "zig",
        "build",
        "--summary",
        "none",
        "--cache-dir",
        ".zig-cache",
    };
    const fingerprint_probe = try std.process.run(std.testing.allocator, std.testing.io, .{
        .argv = build_args,
        .cwd = .{ .path = consumer_root },
        .stderr_limit = .limited(1024 * 1024),
        .stdout_limit = .limited(1024 * 1024),
    });
    defer std.testing.allocator.free(fingerprint_probe.stdout);
    defer std.testing.allocator.free(fingerprint_probe.stderr);

    switch (fingerprint_probe.term) {
        .exited => |code| if (code != 0 and std.mem.find(u8, fingerprint_probe.stderr, expected_stderr) != null) return,
        else => {},
    }
    const fingerprint = suggestedFingerprint(fingerprint_probe.stderr) orelse {
        std.debug.print("downstream fingerprint probe failed unexpectedly:\n{s}\n", .{fingerprint_probe.stderr});
        return error.UnexpectedChildCommandFailure;
    };
    try writeDownstreamBuildZon(tmp.dir, fingerprint);
    try runChildAtPathExpectFailureContains(consumer_root, build_args, expected_stderr);
}

fn runDownstreamAbilityWithMain(comptime main_zig: []const u8) !void {
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
        \\    const dep = b.dependency("ability", .{ .target = target, .optimize = optimize });
        \\
        \\    const root = b.createModule(.{
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\    root.addImport("ability", dep.module("ability"));
        \\
        \\    const exe = b.addExecutable(.{
        \\        .name = "downstream-ability-with",
        \\        .root_module = root,
        \\    });
        \\    const run = b.addRunArtifact(exe);
        \\    b.default_step.dependOn(&run.step);
        \\}
        \\
    ;
    try writeTmpFile(tmp.dir, "build.zig", build_zig);
    try writeDownstreamBuildZon(tmp.dir, null);
    try writeTmpFile(tmp.dir, "main.zig", main_zig);

    const build_args = &.{
        "zig",
        "build",
        "--summary",
        "none",
        "--cache-dir",
        ".zig-cache",
    };
    const fingerprint_probe = try std.process.run(std.testing.allocator, std.testing.io, .{
        .argv = build_args,
        .cwd = .{ .path = consumer_root },
        .stderr_limit = .limited(1024 * 1024),
        .stdout_limit = .limited(1024 * 1024),
    });
    defer std.testing.allocator.free(fingerprint_probe.stdout);
    defer std.testing.allocator.free(fingerprint_probe.stderr);

    switch (fingerprint_probe.term) {
        .exited => |code| if (code == 0) return,
        else => {},
    }
    const fingerprint = suggestedFingerprint(fingerprint_probe.stderr) orelse {
        std.debug.print("downstream fingerprint probe failed unexpectedly:\n{s}\n", .{fingerprint_probe.stderr});
        return error.UnexpectedChildCommandFailure;
    };
    try writeDownstreamBuildZon(tmp.dir, fingerprint);
    try runChildAtPathExpectSuccess(consumer_root, build_args);
}

fn runDownstreamAbilityWithMainAndSubmodule(
    comptime main_zig: []const u8,
    comptime submodule_zig: []const u8,
) !void {
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
        \\    const dep = b.dependency("ability", .{ .target = target, .optimize = optimize });
        \\
        \\    const root = b.createModule(.{
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\    root.addImport("ability", dep.module("ability"));
        \\
        \\    const exe = b.addExecutable(.{
        \\        .name = "downstream-ability-with",
        \\        .root_module = root,
        \\    });
        \\    const run = b.addRunArtifact(exe);
        \\    b.default_step.dependOn(&run.step);
        \\}
        \\
    ;
    try writeTmpFile(tmp.dir, "build.zig", build_zig);
    try writeDownstreamBuildZon(tmp.dir, null);
    try writeTmpFile(tmp.dir, "main.zig", main_zig);
    try writeTmpFile(tmp.dir, "sub/foo.zig", submodule_zig);

    const build_args = &.{
        "zig",
        "build",
        "--summary",
        "none",
        "--cache-dir",
        ".zig-cache",
    };
    const fingerprint_probe = try std.process.run(std.testing.allocator, std.testing.io, .{
        .argv = build_args,
        .cwd = .{ .path = consumer_root },
        .stderr_limit = .limited(1024 * 1024),
        .stdout_limit = .limited(1024 * 1024),
    });
    defer std.testing.allocator.free(fingerprint_probe.stdout);
    defer std.testing.allocator.free(fingerprint_probe.stderr);

    switch (fingerprint_probe.term) {
        .exited => |code| if (code == 0) return,
        else => {},
    }
    const fingerprint = suggestedFingerprint(fingerprint_probe.stderr) orelse {
        std.debug.print("downstream fingerprint probe failed unexpectedly:\n{s}\n", .{fingerprint_probe.stderr});
        return error.UnexpectedChildCommandFailure;
    };
    try writeDownstreamBuildZon(tmp.dir, fingerprint);
    try runChildAtPathExpectSuccess(consumer_root, build_args);
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

    {
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
}

test "source helper captures explicit repo path plus caller-owned participation" {
    const src = ability_compile.lowering_api.sourceWithContent("test/source_ownership_probe_test.zig", @src(), @embedFile(std.Io.Dir.path.basename(@src().file)));

    try std.testing.expectEqualStrings("test/source_ownership_probe_test.zig", src.repo_path);
    try std.testing.expectEqualStrings(std.Io.Dir.path.basename(@src().file), std.Io.Dir.path.basename(src.caller_file));
}

test "source helper stays callable from test modules" {
    const src = ability_compile.lowering_api.source("test/source_ownership_probe_test.zig", @src());

    try std.testing.expectEqualStrings("test/source_ownership_probe_test.zig", src.repo_path);
    try std.testing.expectEqualStrings(std.Io.Dir.path.basename(@src().file), std.Io.Dir.path.basename(src.caller_file));
}

test "public root drops compile entrypoints while ability_compile keeps provenance-bearing lowering" {
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

test "plain ability.with anonymous downstream bodies fail closed without Body.source" {
    const main_zig =
        \\const ability = @import("ability");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    var runtime = ability.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\
        \\    const result = try ability.with(&runtime, .{
        \\        .state = ability.effect.state.use(@as(i32, 9)),
        \\    }, struct {
        \\        pub fn body(eff: anytype) anyerror!i32 {
        \\            return try eff.state.get();
        \\        }
        \\    });
        \\    if (result.value != 9) return error.UnexpectedValue;
        \\}
        \\
    ;
    try runDownstreamAbilityWithMainExpectFailure(main_zig, "pub const source containing embedded source bytes");
}

test "plain ability.with named downstream bodies fail closed without Body.source" {
    const main_zig =
        \\const ability = @import("ability");
        \\const std = @import("std");
        \\
        \\const Body = struct {
        \\    pub fn body(eff: anytype) anyerror!i32 {
        \\        return try eff.state.get();
        \\    }
        \\};
        \\
        \\pub fn main() !void {
        \\    var runtime = ability.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\
        \\    const result = try ability.with(&runtime, .{
        \\        .state = ability.effect.state.use(@as(i32, 9)),
        \\    }, Body);
        \\    if (result.value != 9) return error.UnexpectedValue;
        \\}
        \\
    ;
    try runDownstreamAbilityWithMainExpectFailure(main_zig, "pub const source containing embedded source bytes");
}

test "ability.with admits anonymous downstream bodies with Body.source" {
    const main_zig =
        \\const ability = @import("ability");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    var runtime = ability.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\
        \\    const result = try ability.with(&runtime, .{
        \\        .state = ability.effect.state.use(@as(i32, 9)),
        \\    }, struct {
        \\        fn sourceBytes() []const u8 { return @embedFile(std.Io.Dir.path.basename(@src().file)); }
        \\    pub const source = sourceBytes();
        \\        pub fn body(eff: anytype) anyerror!i32 {
        \\            return try eff.state.get();
        \\        }
        \\    });
        \\    if (result.value != 9) return error.UnexpectedValue;
        \\}
        \\
    ;
    try runDownstreamAbilityWithMain(main_zig);
}

test "ability.with admits anonymous downstream requirement aliases with Body.source" {
    const main_zig =
        \\const ability = @import("ability");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    var runtime = ability.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\
        \\    const result = try ability.with(&runtime, .{
        \\        .state = ability.effect.state.use(@as(i32, 9)),
        \\    }, struct {
        \\        fn sourceBytes() []const u8 { return @embedFile(std.Io.Dir.path.basename(@src().file)); }
        \\    pub const source = sourceBytes();
        \\        pub fn body(eff: anytype) anyerror!i32 {
        \\            const state = eff.state;
        \\            return try state.get();
        \\        }
        \\    });
        \\    if (result.value != 9) return error.UnexpectedValue;
        \\}
        \\
    ;
    try runDownstreamAbilityWithMain(main_zig);
}

test "ability.with admits named downstream bodies with Body.source" {
    const main_zig =
        \\const ability = @import("ability");
        \\const std = @import("std");
        \\
        \\const Body = struct {
        \\    fn sourceBytes() []const u8 { return @embedFile(std.Io.Dir.path.basename(@src().file)); }
        \\    fn sourceLocation() std.builtin.SourceLocation { return @src(); }
        \\    pub const source = sourceBytes();
        \\    pub const source_location = sourceLocation();
        \\    pub const source_identity = "main.Body";
        \\    pub fn body(eff: anytype) anyerror!i32 {
        \\        return try eff.state.get();
        \\    }
        \\};
        \\
        \\pub fn main() !void {
        \\    var runtime = ability.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\
        \\    const result = try ability.with(&runtime, .{
        \\        .state = ability.effect.state.use(@as(i32, 9)),
        \\    }, Body);
        \\    if (result.value != 9) return error.UnexpectedValue;
        \\}
        \\
    ;
    try runDownstreamAbilityWithMain(main_zig);
}

test "ability.with admits named downstream run bodies with Body.source" {
    const main_zig =
        \\const ability = @import("ability");
        \\const std = @import("std");
        \\
        \\const Body = struct {
        \\    fn sourceBytes() []const u8 { return @embedFile(std.Io.Dir.path.basename(@src().file)); }
        \\    fn sourceLocation() std.builtin.SourceLocation { return @src(); }
        \\    pub const source = sourceBytes();
        \\    pub const source_location = sourceLocation();
        \\    pub const source_identity = "main.Body";
        \\    pub fn run(eff: anytype) anyerror!i32 {
        \\        return try eff.state.get();
        \\    }
        \\};
        \\
        \\pub fn main() !void {
        \\    var runtime = ability.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\
        \\    const result = try ability.with(&runtime, .{
        \\        .state = ability.effect.state.use(@as(i32, 9)),
        \\    }, Body);
        \\    if (result.value != 9) return error.UnexpectedValue;
        \\}
        \\
    ;
    try runDownstreamAbilityWithMain(main_zig);
}

test "ability.with admits named downstream requirement aliases with Body.source" {
    const main_zig =
        \\const ability = @import("ability");
        \\const std = @import("std");
        \\
        \\const Body = struct {
        \\    fn sourceBytes() []const u8 { return @embedFile(std.Io.Dir.path.basename(@src().file)); }
        \\    fn sourceLocation() std.builtin.SourceLocation { return @src(); }
        \\    pub const source = sourceBytes();
        \\    pub const source_location = sourceLocation();
        \\    pub const source_identity = "main.Body";
        \\    pub fn body(eff: anytype) anyerror!i32 {
        \\        const state = eff.state;
        \\        return try state.get();
        \\    }
        \\};
        \\
        \\pub fn main() !void {
        \\    var runtime = ability.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\
        \\    const result = try ability.with(&runtime, .{
        \\        .state = ability.effect.state.use(@as(i32, 9)),
        \\    }, Body);
        \\    if (result.value != 9) return error.UnexpectedValue;
        \\}
        \\
    ;
    try runDownstreamAbilityWithMain(main_zig);
}

test "ability.with admits typed named downstream bodies with Body.source" {
    const main_zig =
        \\const ability = @import("ability");
        \\const std = @import("std");
        \\
        \\const Body: type = struct {
        \\    fn sourceBytes() []const u8 { return @embedFile(std.Io.Dir.path.basename(@src().file)); }
        \\    fn sourceLocation() std.builtin.SourceLocation { return @src(); }
        \\    pub const source = sourceBytes();
        \\    pub const source_location = sourceLocation();
        \\    pub const source_identity: []const u8 = "main.Body";
        \\    pub fn body(eff: anytype) anyerror!i32 {
        \\        return try eff.state.get();
        \\    }
        \\};
        \\
        \\pub fn main() !void {
        \\    var runtime = ability.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\
        \\    const result = try ability.with(&runtime, .{
        \\        .state = ability.effect.state.use(@as(i32, 9)),
        \\    }, Body);
        \\    if (result.value != 9) return error.UnexpectedValue;
        \\}
        \\
    ;
    try runDownstreamAbilityWithMain(main_zig);
}

test "ability.with admits named body from nested downstream module with Body.source" {
    const main_zig =
        \\const foo = @import("sub/foo.zig");
        \\
        \\pub fn main() !void {
        \\    try foo.run();
        \\}
        \\
    ;
    const submodule_zig =
        \\const ability = @import("ability");
        \\const std = @import("std");
        \\
        \\const Body = struct {
        \\    fn sourceBytes() []const u8 { return @embedFile(std.Io.Dir.path.basename(@src().file)); }
        \\    fn sourceLocation() std.builtin.SourceLocation { return @src(); }
        \\    pub const source = sourceBytes();
        \\    pub const source_location = sourceLocation();
        \\    pub const source_identity = "foo.Body";
        \\    pub fn body(eff: anytype) anyerror!i32 {
        \\        return try eff.state.get();
        \\    }
        \\};
        \\
        \\pub fn run() !void {
        \\    var runtime = ability.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\
        \\    const result = try ability.with(
        \\        &runtime,
        \\        .{ .state = ability.effect.state.use(@as(i32, 9)) },
        \\        Body,
        \\    );
        \\    if (result.value != 9) return error.UnexpectedValue;
        \\}
        \\
    ;
    try runDownstreamAbilityWithMainAndSubmodule(main_zig, submodule_zig);
}

test "ability.with admits named downstream body with nested same-name declaration and Body.source" {
    const main_zig =
        \\const ability = @import("ability");
        \\const std = @import("std");
        \\
        \\const Wrapper = struct {
        \\    const Body = struct {
        \\        pub fn body(_: anytype) anyerror!i32 {
        \\            return 0;
        \\        }
        \\    };
        \\};
        \\
        \\const Body = struct {
        \\    fn sourceBytes() []const u8 { return @embedFile(std.Io.Dir.path.basename(@src().file)); }
        \\    fn sourceLocation() std.builtin.SourceLocation { return @src(); }
        \\    pub const source = sourceBytes();
        \\    pub const source_location = sourceLocation();
        \\    pub const source_identity = "main.Body";
        \\    pub fn body(eff: anytype) anyerror!i32 {
        \\        return try eff.state.get();
        \\    }
        \\};
        \\
        \\pub fn main() !void {
        \\    _ = Wrapper;
        \\    var runtime = ability.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\
        \\    const result = try ability.with(&runtime, .{
        \\        .state = ability.effect.state.use(@as(i32, 9)),
        \\    }, Body);
        \\    if (result.value != 9) return error.UnexpectedValue;
        \\}
        \\
    ;
    try runDownstreamAbilityWithMain(main_zig);
}

test "ability.with admits downstream choice continuations with Body.source" {
    const main_zig =
        \\const ability = @import("ability");
        \\const std = @import("std");
        \\
        \\const PickerHandler = struct {
        \\    pub fn pick(_: *@This(), payload: i32) !ability.effect.choice.Decision(i32, []const u8) {
        \\        return ability.effect.choice.Decision(i32, []const u8).resumeWith(payload);
        \\    }
        \\
        \\    pub fn afterPick(_: *@This(), answer: []const u8) ![]const u8 {
        \\        return answer;
        \\    }
        \\};
        \\
        \\const Picker = ability.effect.Define(.{
        \\    .state_type = void,
        \\    .ops = .{
        \\        ability.effect.ops.Choice("pick", i32, i32),
        \\    },
        \\});
        \\
        \\const Body = struct {
        \\    fn sourceBytes() []const u8 { return @embedFile(std.Io.Dir.path.basename(@src().file)); }
        \\    fn sourceLocation() std.builtin.SourceLocation { return @src(); }
        \\    pub const source = sourceBytes();
        \\    pub const source_location = sourceLocation();
        \\    pub const source_identity = "main.Body";
        \\    pub fn body(eff: anytype) anyerror![]const u8 {
        \\        return try eff.picker.pick.perform(41, struct {
        \\            pub fn apply(_: i32, _: anytype) anyerror![]const u8 {
        \\                return "answer=42";
        \\            }
        \\        });
        \\    }
        \\};
        \\
        \\pub fn main() !void {
        \\    var runtime = ability.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\
        \\    const result = try ability.with(&runtime, .{
        \\        .picker = Picker.use(.{ .handler = PickerHandler{} }),
        \\    }, Body);
        \\    if (!std.mem.eql(u8, result.value, "answer=42")) return error.UnexpectedValue;
        \\}
        \\
    ;
    try runDownstreamAbilityWithMain(main_zig);
}

test "ability.with rejects unsupported named downstream helper calls with Body.source" {
    const main_zig =
        \\const ability = @import("ability");
        \\const std = @import("std");
        \\
        \\fn helper() i32 {
        \\    return 1;
        \\}
        \\
        \\const Body = struct {
        \\    fn sourceBytes() []const u8 { return @embedFile(std.Io.Dir.path.basename(@src().file)); }
        \\    fn sourceLocation() std.builtin.SourceLocation { return @src(); }
        \\    pub const source = sourceBytes();
        \\    pub const source_location = sourceLocation();
        \\    pub const source_identity = "main.Body";
        \\    pub fn body(eff: anytype) anyerror!i32 {
        \\        return try eff.state.get() + helper();
        \\    }
        \\};
        \\
        \\pub fn main() !void {
        \\    var runtime = ability.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\
        \\    const result = try ability.with(&runtime, .{
        \\        .state = ability.effect.state.use(@as(i32, 9)),
        \\    }, Body);
        \\    if (result.value != 10) return error.UnexpectedValue;
        \\}
        \\
    ;
    try runDownstreamAbilityWithMainExpectFailure(
        main_zig,
        "ability.with source-backed named body must lower to ProgramPlan without unsupported syntax",
    );
}

test "ability.with rejects source-backed @This qualified helper calls" {
    const main_zig =
        \\const ability = @import("ability");
        \\const std = @import("std");
        \\
        \\const Body = struct {
        \\    fn sourceBytes() []const u8 { return @embedFile(std.Io.Dir.path.basename(@src().file)); }
        \\    fn sourceLocation() std.builtin.SourceLocation { return @src(); }
        \\    pub const source = sourceBytes();
        \\    pub const source_location = sourceLocation();
        \\    pub const source_identity = "main.Body";
        \\    fn helper() i32 {
        \\        return 1;
        \\    }
        \\
        \\    pub fn body(eff: anytype) anyerror!i32 {
        \\        return try eff.state.get() + @This().helper();
        \\    }
        \\};
        \\
        \\pub fn main() !void {
        \\    var runtime = ability.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\
        \\    const result = try ability.with(&runtime, .{
        \\        .state = ability.effect.state.use(@as(i32, 9)),
        \\    }, Body);
        \\    if (result.value != 10) return error.UnexpectedValue;
        \\}
        \\
    ;
    try runDownstreamAbilityWithMainExpectFailure(
        main_zig,
        "ability.with source-backed named body must lower to ProgramPlan without unsupported syntax",
    );
}

test "ability.with rejects source-backed namespace qualified helper calls" {
    const main_zig =
        \\const ability = @import("ability");
        \\const std = @import("std");
        \\
        \\const Helpers = struct {
        \\    pub fn foo() i32 {
        \\        return 1;
        \\    }
        \\};
        \\
        \\pub fn main() !void {
        \\    var runtime = ability.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\
        \\    const result = try ability.with(&runtime, .{
        \\        .state = ability.effect.state.use(@as(i32, 9)),
        \\    }, struct {
        \\        fn sourceBytes() []const u8 { return @embedFile(std.Io.Dir.path.basename(@src().file)); }
        \\    pub const source = sourceBytes();
        \\        pub fn body(eff: anytype) anyerror!i32 {
        \\            return try eff.state.get() + Helpers.foo();
        \\        }
        \\    });
        \\    if (result.value != 10) return error.UnexpectedValue;
        \\}
        \\
    ;
    try runDownstreamAbilityWithMainExpectFailure(
        main_zig,
        "ability.with source-backed anonymous body must lower to ProgramPlan without unsupported syntax",
    );
}

test "ability.with rejects source-backed named bodies whose source has a mismatched same-name declaration" {
    const imported_zig =
        \\pub const Body = struct {
        \\    fn sourceLocation() @import("std").builtin.SourceLocation { return @src(); }
        \\    pub const source = @embedFile("main.zig");
        \\    pub const source_location = sourceLocation();
        \\    pub const source_identity = "imported.Body";
        \\    pub fn body(eff: anytype) anyerror!i32 {
        \\        return try eff.state.get();
        \\    }
        \\};
        \\
    ;
    const main_zig =
        \\const Body = struct {
        \\    pub const source_identity = "imported.Body";
        \\    pub fn body(_: anytype) anyerror!i32 {
        \\        return 0;
        \\    }
        \\};
        \\
        \\const ability = @import("ability");
        \\const imported = @import("imported.zig");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    _ = Body;
        \\    var runtime = ability.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\
        \\    const result = try ability.with(&runtime, .{
        \\        .state = ability.effect.state.use(@as(i32, 9)),
        \\    }, imported.Body);
        \\    if (result.value != 9) return error.UnexpectedValue;
        \\}
        \\
    ;
    try runDownstreamAbilityWithMainAndImportExpectFailure(
        main_zig,
        imported_zig,
        "ability.with source-backed named body source_identity/source_location did not match the selected top-level declaration",
    );
}
