const build_options = @import("build_options");
const builtin = @import("builtin");
const std = @import("std");

fn smokeCaseStart(label: []const u8) i128 {
    const start_ns = std.time.nanoTimestamp();
    std.debug.print("[public-root-package-contract] start {s}\n", .{label});
    return start_ns;
}

fn smokeCaseDone(label: []const u8, start_ns: i128) void {
    const elapsed_ns = std.time.nanoTimestamp() - start_ns;
    const elapsed_ms = @divTrunc(elapsed_ns, std.time.ns_per_ms);
    std.debug.print("[public-root-package-contract] done {s} ({d} ms)\n", .{ label, elapsed_ms });
}

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

fn runChildNoOutput(
    cwd_dir: std.fs.Dir,
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    env_map: ?*const std.process.EnvMap,
) !std.process.Child.Term {
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

    var child = std.process.Child.init(argv, allocator);
    child.cwd = cwd_path;
    child.env_map = &effective_env;
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    return try child.spawnAndWait();
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
    while (true) {
        const term = try runChildNoOutput(cwd_dir, allocator, argv, env_map);
        switch (term) {
            .Exited => |code| if (code == 0) return,
            else => {},
        }

        const result = try runChild(cwd_dir, allocator, argv, env_map);
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        switch (result.term) {
            .Exited => |code| if (code != 0) {
                const suggested = extractSuggestedFingerprint(result.stderr) orelse {
                    std.debug.print("child command failed: {s}\nstdout:\n{s}\nstderr:\n{s}\n", .{ argv[0], result.stdout, result.stderr });
                    return error.UnexpectedChildCommandFailure;
                };
                try rewriteBuildZonFingerprint(allocator, suggested.manifest_path, suggested.fingerprint);
                continue;
            },
            else => {},
        }

        std.debug.print("child command unexpectedly failed without an exit code: {s}\n", .{argv[0]});
        return error.UnexpectedChildCommandFailure;
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

fn assertPublishedPackagePathsMatchManifest(repo_dir: std.fs.Dir) !void {
    const manifest = try repo_dir.readFileAlloc(std.testing.allocator, "build.zig.zon", std.math.maxInt(usize));
    defer std.testing.allocator.free(manifest);

    const paths_start = std.mem.indexOf(u8, manifest, ".paths = .{") orelse return error.InvalidPublishedPackageManifest;
    const block_tail = manifest[paths_start..];
    const paths_end = std.mem.indexOf(u8, block_tail, "    },") orelse return error.InvalidPublishedPackageManifest;
    const paths_block = block_tail[0..paths_end];

    inline for (published_package_paths) |path| {
        const quoted = comptime std.fmt.comptimePrint("\"{s}\"", .{path});
        if (std.mem.indexOf(u8, paths_block, quoted) == null) return error.PublishedPackagePathDrift;
    }

    var line_iter = std.mem.splitScalar(u8, paths_block, '\n');
    var actual_count: usize = 0;
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] != '"') continue;
        actual_count += 1;
    }
    if (actual_count != published_package_paths.len) return error.PublishedPackagePathDrift;
}

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
    try assertPublishedPackagePathsMatchManifest(repo_dir);

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

fn writeConsumerExecutableBuild(dir: std.fs.Dir, import_name: []const u8) !void {
    return writeConsumerExecutableBuildWithRoot(dir, import_name, "main.zig");
}

fn writeConsumerExecutableBuildWithRoot(
    dir: std.fs.Dir,
    import_name: []const u8,
    root_source_path: []const u8,
) !void {
    const build_zig = try std.fmt.allocPrint(std.testing.allocator,
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {{
        \\    const target = b.standardTargetOptions(.{{}});
        \\    const optimize = b.standardOptimizeOption(.{{}});
        \\    const shift_dep = b.dependency("shift", .{{ .target = target, .optimize = optimize }});
        \\    const exe_mod = b.createModule(.{{
        \\        .root_source_file = b.path("{s}"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    }});
        \\    exe_mod.addImport("{s}", shift_dep.module("{s}"));
        \\    const exe = b.addExecutable(.{{
        \\        .name = "consumer_probe",
        \\        .root_module = exe_mod,
        \\    }});
        \\    b.installArtifact(exe);
        \\}}
        \\
    , .{ root_source_path, import_name, import_name });
    defer std.testing.allocator.free(build_zig);
    try writeTmpFile(dir, "build.zig", build_zig);
}

fn writeConsumerTestBuild(dir: std.fs.Dir, import_name: []const u8) !void {
    const build_zig = try std.fmt.allocPrint(std.testing.allocator,
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {{
        \\    const target = b.standardTargetOptions(.{{}});
        \\    const optimize = b.standardOptimizeOption(.{{}});
        \\    const shift_dep = b.dependency("shift", .{{ .target = target, .optimize = optimize }});
        \\    const test_mod = b.createModule(.{{
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    }});
        \\    test_mod.addImport("{s}", shift_dep.module("{s}"));
        \\    const unit_tests = b.addTest(.{{
        \\        .name = "consumer_probe",
        \\        .root_module = test_mod,
        \\    }});
        \\    const run_tests = b.addRunArtifact(unit_tests);
        \\    b.default_step.dependOn(&run_tests.step);
        \\}}
        \\
    , .{ import_name, import_name });
    defer std.testing.allocator.free(build_zig);
    try writeTmpFile(dir, "build.zig", build_zig);
}

const ConsumerSmokeSuite = struct {
    tmp: std.testing.TmpDir,

    fn init(repo_root: []const u8) !ConsumerSmokeSuite {
        var tmp = std.testing.tmpDir(.{});
        try writeConsumerBuildFiles(&tmp, repo_root);
        return .{ .tmp = tmp };
    }

    fn deinit(self: *ConsumerSmokeSuite) void {
        self.tmp.cleanup();
    }

    fn writeFile(self: *ConsumerSmokeSuite, path: []const u8, contents: []const u8) !void {
        try writeTmpFile(self.tmp.dir, path, contents);
    }

    fn expectSuccess(
        self: *ConsumerSmokeSuite,
        label: []const u8,
        argv: []const []const u8,
        env_map: ?*const std.process.EnvMap,
    ) !void {
        const start_ns = smokeCaseStart(label);
        try runChildExpectSuccess(self.tmp.dir, std.testing.allocator, argv, env_map);
        smokeCaseDone(label, start_ns);
    }

    fn expectFailureContains(
        self: *ConsumerSmokeSuite,
        label: []const u8,
        argv: []const []const u8,
        env_map: ?*const std.process.EnvMap,
        needle: []const u8,
    ) !void {
        const start_ns = smokeCaseStart(label);
        try runChildExpectFailureContains(self.tmp.dir, std.testing.allocator, argv, env_map, needle);
        smokeCaseDone(label, start_ns);
    }
};

test "downstream consumer smoke suite reuses one mirrored consumer fixture" {
    const repo_root = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    var suite = try ConsumerSmokeSuite.init(repo_root);
    defer suite.deinit();

    const argv = zigBuildArgv();

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
        \\const shift = @import("shift");
        \\
        \\pub fn main() void {
        \\    _ = shift.Runtime;
        \\    _ = shift.RuntimeError;
        \\    _ = shift.effect;
        \\    const witness: shift.OwnedSourceWitness = .{};
        \\    _ = witness;
        \\    _ = shift.with;
        \\    _ = shift.withOwnedSource;
        \\}
        \\
    );
    const shadow_path = try writeFakeZigOnPath(&suite.tmp);
    var env_map = try std.process.getEnvMap(std.testing.allocator);
    defer env_map.deinit();
    try env_map.put("PATH", shadow_path);
    try suite.expectSuccess("public root imports only shipped APIs", &argv, &env_map);

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift_compile");
    try suite.writeFile("main.zig",
        \\const shift_compile = @import("shift_compile");
        \\
        \\pub fn main() void {
        \\    _ = shift_compile.lower;
        \\}
        \\
    );
    try suite.expectFailureContains("shift_compile stays hidden from downstream packages", &argv, null, "shift_compile");

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift_vm");
    try suite.writeFile("main.zig",
        \\const shift_vm = @import("shift_vm");
        \\
        \\pub fn main() void {
        \\    _ = shift_vm.Runtime;
        \\}
        \\
    );
    try suite.expectFailureContains("shift_vm stays hidden from downstream packages", &argv, null, "shift_vm");

    try writeConsumerTestBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\fn witnessMultiPromptBody(_: anytype) anyerror!i32 {
        \\    return 0;
        \\}
        \\
        \\test "repo-owned NamedBody does not use a local fallback in test builds" {
        \\    var runtime = shift.Runtime.init(std.testing.allocator);
        \\    defer runtime.deinit();
        \\    _ = try shift.withAt(@src(), &runtime, .{
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
    try suite.expectFailureContains("repo-owned NamedBody does not fall back to local test bodies", &argv, null, "shift.NamedBody source_path must match the supplied body function provenance");

    try writeConsumerTestBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\test "legacy lexical and state wrappers stay source-compatible" {
        \\    const AnyError = anyerror;
        \\    var runtime = shift.Runtime.init(std.testing.allocator);
        \\    defer runtime.deinit();
        \\
        \\    const with_result = try shift.with(&runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, struct {
        \\        pub fn body(eff: anytype) anyerror!i32 {
        \\            const before = try eff.state.get();
        \\            try eff.state.set(before + 1);
        \\            return try eff.state.get();
        \\        }
        \\    });
        \\    try std.testing.expectEqual(@as(i32, 1), with_result.value);
        \\    try std.testing.expectEqual(@as(i32, 1), with_result.outputs.state);
        \\
        \\    var state_instance = shift.effect.state.Instance(i32, AnyError).init();
        \\    const handled = try shift.effect.state.handle(i32, &runtime, &state_instance, @as(i32, 0), struct {
        \\        pub fn body(comptime Cap: type, ctx: anytype) AnyError!i32 {
        \\            const before = try shift.effect.state.get(Cap, ctx);
        \\            try shift.effect.state.set(Cap, ctx, before + 2);
        \\            return try shift.effect.state.get(Cap, ctx);
        \\        }
        \\    });
        \\    try std.testing.expectEqual(@as(i32, 2), handled.value);
        \\    try std.testing.expectEqual(@as(i32, 2), handled.state);
        \\
        \\    var state_instance_with_error = shift.effect.state.Instance(i32, AnyError).init();
        \\    const handled_with_error = try shift.effect.state.handleWithErrorSet(i32, AnyError, &runtime, &state_instance_with_error, @as(i32, 0), struct {
        \\        pub fn body(comptime Cap: type, ctx: anytype) AnyError!i32 {
        \\            const before = try shift.effect.state.get(Cap, ctx);
        \\            try shift.effect.state.set(Cap, ctx, before + 3);
        \\            return try shift.effect.state.get(Cap, ctx);
        \\        }
        \\    });
        \\    try std.testing.expectEqual(@as(i32, 3), handled_with_error.value);
        \\    try std.testing.expectEqual(@as(i32, 3), handled_with_error.state);
        \\}
        \\
    );
    try suite.expectSuccess("legacy lexical and state wrappers stay source-compatible", &argv, null);

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
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
    );
    try suite.expectSuccess("withOwnedSource anonymous bodies stay usable downstream", &argv, null);

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
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
    );
    try suite.expectSuccess("withOwnedSource keeps repo-owned NamedBody identity", &argv, null);

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
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
        \\    const result = try shift.with(&runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, shift.NamedBody(@src().file, "body", anyerror!i32, body));
        \\    if (result.value != 1) return error.UnexpectedResult;
        \\    if (result.outputs.state != 1) return error.UnexpectedState;
        \\}
        \\
    );
    try suite.expectSuccess("downstream NamedBody stays usable with shift.with", &argv, null);

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("helpers.zig",
        \\pub fn body(eff: anytype) anyerror!i32 {
        \\    const before = try eff.state.get();
        \\    try eff.state.set(before + 1);
        \\    return try eff.state.get();
        \\}
        \\
    );
    try suite.writeFile("main.zig",
        \\const helpers = @import("helpers.zig");
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    const result = try shift.withAt(@src(), &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, shift.NamedBody("helpers.zig", "body", anyerror!i32, helpers.body));
        \\    if (result.value != 1) return error.UnexpectedResult;
        \\    if (result.outputs.state != 1) return error.UnexpectedState;
        \\}
        \\
    );
    try suite.expectSuccess("downstream NamedBody stays usable across helper files with withAt", &argv, null);

    try writeConsumerExecutableBuildWithRoot(suite.tmp.dir, "shift", "src/main.zig");
    try suite.writeFile("src/helpers.zig",
        \\pub fn body(eff: anytype) anyerror!i32 {
        \\    const before = try eff.state.get();
        \\    try eff.state.set(before + 1);
        \\    return try eff.state.get();
        \\}
        \\
    );
    try suite.writeFile("src/main.zig",
        \\const helpers = @import("helpers.zig");
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    const result = try shift.withAt(@src(), &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, shift.NamedBody("src/helpers.zig", "body", anyerror!i32, helpers.body));
        \\    if (result.value != 1) return error.UnexpectedResult;
        \\    if (result.outputs.state != 1) return error.UnexpectedState;
        \\}
        \\
    );
    try suite.expectSuccess("downstream NamedBody stays usable for source-rooted helpers with withAt", &argv, null);

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
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
        \\    const result = try shift.withAt(@src(), &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, shift.NamedBody(@src().file, "body", anyerror!i32, body));
        \\    if (result.value != 1) return error.UnexpectedResult;
        \\    if (result.outputs.state != 1) return error.UnexpectedState;
        \\}
        \\
    );
    try suite.expectSuccess("downstream NamedBody stays usable with withAt", &argv, null);

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn body(eff: anytype) anyerror![]const u8 {
        \\    return try eff.optional.request(struct {
        \\        pub fn apply(value: i32, _: anytype) anyerror![]const u8 {
        \\            if (value != 41) unreachable;
        \\            return "answer=42";
        \\        }
        \\    });
        \\}
        \\
        \\pub fn main() !void {
        \\    const policy = struct {
        \\        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, []const u8) {
        \\            return shift.effect.choice.Decision(i32, []const u8).resumeWith(41);
        \\        }
        \\
        \\        pub fn afterResume(answer: []const u8) []const u8 {
        \\            return answer;
        \\        }
        \\    };
        \\
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    const result = try shift.withAt(@src(), &runtime, .{
        \\        .optional = shift.effect.optional.use(i32, policy),
        \\    }, shift.NamedBody(@src().file, "body", anyerror![]const u8, body));
        \\    if (!std.mem.eql(u8, result.value, "answer=42")) return error.UnexpectedResult;
        \\}
        \\
    );
    try suite.expectSuccess("downstream NamedBody keeps resumed payload semantics with withAt", &argv, null);

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    const policy = struct {
        \\        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, []const u8) {
        \\            return shift.effect.choice.Decision(i32, []const u8).resumeWith(41);
        \\        }
        \\
        \\        pub fn afterResume(answer: []const u8) []const u8 {
        \\            return answer;
        \\        }
        \\    };
        \\
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    _ = try shift.withOwnedSource(@src(), @embedFile(@src().file), .{
        \\        .entry_symbol = "ownedBody",
        \\        .body_source =
        \\        \\pub fn ownedBody(eff: anytype) anyerror![]const u8 {
        \\        \\    return try eff.optional.request(struct {
        \\        \\        pub fn apply(value: i32, _: anytype) anyerror![]const u8 {
        \\        \\            if (value != 41) unreachable;
        \\        \\            return "answer=42";
        \\        \\        }
        \\        \\    }, "extra");
        \\        \\}
        \\        ,
        \\    }, &runtime, .{
        \\        .optional = shift.effect.optional.use(i32, policy),
        \\    }, struct {});
        \\}
        \\
    );
    try suite.expectFailureContains("withOwnedSource rejects explicit continuations with trailing arguments", &argv, null, "shift.withOwnedSource explicit source witnesses must stay within the retained compiled lexical subset");

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
        \\const shift = @import("shift");
        \\
        \\pub fn body(_: anytype) anyerror!i32 {
        \\    return 1;
        \\}
        \\
        \\pub fn main() void {
        \\    _ = shift.NamedBody(@src().file, "wrongBody", anyerror!i32, &body);
        \\}
        \\
    );
    try suite.expectFailureContains("NamedBody rejects mismatched entry_symbol", &argv, null, "shift.NamedBody entry_symbol must match the supplied body function name");

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("helpers.zig",
        \\pub fn body(_: anytype) anyerror!i32 {
        \\    return 2;
        \\}
        \\
    );
    try suite.writeFile("main.zig",
        \\const helpers = @import("helpers.zig");
        \\const shift = @import("shift");
        \\
        \\pub fn body(_: anytype) anyerror!i32 {
        \\    return 1;
        \\}
        \\
        \\pub fn main() void {
        \\    _ = shift.NamedBody(@src().file, "body", anyerror!i32, &helpers.body);
        \\}
        \\
    );
    try suite.expectFailureContains("NamedBody rejects helper function provenance drift", &argv, null, "shift.NamedBody source_path must match the supplied body function provenance");

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("x/a/helpers.zig",
        \\pub fn body(_: anytype) anyerror!i32 {
        \\    return 2;
        \\}
        \\
    );
    try suite.writeFile("main.zig",
        \\const helpers = @import("x/a/helpers.zig");
        \\const shift = @import("shift");
        \\
        \\pub fn main() void {
        \\    _ = shift.NamedBody("totally/fake/a/helpers.zig", "body", anyerror!i32, &helpers.body);
        \\}
        \\
    );
    try suite.expectFailureContains("NamedBody rejects suffix-only external source_path matches", &argv, null, "shift.NamedBody source_path must match the supplied body function provenance");

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("body.zig",
        \\pub fn forged(eff: anytype) anyerror!i32 {
        \\    const before = try eff.state.get();
        \\    try eff.state.set(before + 20);
        \\    return try eff.state.get();
        \\}
        \\
    );
    try suite.writeFile("main.zig",
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
        \\    const result = try shift.withOwnedSource(@src(), @embedFile(@src().file), .{
        \\        .source_path = "body.zig",
        \\        .entry_symbol = "forged",
        \\    }, &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, named);
        \\    if (result.value != 1) return error.UnexpectedResult;
        \\    if (result.outputs.state != 1) return error.UnexpectedState;
        \\}
        \\
    );
    try suite.expectSuccess("explicit witness disagreement cannot override repo-owned NamedBody", &argv, null);

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("forged.zig",
        \\pub fn body(eff: anytype) anyerror!i32 {
        \\    const before = try eff.state.get();
        \\    try eff.state.set(before + 20);
        \\    return try eff.state.get();
        \\}
        \\
    );
    try suite.writeFile("body.zig",
        \\pub fn body(eff: anytype) anyerror!i32 {
        \\    const before = try eff.state.get();
        \\    try eff.state.set(before + 1);
        \\    return try eff.state.get();
        \\}
        \\
    );
    try suite.writeFile("main.zig",
        \\const body_file = @import("body.zig");
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    const named = shift.NamedBody("body.zig", "body", anyerror!i32, body_file.body);
        \\    const result = try shift.withOwnedSource(@src(), @embedFile("forged.zig"), .{}, &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, named);
        \\    if (result.value != 1) return error.UnexpectedResult;
        \\    if (result.outputs.state != 1) return error.UnexpectedState;
        \\}
        \\
    );
    try suite.expectSuccess("withOwnedSource keeps downstream NamedBody identity", &argv, null);

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("body.zig",
        \\pub fn forged() void {}
        \\
    );
    try suite.writeFile("main.zig",
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    _ = try shift.withOwnedSource(@src(), @embedFile(@src().file), .{
        \\        .source_path = "body.zig",
        \\    }, &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, struct {
        \\        pub fn body(eff: anytype) anyerror!i32 {
        \\            const before = try eff.state.get();
        \\            try eff.state.set(before + 1);
        \\            return try eff.state.get();
        \\        }
        \\    });
        \\}
        \\
    );
    try suite.expectFailureContains("withOwnedSource rejects mismatched explicit body-source witnesses", &argv, null, "shift.withOwnedSource anonymous and body-source witnesses require witness.source_path to agree with the caller source");

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    _ = try shift.withOwnedSource(@src(), @embedFile(@src().file), .{}, &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, struct {
        \\        pub const source_path = "body.zig";
        \\        pub fn body(eff: anytype) anyerror!i32 {
        \\            const before = try eff.state.get();
        \\            try eff.state.set(before + 1);
        \\            return try eff.state.get();
        \\        }
        \\    });
        \\}
        \\
    );
    try suite.expectFailureContains("withOwnedSource anonymous bodies reject source_path declarations", &argv, null, "shift.withOwnedSource anonymous bodies must not declare source_path; use witness.source_path or shift.NamedBody(...)");

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("main.zig",
        \\const shift = @import("shift");
        \\const std = @import("std");
        \\
        \\pub fn main() !void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    _ = try shift.withOwnedSource(@src(), @embedFile(@src().file), .{}, &runtime, .{
        \\        .state = shift.effect.state.use(@as(i32, 0)),
        \\    }, struct {
        \\        pub const entry_symbol = "forged";
        \\        pub fn body(eff: anytype) anyerror!i32 {
        \\            const before = try eff.state.get();
        \\            try eff.state.set(before + 1);
        \\            return try eff.state.get();
        \\        }
        \\    });
        \\}
        \\
    );
    try suite.expectFailureContains("withOwnedSource anonymous bodies reject entry_symbol declarations", &argv, null, "shift.withOwnedSource anonymous bodies must not declare entry_symbol; use witness.entry_symbol/body_method_name or shift.NamedBody(...)");

    try writeConsumerExecutableBuild(suite.tmp.dir, "shift");
    try suite.writeFile("nested/main.zig",
        \\pub fn body(_: anytype) anyerror!i32 {
        \\    return 2;
        \\}
        \\
    );
    try suite.writeFile("main.zig",
        \\const nested = @import("nested/main.zig");
        \\const shift = @import("shift");
        \\
        \\pub fn body(_: anytype) anyerror!i32 {
        \\    return 1;
        \\}
        \\
        \\pub fn main() void {
        \\    _ = shift.NamedBody("main.zig", "body", anyerror!i32, &nested.body);
        \\}
        \\
    );
    try suite.expectFailureContains("NamedBody keeps nested module provenance distinct", &argv, null, "shift.NamedBody source_path must match the supplied body function provenance");
}
