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

fn writeConsumerBuildFiles(tmp: *std.testing.TmpDir, repo_root: []const u8) !void {
    try tmp.dir.makePath("deps");
    try tmp.dir.symLink(repo_root, "deps/shift", .{});

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

test "downstream consumer smoke can import only the root shift module even when PATH shadows zig" {
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

test "downstream consumer smoke cannot request shift_compile as a package module" {
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
    try runChildExpectFailureContains(tmp.dir, std.testing.allocator, &argv, null, "shift_compile");
}
