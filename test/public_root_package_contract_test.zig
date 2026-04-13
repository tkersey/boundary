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

fn runChild(cwd_dir: std.fs.Dir, allocator: std.mem.Allocator, argv: []const []const u8) !std.process.Child.RunResult {
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .cwd_dir = cwd_dir,
        .max_output_bytes = 32 * 1024,
    });
}

fn extractSuggestedFingerprint(stderr: []const u8) ?[]const u8 {
    const marker = "if this is a new or forked package, use this value: ";
    const start = std.mem.indexOf(u8, stderr, marker) orelse return null;
    const fingerprint = stderr[start + marker.len ..];
    const line_end = std.mem.indexOfScalar(u8, fingerprint, '\n') orelse fingerprint.len;
    return fingerprint[0..line_end];
}

fn rewriteBuildZonFingerprint(cwd_dir: std.fs.Dir, allocator: std.mem.Allocator, fingerprint: []const u8) !void {
    const manifest = try cwd_dir.readFileAlloc(allocator, "build.zig.zon", std.math.maxInt(usize));
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
    try writeTmpFile(cwd_dir, "build.zig.zon", repaired);
}

fn runChildWithFingerprintRepair(
    cwd_dir: std.fs.Dir,
    allocator: std.mem.Allocator,
    argv: []const []const u8,
) !std.process.Child.RunResult {
    const result = try runChild(cwd_dir, allocator, argv);

    switch (result.term) {
        .Exited => |code| if (code != 0) {
            const suggested = extractSuggestedFingerprint(result.stderr) orelse return result;
            try rewriteBuildZonFingerprint(cwd_dir, allocator, suggested);
            allocator.free(result.stdout);
            allocator.free(result.stderr);
            return try runChild(cwd_dir, allocator, argv);
        },
        else => {},
    }

    return result;
}

fn runChildExpectSuccess(cwd_dir: std.fs.Dir, allocator: std.mem.Allocator, argv: []const []const u8) !void {
    const result = try runChildWithFingerprintRepair(cwd_dir, allocator, argv);
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
    needle: []const u8,
) !void {
    const result = try runChildWithFingerprintRepair(cwd_dir, allocator, argv);
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

test "downstream consumer can import only the root shift module and root hides specialist symbols" {
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
        \\}
        \\
        \\pub fn main() void {
        \\    _ = shift.Runtime;
        \\    _ = shift.RuntimeError;
        \\    _ = shift.effect;
        \\    _ = shift.with;
        \\}
        \\
    );

    try runChildExpectSuccess(tmp.dir, std.testing.allocator, &.{ "zig", "build" });
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

    try runChildExpectFailureContains(tmp.dir, std.testing.allocator, &.{ "zig", "build" }, "shift_compile");
}
