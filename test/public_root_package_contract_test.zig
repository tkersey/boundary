const build_options = @import("build_options");
const builtin = @import("builtin");
const std = @import("std");

fn writeTmpFile(dir: std.fs.Dir, path: []const u8, contents: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir_name| try dir.makePath(dir_name);
    var file = try dir.createFile(path, .{ .truncate = true });
    defer file.close();
    var buffer: [1024]u8 = undefined;
    var writer = file.writer(&buffer);
    try writer.interface.writeAll(contents);
    try writer.interface.flush();
}

fn runChild(
    cwd_dir: std.fs.Dir,
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    env_map: ?*const std.process.EnvMap,
) !std.process.Child.RunResult {
    const cwd_path = try cwd_dir.realpathAlloc(allocator, ".");
    defer allocator.free(cwd_path);

    var effective_env = if (env_map) |existing| blk: {
        var cloned = std.process.EnvMap.init(allocator);
        var it = existing.iterator();
        while (it.next()) |entry| {
            try cloned.put(entry.key_ptr.*, entry.value_ptr.*);
        }
        break :blk cloned;
    } else try std.process.getEnvMap(allocator);
    defer effective_env.deinit();

    if (!effective_env.hash_map.contains("ZIG_GLOBAL_CACHE_DIR")) {
        try effective_env.put("ZIG_GLOBAL_CACHE_DIR", ".zig-global-cache");
    }

    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .cwd = cwd_path,
        .env_map = &effective_env,
        .max_output_bytes = 32 * 1024,
    });
}

const FingerprintRepair = struct {
    manifest_path: []const u8,
    fingerprint: []const u8,
};

fn extractSuggestedFingerprint(stderr: []const u8) ?FingerprintRepair {
    const marker = "if this is a new or forked package, use this value: ";
    const start = std.mem.indexOf(u8, stderr, marker) orelse return null;
    const fingerprint_tail = stderr[start + marker.len ..];
    const fingerprint_end = std.mem.indexOfScalar(u8, fingerprint_tail, '\n') orelse fingerprint_tail.len;
    const fingerprint = fingerprint_tail[0..fingerprint_end];

    const path_marker = ":1:2: error: invalid fingerprint:";
    const path_end = std.mem.indexOf(u8, stderr, path_marker) orelse return null;
    const line_start = std.mem.lastIndexOfScalar(u8, stderr[0..path_end], '\n') orelse 0;
    const path_start = if (line_start == 0) 0 else line_start + 1;
    return .{
        .manifest_path = stderr[path_start..path_end],
        .fingerprint = fingerprint,
    };
}

fn rewriteBuildZonFingerprint(allocator: std.mem.Allocator, manifest_path: []const u8, fingerprint: []const u8) !void {
    const manifest_dir_path = std.fs.path.dirname(manifest_path) orelse return error.InvalidConsumerManifest;
    const manifest_basename = std.fs.path.basename(manifest_path);
    var manifest_dir = try std.fs.openDirAbsolute(manifest_dir_path, .{});
    defer manifest_dir.close();

    const manifest = try manifest_dir.readFileAlloc(allocator, manifest_basename, std.math.maxInt(usize));
    defer allocator.free(manifest);

    const marker = ".fingerprint = ";
    const start = std.mem.indexOf(u8, manifest, marker) orelse return error.InvalidConsumerManifest;
    const value_start = start + marker.len;
    const after_value = manifest[value_start..];
    const line_end_rel = std.mem.indexOfScalar(u8, after_value, '\n') orelse after_value.len;
    const value_end = value_start + line_end_rel;

    const repaired = try std.fmt.allocPrint(
        allocator,
        "{s}{s}{s}",
        .{ manifest[0..value_start], fingerprint, manifest[value_end..] },
    );
    defer allocator.free(repaired);
    try writeTmpFile(manifest_dir, manifest_basename, repaired);
}

fn runChildWithFingerprintRepair(
    cwd_dir: std.fs.Dir,
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    env_map: ?*const std.process.EnvMap,
) !std.process.Child.RunResult {
    while (true) {
        const result = try runChild(cwd_dir, allocator, argv, env_map);

        switch (result.term) {
            .Exited => |code| if (code != 0) {
                const suggested = extractSuggestedFingerprint(result.stderr) orelse return result;
                try rewriteBuildZonFingerprint(allocator, suggested.manifest_path, suggested.fingerprint);
                allocator.free(result.stdout);
                allocator.free(result.stderr);
                continue;
            },
            else => {},
        }

        return result;
    }
}

fn runChildExpectSuccess(
    cwd_dir: std.fs.Dir,
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    env_map: ?*const std.process.EnvMap,
) !void {
    const result = try runChildWithFingerprintRepair(cwd_dir, allocator, argv, env_map);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| if (code == 0) return,
        else => {},
    }
    std.debug.print("child command failed: {s}\nstdout:\n{s}\nstderr:\n{s}\n", .{ argv[0], result.stdout, result.stderr });
    return error.UnexpectedChildCommandFailure;
}

fn repairChildFingerprintIfNeeded(
    cwd_dir: std.fs.Dir,
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    env_map: ?*const std.process.EnvMap,
) !void {
    while (true) {
        const result = try runChild(cwd_dir, allocator, argv, env_map);
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        switch (result.term) {
            .Exited => |code| {
                if (code == 0) return;
                const suggested = extractSuggestedFingerprint(result.stderr) orelse return;
                try rewriteBuildZonFingerprint(allocator, suggested.manifest_path, suggested.fingerprint);
                continue;
            },
            else => return error.UnexpectedChildCommandFailure,
        }
    }
}

fn runChildExpectFailureContains(
    cwd_dir: std.fs.Dir,
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    env_map: ?*const std.process.EnvMap,
    needle: []const u8,
) !void {
    const result = try runChildWithFingerprintRepair(cwd_dir, allocator, argv, env_map);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| if (code != 0) {
            if (std.mem.indexOf(u8, result.stderr, needle) != null or std.mem.indexOf(u8, result.stdout, needle) != null) return;
            std.debug.print("child command failed without expected needle '{s}'\nstdout:\n{s}\nstderr:\n{s}\n", .{ needle, result.stdout, result.stderr });
            return error.UnexpectedChildCommandFailure;
        },
        else => {},
    }

    std.debug.print("child command unexpectedly succeeded: {s}\n", .{argv[0]});
    return error.UnexpectedChildCommandFailure;
}

fn zigBuildArgv() [2][]const u8 {
    return .{ build_options.zig_exe, "build" };
}

fn writeFakeZigOnPath(tmp: *std.testing.TmpDir) ![]const u8 {
    try tmp.dir.makePath("shadow-bin");
    const fake_name = if (builtin.os.tag == .windows) "shadow-bin/zig.bat" else "shadow-bin/zig";
    const fake_contents = if (builtin.os.tag == .windows)
        "@echo off\r\necho FAKE-ZIG-IN-PATH 1>&2\r\nexit /b 97\r\n"
    else
        "#!/bin/sh\nprintf 'FAKE-ZIG-IN-PATH\\n' >&2\nexit 97\n";
    try writeTmpFile(tmp.dir, fake_name, fake_contents);
    if (builtin.os.tag != .windows) {
        var fake_file = try tmp.dir.openFile(fake_name, .{});
        defer fake_file.close();
        try fake_file.chmod(0o755);
    }
    return "shadow-bin";
}

const published_package_paths = [_][]const u8{
    "README.md",
    "bench",
    "build.zig",
    "build.zig.zon",
    "examples",
    "repo_zig_paths.txt",
    "source_graph_embed.zig",
    "src",
    "test",
    "tools",
};

const fixture_zlinter_import = "const zlinter = @import(\"zlinter\");";
const fixture_zlinter_dependency =
    \\        .zlinter = .{
    \\            .url = "git+https://github.com/tkersey/zlinter.git?ref=zig015-fixes#42461509e68f2f947f7594fdf4d63f46db40ab87",
    \\            .hash = "zlinter-0.0.1-OjQ08dCnCwBINQWXHHWuaDi4eSx9hRXBbJUtySTqfcU3",
    \\        },
;
const fixture_zprof_dependency =
    \\        .zprof = .{
    \\            .url = "https://github.com/ANDRVV/zprof/archive/v3.0.1.zip",
    \\            .hash = "zprof-3.0.0-Z3ILTYpyAABVThrMKcGO58SgE-kGtctSugefMGgSPEyy",
    \\            .lazy = true,
    \\        },
;
const fixture_zprof_stub_dependency =
    \\        .zprof = .{
    \\            .path = "deps/zprof",
    \\        },
;
const fixture_zlinter_stub =
    \\const zlinter = struct {
    \\    pub const BuiltinLintRule = enum { fixture_noop };
    \\
    \\    pub fn builder(b: *std.Build, _: anytype) Builder {
    \\        return .{ .step = b.step("fixture-zlinter-noop", "No-op fixture zlinter step") };
    \\    }
    \\
    \\    pub const Builder = struct {
    \\        step: *std.Build.Step,
    \\
    \\        pub fn addPaths(_: *Builder, _: anytype) void {}
    \\
    \\        pub fn addRule(_: *Builder, _: anytype, _: anytype) void {}
    \\
    \\        pub fn build(self: *Builder) *std.Build.Step {
    \\            return self.step;
    \\        }
    \\    };
    \\};
;
const fixture_zprof_build =
    \\const std = @import("std");
    \\
    \\pub fn build(b: *std.Build) void {
    \\    const target = b.standardTargetOptions(.{});
    \\    const optimize = b.standardOptimizeOption(.{});
    \\    _ = b.addModule("zprof", .{
    \\        .root_source_file = b.path("src/root.zig"),
    \\        .target = target,
    \\        .optimize = optimize,
    \\    });
    \\}
;
const fixture_zprof_zon =
    \\.{
    \\    .name = .zprof,
    \\    .version = "0.0.0",
    \\    .minimum_zig_version = "0.15.2",
    \\    .paths = .{
    \\        "build.zig",
    \\        "build.zig.zon",
    \\        "src",
    \\    },
    \\    .fingerprint = 0xfeedfacecafebeef,
    \\}
;
const fixture_zprof_root =
    \\pub const Profiler = struct {};
;

fn copyRepoFileIntoFixture(
    repo_dir: std.fs.Dir,
    fixture_dir: std.fs.Dir,
    source_path: []const u8,
    dest_path: []const u8,
) !void {
    const contents = try repo_dir.readFileAlloc(std.testing.allocator, source_path, std.math.maxInt(usize));
    defer std.testing.allocator.free(contents);
    try writeTmpFile(fixture_dir, dest_path, contents);
}

fn copyRepoDirectoryIntoFixture(
    repo_dir: std.fs.Dir,
    fixture_dir: std.fs.Dir,
    source_dir_path: []const u8,
    dest_dir_path: []const u8,
) !void {
    try fixture_dir.makePath(dest_dir_path);

    var source_dir = try repo_dir.openDir(source_dir_path, .{ .iterate = true });
    defer source_dir.close();

    var walker = try source_dir.walk(std.testing.allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        const fixture_entry_path = try std.fs.path.join(std.testing.allocator, &.{ dest_dir_path, entry.path });
        defer std.testing.allocator.free(fixture_entry_path);

        switch (entry.kind) {
            .directory => try fixture_dir.makePath(fixture_entry_path),
            .file, .sym_link => try copyRepoFileIntoFixture(source_dir, fixture_dir, entry.path, fixture_entry_path),
            else => return error.UnsupportedPublishedPackageEntry,
        }
    }
}

fn mirrorPublishedPackageIntoFixture(tmp: *std.testing.TmpDir, repo_root: []const u8) !void {
    try tmp.dir.makePath("deps/shift");

    var repo_dir = try std.fs.openDirAbsolute(repo_root, .{});
    defer repo_dir.close();

    for (published_package_paths) |path| {
        const fixture_path = try std.fs.path.join(std.testing.allocator, &.{ "deps/shift", path });
        defer std.testing.allocator.free(fixture_path);

        if (repo_dir.openDir(path, .{ .iterate = true })) |dir| {
            var opened_dir = dir;
            opened_dir.close();
            try copyRepoDirectoryIntoFixture(repo_dir, tmp.dir, path, fixture_path);
            continue;
        } else |err| switch (err) {
            error.NotDir => try copyRepoFileIntoFixture(repo_dir, tmp.dir, path, fixture_path),
            else => return err,
        }
    }
}

fn rewriteFixtureShiftBuildForHermeticTests(tmp: *std.testing.TmpDir) !void {
    const fixture_build_path = "deps/shift/build.zig";
    const original_build = try tmp.dir.readFileAlloc(std.testing.allocator, fixture_build_path, std.math.maxInt(usize));
    defer std.testing.allocator.free(original_build);

    const import_start = std.mem.indexOf(u8, original_build, fixture_zlinter_import) orelse return error.InvalidPublishedPackageFixture;
    const import_end = import_start + fixture_zlinter_import.len;
    const rewritten_build = try std.fmt.allocPrint(
        std.testing.allocator,
        "{s}{s}{s}",
        .{ original_build[0..import_start], fixture_zlinter_stub, original_build[import_end..] },
    );
    defer std.testing.allocator.free(rewritten_build);

    try writeTmpFile(tmp.dir, fixture_build_path, rewritten_build);

    const fixture_zon_path = "deps/shift/build.zig.zon";
    const original_zon = try tmp.dir.readFileAlloc(std.testing.allocator, fixture_zon_path, std.math.maxInt(usize));
    defer std.testing.allocator.free(original_zon);

    const hermetic_dependency_blocks = [_][]const u8{
        fixture_zlinter_dependency,
    };
    var rewritten_zon = try std.testing.allocator.dupe(u8, original_zon);
    defer std.testing.allocator.free(rewritten_zon);

    for (hermetic_dependency_blocks) |dependency_block| {
        const dependency_start = std.mem.indexOf(u8, rewritten_zon, dependency_block) orelse return error.InvalidPublishedPackageFixture;
        const dependency_end = dependency_start + dependency_block.len;
        const next_zon = try std.fmt.allocPrint(
            std.testing.allocator,
            "{s}{s}",
            .{ rewritten_zon[0..dependency_start], rewritten_zon[dependency_end..] },
        );
        std.testing.allocator.free(rewritten_zon);
        rewritten_zon = next_zon;
    }

    const zprof_dependency_start = std.mem.indexOf(u8, rewritten_zon, fixture_zprof_dependency) orelse return error.InvalidPublishedPackageFixture;
    const zprof_dependency_end = zprof_dependency_start + fixture_zprof_dependency.len;
    const rewritten_with_stub_zprof = try std.fmt.allocPrint(
        std.testing.allocator,
        "{s}{s}{s}",
        .{
            rewritten_zon[0..zprof_dependency_start],
            fixture_zprof_stub_dependency,
            rewritten_zon[zprof_dependency_end..],
        },
    );
    std.testing.allocator.free(rewritten_zon);
    rewritten_zon = rewritten_with_stub_zprof;

    try writeTmpFile(tmp.dir, fixture_zon_path, rewritten_zon);

    try writeTmpFile(tmp.dir, "deps/shift/deps/zprof/build.zig", fixture_zprof_build);
    try writeTmpFile(tmp.dir, "deps/shift/deps/zprof/build.zig.zon", fixture_zprof_zon);
    try writeTmpFile(tmp.dir, "deps/shift/deps/zprof/src/root.zig", fixture_zprof_root);
}

fn writeConsumerBuildFiles(tmp: *std.testing.TmpDir, repo_root: []const u8) !void {
    try mirrorPublishedPackageIntoFixture(tmp, repo_root);
    try rewriteFixtureShiftBuildForHermeticTests(tmp);

    const build_zon = try std.fmt.allocPrint(std.testing.allocator,
        \\.{{
        \\    .name = .consumer_probe,
        \\    .version = "0.0.0",
        \\    .minimum_zig_version = "0.15.2",
        \\    .dependencies = .{{
        \\        .shift = .{{ .path = "deps/shift" }},
        \\    }},
        \\    .paths = .{{
        \\        "build.zig",
        \\        "build.zig.zon",
        \\        "main.zig",
        \\    }},
        \\    .fingerprint = 0x1234567890abcdef,
        \\}}
        \\
    , .{});
    defer std.testing.allocator.free(build_zon);

    try writeTmpFile(tmp.dir, "build.zig.zon", build_zon);
}

test "downstream consumer can import only the root shift module even when PATH shadows zig" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeConsumerBuildFiles(&tmp, repo_root);
    try writeTmpFile(tmp.dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\    const shift_dep = b.dependency("shift", .{ .target = target, .optimize = optimize });
        \\    const exe_mod = b.createModule(.{
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\    exe_mod.addImport("shift", shift_dep.module("shift"));
        \\    const exe = b.addExecutable(.{
        \\        .name = "consumer_probe",
        \\        .root_module = exe_mod,
        \\    });
        \\    b.installArtifact(exe);
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "main.zig",
        \\const shift = @import("shift");
        \\
        \\comptime {
        \\    if (@hasDecl(shift, "Program")) @compileError("root leaked Program");
        \\    if (@hasDecl(shift, "run")) @compileError("root leaked run");
        \\    if (@hasDecl(shift, "Decl")) @compileError("root leaked Decl");
        \\    if (@hasDecl(shift, "Op")) @compileError("root leaked Op");
        \\    if (@hasDecl(shift, "Decision")) @compileError("root leaked Decision");
        \\    if (@hasDecl(shift, "compat")) @compileError("root leaked compat");
        \\    if (@hasDecl(shift, "artifact")) @compileError("root leaked artifact");
        \\    if (@hasDecl(shift, "durable")) @compileError("root leaked durable");
        \\    if (@hasDecl(shift, "interpreter")) @compileError("root leaked interpreter");
        \\    if (@hasDecl(shift, "withCallerSource")) @compileError("root leaked withCallerSource");
        \\    if (@hasDecl(shift, "withCallerSourceAndContent")) @compileError("root leaked withCallerSourceAndContent");
        \\}
        \\
        \\pub fn main() void {
        \\    _ = shift.Runtime;
        \\    _ = shift.RuntimeError;
        \\    _ = shift.effect;
        \\    _ = shift.with;
        \\    _ = shift.withOwnedSource;
        \\}
        \\
    );

    const argv = zigBuildArgv();
    const shadow_path = try writeFakeZigOnPath(&tmp);
    var env_map = try std.process.getEnvMap(std.testing.allocator);
    defer env_map.deinit();
    try env_map.put("PATH", shadow_path);
    try runChildExpectSuccess(tmp.dir, std.testing.allocator, &argv, &env_map);
}

test "downstream consumer cannot request shift_compile as a package module" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeConsumerBuildFiles(&tmp, repo_root);
    try writeTmpFile(tmp.dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\    const shift_dep = b.dependency("shift", .{ .target = target, .optimize = optimize });
        \\    const exe_mod = b.createModule(.{
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\    exe_mod.addImport("shift_compile", shift_dep.module("shift_compile"));
        \\    const exe = b.addExecutable(.{
        \\        .name = "consumer_probe",
        \\        .root_module = exe_mod,
        \\    });
        \\    b.installArtifact(exe);
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "main.zig",
        \\const shift_compile = @import("shift_compile");
        \\
        \\pub fn main() void {
        \\    _ = shift_compile.lower;
        \\}
        \\
    );

    const argv = zigBuildArgv();
    try repairChildFingerprintIfNeeded(tmp.dir, std.testing.allocator, &argv, null);
    try runChildExpectFailureContains(tmp.dir, std.testing.allocator, &argv, null, "shift_compile");
}

test "downstream consumer cannot request shift_vm as a package module" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeConsumerBuildFiles(&tmp, repo_root);
    try writeTmpFile(tmp.dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\    const shift_dep = b.dependency("shift", .{ .target = target, .optimize = optimize });
        \\    const exe_mod = b.createModule(.{
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\    exe_mod.addImport("shift_vm", shift_dep.module("shift_vm"));
        \\    const exe = b.addExecutable(.{
        \\        .name = "consumer_probe",
        \\        .root_module = exe_mod,
        \\    });
        \\    b.installArtifact(exe);
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "main.zig",
        \\const shift_vm = @import("shift_vm");
        \\
        \\pub fn main() void {
        \\    _ = shift_vm.runtime;
        \\}
        \\
    );

    const argv = zigBuildArgv();
    try repairChildFingerprintIfNeeded(tmp.dir, std.testing.allocator, &argv, null);
    try runChildExpectFailureContains(tmp.dir, std.testing.allocator, &argv, null, "shift_vm");
}

test "downstream consumer cannot compile caller-owned NamedBody sources through the root package yet" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeConsumerBuildFiles(&tmp, repo_root);
    try writeTmpFile(tmp.dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\    const shift_dep = b.dependency("shift", .{ .target = target, .optimize = optimize });
        \\    const exe_mod = b.createModule(.{
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\    exe_mod.addImport("shift", shift_dep.module("shift"));
        \\    const exe = b.addExecutable(.{
        \\        .name = "consumer_probe",
        \\        .root_module = exe_mod,
        \\    });
        \\    b.installArtifact(exe);
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "main.zig",
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\fn body(_: anytype) anyerror!i32 {
        \\    return 0;
        \\}
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    _ = try shift.with(@src(), &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, shift.NamedBody("main.zig", "body", anyerror!i32, body));
        \\}
        \\
    );

    const argv = zigBuildArgv();
    try repairChildFingerprintIfNeeded(tmp.dir, std.testing.allocator, &argv, null);
    try runChildExpectFailureContains(tmp.dir, std.testing.allocator, &argv, null, "public lowering source path must resolve to an owned repo file");
}

test "downstream consumer cannot bind a repo-owned NamedBody source_path to a different function with the same name" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeConsumerBuildFiles(&tmp, repo_root);
    try writeTmpFile(tmp.dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\    const shift_dep = b.dependency("shift", .{ .target = target, .optimize = optimize });
        \\    const exe_mod = b.createModule(.{
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\    exe_mod.addImport("shift", shift_dep.module("shift"));
        \\    const exe = b.addExecutable(.{
        \\        .name = "consumer_probe",
        \\        .root_module = exe_mod,
        \\    });
        \\    b.installArtifact(exe);
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "main.zig",
        \\const shift = @import("shift");
        \\
        \\fn namedBodyRepoSourceCollision(_: anytype) anyerror!i32 {
        \\    return 0;
        \\}
        \\
        \\pub fn main() !void {
        \\    _ = shift.NamedBody(
        \\        "test/named_body_repo_source_collision_a.zig",
        \\        "namedBodyRepoSourceCollision",
        \\        anyerror!i32,
        \\        namedBodyRepoSourceCollision,
        \\    );
        \\}
        \\
    );

    const argv = zigBuildArgv();
    try repairChildFingerprintIfNeeded(tmp.dir, std.testing.allocator, &argv, null);
    try runChildExpectFailureContains(tmp.dir, std.testing.allocator, &argv, null, "entry_symbol must be unique across owned repo sources");
}

test "downstream consumer cannot bind a repo-owned NamedBody source_path that does not export the declared function" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeConsumerBuildFiles(&tmp, repo_root);
    try writeTmpFile(tmp.dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\    const shift_dep = b.dependency("shift", .{ .target = target, .optimize = optimize });
        \\    const exe_mod = b.createModule(.{
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\    exe_mod.addImport("shift", shift_dep.module("shift"));
        \\    const exe = b.addExecutable(.{
        \\        .name = "consumer_probe",
        \\        .root_module = exe_mod,
        \\    });
        \\    b.installArtifact(exe);
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "main.zig",
        \\const shift = @import("shift");
        \\
        \\fn witnessMultiPromptBody(_: anytype) anyerror!i32 {
        \\    return 0;
        \\}
        \\
        \\pub fn main() void {
        \\    _ = shift.NamedBody(
        \\        "src/root.zig",
        \\        "witnessMultiPromptBody",
        \\        anyerror!i32,
        \\        witnessMultiPromptBody,
        \\    );
        \\}
        \\
    );

    const argv = zigBuildArgv();
    try repairChildFingerprintIfNeeded(tmp.dir, std.testing.allocator, &argv, null);
    try runChildExpectFailureContains(tmp.dir, std.testing.allocator, &argv, null, "source_path must export the supplied entry_symbol");
}

test "downstream consumer cannot ship NamedBody paths outside the retained compiled lexical subset" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeConsumerBuildFiles(&tmp, repo_root);
    try writeTmpFile(tmp.dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\    const shift_dep = b.dependency("shift", .{ .target = target, .optimize = optimize });
        \\    const exe_mod = b.createModule(.{
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\    exe_mod.addImport("shift", shift_dep.module("shift"));
        \\    const exe = b.addExecutable(.{
        \\        .name = "consumer_probe",
        \\        .root_module = exe_mod,
        \\    });
        \\    b.installArtifact(exe);
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "main.zig",
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\fn witnessMultiPromptBody(_: anytype) anyerror!i32 {
        \\    return 0;
        \\}
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    _ = try shift.with(@src(), &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, shift.NamedBody(
        \\        "src/witness_sources.zig",
        \\        "witnessMultiPromptBody",
        \\        anyerror!i32,
        \\        witnessMultiPromptBody,
        \\    ));
        \\}
        \\
    );

    const argv = zigBuildArgv();
    try repairChildFingerprintIfNeeded(tmp.dir, std.testing.allocator, &argv, null);
    try runChildExpectFailureContains(tmp.dir, std.testing.allocator, &argv, null, "shift.NamedBody shipped execution must stay within the retained compiled lexical subset");
}

test "downstream consumer can compile an anonymous same-file lexical body through the root package" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeConsumerBuildFiles(&tmp, repo_root);
    try writeTmpFile(tmp.dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\    const shift_dep = b.dependency("shift", .{ .target = target, .optimize = optimize });
        \\    const exe_mod = b.createModule(.{
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\    exe_mod.addImport("shift", shift_dep.module("shift"));
        \\    const exe = b.addExecutable(.{
        \\        .name = "consumer_probe",
        \\        .root_module = exe_mod,
        \\    });
        \\    b.installArtifact(exe);
        \\}
        \\
    );
    const main_source =
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    const result = try shift.with(@src(), &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, struct {
        \\        pub fn body(eff: anytype) anyerror!i32 {
        \\            const before = try eff.state.get();
        \\            try eff.state.set(before + 1);
        \\            return try eff.state.get();
        \\        }
        \\    });
        \\    if (result.value != 1) return error.UnexpectedResult;
        \\}
        \\
    ;
    try writeTmpFile(tmp.dir, "main.zig", main_source);

    const argv = zigBuildArgv();
    try runChildExpectSuccess(tmp.dir, std.testing.allocator, &argv, null);
}

test "downstream consumer can compile an anonymous same-file lexical body through withOwnedSource" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeConsumerBuildFiles(&tmp, repo_root);
    try writeTmpFile(tmp.dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\    const shift_dep = b.dependency("shift", .{ .target = target, .optimize = optimize });
        \\    const exe_mod = b.createModule(.{
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\    exe_mod.addImport("shift", shift_dep.module("shift"));
        \\    const exe = b.addExecutable(.{
        \\        .name = "consumer_probe",
        \\        .root_module = exe_mod,
        \\    });
        \\    b.installArtifact(exe);
        \\}
        \\
    );
    const main_source =
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    const result = try shift.withOwnedSource(@src(), @embedFile(@src().file), .{}, &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, struct {
        \\        pub fn body(eff: anytype) anyerror!i32 {
        \\            const before = try eff.state.get();
        \\            try eff.state.set(before + 1);
        \\            return try eff.state.get();
        \\        }
        \\    });
        \\    if (result.value != 1) return error.UnexpectedResult;
        \\}
        \\
    ;
    try writeTmpFile(tmp.dir, "main.zig", main_source);

    const argv = zigBuildArgv();
    try runChildExpectSuccess(tmp.dir, std.testing.allocator, &argv, null);
}

test "downstream consumer can compile caller-owned NamedBody sources through the root package via explicit withOwnedSource witness" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeConsumerBuildFiles(&tmp, repo_root);
    try writeTmpFile(tmp.dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\    const shift_dep = b.dependency("shift", .{ .target = target, .optimize = optimize });
        \\    const exe_mod = b.createModule(.{
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\    exe_mod.addImport("shift", shift_dep.module("shift"));
        \\    const exe = b.addExecutable(.{
        \\        .name = "consumer_probe",
        \\        .root_module = exe_mod,
        \\    });
        \\    b.installArtifact(exe);
        \\}
        \\
    );
    const main_source =
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn body(eff: anytype) anyerror!i32 {
        \\    const before = try eff.state.get();
        \\    try eff.state.set(before + 1);
        \\    return try eff.state.get();
        \\}
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    const named = shift.NamedBody(@src().file, "body", anyerror!i32, body);
        \\    const result = try shift.withOwnedSource(@src(), @embedFile(@src().file), .{}, &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, named);
        \\    if (result.value != 1) return error.UnexpectedResult;
        \\}
        \\
    ;
    try writeTmpFile(tmp.dir, "main.zig", main_source);

    const argv = zigBuildArgv();
    try runChildExpectSuccess(tmp.dir, std.testing.allocator, &argv, null);
}

test "downstream consumer can compile caller-owned bool literal NamedBody sources through withOwnedSource witness" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeConsumerBuildFiles(&tmp, repo_root);
    try writeTmpFile(tmp.dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\    const shift_dep = b.dependency("shift", .{ .target = target, .optimize = optimize });
        \\    const exe_mod = b.createModule(.{
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\    exe_mod.addImport("shift", shift_dep.module("shift"));
        \\    const exe = b.addExecutable(.{
        \\        .name = "consumer_probe",
        \\        .root_module = exe_mod,
        \\    });
        \\    b.installArtifact(exe);
        \\}
        \\
    );
    const main_source =
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn body(_: anytype) anyerror!bool {
        \\    return true;
        \\}
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    const named = shift.NamedBody(@src().file, "body", anyerror!bool, body);
        \\    const result = try shift.withOwnedSource(@src(), @embedFile(@src().file), .{}, &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, named);
        \\    if (!result.value) return error.UnexpectedResult;
        \\}
        \\
    ;
    try writeTmpFile(tmp.dir, "main.zig", main_source);

    const argv = zigBuildArgv();
    try runChildExpectSuccess(tmp.dir, std.testing.allocator, &argv, null);
}

test "downstream consumer can compile caller-owned large usize literal NamedBody sources through withOwnedSource witness" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeConsumerBuildFiles(&tmp, repo_root);
    try writeTmpFile(tmp.dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\    const shift_dep = b.dependency("shift", .{ .target = target, .optimize = optimize });
        \\    const exe_mod = b.createModule(.{
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\    exe_mod.addImport("shift", shift_dep.module("shift"));
        \\    const exe = b.addExecutable(.{
        \\        .name = "consumer_probe",
        \\        .root_module = exe_mod,
        \\    });
        \\    b.installArtifact(exe);
        \\}
        \\
    );
    const main_source =
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn body(_: anytype) anyerror!usize {
        \\    return 5000000000;
        \\}
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    const named = shift.NamedBody(@src().file, "body", anyerror!usize, body);
        \\    const result = try shift.withOwnedSource(@src(), @embedFile(@src().file), .{}, &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, named);
        \\    if (result.value != 5000000000) return error.UnexpectedResult;
        \\}
        \\
    ;
    try writeTmpFile(tmp.dir, "main.zig", main_source);

    const argv = zigBuildArgv();
    try runChildExpectSuccess(tmp.dir, std.testing.allocator, &argv, null);
}

test "downstream consumer can compile caller-owned cross-file NamedBody sources through the root package via explicit withOwnedSource witness" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeConsumerBuildFiles(&tmp, repo_root);
    try writeTmpFile(tmp.dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\    const shift_dep = b.dependency("shift", .{ .target = target, .optimize = optimize });
        \\    const exe_mod = b.createModule(.{
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\    exe_mod.addImport("shift", shift_dep.module("shift"));
        \\    const exe = b.addExecutable(.{
        \\        .name = "consumer_probe",
        \\        .root_module = exe_mod,
        \\    });
        \\    b.installArtifact(exe);
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "body.zig",
        \\pub fn body(eff: anytype) anyerror!i32 {
        \\    const before = try eff.state.get();
        \\    try eff.state.set(before + 1);
        \\    return try eff.state.get();
        \\}
        \\
    );
    const main_source =
        \\const body_mod = @import("body.zig");
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    const named = shift.NamedBody("body.zig", "body", anyerror!i32, body_mod.body);
        \\    const result = try shift.withOwnedSource(@src(), @embedFile("body.zig"), .{}, &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, named);
        \\    if (result.value != 1) return error.UnexpectedResult;
        \\}
        \\
    ;
    try writeTmpFile(tmp.dir, "main.zig", main_source);

    const argv = zigBuildArgv();
    try runChildExpectSuccess(tmp.dir, std.testing.allocator, &argv, null);
}

test "downstream consumer rejects withOwnedSource witness bodies outside the retained compiled subset" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeConsumerBuildFiles(&tmp, repo_root);
    try writeTmpFile(tmp.dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\    const shift_dep = b.dependency("shift", .{ .target = target, .optimize = optimize });
        \\    const exe_mod = b.createModule(.{
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\    exe_mod.addImport("shift", shift_dep.module("shift"));
        \\    const exe = b.addExecutable(.{
        \\        .name = "consumer_probe",
        \\        .root_module = exe_mod,
        \\    });
        \\    b.installArtifact(exe);
        \\}
        \\
    );
    const main_source =
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\const Body = struct {
        \\    pub fn body(_: anytype) anyerror!i32 {
        \\        return 7;
        \\    }
        \\};
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    _ = try shift.withOwnedSource(@src(), @embedFile(@src().file), .{
        \\        .body_source =
        \\        \\pub fn body(_: anytype) anyerror!i32 {
        \\        \\    var total: i32 = 0;
        \\        \\    while (total < 1) : (total += 1) {}
        \\        \\    return total;
        \\        \\}
        \\        ,
        \\    }, &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, Body);
        \\}
        \\
    ;
    try writeTmpFile(tmp.dir, "main.zig", main_source);

    const argv = zigBuildArgv();
    try runChildExpectFailureContains(
        tmp.dir,
        std.testing.allocator,
        &argv,
        null,
        "shift.withOwnedSource explicit source witnesses must stay within the retained compiled lexical subset",
    );
}

test "downstream helper basename collisions stay caller-owned through withOwnedSource" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeConsumerBuildFiles(&tmp, repo_root);
    try writeTmpFile(tmp.dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\    const shift_dep = b.dependency("shift", .{ .target = target, .optimize = optimize });
        \\    const exe_mod = b.createModule(.{
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\    exe_mod.addImport("shift", shift_dep.module("shift"));
        \\    const exe = b.addExecutable(.{
        \\        .name = "consumer_probe",
        \\        .root_module = exe_mod,
        \\    });
        \\    b.installArtifact(exe);
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "helper.zig",
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn run() !i32 {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    const result = try shift.withOwnedSource(@src(), @embedFile(@src().file), .{}, &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, struct {
        \\        pub fn body(eff: anytype) anyerror!i32 {
        \\            const before = try eff.state.get();
        \\            try eff.state.set(before + 1);
        \\            return try eff.state.get();
        \\        }
        \\    });
        \\    return result.value;
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "main.zig",
        \\const helper = @import("helper.zig");
        \\
        \\pub fn main() !void {
        \\    const result = try helper.run();
        \\    if (result != 1) return error.UnexpectedResult;
        \\}
        \\
    );

    const argv = zigBuildArgv();
    try runChildExpectSuccess(tmp.dir, std.testing.allocator, &argv, null);
}

test "downstream anonymous withOwnedSource rejects explicit imported helper witnesses outside the retained compiled subset" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    try writeConsumerBuildFiles(&tmp, repo_root);
    try writeTmpFile(tmp.dir, "build.zig",
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\    const shift_dep = b.dependency("shift", .{ .target = target, .optimize = optimize });
        \\    const exe_mod = b.createModule(.{
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\    exe_mod.addImport("shift", shift_dep.module("shift"));
        \\    const exe = b.addExecutable(.{
        \\        .name = "consumer_probe",
        \\        .root_module = exe_mod,
        \\    });
        \\    b.installArtifact(exe);
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "helper.zig",
        \\pub fn bump(value: i32) i32 {
        \\    return value + 1;
        \\}
        \\
    );
    try writeTmpFile(tmp.dir, "main.zig",
        \\const helper = @import("helper.zig");
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    const result = try shift.withOwnedSource(@src(), @embedFile(@src().file), .{
        \\        .imported_sources = &.{
        \\            .{
        \\                .path = "helper.zig",
        \\                .content = @embedFile("helper.zig"),
        \\            },
        \\        },
        \\    }, &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, struct {
        \\        pub fn body(eff: anytype) anyerror!i32 {
        \\            const before = try eff.state.get();
        \\            try eff.state.set(helper.bump(before));
        \\            return try eff.state.get();
        \\        }
        \\    });
        \\    if (result.value != 1) return error.UnexpectedResult;
        \\}
        \\
    );

    const argv = zigBuildArgv();
    try runChildExpectFailureContains(
        tmp.dir,
        std.testing.allocator,
        &argv,
        null,
        "shift.withOwnedSource explicit source witnesses must stay within the retained compiled lexical subset",
    );
}

test "runChild accepts apostrophes in non-Windows cwd and argv" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("o'connor");
    var quoted_dir = try tmp.dir.openDir("o'connor", .{});
    defer quoted_dir.close();

    const argv: [3][]const u8 = .{ "printf", "%s", "o'connor" };
    const result = try runChild(quoted_dir, std.testing.allocator, &argv, null);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try std.testing.expectEqual(@as(std.process.Child.Term, .{ .Exited = 0 }), result.term);
    try std.testing.expectEqualStrings("o'connor", result.stdout);
}
