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
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .cwd_dir = cwd_dir,
        .env_map = env_map,
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
    env_map: ?*const std.process.EnvMap,
) !std.process.Child.RunResult {
    const result = try runChild(cwd_dir, allocator, argv, env_map);

    switch (result.term) {
        .Exited => |code| if (code != 0) {
            const suggested = extractSuggestedFingerprint(result.stderr) orelse return result;
            try rewriteBuildZonFingerprint(cwd_dir, allocator, suggested);
            allocator.free(result.stdout);
            allocator.free(result.stderr);
            return try runChild(cwd_dir, allocator, argv, env_map);
        },
        else => {},
    }

    return result;
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

fn writeConsumerBuildFiles(tmp: *std.testing.TmpDir, repo_root: []const u8) !void {
    try mirrorPublishedPackageIntoFixture(tmp, repo_root);

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
        \\    _ = try shift.with(&runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, shift.NamedBody("main.zig", "body", anyerror!i32, body));
        \\}
        \\
    );

    const argv = zigBuildArgv();
    try runChildExpectFailureContains(tmp.dir, std.testing.allocator, &argv, null, "public lowering source path must resolve to an owned repo file");
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
    try writeTmpFile(tmp.dir, "main.zig", "pub fn main() void {}\n");
    const main_path = try tmp.dir.realpathAlloc(std.testing.allocator, "main.zig");
    defer std.testing.allocator.free(main_path);
    const main_source = try std.fmt.allocPrint(std.testing.allocator,
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {{
        \\    const caller_src: std.builtin.SourceLocation = .{{
        \\        .module = @src().module,
        \\        .file = "{s}",
        \\        .line = @src().line,
        \\        .column = @src().column,
        \\        .fn_name = @src().fn_name,
        \\    }};
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    const result = try shift.withOwnedSource(caller_src, @embedFile(@src().file), .{{
        \\        .source_path = "{s}",
        \\        .entry_symbol = "__owned_body",
        \\        .body_source =
        \\            \\pub fn __owned_body(eff: anytype) anyerror!i32 {{
        \\            \\    const before = try eff.state.get();
        \\            \\    try eff.state.set(before + 1);
        \\            \\    return try eff.state.get();
        \\            \\}}
        \\        ,
        \\    }}, &runtime, .{{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }}, struct {{
        \\        pub fn body(eff: anytype) anyerror!i32 {{
        \\            const before = try eff.state.get();
        \\            try eff.state.set(before + 1);
        \\            return try eff.state.get();
        \\        }}
        \\    }});
        \\    if (result.value != 1) return error.UnexpectedResult;
        \\}}
        \\
    , .{ main_path, main_path });
    defer std.testing.allocator.free(main_source);
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
    try writeTmpFile(tmp.dir, "main.zig", "pub fn main() void {}\n");
    const main_path = try tmp.dir.realpathAlloc(std.testing.allocator, "main.zig");
    defer std.testing.allocator.free(main_path);
    const main_source = try std.fmt.allocPrint(std.testing.allocator,
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn body(eff: anytype) anyerror!i32 {{
        \\    const before = try eff.state.get();
        \\    try eff.state.set(before + 1);
        \\    return try eff.state.get();
        \\}}
        \\
        \\pub fn main() !void {{
        \\    const caller_src: std.builtin.SourceLocation = .{{
        \\        .module = @src().module,
        \\        .file = "{s}",
        \\        .line = @src().line,
        \\        .column = @src().column,
        \\        .fn_name = @src().fn_name,
        \\    }};
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    const named = shift.NamedBody("{s}", "body", anyerror!i32, body);
        \\    const result = try shift.withOwnedSource(caller_src, @embedFile(@src().file), .{{}}, &runtime, .{{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }}, named);
        \\    if (result.value != 1) return error.UnexpectedResult;
        \\}}
        \\
    , .{ main_path, main_path });
    defer std.testing.allocator.free(main_source);
    try writeTmpFile(tmp.dir, "main.zig", main_source);

    const argv = zigBuildArgv();
    try runChildExpectSuccess(tmp.dir, std.testing.allocator, &argv, null);
}
